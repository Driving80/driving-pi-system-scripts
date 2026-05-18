# stream_to_pi.ps1 -- Wrapper for stream_to_pi.bat with file logging and rotation.
# Designed for Task Scheduler at-logon trigger, no visible window.
#
# ASCII-only output to be safe on Windows PowerShell 5.1 (CP1252 default).
# Logs to %LOCALAPPDATA%\driving-pi\stream_to_pi.log (rotated, 5 x 5MB).

param(
    [int]$MaxSizeMB = 5,
    [int]$MaxKeep  = 5,
    [int]$RotateEveryLines = 500
)

$ErrorActionPreference = "Continue"

$LogDir  = Join-Path $env:LOCALAPPDATA "driving-pi"
$LogFile = Join-Path $LogDir "stream_to_pi.log"
$BatFile = Join-Path $PSScriptRoot "stream_to_pi.bat"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Invoke-LogRotation {
    if (-not (Test-Path $LogFile)) { return }
    try {
        $sizeMB = (Get-Item $LogFile).Length / 1MB
    } catch { return }
    if ($sizeMB -lt $MaxSizeMB) { return }

    for ($i = $MaxKeep - 1; $i -ge 1; $i--) {
        $old = "$LogFile.$i"
        $new = "$LogFile.$($i + 1)"
        if (Test-Path $old) { Move-Item $old $new -Force -ErrorAction SilentlyContinue }
    }
    Move-Item $LogFile "$LogFile.1" -Force -ErrorAction SilentlyContinue
}

function Write-LogLine {
    param([string]$Line)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts $Line" | Add-Content -Path $LogFile -ErrorAction SilentlyContinue
}

Invoke-LogRotation
Write-LogLine "==================== stream_to_pi wrapper START (pid $PID) ===================="
Write-LogLine "Bat file: $BatFile"

$lineCount = 0
try {
    & cmd /c $BatFile 2>&1 | ForEach-Object {
        Write-LogLine $_
        $lineCount++
        if ($lineCount -ge $RotateEveryLines) {
            Invoke-LogRotation
            $lineCount = 0
        }
    }
} catch {
    Write-LogLine "WRAPPER ERROR: $($_.Exception.Message)"
}

Write-LogLine "==================== stream_to_pi wrapper EXIT ===================="
