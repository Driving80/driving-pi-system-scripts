# install_claymore_brand_task.ps1 - Installa Scheduled Task "ClaymoreBrandLayout".
#
# Idempotente: se task esiste, lo elimina e ricrea con configurazione corrente.
# 2 trigger: At logon + On resume from sleep (Power-Troubleshooter ID 1).
#
# IMPORTANTE: eseguire con elevazione admin (RunAs Administrator).
# Eseguire dalla cartella del repo per risolvere correttamente $PSScriptRoot.
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

param(
    [string]$TaskName       = "ClaymoreBrandLayout",
    [string]$ScriptPath     = $null,  # se null, default a $PSScriptRoot/claymore-brand-layout.ps1
    [string]$UserName       = $env:USERNAME,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# --- Verifica elevazione admin (richiesta da schtasks /create) ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run as Administrator. Re-launch PowerShell with 'Run as administrator' and try again."
}

if (-not $ScriptPath) {
    $ScriptPath = Join-Path $PSScriptRoot "claymore-brand-layout.ps1"
}

Write-Host "=== Install ClaymoreBrandLayout scheduled task ===" -ForegroundColor Cyan
Write-Host "TaskName: $TaskName"
Write-Host "ScriptPath: $ScriptPath"
Write-Host "User: $UserName"
Write-Host ""

# --- Uninstall ---
if ($Uninstall) {
    Write-Host "Uninstalling..." -ForegroundColor Yellow
    $deleteExit = & {
        $ErrorActionPreference = "SilentlyContinue"
        schtasks /delete /tn $TaskName /f 2>$null | Out-Null
        return $LASTEXITCODE
    }
    if ($deleteExit -eq 0) {
        Write-Host "Done."
    } else {
        Write-Host "Task '$TaskName' not found (already uninstalled). Done." -ForegroundColor DarkGray
    }
    exit 0
}

# --- Verifica script esiste ---
if (-not (Test-Path $ScriptPath)) {
    throw "Script not found: $ScriptPath"
}

# --- Cleanup vecchia istanza (idempotenza) ---
# Scope EAP locale: schtasks /query stderr quando task non esiste e' atteso
# (PowerShell 7+ con ErrorActionPreference=Stop lo trattava come terminante).
$queryExit = & {
    $ErrorActionPreference = "SilentlyContinue"
    schtasks /query /tn $TaskName 2>$null | Out-Null
    return $LASTEXITCODE
}
if ($queryExit -eq 0) {
    Write-Host "Existing task found, deleting..." -ForegroundColor Yellow
    schtasks /delete /tn $TaskName /f | Out-Null
}

# --- XML definition (2 trigger) ---
$xmlPath = Join-Path $env:TEMP "$TaskName.xml"
$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) {
    $pwshExe = "powershell.exe"  # fallback PS 5.1
}

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Apply drivingtech brand layout to Claymore II at logon + wake.</Description>
    <Author>$UserName</Author>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$env:USERDOMAIN\$UserName</UserId>
    </LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT3S</Delay>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$env:USERDOMAIN\$UserName</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$pwshExe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "$ScriptPath"</Arguments>
      <WorkingDirectory>$(Split-Path -Parent $ScriptPath)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

try {
    Set-Content -Path $xmlPath -Value $xml -Encoding Unicode

    # --- Registra task ---
    Write-Host "Registering task..." -ForegroundColor Yellow
    schtasks /create /tn $TaskName /xml $xmlPath /f
    if ($LASTEXITCODE -ne 0) {
        throw "schtasks create failed with exit $LASTEXITCODE"
    }
} finally {
    # Cleanup XML temp anche su exception (disk full, schtasks fail, ecc)
    Remove-Item $xmlPath -ErrorAction SilentlyContinue
}

Write-Host "Task '$TaskName' installed. Triggers: At-logon + On-wake (Power-Troubleshooter ID 1)." -ForegroundColor Green
Write-Host "Test manual run: schtasks /run /tn $TaskName"
