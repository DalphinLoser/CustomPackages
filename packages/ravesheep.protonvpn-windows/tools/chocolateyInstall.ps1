$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "ravesheep.protonvpn-windows"
    fileType        = "exe"
    url             = "https://github.com/ravesheep/ProtonVPN-windows/releases/download/3.2.4/ProtonVPN_v3.2.4.exe"
    softwareName    = "Proton VPN"
    silentArgs      = "/VERYSILENT /NORESTART"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
