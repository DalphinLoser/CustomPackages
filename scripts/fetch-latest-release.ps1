$ErrorActionPreference = 'Stop'
###################################################################################################
#region Functions

#region Debugging
function Get-ObjectProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Object]$Object,

        [Parameter()]
        [int]$MaxDepth = 4
    )

    $currentColor = 'DarkGreen'

    function Get-InternalProperties {
        param (
            [Object]$Obj,
            [string]$Indent,
            [int]$Depth
        )

        if ($Depth -ge $MaxDepth) {
            Write-Host "${Indent}... (max depth reached)" -ForegroundColor DarkYellow
            return
        }

        $props = if ($Obj -is [PSCustomObject]) {
            $Obj.PSObject.Properties
        } elseif ($Obj -is [Hashtable]) {
            $Obj.GetEnumerator() | ForEach-Object { 
                New-Object PSObject -Property @{
                    Name = $_.Key
                    Value = $_.Value
                }
            }
        } elseif ($Obj -is [Array]) {
            $Obj | ForEach-Object -Begin { $i = 0 } -Process {
                New-Object PSObject -Property @{
                    Name = "Index $i"
                    Value = $_
                }
                $i++
            }
        } else {
            Write-Host "${Indent}Unsupported type: $($Obj.GetType().Name)" -ForegroundColor Red
            return
        }

        foreach ($prop in $props) {
            $propType = if ($null -ne $prop.Value) { $prop.Value.GetType().Name } else { '<null>' }
            $propValue = if (-not [string]::IsNullOrWhiteSpace($prop.Value)) {
                $prop.Value.ToString() -replace "`r`n|`r|`n", " "
            } else {
                '<empty or whitespace>'
            }

            if ($prop.Value -is [Array]) {
                $propType = 'Object[]'
                $propValue = "<array of $($prop.Value.Length) items>"
            }
            elseif ($prop.Value -is [PSCustomObject]) {
                $propType = 'PSCustomObject'
                $propValue = "<custom object>"
            }
            elseif ($prop.Value -is [Hashtable]) {
                $propType = 'Hashtable'
                $propValue = "<hashtable with $($prop.Value.Count) items>"
            }

            # Toggle color for the whole group
            $currentColor = if ($currentColor -eq 'DarkGreen') { 'DarkCyan' } else { 'DarkGreen' }

            Write-Host "$Depth" -NoNewline
            Write-Host "$Indent| Name: " -NoNewline -ForegroundColor $currentColor
            Write-Host "$($prop.Name)" -BackgroundColor DarkGray
            Write-Host "$Depth" -NoNewline
            if ($prop.Value -is [PSCustomObject] -or $prop.Value -is [Hashtable] -or $prop.Value -is [Array]) {
                $index = 0
                foreach ($item in $prop.Value) {
                    Write-Host "$Indent| Type: $propType" -ForegroundColor $currentColor
                    Get-InternalProperties -Obj $item -Indent "$Indent    " -Depth ($Depth + 1)
                    $index++
                }
            } else {
                Write-Host "$Indent| Type: $propType" -ForegroundColor $currentColor
                Write-Host "$Depth" -NoNewline
                Write-Host "$Indent| Value: $propValue" -ForegroundColor $currentColor
            }
        }
    }

    Get-InternalProperties -Obj $Object -Indent "   " -Depth 1
}

function Write-LogHeader {
    param (
        [string]$Message,
        [System.ConsoleColor]$Color
    )
    # If a color is not specified, use Dark Gray
    if (-not $Color) {
        $Color = 'DarkGray'
    }
    Write-Host "`n=== [ ENTER: $Message ] ===" -BackgroundColor $Color
}
function Write-LogFooter {
    param (
        [string]$Message,
        [System.ConsoleColor]$Color
    )
    # If a color is not specified, use Dark Gray
    if (-not $Color) {
        $Color = 'DarkGray'
    }
    Write-Host "=== [ EXIT: $Message ] ===" -BackgroundColor $Color
    Write-Host
}
#endregion

#region Get-Assets and Information
function Find-IcoInRepo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$owner,

        [Parameter(Mandatory=$true)]
        [string]$repo,

        [Parameter(Mandatory=$true)]
        [string]$defaultBranch
    )

    Write-LogHeader "Find-IcoInRepo function"
    $token = $env:GITHUB_TOKEN

    Write-Host "Default branch recieved: $defaultBranch"

    if (-not $token) {
        Write-Error "ERROR: GITHUB_TOKEN environment variable not set. Please set it before proceeding."
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
        Write-Error "ERROR: Failed to query GitHub API."
        exit 1
    }

    # Filter for files with .ico extension
    $icoFiles = $response.tree | Where-Object { $_.type -eq 'blob' -and $_.path -like '*.ico' }

    if ($icoFiles.Count -gt 0) {
        Write-LogFooter "Find-IcoInRepo function (Found)"
        return $icoFiles[0].path
    } else {
        Write-LogFooter "Find-IcoInRepo function (Not Found)"
        return
    }
}
function Get-Favicon {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Homepage
    )

    Write-Host "---------- Script Start ----------" -ForegroundColor Cyan

    #region Fetching webpage content
    Write-Host "Fetching webpage content from $Homepage" -ForegroundColor Yellow
    try {
        $webRequest = Invoke-WebRequest -Uri $Homepage
    } catch {
        Write-Host "Failed to fetch webpage content. Please check your internet connection and the URL." -ForegroundColor Red
        return $null
    }
    #endregion
    
    # Strip everything after the domain name
    $HomepageTld = $Homepage -replace '^(https?://[^/]+).*', '$1'

    # Output Information
    Write-Host "    Homepage: " -ForegroundColor Yellow -NoNewline
    Write-Host "$Homepage"
    Write-Host "    Homepage TLD: " -ForegroundColor Yellow -NoNewline
    Write-Host "$HomepageTld"

    # Regex for matching all icon links
    $regex = "<link[^>]*rel=`"(icon|shortcut icon)`"[^>]*href=`"([^`"]+)`""
    $iconMatches = $webRequest.Content | Select-String -Pattern $regex -AllMatches

    if ($null -ne $iconMatches) {
        $icons = $iconMatches.Matches | ForEach-Object { 
            $faviconRelativeLink = $_.Groups[2].Value
            if ($faviconRelativeLink -match "^(https?:\/\/)") {
                $faviconRelativeLink  # It's already an absolute URL
            } elseif ($faviconRelativeLink -match "^/") {
                "$HomepageTld$faviconRelativeLink"
            } else {
                "$HomepageTld/$faviconRelativeLink"
            }
        }  
        
        Write-Host "    Available Icons: " -ForegroundColor Yellow
        Write-Host "    $($icons -join ', ')"

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

    Write-Host "    Analyzing file: " -ForegroundColor Yellow -NoNewline
    Write-Host "$filePath"
    

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
                Write-Host "    PNG Dimensions: " -ForegroundColor Green -NoNewline
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
function Select-Asset {
    param (
        [Parameter(Mandatory=$true)]
        # PSCustomCbject
        [System.Object[]]$LatestReleaseObj,

        [Parameter(Mandatory=$true)]
        [hashtable]$PackageData
    )

    Write-LogHeader "Select-Asset function"

    $specifiedAssetName = $PackageData.specifiedAssetName
    
  

    $baseRepoApiUrl= $PackageData.baseRepoApiUrl
    # Validation check for the assets
    $f_supportedTypes = $acceptedExtensions

    # Validate that assets is not null or empty
    if ($null -eq $LatestReleaseObj.assets -or $LatestReleaseObj.assets.Count -eq 0) {
        Write-Error "No assets found for the latest release. LatestReleaseObj is Null or Empty"
        exit 1
    }

    # If an asset name is providid, select the asset with that name. If not, select the first asset with a supported type.
    if (-not [string]::IsNullOrWhiteSpace($specifiedAssetName)) {
        # if the specified asset name contains the version number, replace it with the version number from the latest release
        if ($specifiedAssetName -match $PackageData.tag) {
            $cleanedSpecifiedAssetName = $specifiedAssetName -replace $PackageData.tag, $LatestReleaseObj.tag_name
            Write-Host "    Specified Asset Name contains version number. Replacing with version number from latest release: " -ForegroundColor Yellow
            Write-Host "    `"$specifiedAssetName`""
            Write-Host "    `"$cleanedSpecifiedAssetName`""
            $specifiedAssetName = $cleanedSpecifiedAssetName
        }
        Write-Host "    Selecting asset with name: " -ForegroundColor Yellow -NoNewline
        Write-Host "`"$specifiedAssetName`""
        $f_selectedAsset = $LatestReleaseObj.assets | Where-Object { $_.name -eq $specifiedAssetName }
        # If there is no match for the asset name, throw an error
        if ($null -eq $f_selectedAsset) {
            # If there is still no match, throw an error
            Write-Error "No asset found with name: `"$specifiedAssetName`""
            exit 1
        }
    } else {
        $f_selectedAsset = $LatestReleaseObj.assets | 
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

    Write-LogFooter "Selected Asset"
    return $f_selectedAsset
}
function Get-RootRepository {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_repoUrl
    )
    Write-LogHeader "Get-RootRepository function"
    Write-Host "    Getting root repository for: " -NoNewline -ForegroundColor Yellow
    Write-Host $p_repoUrl
    
    # Broken TODO: This is broken. It is not returning the root repo

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
        Write-LogFooter "root repository info"
        return $repoInfo
    }
}
function Get-Filetype {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_fileName,
        [string[]]$p_acceptedExtensions = $acceptedExtensions
    )
    Write-LogHeader "Get-Filetype function"

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
        Write-LogFooter "File Type"
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
    Write-LogHeader "Get-SilentArgs function"
    
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

    Write-LogFooter "Silent Args"
    return $f_silentArgs
}
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
function Get-LatestReleaseObject {
    param (
        [Parameter(Mandatory=$true)]
        [string]$LatestReleaseApiUrl
    )

    Write-LogHeader "Get-LatestReleaseObject"
    Write-Host "    Target GitHub API URL: $LatestReleaseApiUrl"

    Write-Host "    Initiating web request to GitHub API..."
    $response = Invoke-WebRequest -Uri $LatestReleaseApiUrl
    Write-Host "    HTTP Status Code: $($response.StatusCode)"

    
    $latestReleaseObj = $response | ConvertFrom-Json
    # Content of latestReleaseObj
    Write-Host "Type of latestReleaseObj: " -NoNewline -ForegroundColor Yellow
    Write-Host $latestReleaseObj.GetType().Name
    
    if ($null -eq $latestReleaseObj) {
        Write-Error "   Received data is null. URL used: $LatestReleaseApiUrl"
        exit 1
    }

    # Make sure the assets field is not null or empty
    $assetCount = ($latestReleaseObj.assets | Measure-Object).Count
    if ($null -eq $latestReleaseObj.assets -or $assetCount -eq 0) {
        Write-Error "   No assets found for the latest release. URL used: $LatestReleaseApiUrl"
        exit 1
    }

    Write-LogFooter "Get-LatestReleaseObject"
    return $latestReleaseObj
}
function Get-AssetInfo {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$PackageData
    )
    Write-LogHeader "Get-AssetInfo function"
    
    $retreivedLatestReleaseObj = Get-LatestReleaseObject -LatestReleaseApiUrl $PackageData.latestReleaseApiUrl

    # Select the best asset based on supported types
    $selectedAsset = Select-Asset -LatestReleaseObj $retreivedLatestReleaseObj -PackageData $PackageData
    Write-Host "Selected asset name: " -NoNewline -ForegroundColor Yellow
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
    $PackageData.baseRepoApiUrl = $retreivedLatestReleaseObj.url -replace '/releases/.*', ''
    Write-Host "    Base Repo URL: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageData.baseRepoApiUrl
    $rootRepoInfo = Get-RootRepository -p_repoUrl $PackageData.baseRepoApiUrl
    Write-Host "    Root Repo URL: " -NoNewline -ForegroundColor Yellow
    Write-Host $rootRepoInfo.url

    # Get the default branch of the root repository
    # TODO: I am sure this is redundant. It is late and this is a quick fix.
    $baseRepoInfo = (Invoke-WebRequest -Uri "$($PackageData.baseRepoApiUrl)").Content | ConvertFrom-Json

    $myDefaultBranch = "$($baseRepoInfo.default_branch)"
    Write-Host "Default Branch (Root): " -ForegroundColor Yellow
    Write-Host "`"$myDefaultBranch`""
    

    # Array table to store the tags. Uses the topics json result from the GitHub API
    $tags = @()
    # If the result is not null or empty or whitespace, add the tags to the hash table from the base repo info. Otherwise, add the tags from the root repo info.
    if (-not [string]::IsNullOrWhiteSpace($baseRepoInfo.topics)) {
        $tags += $baseRepoInfo.topics
        Write-Host "    Tags from base repo info: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($baseRepoInfo.topics)"
    } elseif (-not [string]::IsNullOrWhiteSpace($rootRepoInfo.topics)) {
        $tags += $rootRepoInfo.topics
        Write-Host "    Tags from root repo info: " -NoNewline -ForegroundColor Yellow
        Write-Host "$($rootRepoInfo.topics)"
    }
    else {
        Write-Host "No tags found."
    }
    

    Write-Host "Tags is of type: " -NoNewline -ForegroundColor Yellow
    Write-Host $tags.GetType().Name

    # if the tags array is not null or empty, print the tags
    if ($null -ne $tags -and $tags.Count -gt 0) {
        Write-Host "    Tags: " -ForegroundColor Yellow
        $tags | ForEach-Object {
            Write-Host "    $_"
        }
    } else {
        Write-Host "    No tags found."
    }

    # Initial variable declaration
    $iconUrl = $null
    $iconInfo = $null

    # Check if the root repository has a homepage
    if (-not [string]::IsNullOrWhiteSpace($rootRepoInfo.homepage)) {
        $homepage = $rootRepoInfo.homepage

        # Attempt to get the favicon from the homepage
        $iconInfo = Get-Favicon -Homepage $homepage

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
        $icoPath = Find-IcoInRepo -owner $PackageData.user -repo $PackageData.repoName -defaultBranch $myDefaultBranch
        
        if ($null -ne $icoPath) {
            $iconUrl = "https://raw.githubusercontent.com/$($PackageData.user)/$($PackageData.repoName)/main/$icoPath"
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
            $readmeInfo = (Invoke-WebRequest -Uri "$($PackageData.baseRepoApiUrl.url/"readme")").Content | ConvertFrom-Json
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
    $rawVersion = $retreivedLatestReleaseObj.tag_name
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
    $chocoPackageName = "$($PackageData.user).$($PackageData.repoName).$($PackageData.cleanedSpecifiedAssetName)"
    # If the name contains the version number exactly, remove the version number from the package name
    if ($chocoPackageName -match $sanitizedVersion) {
        Write-Host "Package name: " -NoNewline -ForegroundColor Yellow
        Write-Host $chocoPackageName -NoNewline
        Write-Host " contains version number: " -NoNewline -ForegroundColor Yellow
        Write-Host $sanitizedVersion
        $chocoPackageName = $chocoPackageName -replace $sanitizedVersion, ''
    }
    Write-Host "    Package Name: " -NoNewline -ForegroundColor Yellow
    Write-Host $chocoPackageName
    # Convert to valid package name
    $chocoPackageName = ConvertTo-ValidPackageName -PackageName $chocoPackageName
    
    # If the org name is not null or empty, use it as the repo name
    if (-not [string]::IsNullOrWhiteSpace($orgName)) {
        $githubRepoName = $orgName
    }

    #Initialize licenseUrl
    $licenseUrl = $null
    # Set thhe license URL to the license URL of the root repository if it is not null or whitespace
    if (-not [string]::IsNullOrWhiteSpace($rootRepoInfo.license.url)) {
        # Set the license url equal to (repo url)/blob/(default branch)/LICENSE
        $licenseUrl = "$($rootRepoInfo.html_url)/blob/$myDefaultBranch/LICENSE"
        Write-Host "    License URL: " -NoNewline -ForegroundColor Yellow
        Write-Host $licenseUrl
    } elseif (-not [string]::IsNullOrWhiteSpace($baseRepoInfo.license.url)) {
        # Set the license url equal to (repo url)/blob/(default branch)/LICENSE
        $licenseUrl = "$($baseRepoInfo.html_url)/blob/$myDefaultBranch/LICENSE"
        Write-Host "    License URL: " -NoNewline -ForegroundColor Yellow
        Write-Host $licenseUrl
    } else {
        Write-Host "    No license URL found."
    }

    $packageSize = $selectedAsset.size

    Write-Host "    Package Size: " -NoNewline -ForegroundColor Yellow
    Write-Host $packageSize

    # Build the URL for the API request
    $hashUrl = "https://api.github.com/repos/$($PackageData.user)/$($PackageData.repoName)/git/refs/tags/$($retreivedLatestReleaseObj.tag_name)"

    # Make the API request
    $response = Invoke-RestMethod -Uri $hashUrl

    # Extract the commit hash from the response
    $commitHash = $response.object.sha

    # Output the commit hash
    Write-Host "    Commit Hash: " -NoNewline -ForegroundColor Yellow
    Write-Host $commitHash

    # repository variable in format : <repository type="git" url="https://github.com/NuGet/NuGet.Client.git" branch="dev" commit="e1c65e4524cd70ee6e22abe33e6cb6ec73938cb3" />
    $nu_repoUrl = " type=`"git`" url=`"$($rootRepoInfo.html_url)`" branch=`"$($rootRepoInfo.default_branch)`" commit=`"$($commitHash)`" "

    # Shoule probably (maybe) use root instead
    $licenseUrl = "$($PackageData.baseRepoUrl)/blob/$myDefaultBranch/LICENSE"
    Write-Host "    License URL: " -NoNewline -ForegroundColor Yellow

    Write-Host "    Repository: " -NoNewline -ForegroundColor Yellow
    Write-Host $nu_repoUrl

    $tagsStr = $tags -join ' '

    # $packageTitle = Get-MostSimilarString -key "ProtonVPN_v3.2.1.exe" -strings @("maah", "ProtonVPN-win-app", "ProtonVPN")
    $packageTitle = Get-MostSimilarString -key $selectedAsset.name -strings @($PackageData.user, $PackageData.repoName, $rootRepoInfo.name)

    Write-Host "    Package Title: " -NoNewline -ForegroundColor Yellow
    Write-Host $packageTitle

    # Create package metadata object as a hashtable
    $packageMetadata        = @{
        PackageName         = $chocoPackageName
        Version             = $sanitizedVersion
        Author              = $PackageData.user
        Description         = $description
        VersionDescription  = $retreivedLatestReleaseObj.body -replace "\r\n", " "
        Url                 = $selectedAsset.browser_download_url
        ProjectUrl          = $PackageData.baseRepoUrl
        FileType            = $fileType
        SilentArgs          = $silentArgs
        IconUrl             = $iconUrl
        GithubRepoName      = $packageTitle
        LicenseUrl          = $licenseUrl
        PackageSize         = $packageSize
        Tags                = $tagsStr
        # Repository          = $nu_repoUrl
        # ProjectSiteUrl      = $homepage
    }

    if ($packageMetadata -is [System.Collections.Hashtable]) {
        Write-Host "    Type of packageMetadata before return: " -NoNewline -ForegroundColor Yellow
        Write-Host $($packageMetadata.GetType().Name)
    } else {
        Write-Host "    Type of packageMetadata before return: NOT Hashtable"
    }
    
    Write-Host "    Final Check of packageMetadata: " -NoNewline -ForegroundColor Yellow
    Write-Host $($packageMetadata.GetType().Name)
    Write-LogFooter "Get-AssetInfo function"
    # Ensure that the package metadata is returned as a hashtable
    return $packageMetadata
}
#endregion

#region Process and Validate Arguments
function ConvertTo-ValidPackageName {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PackageName
    )
    Write-LogHeader "ConvertTo-ValidPackageName"

    Write-Host "    Package name before conversion: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageName

    # Check for invalid characters and spaces
    if (-not ($PackageName -match '^[a-z0-9._-]+$') -or $PackageName.Contains(' ')) {
        Write-Host "    Invalid characters or spaces found in package name: " -NoNewline -ForegroundColor Yellow
        Write-Host $PackageName
        # Remove invalid characters and spaces
        $PackageName = $PackageName -replace ' ', '-'
        $PackageName = $PackageName -replace '[^a-z0-9._-]', ''
        Write-Host "    Package name after removing invalid characters and spaces: " -NoNewline -ForegroundColor Yellow
        Write-Host $PackageName
    }

    Write-Host "    Removing and consolidating groupings of dots, underscores, and hyphens: " -NoNewline -ForegroundColor Yellow
    $PackageName = $PackageName -replace '[-]+', '-'  # Remove and consolidate groupings of hyphens
    Write-Host $PackageName
    Write-Host "    Package name after removing and consolidating groupings of hyphens: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageName
    $PackageName = $PackageName -replace '[_]+', '_'  # Remove and consolidate groupings of underscores
    Write-Host "    Package name after removing and consolidating groupings of underscores: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageName
    $PackageName = $PackageName -replace '[.]+', '.'  # Remove and consolidate groupings of dots
    Write-Host "    Package name after removing and consolidating groupings of dots: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageName
    $PackageName = $PackageName -replace '([-_.])\1+', '.' # Remove and consolidate groupings of dots, underscores, and hyphens
    Write-Host "    Package name after removing and consolidating groupings of dots, underscores, and hyphens: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageName
    $PackageName = $PackageName.Trim('-._')  # Remove leading and trailing hyphens, underscores, and dots
    Write-Host "    Package name after removing leading and trailing hyphens, underscores, and dots: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageName
    $PackageName = $PackageName.ToLower()  # Convert to lowercase
    Write-Host "    Package name after converting to lowercase: " -NoNewline -ForegroundColor Yellow
    Write-Host $PackageName

    Write-LogFooter "ConvertTo-ValidPackageName"

    return $PackageName 
}
function ConvertTo-EscapedXmlContent {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Content
    )
    Write-LogHeader "ConvertTo-EscapedXmlContent function"
    Write-Host "    Escaping XML Content: " -NoNewline -ForegroundColor Yellow
    Write-Host $Content
    $escapedContent = $Content -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
    Write-LogFooter "ConvertTo-EscapedXmlContent function"
    return $escapedContent
}
function ConvertTo-SanitizedNugetVersion {
    param (
        [string]$p_rawVersion
    )
    Write-LogHeader "ConvertTo-SanitizedNugetVersion function"
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
    Write-LogFooter "Sanitized Version"
    return $f_sanitizedVersion
}
function Confirm-DirectoryExists {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_path,
        [Parameter(Mandatory=$true)]
        [string]$p_name
    )
    Write-LogHeader "Confirm-DirectoryExists function"
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
    Write-LogFooter "Confirm-DirectoryExists function"
}
#endregion

#region Create Files
function New-NuspecFile {
    param (
        [Parameter(Mandatory=$true)]
        [System.Object]$Metadata,
        [Parameter(Mandatory=$true)]
        [string]$PackageDir
    )

    Write-LogHeader "New-NuspecFile function"

    $elementMapping = @{
        id = 'PackageName'
        title = 'GithubRepoName'
        version = 'Version'
        authors = 'Author'
        description = 'Description'
        projectUrl = 'ProjectUrl'
        # projectUrl = 'ProjectSiteUrl' # The actual project site - does not always exist
        packageSourceUrl = 'Url'
        releaseNotes = 'VersionDescription'
        licenseUrl = 'LicenseUrl'
        iconUrl = 'IconUrl'
        tags = 'Tags'
        # repository = 'Repository' # Does not work with chocolatey, only nuget
        
    }

    # One per line, print the content of elementMapping
    Write-Host "Element Mapping:" -ForegroundColor Yellow
    $elementMapping.GetEnumerator() | ForEach-Object {
        Write-Host "    $($_.Key) -> $($_.Value)"
    }

    $elementOrder = @('id', 'version', 'title',  'authors', 'packageSourceUrl', 'releaseNotes', 'licenseUrl')

    $xmlDoc = (New-Object System.Xml.XmlDocument)

    $loadXml = ($xmlDoc.LoadXml('<?xml version="1.0"?><package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"><metadata></metadata></package>'))
    $nsManager = (New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable))
    $nsManager.AddNamespace('ns', 'http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd')
    $metadataElem = ($xmlDoc.SelectSingleNode('/ns:package/ns:metadata', $nsManager))

    Write-Host "Appending required elements to metadata: " -ForegroundColor Yellow

    $namespaceUri = "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"

    # Add elements in the order specified by elementOrder
    foreach ($elementName in $elementOrder) {

        #Write-Host "Processing element: $elementName" -ForegroundColor Yellow
        
        # Assuming $elementMapping is now an object with properties instead of a hashtable
        if (-not $elementMapping.PSObject.Properties.Name -contains $elementName) {
            Write-Host "Warning: $elementName not found in elementMapping" -ForegroundColor Yellow
        }
    
        $key = $elementMapping.$elementName
    
        # Assuming $Metadata is now an object with properties instead of a hashtable
        if (-not $Metadata.PSObject.Properties.Name -contains $key) {
            Write-Host "Warning: $key not found in Metadata" -ForegroundColor Yellow
        }
    
        $value = $Metadata.$key
    
        if ($null -eq $value) {
            Write-Host "Warning: Value for $key is null" -ForegroundColor Yellow
        }
    
        Write-Host "Creating element with " -NoNewline -ForegroundColor Green
        Write-Host "name: " -NoNewline -ForegroundColor Cyan
        Write-Host "$elementName" -NoNewline -ForegroundColor White
        Write-Host " value: " -NoNewline -ForegroundColor Cyan
        Write-Host "$value" -ForegroundColor White -NoNewline
    
        try {
            Write-Host "    Creating element..." -NoNewline
            $elem = ($xmlDoc.CreateElement($elementName, $namespaceUri))
            Write-Host "    Element created successfully" -ForegroundColor Green

        } catch {
            Write-Host "Error creating element $($elementName): $_" -ForegroundColor Red
        }
        $elem.InnerText = $value
        $metadataElem.AppendChild($elem)
    }
    

    # If there are remaining elemetns in elementMapping, add them to the file
    $remainingElements = $elementMapping.Keys | Where-Object { $elementOrder -notcontains $_ }
    Write-Host "Appending optional elements to metadata... " -ForegroundColor Yellow
    try {
        foreach ($elementName in $remainingElements) {
            Write-Host "Creating element with " -NoNewline -ForegroundColor Green
            Write-Host "name: " -NoNewline -ForegroundColor Cyan
            Write-Host "$elementName" -NoNewline -ForegroundColor White
            Write-Host " value: " -NoNewline -ForegroundColor Cyan
            Write-Host "$value" -ForegroundColor White -NoNewline

            $key = $elementMapping[$elementName]
            $value = $Metadata.$key

            if ($null -eq $value) {
                Write-Host "Warning: Value for $key is null" -ForegroundColor Yellow
            }

            Write-Host "    Creating element..." -NoNewline
            $elem = ($xmlDoc.CreateElement($elementName, $namespaceUri))
            $elem.InnerText = $value
            $metadataElem.AppendChild($elem)
            Write-Host "    Element created successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error creating element $($elementName): $_" -ForegroundColor Red
    }

    # Check if f_nuspecPath is null or empty
    if ([string]::IsNullOrWhiteSpace($f_nuspecPath)) {
        Write-Host "Nuspec file variable is empty (this is a good thing)" -ForegroundColor Green
    }
    else {
        Write-Host "Nuspec file variable is not empty (this is a bad thing): " -NoNewline
        Write-Host $f_nuspecPath
    }

    Write-Host "Creating nuspec path using package directory and package name" -ForegroundColor Yellow
    Write-Host "    Package Directory Type: " -NoNewline -ForegroundColor Cyan
    Write-Host $PackageDir.GetType().Name
    Write-Host "    Package Directory: " -NoNewline -ForegroundColor Cyan
    Write-Host "$PackageDir"
    Write-Host "    Package Name Type: " -NoNewline -ForegroundColor Cyan
    Write-Host $Metadata.PackageName.GetType().Name
    Write-Host "    Package Name: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($Metadata.PackageName)"

    $f_nuspecPath = Join-Path $PackageDir "$($Metadata.PackageName).nuspec"
    $result = ($xmlDoc.Save($f_nuspecPath))

    Write-Host "Nuspec file created at: $f_nuspecPath" -ForegroundColor Green
    Write-Host "    Type of f_nuspecPath: " -NoNewline -ForegroundColor Yellow
    Write-Host $f_nuspecPath.GetType().Name
    Write-Host "    Returning f_nuspecPath: " -NoNewline -ForegroundColor Yellow
    Write-Host $f_nuspecPath

    Write-LogFooter "New-NuspecFile function"
}
function New-InstallScript {
    param (
        [Parameter(Mandatory=$true)]
        [System.Object]$Metadata,
        
        [Parameter(Mandatory=$true)]
        [string]$p_toolsDir
    )

    Write-LogHeader "New-InstallScript function"

    # Validation
    if (-not $Metadata.PackageName -or -not $Metadata.ProjectUrl -or -not $Metadata.Url -or -not $Metadata.Version -or -not $Metadata.Author -or -not $Metadata.Description) {
        Write-Error "Missing mandatory metadata for install script."
        return
    }

    # Check the file type
    if ($Metadata.FileType -eq "zip") {
        $globalInstallDir = "C:\AutoPackages\$($Metadata.PackageName)"

        $f_installScriptContent = @"
`$ErrorActionPreference = 'Stop';
`$toolsDir   = "$globalInstallDir"

`$packageArgs = @{
    packageName     = "$($Metadata.PackageName)"
    url             = "$($Metadata.Url)"
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
    `$exeName = [System.IO.Path]::GetFileNameWithoutExtension(`$exe.Name)
    
    # Create Desktop Shortcut
    `$desktopShortcutPath = Join-Path `$desktopDir "`$exeName.lnk"
    `$WshShell = New-Object -comObject WScript.Shell
    `$DesktopShortcut = `$WshShell.CreateShortcut(`$desktopShortcutPath)
    `$DesktopShortcut.TargetPath = `$exe.FullName
    `$DesktopShortcut.Save()
    
    # Create Start Menu Shortcut
    `$startMenuShortcutPath = Join-Path `$startMenuDir "`$exeName.lnk"
    `$StartMenuShortcut = `$WshShell.CreateShortcut(`$startMenuShortcutPath)
    `$DesktopShortcut.TargetPath = `$exe.FullName
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
    `$exeName = [System.IO.Path]::GetFileNameWithoutExtension(`$exe.Name)
    
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
    packageName     = "$($Metadata.PackageName)"
    fileType        = "$($Metadata.FileType)"
    url             = "$($Metadata.Url)"
    softwareName    = "$($Metadata.GithubRepoName)"
    silentArgs      = "$($Metadata.SilentArgs)"
    validExitCodes  = @(0)
}

Install-ChocolateyPackage @packageArgs
"@
    }

    $f_installScriptPath = Join-Path $p_toolsDir "chocolateyInstall.ps1"
    Out-File -InputObject $f_installScriptContent -FilePath $f_installScriptPath -Encoding utf8
    Write-Host "    Install script created at: " -NoNewline -ForegroundColor Yellow
    Write-Host $f_installScriptPath



    Write-LogFooter "New-InstallScript function"
    return $f_installScriptPath
}
function New-ChocolateyPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$NuspecPath,
        [Parameter(Mandatory=$true)]
        [string]$PackageDir
    )
    Write-LogHeader "New-ChocolateyPackage function"
    # Check the type of the nuspecPath
    Write-Host "    The type of NuspecPath is: " -NoNewline -ForegroundColor Yellow
    Write-Host $NuspecPath.GetType().Name -ForegroundColor Blue
    # Write the content of the nuspecPath

    # Check for Nuspec File
    Write-Host "    Checking for nuspec file..."
    if (-not (Test-Path $NuspecPath)) {
        Write-Error "Nuspec file not found at: $NuspecPath"
        exit 1
    }
    else {
        Write-Host "    Nuspec file found at: $NuspecPath" -ForegroundColor Yellow
    }

    # Create Chocolatey package
    try {
        Write-Host "    Creating Chocolatey package..."
        choco pack $NuspecPath -Force -Verbose --out $PackageDir
    } catch {
        Write-Error "Failed to create Chocolatey package."
        exit 1
    }
    Write-LogFooter "New-ChocolateyPackage function"
}
#endregion
function Get-Updates {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PackagesDir
    )
    Write-LogHeader "Get-Updates function"

    if (-not (Test-Path $PackagesDir)) {
        Write-Error "Path is not valid: $PackagesDir"
        exit 1
    }
    Write-Host "Path is valid: $PackagesDir" -ForegroundColor Green

    $packageDirNames = Get-ChildItem -Path $PackagesDir -Directory

    foreach ($dirInfo in $packageDirNames) {
        if ([string]::IsNullOrWhiteSpace($dirInfo)) {
            Write-Error "dirInfo is null or empty"
            exit 1
        }

        Write-Host "Checking for updates for: $($dirInfo.Name)" -ForegroundColor Magenta
        $package = $dirInfo.Name

        $latestReleaseObj_UP = Get-LatestReleaseObject -LatestReleaseApiUrl "https://api.github.com/repos/$($($package -split '\.')[0])/$($($package -split '\.')[1])/releases/latest"

        Write-Host "    Latest Release Object: " -NoNewline -ForegroundColor Yellow
        Write-Host $latestReleaseObj_UP

        $nuspecFile = Get-ChildItem -Path "$($dirInfo.FullName)" -Filter "*.nuspec" -File | Select-Object -First 1

        if ($null -eq $nuspecFile) {
            Write-Error "No .nuspec file found in directory $($dirInfo.FullName)"
            continue
        }

        $nuspecFileContent = Get-Content -Path $nuspecFile.FullName -Raw
        # Find the value of the packageSourceUrl field in the nuspec file
        if ($nuspecFileContent -match '<packageSourceUrl>(.*?)<\/packageSourceUrl>') {
            $packageSourceUrl = $matches[1]
        } else {
            Write-Error "No <packageSourceUrl> tag found."
            exit 1
        }
        
        Write-Host "    Current URL: $packageSourceUrl"
        # Extract the old version number using regex. This assumes the version follows right after '/download/'
        if ($packageSourceUrl -match '/download/([^/]+)/') {
            $oldVersion = $matches[1]
        } else {
            Write-Error "Could not find the version number in the URL."
            exit 1
        }

        # Get the URL of the asset that matches the packageSourceUrl with the version number replaced the newest version number
        $latestReleaseUrl_Update = $packageSourceUrl -replace [regex]::Escape($oldVersion), $latestReleaseObj_UP.tag_name
        Write-Host "    Latest  URL: $latestReleaseUrl_Update"
        # Compate the two urls
        # Compare the two URLs
        if ($latestReleaseUrl_Update -eq $packageSourceUrl) {
            Write-Host "    The URLs are identical. No new version seems to be available." -ForegroundColor Green
        } else {
            Write-Host "    The URLs are different. A new version appears to be available." -ForegroundColor Green
            Write-Host "    Old URL: $packageSourceUrl"
            Write-Host "    New URL: $latestReleaseUrl_Update"
        }
        Write-Host "    Current Version: $oldVersion"
        Write-Host "    Latest Version: $($latestReleaseObj_UP.tag_name)"
        # If the URLs are different, update the metadata for the package
        if ($latestReleaseUrl_Update -ne $packageSourceUrl) {
            
            # Remove the old nuspec file
            Remove-Item -Path $nuspecFile -Force

            Write-Host "    Updating metadata for $package"
            Write-Host "    The latest release URL is: " -NoNewline -ForegroundColor Yellow
            Write-Host $latestReleaseUrl_Update
            # Get the new metadata
            Initialize-GithubPackage -InputUrl "$latestReleaseUrl_Update"
            # Remove the old nuspec file
            Write-Host "    Removing old nuspec file"
            
        } else {
            Write-Host "    No updates found for $package"
        }
    }
    Write-LogFooter "Get-Updates function"
}
function Initialize-PackageTable {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputGithubUrl
    )
    Write-LogHeader "Initialize-PackageTable function"
    # Check if the URL is a GitHub repository URL
    if ($InputGithubUrl -match '^https?://github.com/[\w-]+/[\w-]+') {

        # Stores an array of the URL segments, split by '/'
        $urlParts = $InputGithubUrl -split '/'
        # Get the GitHub user and repo name from the provided URL
        $githubUser = $urlParts[3]
        $githubRepoName = $urlParts[4]
        # Create the new URL's from the input URL
        $baseRepoUrl = ($InputGithubUrl -split '/')[0..4] -join '/'
        $baseRepoApiUrl = "https://api.github.com/repos/${githubUser}/${githubRepoName}"
        $latestReleaseApiUrl = ($baseRepoApiUrl + '/releases/latest')

        #region Display URL information for debugging
        Write-Host "    GitHub User: " -NoNewline -ForegroundColor Magenta
        Write-Host $githubUser
        Write-Host "    GitHub Repo Name: " -NoNewline -ForegroundColor Magenta
        Write-Host $githubRepoName
        Write-Host "    Base Repo URL: " -NoNewline -ForegroundColor Magenta
        Write-Host $baseRepoApiUrl
        #endregion
        
        # Check if asset was specified
        if ($urlParts.Length -gt 7 -and $urlParts[5] -eq 'releases' -and $urlParts[6] -eq 'download') {

            # Get the release tag and asset name from the provided URL
            $tag = $urlParts[7]
            $specifiedAssetName = $urlParts[-1]

            #region Display tag and asset name for debugging
            Write-Host "    Release tag detected: " -NoNewline -ForegroundColor Magenta
            Write-Host $tag
            Write-Host "    Asset name detected: " -NoNewline -ForegroundColor Magenta
            Write-Host $specifiedAssetName
            #endregion
        }
    }
    else {
        Write-Error "Please provide a valid GitHub repository URL. URL provided: $InputGithubUrl does not match the pattern of a GitHub repository URL. GithubUser/GithubRepoName is required. Current User: $githubUser, Current Repo Name: $githubRepoName "
        exit 1
    }

    # hash table to store the PackageTable and information
    $packageTable = @{
        baseRepoUrl             = $baseRepoUrl
        baseRepoApiUrl          = $baseRepoApiUrl
        user                    = $githubUser
        repoName                = $githubRepoName
        latestReleaseApiUrl     = $latestReleaseApiUrl
    }

    # Add optional keys if they are not null or empty
    if (-not [string]::IsNullOrWhiteSpace($tag) -and -not [string]::IsNullOrWhiteSpace($specifiedAssetName)) {
        $packageTable.Add('tag', $tag)
        $packageTable.Add('specifiedAssetName', $specifiedAssetName)
        $packageTable.Add('specifiedAssetApiUrl', "$baseRepoApiUrl/releases/download/$tag/$specifiedAssetName")
    }

    # List of expected keys. This is important as other functions will expect these keys to exist
    $requiredKeys = @('baseRepoApiUrl', 'user', 'repoName', 'latestReleaseApiUrl', 'baseRepoUrl')

    # Verify each expected key
    foreach ($key in $requiredKeys) {
        if ($packageTable.ContainsKey($key)) {
            # Key exists, check if its value is null or empty
            if ([string]::IsNullOrWhiteSpace($packageTable[$key])) {
                Write-Error "The value for '$key' is null or empty in the hash table."
                exit 1
            }
        }
        else {
            Write-Error "The key '$key' does not exist in the hash table."
            exit 1
        }
    }

    Write-LogFooter "Initialize-PackageTable function"

    # Return the hash table
    return $packageTable
}

function Get-MostSimilarString {
    param (
        [string]$key,
        [string[]]$strings
    )

    # Helper function to calculate Jaccard similarity
    function Get-JaccardSimilarity {
        param (
            [string]$str1,
            [string]$str2
        )
        $set1 = $str1.ToCharArray() | Sort-Object | Get-Unique
        $set2 = $str2.ToCharArray() | Sort-Object | Get-Unique
        $intersection = $set1 | Where-Object { $set2 -contains $_ }
        $union = $set1 + $set2 | Sort-Object | Get-Unique
        return ($intersection.Count / $union.Count)
    }

    # Helper function to find longest common substring
    function Get-LongestCommonSubstring {
        param (
            [string]$str1,
            [string]$str2
        )
        $result = ""
        $str1Length = $str1.Length
        $str2Length = $str2.Length
        $len = 0
        
        # Initialize the table as a hashtable
        $table = @{}
        for ($i = 0; $i -le $str1Length; $i++) {
            for ($j = 0; $j -le $str2Length; $j++) {
                $table["$i,$j"] = 0
            }
        }

        for ($i = 1; $i -le $str1Length; $i++) {
            for ($j = 1; $j -le $str2Length; $j++) {
                if ($str1[$i - 1] -eq $str2[$j - 1]) {
                    $table["$i,$j"] = $table["$($i - 1),$($j - 1)"] + 1
                    if ($table["$i,$j"] -gt $len) {
                        $len = $table["$i,$j"]
                        $result = $str1.Substring($i - $len, $len)
                    }
                }
            }
        }
        return $result
    }

    # Main logic of Get-MostSimilarString
    $maxSimilarity = 0
    $mostSimilarStrings = @()

    foreach ($string in $strings) {
        $similarity = Get-JaccardSimilarity -str1 $key -str2 $string
        if ($similarity -gt $maxSimilarity) {
            $maxSimilarity = $similarity
            $mostSimilarStrings = @($string)
        } elseif ($similarity -eq $maxSimilarity) {
            $mostSimilarStrings += $string
        }
    }

    $maxLcsLength = 0
    $finalString = ""

    foreach ($string in $mostSimilarStrings) {
        $lcs = Get-LongestCommonSubstring -str1 $key.ToLower() -str2 $string.ToLower()
        if ($lcs.Length -gt $maxLcsLength) {
            $maxLcsLength = $lcs.Length
            $finalString = $string
        }
    }

    $finalLcs = Get-LongestCommonSubstring -str1 $key.ToLower() -str2 $finalString.ToLower()
    return $finalString.Substring($finalString.ToLower().IndexOf($finalLcs), $finalLcs.Length)
}


#endregion
###################################################################################################
function Initialize-GithubPackage{
    param (
        [Parameter(Mandatory=$true)]
        [string]$InputUrl
    )
    Write-LogHeader -Color Blue "Initialize-GithubPackage function"
    Write-Host "    Input Received: " -NoNewline -ForegroundColor Magenta
    Write-Host $InputUrl

    # Create a hashtable to store the PackageTable
    $retrievedPackageTable = Initialize-PackageTable -InputGithubUrl $InputUrl
    
    #region Get Asset Info

    # retrievedAssetTable

    $myMetadata = Get-AssetInfo -PackageData $retrievedPackageTable

    # Set the path to the package directory and create it if it doesn't exist
    $packageDir = Join-Path (Get-Location).Path $myMetadata.PackageName
    Confirm-DirectoryExists -p_path $packageDir -p_name 'package'

    # Explicitly set the path to the tools directory and create it if it doesn't exist
    $toolsDir = Join-Path $packageDir "tools"
    Confirm-DirectoryExists -p_path $toolsDir -p_name 'tools'

    #endregion

    #region Create Nuspec File and Install Script

    # Write the type of the metadata object
    Write-Host "Type of myMetadata before NUSPEC: " -NoNewline -ForegroundColor Magenta
    Write-Host $($myMetadata.GetType().Name)

    # Create the nuspec file and install script
    New-NuspecFile -Metadata $myMetadata -PackageDir $packageDir
    Write-Host "    Nuspec File Created Successfully" -ForegroundColor Green
    
    Write-Host "    Creating Instal Script..." -NoNewline -ForegroundColor Yellow
    New-InstallScript -Metadata $myMetadata -p_toolsDir $toolsDir
    Write-Host "    Install Script Created Successfully" -ForegroundColor Green

    #endregion

    #region Create Chocolatey Package

        Write-Host "Type of packageDir before New-ChocolateyPackage: " -NoNewline -ForegroundColor Magenta
        Write-Host $($packageDir.GetType().Name)

        $nuspecPath = Join-Path $packageDir "$($myMetadata.PackageName).nuspec"

        # Check the nuspecPath System Object or string before passing it to New-ChocolateyPackage
        Write-Host "nuspecPath before New-ChocolateyPackage: " -NoNewline -ForegroundColor Magenta
        Write-Host $nuspecPath

        #endregion

        
        # Create the Chocolatey package
        New-ChocolateyPackage -NuspecPath "$nuspecPath" -PackageDir $packageDir

    #endregion
Write-LogFooter -Color Blue "Initialize-GithubPackage function"
}
###################################################################################################

# Global Variables
$acceptedExtensions = @('exe', 'msi', 'zip')
