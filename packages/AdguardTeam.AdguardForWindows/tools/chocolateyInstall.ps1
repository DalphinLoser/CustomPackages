$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "AdguardTeam.AdguardForWindows"
    fileType        = "exe"
    url             = "https://github.com/AdguardTeam/AdguardForWindows/releases/download/v7.14.0/AdGuard-7.14.exe"
    softwareName    = "AdguardTeam"
    silentArgs      = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
