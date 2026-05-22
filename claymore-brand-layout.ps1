# claymore-brand-layout.ps1 - Long-running daemon che mantiene il brand layout
# drivingtech sulla Claymore II via mapping deterministic Code -> family.
#
# Architettura (post 2026-05-22 deterministic pivot):
#   - Mapping deterministic via Aura SDK .Keys collection (107 phys keys) +
#     lookup Code -> family (claymore-keys-mapping.ps1). Zero calibrazione visiva.
#   - Acquisisce SDK control + SwitchMode + Apply iniziale UNA VOLTA
#   - Entra in loop infinito: sleep N sec, re-Apply idempotente, ripeti
#   - MAI ReleaseControl (chiamarlo resetterebbe LED a default Armoury Crate)
#   - SDK rilasciato automaticamente alla terminazione del processo (logoff / kill)
#
# Eseguito da:
#   - Scheduled Task "ClaymoreBrandLayout" al logon utente + resume from sleep
#   - Manualmente da Guido (console session) per testing
#
# Per stoppare temporaneamente (es. testare altre luci via Armoury Crate):
#   schtasks /end /tn ClaymoreBrandLayout
# Per riavviare:
#   schtasks /run /tn ClaymoreBrandLayout
#
# Vincoli: console session SOLO. NON funziona via SSH/NSSM-service/VS-Code-Bash
# (sessioni non interactive). Vedi [[aura-sdk-com-direct-pattern]].
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

param(
    [string]$LogPath    = (Join-Path $env:TEMP "claymore-brand-layout.log"),
    [int]$ReapplyIntervalSec = 10,
    [int]$RetryCount    = 3,
    [int]$RetryDelaySec = 2
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "claymore-brand-colors.ps1")
. (Join-Path $PSScriptRoot "claymore-keys-mapping.ps1")

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch {}
    Write-Host $line
}

function Set-DeviceBrandColors {
    param([Parameter(Mandatory=$true)]$Device)

    # 1. Background fallback: set ALL 182 Lights[] to LIME (per LED non-mappati
    #    a Keys: edge lighting, logo, slot fantasma).
    $lime = Get-ClaymoreBrandColor "lime"
    for ($i = 0; $i -lt $Device.Lights.Count; $i++) {
        $Device.Lights[$i].Red   = $lime.R
        $Device.Lights[$i].Green = $lime.G
        $Device.Lights[$i].Blue  = $lime.B
    }

    # 2. Override per-key colors via Keys[] (107 entries) con family lookup
    #    deterministic via .Code. Set ordine importante: Keys DOPO Lights cosi'
    #    se SDK condivide buffer, l'ultimo write (Key family) vince per i tasti.
    for ($i = 0; $i -lt $Device.Keys.Count; $i++) {
        $key = $Device.Keys[$i]
        $family = Get-ClaymoreKeyFamily -Code $key.Code
        $c = Get-ClaymoreBrandColor $family
        $key.Red   = $c.R
        $key.Green = $c.G
        $key.Blue  = $c.B
    }

    $Device.Apply()
}

function Initialize-SdkAndDevices {
    $sdk = $null
    $attempt = 0
    while ($attempt -lt $RetryCount) {
        $attempt++
        try {
            $sdk = New-Object -ComObject "Aura.Sdk"
            $null = $sdk.RequireDeviceControlState(0x80000)
            break
        } catch {
            Write-Log "WARN" "SDK init failed (attempt $attempt/$RetryCount): $($_.Exception.Message)"
            if ($attempt -ge $RetryCount) {
                Write-Log "ERROR" "SDK init failed after $RetryCount attempts."
                return $null
            }
            Start-Sleep -Seconds $RetryDelaySec
        }
    }

    $devices = $sdk.Enumerate(0x80000)
    if ($devices.Count -eq 0) {
        Write-Log "WARN" "No keyboard devices enumerated."
        return $null
    }

    $sdk.SwitchMode()
    Start-Sleep -Milliseconds 200
    Write-Log "INFO" "Enumerated $($devices.Count) endpoint(s), SwitchMode OK"
    return [PSCustomObject]@{ Sdk = $sdk; Devices = $devices }
}

function Invoke-ClaymoreBrandLayoutDaemon {
    Write-Log "INFO" "claymore-brand-layout DAEMON START (interval=${ReapplyIntervalSec}s, deterministic Code->family)"

    # --- Acquire iniziale ---
    $sdkState = Initialize-SdkAndDevices
    if ($null -eq $sdkState) {
        Write-Log "ERROR" "Initial SDK acquire failed. Exiting."
        exit 1
    }

    # --- Loop forever ---
    # MAI chiamare ReleaseControl. SDK rilascia auto alla terminazione del processo.
    $iter = 0
    while ($true) {
        $iter++
        try {
            foreach ($device in $sdkState.Devices) {
                Set-DeviceBrandColors -Device $device
            }
            if ($iter -eq 1 -or ($iter % 60) -eq 0) {
                Write-Log "INFO" "Apply iteration #$iter OK"
            }
        } catch {
            Write-Log "WARN" "Apply iteration #$iter failed: $($_.Exception.Message). Re-acquiring SDK..."
            Start-Sleep -Seconds $RetryDelaySec
            $sdkState = Initialize-SdkAndDevices
            if ($null -eq $sdkState) {
                Write-Log "WARN" "Re-acquire fallito iter #$iter. Aspetto next loop."
            } else {
                Write-Log "INFO" "SDK re-acquired."
            }
        }
        Start-Sleep -Seconds $ReapplyIntervalSec
    }
}

# Esegui solo se invocato come script, non se dot-sourced dai test
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ClaymoreBrandLayoutDaemon
}
