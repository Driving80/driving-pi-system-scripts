# Claymore Brand Layout - Integration tests T1-T6

Manual smoke procedure post-deploy. Eseguire **in console session interactive** su HAL9000.

Prerequisites:
- Pester 12/12 passing (verifiable via `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path '.\tests\Claymore.Tests.ps1' -Show All"`)
- `claymore-brand-keymap.json` generato da calibrazione (T3b - script `calibrate-claymore.ps1`)
- Scheduled task `ClaymoreBrandLayout` installato (T5b - script `install_claymore_brand_task.ps1` con admin elevation)

## T1 - First apply post-install

```powershell
cd "c:\Users\gpier\Documents\Claude\Projects\driving-pi-system-scripts"
.\claymore-brand-layout.ps1
```

**Pass criteria:**
- [ ] Console output INFO senza ERROR
- [ ] Tastiera mostra layout brand (lime+cyan+magenta) entro 2 secondi
- [ ] Log `$env:TEMP\claymore-brand-layout.log` contiene entry START + OK
- [ ] Numpad detachable mostra anch'esso il pattern (operatori cyan, numeri lime)
- [ ] Colori appaiono ACIDI (lime giallo-acido, cyan elettrico, magenta fuxia) a brightness 100%

## T2 - Logon trigger

```powershell
# Su HAL9000:
logoff
# Login di nuovo
# Apri PowerShell e:
Get-Content $env:TEMP\claymore-brand-layout.log -Tail 5
```

**Pass criteria:**
- [ ] Entry log con timestamp del logon (entro 30s da desktop disponibile)
- [ ] Tastiera mostra brand layout
- [ ] Nessun ERROR nel log

## T3 - Wake trigger

```powershell
# Su HAL9000 console:
psshutdown -d -t 0  # entra in sleep
# Wake da bottone strip TV "wake" (via tablet -> HA -> Pi -> SSH -> Magic Packet)
# Aspetta 10s post-wake, poi:
Get-Content $env:TEMP\claymore-brand-layout.log -Tail 5
```

**Pass criteria:**
- [ ] Entry log con timestamp del wake (entro 5s post-resume)
- [ ] Tastiera mostra brand layout immediatamente dopo wake
- [ ] Nessun ERROR nel log

## T4 - Coordinamento monitor-off/on

Da tablet -> dashboard-casa:
1. Tap "monitor off" -> LED Claymore II si spengono
2. Attendi 5s
3. Tap "monitor on" -> LED riaccendono

**Pass criteria:**
- [ ] LED spengono in <1s da tap
- [ ] LED riaccendono in <2s da tap
- [ ] Colori che tornano = brand layout (vedi T6 per Caso A vs B)
- [ ] Nessun glitch (rainbow flash, colori sparsi, ecc.)

## T5 - Interferenza Armoury Crate

1. Apri Armoury Crate
2. Cambia preset Aura a "Rainbow" o "Static blu"
3. Verifica che tastiera mostra il nuovo preset (NON il brand)
4. Logout + login
5. Verifica che brand layout torna automaticamente al logon

**Pass criteria:**
- [ ] Armoury Crate preset prende controllo dopo step 2 (questo e' atteso, OK)
- [ ] Brand layout ritorna entro 30s dal nuovo logon
- [ ] Log mostra entry post-logon

## T6 - Brand fidelity visiva

Foto della tastiera in luce ambient normale studio.

Confronta con:
- `c:\Users\gpier\Documents\Claude\Projects\driving-tech\assets\gmail-darkv2.jpg` (wallpaper)
- `c:\Users\gpier\Documents\Claude\Projects\driving-tech\index.html` aperto in browser (landing)

**Pass criteria:**
- [ ] Lime appare giallo-acido (NON verde-oliva)
- [ ] Magenta appare fuxia-saturo (NON viola)
- [ ] Cyan appare elettrico (NON azzurro polvere)
- [ ] Distribuzione % visivamente coerente: massa lime, frame cyan, accent magenta
