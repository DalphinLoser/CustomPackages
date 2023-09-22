$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName   = "Black.Pearl.Origin_0.3.0_x64_en-US"
    fileType      = "msi"
    url           = "https://github.com/BlackPearlOrigin/blackpearlorigin/releases/download/1.1.0/Black.Pearl.Origin_0.3.0_x64_en-US.msi"
    softwareName  = "blackpearlorigin"
    silentArgs    = "/quiet /qn /norestart"
    validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
