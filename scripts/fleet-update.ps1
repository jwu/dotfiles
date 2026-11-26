$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$env:HTTP_PROXY = $proxy
$env:HTTPS_PROXY = $proxy
$env:ALL_PROXY = $proxy
$env:NO_PROXY = 'localhost,127.0.0.1,::1'
$env:NODE_USE_ENV_PROXY = '1'
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'http.proxy'
$env:GIT_CONFIG_VALUE_0 = $proxy

function Confirm-Native([string]$operation) {
    if ($LASTEXITCODE) { throw "$operation failed (exit $LASTEXITCODE)" }
}

curl.exe -fsSL --max-time 15 -o NUL https://registry.npmjs.org/
Confirm-Native 'Proxy probe'

function Update-Dotfiles {
    $source = (chezmoi source-path).Trim()
    Confirm-Native 'chezmoi source-path'
    $origin = (git -C $source remote get-url origin).Trim()
    Confirm-Native 'Dotfiles origin'
    if ($origin -notmatch '^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)jwu/dotfiles(\.git)?$') {
        throw 'chezmoi source does not track jwu/dotfiles'
    }
    $branch = (git -C $source branch --show-current).Trim()
    Confirm-Native 'Dotfiles branch'
    if ($branch -ne 'main') { throw 'chezmoi source is not on main' }
    git -C $source fetch https://github.com/jwu/dotfiles.git refs/heads/main:refs/remotes/origin/main
    Confirm-Native 'Dotfiles fetch'
    git -C $source merge --ff-only refs/remotes/origin/main
    Confirm-Native 'Dotfiles fast-forward'
    chezmoi diff --include=files | Out-Null
    Confirm-Native 'chezmoi diff'
    chezmoi status --include=files
    Confirm-Native 'chezmoi status'
    chezmoi apply --keep-going --error-on-conflict --no-tty
    $applyStatus = $LASTEXITCODE
    chezmoi status --include=files
    Confirm-Native 'chezmoi status after apply'
    if ($applyStatus) { throw "chezmoi apply failed (exit $applyStatus)" }
}

function Update-Pi {
    Push-Location $HOME
    try {
        pi update --all --no-approve
        Confirm-Native 'pi update'
        pi --version
        Confirm-Native 'pi version'
    } finally { Pop-Location }
}

function Update-Magpie {
    $update = Start-Process -FilePath $magpie -ArgumentList @('update','--proxy',$proxy) -NoNewWindow -Wait -PassThru
    if ($update.ExitCode) { throw "Magpie updater exited with $($update.ExitCode)" }
    $version = Start-Process -FilePath $magpie -ArgumentList '--version' -NoNewWindow -Wait -PassThru
    if ($version.ExitCode) { throw 'Could not read Magpie version' }
}

function Invoke-DesktopInstaller($installer, $temp, $identity) {
    # Run the updater with the same integrity level as the desktop daemon.
    $name = 'HerdrFleet-' + [guid]::NewGuid().ToString('N')
    $log = Join-Path $temp 'desktop-update.log'
    $result = Join-Path $temp 'desktop-update.exit'
    $corePath = $core.Replace("'", "''")
    $installerPath = $installer.Replace("'", "''")
    $logPath = $log.Replace("'", "''")
    $resultPath = $result.Replace("'", "''")
    $body = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$env:HTTP_PROXY = '$proxy'
`$env:HTTPS_PROXY = '$proxy'
`$env:ALL_PROXY = '$proxy'
`$env:NO_PROXY = 'localhost,127.0.0.1,::1'
`$env:HC_VERSION = '$($release.version)'
`$env:HC_INSTALL_DIR = Split-Path -Parent '$corePath'
`$code = 0
try {
    & ([ScriptBlock]::Create([IO.File]::ReadAllText('$installerPath'))) *> '$logPath'
    & '$corePath' server start *>> '$logPath'
    if (`$LASTEXITCODE) { throw 'Could not start Herdr Core in the desktop session' }
} catch {
    Add-Content -LiteralPath '$logPath' -Value `$_
    `$code = 1
} finally { [IO.File]::WriteAllText('$resultPath', [string]`$code) }
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    $action = New-ScheduledTaskAction -Execute (Get-Command pwsh.exe).Source -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $encoded"
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $name -Action $action -Principal $principal | Out-Null
    try {
        Start-ScheduledTask -TaskName $name
        for ($i = 0; $i -lt 240; $i++) {
            if (Test-Path -LiteralPath $result) { break }
            Start-Sleep -Seconds 1
        }
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
        if (-not (Test-Path -LiteralPath $result) -or [IO.File]::ReadAllText($result) -ne '0') { throw 'Herdr Core desktop update failed or timed out' }
    } finally {
        if ((Get-ScheduledTask -TaskName $name).State -eq 'Running' -and -not (Test-Path -LiteralPath $result)) {
            Stop-ScheduledTask -TaskName $name
        }
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
    }
}

function Update-Herdr {
    $manifest = curl.exe -fsSL --retry 2 --max-time 20 https://releases.herdr.dev/core/latest.json
    Confirm-Native 'Herdr manifest download'
    $release = ($manifest -join "`n") | ConvertFrom-Json
    if ($release.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Herdr release version' }
    $installed = (& $core --version).Trim()
    Confirm-Native 'Herdr version'
    if ($installed -eq "hc $($release.version)") { "$installed is current"; return }
    $temp = [IO.Directory]::CreateTempSubdirectory('herdr-fleet-').FullName
    try {
        $installer = Join-Path $temp 'install.ps1'
        curl.exe -fsSL --retry 2 --max-time 30 https://releases.herdr.dev/core/install.ps1 -o $installer
        Confirm-Native 'Herdr installer download'
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $desktop = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Where-Object {
            (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid).Sid -eq $identity.User.Value
        }
        if ($desktop) {
            Invoke-DesktopInstaller $installer $temp $identity
        } else {
            $env:HC_VERSION = $release.version
            $env:HC_INSTALL_DIR = Split-Path -Parent $core
            & ([ScriptBlock]::Create([IO.File]::ReadAllText($installer)))
        }
        $installed = (& $core --version).Trim()
        if ($installed -ne "hc $($release.version)") { throw "Herdr version after update: $installed" }
        $installed
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}

function Invoke-Step($name, $tool, [scriptblock]$update) {
    if (-not $tool) { $result = 'ABSENT' }
    elseif ($mode -eq 'check') { "${name}: $tool"; $result = 'READY' }
    else {
        "Updating $name"
        try { & $update; $result = 'OK' }
        catch { "${name}: $($_.Exception.Message)"; $result = 'FAILED' }
    }
    "FLEET_RESULT $name $result"
}

$magpie = (Get-Command magpie.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $magpie) {
    $magpie = @("$env:LOCALAPPDATA\Programs\Magpie\magpie.exe", "$env:ProgramFiles\Magpie\magpie.exe") |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
$core = (Get-Command herdr-core.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
Invoke-Step dotfiles (Get-Command chezmoi -ErrorAction SilentlyContinue).Source { Update-Dotfiles }
Invoke-Step pi (Get-Command pi -ErrorAction SilentlyContinue).Source { Update-Pi }
Invoke-Step magpie $magpie { Update-Magpie }
Invoke-Step herdr $core { Update-Herdr }
