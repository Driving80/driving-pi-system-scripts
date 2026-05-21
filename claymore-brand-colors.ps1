# claymore-brand-colors.ps1
# Drivingtech brand RGB constants for Claymore II layout.
#
# Source-of-truth: driving-tech/execution/generate_gmail_wallpaper.py lines 26-28.
# DO NOT modify these values without updating the brand wallpaper script too.
#
# Compatible with PowerShell 5.1 and 7+. ASCII-only.

$script:ClaymoreBrandColors = @{
    "lime"    = @{ R = 212; G = 255; B = 0   }
    "cyan"    = @{ R = 0;   G = 229; B = 255 }
    "magenta" = @{ R = 255; G = 0;   B = 200 }
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
