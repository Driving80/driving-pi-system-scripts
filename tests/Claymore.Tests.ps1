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
