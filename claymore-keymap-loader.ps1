# claymore-keymap-loader.ps1 -- Load + query Claymore II LED keymap.
#
# Schema flat: mappa LED index (stringa) -> brand color family
# ("lime" | "cyan" | "magenta"). Applicato identico a tutti gli endpoint
# enumerati dalla Aura SDK (Claymore II espone 2 endpoint mirror dello
# stesso hardware fisico, entrambi MA02 con 182 LED 26x7).
#
# Compatibile PowerShell 5.1 e 7+. ASCII-only.

function Import-ClaymoreKeymap {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Keymap file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json

    # Normalizza leds a hashtable per access efficiente
    $ledsHash = @{}
    if ($obj.leds) {
        foreach ($prop in $obj.leds.PSObject.Properties) {
            $ledsHash[$prop.Name] = $prop.Value
        }
    }

    return [PSCustomObject]@{
        version      = $obj.version
        device       = $obj.device
        generated_by = $obj.generated_by
        leds         = $ledsHash
    }
}

function Get-LedFamily {
    param(
        [Parameter(Mandatory=$true)]$Keymap,
        [Parameter(Mandatory=$true)][int]$LedIndex
    )

    $key = $LedIndex.ToString()
    if ($Keymap.leds.ContainsKey($key)) {
        return $Keymap.leds[$key]
    }
    return "lime"  # fallback su LIME (famiglia dominante del layout)
}
