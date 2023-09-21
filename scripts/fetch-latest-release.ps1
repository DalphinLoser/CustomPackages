$ErrorActionPreference = 'Stop'

# Function to print a log section header
Function Write-LogHeader {
    param (
        [string]$Message
    )
    Write-Host "`n=== [ $Message ] ===`n"
}

Write-LogHeader "Initializing Script"

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
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet('exe', 'msi', '7z', 'zip', 'msu', 'msp')]
        [string]$fileType
    )

    Write-Host "Determining silent installation arguments for $fileType..."

    $silentArgs = ''
    
    switch ($fileType) {
        'exe' { 
            $silentArgs = '/SP- /VERYSILENT /NORESTART'  # Silent installation
        }
        'msi' { 
            $silentArgs = '/qn /norestart'  # Quiet mode, no user input, no restart
        }
        '7z'  { 
            $silentArgs = '-y'  # Assume yes on all queries
        }
        'zip' { 
            $silentArgs = '-y'  # Assume yes on all queries (Note: Not standard for ZIP)
        }
        'msu' { 
            $silentArgs = '/quiet /norestart'  # Quiet mode, no restart
        }
        'msp' { 
            $silentArgs = '/qn /norestart'  # Quiet mode, no restart
        }
        default { 
            Write-Error "Unsupported file type: $fileType"
            return ''
        }
    }

    Write-Host "Silent installation arguments for {$fileType}: $silentArgs"
    return $silentArgs
}


Write-LogHeader "Fetching Latest Release Info"

# Initialize repository URL
$repo = "https://github.com/maah/ProtonVPN-win-app"

# Fetch latest release information
$latestReleaseInfo = Get-LatestReleaseInfo -repo $repo
if ($null -eq $latestReleaseInfo) {
    exit 1
}

write-host "Latest Release URL: $latestReleaseUrl"

Write-LogHeader "Selecting Asset"

# Select the best asset based on supported types
$selectedAsset = Select-Asset -assets $latestReleaseInfo.assets
if ($null -eq $selectedAsset) {
    exit 1
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

# Explicitly set the tools directory
$toolsDir = Join-Path (Get-Location) "tools"

# Create the tools directory
New-Item -Path $toolsDir -ItemType "directory" -Force

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
    <packageSourceUrl>$url</packageSourceUrl>
    <licenseUrl>$repo/blob/master/LICENSE</licenseUrl>
    <tags>protonvpn vpn</tags>
  </metadata>
</package>
"@
# Create a nuspec file for the package
$nuspecPath = Join-Path $toolsDir "$githubRepo.nuspec"
Out-File -InputObject $nuspec -FilePath $nuspecPath -Encoding utf8
Write-Host "Nuspec file created at: $nuspecPath"

$installScriptContent = @"
$ErrorActionPreference = 'Stop';

# Prepare Chocolatey package arguments
$packageArgs = @{
  packageName   = $packageName
  unzipLocation = $toolsDir
  fileType      = $fileType
  url           = $url
  softwareName  = "$githubRepo*"
  silentArgs    = $silentArgs
  validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
"@
Set-Location -Path $toolsDir
Out-File -InputObject $installScriptContent -FilePath ".\chocolateyInstall.ps1" -Encoding utf8

Write-LogHeader "Creating Chocolatey Package"
Write-Host "Tools Directory: $toolsDir"
Write-Host "Nuspec Path: $nuspecPath"
Write-Host "Working Directory: $(Get-Location)"

# Check for Nuspec File
if (-not (Test-Path $nuspecPath)) {
    Write-Error "Nuspec file not found at: $nuspecPath"
    exit 1
}
else {
    Write-Host "Nuspec file found at: $nuspecPath"
}

# Create Chocolatey package
try {
    # Move to the directory containing the .nuspec file
    Set-Location -Path $toolsDir
    write-host "Moved to: $(Get-Location)"
    # Create the Chocolatey package
    Write-Host "Creating Chocolatey package..."
    choco pack $nuspecPath -Force -Verbose
} catch {
    Write-Error "Failed to create Chocolatey package."
    exit 1
}
