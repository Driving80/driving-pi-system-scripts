# post_wake_video_off.ps1 — Sleep Policy Enforcement (Phase 0.a, ADR 34)
#
# Invocato dal bot Pi via SSH come post_wake_callback dopo che WakeHandler
# ha confermato authoritative_state='online'. Spegne display e TV LG per
# evitare di accenderli inutilmente durante un wake remoto da bot.
#
# Idempotente: se display/TV gia' off, non fa danni.
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

param(
    [string]$LGTVIPAddress = $env:LG_TV_IP,
    [string]$LGTVClientKey = $env:LG_TV_CLIENT_KEY,
    [string]$LogPath       = (Join-Path $env:TEMP "post_wake_video_off.log")
)

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch {}
}

Write-Log "INFO" "post_wake_video_off started"

# Step 1: Display Windows off via DPMS (SC_MONITORPOWER state=2 = off)
try {
    $sig = @"
using System;
using System.Runtime.InteropServices;
public class Dpms {
    [DllImport("user32.dll")]
    public static extern int SendMessage(int hWnd, int hMsg, int wParam, int lParam);
    public const int HWND_BROADCAST  = 0xFFFF;
    public const int WM_SYSCOMMAND   = 0x0112;
    public const int SC_MONITORPOWER = 0xF170;
}
"@
    if (-not ("Dpms" -as [type])) {
        Add-Type -TypeDefinition $sig -ErrorAction Stop
    }
    [Dpms]::SendMessage([Dpms]::HWND_BROADCAST, [Dpms]::WM_SYSCOMMAND, [Dpms]::SC_MONITORPOWER, 2) | Out-Null
    Write-Log "OK" "display off (DPMS)"
}
catch {
    Write-Log "WARN" ("display off failed: " + $_.Exception.Message)
}

# Step 2: LG TV off via LG TV Companion (scelta utente 2026-05-18, ADR 34).
#
# LG TV Companion (https://github.com/JPersson77/LGTVCompanion) e' installato
# come servizio Windows + UI. La discovery cerca l'eseguibile in path standard
# e tenta una sequenza di flag/argomenti noti per inviare "power off" alla TV
# pairata via webOS.
#
# Se la sintassi corretta sul setup utente differisce, eseguire una volta lo
# script di discovery dedicato `lgtv_discover.ps1` per identificare il
# comando esatto, poi aggiornare $LGTVOffCommand qui sotto.

# LG TV Companion CLI (validato 2026-05-18 su HAL9000 setup): LGTVcli.exe v5.5.0
# in 'C:\Program Files\LGTV Companion\'. Flag di power off: -powerOff.
# Esiste anche -screenOff (blank screen mantenendo network attivo) come variante
# piu' rapida da svegliare; qui usiamo -powerOff per risparmio energia massimo.
$lgtvCliCandidates = @(
    "${env:ProgramFiles}\LGTV Companion\LGTVcli.exe",
    "${env:ProgramFiles}\LG TV Companion\LGTVcli.exe",
    "${env:ProgramFiles(x86)}\LGTV Companion\LGTVcli.exe",
    "${env:ProgramFiles(x86)}\LG TV Companion\LGTVcli.exe",
    "${env:LOCALAPPDATA}\Programs\LGTV Companion\LGTVcli.exe"
)

$lgtvCli = $null
foreach ($p in $lgtvCliCandidates) {
    if ($p -and (Test-Path $p)) {
        $lgtvCli = $p
        break
    }
}
if (-not $lgtvCli) {
    $gc = Get-Command "LGTVcli.exe" -ErrorAction SilentlyContinue
    if ($gc) { $lgtvCli = $gc.Path }
}

if ($lgtvCli) {
    Write-Log "INFO" ("LGTVcli found at: " + $lgtvCli)
    try {
        $proc = Start-Process -FilePath $lgtvCli `
                              -ArgumentList "-powerOff" `
                              -WindowStyle Hidden `
                              -PassThru `
                              -Wait `
                              -ErrorAction Stop
        Write-Log "OK" ("LG TV -powerOff sent (exitCode=" + $proc.ExitCode + ")")
    }
    catch {
        Write-Log "WARN" ("LG TV -powerOff failed: " + $_.Exception.Message)
    }
}
else {
    Write-Log "WARN" "LGTVcli.exe non trovato. Display DPMS dovrebbe gia' propagare via HDMI."
}

Write-Log "INFO" "post_wake_video_off done"
