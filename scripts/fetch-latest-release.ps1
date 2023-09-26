param (
    [string]$repoUrl
)
$ErrorActionPreference = 'Stop'
###################################################################################################
#region Functions
function Format-Json {
    # Function to format and print JSON recursively, allowing for nested lists
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$json,
        
        [Parameter(Mandatory=$false)]
        [int]$depth = 0
    )

    # Color scale from dark blue to light blue
    $colorScale = @('DarkBlue', 'Blue', 'Yellow')

    if ($null -eq $json) {
        Write-Host "Received null json object."
        return
    }

    $currentColor = $colorScale[$depth % $colorScale.Length]

    if ($json -is [pscustomobject]) {
        $properties = $json.PSObject.Properties
        if ($null -eq $properties) {
            Write-Host "No properties found in object."
            return
        }

        $properties | ForEach-Object {
            if ($null -eq $_) {
                Write-Host "Null property found."
                return
            }

            Write-Host $_.Name -ForegroundColor $currentColor -NoNewline
            if ($_.Value -is [pscustomobject] -or $_.Value -is [System.Collections.ArrayList]) {
                Write-Host ":"
                Format-Json -json $_.Value -depth ($depth + 1)
            } else {
                Write-Host ": $($_.Value)" -ForegroundColor White
            }
        }
    } elseif ($json -is [System.Collections.ArrayList]) {
        $json | ForEach-Object {
            if ($_ -is [pscustomobject] -or $_ -is [System.Collections.ArrayList]) {
                Format-Json -json $_ -depth ($depth + 1)
            } else {
                Write-Host $_ -ForegroundColor White
            }
        }
    } else {
        Write-Host "Unsupported type: $($json.GetType().FullName)"
    }
}
function Write-LogHeader {
    param (
        [string]$Message
    )
    Write-Host "`n=== [ $Message ] ===`n" -ForegroundColor Magenta
}
function Select-Asset {
    param (
        [array]$p_assets,
        [Parameter(Mandatory=$false)]
        [string]$p_assetName
    )

    # Validation check for the assets
    $f_supportedTypes = $acceptedExtensions

    # Validate that assets is not null or empty
    if ($null -eq $p_assets -or $p_assets.Count -eq 0) {
        Write-Error "No assets found for the latest release. Assets is Null or Empty"
        exit 1
    }

    # If an asset name is providid, select the asset with that name. If not, select the first asset with a supported type.
    if (-not [string]::IsNullOrEmpty($p_assetName)) {
        Write-Host "Selecting asset with name: `"$p_assetName`""
        $f_selectedAsset = $p_assets | Where-Object { $_.name -eq $p_assetName }
        # If there is no match for the asset name, throw an error
        if ($null -eq $f_selectedAsset) {
            # This is messy but works. Should be cleaned up.
            # Try checking for the asset in all releases
            Write-Host "No asset found in latest release with name: `"$p_assetName`". Checking all releases..."
            $releasesUrl = "$baseRepoUrl/releases"
            $releasesInfo = (Invoke-WebRequest -Uri $releasesUrl).Content | ConvertFrom-Json
            foreach ($release in $releasesInfo) {
                $f_selectedAsset = $release.assets | Where-Object { $_.name -eq $p_assetName }
                if ($null -ne $f_selectedAsset) {
                    Write-Host "Asset found in release: $($release.tag_name)"
                    break
                }
            }
            # If there is still no match, throw an error
            if ($null -eq $f_selectedAsset) {
                Write-Error "No asset found with name: `"$p_assetName`""
                exit 1
            }
        }
    } else {
        Write-Host "Selecting first asset with supported type: $f_supportedTypes"
        $f_selectedAsset = $p_assets | 
            Where-Object { 
                if ($_.name -match '\.([^.]+)$') {
                    return $f_supportedTypes -contains $matches[1]
                }
                return $false
            } |
            Sort-Object { $f_supportedTypes.IndexOf($matches[1]) } |
            Select-Object -First 1
    }

    # Validation check for the selected asset
    if ($null -eq $f_selectedAsset) {
        Write-Error "No suitable asset found for the latest release. Selected Asset is Null"
        exit 1
    }

    return $f_selectedAsset
}
function ConvertTo-SanitizedNugetVersion {
    param (
        [string]$p_rawVersion
    )
    
    # Step 1: Trim leading and trailing whitespaces and remove non-numeric leading characters
    $f_cleanVersion = $p_rawVersion.Trim()
    $f_cleanVersion = $f_cleanVersion -replace '^[^0-9]*', ''
    
    # Step 2: Split into numeric and label parts
    $f_numeric = if ($f_cleanVersion -match '^[0-9.]+') { $matches[0] } else { '' }
    $f_label = if ($f_cleanVersion -match '[^-+0-9.]+([-.+].*)$') { $matches[1] } else { '' }
    
    # Step 3: Sanitize numeric part to only include numerals and periods
    $f_numeric = $f_numeric -replace '[^0-9.]', ''
    
    # Step 4: Sanitize labels to only include alphanumerics and hyphens
    $f_label = $f_label -replace '[^-a-zA-Z0-9.+]', ''
    
    # Step 5: Reassemble the version string
    $f_sanitizedVersion = "$f_numeric$f_label"
    
    # Return the sanitized version string
    return $f_sanitizedVersion
}
function Get-Filetype {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_fileName,
        [string[]]$p_acceptedExtensions = $acceptedExtensions
    )
    
    $found = $false

    # Iterate through the accepted extensions and check if the file name ends with one of them
    foreach ($ext in $p_acceptedExtensions) {
        if ($p_fileName.EndsWith($ext, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $true
            break
        }
    }
    
    if ($found) {
        # The file name ends with one of the accepted extensions
        Write-Host "File name ends with an accepted extension."
        # return the extension that was found
        return $ext
    } else {
        Write-Error "Unsupported file type: $p_fileName"
        exit 1
    }
}
function Get-SilentArgs {
    # This is admittedly not a great way to handle this.
    # Maybe run /help or /? on the installer and parse the output?
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_fileType
    )

    $f_silentArgs = ''
    
    switch ($p_fileType) {
        'exe' { 
            $f_silentArgs = '/S /s /Q /q /SP- /VERYSILENT /NORESTART /quiet /silent'  # Silent installation
        }
        'msi' { 
            $f_silentArgs = '/quiet /qn /norestart'  # Quiet mode, no user input, no restart
        }
        'zip' { 
            $f_silentArgs = '-y'  # Assume yes on all queries (Note: Not standard for ZIP)
        }
        <# These Types Are Not Currently Supported
        '7z'  { 
            $f_silentArgs = '-y'  # Assume yes on all queries
        }        
        'msu' { 
            $f_silentArgs = '/quiet /norestart'  # Quiet mode, no restart
        }
        'msp' { 
            $f_silentArgs = '/qn /norestart'  # Quiet mode, no restart
        }
        #>
        default { 
            Write-Error "Unsupported file type: $p_fileType"
            exit 1
        }
    }

    return $f_silentArgs
}
function Get-LatestReleaseInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_baseRepoUrl
    )

    # Fetch rate limit information
    #$rateLimitInfo = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit'
    #Write-Host "Rate Limit Remaining: " -NoNewline -ForegroundColor DarkRed
    #Write-Host $rateLimitInfo

    # Fetch and parse latest release data
    $f_latestReleaseInfo = (Invoke-WebRequest -Uri $p_baseRepoUrl).Content | ConvertFrom-Json
    
    # Validation check for the API call
    if ($null -eq $f_latestReleaseInfo -or $f_latestReleaseInfo.PSObject.Properties.Name -notcontains 'tag_name') {
        Write-Error "Failed to fetch valid release information from GitHub. URL used: $p_baseRepoUrl"
        exit 1
    }
    #Write-Host "Latest Release Info: " -NoNewline -ForegroundColor DarkYellow
    #Format-Json -json $f_latestReleaseInfo
    Write-Host "Returning latest release info for $($f_latestReleaseInfo.tag_name)" -ForegroundColor Green
    Write-Host "Latest Release Assets: $($f_latestReleaseInfo.assets) " -ForegroundColor DarkYellow
    return $f_latestReleaseInfo
}
function Get-RootRepository {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_repoUrl
    )
    
    # Fetch the repository information
    try {
        $rateLimitInfo = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit'
        Write-Host "Rate Limit Remaining: " -NoNewline -ForegroundColor DarkRed
        Write-Host $rateLimitInfo

        $repoInfo = (Invoke-WebRequest -Uri $p_repoUrl).Content | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to fetch repository information."
        return $null
    }

    # Check if the repository is a fork
    if ($repoInfo.fork -eq $true) {
        # If it's a fork, recurse into its parent
        return (Get-RootRepository -p_repoUrl $repoInfo.parent.url)
    } else {
        # If it's not a fork, return the current repository info
        return $repoInfo
    }
}
function New-NuspecFile {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$p_Metadata,

        [Parameter(Mandatory=$true)]
        [string]$p_packageDir
    )

    # Validation
    if (-not $p_Metadata.PackageName -or -not $p_Metadata.Repo -or -not $p_Metadata.Url -or -not $p_Metadata.Version -or -not $p_Metadata.Author -or -not $p_Metadata.Description) {
        Write-Error "Missing mandatory metadata for nuspec file. PackageName: $($p_Metadata.PackageName), Repo: $($p_Metadata.Repo), Url: $($p_Metadata.Url), Version: $($p_Metadata.Version), Author: $($p_Metadata.Author), Description: $($p_Metadata.Description)"
        return
    }

    $f_nuspec = @"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>$($p_Metadata.PackageName)</id>
    <title>$($p_Metadata.GithubRepoName)</title>
    <version>$($p_Metadata.Version)</version>
    <authors>$($p_Metadata.Author)</authors>
    <description>$($p_Metadata.Description)</description>
    <projectUrl>$($p_Metadata.Repo)</projectUrl>
    <packageSourceUrl>$($p_Metadata.Url)</packageSourceUrl>
    <releaseNotes>$($p_Metadata.VersionDescription)</releaseNotes>
    <licenseUrl>$($p_Metadata.Repo)/blob/master/LICENSE</licenseUrl>
    <iconUrl>$($p_Metadata.IconUrl)</iconUrl>
    <tags></tags>
  </metadata>
</package>
"@

    $f_nuspecPath = Join-Path $p_packageDir "$($p_Metadata.PackageName).nuspec"
    try {
        Out-File -InputObject $f_nuspec -FilePath $f_nuspecPath -Encoding utf8
    }
    catch {
        Write-Error "Failed to create nuspec file at: $f_nuspecPath"
        exit 1
    }
    return $f_nuspecPath
}
function New-InstallScript {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$p_Metadata,

        [Parameter(Mandatory=$true)]
        [string]$p_toolsDir
    )

    Write-Host
    Write-Host "Package Metadata From Install Script Method:" -ForegroundColor DarkYellow
    Format-Json -json $p_Metadata
    Write-Host

    # Validation
    if (-not $p_Metadata.PackageName -or -not $p_Metadata.Repo -or -not $p_Metadata.Url -or -not $p_Metadata.Version -or -not $p_Metadata.Author -or -not $p_Metadata.Description) {
        Write-Error "Missing mandatory metadata for install script."
        return
    }
    
    $f_installScriptContent = @"
`$ErrorActionPreference = 'Stop';

`$packageArgs = @{
    packageName   = "$($p_Metadata.PackageName)"
    fileType      = "$($p_Metadata.FileType)"
    url           = "$($p_Metadata.Url)"
    softwareName  = "$($p_Metadata.GithubRepoName)"
    silentArgs    = "$($p_Metadata.SilentArgs)"
    validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
"@
    $f_installScriptPath = Join-Path $p_toolsDir "chocolateyInstall.ps1"
    Out-File -InputObject $f_installScriptContent -FilePath $f_installScriptPath -Encoding utf8
    return $f_installScriptPath
}
function Confirm-DirectoryExists {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_path,
        [Parameter(Mandatory=$true)]
        [string]$p_name
    )
    
    Write-Host "Checking for $p_name directory..."
    if (-not (Test-Path $p_path)) {
        Write-Host "No $p_name directory found, creating $p_name directory..."
        New-Item -Path $p_path -ItemType Directory | Out-Null
        Write-Host "$p_name directory created at: $p_path" -ForegroundColor Cyan
    }
    else {
        Write-Host "$p_name directory found at: $p_path" -ForegroundColor Cyan
    }
}
function Get-Updates {
    if ($null -eq $latestReleaseInfo) {
        Write-Error "No release information found."
        exit 1
    }
    # Get all of the names of the folders in the packages directory
    Write-LogHeader "Checking for updates"
    # Not a great way to do this. Change it if one day happens to be 27 hours long.
    # Go up one level and then find a directory named packages
    # Initialize package directory to null
    $f_packageDir = $null

    # Search for the 'packages' directory starting from the parent directory
    $possibleDir = Get-ChildItem -Path ".." -Filter "packages" -Directory

    # Check if the directory was found
    if ($null -eq $possibleDir) {
        Write-Error "No 'packages' directory found."
        exit 1
    } else {
        # If the directory is found, use it
        $f_packageDir = $possibleDir.FullName
        Write-Host "Found 'packages' directory: $f_packageDir"
    }

    Write-Host "The packages directory is: $f_packageDir"

    # List the directories in the packages directory
    $f_packageDirs = Get-ChildItem -Path $f_packageDir -Directory
    Write-Host "The packages directory contains the following directories: $($f_packageDirs.Name -join ', ')"
    
    # For each item in the packages directory, get the latest release info.
    foreach ($dirInfo in $f_packageDirs) {
        # Extract just the directory name from the DirectoryInfo object
        $package = $dirInfo.Name
    
        # Validate that path is valid
        if (-not (Test-Path $f_packageDir)) {
            Write-Error "Path is not valid: $f_packageDir"
            exit 1
        }
    
        # Write the contents of the package directory to the console
        Write-Host "The contents of the package directory are: $package"
    
        # Find the nuspec file in the package directory
        $nuspecFile = Get-ChildItem -Path "$f_packageDir\$package" -Filter "*.nuspec"
        Write-Host "The nuspec file is: $($nuspecFile.Name)"
    
        Write-Host "Checking for updates for: $package" -ForegroundColor Magenta
    
        # More code...
    }
    
        Write-Host $package # TODO: THIS IS BROKEN FIX THE PATH THING THEN IT WILL WORK
        # The repo owner is the first part of the package name and the repo name is the second part of the package name
        $latestReleaseInfo = Get-LatestReleaseInfo -p_baseRepoUrl "https://api.github.com/repos/$($($package -split '\.')[0])/$($($package -split '\.')[1])/releases/latest"
        # Check the packageSourceUrl from the file ending in .nuspec to see if it matches the latest release url
        $nuspecFile = Get-ChildItem -Path "$f_packageDir\$package" -Filter "*.nuspec"
        $nuspecFileContent = Get-Content -Path $nuspecFile -Raw
        # Find the value of the packageSourceUrl field in the nuspec file
        if ($nuspecFileContent -match '<packageSourceUrl>(.*?)<\/packageSourceUrl>') {
            $packageSourceUrl = $matches[1]
        } else {
            Write-Error "No <packageSourceUrl> tag found."
            exit 1
        }
        
        Write-Host "Package Source URL: $packageSourceUrl"
        # Extract the old version number using regex. This assumes the version follows right after '/download/'
        if ($packageSourceUrl -match '/download/([^/]+)/') {
            $oldVersion = $matches[1]
        } else {
            Write-Error "Could not find the version number in the URL."
            exit 1
        }
        # Get the URL of the asset that matches the packageSourceUrl with the version number replaced the newest version number
        $latestReleaseUrl = $packageSourceUrl -replace [regex]::Escape($oldVersion), $latestReleaseInfo.tag_name
        Write-Host "Latest Release URL: $latestReleaseUrl"
        # Compate the two urls

    }
}
<# Get-MostRecentValidRelease: This is useful if releases do not always contain valid assets
function Get-MostRecentValidRelease {
    param ( # Parameter declarations
        [Parameter(Mandatory=$true)]
        [string]$p_repoUrl,
        [string[]]$validFileTypes = @('.exe', '.msi')
    )

    try { # Fetch the release information
        $rateLimitInfo = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit'
        Write-Host "Rate Limit Remaining: " -NoNewline -ForegroundColor DarkRed
        Write-Host $rateLimitInfo
        
        $f_releasesInfo = (Invoke-WebRequest -Uri "$p_repoUrl/releases").Content | ConvertFrom-Json
    }
    catch { # Write an error if the API call fails
        Write-Error "Failed to fetch release information."
        return $null
    }

    if ($null -eq $f_releasesInfo -or $f_releasesInfo.Count -eq 0) {
        Write-Host "No releases found."
        return $null
    }

    # Iterate through the releases and return the URL of the first release that contains a valid asset
    foreach ($release in $f_releasesInfo) {
        if ($null -eq $release.assets -or $release.assets.Count -eq 0) {
            continue
        }

        foreach ($asset in $release.assets) {
            $extension = $asset.name -replace '.*(\..+)$', '$1'
            if ($validFileTypes -contains $extension) {
                return $release.url
            }
        }
    }

    Write-Host "No valid release found."
    return $null
}
#>
#endregion
###################################################################################################

Write-LogHeader "Fetching Latest Release Info"
#region Get Latest Release Info

Write-Host "!!!!!!!!!!!!!!!!! The repo url is: $repoUrl"
# Check if URL is provided
if ([string]::IsNullOrEmpty($repoUrl)) {
    Write-Error "Please provide a URL as an argument."
    exit 1
}


# Create a variable to store accepted extensions
$acceptedExtensions = @('exe', 'msi', 'zip')

# Check if the URL is a GitHub repository URL
if ($repoUrl -match '^https?://github.com/[\w-]+/[\w-]+') {
    $repo = $repoUrl
    $urlParts = $repo -split '/'
    
    $githubUser = $urlParts[3]
    $githubRepoName = $urlParts[4]
    $baseRepoUrl = "https://api.github.com/repos/${githubUser}/${githubRepoName}"
    Write-Host "GitHub User: $githubUser"
    Write-Host "GitHub Repo Name: $githubRepoName"
    Write-Host "Base Repo URL: $baseRepoUrl"

    # Further check for release tag and asset name
    if ($urlParts.Length -gt 7 -and $urlParts[5] -eq 'releases' -and $urlParts[6] -eq 'download') {
        $tag = $urlParts[7]
        $specifiedAssetName = $urlParts[-1]
        Write-Host "Release tag detected: $tag"
        Write-Host "Asset name detected: $specifiedAssetName"
    }
} else {
    Write-Error "Please provide a valid GitHub repository URL. URL provided: $repoUrl does not match the pattern of a GitHub repository URL. GithubUser/GithubRepoName is required. Current User: $githubUser, Current Repo: $githubRepoName "
    exit 1
}

<# This is useful if releases do not always contain valid assets 
ex: releases sometimes containin only updates for specific versions such as linux only releases

$latestReleaseUrl = Get-MostRecentValidRelease -p_repoUrl $baseRepoUrl
if ($null -ne $validReleaseApiUrl) {
    Write-Host "API URL of the most recent valid release is $latestReleaseUrl"
}
#>

# Fetch latest release information
Write-Host "Fetching latest release information from GitHub..."
$latestReleaseUrl = "$baseRepoUrl/releases/latest"
Write-Host "Passing Latest Release URL to Get-Info: $latestReleaseUrl"  
$latestReleaseInfo = Get-LatestReleaseInfo -p_baseRepoUrl $latestReleaseUrl

#endregion
###################################################################################################
Write-LogHeader "Getting Asset Info"
#region Get Asset Info

# Select the best asset based on supported types
Write-Host "Selecting asset..."
# Check if asset name is provided and print it if it is
if (-not [string]::IsNullOrEmpty($specifiedAssetName)) {
    Write-Host "Specified Asset Name: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $specifiedAssetName
    $selectedAsset = Select-Asset -p_assets $latestReleaseInfo.assets -p_assetName $specifiedAssetName
}
else {
    $selectedAsset = Select-Asset -p_assets $latestReleaseInfo.assets
}
Write-Host "Selected asset: $($selectedAsset.name)" -ForegroundColor Cyan

# Set the description using latest release
$description = $latestReleaseInfo.body

# Display repository description
Write-Host "Repository Description: $description"

# Determine file type from asset name
Write-Host "Determining file type from asset name..."
$fileType = Get-Filetype -p_fileName $selectedAsset.name
Write-Host "File type: $fileType" -ForegroundColor Cyan

# Determine silent installation arguments based on file type
Write-Host "Determining silent installation arguments for $fileType... (" -NoNewline; Write-Host "poorly" -ForegroundColor Yellow -NoNewline; Write-Host ")"
$silentArgs = Get-SilentArgs -p_fileType $fileType
Write-Host "Silent installation arguments for {$fileType}: $silentArgs" -ForegroundColor Cyan

# Find the root repository
$rootRepoInfo = Get-RootRepository -p_repoUrl $baseRepoUrl

# Use the avatar URL from the root repository's owner
$iconUrl = $rootRepoInfo.owner.avatar_url

$rawVersion = $latestReleaseInfo.tag_name
$sanitizedVersion = ConvertTo-SanitizedNugetVersion -p_rawVersion $rawVersion
Write-Host "Sanitized Version: $sanitizedVersion"

# If specifiedasset is not null or empty print it
if (-not [string]::IsNullOrEmpty($specifiedAssetName)) {
        # If the asset name contains the version number, remove it.
    if ($specifiedAssetName -match $tag) {
        $cleanedSpecifiedAssetName = $specifiedAssetName -replace $tag, ''
        # Split by . and remove the last element if it is a valid extension
        $cleanedSpecifiedAssetName = $cleanedSpecifiedAssetName.Split('.') | Where-Object { $_ -notin $acceptedExtensions }
    }   
    else {
        cleanedSpecifiedAssetName = $specifiedAssetName
    }
    #clean package name to avoid errors such as this:The package ID 'Ryujinx.release-channel-master.ryujinx--win_x64.zip' contains invalid characters. Examples of valid package IDs include 'MyPackage' and 'MyPackage.Sample'.
    $cleanedSpecifiedAssetName = ".$cleanedSpecifiedAssetName" -replace '[^a-zA-Z0-9.]', ''
    Write-Host "Specified Asset Name -Version Tag: $cleanedSpecifiedAssetName"
}

# Some of these should be renamed for clarity
# Create package metadata object
$packageMetadata        = [PSCustomObject]@{
    PackageName         = "${githubUser}.${githubRepoName}${cleanedSpecifiedAssetName}"
    Version             = $sanitizedVersion
    Author              = $githubUser
    Description         = $description
    VersionDescription  = $latestReleaseInfo.body -replace "\r\n", " "
    Url                 = $selectedAsset.browser_download_url
    Repo                = $repo
    FileType            = $fileType
    SilentArgs          = $silentArgs
    IconUrl             = $iconUrl
    GithubRepoName      = $githubRepoName
}
Write-Host "Selected asset: $($packageMetadata.PackageName)" -ForegroundColor Cyan

Write-Host
Write-Host "Package Metadata:" -ForegroundColor DarkYellow
Format-Json -json $packageMetadata
Write-Host

# If the name contains the version number exactly, remove the version number from the package name
if ($packageMetadata.PackageName -match $packageMetadata.Version) {
    $packageMetadata.PackageName = $packageMetadata.PackageName -replace $packageMetadata.Version, ''
}

Write-Host
Write-Host "Download URL: " -NoNewline
Write-Host "$($packageMetadata.Url)" -ForegroundColor Blue
Write-Host

#endregion
###################################################################################################
Write-LogHeader "Creating Nuspec File and Install Script"
#region Create Nuspec File and Install Script

# Set the path to the package directory
$packageDir = Join-Path (Get-Location).Path $packageMetadata.PackageName

Write-Host "Checking for package directory..."
# Create the tools directory if it doesn't exist
Confirm-DirectoryExists -p_path $packageDir -p_name 'package'

# Explicitly set the path to the tools directory
$toolsDir = Join-Path $packageDir "tools"

# Create the tools directory if it doesn't exist
Confirm-DirectoryExists -p_path $toolsDir -p_name 'tools'

Write-Host "Creating nuspec file..."
$nuspecPath = New-NuspecFile -p_Metadata $packageMetadata -p_packageDir $packageDir
Write-Host "Nuspec file created at: $nuspecPath" -ForegroundColor Cyan

Write-Host "Creating install script..."
$installScriptPath = New-InstallScript -p_Metadata $packageMetadata -p_toolsDir $toolsDir
Write-Host "Install script created at: $installScriptPath" -ForegroundColor Cyan

# This is just here for testing
# The function relies on variables currently set in this section
# It should be changed to be standalone

# Specifically keep the variables here but move the actions of this section and the next to their own function
# That way they can be called individually

# There may be errors in the get updates function related to the path. Check that first

Get-Updates

#endregion
###################################################################################################
Write-LogHeader "Creating Chocolatey Package"
#region Create Chocolatey Package

# Check for Nuspec File
Write-Host "Checking for nuspec file..."
if (-not (Test-Path $nuspecPath)) {
    Write-Error "Nuspec file not found at: $nuspecPath"
    exit 1
}
else {
    Write-Host "Nuspec file found at: $nuspecPath" -ForegroundColor Cyan
}

# Create Chocolatey package
try {
    Write-Host "Creating Chocolatey package..."
    choco pack $nuspecPath -Force -Verbose --out $packageDir
} catch {
    Write-Error "Failed to create Chocolatey package."
    exit 1
}

#endregion
###################################################################################################
