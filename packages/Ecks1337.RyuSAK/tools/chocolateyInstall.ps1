$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "ecks1337.ryusak"
    fileType        = "exe"
    url             = "https://github.com/Ecks1337/RyuSAK/releases/download/v1.6.2/RyuSAK-1.6.2.Setup.exe"
    softwareName    = "RyuSAK"
    silentArgs      = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
