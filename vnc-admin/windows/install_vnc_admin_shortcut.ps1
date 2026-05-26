<#
.SYNOPSIS
Installs the VNC admin desktop shortcut for driving-pi-01.

.DESCRIPTION
Idempotent installer:
1. Verifies TigerVNC Viewer is installed (offers winget install if missing)
2. Copies .vnc preset and .ico to %USERPROFILE%\.vnc\
3. Creates .lnk shortcut on Desktop pointing at vncviewer.exe + preset
4. Copies .lnk to Start Menu (so Win 11 'Pin to taskbar' is discoverable)

.NOTES
After running, pin manually: Start Menu -> right-click "Admin Pi-01" -> Pin to taskbar
#>
[CmdletBinding()]
param(
    [string]$VncViewerPath = "C:\Program Files\TigerVNC\vncviewer.exe",
    [string]$TargetDir = (Join-Path $env:USERPROFILE ".vnc"),
    [switch]$ForceWingetInstall
)

$ErrorActionPreference = "Stop"

# 1. Verify TigerVNC Viewer
if (-not (Test-Path $VncViewerPath)) {
    if ($ForceWingetInstall) {
        Write-Host "Installing TigerVNC Viewer via winget..." -ForegroundColor Cyan
        winget install --id tigervnc.tigervnc --accept-source-agreements --accept-package-agreements
        if (-not (Test-Path $VncViewerPath)) {
            throw "TigerVNC Viewer not found at $VncViewerPath after winget install"
        }
    } else {
        throw "TigerVNC Viewer not found at $VncViewerPath. Re-run with -ForceWingetInstall or install manually: winget install tigervnc.tigervnc"
    }
}
Write-Host "TigerVNC Viewer found: $VncViewerPath" -ForegroundColor Green

# 2. Copy preset and icon to ~/.vnc
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$presetSrc = Join-Path $scriptDir "driving-pi-01-admin.vnc"
$iconSrc = Join-Path $scriptDir "drivingtech-admin.ico"

foreach ($src in @($presetSrc, $iconSrc)) {
    if (-not (Test-Path $src)) {
        throw "Source file missing: $src"
    }
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
$presetDst = Join-Path $TargetDir "driving-pi-01-admin.vnc"
$iconDst = Join-Path $TargetDir "drivingtech-admin.ico"

Copy-Item $presetSrc $presetDst -Force
Copy-Item $iconSrc $iconDst -Force
Write-Host "Preset copied: $presetDst" -ForegroundColor Green
Write-Host "Icon copied:   $iconDst" -ForegroundColor Green

# 3. Create desktop .lnk
$shell = New-Object -ComObject WScript.Shell
$desktopLnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "Admin Pi-01.lnk"

$lnk = $shell.CreateShortcut($desktopLnk)
$lnk.TargetPath = $VncViewerPath
$lnk.Arguments = "`"$presetDst`""
$lnk.IconLocation = $iconDst
$lnk.WorkingDirectory = $TargetDir
$lnk.Description = "Admin desktop driving-pi-01 via VNC :5901"
$lnk.Save()
Write-Host "Desktop shortcut: $desktopLnk" -ForegroundColor Green

# 4. Copy to Start Menu (Programs\drivingtech\)
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\drivingtech"
New-Item -ItemType Directory -Force -Path $startMenuDir | Out-Null
$startMenuLnk = Join-Path $startMenuDir "Admin Pi-01.lnk"
Copy-Item $desktopLnk $startMenuLnk -Force
Write-Host "Start Menu shortcut: $startMenuLnk" -ForegroundColor Green

Write-Host "`n=== Setup complete ===" -ForegroundColor Yellow
Write-Host "Next step (manual, one-shot):" -ForegroundColor Yellow
Write-Host "  1. Open Start Menu, search 'Admin Pi-01'"
Write-Host "  2. Right-click the result -> 'Pin to taskbar'"
Write-Host "  3. Click the taskbar icon to test."
