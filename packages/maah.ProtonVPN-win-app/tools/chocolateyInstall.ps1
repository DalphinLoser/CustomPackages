$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "maah.protonvpn-win-app"
    fileType        = "exe"
    url             = "https://github.com/maah/ProtonVPN-win-app/releases/download/3.2.1/ProtonVPN_v3.2.1.exe"
    softwareName    = "ProtonVPN"
    silentArgs      = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
