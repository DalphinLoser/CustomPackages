$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName   = "ProtonVPN_v"
    fileType      = "exe"
    url           = "https://github.com/maah/ProtonVPN-win-app/releases/download/3.1.1/ProtonVPN_v3.1.1.exe"
    softwareName  = "ProtonVPN_v"
    silentArgs    = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
