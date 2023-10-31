$toolsDir = "C:\AutoPackages\yuzu-emu.yuzu-mainline.yuzu-windows-msvc-20231031-a0398cff0"
$shortcutPath = "$env:USERPROFILE\Desktop"

# Initialize directories for shortcuts
$desktopDir = "$env:USERPROFILE\Desktop"
$startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

# Dynamically find all .exe files in the extracted directory and create shortcuts for them
$exes = Get-ChildItem -Path $toolsDir -Recurse -Include *.exe
foreach ($exe in $exes) {
    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($exe.Name)
    
    # Remove Desktop Shortcut
    $desktopShortcutPath = Join-Path $desktopDir "$exeName.lnk"
    Remove-Item "$desktopShortcutPath" -Force
    
    # Remove Start Menu Shortcut
    $startMenuShortcutPath = Join-Path $startMenuDir "$exeName.lnk"
    Remove-Item "$startMenuShortcutPath" -Force
}
# Remove the installation directory
if (Test-Path $toolsDir) {
    Remove-Item -Path $toolsDir -Recurse -Force
}
