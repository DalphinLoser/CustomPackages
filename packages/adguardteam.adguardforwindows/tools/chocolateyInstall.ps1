$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "adguardteam.adguardforwindows"
    fileType        = "exe"
    url             = "https://github.com/AdguardTeam/AdguardForWindows/releases/download/v7.15.1/AdGuard-7.15.1-.4386.exe"
    softwareName    = "AdGuard"
    silentArgs      = "/quiet"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs

