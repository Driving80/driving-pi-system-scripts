# install_stream_to_pi_task.ps1 -- Idempotent (re)install of the StreamToPI scheduled task.
#
# What this does:
#   - Unregisters any existing StreamToPI task
#   - Registers it pointing to stream_to_pi.vbs in this repo folder
#   - Triggers: AtLogOn (current user) + Wake-from-sleep event
#   - Hidden execution, no console window
#   - Auto-restart up to 3 times on failure
#   - No execution time limit, allowed on battery, allowed to run elevated user task
#
# Run from PowerShell as Administrator. Re-run safe.

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$TaskName = "StreamToPI"
$VbsPath  = Join-Path $PSScriptRoot "stream_to_pi.vbs"

if (-not (Test-Path $VbsPath)) {
    Write-Host "ERROR: stream_to_pi.vbs not found at $VbsPath" -ForegroundColor Red
    exit 1
}

Write-Host "Installing scheduled task '$TaskName'..." -ForegroundColor Cyan
Write-Host "  Launcher: $VbsPath"

# 1. Remove any existing task with this name
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# 2. Action: launch the VBS via wscript.exe (hidden, no window)
$action = New-ScheduledTaskAction `
    -Execute "wscript.exe" `
    -Argument "`"$VbsPath`"" `
    -WorkingDirectory $PSScriptRoot

# 3. Triggers: at user logon + wake from sleep
$user = "$env:USERDOMAIN\$env:USERNAME"
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user

# Wake-from-sleep event trigger (Power-Troubleshooter EventID 1 = system resumed from sleep)
$wakeXml = @'
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select>
  </Query>
</QueryList>
'@
$wakeTrigger = New-CimInstance -CimClass (Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace "Root/Microsoft/Windows/TaskScheduler") -ClientOnly
$wakeTrigger.Subscription = $wakeXml
$wakeTrigger.Enabled      = $true

# 4. Settings: hidden, restart on failure, no time limit, allow battery
$settings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

# 5. Principal: run as current user, interactive
$principal = New-ScheduledTaskPrincipal `
    -UserId $user `
    -LogonType Interactive `
    -RunLevel Limited

# 6. Register
$task = New-ScheduledTask `
    -Action $action `
    -Trigger @($logonTrigger, $wakeTrigger) `
    -Settings $settings `
    -Principal $principal `
    -Description "Stream Windows audio (VB-Audio Cable Output) to Pi via GStreamer RTP. See driving-pi-system-scripts repo."

Register-ScheduledTask -TaskName $TaskName -InputObject $task | Out-Null

Write-Host ""
Write-Host "Task '$TaskName' installed successfully." -ForegroundColor Green
Write-Host "It will start automatically:" -ForegroundColor Green
Write-Host "  - When you log on" -ForegroundColor Green
Write-Host "  - When the system resumes from sleep" -ForegroundColor Green
Write-Host ""
Write-Host "To start it now (without logging out):" -ForegroundColor Cyan
Write-Host "  Start-ScheduledTask -TaskName $TaskName"
Write-Host ""
Write-Host "Logs: $env:LOCALAPPDATA\driving-pi\stream_to_pi.log"
