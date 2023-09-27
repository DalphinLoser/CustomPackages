$ErrorActionPreference = 'Stop';
$toolsDir   = "C:\AutoPackages\Ryujinx.release-channel-master.testavaryujinxwinx64"

$packageArgs = @{
    packageName     = "Ryujinx.release-channel-master.testavaryujinxwinx64"
    url             = "https://github.com/Ryujinx/release-channel-master/releases/download/1.1.1032/test-ava-ryujinx-1.1.1032-win_x64.zip"
    unzipLocation   = $toolsDir
}

Install-ChocolateyZipPackage @packageArgs

# Dynamically find all .exe files in the extracted directory and create shortcuts for them
$exes = Get-ChildItem -Path $toolsDir -Recurse -Include *.exe
foreach ($exe in $exes) {
    $exeName = [System.IO.Path]::GetFileNameWithoutExtension($exe.FullName)
    $shortcutPath = "$env:USERPROFILE\Desktop\$exeName.lnk"
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = $exe.FullName
    $Shortcut.Save()
}
