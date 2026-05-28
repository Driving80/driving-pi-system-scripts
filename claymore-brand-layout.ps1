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
    [string]$LogPath          = (Join-Path $env:TEMP "claymore-brand-layout.log"),
    [string]$ModeFlagPath     = (Join-Path $env:TEMP "claymore-mode.flag"),
    [string]$ApiKeyPath       = (Join-Path $env:USERPROFILE ".claymore-api-key.txt"),
    [int]$ListenerPort        = 8765,
    [int]$WatchdogIntervalSec = 1,
    [int]$RetryCount          = 3,
    [int]$RetryDelaySec       = 2
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

function Get-ClaymoreMode {
    # Legge il file flag $ModeFlagPath e ritorna il mode corrente.
    # Mode validi: "brand" | "off". Qualsiasi altro contenuto = "brand" (safe default).
    # File assente = "brand" (default).
    if (Test-Path $script:ModeFlagPath) {
        try {
            $content = (Get-Content -Path $script:ModeFlagPath -Raw -ErrorAction Stop).Trim().ToLowerInvariant()
            if ($content -eq "off") { return "off" }
            return "brand"
        } catch {
            return "brand"
        }
    }
    return "brand"
}

function Set-DeviceBrandColors {
    param(
        [Parameter(Mandatory=$true)]$Device,
        [string]$Mode = "brand"
    )

    if ($Mode -eq "off") {
        # Mode off: tutti i 182 Lights a (0,0,0) + tutti i Keys a (0,0,0).
        # Apply ancora richiesto per propagare al firmware.
        for ($i = 0; $i -lt $Device.Lights.Count; $i++) {
            $Device.Lights[$i].Red   = 0
            $Device.Lights[$i].Green = 0
            $Device.Lights[$i].Blue  = 0
        }
        for ($i = 0; $i -lt $Device.Keys.Count; $i++) {
            $Device.Keys[$i].Red   = 0
            $Device.Keys[$i].Green = 0
            $Device.Keys[$i].Blue  = 0
        }
        $Device.Apply()
        return
    }

    # Mode brand (default):
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

function Get-ApiKey {
    # Legge la API key dal file. Required - se assente, daemon fallisce safe.
    if (-not (Test-Path $script:ApiKeyPath)) {
        Write-Log "ERROR" "API key file not found: $script:ApiKeyPath"
        return $null
    }
    try {
        return (Get-Content -Path $script:ApiKeyPath -Raw -ErrorAction Stop).Trim()
    } catch {
        Write-Log "ERROR" "Failed to read API key: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-DPMSOff {
    # PostMessage SC_MONITORPOWER off (HWND_BROADCAST). Asincrono, no caller block.
    if (-not ("Display" -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Display {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@
    }
    # HWND_BROADCAST=0xFFFF, WM_SYSCOMMAND=0x0112, SC_MONITORPOWER=0xF170, off=2
    [void][Display]::PostMessage([IntPtr]0xFFFF, 0x0112, [IntPtr]0xF170, [IntPtr]2)
}

function Invoke-MouseJiggle {
    # Wake display da SC_MONITORPOWER off. SetCursorPos NON basta: sposta solo il
    # cursore senza generare un evento input HID, quindi Windows spesso non
    # risveglia il monitor. mouse_event(MOUSEEVENTF_MOVE) inietta vero input HID.
    if (-not ("Mouse" -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Mouse {
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
}
"@
    }
    # MOUSEEVENTF_MOVE = 0x0001 (movimento relativo = input HID reale)
    for ($i = 0; $i -lt 5; $i++) {
        [Mouse]::mouse_event(0x0001, 0, 8, 0, 0)
        Start-Sleep -Milliseconds 40
        [Mouse]::mouse_event(0x0001, 0, -8, 0, 0)
        Start-Sleep -Milliseconds 40
    }
    # fallback: jiggle assoluto
    $pt = New-Object Mouse+POINT
    [void][Mouse]::GetCursorPos([ref]$pt)
    [void][Mouse]::SetCursorPos($pt.X + 1, $pt.Y)
    Start-Sleep -Milliseconds 30
    [void][Mouse]::SetCursorPos($pt.X, $pt.Y)
}

function Write-HttpResponse {
    param($Response, [int]$Status, [string]$Body, [string]$ContentType = "application/json")
    $Response.StatusCode = $Status
    $Response.ContentType = $ContentType
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.ContentLength64 = $bytes.Length
    try {
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {}
    $Response.Close()
}

function Invoke-RequestHandler {
    param(
        $Context,
        $SdkState,
        [string]$ApiKey,
        [ref]$CurrentMode
    )
    $req  = $Context.Request
    $resp = $Context.Response

    # Auth: Bearer token in Authorization header
    $authHdr = $req.Headers["Authorization"]
    if (-not $authHdr -or $authHdr -ne "Bearer $ApiKey") {
        Write-Log "WARN" "401 unauthorized from $($req.RemoteEndPoint) on $($req.HttpMethod) $($req.Url.AbsolutePath)"
        Write-HttpResponse -Response $resp -Status 401 -Body '{"error":"unauthorized"}'
        return
    }

    $method = $req.HttpMethod
    $path   = $req.Url.AbsolutePath.TrimEnd('/')
    $start  = Get-Date

    if ($method -eq "POST" -and $path -eq "/screen/off") {
        try {
            foreach ($d in $SdkState.Devices) { Set-DeviceBrandColors -Device $d -Mode "off" }
            Invoke-DPMSOff
            $CurrentMode.Value = "off"
            try { Set-Content -Path $script:ModeFlagPath -Value "off" -NoNewline -Encoding ASCII -ErrorAction Stop } catch {}
            $elapsed = [int]((Get-Date) - $start).TotalMilliseconds
            Write-Log "INFO" "POST /screen/off OK (${elapsed}ms)"
            Write-HttpResponse -Response $resp -Status 200 -Body "{`"mode`":`"off`",`"elapsed_ms`":$elapsed}"
        } catch {
            Write-Log "ERROR" "POST /screen/off failed: $($_.Exception.Message)"
            Write-HttpResponse -Response $resp -Status 500 -Body '{"error":"apply failed"}'
        }
    } elseif ($method -eq "POST" -and $path -eq "/screen/on") {
        try {
            Invoke-MouseJiggle
            foreach ($d in $SdkState.Devices) { Set-DeviceBrandColors -Device $d -Mode "brand" }
            $CurrentMode.Value = "brand"
            try { Set-Content -Path $script:ModeFlagPath -Value "brand" -NoNewline -Encoding ASCII -ErrorAction Stop } catch {}
            $elapsed = [int]((Get-Date) - $start).TotalMilliseconds
            Write-Log "INFO" "POST /screen/on OK (${elapsed}ms)"
            Write-HttpResponse -Response $resp -Status 200 -Body "{`"mode`":`"brand`",`"elapsed_ms`":$elapsed}"
        } catch {
            Write-Log "ERROR" "POST /screen/on failed: $($_.Exception.Message)"
            Write-HttpResponse -Response $resp -Status 500 -Body '{"error":"apply failed"}'
        }
    } elseif ($method -eq "GET" -and $path -eq "/status") {
        Write-HttpResponse -Response $resp -Status 200 -Body "{`"mode`":`"$($CurrentMode.Value)`"}"
    } elseif ($method -eq "GET" -and $path -eq "/health") {
        Write-HttpResponse -Response $resp -Status 200 -Body '{"status":"ok"}'
    } else {
        Write-HttpResponse -Response $resp -Status 404 -Body '{"error":"not found"}'
    }
}

function Invoke-ClaymoreBrandLayoutDaemon {
    Write-Log "INFO" "claymore-brand-layout DAEMON START (HTTP listener on :$ListenerPort, watchdog=${WatchdogIntervalSec}s)"

    # Clear stale mode flag al startup: wake-from-sleep / fresh logon ripartono
    # sempre col layout brand, anche se flag era "off" prima dello sleep.
    if (Test-Path $script:ModeFlagPath) {
        try {
            Remove-Item -Path $script:ModeFlagPath -Force -ErrorAction Stop
            Write-Log "INFO" "Stale mode flag cleared at startup (fresh brand default)"
        } catch {
            Write-Log "WARN" "Could not clear stale flag: $($_.Exception.Message)"
        }
    }

    # --- Load API key (required) ---
    $apiKey = Get-ApiKey
    if (-not $apiKey) {
        Write-Log "ERROR" "API key required. Create file at $script:ApiKeyPath with a random token. Exiting."
        exit 1
    }
    Write-Log "INFO" "API key loaded (len=$($apiKey.Length))"

    # --- Acquire SDK iniziale ---
    $sdkState = Initialize-SdkAndDevices
    if ($null -eq $sdkState) {
        Write-Log "ERROR" "Initial SDK acquire failed. Exiting."
        exit 1
    }

    # --- Initial Apply (brand layout) ---
    $currentMode = "brand"
    foreach ($device in $sdkState.Devices) {
        Set-DeviceBrandColors -Device $device -Mode $currentMode
    }
    Write-Log "INFO" "Initial Apply OK (mode=$currentMode)"

    # --- Start HTTP listener ---
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://+:$ListenerPort/")
    try {
        $listener.Start()
    } catch {
        Write-Log "ERROR" "HttpListener.Start() failed: $($_.Exception.Message). URL ACL missing? Run admin: netsh http add urlacl url=http://+:$ListenerPort/ user=Everyone"
        exit 1
    }
    Write-Log "INFO" "HTTP listener started on port $ListenerPort"

    # --- Async accept loop + periodic re-Apply watchdog ---
    # Design (post 2026-05-24 fix wake-from-sleep): GetContextAsync() + Wait(timeoutMs).
    # - Wait completa: arrivata una request HTTP -> handle sync (~50ms), azzera $accept,
    #   prossimo iter crea un nuovo GetContextAsync.
    # - Wait timeout: scatta re-Apply periodico — recovery firmware reset Aura post
    #   wake-from-sleep / USB selective suspend resume. Il task GetContextAsync resta
    #   pending: NON crearne uno nuovo finche' non completa, altrimenti task abbandonati
    #   tra iter -> CLOSE_WAIT connection leak (regressione 2026-05-22 corretta).
    # WatchdogIntervalSec default 30s = max latency recovery dopo wake.
    $currentModeRef = [ref]$currentMode
    $accept = $null
    $watchdogMs = $WatchdogIntervalSec * 1000
    $wdCount = 0
    while ($true) {
        if ($null -eq $accept) {
            try {
                $accept = $listener.GetContextAsync()
            } catch {
                Write-Log "ERROR" "GetContextAsync() failed: $($_.Exception.Message)"
                Start-Sleep -Seconds 1
                continue
            }
        }
        $completed = $false
        try {
            $completed = $accept.Wait($watchdogMs)
        } catch {
            Write-Log "ERROR" "Accept Wait() raised: $($_.Exception.Message)"
            $accept = $null
            Start-Sleep -Seconds 1
            continue
        }
        if ($completed) {
            try {
                $context = $accept.Result
                try {
                    Invoke-RequestHandler -Context $context -SdkState $sdkState -ApiKey $apiKey -CurrentMode $currentModeRef
                } catch {
                    Write-Log "ERROR" "Request handler failed: $($_.Exception.Message)"
                    try { $context.Response.Close() } catch {}
                }
            } catch {
                Write-Log "ERROR" "Accept.Result unwrap failed: $($_.Exception.Message)"
            }
            $accept = $null
        } else {
            $wdCount++
            try {
                foreach ($device in $sdkState.Devices) {
                    Set-DeviceBrandColors -Device $device -Mode $currentModeRef.Value
                }
                if (($wdCount -eq 1) -or (($wdCount % 60) -eq 0)) {
                    Write-Log "INFO" "Watchdog re-apply #$wdCount (mode=$($currentModeRef.Value))"
                }
            } catch {
                Write-Log "WARN" "Watchdog re-apply #$wdCount failed: $($_.Exception.Message). Re-acquiring SDK..."
                $sdkState = Initialize-SdkAndDevices
                if ($null -eq $sdkState) {
                    Write-Log "ERROR" "SDK re-acquire fallito; ritento al prossimo timeout."
                } else {
                    Write-Log "INFO" "SDK re-acquired."
                }
            }
        }
    }
}

# Esegui solo se invocato come script, non se dot-sourced dai test
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ClaymoreBrandLayoutDaemon
}
