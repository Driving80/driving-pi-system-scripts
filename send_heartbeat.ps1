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

function Get-OllamaState {
    # Probe local Ollama + nvidia-smi. Never throws; logs WARN on failures and returns safe defaults.
    $state = @{
        ollama_ready  = $false
        models_loaded = @()
        models_warm   = @()
        vram_free_mb  = $null
    }

    # Probe 1: /api/tags (models installed)
    try {
        $tags = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method GET -TimeoutSec 3 -ErrorAction Stop
        $state.ollama_ready = $true
        if ($tags -and $tags.models) {
            $names = @()
            foreach ($m in $tags.models) {
                if ($m.name) { $names += [string]$m.name }
            }
            $state.models_loaded = @($names)
        }
    }
    catch {
        Write-Log "WARN" ("Ollama /api/tags probe failed: " + $_.Exception.Message)
    }

    # Probe 2: /api/ps (models currently warm in VRAM) -- only if /api/tags succeeded
    if ($state.ollama_ready) {
        try {
            $ps = Invoke-RestMethod -Uri "http://localhost:11434/api/ps" -Method GET -TimeoutSec 3 -ErrorAction Stop
            if ($ps -and $ps.models) {
                $warm = @()
                foreach ($m in $ps.models) {
                    if ($m.name) { $warm += [string]$m.name }
                }
                $state.models_warm = @($warm)
            }
        }
        catch {
            Write-Log "WARN" ("Ollama /api/ps probe failed: " + $_.Exception.Message)
        }
    }

    # Probe 3: nvidia-smi VRAM free (first GPU)
    try {
        $smi = & nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>$null
        if ($LASTEXITCODE -eq 0 -and $smi) {
            $firstLine = ($smi | Select-Object -First 1).ToString().Trim()
            $parsed = 0
            if ([int]::TryParse($firstLine, [ref]$parsed)) {
                $state.vram_free_mb = $parsed
            } else {
                Write-Log "WARN" ("nvidia-smi returned unparseable value: " + $firstLine)
            }
        } else {
            Write-Log "WARN" "nvidia-smi unavailable or returned no data"
        }
    }
    catch {
        Write-Log "WARN" ("nvidia-smi probe failed: " + $_.Exception.Message)
    }

    return $state
}

Write-Log "INFO" "Starting heartbeat sender -> $HeartbeatUrl (interval ${HeartbeatInterval}s, pid $PID, host $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion))"

$FailureCount = 0
$MaxFailures  = 5

while ($true) {
    try {
        $ollamaState = Get-OllamaState

        $payload = @{
            ts             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            ollama_ready   = $ollamaState.ollama_ready
            models_loaded  = @($ollamaState.models_loaded)
            models_warm    = @($ollamaState.models_warm)
            vram_free_mb   = $ollamaState.vram_free_mb
            sleep_policy   = "manual_only"
        } | ConvertTo-Json -Compress

        $Response = Invoke-WebRequest -UseBasicParsing -Uri $HeartbeatUrl -Method POST -Body $payload -ContentType "application/json" -TimeoutSec ($TimeoutMs / 1000) -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            if ($FailureCount -gt 0) {
                Write-Log "INFO" "Heartbeat recovered after $FailureCount failures"
            }
            Write-Log "OK" "Heartbeat sent (ollama_ready=$($ollamaState.ollama_ready), vram=$($ollamaState.vram_free_mb)MB)"
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
