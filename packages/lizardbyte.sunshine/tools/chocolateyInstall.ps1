$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "lizardbyte.sunshine"
    fileType        = "exe"
    url             = "https://github.com/LizardByte/Sunshine/releases/download/v0.21.0/sunshine-windows-installer.exe"
    softwareName    = "Sunshine"
    silentArgs      = "/S /CLOSEAPPLICATIONS"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
