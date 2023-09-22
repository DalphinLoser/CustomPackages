$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName   = "LizardByte.Sunshine"
    fileType      = "exe"
    url           = "https://github.com/LizardByte/Sunshine/releases/download/v0.20.0/sunshine-windows-installer.exe"
    softwareName  = "Sunshine"
    silentArgs    = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
