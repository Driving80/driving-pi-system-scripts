# Heartbeat sender — Windows → Pi audio switch monitor
# Run in background or via Task Scheduler (Windows logon trigger)
# Sends HTTP POST http://192.168.68.68:5005/heartbeat every 30 seconds

param(
    [string]$PiAddress = "192.168.68.68",
    [int]$HeartbeatInterval = 30,
    [int]$TimeoutMs = 5000
)

$HeartbeatUrl = "http://${PiAddress}:5005/heartbeat"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Starting heartbeat sender → $HeartbeatUrl (interval: ${HeartbeatInterval}s)" -ForegroundColor Green

$FailureCount = 0
$MaxFailures = 5

while ($true) {
    try {
        $Response = Invoke-WebRequest -Uri $HeartbeatUrl -Method POST -TimeoutSec ($TimeoutMs / 1000) -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 💓 Heartbeat sent — Windows online" -ForegroundColor Cyan
            $FailureCount = 0
        }
    }
    catch {
        $FailureCount++
        $Err = $_.Exception.Message
        if ($FailureCount -le 2) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ⚠ Heartbeat failed ($FailureCount/$MaxFailures): $Err" -ForegroundColor Yellow
        } elseif ($FailureCount -eq $MaxFailures) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ✗ Heartbeat failed $MaxFailures times — Pi may be offline" -ForegroundColor Red
        }
    }

    Start-Sleep -Seconds $HeartbeatInterval
}