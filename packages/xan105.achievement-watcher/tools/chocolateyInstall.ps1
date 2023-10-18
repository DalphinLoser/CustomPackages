$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "xan105.achievement-watcher"
    fileType        = "exe"
    url             = "https://github.com/xan105/Achievement-Watcher/releases/download/1.6.8/Achievement.Watcher.Setup.exe"
    softwareName    = "Achievement Watcher"
    silentArgs      = "/VERYSILENT /CLOSEAPPLICATIONS"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
