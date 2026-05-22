# claymore-keys-mapping.ps1 - Deterministic mapping Claymore II key Code -> brand family.
#
# Derivato dal probe della Aura SDK .Keys collection (107 tasti fisici) + probe
# verifica live 2026-05-22 (single-LED BLU su codes 17/31/45 -> lit up W/S/X).
# Quel test ha rivelato un offset sistemico nell'interpretazione X,Y del primo dump:
#   - X=0 column NON e' M1-M5 macro (che probabilmente non esistono nel SDK Keys
#     di questa Claymore II) ma e' la colonna modifier sinistra (ESC/`/Tab/Caps/LShift/LCtrl)
#   - X=2 column NON e' Tab/Caps/LShift ma e' la prima lettera di ogni riga (Q/A/Z)
#
# Mapping CORRETTO:
#   Y=0  ESC, F-row(F1-F12), PrtSc/ScrLk/Pausa, multimedia top
#   Y=1  `, 1-0, ', ì, Backspace, Ins/Home/PgU, NumLk + numpad row 1
#   Y=2  Tab, QWERTYUIOP, e', +, \, Del/End/PgD, numpad row 2
#   Y=3  CapsLock, ASDFGHJKL, o', a', Enter, numpad row 3
#   Y=4  LShift, ZXCVBNM, , . - RShift, Up arrow, numpad row 4
#   Y=5  LCtrl LWin LAlt Space RAlt Fn Menu RCtrl arrows, numpad 0 + dec
#
# Distribuzione live (post nav->MAGENTA, arrows->LIME, modifier-col fix):
#   LIME    = 62 keys (58%) - numeri + lettere + punteggiatura + numpad numerico + arrows
#   CYAN    = 22 keys (21%) - F-row + sistema (PrtSc/ScrLk/Pausa) + numpad ops + multimedia
#   MAGENTA = 23 keys (21%) - modifier perimetrali + nav cluster + transazionali + NumLock
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

# MAGENTA - modifiers/structural + arrows + number row (31 keys)
# v5 2026-05-22: numbers 1-0 (codes 2-11) -> magenta per visual separator
# tra numpad numerici e tastiera principale.
$script:ClaymoreMagentaCodes = @(
    # Left modifier column (colonna X=0, una per riga)
    1,    # ESC      (Y=0)
    15,   # Tab      (Y=2)
    58,   # CapsLock (Y=3)
    42,   # LShift   (Y=4)
    29,   # LCtrl    (Y=5)
    # Right modifier column (X=15 perimetro destro)
    14,   # Backspace (Y=1)
    28,   # Enter main (Y=3)
    54,   # RShift   (Y=4)
    157,  # RCtrl    (Y=5)
    # Bottom row modifiers (X=1, 2, 9, 11, 12 su Y=5)
    219,  # LWin
    56,   # LAlt
    57,   # Spacebar
    184,  # RAlt
    256,  # Fn
    221,  # Menu (context)
    # Numpad modifiers
    69,   # NumLock
    156,  # Numpad Enter
    # Arrows (moved from LIME 2026-05-22 feedback)
    200,  # Up
    203,  # Left
    205,  # Right
    208,  # Down
    # Number row 1-0 (v5 2026-05-22 - separator visivo)
    2, 3, 4, 5, 6, 7, 8, 9, 10, 11
)

# CYAN - commands/actions (35 keys)
# v4 2026-05-22: punteggiatura italiana (', ì, è, +, ò, à, ù, , . -) -> CYAN
# per accent-color sui caratteri speciali italiani.
$script:ClaymoreCyanCodes = @(
    # F-row F1-F12 (F1-F10 sequenziali 59-68, F11=87, F12=88)
    59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88,
    # Nav cluster (Ins/Del/Home/End/PgUp/PgDn) - cyan
    210, 211, 199, 207, 201, 209,
    # Numpad operators: /, *, -, +
    181, 55, 74, 78,
    # Multimedia top-right (volume wheel + profile + extra)
    257, 258, 259,
    # Italian punctuation accents (v4 live feedback + v6 \ correction)
    12,   # ' apostrofo (Y=1 X=12)
    13,   # i' (Y=1 X=13)
    26,   # e' (Y=2 X=12)
    27,   # + (Y=2 X=13)
    39,   # o' (Y=3 X=11)
    40,   # a' (Y=3 X=12)
    41,   # \ backslash (Y=1 X=0 - Italian PC layout, NOT backtick come pensato) v6 2026-05-22
    43,   # phantom slot (no LED fisico - probe live confermato), tenuto cyan per safety
    51,   # , (Y=4 X=9)
    52,   # . (Y=4 X=10)
    53    # - (Y=4 X=11)
)

# Default LIME (62 keys) per esclusione:
#   - Number row: 41 (`), 2-13 (1-0 + Italian punct)
#   - QWERTY row: 16-27 (Q-P + Italian punct), 43 (\)
#   - ASDF row:   30-40 (A-L + Italian punct)
#   - ZXCV row:   44-53 (Z-/ + Italian punct)
#   - Numpad numeric: 71-73, 75-77, 79-83 (e decimal)
#   - Arrows: 200, 203, 205, 208 (Up, Left, Right, Down)
#
# LIMITAZIONE NOTA (2026-05-22 dopo brute-force probe):
# Il tasto 'u' italiano ha un LED che risponde al "set all Lights[]" del daemon
# (mostra lime di sfondo) ma il suo indice non e' addressable individualmente
# - ne' tramite .Keys[code] (non enumerato in nessuno dei 107 codes), ne'
# tramite .Lights[index] (non emerge in nessun probe singolo dei 75 unmapped
# Lights). E' un quirk firmware-level della Claymore II Italian: il LED esiste
# fisicamente ma il SDK non lo espone per scritture mirate. Accettata come
# limitazione: 'u' resta LIME background, non puo' essere portata in CYAN.
#
# Stesso vale per '<' (tasto ISO key tra LShift e Z): questa Claymore II e'
# ANSI 104-key, '<' non esiste fisicamente. Combo software AltGr+qualcosa.

function Get-ClaymoreKeyFamily {
    param([Parameter(Mandatory=$true)][int]$Code)

    if ($script:ClaymoreMagentaCodes -contains $Code) { return "magenta" }
    if ($script:ClaymoreCyanCodes -contains $Code) { return "cyan" }
    # Default: LIME
    return "lime"
}
