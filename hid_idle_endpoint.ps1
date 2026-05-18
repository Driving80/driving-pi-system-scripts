# hid_idle_endpoint.ps1 — Sleep Policy Enforcement (Phase 0.a, ADR 34)
#
# HTTP endpoint locale che espone GetLastInputInfo() (HID idle ms) al bot Pi.
# Il bot Pi consulta GET http://workstation:5007/idle-ms per il pre-sleep
# check ibrido (l'utente NON sta usando mouse/tastiera da X min).
#
# Esempio risposta:
#   { "idle_ms": 7234521, "ts": "2026-05-18T22:30:00Z" }
#
# Lifecycle: install as NSSM service "ws-hid-idle" autostart su WS, expose :5007.
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

param(
    [int]   $Port    = 5007,
    [string]$LogPath = (Join-Path $env:TEMP "hid_idle_endpoint.log")
)

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch {}
    try { Write-Host $line } catch {}
}

# P/Invoke GetLastInputInfo (user32.dll)
$sig = @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct LASTINPUTINFO {
    public uint cbSize;
    public uint dwTime;
}

public class IdleProbe {
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    public static extern uint GetTickCount();

    public static long IdleMs() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) {
            return -1;
        }
        return (long)GetTickCount() - (long)lii.dwTime;
    }
}
"@
if (-not ("IdleProbe" -as [type])) {
    Add-Type -TypeDefinition $sig -ErrorAction Stop
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:${Port}/")
try {
    $listener.Start()
    Write-Log "INFO" "hid_idle_endpoint listening on :$Port"
}
catch {
    Write-Log "ERROR" ("listener start failed: " + $_.Exception.Message)
    throw
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $resp = $ctx.Response
        try {
            $idle = [IdleProbe]::IdleMs()
            $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            $body = '{"idle_ms":' + $idle + ',"ts":"' + $ts + '"}'
            $resp.StatusCode = 200
            $resp.ContentType = "application/json"
            $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
            $resp.ContentLength64 = $buf.Length
            $resp.OutputStream.Write($buf, 0, $buf.Length)
        }
        catch {
            Write-Log "WARN" ("request handler error: " + $_.Exception.Message)
            $resp.StatusCode = 500
        }
        finally {
            try { $resp.Close() } catch {}
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
    Write-Log "INFO" "hid_idle_endpoint stopped"
}
