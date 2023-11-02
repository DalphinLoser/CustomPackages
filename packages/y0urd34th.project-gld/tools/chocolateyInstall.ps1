$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "y0urd34th.project-gld"
    fileType        = "exe"
    url             = "https://github.com/Y0URD34TH/Project-GLD/releases/download/Update-V2.07/Project-GLD.exe"
    softwareName    = "Project-GLD"
    silentArgs      = "/S /s /Q /q /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs

