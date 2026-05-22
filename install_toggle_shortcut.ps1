# install_toggle_shortcut.ps1 -- Create Desktop shortcut for toggle_audio_route.ps1.
#
# Creates "Toggle Audio Route.lnk" on the user's Desktop pointing at
# toggle_audio_route.ps1, with the "Run as Administrator" flag set so a single
# click triggers a UAC prompt then runs elevated.
#
# Pin the resulting .lnk to the taskbar manually (right-click -> Pin to taskbar).

[CmdletBinding()]
param(
    [string]$ShortcutName = 'Toggle Audio Route',
    [string]$RepoRoot     = $PSScriptRoot
)

if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }
$ScriptPath  = Join-Path $RepoRoot 'toggle_audio_route.ps1'
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$LnkPath     = Join-Path $DesktopPath "$ShortcutName.lnk"

if (-not (Test-Path $ScriptPath)) {
    Write-Host "[FAIL] Target script not found: $ScriptPath" -ForegroundColor Red
    exit 1
}

Write-Host "Creating shortcut:" -ForegroundColor Cyan
Write-Host "  $LnkPath"
Write-Host "Target script:"
Write-Host "  $ScriptPath"

$WshShell = New-Object -ComObject WScript.Shell
$sc = $WshShell.CreateShortcut($LnkPath)
$sc.TargetPath       = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
$sc.WorkingDirectory = $RepoRoot
$sc.IconLocation     = 'C:\Windows\System32\SndVol.exe,0'
$sc.Description      = 'Toggle audio route between PC (Focusrite) and Pi (HiFi streaming)'
$sc.WindowStyle      = 7   # Minimized
$sc.Save()

# Set the "Run as Administrator" flag (byte 0x15, bit 0x20) inside the .lnk.
$bytes = [System.IO.File]::ReadAllBytes($LnkPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20
[System.IO.File]::WriteAllBytes($LnkPath, $bytes)

Write-Host "[OK] Shortcut created with 'Run as Administrator' flag set." -ForegroundColor Green
Write-Host ""
Write-Host "Next step:" -ForegroundColor Yellow
Write-Host "  Right-click the Desktop shortcut -> 'Pin to taskbar'"
