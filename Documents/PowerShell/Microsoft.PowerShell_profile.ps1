# PowerShell 7 profile, deployed on Windows only.
#
# The default Windows shell is still cmd + Clink (see docs/windows-shell.md).
# This file exists so pwsh can be compared side by side: it reproduces the parts
# of AppData/Local/clink that have an equivalent, and deliberately leaves out the
# ones that do not (clink-completions, fzf's completion interception).

# cmd starts at the OEM codepage; pwsh 7 is UTF-8 but the console encoding is not
# guaranteed to be, and eza/starship garble Chinese output without this.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

# Prompt: the same ~/.config/starship.toml the cmd and Unix shells use.
Invoke-Expression (& starship init powershell | Out-String)

# Replaces clink's zoxide.lua: the z/zi aliases and the pwd hook.
Invoke-Expression (& { (zoxide init powershell | Out-String) })

# wezterm derives the tab title from the cwd reported over OSC 7. Clink did this
# from clink.lua's prompt filter; starship calls this hook before every prompt.
function global:Invoke-Starship-PreCommand {
  $path = $PWD.ProviderPath.Replace('\', '/').Replace(' ', '%20')
  [Console]::Write("$([char]0x1b)]7;file://$env:COMPUTERNAME/$path$([char]0x1b)\")
}

# session.lua's aliases. Only the ones that rewrite a command are here: scoop's
# uutils-coreutils already puts ls/cat/cp/rm/ln/pwd on PATH, and clear is a
# PowerShell builtin.
Set-Alias -Name vi -Value nvim -Force
Set-Alias -Name open -Value explorer -Force
Set-Alias -Name ls -Value eza -Force
# PowerShell ships gl as a read-only alias for Get-Location and an alias wins over
# a function of the same name, so it has to go before the git log one is defined.
Remove-Item -Path Alias:gl -Force
function global:gl { git log --oneline --all --graph --decorate @args }
function global:ll { eza -lh --icons @args }
function global:la { eza -lah --icons @args }
function global:lt { eza --tree --icons @args }

# cmd's `set` has no PowerShell equivalent, so the proxy helpers are functions
# over the process-level $env: variables the cmd session sets.
function global:pon {
  $env:HTTP_PROXY = 'http://127.0.0.1:7890'
  $env:HTTPS_PROXY = 'http://127.0.0.1:7890'
  $env:ALL_PROXY = 'socks5://127.0.0.1:7890'
  Write-Host '[Clash] Terminal Proxy ON (Port: 7890)'
}
function global:poff {
  $env:HTTP_PROXY = $null
  $env:HTTPS_PROXY = $null
  $env:ALL_PROXY = $null
  Write-Host '[Clash] Terminal Proxy OFF'
}
function global:pstat {
  Write-Host "HTTP:  $env:HTTP_PROXY"
  Write-Host "HTTPS: $env:HTTPS_PROXY"
  Write-Host "ALL:   $env:ALL_PROXY"
}
