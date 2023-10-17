$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "obsidianmd.obsidian-releases"
    fileType        = "exe"
    url             = "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.4.16/Obsidian.1.4.14-32.exe"
    softwareName    = "Obsidian"
    silentArgs      = "/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs

