$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "josefnemec.playnite"
    fileType        = "exe"
    url             = "https://github.com/JosefNemec/Playnite/releases/download/10.19/Playnite1019.exe"
    softwareName    = "Playnite"
    silentArgs      = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
