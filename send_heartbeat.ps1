# Heartbeat sender -- Windows -> Pi audio switch monitor
# Run via Task Scheduler (logon + wake triggers).
# Sends HTTP POST http://192.168.68.68:5006/heartbeat every HeartbeatInterval seconds.
#
# Compatible with both Windows PowerShell 5.1 (powershell.exe) and PowerShell 7+ (pwsh.exe).
# ASCII-only output to avoid encoding issues across hosts.

param(
    [string]$PiAddress        = "192.168.68.68",
    [int]   $HeartbeatPort    = 5006,
    [int]   $HeartbeatInterval = 30,
    [int]   $TimeoutMs        = 5000,
    [string]$LogPath          = (Join-Path $env:TEMP "heartbeat_sender.log")
)

$ErrorActionPreference = "Continue"
$HeartbeatUrl = "http://${PiAddress}:${HeartbeatPort}/heartbeat"

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch {}
    try { Write-Host $line } catch {}
}

Write-Log "INFO" "Starting heartbeat sender -> $HeartbeatUrl (interval ${HeartbeatInterval}s, pid $PID, host $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion))"

$FailureCount = 0
$MaxFailures  = 5

while ($true) {
    try {
        $Response = Invoke-WebRequest -UseBasicParsing -Uri $HeartbeatUrl -Method POST -TimeoutSec ($TimeoutMs / 1000) -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            if ($FailureCount -gt 0) {
                Write-Log "INFO" "Heartbeat recovered after $FailureCount failures"
            }
            Write-Log "OK" "Heartbeat sent -- Windows online"
            $FailureCount = 0
        } else {
            Write-Log "WARN" "Unexpected status $($Response.StatusCode)"
        }
    }
    catch {
        $FailureCount++
        $Err = $_.Exception.Message
        if ($FailureCount -le 2) {
            Write-Log "WARN" "Heartbeat failed ($FailureCount/$MaxFailures): $Err"
        } elseif ($FailureCount -eq $MaxFailures) {
            Write-Log "ERR"  "Heartbeat failed $MaxFailures times -- Pi may be offline"
        }
    }

    Start-Sleep -Seconds $HeartbeatInterval
}
