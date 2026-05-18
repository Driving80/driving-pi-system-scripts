# Heartbeat Switching — Windows ↔ Pi Audio Source

## Problema Risolto

Prima, sia **librespot** (Spotify Connect) che **GStreamer RTP** (audio Windows) erano configurati per scrivere a `hw:Loopback,0` contemporaneamente, causando conflitto. Solo un'applicazione alla volta può tenere il device.

## Soluzione

Monitor heartbeat su Pi commuta automaticamente:
- **Windows online** (heartbeat fresco) → ferma librespot, avvia GStreamer RTP
- **Windows offline** (heartbeat stale) → ferma GStreamer, avvia librespot

Così:
- PC Windows ON → audio Windows via GStreamer
- PC Windows OFF → Spotify Connect via librespot (senza conflitti)

---

## Installazione — Lato Pi

### 1. Copia script monitor

```bash
scp heartbeat_monitor.py audio@192.168.68.68:~
```

### 2. Installa servizio

```bash
scp heartbeat_monitor.service audio@192.168.68.68:~
ssh audio@192.168.68.68 "systemctl --user link ~/heartbeat_monitor.service"
ssh audio@192.168.68.68 "systemctl --user enable heartbeat_monitor.service"
```

### 3. Installa dipendenze (se serve)

```bash
ssh audio@192.168.68.68
pip install fastapi uvicorn
```

### 4. Avvia servizio

```bash
ssh audio@192.168.68.68 "systemctl --user start heartbeat_monitor.service"
```

### 5. Verifica

```bash
ssh audio@192.168.68.68 "systemctl --user status heartbeat_monitor.service"
curl http://192.168.68.68:5005/status
# Deve mostrare: {"windows_online": false, "last_heartbeat": null, ...}
```

---

## Installazione — Lato Windows

### Opzione A: Task Scheduler (Consigliata)

**Setup manuale:**

1. Apri Task Scheduler (`taskschd.msc`)
2. Crea Basic Task → Nome: "Heartbeat Sender"
3. Trigger: "Al logon" (ripeti ogni 30 minuti indefinitamente)
4. Azione: Avvia programma
   - Programma: `powershell.exe`
   - Argomenti: `-NoProfile -ExecutionPolicy Bypass -File "C:\Users\gpier\Documents\Claude\Projects\send_heartbeat.ps1"`
   - Cartella di lavoro: `C:\Users\gpier\Documents\Claude\Projects`
5. Condizioni: Deseleziona "Arresta se su batteria"
6. Impostazioni: Consenti avvio manuale, consenti istanze multiple

### Opzione B: Linea di comando (one-liner)

```powershell
$TaskAction = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File 'C:\Users\gpier\Documents\Claude\Projects\send_heartbeat.ps1'"
$TaskTrigger = New-ScheduledTaskTrigger -AtLogOn -RepetitionInterval (New-TimeSpan -Minutes 30)
$TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Heartbeat Sender" -Action $TaskAction -Trigger $TaskTrigger -Settings $TaskSettings
```

### 3. Verifica heartbeat manuale

```powershell
# Esegui manualmente in PowerShell:
. C:\Users\gpier\Documents\Claude\Projects\send_heartbeat.ps1 -HeartbeatInterval 5

# Deve stampare: "💓 Heartbeat sent — Windows online" ogni 5 secondi
```

### 4. Controlla log

Monitor su Pi:

```bash
ssh audio@192.168.68.68 "journalctl --user-unit heartbeat_monitor.service -f"
# Deve mostrare "💓 Heartbeat received from Windows" ogni 30s
```

---

## Transizioni di Stato

| Evento | librespot | GStreamer | Sorgente Audio |
|--------|-----------|-----------|----------------|
| Pi boot, no heartbeat | **RUNNING** | stopped | Spotify Connect |
| Windows invia heartbeat | stopping → stopped | starting → **RUNNING** | Audio Windows (GStreamer) |
| Heartbeat stale (90s+) | starting → **RUNNING** | stopping → stopped | Spotify Connect |

---

## Configurazione

Modifica `heartbeat_monitor.py`:

```python
HEARTBEAT_WINDOW = 90      # secondi prima di considerare heartbeat stale
HEARTBEAT_PORT = 5005      # porta HTTP POST su Pi
LIBRESPOT_SERVICE = "librespot.service"      # nome servizio systemd
GSTREAMER_SERVICE = "audio-receiver.service" # nome servizio systemd
```

---

## Cosa invia il daemon (Step 3.4)

Dal 2026-05-18 il daemon `send_heartbeat.ps1` invia un payload JSON ricco insieme al heartbeat. Prima di ogni POST interroga:

- `GET http://localhost:11434/api/tags` (timeout 3s) -> lista modelli scaricati in `models_loaded`
- `GET http://localhost:11434/api/ps` (timeout 3s) -> lista modelli caldi in VRAM in `models_warm`
- `nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits` -> VRAM libera in MB in `vram_free_mb` (`null` se nvidia-smi assente)

Il payload viene mandato come body JSON sulla `POST /heartbeat`. Il monitor Pi lo conserva in memoria (`workstation_state`) e lo espone in lettura su `GET /state/ws`. Il bot Telegram su Pi consulta quell'endpoint ogni 30 secondi per decidere se mandare la richiesta NLU/chat alla workstation (qwen3:4b/qwen3:14b GPU) o al fallback locale Pi (L0 regex + qwen3:1.7b L1).

**Backward-compat**: se Ollama o nvidia-smi falliscono, il daemon manda comunque il payload con `ollama_ready: false` e `vram_free_mb: null`. Il monitor accetta ANCHE body vuoto, quindi vecchi daemon o test manuali con `curl -X POST ...` continuano a funzionare per il solo audio switching.

**Test manuale dello stato (da qualsiasi host del tailnet o LAN):**

```bash
curl -s http://192.168.68.68:5006/state/ws | python3 -m json.tool
```

Se `ollama_ready: true` e `nlu_available: true`, il bot routera' tutto verso la workstation. Se `freshness_seconds > 180`, il bot considera la workstation offline e usa il Pi fallback.

---

## Troubleshooting

### Heartbeat non arriva

**Controlla firewall Pi:**

```bash
sudo ufw allow 5005/tcp
```

**Controlla Windows raggiunge Pi:**

```powershell
curl http://192.168.68.68:5005/status
```

### Servizi non commutano

**Test manuale su Pi:**

```bash
systemctl --user stop librespot
systemctl --user start audio-receiver
# Aspetta 90s senza heartbeat, poi:
curl -X POST http://192.168.68.68:5005/heartbeat
# GStreamer deve rimanere running
# Dopo 90s stale, librespot deve auto-start
```

### Log

**Windows Task Scheduler:**
```
C:\Users\%username%\AppData\Local\Temp\heartbeat_sender.log
```

**Pi systemd:**
```bash
journalctl --user-unit heartbeat_monitor.service -n 50
```

---

## Prossimi Step

- [ ] Testare arrivo heartbeat su Pi (Task Scheduler running)
- [ ] Verificare transizioni di stato (ferma manualmente Windows heartbeat, conferma librespot in 90s)
- [ ] Optional: USB switch SMSL (~€20) — connetti SMSL a Windows quando PC on, a Pi quando PC off
- [ ] Optional: Implementare comando /askdoc Telegram (task separato)