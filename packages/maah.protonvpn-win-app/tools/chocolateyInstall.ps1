$ErrorActionPreference = 'Stop';

$packageArgs = @{
    packageName     = "maah.protonvpn-win-app"
    fileType        = "exe"
    url             = "https://github.com/maah/ProtonVPN-win-app/releases/download/3.2.4/ProtonVPN_v3.2.4.exe"
    softwareName    = "Proton VPN"
    silentArgs      = "/VERYSILENT /NORESTART"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
