# install_hid_idle_endpoint_service.ps1
# Installa hid_idle_endpoint.ps1 come servizio NSSM "ws-hid-idle" (Phase 0.a, ADR 34).
#
# REQUISITI:
#   - Eseguire da PowerShell ELEVATED (admin)
#   - nssm.exe disponibile (WinGet Links o installato manualmente)
#
# DEPLOY ATTESO:
#   - Servizio Windows "ws-hid-idle" autostart
#   - Listener HTTP su porta 5007
#   - Log: %ProgramData%\ws-hid-idle\service.log (rotato da NSSM)
#
# VERIFICA POST-INSTALL:
#   Get-Service ws-hid-idle
#   Invoke-RestMethod http://localhost:5007/idle-ms

#Requires -RunAsAdministrator

param(
    [string]$ServiceName  = "ws-hid-idle",
    [string]$ScriptPath   = "$PSScriptRoot\hid_idle_endpoint.ps1",
    [int]   $Port         = 5007,
    [string]$LogDir       = "$env:ProgramData\ws-hid-idle"
)

$ErrorActionPreference = "Stop"

function Find-Nssm {
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\nssm.exe",
        "$env:ProgramFiles\nssm\nssm.exe",
        "$env:ProgramFiles(x86)\nssm\nssm.exe"
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    $gc = Get-Command "nssm.exe" -ErrorAction SilentlyContinue
    if ($gc) { return $gc.Path }
    throw "nssm.exe non trovato. Installa via: winget install NSSM.NSSM"
}

$nssm = Find-Nssm
Write-Host "Using NSSM: $nssm" -ForegroundColor Cyan

if (-not (Test-Path $ScriptPath)) {
    throw "Script non trovato: $ScriptPath"
}

# Determina powershell.exe da usare. Prefer pwsh.exe (7+) REAL path (NOT
# WindowsApps alias che fallisce in LocalSystem context), fallback a
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

# Prepara dir log
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Stop + rimuovi servizio esistente se presente (idempotenza).
# Importante: nssm scrive avvisi su stderr quando il servizio e' gia' stopped;
# con $ErrorActionPreference="Stop" questi avvisi terminano lo script.
# Cattura via try/catch + redirect stderr a $null per essere robusti.
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Stopping existing service $ServiceName..." -ForegroundColor Yellow
    try { & $nssm stop $ServiceName 2>$null | Out-Null } catch {}
    Start-Sleep -Seconds 2
    Write-Host "Removing existing service $ServiceName..." -ForegroundColor Yellow
    try { & $nssm remove $ServiceName confirm 2>$null | Out-Null } catch {}
    Start-Sleep -Seconds 1
}

# Install
Write-Host "Installing service $ServiceName..." -ForegroundColor Green
$psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Port $Port"
& $nssm install $ServiceName $powershell $psArgs 2>&1 | Out-Null
& $nssm set $ServiceName AppDirectory (Split-Path $ScriptPath -Parent) 2>&1 | Out-Null
& $nssm set $ServiceName DisplayName "WS HID Idle Endpoint (Sleep Policy ADR 34)" 2>&1 | Out-Null
& $nssm set $ServiceName Description "Espone GET :$Port/idle-ms con GetLastInputInfo() per pre-sleep check Pi" 2>&1 | Out-Null
& $nssm set $ServiceName Start SERVICE_AUTO_START 2>&1 | Out-Null

# Restart on crash (NSSM default: throttle 1500 ms tra restart, max 5 in 60s)
& $nssm set $ServiceName AppExit Default Restart 2>&1 | Out-Null
& $nssm set $ServiceName AppRestartDelay 5000 2>&1 | Out-Null

# Logging stdout/stderr a file con rotazione
& $nssm set $ServiceName AppStdout "$LogDir\stdout.log" 2>&1 | Out-Null
& $nssm set $ServiceName AppStderr "$LogDir\stderr.log" 2>&1 | Out-Null
& $nssm set $ServiceName AppRotateFiles 1 2>&1 | Out-Null
& $nssm set $ServiceName AppRotateBytes 1048576 2>&1 | Out-Null

# Run as LocalSystem (default) — per GetLastInputInfo basta. NON necessario interactive desktop.

Write-Host "Starting $ServiceName..." -ForegroundColor Green
& $nssm start $ServiceName 2>&1 | Out-Null
Start-Sleep -Seconds 3

$svc = Get-Service -Name $ServiceName
Write-Host ""
Write-Host "Status: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })

# Smoke test
try {
    $r = Invoke-RestMethod -Uri "http://localhost:$Port/idle-ms" -TimeoutSec 3 -ErrorAction Stop
    Write-Host "Smoke test: idle_ms=$($r.idle_ms) ts=$($r.ts)" -ForegroundColor Green
}
catch {
    Write-Host "Smoke test FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check $LogDir\stderr.log" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host "Service:  $ServiceName (autostart)"
Write-Host "URL:      http://localhost:$Port/idle-ms"
Write-Host "Logs:     $LogDir\{stdout,stderr}.log"
Write-Host "Uninstall: & '$nssm' stop $ServiceName; & '$nssm' remove $ServiceName confirm"
