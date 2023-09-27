$f_installDir = "C:\AutoPackages\Ryujinx.release-channel-master.testavaryujinxwinx64"
$shortcutPath = "C:\Users\runneradmin\Desktop"

# Remove the installation directory
if (Test-Path $f_installDir) {
    Remove-Item -Path $f_installDir -Recurse -Force
}

# Remove any shortcuts related to this package from the Desktop
Get-ChildItem -Path $shortcutPath -Filter "Ryujinx.release-channel-master.testavaryujinxwinx64*.lnk" | Remove-Item -Force
