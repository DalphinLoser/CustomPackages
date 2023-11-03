$ErrorActionPreference = 'Stop';
$toolsDir   = "C:\AutoPackages\yuzu-emu.yuzu-mainline.yuzu-windows-msvc-20231031-a0398cff0"

$packageArgs = @{
    packageName     = "yuzu-emu.yuzu-mainline.yuzu-windows-msvc-20231031-a0398cff0"
    url             = "https://github.com/yuzu-emu/yuzu-mainline/releases/download/mainline-0-1608/yuzu-windows-msvc-20231102-c1496b69d.7z"
    unzipLocation   = $toolsDir
}

Install-ChocolateyZipPackage @packageArgs

# Initialize directories for shortcuts
$desktopDir = "$env:USERPROFILE\Desktop"
$startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

# Check if directories exist, if not, create them
if (!(Test-Path -Path $desktopDir)) { New-Item -Path $desktopDir -ItemType Directory }
if (!(Test-Path -Path $startMenuDir)) { New-Item -Path $startMenuDir -ItemType Directory }

# Dynamically find all .exe files in the extracted directory and create a shortcut for the largest one
$exes = Get-ChildItem -Path $toolsDir -Recurse -Include *.exe | Sort-Object -Property Length -Descending

# Select the largest exe file
$largestExe = $exes[0]

$exeName = [System.IO.Path]::GetFileNameWithoutExtension($largestExe.Name)

# Create Desktop Shortcut
$desktopShortcutPath = Join-Path $desktopDir "$exeName.lnk"
$WshShell = New-Object -comObject WScript.Shell
$DesktopShortcut = $WshShell.CreateShortcut($desktopShortcutPath)
$DesktopShortcut.TargetPath = $largestExe.FullName
$DesktopShortcut.Save()

# Create Start Menu Shortcut
$startMenuShortcutPath = Join-Path $startMenuDir "$exeName.lnk"
$StartMenuShortcut = $WshShell.CreateShortcut($startMenuShortcutPath)
$DesktopShortcut.TargetPath = $largestExe.FullName
$StartMenuShortcut.Save()



