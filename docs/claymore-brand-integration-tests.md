# Claymore Brand Layout - Integration tests + Final state

Procedure post-deploy. Eseguire **in console session interactive** su HAL9000
(non via SSH ne' VS Code Bash subprocess - quei contesti sono "ghost sessions"
per il SDK Aura, vedi memory [[aura-sdk-com-direct-pattern]]).

## Architettura finale (post 2026-05-22 deterministic pivot)

**Daemon long-running** invece di apply one-shot. Il SDK Aura ASUS resetta i
LED al "default effect" quando il control viene rilasciato (anche su process
exit), come da [doc ufficiale IAuraSdk2](https://www.asus.com/microsite/aurareadydevportal/interface_aura_service_lib_1_1_i_aura_sdk2.html).
Quindi il daemon:
- Acquisisce SDK control + SwitchMode + Apply iniziale UNA VOLTA al logon
- Entra in loop infinito: sleep 10s, re-Apply idempotente, ripeti
- MAI ReleaseControl (SDK rilascia auto su exit processo)
- Re-acquire automatico su errore (wake-from-sleep, disconnect)

**Mapping deterministico** via `.Keys[]` collection (107 phys keys con .Code
stabile + X,Y grid coords). Zero calibrazione visiva. Output: brand layout
applicato direttamente al primo logon, no intermediate steps.

## Layout colori finale

LIME `#A0FF00` (LED-calibrated - screen brand e' `#D4FF00`, ma su Aura LED
appare troppo giallo, calibrato a `#A0FF00` per matchare la percezione
visiva del brand):
- Lettere QWERTY, ASDF, ZXCV
- Numpad numerici (0-9 + decimale)

CYAN `#00E5FF` brand verbatim:
- F-row F1-F12
- Punteggiatura italiana: \ ' i' e' + o' a' (codes 41, 12, 13, 26, 27, 39, 40)
- Punteggiatura main: , . - (codes 51, 52, 53)
- Numpad operatori: + - * /
- Multimedia top-right (volume wheel + profile)

MAGENTA `#FF00C8` brand verbatim:
- Numeri 1-0 (separator visivo tra numpad e tastiera principale)
- Frecce up/down/left/right (codes 200, 203, 205, 208)
- Modifier perimetrali: Esc, Tab, Caps, Shift, Ctrl, Win, Alt, Fn, Menu,
  Backspace, Enter, Space, NumLock, Numpad Enter
- Nav cluster: Ins, Del, Home, End, PgUp, PgDn

## Limitazioni note

Il tasto **u' (Italian punct)** rimane LIME background, non puo' essere
portato a CYAN. La 'u' ha un LED che risponde al "set all Lights[]"
broadcast (per quello mostra lime) ma il suo indice non e' addressable via
SDK ne' tramite .Keys[code] ne' .Lights[index] singoli. Confermato via
brute-force probe di tutti i 107 codes + tutti i 75 unmapped Lights indexes.
Quirk firmware-level specifico di questa Claymore II Italian.

Il tasto **<** (ISO key tra LShift e Z) non esiste fisicamente: la Claymore
II in questione e' ANSI 104-key, non ISO 105-key. Niente LED da colorare.

## T1 - First apply post-install

```powershell
cd "c:\Users\gpier\Documents\Claude\Projects\driving-pi-system-scripts"
.\claymore-brand-layout.ps1
```

Pass criteria:
- [ ] Console output INFO senza ERROR
- [ ] Tastiera mostra layout brand entro 5 secondi
- [ ] Log $env:TEMP\claymore-brand-layout.log contiene DAEMON START + Apply iteration #1 OK
- [ ] LIME visibile come acid yellow-green (non verde scuro, non giallo)
- [ ] Process resta running (Ctrl+C per fermare)

## T2 - Logon trigger

```powershell
# Logout + login. Poi:
Get-Content $env:TEMP\claymore-brand-layout.log -Tail 5
```

Pass criteria:
- [ ] Entry log con DAEMON START + timestamp logon
- [ ] Tastiera mostra brand layout entro 10s dal desktop disponibile
- [ ] Nessun ERROR nel log

## T3 - Wake trigger

```powershell
psshutdown -d -t 0  # sleep S3
# Wake da bottone strip TV "wake"
Start-Sleep -Seconds 15
Get-Content $env:TEMP\claymore-brand-layout.log -Tail 5
```

Pass criteria:
- [ ] Daemon resume (process suspended con OS, riprende all'awake)
- [ ] Apply iterations continuano post-wake
- [ ] Tastiera mostra brand layout entro 15s post-wake
- [ ] Nessun ERROR

NOTA: in caso di drift visibile post-wake (colori "stale" anche dopo molti
secondi), restart manuale:
```powershell
schtasks /end /tn ClaymoreBrandLayout
schtasks /run /tn ClaymoreBrandLayout
```

## T4 - Coordinamento monitor-off/on

Da tablet dashboard-casa:
1. Tap "monitor off" -> LED Claymore II si spengono (via OpenRGB brightness 0)
2. Attendi 5s
3. Tap "monitor on" -> LED riaccendono

Pass criteria:
- [ ] LED spengono in <1s
- [ ] LED riaccendono in <2s con brand layout
- [ ] Daemon non crash durante il cycle
- [ ] Log nessun ERROR

## T5 - Interferenza Armoury Crate

1. Apri Armoury Crate
2. Cambia preset Aura a "Rainbow"
3. Verifica preset attivo dopo qualche secondo
4. Logout + login
5. Verifica daemon riacquisce + applica brand layout al logon

Pass criteria:
- [ ] Armoury Crate preset prende controllo (atteso, OK durante test)
- [ ] Daemon re-applica brand layout entro 30s dal logon successivo
- [ ] Per recovery rapido manuale: schtasks /end /tn ClaymoreBrandLayout; schtasks /run /tn ClaymoreBrandLayout

## T6 - Brand fidelity visiva

Foto della tastiera in luce ambient normale studio.

Confronta con:
- c:\Users\gpier\Documents\Claude\Projects\driving-tech\assets\gmail-darkv2.jpg (wallpaper)
- c:\Users\gpier\Documents\Claude\Projects\driving-tech\index.html aperto in browser

Pass criteria:
- [ ] Lime appare acid yellow-green (NON verde-oliva ne' giallo-saturo)
- [ ] Magenta appare fuxia-saturo (NON viola)
- [ ] Cyan appare elettrico (NON azzurro polvere)
- [ ] Distribuzione visivamente coerente: massa lime al centro, blocchi
      magenta perimetrali, cyan accent su F-row + nav + punteggiatura
