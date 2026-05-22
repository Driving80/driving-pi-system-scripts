# claymore-keys-mapping.ps1 - Deterministic mapping Claymore II key Code -> brand family.
#
# Derivato dal probe della Aura SDK .Keys collection (107 tasti fisici sulla
# Claymore II). Ogni tasto ha un .Code stabile assegnato dal SDK; le coordinate
# X,Y sulla griglia (Width=26, Height=7) sono state usate per identificare
# quale tasto fisico corrisponde a ogni Code.
#
# Distribuzione risultante:
#   LIME    = 54 keys (50.5%) - numeri + lettere + punteggiatura + numpad numerico
#   CYAN    = 37 keys (34.6%) - F-row + macro + arrows + nav + system + numpad operatori + multimedia
#   MAGENTA = 16 keys (15.0%) - perimetro modifiers + transazionali (Spazio/Invio/Backspace) + NumLock
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

# MAGENTA - modifiers/structural + nav cluster (22 keys)
# Nav cluster spostato qui da CYAN su feedback live 2026-05-22:
# Ins/Del/Home/End/PgUp/PgDn sono "navigazione strutturale" piu' che "comando".
$script:ClaymoreMagentaCodes = @(
    14,   # Backspace
    16,   # Tab
    28,   # Enter (main)
    29,   # Left Ctrl
    30,   # CapsLock
    44,   # Left Shift
    54,   # Right Shift
    56,   # Left Alt
    57,   # Spacebar
    69,   # NumLock
    156,  # Numpad Enter
    157,  # Right Ctrl
    184,  # Right Alt
    219,  # Left Win
    221,  # Menu (context)
    256,  # Fn
    # Nav cluster (moved from CYAN 2026-05-22)
    210,  # Ins
    211,  # Del
    199,  # Home
    207,  # End
    201,  # PgUp
    209   # PgDn
)

# CYAN - commands/actions (27 keys)
# Arrows rimossi da qui su feedback live 2026-05-22 (vanno in LIME come default).
$script:ClaymoreCyanCodes = @(
    # Macros M1-M5 (M1=1, M2=41, M3=15, M4=58, M5=42)
    1, 15, 41, 42, 58,
    # F-row F1-F12 (F1-F10 sequenziali 59-68, F11=87, F12=88)
    59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88,
    # System cluster: PrtSc, ScrLk, Pause
    183, 70, 197,
    # Numpad operators: /, *, -, +
    181, 55, 74, 78,
    # Multimedia top-right (volume wheel + profile)
    257, 258, 259
)

function Get-ClaymoreKeyFamily {
    param([Parameter(Mandatory=$true)][int]$Code)

    if ($script:ClaymoreMagentaCodes -contains $Code) { return "magenta" }
    if ($script:ClaymoreCyanCodes -contains $Code) { return "cyan" }
    # Default: LIME (numbers, letters, punctuation, numpad numeric, decimal)
    return "lime"
}
