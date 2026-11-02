# Stop the focused pane's command tree. Herdr's pwsh panes never receive a real
# Ctrl+C over SSH/ConPTY, so the pane's shell pid is the only reliable anchor.
# See docs/herdr.md.
param([string]$PaneId)
$ErrorActionPreference = "Stop"
$herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }
$json = & $herdr pane process-info --pane $PaneId | ConvertFrom-Json
$shellPid = $json.result.process_info.shell_pid
if (-not $shellPid) { Write-Output "no-shell-pid"; exit 1 }
$kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$shellPid")
if ($kids.Count -eq 0) { Write-Output "nothing-to-stop"; exit 0 }
foreach ($kid in $kids) {
  & taskkill /F /T /PID $kid.ProcessId | Out-Null
  Write-Output "killed:$($kid.ProcessId):$($kid.Name)"
}
