$ErrorActionPreference = 'Stop';
$toolsDir   = Join-Path $(Get-ToolsLocation) $env:ChocolateyPackageName

$packageArgs = @{
    packageName     = "LizardByte.Sunshine"
    url             = "https://github.com/LizardByte/Sunshine/releases/download/v0.20.0/sunshine-debuginfo-win32.zip"
    unzipLocation   = $toolsDir
}

Install-ChocolateyZipPackage @packageArgs
