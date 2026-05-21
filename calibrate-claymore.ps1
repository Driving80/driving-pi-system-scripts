# calibrate-claymore.ps1 - Generate claymore-brand-keymap.json by interactive LED probing.
#
# Schema flat: mappa LED index (stringa) -> brand color family.
# Probiamo SOLO endpoint 0 (i 2 endpoint enumerati dalla SDK sono mirror
# dello stesso hardware fisico, vedi T0 discovery).
#
# Per ogni LED:
#   1. Spegne tutti i LED dei 2 endpoint
#   2. Accende SOLO il LED i-esimo (su entrambi gli endpoint, mirror) in MAGENTA
#   3. Chiede a Guido quale famiglia (l/c/m) assegnare
#   4. Salva mapping
#
# IMPORTANTE: eseguire ESCLUSIVAMENTE in console session interactive sulla workstation.
# NON funziona via SSH (vedi [[aura-sdk-com-direct-pattern]]).
#
# Output: scrive (o sovrascrive) claymore-brand-keymap.json nella cwd dello script.
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "claymore-brand-keymap.json"),
    [int]$StartIndex = 0,
    [int]$EndIndex = -1,  # -1 = tutti
    [switch]$Resume       # se OutputPath esiste, riprendi dal primo LED non mappato
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "claymore-brand-colors.ps1")

Write-Host "=== Claymore II LED calibration ===" -ForegroundColor Cyan
Write-Host "Output: $OutputPath"
Write-Host ""

# --- Stato esistente (per --Resume) ---
$ledMap = @{}
if ($Resume -and (Test-Path $OutputPath)) {
    Write-Host "Loading existing keymap for resume..." -ForegroundColor Yellow
    $existing = Get-Content $OutputPath -Raw | ConvertFrom-Json
    if ($existing.leds) {
        foreach ($p in $existing.leds.PSObject.Properties) {
            $ledMap[$p.Name] = $p.Value
        }
        Write-Host "  Loaded $($ledMap.Count) existing LED mappings." -ForegroundColor Green
    }
}

# --- SDK init ---
Write-Host "Acquiring Aura SDK..." -ForegroundColor Yellow
$sdk = New-Object -ComObject "Aura.Sdk"
$null = $sdk.RequireDeviceControlState(0x80000)
$devices = $sdk.Enumerate(0x80000)
$sdk.SwitchMode()
Start-Sleep -Milliseconds 300

if ($devices.Count -eq 0) {
    throw "No keyboard devices found. Is Armoury Crate running?"
}

Write-Host "Enumerated $($devices.Count) keyboard endpoint(s):" -ForegroundColor Cyan
foreach ($d in $devices) {
    Write-Host ("  Name={0}  Lights={1}  {2}x{3}" -f $d.Name, $d.Lights.Count, $d.Width, $d.Height)
}

$mag   = Get-ClaymoreBrandColor "magenta"
$lime  = Get-ClaymoreBrandColor "lime"
$black = @{ R = 0; G = 0; B = 0 }

$ledCount = $devices[0].Lights.Count
$lo = $StartIndex
$hi = if ($EndIndex -lt 0) { $ledCount - 1 } else { [Math]::Min($EndIndex, $ledCount - 1) }

Write-Host "`nCalibrating LEDs $lo..$hi (writing both endpoints in mirror)" -ForegroundColor Cyan

for ($i = $lo; $i -le $hi; $i++) {
    # Skip se gia' mappato e --Resume
    if ($Resume -and $ledMap.ContainsKey($i.ToString())) {
        continue
    }

    # Spegni tutti i LED su tutti gli endpoint
    foreach ($device in $devices) {
        for ($j = 0; $j -lt $device.Lights.Count; $j++) {
            $device.Lights[$j].Red   = $black.R
            $device.Lights[$j].Green = $black.G
            $device.Lights[$j].Blue  = $black.B
        }
    }
    # Accendi LED $i in MAGENTA su tutti gli endpoint (mirror)
    foreach ($device in $devices) {
        if ($i -lt $device.Lights.Count) {
            $device.Lights[$i].Red   = $mag.R
            $device.Lights[$i].Green = $mag.G
            $device.Lights[$i].Blue  = $mag.B
        }
    }
    foreach ($device in $devices) { $device.Apply() }

    Write-Host -NoNewline "LED[$i] - famiglia? (l=lime c=cyan m=magenta s=skip q=quit) > "
    $response = Read-Host
    $response = $response.Trim().ToLowerInvariant()

    switch ($response) {
        "l" { $ledMap[$i.ToString()] = "lime" }
        "c" { $ledMap[$i.ToString()] = "cyan" }
        "m" { $ledMap[$i.ToString()] = "magenta" }
        "s" { Write-Host "  skipped (no entry written)" -ForegroundColor DarkGray }
        "q" {
            Write-Host "Quitting at LED $i. Saving partial keymap..." -ForegroundColor Yellow
        }
        default {
            Write-Host "  invalid response, treating as skip" -ForegroundColor Red
        }
    }
    if ($response -eq "q") { break }
}

# Apply un colore "neutro" cosi' Guido vede che il device e' finito
foreach ($device in $devices) {
    for ($j = 0; $j -lt $device.Lights.Count; $j++) {
        $device.Lights[$j].Red   = $lime.R
        $device.Lights[$j].Green = $lime.G
        $device.Lights[$j].Blue  = $lime.B
    }
    $device.Apply()
}

# --- Salva JSON ---
$out = [ordered]@{
    version      = 1
    device       = "Claymore II"
    generated_by = "calibrate-claymore.ps1 ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"
    leds         = $ledMap
}
$json = $out | ConvertTo-Json -Depth 10
Set-Content -Path $OutputPath -Value $json -Encoding UTF8

Write-Host "`nKeymap saved to: $OutputPath" -ForegroundColor Green
Write-Host "Total mapped LEDs: $($ledMap.Count)"

$sdk.ReleaseControl(0)
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($sdk) | Out-Null
