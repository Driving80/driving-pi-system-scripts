# driving-pi-system-scripts

Script di sistema per Raspberry Pi 5 (driving-pi-01): automazione, monitoring, switching audio.

## Contenuto

### heartbeat_monitor — Commutatore audio Windows ↔ Pi

Risolve il conflitto device `hw:Loopback,0` fra librespot (Spotify Connect) e GStreamer RTP (audio Windows).

**File:**
- `heartbeat_monitor.py` — Monitor FastAPI su Pi (:5006) che ascolta heartbeat da Windows
- `heartbeat_monitor.service` — Servizio systemd user
- `send_heartbeat.ps1` — Sender Windows (PowerShell)
- `send_heartbeat.bat` — Wrapper Task Scheduler
- `HEARTBEAT_SETUP.md` — Istruzioni installazione completa

**Logica:**
- Windows invia POST HTTP ogni 30s
- Se heartbeat fresco (Windows online) → stop librespot, start GStreamer RTP
- Se heartbeat stale (90s+) → stop GStreamer, start librespot

Vedi `HEARTBEAT_SETUP.md` per installazione dettagliata.

### stream_to_pi — Sender GStreamer audio Windows → Pi

Cattura il flusso audio uscente verso `CABLE Input (VB-Audio Virtual Cable)` e lo invia al Pi via RTP (UDP 5004), dove il receiver lo passa a CamillaDSP e poi al DAC.

**File:**
- `stream_to_pi.bat` — Comando `gst-launch-1.0` (loop infinito, restart 3s su crash)
- `stream_to_pi.ps1` — Wrapper PowerShell con logging + rotazione (5×5MB) in `%LOCALAPPDATA%\driving-pi\stream_to_pi.log`
- `stream_to_pi.vbs` — Launcher invisibile (SW_HIDE = 0) usato da Task Scheduler per non mostrare alcuna finestra
- `install_stream_to_pi_task.ps1` — Setup idempotente del task `StreamToPI` (AtLogOn + Wake-from-sleep, hidden, restart on failure)
- `restore_audio_pipeline.ps1` — Recovery one-click (vedi sotto)

**Device sorgente fisso:** `CABLE Output (VB-Audio Virtual Cable)` con device-id
`{0.0.1.00000000}.{c78dc72e-bdf4-48cf-997a-276af77fbd97}`. Niente `loopback=true` (è già un capture endpoint nativo). Pipeline: `wasapisrc → audioresample → audioconvert → S16BE 44100 stereo → rtpL16pay → udpsink 192.168.68.68:5004`.

**Per usarlo:** imposta `CABLE Input (VB-Audio Virtual Cable)` come dispositivo predefinito di riproduzione in `mmsys.cpl`. Tutto ciò che le app suonano va a CABLE Input → loopback interno VB-Audio → CABLE Output → catturato dal sender → Pi → DAC.

**Installazione:**
```powershell
# Da PowerShell come Administrator
cd C:\Users\gpier\Documents\Claude\Projects\driving-pi-system-scripts
.\install_stream_to_pi_task.ps1
Start-ScheduledTask -TaskName "StreamToPI"
```

### Restore one-click — `restore_audio_pipeline.ps1`

Recupera la pipeline quando lo stack audio Windows va in stato sporco (sintomi: `Could not open resource for reading` o `Failed to open device` sui device VB-Audio; `gst-launch-1.0` in loop di crash; nessun suono dalle casse pur con heartbeat OK).

**Cosa fa (richiede Admin):**
1. Stop del task `StreamToPI` + kill dei wrapper/gst-launch orfani
2. `Restart-Service AudioEndpointBuilder -Force` (Audiosrv ricarica in cascata)
3. Verifica che CABLE Output sia presente fra gli endpoint attivi
4. (Opzionale) Reimposta CABLE Input come default playback se il modulo `AudioDeviceCmdlets` è installato
5. Restart del task
6. Verifica che `gst-launch-1.0` sia in esecuzione

**Lancio rapido:** sul Desktop trovi lo shortcut **"Restore Audio Pipeline"** (icona ingranaggio, già configurato Run-As-Admin). Trascinalo sulla taskbar per pinnarlo: un click + UAC e la pipeline è ripristinata.

In alternativa, da PowerShell admin:
```powershell
& "C:\Users\gpier\Documents\Claude\Projects\driving-pi-system-scripts\restore_audio_pipeline.ps1"
```

## Installazione rapida

```bash
# Pi
scp heartbeat_monitor.py audio@192.168.68.68:~
scp heartbeat_monitor.service audio@192.168.68.68:~
ssh audio@192.168.68.68 'pip install fastapi uvicorn && systemctl --user link ~/heartbeat_monitor.service && systemctl --user enable heartbeat_monitor.service && systemctl --user start heartbeat_monitor.service'

# Verifica
curl http://192.168.68.68:5005/status
```

```powershell
# Windows — Task Scheduler (vedi HEARTBEAT_SETUP.md per dettagli)
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File 'C:\Users\gpier\Documents\Claude\Projects\driving-pi-system-scripts\send_heartbeat.ps1'"
$TaskTrigger = New-ScheduledTaskTrigger -AtLogOn -RepetitionInterval (New-TimeSpan -Minutes 30)
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Heartbeat Sender" -Action $TaskAction -Trigger $TaskTrigger -Settings $TaskSettings
```

## API endpoints

### POST /heartbeat

Riceve heartbeat dalla workstation Windows. **Body opzionale**: JSON con stato ricco (Step 3.4) o vuoto (legacy audio switching).

**Request (Step 3.4 rich payload):**

```http
POST /heartbeat HTTP/1.1
Host: 192.168.68.68:5006
Content-Type: application/json

{
  "ts": "2026-05-18T10:00:00Z",
  "ollama_ready": true,
  "models_loaded": ["qwen3:4b", "qwen3:14b", "bge-m3"],
  "models_warm": ["qwen3:14b"],
  "vram_free_mb": 3072,
  "sleep_policy": "manual_only"
}
```

**Request (legacy, solo audio switching):**

```http
POST /heartbeat HTTP/1.1
Host: 192.168.68.68:5006
```
(body vuoto — il monitor aggiorna solo il timestamp per la commutazione audio librespot <-> GStreamer)

**Response:**

```json
{"status": "heartbeat received", "timestamp": "2026-05-18T10:00:00.123456Z"}
```

### GET /state/ws  *(nuovo Step 3.4)*

Stato workstation consumato dal bot Telegram su Pi (`telegram-bot-pi.service`) per routing dinamico NLU+chat.

**Response:**

```json
{
  "ws_state": {
    "ts": "2026-05-18T10:00:00Z",
    "ollama_ready": true,
    "models_loaded": ["qwen3:4b", "qwen3:14b", "bge-m3"],
    "models_warm": ["qwen3:14b"],
    "vram_free_mb": 3072,
    "sleep_policy": "manual_only"
  },
  "freshness_seconds": 12,
  "nlu_available": true,
  "chat_available": true,
  "computed_at": "2026-05-18T10:00:12Z"
}
```

Logica `nlu_available`: `freshness_seconds <= 180 AND ws_state.ollama_ready AND "qwen3:4b" in ws_state.models_loaded AND (ws_state.vram_free_mb is null OR ws_state.vram_free_mb >= 2048)`.

Logica `chat_available`: come sopra ma con `qwen3:14b` e soglia VRAM 4096 MB (modello piu' grande, richiede piu' margine).

Se `workstation_state is null` (nessun heartbeat mai ricevuto) o `freshness > 180s`, entrambe le bool sono `false`.

### GET /status

Diagnostica audio (esistente, invariato).

```json
{"windows_online": true, "last_heartbeat": "...", "librespot_active": false, "gstreamer_active": true, ...}
```

## Troubleshooting

Vedi `HEARTBEAT_SETUP.md` § Troubleshooting.

## Roadmap

- [ ] Aggiungere `/askdoc` Telegram su vault Obsidian
- [ ] Implementare USB switch SMSL (€20) per commutazione hardware
- [ ] Monitoring dashboard web per stato audio Pi