$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "y0urd34th.project-gld"
    fileType        = "exe"
    url             = "https://github.com/Y0URD34TH/Project-GLD/releases/download/Hotfix-V2.02/Project-GLD.exe"
    softwareName    = "Project-GLD"
    silentArgs      = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
