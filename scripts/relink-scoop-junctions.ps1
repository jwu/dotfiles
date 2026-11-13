#Requires -Version 5.1
# scoop creates apps\<name>\current from a medium-integrity session, and Windows
# refuses to traverse such a mount point from an elevated token -- which is what
# sshd hands out to Administrators. Rebuilding the junction elevated marks it
# trusted, so elevated shells can use the shims again.
#
# scoop update / scoop install re-create the junction unelevated, so re-run this
# after updating. See docs/windows-sshd.md.

$ErrorActionPreference = 'Stop'

# pi and other shells may pass PowerShell 7's PSModulePath into 5.1, which
# breaks cmdlet autoloading. Pin the 5.1 paths before using anything else.
$env:PSModulePath = 'C:\Windows\System32\WindowsPowerShell\v1.0\Modules;C:\Program Files\WindowsPowerShell\Modules'

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $false
    }
    # IsInRole is also true for the filtered token; the High IL SID is not.
    $groups = & (Join-Path $env:SystemRoot 'System32\whoami.exe') /groups 2>&1
    return ($groups -join "`n") -match 'S-1-16-12288'
}

function Get-ScoopRoot {
    if ($env:SCOOP) { $env:SCOOP } else { Join-Path $env:USERPROFILE 'scoop' }
}

function Test-Traversable([string]$Path) {
    try {
        [void](New-Object System.IO.DirectoryInfo $Path).GetFileSystemInfos()
        return $true
    } catch {
        return $false
    }
}

if (-not (Test-Elevated)) {
    Write-Host 'Rebuilding scoop junctions needs an elevated session; asking for approval...'
    Start-Process -Verb RunAs -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    exit 0
}

$appsRoot = Join-Path (Get-ScoopRoot) 'apps'
if (-not (Test-Path -LiteralPath $appsRoot)) {
    Write-Host "No scoop apps directory at $appsRoot; nothing to do."
    exit 0
}

$fixed = 0
$skipped = 0
$failed = 0

Get-ChildItem -LiteralPath $appsRoot -Directory -Force | ForEach-Object {
    $app = $_.Name
    $current = Join-Path $_.FullName 'current'

    if (-not (Test-Path -LiteralPath $current)) { return }

    $item = Get-Item -LiteralPath $current -Force
    if ($item.LinkType -ne 'Junction') { return }

    if (Test-Traversable $current) {
        $script:skipped++
        return
    }

    $target = @($item.Target)[0]
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Write-Warning "$app`: target missing ($target); skipped"
        $script:failed++
        return
    }

    try {
        # A stale ReadOnly bit makes Directory.Delete fail with access denied.
        if ($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
            $item.Attributes = [System.IO.FileAttributes]::Directory
        }
        [System.IO.Directory]::Delete($current)
        New-Item -ItemType Junction -Path $current -Target $target -ErrorAction Stop | Out-Null
        if (-not (Test-Traversable $current)) { throw 'junction still not traversable' }
        Write-Host "fixed   $app -> $(Split-Path $target -Leaf)"
        $script:fixed++
    } catch {
        Write-Warning "$app`: $($_.Exception.Message)"
        $script:failed++
    }
}

Write-Host ''
Write-Host "fixed=$fixed already-ok=$skipped failed=$failed"
if ($failed -gt 0) { exit 1 }
