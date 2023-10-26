$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "fennyfatal.ryusak"
    fileType        = "exe"
    url             = "https://github.com/FennyFatal/RyuSAK/releases/download/v1.6.3-experimental/RyuSAK-1.6.3.Setup.exe"
    softwareName    = "RyuSAK"
    silentArgs      = "/S /s /Q /q /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
