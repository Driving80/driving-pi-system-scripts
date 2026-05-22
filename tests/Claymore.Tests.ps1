# tests/Claymore.Tests.ps1
# Pester tests for Claymore II brand color layout.
# Pester 3.4 syntax, compatible with PS 5.1 and 7+

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $here
. (Join-Path $repoRoot "claymore-brand-colors.ps1")
. (Join-Path $repoRoot "claymore-keys-mapping.ps1")

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

Describe "Keys mapping (Code -> family lookup)" {
    It "Modifier codes return magenta" {
        Get-ClaymoreKeyFamily -Code 14  | Should Be "magenta"  # Backspace
        Get-ClaymoreKeyFamily -Code 16  | Should Be "magenta"  # Tab
        Get-ClaymoreKeyFamily -Code 28  | Should Be "magenta"  # Enter
        Get-ClaymoreKeyFamily -Code 29  | Should Be "magenta"  # Left Ctrl
        Get-ClaymoreKeyFamily -Code 30  | Should Be "magenta"  # CapsLock
        Get-ClaymoreKeyFamily -Code 44  | Should Be "magenta"  # Left Shift
        Get-ClaymoreKeyFamily -Code 54  | Should Be "magenta"  # Right Shift
        Get-ClaymoreKeyFamily -Code 56  | Should Be "magenta"  # Left Alt
        Get-ClaymoreKeyFamily -Code 57  | Should Be "magenta"  # Spacebar
        Get-ClaymoreKeyFamily -Code 69  | Should Be "magenta"  # NumLock
        Get-ClaymoreKeyFamily -Code 156 | Should Be "magenta"  # Numpad Enter
        Get-ClaymoreKeyFamily -Code 157 | Should Be "magenta"  # Right Ctrl
        Get-ClaymoreKeyFamily -Code 184 | Should Be "magenta"  # Right Alt
        Get-ClaymoreKeyFamily -Code 219 | Should Be "magenta"  # Left Win
        Get-ClaymoreKeyFamily -Code 221 | Should Be "magenta"  # Menu
        Get-ClaymoreKeyFamily -Code 256 | Should Be "magenta"  # Fn
    }

    It "Nav cluster codes return magenta (moved from cyan 2026-05-22)" {
        Get-ClaymoreKeyFamily -Code 210 | Should Be "magenta"  # Ins
        Get-ClaymoreKeyFamily -Code 211 | Should Be "magenta"  # Del
        Get-ClaymoreKeyFamily -Code 199 | Should Be "magenta"  # Home
        Get-ClaymoreKeyFamily -Code 207 | Should Be "magenta"  # End
        Get-ClaymoreKeyFamily -Code 201 | Should Be "magenta"  # PgUp
        Get-ClaymoreKeyFamily -Code 209 | Should Be "magenta"  # PgDn
    }

    It "F-row codes return cyan" {
        59..68 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "cyan" }
        Get-ClaymoreKeyFamily -Code 87 | Should Be "cyan"  # F11
        Get-ClaymoreKeyFamily -Code 88 | Should Be "cyan"  # F12
    }

    It "Macro M1-M5 codes return cyan" {
        Get-ClaymoreKeyFamily -Code 1  | Should Be "cyan"  # M1
        Get-ClaymoreKeyFamily -Code 41 | Should Be "cyan"  # M2
        Get-ClaymoreKeyFamily -Code 15 | Should Be "cyan"  # M3
        Get-ClaymoreKeyFamily -Code 58 | Should Be "cyan"  # M4
        Get-ClaymoreKeyFamily -Code 42 | Should Be "cyan"  # M5
    }

    It "System cluster codes return cyan (PrtSc/ScrLk/Pause stay cyan per feedback)" {
        Get-ClaymoreKeyFamily -Code 183 | Should Be "cyan"  # PrtSc
        Get-ClaymoreKeyFamily -Code 70  | Should Be "cyan"  # ScrLk
        Get-ClaymoreKeyFamily -Code 197 | Should Be "cyan"  # Pause
    }

    It "Arrow codes return lime (moved from cyan 2026-05-22 - treated as content navigation)" {
        Get-ClaymoreKeyFamily -Code 200 | Should Be "lime"  # Up
        Get-ClaymoreKeyFamily -Code 203 | Should Be "lime"  # Left
        Get-ClaymoreKeyFamily -Code 205 | Should Be "lime"  # Right
        Get-ClaymoreKeyFamily -Code 208 | Should Be "lime"  # Down
    }

    It "Numpad operators return cyan; numpad numerics return lime" {
        # Operators
        Get-ClaymoreKeyFamily -Code 181 | Should Be "cyan"  # /
        Get-ClaymoreKeyFamily -Code 55  | Should Be "cyan"  # *
        Get-ClaymoreKeyFamily -Code 74  | Should Be "cyan"  # -
        Get-ClaymoreKeyFamily -Code 78  | Should Be "cyan"  # +
        # Numerics
        71..73 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "lime" }  # 7,8,9
        75..77 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "lime" }  # 4,5,6
        79..83 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "lime" }  # 1,2,3,0,.
    }

    It "Number row + letters + punctuation return lime" {
        # Number row codes 2-13 (` 1 2 3 4 5 6 7 8 9 0 - =)
        2..13 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "lime" }
        # QWERTY row codes 17-27 + 43 (\)
        17..27 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "lime" }
        Get-ClaymoreKeyFamily -Code 43 | Should Be "lime"
        # ASDF row codes 31-40
        31..40 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "lime" }
        # ZXCV row codes 45-53
        45..53 | ForEach-Object { Get-ClaymoreKeyFamily -Code $_ | Should Be "lime" }
    }

    It "Multimedia top-right (257-259) return cyan" {
        Get-ClaymoreKeyFamily -Code 257 | Should Be "cyan"
        Get-ClaymoreKeyFamily -Code 258 | Should Be "cyan"
        Get-ClaymoreKeyFamily -Code 259 | Should Be "cyan"
    }

    It "Unknown code falls back to lime" {
        Get-ClaymoreKeyFamily -Code 9999 | Should Be "lime"
        Get-ClaymoreKeyFamily -Code 0    | Should Be "lime"
    }
}

Describe "Brand layout apply (with mock SDK)" {
    BeforeEach {
        $script:mockApplyCount = 0
        $script:mockKeysWritten = @()
        $script:mockLightsWritten = @()

        $mockDevice = New-Object PSObject -Property @{
            Name = "MA02"
            Keys = @()
            Lights = @()
        }
        # 3 mock Keys con vari Code: 14 (Bksp=magenta), 19 (E=lime), 59 (F1=cyan)
        $mockKeyCodes = @(14, 19, 59)
        foreach ($code in $mockKeyCodes) {
            $mockKey = New-Object PSObject -Property @{
                Code = $code; Red = 0; Green = 0; Blue = 0
            }
            $mockDevice.Keys += $mockKey
        }
        # 5 mock Lights (per il background fallback)
        for ($i = 0; $i -lt 5; $i++) {
            $mockLight = New-Object PSObject -Property @{
                Red = 0; Green = 0; Blue = 0
            }
            $mockDevice.Lights += $mockLight
        }
        Add-Member -InputObject $mockDevice -MemberType ScriptMethod -Name Apply -Value {
            $script:mockApplyCount++
            for ($i = 0; $i -lt $this.Lights.Count; $i++) {
                $script:mockLightsWritten += @{
                    Index = $i; R = $this.Lights[$i].Red; G = $this.Lights[$i].Green; B = $this.Lights[$i].Blue
                }
            }
            for ($i = 0; $i -lt $this.Keys.Count; $i++) {
                $script:mockKeysWritten += @{
                    Code = $this.Keys[$i].Code; R = $this.Keys[$i].Red; G = $this.Keys[$i].Green; B = $this.Keys[$i].Blue
                }
            }
        } -Force
        $script:mockDevice = $mockDevice
    }

    It "Set-DeviceBrandColors applies LIME to all Lights as background" {
        . (Join-Path $repoRoot "claymore-brand-layout.ps1")
        Set-DeviceBrandColors -Device $script:mockDevice

        $script:mockApplyCount | Should Be 1
        $script:mockLightsWritten.Count | Should Be 5
        foreach ($l in $script:mockLightsWritten) {
            $l.R | Should Be 212  # lime
            $l.G | Should Be 255
            $l.B | Should Be 0
        }
    }

    It "Set-DeviceBrandColors applies family colors to Keys by Code lookup" {
        . (Join-Path $repoRoot "claymore-brand-layout.ps1")
        Set-DeviceBrandColors -Device $script:mockDevice

        # mock Keys: code 14 (Bksp=magenta), code 19 (E=lime), code 59 (F1=cyan)
        $script:mockKeysWritten.Count | Should Be 3
        # Code 14 -> magenta (255,0,200)
        $key14 = $script:mockKeysWritten | Where-Object { $_.Code -eq 14 } | Select-Object -First 1
        $key14.R | Should Be 255
        $key14.G | Should Be 0
        $key14.B | Should Be 200
        # Code 19 -> lime (212,255,0)
        $key19 = $script:mockKeysWritten | Where-Object { $_.Code -eq 19 } | Select-Object -First 1
        $key19.R | Should Be 212
        $key19.G | Should Be 255
        $key19.B | Should Be 0
        # Code 59 -> cyan (0,229,255)
        $key59 = $script:mockKeysWritten | Where-Object { $_.Code -eq 59 } | Select-Object -First 1
        $key59.R | Should Be 0
        $key59.G | Should Be 229
        $key59.B | Should Be 255
    }
}
