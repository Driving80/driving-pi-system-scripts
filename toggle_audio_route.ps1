# toggle_audio_route.ps1 -- Bidirectional audio route toggle: PC <-> Pi.
#
# What it does:
#   PC mode  : stops StreamToPI + Heartbeat Sender tasks, kills gst-launch,
#              sets default playback to local Focusrite speakers.
#   Pi mode  : sets default playback to CABLE Input (VB-Audio Virtual Cable),
#              starts Heartbeat Sender then StreamToPI (heartbeat monitor on Pi
#              then routes Windows audio through the GStreamer RTP pipeline).
#
# Without -Mode: toggles to the opposite of current state.
# -Mode PC or -Mode Pi: force a specific mode.
#
# Requires Administrator (Stop/Start-ScheduledTask on system tasks).
# Requires AudioDeviceCmdlets PS module (auto-installed on first run).

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('PC','Pi')]
    [string]$Mode
)

$ErrorActionPreference = 'Continue'

$StreamTask      = 'StreamToPI'
$HeartbeatTask   = 'Heartbeat Sender'
$LocalDeviceName = 'Altoparlanti (Focusrite USB Audio)'
$PiDeviceName    = 'CABLE Input (VB-Audio Virtual Cable)'
$LogDir          = Join-Path $env:LOCALAPPDATA 'driving-pi'
$LogFile         = Join-Path $LogDir 'toggle_audio_route.log'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Log([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$ts] $msg"
    Write-Host $msg
}

function Ensure-AudioCmdlets {
    if (-not (Get-Module -ListAvailable -Name AudioDeviceCmdlets)) {
        Log "Installing AudioDeviceCmdlets (CurrentUser scope)..."
        Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module AudioDeviceCmdlets -ErrorAction Stop
}

function Set-DefaultPlayback([string]$name) {
    $dev = Get-AudioDevice -List | Where-Object { $_.Type -eq 'Playback' -and $_.Name -eq $name }
    if (-not $dev) {
        Log "  [FAIL] Device '$name' not found among active playback endpoints"
        return $false
    }
    Set-AudioDevice -Index $dev.Index | Out-Null
    Log "  [OK] Default playback -> $name"
    return $true
}

function Get-CurrentMode {
    $t = Get-ScheduledTask -TaskName $StreamTask -ErrorAction SilentlyContinue
    if ($t -and $t.State -eq 'Running') { return 'Pi' }
    $gst = Get-Process gst-launch-1.0 -ErrorAction SilentlyContinue
    if ($gst) { return 'Pi' }
    return 'PC'
}

function Switch-ToPC {
    Log "==> Switching to PC mode"
    foreach ($task in @($StreamTask, $HeartbeatTask)) {
        try {
            Stop-ScheduledTask -TaskName $task -ErrorAction Stop
            Log "  [OK] Stopped task: $task"
        } catch {
            Log "  [..] $task already idle"
        }
    }
    Start-Sleep -Seconds 1
    Get-Process gst-launch-1.0 -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; Log "  [OK] Killed gst-launch PID $($_.Id)" } catch {}
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'stream_to_pi|send_heartbeat' } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; Log "  [OK] Killed orphan PID $($_.ProcessId)" } catch {}
        }
    Set-DefaultPlayback $LocalDeviceName | Out-Null
    return 'PC'
}

function Switch-ToPi {
    Log "==> Switching to Pi mode"
    Set-DefaultPlayback $PiDeviceName | Out-Null
    foreach ($task in @($HeartbeatTask, $StreamTask)) {
        try {
            Start-ScheduledTask -TaskName $task -ErrorAction Stop
            Log "  [OK] Started task: $task"
        } catch {
            Log "  [FAIL] Could not start $task : $($_.Exception.Message)"
        }
    }
    return 'Pi'
}

function Show-Notification([string]$newMode) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Information
        $ni.BalloonTipTitle = "Audio Route"
        $ni.BalloonTipText  = if ($newMode -eq 'PC') { "Audio --> PC (Focusrite local)" } else { "Audio --> Pi (HiFi via streaming)" }
        $ni.Visible = $true
        $ni.ShowBalloonTip(4000)
        Start-Sleep -Seconds 5
        $ni.Dispose()
    } catch {
        Log "  [..] Notification skipped: $($_.Exception.Message)"
    }
}

# --- Main ---
Ensure-AudioCmdlets

$current = Get-CurrentMode
Log "Current mode: $current"

if (-not $Mode) {
    $Mode = if ($current -eq 'Pi') { 'PC' } else { 'Pi' }
    Log "Toggle -> $Mode"
} else {
    Log "Forced -> $Mode"
}

if ($Mode -eq 'PC') { $final = Switch-ToPC } else { $final = Switch-ToPi }

Log "Final mode: $final"
Show-Notification $final
