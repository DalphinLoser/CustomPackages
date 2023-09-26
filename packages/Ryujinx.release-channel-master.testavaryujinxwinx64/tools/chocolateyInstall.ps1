$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName   = "Ryujinx.release-channel-master.testavaryujinxwinx64"
    fileType      = "zip"
    url           = "https://github.com/Ryujinx/release-channel-master/releases/download/1.1.1030/test-ava-ryujinx-1.1.1030-win_x64.zip"
    softwareName  = "release-channel-master"
    silentArgs    = "-y"
    validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
