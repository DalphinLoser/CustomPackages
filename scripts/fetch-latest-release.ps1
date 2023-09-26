$ErrorActionPreference = 'Stop'
###################################################################################################
#region Functions
function Get-Favicon {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_homepage
    )
    Write-Host "ENTERING Get-Favicon function" -ForegroundColor Yellow
    $webRequest = Invoke-WebRequest -Uri $p_homepage

    # Use regex to find <link rel="icon" ...> or <link rel="shortcut icon" ...>
    if ($webRequest.Content -match "<link[^>]*rel=`"(icon|shortcut icon)`"[^>]*href=`"([^`"]+)`"") {
        $faviconRelativeLink = $matches[2]

        # Check if link is relative
        if ($faviconRelativeLink -match "^/") {
            # Convert to absolute URL
            $faviconAbsoluteLink = "$p_homepage$faviconRelativeLink"
            Write-Host "    Favicon URL: $faviconAbsoluteLink"
            return $faviconAbsoluteLink
        } else {
            Write-Host "    Favicon URL: $faviconRelativeLink"
            return $faviconRelativeLink
        }
    } else {
        Write-Host "No favicon link found in HTML"
        return $null
    }
    Write-Host "EXITING Get-Favicon function" -ForegroundColor Green
}
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
        [Parameter(Mandatory=$true)]
        [hashtable]$p_urls
    )

    $p_assetName = $p_urls.specifiedAssetName
    $baseRepoUrl = $p_urls.baseRepoUrl
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

    Write-Host "EXITING Selected Asset" -ForegroundColor Green
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
    Write-Host "EXITING Sanitized Version" -ForegroundColor Green
    return $f_sanitizedVersion
}
function Get-Filetype {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_fileName,
        [string[]]$p_acceptedExtensions = $acceptedExtensions
    )
    Write-Host "ENTERING Get-Filetype function" -ForegroundColor Yellow

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
        Write-Host "    File name ends with an accepted extension."
        # return the extension that was found
        return $ext
    } else {
        Write-Error "   Unsupported file type: $p_fileName"
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
    Write-Host "ENTERING Get-SilentArgs function" -ForegroundColor Yellow
    
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
            Write-Error "   Unsupported file type: $p_fileType"
            exit 1
        }
    }

    Write-Host "EXITING Silent Args" -ForegroundColor Green
    return $f_silentArgs
}
function Get-LatestReleaseInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_baseRepoUrl
    )

    Write-Host "    ENTERING Get-LatestReleaseInfo function" -ForegroundColor Yellow
    Write-Host "    Target GitHub API URL: $p_baseRepoUrl"

    Write-Host "    Initiating web request to GitHub API..."
    $response = Invoke-WebRequest -Uri $p_baseRepoUrl
    Write-Host "    HTTP Status Code: $($response.StatusCode)"

    Write-Host "    Attempting to parse JSON content..."
    $f_latestReleaseInfo = $response.Content | ConvertFrom-Json

    Write-Host "    Validating received data..."
    if ($null -eq $f_latestReleaseInfo) {
        Write-Error "   Received data is null. URL used: $p_baseRepoUrl"
        exit 1
    }

    if ($f_latestReleaseInfo.PSObject.Properties.Name -notcontains 'tag_name') {
        Write-Error "   No 'tag_name' field in received data. URL used: $p_baseRepoUrl"
        exit 1
    }

    $assetCount = ($f_latestReleaseInfo.assets | Measure-Object).Count
    Write-Host "    Type of 'assets' field: $($f_latestReleaseInfo.assets.GetType().FullName)"
    Write-Host "    Is 'assets' field null? $($null -eq $f_latestReleaseInfo.assets)"
    Write-Host "    Is 'assets' field empty? ($assetCount -eq 0)"

    if ($assetCount -gt 0) {
        Write-Host "    Listing assets:"
        $f_latestReleaseInfo.assets | ForEach-Object {
            Write-Host $_.name
        }
    }

    Write-Host "    Tag Name: $($f_latestReleaseInfo.tag_name)"
    Write-Host "EXITING latest release info" -ForegroundColor Green
    return $f_latestReleaseInfo
}


function Get-RootRepository {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_repoUrl
    )
    Write-Host "ENTERING Get-RootRepository function" -ForegroundColor Yellow
    Write-Host "    Getting root repository for: " -NoNewline -ForegroundColor Cyan
    Write-Host $p_repoUrl
    # Fetch the repository information
    try {
        $repoInfo = (Invoke-WebRequest -Uri $p_repoUrl).Content | ConvertFrom-Json
        Write-Host "    Repository information fetched successfully: " -NoNewline -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to fetch repository information."
        return $null
    }

    # Check if the repository is a fork
    if ($repoInfo.fork -eq $true) {
        # If it's a fork, recurse into its parent
        $rootRepo = Get-RootRepository -p_repoUrl $repoInfo.parent.url
        return $rootRepo
    } else {
        # If it's not a fork, return the current repository info
        Write-Host "EXITING root repository info" -ForegroundColor Green
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

    Write-Host "ENTERING New-NuspecFile function" -ForegroundColor Yellow
    # Validation
    if (-not $p_Metadata.PackageName -or -not $p_Metadata.ProjectUrl -or -not $p_Metadata.Url -or -not $p_Metadata.Version -or -not $p_Metadata.Author -or -not $p_Metadata.Description) {
        Write-Error "Missing mandatory metadata for nuspec file. PackageName: $($p_Metadata.PackageName), Repo: $($p_Metadata.ProjectUrl), Url: $($p_Metadata.Url), Version: $($p_Metadata.Version), Author: $($p_Metadata.Author), Description: $($p_Metadata.Description)"
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
    <projectUrl>$($p_Metadata.ProjectUrl)</projectUrl>
    <packageSourceUrl>$($p_Metadata.Url)</packageSourceUrl>
    <releaseNotes>$($p_Metadata.VersionDescription)</releaseNotes>
    <licenseUrl>$($p_Metadata.ProjectUrl)/blob/master/LICENSE</licenseUrl>
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
    Write-Host "    Nuspec file created at: " -NoNewline -ForegroundColor Cyan
    Write-Host $f_nuspecPath
    Write-Host "EXITING Nuspec Path" -ForegroundColor Green
    return $f_nuspecPath
}
function New-InstallScript {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$p_Metadata,

        [Parameter(Mandatory=$true)]
        [string]$p_toolsDir
    )
    Write-Host "ENTERING New-InstallScript function" -ForegroundColor Yellow
    Write-Host
    #Write-Host "    Package Metadata From Install Script Method:" -ForegroundColor DarkYellow
    #Format-Json -json $p_Metadata
    Write-Host

    # Validation
    if (-not $p_Metadata.PackageName -or -not $p_Metadata.ProjectUrl -or -not $p_Metadata.Url -or -not $p_Metadata.Version -or -not $p_Metadata.Author -or -not $p_Metadata.Description) {
        Write-Error "Missing mandatory metadata for install script."
        return
    }
    
# Choose the appropriate Chocolatey function based on FileType
    # Initialize the script content as an empty string
$f_installScriptContent = ""

# Check the file type
if ($p_Metadata.FileType -eq "zip") {
    $f_installScriptContent = @"
`$ErrorActionPreference = 'Stop';
`$toolsDir   = Join-Path `$(Get-ToolsLocation) `$env:ChocolateyPackageName

`$packageArgs = @{
    packageName     = "$($p_Metadata.PackageName)"
    url             = "$($p_Metadata.Url)"
    unzipLocation   = `$toolsDir
}

Install-ChocolateyZipPackage @packageArgs
"@
} else {
    $f_installScriptContent = @"
`$ErrorActionPreference = 'Stop';

`$packageArgs = @{
    packageName     = "$($p_Metadata.PackageName)"
    fileType        = "$($p_Metadata.FileType)"
    url             = "$($p_Metadata.Url)"
    softwareName    = "$($p_Metadata.GithubRepoName)"
    silentArgs      = "$($p_Metadata.SilentArgs)"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
"@
}


    
    $f_installScriptPath = Join-Path $p_toolsDir "chocolateyInstall.ps1"
    Out-File -InputObject $f_installScriptContent -FilePath $f_installScriptPath -Encoding utf8
    Write-Host "    Install script created at: " -NoNewline -ForegroundColor Cyan
    Write-Host $f_installScriptPath
    Write-Host "EXITING Install Script Path" -ForegroundColor Green
    return $f_installScriptPath
}
function Confirm-DirectoryExists {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_path,
        [Parameter(Mandatory=$true)]
        [string]$p_name
    )
    Write-Host "ENTERING Confirm-DirectoryExists function" -ForegroundColor Yellow
    Write-Host "    Checking for $p_name directory..."
    if (-not (Test-Path $p_path)) {
        Write-Host "    No $p_name directory found, creating $p_name directory..."
        New-Item -Path $p_path -ItemType Directory | Out-Null
        Write-Host "    $p_name directory created at: $p_path" -ForegroundColor Cyan
    }
    else {
        Write-Host "    $p_name directory found at: $p_path" -ForegroundColor Cyan
    }
    Write-Host "Exiting Confirm-DirectoryExists function" -ForegroundColor Green
}
function Get-Updates {
    Write-Host "ENTERING Get-Updates function" -ForegroundColor Yellow
    # Get all of the names of the folders in the packages directory
    Write-LogHeader "   Checking for updates"
    
    # Not a great way to do this. Change it if one day happens to be 27 hours long.

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
        Write-Host "    Found 'packages' directory: $f_packageDir"
    }

    # List the directories in the packages directory
    $f_packageDirs = Get-ChildItem -Path $f_packageDir -Directory
    Write-Host "    The packages directory contains the following directories: $($f_packageDirs.Name -join ', ')"
    
    # For each item in the packages directory, get the latest release info.
    foreach ($dirInfo in $f_packageDirs) {
        # Extract just the directory name from the DirectoryInfo object
        $package = $dirInfo.Name
    
        # Validate that path is valid
        if (-not (Test-Path $f_packageDir)) {
            Write-Error "Path is not valid: $f_packageDir"
            exit 1
        }
    
        # Find the nuspec file in the package directory
        $nuspecFile = Get-ChildItem -Path "$f_packageDir\$package" -Filter "*.nuspec"
    
        Write-Host "    Checking for updates for: $package" -ForegroundColor Magenta
    
        # First part of name
        Write-Host "    First part of name: $($($package -split '\.')[0])"
        # Second part of name
        Write-Host "    Second part of name: $($($package -split '\.')[1])"

        # Get the latest release info for the package
        # The repo owner is the first part of the package name and the repo name is the second part of the package name
        $latestReleaseInfo_UP = Get-LatestReleaseInfo -p_baseRepoUrl "https://api.github.com/repos/$($($package -split '\.')[0])/$($($package -split '\.')[1])/releases/latest"

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
        
        Write-Host "    Package Source URL: $packageSourceUrl"
        # Extract the old version number using regex. This assumes the version follows right after '/download/'
        if ($packageSourceUrl -match '/download/([^/]+)/') {
            $oldVersion = $matches[1]
        } else {
            Write-Error "Could not find the version number in the URL."
            exit 1
        }
        Write-Host "    Old Version URL: $oldVersion"
        # Get the URL of the asset that matches the packageSourceUrl with the version number replaced the newest version number
        $latestReleaseUrl_Update = $packageSourceUrl -replace [regex]::Escape($oldVersion), $latestReleaseInfo_UP.tag_name
        Write-Host "    Latest Release URL: $latestReleaseUrl_Update"
        # Compate the two urls
        # Compare the two URLs
        if ($latestReleaseUrl_Update -eq $packageSourceUrl) {
            Write-Host "    The URLs are identical. No new version seems to be available."
        } else {
            Write-Host "    The URLs are different. A new version appears to be available."
            Write-Host "    Old URL: $packageSourceUrl"
            Write-Host "    New URL: $latestReleaseUrl_Update"
        }
        # If the URLs are different, update the metadata for the package
        if ($latestReleaseUrl_Update -ne $packageSourceUrl) {
            
            # Remove the old nuspec file
            Remove-Item -Path $nuspecFile -Force

            Write-Host "    Updating metadata for $package"
            # Get the new metadata
            Initialize-GithubPackage -repoUrl $latestReleaseUrl_Update
            # Remove the old nuspec file
            Write-Host "    Removing old nuspec file"
            
        } else {
            Write-Host "    No updates found for $package"
        }
    }
    Write-Host "Exiting Get-Updates function" -ForegroundColor Green
}
function New-ChocolateyPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_nuspecPath,
        [Parameter(Mandatory=$true)]
        [string]$p_packageDir
    )
    Write-Host "ENTERING New-ChocolateyPackage function" -ForegroundColor Yellow
    # Check for Nuspec File
    Write-Host "    Checking for nuspec file..."
    if (-not (Test-Path $p_nuspecPath)) {
        Write-Error "Nuspec file not found at: $p_nuspecPath"
        exit 1
    }
    else {
        Write-Host "    Nuspec file found at: $p_nuspecPath" -ForegroundColor Cyan
    }

    # Create Chocolatey package
    try {
        Write-Host "    Creating Chocolatey package..."
        choco pack $p_nuspecPath -Force -Verbose --out $p_packageDir
    } catch {
        Write-Error "Failed to create Chocolatey package."
        exit 1
    }
    Write-Host "Exiting New-ChocolateyPackage function" -ForegroundColor Green
}
function Get-AssetInfo {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$latestReleaseInfo_GETINFO,
        [Parameter(Mandatory=$true)]
        [hashtable]$p_urls
    )
    Write-Host "ENTERING Get-AssetInfo function" -ForegroundColor Yellow
    # Initialize variables
    $tag = $null
    $specifiedAssetName = $null

    Write-Host "    Writing Content of p_urls" -ForegroundColor DarkYellow
    # Check if specifiedasset is null or empty
    if (-not [string]::IsNullOrEmpty($p_urls.specifiedAssetName)) {
        $specifiedAssetName = $p_urls.specifiedAssetName
        Write-Host "        Specified Asset Name: " -NoNewline -ForegroundColor Magenta
        Write-Host $specifiedAssetName
    }

    if (-not [string]::IsNullOrEmpty($p_urls.tag)) {
        $tag = $p_urls.tag
        Write-Host "    Tag: " -NoNewline -ForegroundColor Magenta
        Write-Host $tag
    }
    $repo = $p_urls.repo
    Write-Host "        Repo: " -NoNewline -ForegroundColor Magenta
    Write-Host $repo
    $githubUser = $p_urls.githubUser
    Write-Host "        GitHub User: " -NoNewline -ForegroundColor Magenta
    Write-Host $githubUser
    $githubRepoName = $p_urls.githubRepoName
    Write-Host "        GitHub Repo Name: " -NoNewline -ForegroundColor Magenta
    Write-Host $githubRepoName    

    # Validation check for the asset
    if ($null -eq $latestReleaseInfo_GETINFO) {
        Write-Error "No assets found for the latest release. Latest Release Info is Null"
        exit 1
    }

    # Fetch rate limit information
    #$rateLimitInfo = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit'
    #Write-Host "Rate Limit Remaining: " -NoNewline -ForegroundColor DarkRed
    #Write-Host $rateLimitInfo
    
    # Select the best asset based on supported types
    $selectedAsset = Select-Asset -p_assets $latestReleaseInfo_GETINFO.assets -p_urls $p_urls
    Write-Host "    Selected asset: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $selectedAsset.name

    # Determine file type from asset name
    $fileType = Get-Filetype -p_fileName $selectedAsset.name
    Write-Host "    File type: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $fileType
    # Determine silent installation arguments based on file type
    $silentArgs = Get-SilentArgs -p_fileType $fileType
    Write-Host "    Silent arguments: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $silentArgs

    # Find the root repository
    # get the url from the latest release info and replace everything after the repo name with nothing
    $baseRepoUrl_Info = $latestReleaseInfo_GETINFO.url -replace '/releases/.*', ''
    Write-Host "    Base Repo URL: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $baseRepoUrl_Info
    $rootRepoInfo = Get-RootRepository -p_repoUrl $baseRepoUrl_Info
    Write-Host "    Root Repo URL: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $rootRepoInfo.url
    # Use the avatar URL from the root repository's owner

    if (-not [string]::IsNullOrEmpty($rootRepoInfo.homepage)) {
        $homepage = $rootRepoInfo.homepage
        # Get the favicon from the homepage
        $iconUrl = Get-Favicon -p_homepage $homepage
        Write-Host "    Updated Icon URL to Favicon: " -NoNewline -ForegroundColor DarkYellow
        Write-Host $iconUrl
    }
    else {
        $iconUrl = $rootRepoInfo.owner.avatar_url
        Write-Host "    Icon URL: " -NoNewline -ForegroundColor DarkYellow
        Write-Host $iconUrl
    }

    # If the owner of the root repository is an organization, use the organization name as package name
    if ($rootRepoInfo.owner.type -eq 'Organization') {
        $orgName = $rootRepoInfo.owner.login
        Write-Host "    Updated orgName to Organization Name: " -NoNewline -ForegroundColor DarkYellow
        Write-Host $orgName
    }

    # Get the description
    Write-Host "    Passing rootRepoInfo to Get-Description: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $rootRepoInfo
    # If the description is null or empty, get the description from the root repository
    if ([string]::IsNullOrEmpty($rootRepoInfo.description)) {
        $description = $rootRepoInfo.description
        # If the description is still null, get content of the readme
        if ([string]::IsNullOrEmpty($rootRepoInfo.description)){
            $readmeInfo = (Invoke-WebRequest -Uri "$($baseRepoUrl_Info.url/"readme")").Content | ConvertFrom-Json
            $description = $readmeInfo.content
            Write-Host "    Description not found. Using readme content" -ForegroundColor DarkYellow
        }
        else {
            Write-Host "    Description could not be found."
            $description = "Description could not be found."
        }
    }
    else {
        $description = $rootRepoInfo.description
    }

    Write-Host "    Description: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $description


    # Get the latest release version number
    $rawVersion = $latestReleaseInfo_GETINFO.tag_name
    Write-Host "    Raw Version: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $rawVersion
    # Sanitize the version number
    $sanitizedVersion = ConvertTo-SanitizedNugetVersion -p_rawVersion $rawVersion
    Write-Host "    Sanitized Version: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $sanitizedVersion

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
    Write-Host "    Cleaned Specified Asset Name: " -NoNewline -ForegroundColor DarkYellow
    Write-Host $cleanedSpecifiedAssetName
    }

    # Create package metadata object
    $packageMetadata        = [PSCustomObject]@{
        PackageName         = "${githubUser}.${githubRepoName}${cleanedSpecifiedAssetName}"
        Version             = $sanitizedVersion
        Author              = $githubUser
        Description         = $description
        VersionDescription  = $latestReleaseInfo_GETINFO.body -replace "\r\n", " "
        Url                 = $selectedAsset.browser_download_url
        ProjectUrl          = $repo
        FileType            = $fileType
        SilentArgs          = $silentArgs
        IconUrl             = $iconUrl
        GithubRepoName      = if (-not $orgName) { $githubRepoName } else { $orgName }

    }

    # If the name contains the version number exactly, remove the version number from the package name
    if ($packageMetadata.PackageName -match $packageMetadata.Version) {
        $packageMetadata.PackageName = $packageMetadata.PackageName -replace $packageMetadata.Version, ''
    }

    Write-Host "EXITING Metadata" -ForegroundColor Green
    return $packageMetadata
}
function Initialize-URLs{
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_repoUrl
    )
    Write-Host "ENTERING Initialize-URLs function" -ForegroundColor Yellow
    # Check if the URL is a GitHub repository URL
    if ($p_repoUrl -match '^https?://github.com/[\w-]+/[\w-]+') {
        $urlParts = $p_repoUrl -split '/'
        
        $githubUser = $urlParts[3]
        $githubRepoName = $urlParts[4]
        $baseRepoUrl = "https://api.github.com/repos/${githubUser}/${githubRepoName}"
        Write-Host "    GitHub User: " -NoNewline -ForegroundColor Magenta
        Write-Host $githubUser
        Write-Host "    GitHub Repo Name: " -NoNewline -ForegroundColor Magenta
        Write-Host $githubRepoName
        Write-Host "    Base Repo URL: " -NoNewline -ForegroundColor Magenta
        Write-Host $baseRepoUrl
        
        # Further check for release tag and asset name
        if ($urlParts.Length -gt 7 -and $urlParts[5] -eq 'releases' -and $urlParts[6] -eq 'download') {
            $tag = $urlParts[7]
            $specifiedAssetName = $urlParts[-1]
            Write-Host "    Release tag detected: " -NoNewline -ForegroundColor Magenta
            Write-Host $tag
            Write-Host "    Asset name detected: " -NoNewline -ForegroundColor Magenta
            Write-Host $specifiedAssetName
        }
    } else {
        Write-Error "Please provide a valid GitHub repository URL. URL provided: $p_repoUrl does not match the pattern of a GitHub repository URL. GithubUser/GithubRepoName is required. Current User: $githubUser, Current Repo: $githubRepoName "
        exit 1
    }

    # The url of the repo
    $repo = "https://github.com/${githubUser}/${githubRepoName}"

    # Return all of the urls as a hashtable
    Write-Host "EXITING URLs Hashtable" -ForegroundColor Green
    return @{
        repo = $repo
        githubUser = $githubUser
        githubRepoName = $githubRepoName
        baseRepoUrl = $baseRepoUrl
        tag = $tag
        specifiedAssetName = $specifiedAssetName
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
function Initialize-GithubPackage{
    param (
        [Parameter(Mandatory=$true)]
        [string]$repoUrl
    )
    # Check if URL is provided
    if ([string]::IsNullOrEmpty($repoUrl)) {
        Write-Error "Please provide a URL as an argument."
        exit 1
    }
    Write-Host "ENTERING Initialize-GithubPackage function" -ForegroundColor Yellow
    Write-Host "    Input Received: $repoUrl"

    ###################################################################################################
    Write-LogHeader "Fetching Latest Release Info"
    #region Get Latest Release Info

    # Create a hashtable to store the URLs
    $urls = Initialize-URLs -p_repoUrl $repoUrl

    # Create a variable to store accepted extensions
    

    <# This is useful if releases do not always contain valid assets 
    ex: releases sometimes containin only updates for specific versions such as linux only releases

    $latestReleaseUrl = Get-MostRecentValidRelease -p_repoUrl $baseRepoUrl
    if ($null -ne $validReleaseApiUrl) {
        Write-Host "API URL of the most recent valid release is $latestReleaseUrl"
    }
    #>

    # Fetch latest release information
    Write-Host "    Fetching latest release information from GitHub..."
    $latestReleaseUrl = ($urls.baseRepoUrl + '/releases/latest')
    Write-Host "    Passing Latest Release URL to Get-Info: $latestReleaseUrl"  
    $latestReleaseInfo_GHP = Get-LatestReleaseInfo -p_baseRepoUrl $latestReleaseUrl

    #endregion
    ###################################################################################################
    Write-LogHeader "   Getting Asset Info"
    #region Get Asset Info

    # Get the asset metadata
    Write-Host "    Passing Latest Release Info to Get-AssetInfo: " -ForegroundColor Yellow
    # Write the content of latestReleaseInfo_GHP one per line with the key in Cyan and the value in white
    $latestReleaseInfo_GHP.PSObject.Properties | ForEach-Object {
        Write-Host "    $($_.Name): " -NoNewline -ForegroundColor Cyan
        Write-Host $_.Value
    }
    Write-Host "    Passing URLs to Get-AssetInfo: " -ForegroundColor Yellow
    # Write the content of the hashtable one per line
    $urls.GetEnumerator() | ForEach-Object {
        Write-Host "    $($_.Key): " -NoNewline -ForegroundColor Cyan
        Write-Host $_.Value
    }
    $myMetadata = Get-AssetInfo -latestReleaseInfo_GETINFO $latestReleaseInfo_GHP -p_urls $urls

    #Write-Host "    Package Metadata From Initialize-GithubPackage Method:" -ForegroundColor DarkYellow
    #Format-Json -json $myMetadata

    # Set the path to the package directory and create it if it doesn't exist
    $packageDir = Join-Path (Get-Location).Path $myMetadata.PackageName
    Confirm-DirectoryExists -p_path $packageDir -p_name 'package'

    # Explicitly set the path to the tools directory and create it if it doesn't exist
    $toolsDir = Join-Path $packageDir "tools"
    Confirm-DirectoryExists -p_path $toolsDir -p_name 'tools'

    #endregion
    ###################################################################################################
    Write-LogHeader "Creating Nuspec File and Install Script"
    #region Create Nuspec File and Install Script

    # Create the nuspec file and install script
    $nuspecPath = New-NuspecFile -p_Metadata $myMetadata -p_packageDir $packageDir
    $installScriptPath = New-InstallScript -p_Metadata $myMetadata -p_toolsDir $toolsDir

    #endregion
    ###################################################################################################
    Write-LogHeader "Creating Chocolatey Package"
    #region Create Chocolatey Package

    # Create the Chocolatey package
    New-ChocolateyPackage -p_nuspecPath $nuspecPath -p_packageDir $packageDir

    #endregion
    ###################################################################################################
Write-Host "Exiting Initialize-GithubPackage function" -ForegroundColor Green
}
###################################################################################################

$acceptedExtensions = @('exe', 'msi', 'zip')