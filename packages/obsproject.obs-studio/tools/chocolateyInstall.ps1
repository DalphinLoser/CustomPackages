$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "obsproject.obs-studio"
    fileType        = "exe"
    url             = "https://github.com/obsproject/obs-studio/releases/download/29.1.3/OBS-Studio-29.1.3-Full-Installer-x64.exe"
    softwareName    = "OBS Studio"
    silentArgs      = "/S"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
