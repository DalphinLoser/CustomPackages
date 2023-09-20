$ErrorActionPreference = 'Stop'

Function Get-LatestReleaseInfo {
    param (
        [string]$repo
    )
    $githubUser = $repo.Split('/')[3]
    $githubRepo = $repo.Split('/')[4]
    $latestReleaseUrl = "https://api.github.com/repos/${githubUser}/${githubRepo}/releases/latest"

    # Validate constructed URL
    if ($latestReleaseUrl -notmatch "https://api.github.com/repos/.*/.*/releases/latest") {
        Write-Error "Invalid GitHub release URL: $latestReleaseUrl"
        return $null
    }
    
    # Fetch and parse latest release data
    $latestReleaseInfo = (Invoke-WebRequest -Uri $latestReleaseUrl).Content | ConvertFrom-Json
    
    # Validation check for the API call
    if ($null -eq $latestReleaseInfo -or $latestReleaseInfo.PSObject.Properties.Name -notcontains 'tag_name') {
        Write-Error "Failed to fetch valid release information from GitHub."
        return $null
    }

    return $latestReleaseInfo
}

Function Select-Asset {
    param (
        [array]$assets
    )
    $supportedTypes = @('exe', 'msi', '7z', 'zip', 'msu', 'msp')
    $selectedAsset = $assets | Where-Object { $_.name -match '\.([^.]+)$' } | Sort-Object { $supportedTypes.IndexOf($matches[1]) } | Select-Object -First 1

    if ($null -eq $selectedAsset) {
        Write-Error "No suitable asset (.exe, .msi, .zip, .7z, .msu, .msp) found for the latest release."
        return $null
    }

    return $selectedAsset
}

Function Get-SilentArgs {
    param (
        [string]$fileType
    )
    switch ($fileType) {
        'exe' { return '/S' }
        'msi' { return '/qn /norestart' }
        '7z'  { return '-y' }
        'zip' { return '-y' }
        'msu' { return '/quiet /norestart' }
        'msp' { return '/qn /norestart' }
        default { return '' }
    }
}

# Initialize repository URL
$repo = "https://github.com/maah/ProtonVPN-win-app"

# Fetch latest release information
$latestReleaseInfo = Get-LatestReleaseInfo -repo $repo
if ($null -eq $latestReleaseInfo) {
    return
}

# Select the best asset based on supported types
$selectedAsset = Select-Asset -assets $latestReleaseInfo.assets
if ($null -eq $selectedAsset) {
    return
}

# Determine file type from asset name
$fileType = if ($selectedAsset.name -match '\.(exe|msi|zip|7z|msu|msp)$') { $matches[1] } else { $null }


# Determine silent installation arguments based on file type
$silentArgs = Get-SilentArgs -fileType $fileType

# Extract package metadata
$packageName = $latestReleaseInfo.name
$version = $latestReleaseInfo.tag_name
$author = $latestReleaseInfo.author.login
$description = $latestReleaseInfo.body -replace "\r\n", " "
$url = $selectedAsset.browser_download_url

Write-Host "Download URL: $url"

# Prepare Chocolatey package arguments
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$packageArgs = @{
  packageName   = $packageName
  unzipLocation = $toolsDir
  fileType      = $fileType
  url           = $url
  softwareName  = "$packageName*"
  validExitCodes= @(0, 3010, 1641)
  silentArgs    = $silentArgs
}

Write-Host "Package arguments: $packageArgs"

# Create a nuspec file for the package
$nuspec = @"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>$packageName</id>
    <title>$packageName</title>
    <version>$version</version>
    <authors>$author</authors>
    <owners>$author</owners>
    <description>$description</description>
    <projectUrl>$repo</projectUrl>
    <packageSourceUrl>$repo</packageSourceUrl>
    <licenseUrl>$repo/blob/master/LICENSE</licenseUrl>
    <tags>protonvpn vpn</tags>
  </metadata>
</package>
"@
Out-File -InputObject $nuspec -FilePath "./scripts/$packageName.nuspec" -Encoding utf8

Write-Host "Nuspec file: $packageName.nuspec"

# Create a Chocolatey package (uncomment when ready to use)
New-ChocolateyPackage @packageArgs -Force -Verbose

