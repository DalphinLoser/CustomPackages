$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "obsidianmd.obsidian-releases"
    fileType        = "exe"
    url             = "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.4.16/Obsidian.1.4.16-arm64.exe"
    softwareName    = "Obsidian"
    silentArgs      = "/S"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
