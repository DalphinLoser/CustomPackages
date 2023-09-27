$ErrorActionPreference = 'Stop';
$toolsDir   = Join-Path $(Get-ToolsLocation) $env:ChocolateyPackageName

$packageArgs = @{
    packageName     = "Ryujinx.release-channel-master.testavaryujinxwinx64"
    url             = "https://github.com/Ryujinx/release-channel-master/releases/download/1.1.1032/test-ava-ryujinx-1.1.1032-win_x64.zip"
    unzipLocation   = $toolsDir
}

Install-ChocolateyZipPackage @packageArgs
