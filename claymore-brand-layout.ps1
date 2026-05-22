# claymore-brand-layout.ps1 - Long-running daemon che mantiene il brand layout
# drivingtech sulla Claymore II.
#
# Architettura daemon (post 2026-05-22 discovery):
#   - Acquisisce SDK control + SwitchMode + Apply iniziale UNA VOLTA
#   - Entra in loop infinito: sleep N sec, re-Apply idempotente, ripeti
#   - MAI chiama ReleaseControl (chiamarlo resetterebbe LED a default Armoury Crate)
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
    [string]$KeymapPath = (Join-Path $PSScriptRoot "claymore-brand-keymap.json"),
    [string]$LogPath    = (Join-Path $env:TEMP "claymore-brand-layout.log"),
    [int]$ReapplyIntervalSec = 10,
    [int]$RetryCount    = 3,
    [int]$RetryDelaySec = 2
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "claymore-brand-colors.ps1")
. (Join-Path $PSScriptRoot "claymore-keymap-loader.ps1")

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch {}
    Write-Host $line
}

function Set-DeviceColors {
    param(
        [Parameter(Mandatory=$true)]$Device,
        [Parameter(Mandatory=$true)]$Keymap
    )

    for ($i = 0; $i -lt $Device.Lights.Count; $i++) {
        $family = Get-LedFamily -Keymap $Keymap -LedIndex $i
        $c = Get-ClaymoreBrandColor $family
        $Device.Lights[$i].Red   = $c.R
        $Device.Lights[$i].Green = $c.G
        $Device.Lights[$i].Blue  = $c.B
    }
    $Device.Apply()
}

function Initialize-SdkAndDevices {
    # Acquisisce SDK + control + switch a mode Direct.
    # Ritorna PSCustomObject { Sdk; Devices } se OK, $null se fallisce dopo retry.

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
    Write-Log "INFO" "claymore-brand-layout DAEMON START (keymap=$KeymapPath interval=${ReapplyIntervalSec}s)"

    if (-not (Test-Path $KeymapPath)) {
        Write-Log "ERROR" "Keymap not found: $KeymapPath"
        exit 2
    }
    $keymap = Import-ClaymoreKeymap -Path $KeymapPath
    Write-Log "INFO" "Keymap loaded: device=$($keymap.device) version=$($keymap.version) total_leds=$($keymap.leds.Count)"

    # --- Acquire iniziale ---
    $sdkState = Initialize-SdkAndDevices
    if ($null -eq $sdkState) {
        Write-Log "ERROR" "Initial SDK acquire failed. Exiting."
        exit 1
    }

    # --- Loop forever ---
    # MAI chiamare ReleaseControl. SDK rilascia auto alla terminazione del processo.
    # Re-apply idempotente ogni ReapplyIntervalSec secondi: ricopre il caso wake-from-sleep
    # dove Aura Service prende temporaneamente il sopravvento.
    # Log limitato (primo apply + ogni 60 iterazioni ~= 10min con interval 10s) per non spammare.

    $iter = 0
    while ($true) {
        $iter++
        try {
            foreach ($device in $sdkState.Devices) {
                Set-DeviceColors -Device $device -Keymap $keymap
            }
            if ($iter -eq 1 -or ($iter % 60) -eq 0) {
                Write-Log "INFO" "Apply iteration #$iter OK"
            }
        } catch {
            Write-Log "WARN" "Apply iteration #$iter failed: $($_.Exception.Message). Re-acquiring SDK..."
            # Re-acquire dopo errore (wake-from-sleep, disconnect/reconnect, ecc)
            Start-Sleep -Seconds $RetryDelaySec
            $sdkState = Initialize-SdkAndDevices
            if ($null -eq $sdkState) {
                Write-Log "WARN" "Re-acquire fallito iter #$iter. Aspetto poi riprovo nel prossimo loop."
            } else {
                Write-Log "INFO" "SDK re-acquired."
            }
        }
        Start-Sleep -Seconds $ReapplyIntervalSec
    }
    # Unreachable (loop infinito). SDK rilasciato dal kernel su exit processo.
}

# Esegui solo se invocato come script, non se dot-sourced dai test
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ClaymoreBrandLayoutDaemon
}
