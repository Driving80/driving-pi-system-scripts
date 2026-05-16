# driving-pi-system-scripts

Script di sistema per Raspberry Pi 5 (driving-pi-01): automazione, monitoring, switching audio.

## Contenuto

### heartbeat_monitor — Commutatore audio Windows ↔ Pi

Risolve il conflitto device `hw:Loopback,0` fra librespot (Spotify Connect) e GStreamer RTP (audio Windows).

**File:**
- `heartbeat_monitor.py` — Monitor FastAPI su Pi (:5005) che ascolta heartbeat da Windows
- `heartbeat_monitor.service` — Servizio systemd user
- `send_heartbeat.ps1` — Sender Windows (PowerShell)
- `send_heartbeat.bat` — Wrapper Task Scheduler
- `HEARTBEAT_SETUP.md` — Istruzioni installazione completa

**Logica:**
- Windows invia POST HTTP ogni 30s
- Se heartbeat fresco (Windows online) → stop librespot, start GStreamer RTP
- Se heartbeat stale (90s+) → stop GStreamer, start librespot

Vedi `HEARTBEAT_SETUP.md` per installazione dettagliata.

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

## Troubleshooting

Vedi `HEARTBEAT_SETUP.md` § Troubleshooting.

## Roadmap

- [ ] Aggiungere `/askdoc` Telegram su vault Obsidian
- [ ] Implementare USB switch SMSL (€20) per commutazione hardware
- [ ] Monitoring dashboard web per stato audio Pi