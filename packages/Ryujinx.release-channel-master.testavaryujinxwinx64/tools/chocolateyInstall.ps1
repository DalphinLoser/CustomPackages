$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "Ryujinx.release-channel-master.testavaryujinxwinx64"
    url             = "https://github.com/Ryujinx/release-channel-master/releases/download/1.1.1031/test-ava-ryujinx-1.1.1031-win_x64.zip"
    unzipLocation = "C:\Users\runneradmin\\AutoPackages\\Ryujinx.release-channel-master.testavaryujinxwinx64"
}

Install-ChocolateyZipPackage @packageArgs
