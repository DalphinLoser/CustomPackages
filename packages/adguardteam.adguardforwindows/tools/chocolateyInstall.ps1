$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "adguardteam.adguardforwindows"
    fileType        = "exe"
    url             = "https://github.com/AdguardTeam/AdguardForWindows/releases/download/v7.15.0/AdGuard-7.15-.4385.exe"
    softwareName    = "AdGuard"
    silentArgs      = "/quiet"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
