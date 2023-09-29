$ErrorActionPreference = 'Stop'
###################################################################################################
#region Functions
# ... rest of your code ...

function ConvertTo-ValidPackageName {
    param (
        [string]$p_packageName
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
    Write-Host "ConvertTo-ValidPackageName"

    # Check for invalid characters and spaces
    if (-not ($p_packageName -match '^[a-z0-9._-]+$') -or $p_packageName.Contains(' ')) {
        Write-Host "    Invalid characters or spaces found in package name: " -NoNewline -ForegroundColor Yellow
        Write-Host $p_packageName
        # Remove invalid characters and spaces
        $p_packageName = $p_packageName -replace ' ', '-'
        $p_packageName = $p_packageName -replace '[^a-z0-9._-]', ''
        Write-Host "    Package name after removing invalid characters and spaces: " -NoNewline -ForegroundColor Yellow
        Write-Host $p_packageName
    }

    Write-Host "    Removing and consolidating groupings of dots, underscores, and hyphens: " -NoNewline -ForegroundColor Yellow
    $p_packageName = $p_packageName -replace '[-]+', '-'  # Remove and consolidate groupings of hyphens
    $p_packageName = $p_packageName -replace '[_]+', '_'  # Remove and consolidate groupings of underscores
    $p_packageName = $p_packageName -replace '[.]+', '.'  # Remove and consolidate groupings of dots
    $p_packageName = $p_packageName -replace '[-_.]+', '.'  # Remove and consolidate groupings of dots, underscores, and hyphens
    $p_packageName = $p_packageName.Trim('-._')  # Remove leading and trailing hyphens, underscores, and dots
    $p_packageName = $p_packageName.ToLower()  # Convert to lowercase
    
    Write-Host $p_packageName

    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
    Write-Host "ConvertTo-ValidPackageName"

    return $p_packageName 
}
function Find-IcoInRepo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$owner,

        [Parameter(Mandatory=$true)]
        [string]$repo,

        [Parameter(Mandatory=$true)]
        [string]$defaultBranch
    )

    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
    Write-Host "Find-IcoInRepo function"
    $token = $env:GITHUB_TOKEN

    Write-Host "Default branch recieved: $defaultBranch"

    if (-not $token) {
        Write-Host "ERROR: GITHUB_TOKEN environment variable not set. Please set it before proceeding." -ForegroundColor Red
        exit 1
    }

    $headers = @{
        "Authorization" = "Bearer $token"
        "User-Agent"    = "PowerShell"
    }

    # Using the Trees API now
    $apiUrl = "https://api.github.com/repos/${owner}/${repo}/git/trees/${defaultBranch}?recursive=1"
    Write-Host "Query URL: $apiUrl" -ForegroundColor Yellow

    try {
        $webResponse = Invoke-WebRequest -Uri $apiUrl -Headers $headers
        $response = $webResponse.Content | ConvertFrom-Json
        # Write-Host "Response Status Code: $($webResponse.StatusCode)" -ForegroundColor Yellow
        # Write-Host "Response Content:" -ForegroundColor Yellow
        # Write-Host $webResponse.Content
    } catch {
        Write-Host "ERROR: Failed to query GitHub API."
        exit 1
    }

    # Filter for files with .ico extension
    $icoFiles = $response.tree | Where-Object { $_.type -eq 'blob' -and $_.path -like '*.ico' }

    if ($icoFiles.Count -gt 0) {
        Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
        Write-Host "Find-IcoInRepo function (Found)"
        return $icoFiles[0].path
    } else {
        Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
        Write-Host "Find-IcoInRepo function (Not Found)"
        return
    }
}
function Get-Favicon {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_homepage
    )

    Write-Host "---------- Script Start ----------" -ForegroundColor Cyan

    #region Fetching webpage content
    Write-Host "Fetching webpage content from $p_homepage" -ForegroundColor Cyan
    try {
        $webRequest = Invoke-WebRequest -Uri $p_homepage
    } catch {
        Write-Host "Failed to fetch webpage content. Please check your internet connection and the URL." -ForegroundColor Red
        return $null
    }
    #endregion
    
    # Strip everything after the domain name
    $f_homepageTld = $p_homepage -replace '^(https?://[^/]+).*', '$1'

    # Output Information
    Write-Host "    Homepage: " -ForegroundColor Yellow -NoNewline
    Write-Host "$p_homepage"
    Write-Host "    Homepage TLD: " -ForegroundColor Yellow -NoNewline
    Write-Host "$f_homepageTld"

    # Regex for matching all icon links
    $regex = "<link[^>]*rel=`"(icon|shortcut icon)`"[^>]*href=`"([^`"]+)`""
    $iconMatches = $webRequest.Content | Select-String -Pattern $regex -AllMatches

    if ($null -ne $iconMatches) {
        $icons = $iconMatches.Matches | ForEach-Object { 
            $faviconRelativeLink = $_.Groups[2].Value
            if ($faviconRelativeLink -match "^(https?:\/\/)") {
                $faviconRelativeLink  # It's already an absolute URL
            } elseif ($faviconRelativeLink -match "^/") {
                "$f_homepageTld$faviconRelativeLink"
            } else {
                "$f_homepageTld/$faviconRelativeLink"
            }
        }  
        
        Write-Host "    Available Icons: " -ForegroundColor Yellow
        Write-Host $($icons -join ', ')

        # Find the highest quality icon
        $highestQualityIcon = $null
        $highestQualityDimensions = 0
        foreach ($iconUrl in $icons) {
            $tempFile = Get-TempIcon -iconUrl $iconUrl
            if ($null -ne $tempFile) {
                $dimensions = Get-IconDimensions -filePath $tempFile
                Remove-Item -Path $tempFile  # Delete the temporary file
                if ($null -ne $dimensions) {
                    $currentDimensions = $dimensions.Width * $dimensions.Height
                    if ($currentDimensions -gt $highestQualityDimensions) {
                        $highestQualityIcon = $iconUrl
                        $highestQualityDimensions = $currentDimensions
                    }
                }
            }
        }
        
        if ($null -ne $highestQualityIcon) {
            Write-Host "    Highest Quality Icon: $highestQualityIcon ($highestQualityDimensions pixels)" -ForegroundColor Green
            Write-Host "----------- Script End -----------" -ForegroundColor Cyan
            return @{
                url = $highestQualityIcon
                width = [Math]::Sqrt($highestQualityDimensions)
                height = [Math]::Sqrt($highestQualityDimensions)
            }
        } else {
            Write-Host "No suitable icon found." -ForegroundColor Red
            Write-Host "----------- Script End -----------" -ForegroundColor Cyan
            return $null
        }

    } else {
        Write-Host "No favicon link found in HTML" -ForegroundColor Red
        Write-Host "----------- Script End -----------" -ForegroundColor Cyan
        return $null
    }
}
function Get-IconDimensions {
    param (
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )

    Write-Host "Analyzing file: $filePath" -ForegroundColor Yellow

    # Ensure the file exists before proceeding
    if (-not (Test-Path -Path $filePath)) {
        Write-Host "File not found: $filePath" -ForegroundColor Red
        return $null
    }
}
function Get-IconDimensions {
    param (
        [Parameter(Mandatory=$true)]
        [string]$filePath
    )

    Write-Host "Analyzing file: $filePath" -ForegroundColor Yellow

    # Ensure the file exists before proceeding
    if (-not (Test-Path -Path $filePath)) {
        Write-Host "File not found: $filePath" -ForegroundColor Red
        return $null
    }

    # Create a Uri object from the file path
    $uri = New-Object System.Uri $filePath

    # Now get the extension from the LocalPath property of the Uri object
    $extension = [System.IO.Path]::GetExtension($uri.LocalPath).ToLower().Trim()

    switch ($extension) {
        '.svg' {
            Write-Host "SVG Identified, returning dummy dimensions" -ForegroundColor Yellow
            # SVG dimension retrieval logic
            # As SVG is a vector format, it doesn't have a fixed dimension in pixels.
            return @{
                Width = 999 # As SVG is a vector format, it doesn't have a fixed dimension in pixels.
                Height = 999
            }
        }
        '.ico' {
            # ICO dimension retrieval logic
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                # Initialize variables to keep track of the largest dimensions
                $maxWidth = 0
                $maxHeight = 0
                
                $fileStream.Seek(4, [System.IO.SeekOrigin]::Begin) | Out-Null  # Skip to the Count field in ICONDIR
                $buffer = New-Object byte[] 2
                $fileStream.Read($buffer, 0, 2) | Out-Null
                $imageCount = [BitConverter]::ToUInt16($buffer, 0)

                for ($i = 0; $i -lt $imageCount; $i++) {
                    $buffer = New-Object byte[] 16
                    $fileStream.Read($buffer, 0, 16) | Out-Null  # Read ICONDIRENTRY
                    $width = $buffer[0]
                    $height = $buffer[1]

                    # Handle dimensions reported as 0 (which actually means 256)
                    $width = if ($width -eq 0) { 256 } else { $width }
                    $height = if ($height -eq 0) { 256 } else { $height }

                    if ($width * $height -gt $maxWidth * $maxHeight) {
                        $maxWidth = $width
                        $maxHeight = $height
                    }
                }

                Write-Host "ICO Dimensions: " -ForegroundColor Green -NoNewline
                Write-Host "$maxWidth x $maxHeight"
                return @{
                    Width = $maxWidth
                    Height = $maxHeight
                }
            } finally {
                $fileStream.Close()
            }
        }
        '.png' {
            # PNG dimension retrieval logic
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                $fileStream.Seek(16, [System.IO.SeekOrigin]::Begin) | Out-Null
                $buffer = New-Object byte[] 8
                $fileStream.Read($buffer, 0, 8) | Out-Null
                [Array]::Reverse($buffer, 0, 4)
                [Array]::Reverse($buffer, 4, 4)
                $width = [BitConverter]::ToUInt32($buffer, 0)
                $height = [BitConverter]::ToUInt32($buffer, 4)
                Write-Host "PNG Dimensions: " -ForegroundColor Green -NoNewline
                Write-Host "$width x $height"
                return @{
                    Width = $width
                    Height = $height
                }
            } finally {
                $fileStream.Close()
            }
        }
        default {
            Write-Host "Unsupported file extension: " -ForegroundColor Red -NoNewline
            Write-Host "$extension"
            return $null
        }
    }
}

function Get-TempIcon {
    param (
        [Parameter(Mandatory=$true)]
        [string]$iconUrl
    )

    # Get file extension and create temporary file with the correct extension
    $extension = [System.IO.Path]::GetExtension($iconUrl)
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $validExtension = ($extension -split "([?])")[0] -replace "[$invalidChars]", ""
    $tempFile = [System.IO.Path]::GetTempFileName() + $validExtension

    try {
        Invoke-WebRequest -Uri $iconUrl -OutFile $tempFile
        return $tempFile
    } catch {
        Write-Host "Failed to download icon from $iconUrl" -ForegroundColor Red
        return $null
    }
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
    Write-Host "`n=== [ $Message ] ===" -BackgroundColor DarkGray
}
function Select-Asset {
    param (
        [array]$p_assets,
        [Parameter(Mandatory=$true)]
        [hashtable]$p_urls
    )

    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "Select-Asset function"

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
    if (-not [string]::IsNullOrWhiteSpace($p_assetName)) {
        Write-Host "    Selecting asset with name: " -ForegroundColor Yellow
Write-Host "`"$p_assetName`""
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
        $f_selectedAsset = $p_assets | 
        Where-Object { 
            if ($_.name -match '\.([^.]+)$') {
                return $f_supportedTypes -contains $matches[1]
            }
            return $false
        } |
        Sort-Object { 
            switch -Regex ($_.name) {
                '\.exe$' { return 0 }
                '\.msi$' { return 1 }
                '\.zip$' { return 2 }
                default  { return 3 }
            }
        } |
        Select-Object -First 1
        Write-Host "    Selected asset after sorting: $($f_selectedAsset.name)"
    }
    # Validation check for the selected asset
    if ($null -eq $f_selectedAsset) {
        Write-Error "No suitable asset found for the latest release. Selected Asset is Null"
        exit 1
    }

    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "Selected Asset"
    return $f_selectedAsset
}
function ConvertTo-SanitizedNugetVersion {
    param (
        [string]$p_rawVersion
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "ConvertTo-SanitizedNugetVersion function"
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
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "Sanitized Version"
    return $f_sanitizedVersion
}
function Get-Filetype {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_fileName,
        [string[]]$p_acceptedExtensions = $acceptedExtensions
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
    Write-Host "Get-Filetype function"

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
        Write-Host "    File name ends with an accepted extension" -ForegroundColor Yellow
        # return the extension that was found
        Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
    Write-Host "File Type"
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
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "Get-SilentArgs function"
    
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

    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "Silent Args"
    return $f_silentArgs
}
function Get-LatestReleaseInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_baseRepoUrl
    )

    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "Get-LatestReleaseInfo function"
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
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "latest release info"
    return $f_latestReleaseInfo
}
function Get-RootRepository {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_repoUrl
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
    Write-Host "Get-RootRepository function"
    Write-Host "    Getting root repository for: " -NoNewline -ForegroundColor Yellow
    Write-Host $p_repoUrl
    
    # Fetch the repository information
    try {
        Write-Host "    Repository information fetched successfully: " -NoNewline -ForegroundColor Yellow
        $repoInfo = (Invoke-WebRequest -Uri $p_repoUrl).Content | ConvertFrom-Json
        Write-Host $repoInfo.full_name
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
        Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "root repository info"
        return $repoInfo
    }
}
function ConvertTo-EscapedXmlContent {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Content
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "ConvertTo-EscapedXmlContent function"
    Write-Host "    Escaping XML Content: " -NoNewline -ForegroundColor Yellow
    Write-Host $Content
    $escapedContent = $Content -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "ConvertTo-EscapedXmlContent function"
    return $escapedContent
}
function New-NuspecFile {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$p_Metadata,
        [Parameter(Mandatory=$true)]
        [string]$p_packageDir
    )

    Write-Host "ENTERING: " -NoNewline -ForegroundColor Cyan
    Write-Host "New-NuspecFile function"

    # Log p_Metadata content
    Write-Host "Content of p_Metadata: " -ForegroundColor Yellow
    $p_Metadata.GetEnumerator() | ForEach-Object {
        Write-Host "    $($_.Key): " -NoNewline -ForegroundColor Magenta
        Write-Host $_.Value
    }

    # Define elementMapping
    $elementMapping = @{
        id = 'PackageName'
        title = 'GithubRepoName'
        version = 'Version'
        authors = 'Author'
        description = 'Description'
        projectUrl = 'ProjectUrl'
        packageSourceUrl = 'Url'
        releaseNotes = 'VersionDescription'
        licenseUrl = 'LicenseUrl'
        iconUrl = 'IconUrl'
        tags = 'Tags'
        size = 'PackageSize'
    }
    # Log elementMapping content
    Write-Host "Content of elementMapping: " -ForegroundColor Yellow
    $elementMapping.GetEnumerator() | ForEach-Object {
        Write-Host "    $($_.Key): " -NoNewline -ForegroundColor Magenta
        Write-Host $_.Value
    }

    $elementOrder = @('id', 'title', 'version', 'authors', 'description', 'projectUrl', 'packageSourceUrl', 'releaseNotes', 'licenseUrl', 'iconUrl', 'tags')

    # Create XML document
    $xmlDoc = New-Object System.Xml.XmlDocument
    if ($null -eq $xmlDoc) {
        Write-Error "xmlDoc is null"
        exit 1
    }

    # Load XML template into xmlDoc and create a Namespace Manager
    $xmlDoc.LoadXml('<?xml version="1.0"?><package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"><metadata></metadata></package>')
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $nsManager.AddNamespace('ns', 'http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd')

    # Select the metadata element using the Namespace Manager
    $metadataElem = $xmlDoc.SelectSingleNode('/ns:package/ns:metadata', $nsManager)
    if ($null -eq $metadataElem) {
        Write-Error "Failed to select metadata element"
        exit 1
    }


# Add elements to XML document
Write-Host "    Appending elements to metadata: " -ForegroundColor Yellow
$namespaceUri = "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd" # Define the namespace URI

foreach ($elementName in $elementOrder) {
    Write-Host "        Checking for element: " -NoNewline -ForegroundColor Magenta
    Write-Host $elementName
    if ($elementMapping.ContainsKey($elementName)) {
        $key = $elementMapping[$elementName]
        if ($p_Metadata.ContainsKey($key) -and $null -ne $p_Metadata[$key]) {
            # Create element with namespace
            $elem = $xmlDoc.CreateElement($elementName, $namespaceUri)
            if ($null -eq $elem) {
                Write-Host "            Error: Failed to create element: " -ForegroundColor Red
            } else {
                $elem.InnerText = $p_Metadata[$key]
                $appendResult = $metadataElem.AppendChild($elem)
                if ($null -eq $appendResult) {
                    Write-Host "Error: Failed to append element: " -ForegroundColor Red
                } else {
                    Write-Host "Appended element: " -ForegroundColor Green -NoNewline
                    Write-Host $elementName
                }
            }
        }
        else {
            Write-Host "Element not found in p_Metadata or value is null: " -ForegroundColor Red -NoNewline
            Write-Host $elementName
        }
    }
    else {
        Write-Host "Element not found in elementMapping: " -ForegroundColor Red -NoNewline
        Write-Host $elementName
    }
}


    # Save XML document to file
    $f_nuspecPath = Join-Path $p_packageDir "$($p_Metadata['PackageName']).nuspec"
    $xmlDoc.Save($f_nuspecPath)

    Write-Host "    Nuspec file created at: " -NoNewline -ForegroundColor Green
    Write-Host $f_nuspecPath
    Write-Host "EXITING: New-NuspecFile function" -ForegroundColor Green

    # Return the path to the saved .nuspec file
    return $f_nuspecPath
}
function New-InstallScript {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$p_Metadata,

        [Parameter(Mandatory=$true)]
        [string]$p_toolsDir
    )

    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "New-InstallScript function"
    Write-Host

    # Validation
    if (-not $p_Metadata.PackageName -or -not $p_Metadata.ProjectUrl -or -not $p_Metadata.Url -or -not $p_Metadata.Version -or -not $p_Metadata.Author -or -not $p_Metadata.Description) {
        Write-Error "Missing mandatory metadata for install script."
        return
    }

    # Check the file type
    if ($p_Metadata.FileType -eq "zip") {
        $globalInstallDir = "C:\AutoPackages\$($p_Metadata.PackageName)"

        $f_installScriptContent = @"
`$ErrorActionPreference = 'Stop';
`$toolsDir   = "$globalInstallDir"

`$packageArgs = @{
    packageName     = "$($p_Metadata.PackageName)"
    url             = "$($p_Metadata.Url)"
    unzipLocation   = `$toolsDir
}

Install-ChocolateyZipPackage @packageArgs

# Initialize directories for shortcuts
`$desktopDir = "`$env:USERPROFILE\Desktop"
`$startMenuDir = Join-Path `$env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

# Check if directories exist, if not, create them
if (!(Test-Path -Path `$desktopDir)) { New-Item -Path `$desktopDir -ItemType Directory }
if (!(Test-Path -Path `$startMenuDir)) { New-Item -Path `$startMenuDir -ItemType Directory }

# Dynamically find all .exe files in the extracted directory and create shortcuts for them
`$exes = Get-ChildItem -Path `$toolsDir -Recurse -Include *.exe
foreach (`$exe in `$exes) {
    `$exeName = [System.IO.Path]::GetFileNameWithoutExtension(`$exe.FullName)
    
    # Create Desktop Shortcut
    `$desktopShortcutPath = Join-Path `$desktopDir "`$exeName.lnk"
    `$WshShell = New-Object -comObject WScript.Shell
    `$DesktopShortcut = `$WshShell.CreateShortcut(`$desktopShortcutPath)
    `$DesktopShortcut.TargetPath = `$exe.FullName
    `$DesktopShortcut.Save()
    
    # Create Start Menu Shortcut
    `$startMenuShortcutPath = Join-Path `$startMenuDir "`$exeName.lnk"
    `$StartMenuShortcut = `$WshShell.CreateShortcut(`$startMenuShortcutPath)
    `$StartMenuShortcut.TargetPath = `$exe.FullName
    `$StartMenuShortcut.Save()
}
"@
    # Generate Uninstall Script
    $f_uninstallScriptContent = @"
`$toolsDir = "$globalInstallDir"
`$shortcutPath = "`$env:USERPROFILE\Desktop"

# Initialize directories for shortcuts
`$desktopDir = "`$env:USERPROFILE\Desktop"
`$startMenuDir = Join-Path `$env:APPDATA 'Microsoft\Windows\Start Menu\Programs'

# Dynamically find all .exe files in the extracted directory and create shortcuts for them
`$exes = Get-ChildItem -Path `$toolsDir -Recurse -Include *.exe
foreach (`$exe in `$exes) {
    `$exeName = [System.IO.Path]::GetFileNameWithoutExtension(`$exe.FullName)
    
    # Remove Desktop Shortcut
    `$desktopShortcutPath = Join-Path `$desktopDir "`$exeName.lnk"
    `Remove-Item "`$desktopShortcutPath" -Force
    
    # Remove Start Menu Shortcut
    `$startMenuShortcutPath = Join-Path `$startMenuDir "`$exeName.lnk"
    `Remove-Item "`$startMenuShortcutPath" -Force
}
# Remove the installation directory
if (Test-Path `$toolsDir) {
    Remove-Item -Path `$toolsDir -Recurse -Force
}
"@
    $f_uninstallScriptPath = Join-Path $p_toolsDir "chocolateyUninstall.ps1"
    Out-File -InputObject $f_uninstallScriptContent -FilePath $f_uninstallScriptPath -Encoding utf8
    Write-Host "    Uninstall script created at: " -NoNewline -ForegroundColor Yellow
    Write-Host $f_uninstallScriptPath    
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
    Write-Host "    Install script created at: " -NoNewline -ForegroundColor Yellow
    Write-Host $f_installScriptPath



    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "New-InstallScript function"
    return $f_installScriptPath
}
function Confirm-DirectoryExists {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_path,
        [Parameter(Mandatory=$true)]
        [string]$p_name
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "Confirm-DirectoryExists function"
    Write-Host "    Checking for $p_name directory..."
    if (-not (Test-Path $p_path)) {
        Write-Host "    No $p_name directory found, creating $p_name directory..."
        New-Item -Path $p_path -ItemType Directory | Out-Null
        Write-Host "    $p_name directory created at: $" -NoNewline -ForegroundColor Yellow
Write-Host $p_path
    }
    else {
        Write-Host "    $p_name directory found at: " -NoNewline -ForegroundColor Yellow
Write-Host $p_path
    }
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "Confirm-DirectoryExists function"
}
function Get-Updates {
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "Get-Updates function"
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
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "Get-Updates function"
}
function New-ChocolateyPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_nuspecPath,
        [Parameter(Mandatory=$true)]
        [string]$p_packageDir
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
    Write-Host "New-ChocolateyPackage function"
    # Check for Nuspec File
    Write-Host "    Checking for nuspec file..."
    if (-not (Test-Path $p_nuspecPath)) {
        Write-Error "Nuspec file not found at: $p_nuspecPath"
        exit 1
    }
    else {
        Write-Host "    Nuspec file found at: $p_nuspecPath" -ForegroundColor Yellow
    }

    # Create Chocolatey package
    try {
        Write-Host "    Creating Chocolatey package..."
        choco pack $p_nuspecPath -Force -Verbose --out $p_packageDir
    } catch {
        Write-Error "Failed to create Chocolatey package."
        exit 1
    }
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "New-ChocolateyPackage function"
}
function Get-AssetInfo {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$latestReleaseInfo_GETINFO,
        [Parameter(Mandatory=$true)]
        [hashtable]$p_urls
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
    Write-Host "Get-AssetInfo function"
    # Initialize variables
    $tag = $null
    $specifiedAssetName = $null

    Write-Host "    Writing Content of p_urls" -ForegroundColor Yellow
    # Check if specifiedasset is null or empty
    if (-not [string]::IsNullOrWhiteSpace($p_urls.specifiedAssetName)) {
        $specifiedAssetName = $p_urls.specifiedAssetName
        Write-Host "        Specified Asset Name: " -NoNewline -ForegroundColor Magenta
        Write-Host $specifiedAssetName
    }

    if (-not [string]::IsNullOrWhiteSpace($p_urls.tag)) {
        $tag = $p_urls.tag
        Write-Host "        Tag: " -NoNewline -ForegroundColor Magenta
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
    Write-Host "    Selected asset: " -NoNewline -ForegroundColor Yellow
    Write-Host $selectedAsset.name

    # Determine file type from asset name
    $fileType = Get-Filetype -p_fileName $selectedAsset.name
    Write-Host "    File type: " -NoNewline -ForegroundColor Yellow
    Write-Host $fileType
    # Determine silent installation arguments based on file type
    $silentArgs = Get-SilentArgs -p_fileType $fileType
    Write-Host "    Silent arguments: " -NoNewline -ForegroundColor Yellow
    Write-Host $silentArgs

    # Find the root repository
    # get the url from the latest release info and replace everything after the repo name with nothing
    $baseRepoUrl_Info = $latestReleaseInfo_GETINFO.url -replace '/releases/.*', ''
    Write-Host "    Base Repo URL: " -NoNewline -ForegroundColor Yellow
    Write-Host $baseRepoUrl_Info
    $rootRepoInfo = Get-RootRepository -p_repoUrl $baseRepoUrl_Info
    Write-Host "    Root Repo URL: " -NoNewline -ForegroundColor Yellow
    Write-Host $rootRepoInfo.url

    # Get the default branch of the root repository
    # TODO: I am sure this is redundant. It is late and this is a quick fix.
    $baseRepoInfo = (Invoke-WebRequest -Uri "$($baseRepoUrl_Info)").Content | ConvertFrom-Json

    $myDefaultBranch = "$($baseRepoInfo.default_branch)"
    Write-Host "Default Branch (Root): " -ForegroundColor Yellow
    Write-Host "`"$myDefaultBranch`""
    


    #TODO: Make sure we are getting the largest favicon


# Initial variable declaration
$iconUrl = $null
$iconInfo = $null

# Check if the root repository has a homepage
if (-not [string]::IsNullOrWhiteSpace($rootRepoInfo.homepage)) {
    $homepage = $rootRepoInfo.homepage

    # Attempt to get the favicon from the homepage
    $iconInfo = Get-Favicon -p_homepage $homepage

    if ($null -ne $iconInfo.url) {
        Write-Host "    Found Favicon on Homepage: " -ForegroundColor Yellow -NoNewline
        Write-Host $iconInfo.url
        $iconUrl = $iconInfo.url
    } else {
        Write-Host "    No Favicon found on Homepage. Looking for alternatives..." -ForegroundColor Yellow
    }
}

# If no suitable favicon is found, look for an ICO file in the repo
if ($null -eq $iconUrl) {
    $icoPath = Find-IcoInRepo -owner $p_urls.githubUser -repo $p_urls.githubRepoName -defaultBranch $myDefaultBranch
    
    if ($null -ne $icoPath) {
        $iconUrl = "https://raw.githubusercontent.com/$($p_urls.githubUser)/$($p_urls.githubRepoName)/main/$icoPath"
        Write-Host "    Found ICO file in Repo: $iconUrl" -ForegroundColor Green
    }
}

# If still no suitable icon is found, use the owner's avatar
if ($null -eq $iconUrl) {
    $iconUrl = $rootRepoInfo.owner.avatar_url
    Write-Host "    Using owner's avatar as icon: $iconUrl" -ForegroundColor Green
}

    

    # TODO: Check if the org name or repo name most closely match the name of the file, use the one that most closely matches


    # If the owner of the root repository is an organization, use the organization name as package name
    if ($rootRepoInfo.owner.type -eq 'Organization') {
        $orgName = $rootRepoInfo.owner.login
        Write-Host "    Updated orgName to Organization Name: " -NoNewline -ForegroundColor Yellow
    Write-Host $orgName
    }

    # Get the description
    # Write-Host "    Passing rootRepoInfo to Get-Description: " -NoNewline -ForegroundColor Yellow
    # Write-Host $rootRepoInfo
    # If the description is null or empty, get the description from the root repository
    if ([string]::IsNullOrWhiteSpace($rootRepoInfo.description)) {
        $description = $rootRepoInfo.description
        # If the description is still null, get content of the readme
        if ([string]::IsNullOrWhiteSpace($rootRepoInfo.description)){
            $readmeInfo = (Invoke-WebRequest -Uri "$($baseRepoUrl_Info.url/"readme")").Content | ConvertFrom-Json
            $description = $readmeInfo.content
            Write-Host "    Description not found. Using readme content" -ForegroundColor Yellow
        }
        else {
            Write-Host "    Description could not be found."
            $description = "Description could not be found."
        }
    }
    else {
        $description = $rootRepoInfo.description
    }

    Write-Host "    Description: " -NoNewline -ForegroundColor Yellow
    Write-Host $description


    # Get the latest release version number
    $rawVersion = $latestReleaseInfo_GETINFO.tag_name
    Write-Host "    Raw Version: " -NoNewline -ForegroundColor Yellow
    Write-Host $rawVersion
    # Sanitize the version number
    $sanitizedVersion = ConvertTo-SanitizedNugetVersion -p_rawVersion $rawVersion
    Write-Host "    Sanitized Version: " -NoNewline -ForegroundColor Yellow
    Write-Host $sanitizedVersion

    # If specifiedasset is not null or empty print it
    if (-not [string]::IsNullOrWhiteSpace($specifiedAssetName)) {
        # If the asset name contains the version number, remove it.
    if ($specifiedAssetName -match $tag) {
        $cleanedSpecifiedAssetName = $specifiedAssetName -replace $tag, ''
        # Split by . and remove the last element if it is a valid extension
        $cleanedSpecifiedAssetName = $cleanedSpecifiedAssetName.Split('.') | Where-Object { $_ -notin $acceptedExtensions }
    }   
    else {
        $cleanedSpecifiedAssetName = $specifiedAssetName
    }
    # Clean package name to avoid errors such as this:The package ID 'Ryujinx.release-channel-master.ryujinx--win_x64.zip' contains invalid characters. Examples of valid package IDs include 'MyPackage' and 'MyPackage.Sample'.
    $cleanedSpecifiedAssetName = ".$cleanedSpecifiedAssetName" -replace '[^a-zA-Z0-9.]', ''
    # Remove remaining leading and trailing special characters
    $cleanedSpecifiedAssetName = $cleanedSpecifiedAssetName.Trim('.-_')
    Write-Host "    Cleaned Specified Asset Name: " -NoNewline -ForegroundColor Yellow
    Write-Host $cleanedSpecifiedAssetName
    }

    # Set the package name
    $packageName = "${githubUser}.${githubRepoName}.${cleanedSpecifiedAssetName}"
    # If the name contains the version number exactly, remove the version number from the package name
    if ($packageName -match $sanitizedVersion) {
        $packageName = $packageName -replace $sanitizedVersion, ''
    }
    # Convert to valid package name
    $packageName = ConvertTo-ValidPackageName -p_packageName $packageName
    
    # If the org name is not null or empty, use it as the repo name
    if (-not [string]::IsNullOrWhiteSpace($orgName)) {
        $githubRepoName = $orgName
    }

    #Initialize licenseUrl
    $licenseUrl = $null
    # Set thhe license URL to the license URL of the root repository if it is not null or whitespace
    if (-not [string]::IsNullOrWhiteSpace($rootRepoInfo.license.url)) {
        # Set the license url equal to (repo url)/blob/(default branch)/LICENSE
        $licenseUrl = "$($rootRepoInfo.html_url)/blob/$($rootRepoInfo.default_branch)/LICENSE"
        Write-Host "    License URL: " -NoNewline -ForegroundColor Yellow
        Write-Host $licenseUrl
    }

    $packageSize = $selectedAsset.size

    Write-Host "    Package Size: " -NoNewline -ForegroundColor Yellow
    Write-Host $packageSize

    # Create package metadata object as a hashtable
    $packageMetadata        = @{
        PackageName         = $packageName
        Version             = $sanitizedVersion
        Author              = $githubUser
        Description         = $description
        VersionDescription  = $latestReleaseInfo_GETINFO.body -replace "\r\n", " "
        Url                 = $selectedAsset.browser_download_url
        ProjectUrl          = $repo
        FileType            = $fileType
        SilentArgs          = $silentArgs
        IconUrl             = $iconUrl
        GithubRepoName      = $githubRepoName
        LicenseUrl          = $licenseUrl
        PackageSize         = $packageSize
    }

    if ($packageMetadata -is [System.Collections.Hashtable]) {
        Write-Host "    Type of packageMetadata before return: " -NoNewline -ForegroundColor Yellow
    Write-Host $($packageMetadata.GetType().FullName)
    } else {
        Write-Host "    Type of packageMetadata before return: NOT Hashtable"
        
    }
    
    Write-Host "    Final Check of packageMetadata: " -NoNewline -ForegroundColor Yellow
    Write-Host $($packageMetadata.GetType().FullName)
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
    Write-Host "Metadata"
    return $packageMetadata
}
function Initialize-URLs{
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_repoUrl
    )
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
Write-Host "Initialize-URLs function"
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
    Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "URLs Hashtable"
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
    if ([string]::IsNullOrWhiteSpace($repoUrl)) {
        Write-Error "Please provide a URL as an argument."
        exit 1
    }
    Write-Host "ENTERING: " -NoNewLine -ForegroundColor Cyan
    Write-Host "Initialize-GithubPackage function"
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
    Write-LogHeader "Getting Asset Info"
    #region Get Asset Info

    # Get the asset metadata
    Write-Host "Passing Latest Release Info to Get-AssetInfo: " -ForegroundColor Yellow
    # Write the content of latestReleaseInfo_GHP one per line with the key in Cyan and the value in white
    $latestReleaseInfo_GHP.PSObject.Properties | ForEach-Object {
        Write-Host "    $($_.Name): " -NoNewline -ForegroundColor Yellow
        # Check if the value is null or empty
        if ([string]::IsNullOrWhiteSpace($_.Value)) {
            Write-Host "null" -ForegroundColor White
        }
        else {
            Write-Host "Exists"
        }
    }

    Write-Host "Passing URLs to Get-AssetInfo: " -ForegroundColor Yellow
    # Write the content of the hashtable one per line
    $urls.GetEnumerator() | ForEach-Object {
        Write-Host "    $($_.Key): " -NoNewline -ForegroundColor Yellow
        if ([string]::IsNullOrWhiteSpace($_.Value)) {
            Write-Host "null" -ForegroundColor White
        }
        else {
            Write-Host "Exists"
        }
    }

    # Check if myMetadata already exists
    if ($null -ne $myMetadata) {
        Write-Host "`nmyMetadata already exists: " -NoNewline -ForegroundColor Yellow
    Write-Host $myMetadata.GetEnumerator() | ForEach-Object { 
            Write-Host "    $($_.Key): " -NoNewline -ForegroundColor Yellow
            if ([string]::IsNullOrWhiteSpace($_.Value)) {
                Write-Host "null" -ForegroundColor White
            }
            else {
                Write-Host "Exists"
            }
        }
    }
    else {
        Write-Host "`nmyMetadata does not exist yet`n"
    Write-Host "    Evicence: " -NoNewline -ForegroundColor Yellow
    Write-Host "`"$myMetadata`"`n"
    }

    Write-Host "Passing variables to Get-AssetInfo: " -ForegroundColor Yellow
    Write-Host "    Type of latestReleaseInfo_GHP: $($latestReleaseInfo_GHP.GetType().FullName)"
    Write-Host "    Data in latestReleaseInfo_GHP: " -ForegroundColor Yellow
    Write-Host "            $($latestReleaseInfo_GHP.PSObject.Properties)" | ForEach-Object {
        # Print up to the first 100 characters of the name
        Write-Host "        Name: " -write-host -NoNewline -ForegroundColor Yellow
    Write-Host "$($_.Name.Substring(0, [Math]::Min(100, $_.Name.Length)))" -ForegroundColor Yellow
        # Check if the value is null or empty
        if ([string]::IsNullOrWhiteSpace($_.Value)) {
            Write-Host "null" -ForegroundColor White
        }
        else {
            # Print up to the first 100 characters of the value
            Write-Host "Value: " -NoNewline -ForegroundColor Yellow
            Write-Host "$($_.Value.Substring(0, [Math]::Min(100, $_.Value.Length)))"
        }
    }
    Write-Host "    Type of urls: " -ForegroundColor Yellow
    Write-Host $($urls.GetType().FullName)
    Write-Host "    Data in urls: " -ForegroundColor Yellow
    Write-Host "            $($urls.GetEnumerator())" | ForEach-Object {
        # Print up to the first 100 characters of the name
        Write-Host "        $($_.Name.Substring(0, [Math]::Min(100, $_.Name.Length))): " -NoNewline -ForegroundColor Yellow
        # Check if the value is null or empty
        if ([string]::IsNullOrWhiteSpace($_.Value)) {
            Write-Host "null" -ForegroundColor White
        }
        else {
            # Print up to the first 100 characters of the value
            Write-Host "$($_.Value.Substring(0, [Math]::Min(100, $_.Value.Length)))" -ForegroundColor Magenta
        }
    }
 
    Write-Host "##################################################"

    $myMetadata = Get-AssetInfo -latestReleaseInfo_GETINFO $latestReleaseInfo_GHP -p_urls $urls

    Write-Host "Type of myMetadata AFTER ASSET-INFO: $($myMetadata.GetType().FullName)"
    Write-Host "`nMetadata Object's Content: " -ForegroundColor Yellow
    # Display the contents of the metadata hashtable
    $myMetadata.GetEnumerator() | ForEach-Object {
        Write-Host "    $($_.Key): " -NoNewline -ForegroundColor Yellow
        if ([string]::IsNullOrWhiteSpace($_.Value)) {
            Write-Host "null" -ForegroundColor White
        }
        else {
            # Display the value
            Write-Host "$($_.Value)"
        }
    }

    #Write-Host "    Package Metadata From Initialize-GithubPackage Method:" -ForegroundColor Yellow
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

    # Write the type of the metadata object
    Write-Host "Type of myMetadata before NUSPEC: " -NoNewline -ForegroundColor Magenta
    Write-Host $($myMetadata.GetType().FullName)

    # Create the nuspec file and install script
    $nuspecPath = New-NuspecFile -p_Metadata $myMetadata -p_packageDir $packageDir
    Write-Host "    Nuspec file created at: " -NoNewline -ForegroundColor Yellow
    Write-Host $nuspecPath
    $installScriptPath = New-InstallScript -p_Metadata $myMetadata -p_toolsDir $toolsDir

    #endregion
    ###################################################################################################
    Write-LogHeader "Creating Chocolatey Package"
    #region Create Chocolatey Package

    # Create the Chocolatey package
    New-ChocolateyPackage -p_nuspecPath $nuspecPath -p_packageDir $packageDir

    #endregion
    ###################################################################################################
Write-Host "EXITING: " -NoNewLine -ForegroundColor Green
Write-Host "Initialize-GithubPackage function"
}
###################################################################################################

$acceptedExtensions = @('exe', 'msi', 'zip')
