# claymore-brand-layout.ps1 - Apply drivingtech brand layout sulla Claymore II.
#
# Eseguito da:
#   - Scheduled Task "ClaymoreBrandLayout" al logon utente + resume from sleep
#   - Manualmente da Guido (console session) per riapplicare dopo override Armoury Crate
#
# Vincoli: console session SOLO. Non funziona via SSH (vedi [[aura-sdk-com-direct-pattern]]).
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

param(
    [string]$KeymapPath = (Join-Path $PSScriptRoot "claymore-brand-keymap.json"),
    [string]$LogPath    = (Join-Path $env:TEMP "claymore-brand-layout.log"),
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

function Invoke-ClaymoreBrandLayout {
    Write-Log "INFO" "claymore-brand-layout START (keymap=$KeymapPath)"

    if (-not (Test-Path $KeymapPath)) {
        Write-Log "ERROR" "Keymap not found: $KeymapPath"
        exit 2
    }
    $keymap = Import-ClaymoreKeymap -Path $KeymapPath
    Write-Log "INFO" "Keymap loaded: device=$($keymap.device) version=$($keymap.version)"

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
                Write-Log "ERROR" "SDK init failed after $RetryCount attempts. Aborting."
                exit 1
            }
            Start-Sleep -Seconds $RetryDelaySec
        }
    }

    try {
        $devices = $sdk.Enumerate(0x80000)
        if ($devices.Count -eq 0) {
            Write-Log "WARN" "No keyboard devices enumerated. Maybe disconnected?"
            exit 0  # non-blocking sul logon
        }

        $sdk.SwitchMode()
        Start-Sleep -Milliseconds 200

        foreach ($device in $devices) {
            Write-Log "INFO" "Applying layout to device: $($device.Name) ($($device.Lights.Count) LEDs)"
            Set-DeviceColors -Device $device -Keymap $keymap
        }

        Write-Log "INFO" "claymore-brand-layout OK"
    } finally {
        if ($sdk) {
            try { $sdk.ReleaseControl(0) } catch {}
            try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($sdk) | Out-Null } catch {}
        }
    }
}

# Esegui solo se invocato come script, non se dot-sourced dai test
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ClaymoreBrandLayout
}
