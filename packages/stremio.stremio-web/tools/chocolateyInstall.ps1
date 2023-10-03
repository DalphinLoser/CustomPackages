$ErrorActionPreference = 'Stop';
$toolsDir   = "C:\AutoPackages\stremio.stremio-web"

$packageArgs = @{
    packageName     = "stremio.stremio-web"
    url             = "https://github.com/Stremio/stremio-web/releases/download/v5.0.0-beta.0/stremio-web.zip"
    unzipLocation   = $toolsDir
}

Install-ChocolateyZipPackage @packageArgs

# Initialize directories for shortcuts
$desktopDir = "$env:USERPROFILE\Desktop"
$startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

# Check if directories exist, if not, create them
if (!(Test-Path -Path $desktopDir)) { New-Item -Path $desktopDir -ItemType Directory }
if (!(Test-Path -Path $startMenuDir)) { New-Item -Path $startMenuDir -ItemType Directory }

# Dynamically find all .exe files in the extracted directory and create shortcuts for them
$exes = Get-ChildItem -Path $toolsDir -Recurse -Include *.exe
foreach ($exe in $exes) {
    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($exe.Name)
    
    # Create Desktop Shortcut
    $desktopShortcutPath = Join-Path $desktopDir "$exeName.lnk"
    $WshShell = New-Object -comObject WScript.Shell
    $DesktopShortcut = $WshShell.CreateShortcut($desktopShortcutPath)
    $DesktopShortcut.TargetPath = $exe.FullName
    $DesktopShortcut.Save()
    
    # Create Start Menu Shortcut
    $startMenuShortcutPath = Join-Path $startMenuDir "$exeName.lnk"
    $StartMenuShortcut = $WshShell.CreateShortcut($startMenuShortcutPath)
    $DesktopShortcut.TargetPath = $exe.FullName
    $StartMenuShortcut.Save()
}
