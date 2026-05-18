# restore_audio_pipeline.ps1 -- One-click recovery for Windows -> Pi audio pipeline.
#
# Use when:
#   - Music does not come out of HiFi speakers
#   - Heartbeat /status shows windows_online=true and gstreamer_active=true
#     but no audio reaches the Pi
#   - VB-Audio Cable devices appear in mmsys.cpl but applications cannot
#     open them (Could not open resource for reading)
#
# What it does:
#   1. Stop StreamToPI scheduled task (and orphan gst-launch / wrappers)
#   2. Restart AudioEndpointBuilder service (resets Windows audio stack)
#   3. Verify VB-Audio Cable Output is present
#   4. Set CABLE Input as default playback (if AudioDeviceCmdlets is installed)
#   5. Restart StreamToPI scheduled task
#   6. Verify gst-launch is running
#
# Requires Administrator (for Restart-Service AudioEndpointBuilder).
#
# Pin this script (via the Restore Audio Pipeline.lnk shortcut on the Desktop)
# to the taskbar for one-click recovery.

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

$TaskName       = "StreamToPI"
$CableOutputId  = "{0.0.1.00000000}.{c78dc72e-bdf4-48cf-997a-276af77fbd97}"
$CableInputName = "CABLE Input (VB-Audio Virtual Cable)"

function Section($title) {
    Write-Host ""
    Write-Host "==> $title" -ForegroundColor Cyan
}

function OK($msg)   { Write-Host "    [OK]   $msg" -ForegroundColor Green }
function INFO($msg) { Write-Host "    [..]   $msg" -ForegroundColor Gray  }
function WARN($msg) { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function FAIL($msg) { Write-Host "    [FAIL] $msg" -ForegroundColor Red   }

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Restore audio pipeline -- Windows -> Pi (GStreamer RTP)        " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ---- 1. Stop task and orphans ------------------------------------------------
Section "1/6  Stopping StreamToPI task and orphan processes"

try {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    OK "Stop-ScheduledTask sent"
} catch {
    INFO "Task was not running"
}

$killed = 0
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "stream_to_pi" } |
    ForEach-Object {
        try {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
            $killed++
        } catch {}
    }
Get-Process gst-launch-1.0 -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $killed++ } catch {}
}
OK "Killed $killed orphan process(es)"

Start-Sleep -Seconds 1

# ---- 2. Restart audio services ----------------------------------------------
Section "2/6  Restarting AudioEndpointBuilder (and Audiosrv via dependency)"

try {
    Restart-Service -Name AudioEndpointBuilder -Force -ErrorAction Stop
    OK "AudioEndpointBuilder restarted"
} catch {
    FAIL "Could not restart AudioEndpointBuilder: $($_.Exception.Message)"
    FAIL "Are you running this as Administrator?"
    exit 1
}

Start-Sleep -Seconds 3

# ---- 3. Verify VB-Audio Cable presence --------------------------------------
Section "3/6  Verifying VB-Audio Cable Output device"

$cable = Get-PnpDevice -Class AudioEndpoint -Status OK -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -like "CABLE Output*" }

if (-not $cable) {
    FAIL "CABLE Output not found among active audio endpoints"
    FAIL "Check the VB-Audio Virtual Cable driver in Device Manager"
    exit 1
}
OK "Found: $($cable.FriendlyName)"

# ---- 4. Optional: set CABLE Input as default playback -----------------------
Section "4/6  Ensuring CABLE Input is default playback"

$haveCmdlets = $false
if (Get-Module -ListAvailable -Name AudioDeviceCmdlets -ErrorAction SilentlyContinue) {
    $haveCmdlets = $true
}

if ($haveCmdlets) {
    try {
        Import-Module AudioDeviceCmdlets -ErrorAction Stop
        $target = Get-AudioDevice -List | Where-Object { $_.Name -like "*CABLE Input*" -and $_.Type -eq "Playback" }
        if ($target) {
            Set-AudioDevice -Index $target.Index | Out-Null
            OK "Default playback set to: $($target.Name)"
        } else {
            WARN "CABLE Input playback device not found via cmdlet"
        }
    } catch {
        WARN "AudioDeviceCmdlets call failed: $($_.Exception.Message)"
    }
} else {
    INFO "AudioDeviceCmdlets module not installed -- skipping automatic default switch"
    INFO "To install: Install-Module -Name AudioDeviceCmdlets -Scope CurrentUser"
    INFO "Set default manually in mmsys.cpl -> Playback -> $CableInputName"
}

# ---- 5. Start task ----------------------------------------------------------
Section "5/6  Starting StreamToPI task"

try {
    Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    OK "Start-ScheduledTask sent"
} catch {
    FAIL "Could not start task: $($_.Exception.Message)"
    exit 1
}

Start-Sleep -Seconds 5

# ---- 6. Verify gst-launch is running ----------------------------------------
Section "6/6  Verifying gst-launch is running"

$gst = Get-Process gst-launch-1.0 -ErrorAction SilentlyContinue
if ($gst) {
    OK "gst-launch-1.0 active (PID $($gst.Id))"
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host " Pipeline restored. Play music in apps targeting CABLE Input.   " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    exit 0
} else {
    FAIL "gst-launch-1.0 is NOT running after task start"
    FAIL "Check log: $env:LOCALAPPDATA\driving-pi\stream_to_pi.log"
    Write-Host ""
    Write-Host "Press any key to close..." -ForegroundColor Yellow
    [void][System.Console]::ReadKey($true)
    exit 1
}
