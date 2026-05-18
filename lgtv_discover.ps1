# lgtv_discover.ps1 — Helper di discovery LG TV Companion (Phase 0.a, ADR 34)
#
# Da eseguire UNA VOLTA sulla workstation (con TV accesa) per validare:
#   1. Quale path dell'eseguibile LG TV Companion e' installato.
#   2. Quale flag/argomenti effettivamente spengono la TV.
#
# Output: report a stdout + file di log. Aggiornare manualmente la sequenza
# $attempts in post_wake_video_off.ps1 con il flag che funziona sul setup.
#
# NB: Lo script proverà a spegnere la TV. Assicurati che TV sia accesa
# all'inizio e tu possa monitorarla durante i tentativi. Tra un tentativo
# e l'altro c'e' una pausa di 8 secondi per dare tempo alla TV di reagire
# e di riaccenderla manualmente con il telecomando.

param(
    [int]$DelayBetweenAttempts = 8,
    [string]$LogPath           = (Join-Path $env:TEMP "lgtv_discover.log")
)

$ErrorActionPreference = "Continue"

function Write-Out {
    param([string]$Message, [string]$Color = "Gray")
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -Path $LogPath -Value $line -ErrorAction Stop } catch {}
}

Write-Out "=== LG TV Companion discovery ===" "Cyan"
Write-Out "Log: $LogPath"

# Step 1: Discovery exe
$candidates = @(
    "${env:ProgramFiles}\LG TV Companion\LGTVcompanion.exe",
    "${env:ProgramFiles}\LG TV Companion\LG TV Companion.exe",
    "${env:ProgramFiles(x86)}\LG TV Companion\LGTVcompanion.exe",
    "${env:LOCALAPPDATA}\Programs\LG TV Companion\LGTVcompanion.exe"
)

Write-Out ""
Write-Out "Step 1: discovery eseguibile..." "Yellow"

$foundCandidates = @()
foreach ($p in $candidates) {
    if ($p -and (Test-Path $p)) {
        $foundCandidates += $p
        Write-Out "  FOUND: $p" "Green"
    }
}

$gc = Get-Command "LGTVcompanion" -ErrorAction SilentlyContinue
if (-not $gc) { $gc = Get-Command "lgtv" -ErrorAction SilentlyContinue }
if ($gc) {
    Write-Out "  PATH:  $($gc.Path)" "Green"
    if ($foundCandidates -notcontains $gc.Path) {
        $foundCandidates += $gc.Path
    }
}

if ($foundCandidates.Count -eq 0) {
    Write-Out "" "Red"
    Write-Out "ERROR: LG TV Companion non trovato. Installazione richiesta." "Red"
    Write-Out "Path standard cercati:" "Red"
    foreach ($p in $candidates) { Write-Out "  - $p" }
    exit 1
}

$lgtvExe = $foundCandidates[0]
Write-Out ""
Write-Out "Uso: $lgtvExe" "Cyan"

# Step 2: Info versione/help
Write-Out ""
Write-Out "Step 2: chiedo --help all'eseguibile (puo' aprire una GUI, chiudila e continua)..." "Yellow"
$helpAttempts = @("--help", "-h", "-help", "/?", "/help")
foreach ($flag in $helpAttempts) {
    try {
        $output = & $lgtvExe $flag 2>&1 | Out-String
        if ($output.Trim()) {
            Write-Out "Output con '$flag':" "Magenta"
            Write-Out $output
            break
        }
    }
    catch {
        Write-Out "  '$flag' -> exception: $($_.Exception.Message)" "Gray"
    }
}

# Step 3: Tentativi power-off
Write-Out ""
Write-Out "Step 3: tentativi di power-off (TV deve essere ACCESA all'inizio)" "Yellow"
Write-Out "  Tra ogni tentativo: pausa $DelayBetweenAttempts s. Riaccendi TV col telecomando se necessario."
Write-Out "  Premi Ctrl+C per interrompere."

$attempts = @(
    @("-off"),
    @("--off"),
    @("-poweroff"),
    @("--poweroff"),
    @("/off"),
    @("/poweroff"),
    @("--turn-off"),
    @("-PowerOff"),
    @("--power-off")
)

foreach ($a in $attempts) {
    $argStr = $a -join " "
    Write-Out ""
    Write-Out "Tentativo: $lgtvExe $argStr" "Cyan"
    Write-Out "  -> guarda la TV. Si spegne? (Y/N/Q dopo $DelayBetweenAttempts s)" "Yellow"
    try {
        $proc = Start-Process -FilePath $lgtvExe -ArgumentList $a -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
        Write-Out "  exitCode=$($proc.ExitCode)"
    }
    catch {
        Write-Out "  EXCEPTION: $($_.Exception.Message)" "Red"
        continue
    }
    Start-Sleep -Seconds $DelayBetweenAttempts
    Write-Out "  La TV si e' spenta con questo flag? (Y/N/Q per quit)" "Yellow"
    $resp = Read-Host
    if ($resp -eq "Y" -or $resp -eq "y") {
        Write-Out ""
        Write-Out "=== SUCCESS ===" "Green"
        Write-Out "Flag funzionante: '$argStr'" "Green"
        Write-Out "Aggiorna manualmente post_wake_video_off.ps1 mettendo questo come primo `$attempts." "Green"
        Write-Out "Eseguibile: $lgtvExe" "Green"
        exit 0
    }
    if ($resp -eq "Q" -or $resp -eq "q") {
        Write-Out "Discovery interrotta dall'utente."
        exit 130
    }
}

Write-Out ""
Write-Out "=== NESSUN FLAG TROVATO ===" "Red"
Write-Out "Verifica la documentazione di LG TV Companion installato per la sintassi CLI corretta." "Red"
Write-Out "URL repo: https://github.com/JPersson77/LGTVCompanion" "Red"
exit 2
