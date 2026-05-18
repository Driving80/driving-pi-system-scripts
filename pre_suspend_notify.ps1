# pre_suspend_notify.ps1 — Sleep Policy Enforcement (Phase 0.a, ADR 34)
#
# Invocato da Scheduled Task con trigger "On event" sul System log:
#   - Provider: Microsoft-Windows-Power-Troubleshooter
#   - Event ID: 506 (System has resumed from sleep) -- NO, vogliamo PRIMA del sleep
#   - Event ID: 507 (System has been put to sleep)  -- corretto
#
# In alternativa, trigger su evento Kernel-Power 42 (System is entering sleep).
#
# Lo script dichiara al monitor heartbeat sul Pi che la WS sta entrando in
# sleep, accelerando la convergenza del bot Pi sullo stato 'hibernating'
# senza dover aspettare il TTL heartbeat (180s).
#
# Fire-and-forget. Timeout 1s. Se fallisce non blocca il sleep -- il TTL
# heartbeat fa convergere comunque (failsafe).
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

param(
    [string]$PiAddress  = "192.168.68.68",
    [int]   $Port       = 5006,
    [int]   $TimeoutSec = 1,
    [string]$LogPath    = (Join-Path $env:TEMP "pre_suspend_notify.log")
)

$ErrorActionPreference = "Continue"
$url  = "http://${PiAddress}:${Port}/state/ws/declare"
$body = '{"state":"hibernating","source":"pre_suspend_hook"}'

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch {}
}

try {
    $resp = Invoke-WebRequest -Uri $url `
                              -Method Post `
                              -Body $body `
                              -ContentType "application/json" `
                              -TimeoutSec $TimeoutSec `
                              -UseBasicParsing `
                              -ErrorAction Stop
    Write-Log "OK" ("declared=hibernating status=" + $resp.StatusCode)
}
catch {
    # Failsafe: se il monitor e' irraggiungibile o lento, non blocchiamo il sleep.
    Write-Log "WARN" ("declare failed: " + $_.Exception.Message)
}
