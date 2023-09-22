$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName   = "ProtonVPN.win-app"
    fileType      = "exe"
    url           = "https://github.com/ProtonVPN/win-app/releases/download/3.1.1/ProtonVPN_v3.1.1.exe"
    softwareName  = "win-app"
    silentArgs    = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
