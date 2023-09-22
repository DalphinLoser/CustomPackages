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
    $colorScale = @('DarkBlue', 'Blue', 'RoyalBlue', 'DodgerBlue', 'LightSkyBlue')

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
        [array]$p_assets
    )

    # Validation check for the assets
    $f_supportedTypes = @('exe', 'msi', '7z', 'zip', 'msu', 'msp')
    # Select the first asset that matches a supported type
    $f_selectedAsset = $p_assets | Where-Object { $_.name -match '\.([^.]+)$' } | Sort-Object { $f_supportedTypes.IndexOf($matches[1]) } | Select-Object -First 1
    # Validation check for the selected asset
    if ($null -eq $f_selectedAsset) {
        Write-Error "No suitable asset (.exe, .msi, .zip, .7z, .msu, .msp) found for the latest release."
        exit 1
    }

    return $f_selectedAsset
}
function Get-RepoDescription {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_latestReleaseUrl
    )
    # Remove /release/latest from the URL
    $f_repoInfoUrl = $p_latestReleaseUrl -replace '/releases/latest'
    Write-Host "Fetching repository description from GitHub... ($f_repoInfoUrl)"

    # Fetch and parse latest release data
    $f_repoInfo = (Invoke-WebRequest -Uri $f_repoInfoUrl).Content | ConvertFrom-Json
    
    # Validation check for the API call
    if ($null -eq $f_repoInfo -or $f_repoInfo.PSObject.Properties.Name -notcontains 'description') {
        Write-Error "Failed to fetch valid release information from GitHub."
        exit 1
    }

    return $f_repoInfo.description
}
function Get-Filetype {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_fileName
    )
    
    if ($p_fileName -match '\.(exe|msi|zip|7z|msu|msp)$') {
        # Return the file type from the file name
        return $matches[1]
        } 
    else { 
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
        [ValidateSet('exe', 'msi', '7z', 'zip', 'msu', 'msp')]
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
        '7z'  { 
            $f_silentArgs = '-y'  # Assume yes on all queries
        }
        'zip' { 
            $f_silentArgs = '-y'  # Assume yes on all queries (Note: Not standard for ZIP)
        }
        'msu' { 
            $f_silentArgs = '/quiet /norestart'  # Quiet mode, no restart
        }
        'msp' { 
            $f_silentArgs = '/qn /norestart'  # Quiet mode, no restart
        }
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
        [string]$p_latestReleaseUrl
    )
    # Validate constructed URL
    if ($p_latestReleaseUrl -notmatch "https://api.github.com/repos/.*/.*/releases/latest") {
        Write-Error "Invalid GitHub release URL: $p_latestReleaseUrl"
        return $null
    }
    
    # Fetch and parse latest release data
    $f_latestReleaseInfo = (Invoke-WebRequest -Uri $p_latestReleaseUrl).Content | ConvertFrom-Json
    
    # Validation check for the API call
    if ($null -eq $f_latestReleaseInfo -or $f_latestReleaseInfo.PSObject.Properties.Name -notcontains 'tag_name') {
        Write-Error "Failed to fetch valid release information from GitHub."
        exit 1
    }

    return $f_latestReleaseInfo
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
        Write-Error "Missing mandatory metadata for nuspec file."
        return
    }

    $f_nuspec = @"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>$($p_Metadata.PackageName)</id>
    <title>$($p_Metadata.Repo)</title>
    <version>$($p_Metadata.Version)</version>
    <authors>$($p_Metadata.Author)</authors>
    <owners>$($p_Metadata.Author)</owners>
    <description>$($p_Metadata.Description)</description>
    <projectUrl>$($p_Metadata.Repo)</projectUrl>
    <packageSourceUrl>$($p_Metadata.Url)</packageSourceUrl>
    <licenseUrl>$($p_Metadata.Repo)/blob/master/LICENSE</licenseUrl>
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
    softwareName  = "$($p_Metadata.PackageName)"
    silentArgs    = "$($p_Metadata.SilentArgs)"
    validExitCodes= @(0)
}
Install-ChocolateyPackage @packageArgs
"@
    # TODO: Specify the path to the install script to be one above the tools directory
    $f_installScriptPath = Join-Path $p_toolsDir "chocolateyInstall.ps1"
    Out-File -InputObject $f_installScriptContent -FilePath $f_installScriptPath -Encoding utf8
    return $f_installScriptPath
}
#endregion
###################################################################################################
Write-LogHeader "Fetching Latest Release Info"
#region Get Latest Release Info

# TODO Replace URL with variable
$repo = "https://github.com/maah/ProtonVPN-win-app"
$githubUser = $repo.Split('/')[3]
$githubRepo = $repo.Split('/')[4]
$latestReleaseUrl = "https://api.github.com/repos/${githubUser}/${githubRepo}/releases/latest"

# Fetch repository description
$description = Get-RepoDescription -p_latestReleaseUrl $latestReleaseUrl

# Display repository description
Write-Host "Repository Description: $description"

# Fetch latest release information
Write-Host "Fetching latest release information from GitHub..."
$latestReleaseInfo = Get-LatestReleaseInfo -p_latestReleaseUrl $latestReleaseUrl
Write-Host "Latest Release URL: $latestReleaseUrl"

#endregion
###################################################################################################
Write-LogHeader "Getting Asset Info"
#region Get Asset Info

# Select the best asset based on supported types
Write-Host "Selecting asset..." 
$selectedAsset = Select-Asset -p_assets $latestReleaseInfo.assets

# Determine file type from asset name
Write-Host "Determining file type from asset name..."
$fileType = Get-Filetype -p_fileName $selectedAsset.name
Write-Host "File type: $fileType" -ForegroundColor Cyan

# Determine silent installation arguments based on file type
Write-Host "Determining silent installation arguments for $fileType... (" -NoNewline; Write-Host "poorly" -ForegroundColor Yellow -NoNewline; Write-Host ")"
$silentArgs = Get-SilentArgs -p_fileType $fileType
Write-Host "Silent installation arguments for {$fileType}: $silentArgs" -ForegroundColor Cyan

# Create package metadata object
$packageMetadata        = [PSCustomObject]@{
    PackageName         = $selectedAsset.name -replace '\.[^.]+$'
    Version             = $latestReleaseInfo.tag_name
    Author              = $latestReleaseInfo.author.login
    Description         = $description
    VersionDescription  = $latestReleaseInfo.body -replace "\r\n", " "
    Url                 = $selectedAsset.browser_download_url
    Repo                = $repo
    FileType            = $fileType
    SilentArgs          = $silentArgs
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
if (-not (Test-Path $packageDir)) {
    Write-Host "No pacakge directory found, creating pacakge directory..."
    New-Item -Path $packageDir -ItemType Directory | Out-Null
    Write-Host "Pacakge directory created at: $packageDir" -ForegroundColor Cyan
}
else {
    Write-Host "Tools directory found at: $toolsDir" -ForegroundColor Cyan
}

# Explicitly set the path to the tools directory
$toolsDir = Join-Path $packageDir "tools"

Write-Host "Checking for tools directory..."
# Create the tools directory if it doesn't exist
if (-not (Test-Path $toolsDir)) {
    Write-Host "No tools directory found, creating tools directory..."
    New-Item -Path $toolsDir -ItemType Directory | Out-Null
    Write-Host "Tools directory created at: $toolsDir" -ForegroundColor Cyan
}
else {
    Write-Host "Tools directory found at: $toolsDir" -ForegroundColor Cyan
}

Write-Host "Creating nuspec file..."
$nuspecPath = New-NuspecFile -p_Metadata $packageMetadata -p_packageDir $packageDir
Write-Host "Nuspec file created at: $nuspecPath" -ForegroundColor Cyan

Write-Host "Creating install script..."
$installScriptPath = New-InstallScript -p_Metadata $packageMetadata -p_toolsDir $toolsDir
Write-Host "Install script created at: $installScriptPath" -ForegroundColor Cyan

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
