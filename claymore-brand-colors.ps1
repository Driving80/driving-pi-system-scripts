# claymore-brand-colors.ps1
# Drivingtech brand RGB constants for Claymore II LED layout.
#
# Brand source-of-truth (screen rendering):
#   driving-tech/execution/generate_gmail_wallpaper.py lines 26-28
#   LIME (screen)    = (212, 255, 0)  #D4FF00
#   CYAN (screen)    = (0, 229, 255)  #00E5FF
#   MAGENTA (screen) = (255, 0, 200)  #FF00C8
#
# LED CALIBRATION (deliberate deviation 2026-05-22):
# On Claymore II Aura LEDs the brand LIME #D4FF00 renders too yellow.
# Live comparative probe showed #A0FF00 (160, 255, 0) on the LED appears
# perceptually like the acid-lime of the brand on screen. We keep this
# deviation ONLY for LED hardware rendering; brand wallpapers / sites /
# docs continue to use the verbatim brand #D4FF00.
#
# CYAN and MAGENTA are kept at brand verbatim (LED rendering matches screen).
#
# Compatible with PowerShell 5.1 and 7+. ASCII-only.

$script:ClaymoreBrandColors = @{
    "lime"    = @{ R = 160; G = 255; B = 0   }  # #A0FF00 LED-calibrated (screen brand: #D4FF00)
    "cyan"    = @{ R = 0;   G = 229; B = 255 }  # #00E5FF brand verbatim
    "magenta" = @{ R = 255; G = 0;   B = 200 }  # #FF00C8 brand verbatim
}

function Get-ClaymoreBrandColor {
    param([Parameter(Mandatory=$true)][string]$Family)

    $key = $Family.ToLowerInvariant()
    if ($script:ClaymoreBrandColors.ContainsKey($key)) {
        return $script:ClaymoreBrandColors[$key]
    }
    # Fallback: LIME (primary mass of the layout)
    return $script:ClaymoreBrandColors["lime"]
}
