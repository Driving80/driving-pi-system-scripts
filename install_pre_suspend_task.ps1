# install_pre_suspend_task.ps1
# Installa Scheduled Task "Pre Suspend Notify" su trigger Power-Troubleshooter
# event (Phase 0.a, ADR 34).
#
# Quando il sistema sta per entrare in S3 sleep, Windows registra eventi sul
# System log:
#   - Kernel-Power ID 506 (System has resumed from sleep) → NON useful here
#   - Kernel-Power ID 42  (System is entering sleep)      → use this
#   - Power-Troubleshooter ID 1 (System resumed)          → NON useful here
#
# Lo Scheduled Task si triggera su Kernel-Power ID 42 (event subscription XML)
# e invoca pre_suspend_notify.ps1, che fa POST /state/ws/declare al monitor Pi.
#
# REQUISITI:
#   - Eseguire da PowerShell ELEVATED (admin)
#
# VERIFICA POST-INSTALL:
#   Get-ScheduledTask -TaskName "Pre Suspend Notify"
#   # Forzare manualmente lo sleep: rundll32.exe powrprof.dll,SetSuspendState 0,1,0
#   # Verifica log: Get-Content $env:TEMP\pre_suspend_notify.log -Tail 5

#Requires -RunAsAdministrator

param(
    [string]$TaskName   = "Pre Suspend Notify",
    [string]$ScriptPath = "$PSScriptRoot\pre_suspend_notify.ps1"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ScriptPath)) {
    throw "Script non trovato: $ScriptPath"
}

# Determina PowerShell host. Prefer pwsh.exe (7+) REAL path (NOT
# WindowsApps alias che non funziona in SYSTEM principal), fallback a
# Windows PowerShell 5.1 classico in System32.
function Get-RealPowerShell {
    $candidates = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\6\pwsh.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
}
$powershell = Get-RealPowerShell
Write-Host "Using PowerShell: $powershell" -ForegroundColor Cyan

# Rimuovi task esistente (idempotenza)
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing task $TaskName..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Trigger: System log, Provider 'Microsoft-Windows-Kernel-Power', EventID 42
# (System is entering sleep). Event subscription XML.
$queryXml = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=42]]</Select>
  </Query>
</QueryList>
"@

$class = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
$trigger = New-CimInstance -CimClass $class -ClientOnly
$trigger.Enabled    = $true
$trigger.Subscription = $queryXml

# Action: invoca pre_suspend_notify.ps1
$action = New-ScheduledTaskAction `
    -Execute $powershell `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
    -WorkingDirectory (Split-Path $ScriptPath -Parent)

# Settings: timeout aggressivo (lo script deve terminare velocemente — Windows
# va in sleep poco dopo). MultipleInstances=IgnoreNew per non accumulare.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 10) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

# Principal: SYSTEM (per essere sicuri di poter girare anche se user logged out)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Register
Write-Host "Registering task $TaskName..." -ForegroundColor Green
Register-ScheduledTask `
    -TaskName $TaskName `
    -Trigger $trigger `
    -Action $action `
    -Settings $settings `
    -Principal $principal `
    -Description "Notifies Pi heartbeat monitor that WS is entering S3 sleep (ADR 34, Phase 0.a)" | Out-Null

$registered = Get-ScheduledTask -TaskName $TaskName
Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host "Task:    $TaskName"
Write-Host "Trigger: Kernel-Power EventID 42 (System entering sleep)"
Write-Host "Action:  $($action.Execute) $($action.Arguments)"
Write-Host "State:   $($registered.State)"
Write-Host ""
Write-Host "TEST MANUALE:"
Write-Host "  1. rundll32.exe powrprof.dll,SetSuspendState 0,1,0   # sleep WS"
Write-Host "  2. Wake con tasto o WoL"
Write-Host "  3. Get-Content `$env:TEMP\pre_suspend_notify.log -Tail 5"
Write-Host "  4. ssh driving-pi-01 'curl -s http://localhost:5006/state/ws | python3 -m json.tool'"
Write-Host "     # declared_state dovrebbe essere 'hibernating' subito dopo il wake"
