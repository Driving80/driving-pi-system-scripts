# tests/Claymore.Tests.ps1
# Pester tests for Claymore II brand color layout.
# Pester 3.4 syntax, compatible with PS 5.1 and 7+

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
. (Join-Path $repoRoot "claymore-brand-colors.ps1")

Describe "Brand colors (drivingtech)" {
    It "LIME is (212, 255, 0) verbatim brand" {
        $c = Get-ClaymoreBrandColor "lime"
        $c.R | Should Be 212
        $c.G | Should Be 255
        $c.B | Should Be 0
    }

    It "CYAN is (0, 229, 255) verbatim brand" {
        $c = Get-ClaymoreBrandColor "cyan"
        $c.R | Should Be 0
        $c.G | Should Be 229
        $c.B | Should Be 255
    }

    It "MAGENTA is (255, 0, 200) verbatim brand" {
        $c = Get-ClaymoreBrandColor "magenta"
        $c.R | Should Be 255
        $c.G | Should Be 0
        $c.B | Should Be 200
    }

    It "Unknown family falls back to lime" {
        $c = Get-ClaymoreBrandColor "purple"
        $c.R | Should Be 212
        $c.G | Should Be 255
        $c.B | Should Be 0
    }

    It "Family name is case-insensitive" {
        $c1 = Get-ClaymoreBrandColor "LIME"
        $c2 = Get-ClaymoreBrandColor "lime"
        $c1.R | Should Be $c2.R
        $c1.G | Should Be $c2.G
        $c1.B | Should Be $c2.B
    }
}

. (Join-Path $repoRoot "claymore-keymap-loader.ps1")

Describe "Keymap loader" {
    $fixturePath = Join-Path $here "fixtures\sample-keymap.json"

    It "Carica e parse JSON valido senza errore" {
        $km = Import-ClaymoreKeymap -Path $fixturePath
        $km | Should Not BeNullOrEmpty
    }

    It "Espone .leds come hashtable con LED index (stringa) come chiave" {
        $km = Import-ClaymoreKeymap -Path $fixturePath
        $km.leds.ContainsKey("0") | Should Be $true
        $km.leds.Count | Should Be 4
    }

    It "Get-LedFamily restituisce family corretta per LED noto nella fixture" {
        $km = Import-ClaymoreKeymap -Path $fixturePath
        Get-LedFamily -Keymap $km -LedIndex 0 | Should Be "magenta"
        Get-LedFamily -Keymap $km -LedIndex 1 | Should Be "cyan"
        Get-LedFamily -Keymap $km -LedIndex 3 | Should Be "lime"
    }

    It "Get-LedFamily fa fallback su lime per LED non mappato" {
        $km = Import-ClaymoreKeymap -Path $fixturePath
        Get-LedFamily -Keymap $km -LedIndex 99999 | Should Be "lime"
    }

    It "Solleva errore se file inesistente" {
        { Import-ClaymoreKeymap -Path "C:\does\not\exist.json" } | Should Throw "Keymap file not found"
    }
}
