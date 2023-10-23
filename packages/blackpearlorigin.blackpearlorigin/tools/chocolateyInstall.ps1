$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "blackpearlorigin.blackpearlorigin"
    fileType        = "msi"
    url             = "https://github.com/BlackPearlOrigin/blackpearlorigin/releases/download/1.1.0/Black.Pearl.Origin_0.3.0_x64_en-US.msi"
    softwareName    = "Black Pearl Origin"
    silentArgs      = "/quiet /qn /norestart"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
