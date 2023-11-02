. "$PSScriptRoot\logging-functions.ps1"
. "$PSScriptRoot\new-data-method.ps1"
. "$PSScriptRoot\process-and-validate.ps1"

function Select-AssetFromRelease {
    param (
        [Parameter(Mandatory = $true)]
        [System.Object[]]$LatestReleaseObj,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageData,
        
        [string[]]$AcceptedExtensions = $acceptedExtensions
    )

    Write-LogHeader "Select-AssetFromRelease"

    # Create a pscustomobject to store the latest release information
    $assets = $LatestReleaseObj.assets
    # Print the content of the pscustomobject to the console
    Write-DebugLog "    Latest Release Object Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $LatestReleaseObj.name

    $specifiedAssetName = $PackageData.specifiedAssetName
    # if specifiedAssetName is not null or empty print it
    if (-not [string]::IsNullOrWhiteSpace($specifiedAssetName)) {
        Write-DebugLog "    Specified Asset Name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $specifiedAssetName
        $specifiedAssetType = Get-FileType -FileName $specifiedAssetName

    }
    else {
        Write-DebugLog "    No specified asset name found."
    }
    
    $latestSelectedAsset = if (-not [string]::IsNullOrWhiteSpace($specifiedAssetName)) {
        # If the user specified an asset name, select that asset
        Select-AssetByName -Assets $assets -AssetName $specifiedAssetName
    } else {
        # Otherwise, select the best asset based on supported types
        Write-DebugLog "    Selecting asset by type: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $specifiedAssetType
        Write-DebugLog "    Accepted extensions: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $AcceptedExtensions
        Select-AssetByType -Assets $assets -AcceptedExtensions $AcceptedExtensions
    }

    if (-not $latestSelectedAsset) {
        Write-Error "No suitable asset found for the latest release. Selected Asset is Null"
    }

    Write-LogFooter "Select-AssetFromRelease"
    return $latestSelectedAsset
}
function Select-AssetByName {
    param (
        [System.Object[]]$Assets,
        [string]$AssetName
    )
    Write-LogHeader "Select-AssetByName"
    # The value we will return
    $newSelectedAsset = $null

    Write-DebugLog "    Asset Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $AssetName

    # If the Assets contains an exact match for the AssetName, set the return value to that asset
    $exactMatchAssets = $Assets | Where-Object { $_.name -eq $AssetName }
    if ($exactMatchAssets) {
        $exactMatchAsset = $exactMatchAssets[0]  # Get the first matching asset
        Write-DebugLog "    Exact match found: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $exactMatchAsset.name
        $newSelectedAsset = $exactMatchAsset
    }
    
    else {
        # Get the most similar string from the Assets array
        $mostSimilarAssetName = Get-MostSimilarString -Key $AssetName -Strings ($Assets | ForEach-Object { $_.name })
        Write-DebugLog "    Most similar asset name found: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $mostSimilarAssetName
        # Now get the corresponding asset object based on the most similar name
        $newSelectedAsset = $Assets | Where-Object { $_.name -eq $mostSimilarAssetName }
    }
    Write-LogFooter "Select-AssetByName"
    return $newSelectedAsset
}
function Select-AssetByDownloadURL{
    param (
        [System.Object[]]$Assets,
        [string]$DownloadURL
    )
    Write-LogHeader "Select-AssetByDownloadURL"
    # The value we will return
    $newSelectedAsset = $null

    Write-DebugLog "    Download URL: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $DownloadURL

    # If the Assets contains an exact match for the AssetName, set the return value to that asset
    $exactMatchAssets = $Assets | Where-Object { $_.browser_download_url -eq $DownloadURL }
    if ($exactMatchAssets) {
        $exactMatchAsset = $exactMatchAssets[0]  # Get the first matching asset
        Write-DebugLog "    Exact match found: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $exactMatchAsset.name
        $newSelectedAsset = $exactMatchAsset
    }
    
    else {
        # Get the most similar string from the Assets array
        $mostSimilarAssetName = Get-MostSimilarString -Key $DownloadURL -Strings ($Assets | ForEach-Object { $_.browser_download_url })
        Write-DebugLog "    Most similar asset name found: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $mostSimilarAssetName
        # Now get the corresponding asset object based on the most similar name
        $newSelectedAsset = $Assets | Where-Object { $_.browser_download_url -eq $mostSimilarAssetName }
    }
    Write-LogFooter "Select-AssetByDownloadURL"
    return $newSelectedAsset
}
function Select-AssetByType {
    param (
        [System.Object[]]$Assets,
        [string[]]$AcceptedExtensions
    )
    return $Assets |
        Where-Object { $_.name -match '\.([^.]+)$' -and $AcceptedExtensions -contains $matches[1] } |
        Sort-Object {
            switch -Regex ($_.name) {
                '\.exe$' { return 0 }
                '\.msi$' { return 1 }
                '\.zip$' { return 2 }
                default { return 3 }
            }
        } |
        Select-Object -First 1
}
function Get-BaseRepositoryObject {
    param (
        [Parameter(Mandatory = $true)]
        [string]$baseRepoApiUrl
    )
    Write-LogHeader "Get-BaseRepositoryObject"
    Write-DebugLog "    Getting base repository for: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $baseRepoApiUrl

    # Fetch the repository information
    try {
        Write-DebugLog "    Repository information fetched successfully: " -NoNewline -ForegroundColor Yellow
        $repoObj = (Invoke-WebRequest -Uri $baseRepoApiUrl) | ConvertFrom-Json
        Write-DebugLog $repoObj.full_name
    }
    catch {
        # Detailed error message
        Write-DebugLog "Failed to fetch repository information. URL used: $baseRepoApiUrl $($Error[0].Exception.Message)" 
        return $null
    }

    Write-LogFooter "base repository info"
    return $repoObj
    
}
function Get-RootRepositoryObject {
    param (
        [Parameter(Mandatory = $true)]
        [string]$baseRepoApiUrl
        # expects to be in this format: https://api.github.com/repos/USER/REPONAME
    )
    Write-LogHeader "Get-RootRepositoryObject"
    Write-DebugLog "    Getting root repository for: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $baseRepoApiUrl

    # Fetch the repository information
    try {
        $repoObj = (Invoke-WebRequest -Uri $baseRepoApiUrl) | ConvertFrom-Json
        Write-DebugLog "    Repository information fetched successfully: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $repoObj.full_name
    }
    catch {
        Write-Error "Failed to fetch repository information."
        return $null
    }

    # Check if the repository is a fork
    if ($repoObj.fork -eq $true) {
        # If it's a fork, recurse into its parent
        $rootRepo = Get-RootRepositoryObject -baseRepoApiUrl $repoObj.parent.url
        return $rootRepo
    }
    else {
        # If it's not a fork, return the current repository info
        Write-LogFooter "root repository info"
        return $repoObj
    }
}
function Get-FileType {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )
    Write-LogHeader "Get-FileType"
    Write-DebugLog "    File Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $FileName

    # Get the file extension
    $extension = $FileName -replace '.*\.(.+)$', '$1'
    Write-DebugLog "    File Extension: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $extension

    return $extension
}
function Compare-VersionNumbers ($ver1, $ver2) {
    $ver1Array = $ver1 -split "\."
    $ver2Array = $ver2 -split "\."
    
    $minLength = [Math]::Min($ver1Array.Length, $ver2Array.Length)
    
    for ($i = 0; $i -lt $minLength; $i++) {
        if ($ver1Array[$i] -ne $ver2Array[$i]) {
            return $false
        }
    }
    
    return $true
}
function Get-SilentArgs {
    # This is admittedly not a great way to handle this.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FileType
    )
    Write-LogHeader "Get-SilentArgs"
    
    $silentArgs = ''
    
    switch ($FileType) {
        'exe' { 
            $silentArgs = '/S /s /Q /q /quiet /silent'  # Silent installation
        }
        'msi' { 
            $silentArgs = '/quiet /qn /norestart'  # Quiet mode, no user input, no restart
        }
        'zip' { 
            $silentArgs = '-y'  # Assume yes on all queries (Note: Not standard for ZIP)
        }
        <# These Types Are Not Currently Supported
        '7z'  { 
            $silentArgs = '-y'  # Assume yes on all queries
        }        
        'msu' { 
            $silentArgs = '/quiet /norestart'  # Quiet mode, no restart
        }
        'msp' { 
            $silentArgs = '/qn /norestart'  # Quiet mode, no restart
        }
        #>
        default { 
            Write-Error "   Unsupported file type: $FileType"
            exit 1
        }
    }

    Write-LogFooter "Silent Args"
    return $silentArgs
}
function Get-MostRecentValidRelease {
    param ( # Parameter declarations
        [Parameter(Mandatory = $true)]
        [string]$baseRepoApiUrl,
        [string[]]$validFileTypes = @('.exe', '.msi')
    )

    try {
        # Fetch the release information 

        # Print response of rate limit info as an error if the API call fails (rate limit url: 'https://api.github.com/rate_limit') otherwise do not display it
        $rateLimitResponse = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit'
        if ($rateLimitResponse.StatusCode -ne 200) {
            Write-Error "Rate limit status code: $($rateLimitResponse.StatusCode)"
            Write-Error "$($rateLimitResponse.Content)"
        }
        # PSObject containing the release information
        $releasesObj = (Invoke-WebRequest -Uri "$baseRepoApiUrl/releases").Content | ConvertFrom-Json
    }
    catch {
        # Write an error if the API call fails
        Write-Error "Failed to fetch release information."
        return $null
    }

    if (-not $releasesObj -or $releasesObj.Count -eq 0) {
        Write-DebugLog "No releases found."
        return $null
    }

    # Iterate through the releases and return the URL of the first release that contains a valid asset
    foreach ($release in $releasesObj) {
        if (-not $release.assets -or $release.assets.Count -eq 0) {
            continue
        }

        foreach ($asset in $release.assets) {
            $extension = $asset.name -replace '.*(\..+)$', '$1'
            if ($validFileTypes -contains $extension) {
                return $release.url
            }
        }
    }

    Write-DebugLog "No valid release found."
    return $null
}
function Get-ReleaseObject {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ReleaseApiUrl
    )

    Write-LogHeader "Get-ReleaseObject"
    Write-DebugLog "    Target GitHub API URL: $ReleaseApiUrl"

    Write-DebugLog "    Fetching latest release information..."
    $releaseObj = (Invoke-WebRequest -Uri "$ReleaseApiUrl").Content | ConvertFrom-Json
    
    if (-not $releaseObj) {
        Write-Error "   Received data is null. URL used: $ReleaseApiUrl"
        exit 1
    }

    # Make sure the assets field is not null or empty
    $assetCount = ($releaseObj.assets | Measure-Object).Count
    if (-not $releaseObj.assets -or $assetCount -eq 0) {
        Write-Error "   No assets found for the latest release. URL used: $ReleaseApiUrl"
        exit 1
    }

    Write-LogFooter "Get-ReleaseObject"
    return $releaseObj
}
function Set-AssetInfo {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageData
    )
    Write-LogHeader "Set-AssetInfo"
    
    $retreivedLatestReleaseObj = $PackageData.latestReleaseObj

    # Select the best asset based on supported types
    $selectedAsset = Select-AssetFromRelease -LatestReleaseObj $retreivedLatestReleaseObj -PackageData $PackageData
    Write-DebugLog "    Selected asset name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $selectedAsset.name

    # Determine file type from asset name
    $fileType = Get-FileType -FileName $selectedAsset.name
    Write-DebugLog "    File type: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $fileType
    # Determine silent installation arguments based on file type
    $silentArgs = Get-SilentArgs -FileType $fileType
    Write-DebugLog "    Silent arguments: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $silentArgs

    # Find the root repository
    # get the url from the latest release info and replace everything after the repo name with nothing
    $PackageData.baseRepoApiUrl = $retreivedLatestReleaseObj.url -replace '/releases/.*', ''

    $myDefaultBranch = "$($PackageData.baseRepoObj.default_branch)"
    Write-DebugLog "    Default Branch: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog "    `"$myDefaultBranch`""

    # Array table to store the tags. Uses the topics json result from the GitHub API
    $tags = @()
    # If the result is not null or empty or whitespace, add the tags to the hash table from the base repo info. Otherwise, add the tags from the root repo info.
    if (-not [string]::IsNullOrWhiteSpace($PackageData.baseRepoObj.topics)) {
        $tags += $PackageData.baseRepoObj.topics
        Write-DebugLog "    Tags from base repo info: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "    $($PackageData.baseRepoObj.topics)"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PackageData.latestReleaseObj.topics)) {
        $tags += $PackageData.latestReleaseObj.topics
        Write-DebugLog "    Tags from root repo info: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "    $($PackageData.latestReleaseObj.topics)"
    }
    else {
        Write-DebugLog "    No tags found."
    }

    Write-DebugLog "    Tags is of type: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog "    $($tags.GetType().Name)"

    # if the tags array is not null or empty, print the tags
    if ($null -ne $tags -and $tags.Count -gt 0) {
        Write-DebugLog "    Tags: " -ForegroundColor Yellow
        $tags | ForEach-Object {
            Write-DebugLog "    $_"
        }
    }
    else {
        Write-DebugLog "    No tags found."
    }

    # Initial variable declaration
    $iconUrl = $null
    $iconInfo = $null

    # Check if the root repository has a homepage
    if (-not [string]::IsNullOrWhiteSpace($PackageData.baseRepoObj.homepage)) {
        $homepage = $PackageData.baseRepoObj.homepage
        # If image is found but not svg... (Should do better check for svg instead of dummy info)
        
        # Attempt to get the favicon from the homepage
        $homePageiconInfo = Get-Favicon -Homepage $homepage

        # If the icon is larger than the current icon, use it instead
        if ($null -ne $homePageiconInfo.url -and $homePageiconInfo.width -gt $iconInfo.width -and $homePageiconInfo.height -gt $iconInfo.height) {
            $iconInfo = $homePageiconInfo
            Write-DebugLog "    Found Favicon on Homepage: " -ForegroundColor Yellow -NoNewline
            Write-DebugLog $homePageiconInfo.url
            $iconUrl = $homePageiconInfo.url
        }
        else {
            Write-DebugLog "    No Favicon found on Homepage. Looking for alternatives..." -ForegroundColor Yellow
        }
    }
    # If the icon does not end in .svg, check if the repo has an svg icon
    if (-not $iconUrl -or ($null -ne $iconInfo -and $iconInfo.width -lt 900 -and $iconInfo.height -lt 900)) {
        $repoIconInfo = Find-IcoInRepo -owner $PackageData.user -repo $PackageData.repoName -defaultBranch $myDefaultBranch
        if ($null -ne $repoIconInfo) {
            # If the icon is larger than the current icon, use it instead
            if ($null -ne $repoIconInfo.url -and $repoIconInfo.width -gt $iconInfo.width -and $repoIconInfo.height -gt $iconInfo.height) {
                $iconInfo = $repoIconInfo
                Write-DebugLog "    Found Icon file in Repo: " -ForegroundColor Yellow -NoNewline
                Write-DebugLog $repoIconInfo.url
                $iconUrl = $repoIconInfo.url
            }
            else {
                Write-DebugLog "    No Icon file found in Repo. Looking for alternatives..." -ForegroundColor Yellow
            }

        }
        if ($null -ne $icoPath) {
            $iconUrl = "https://raw.githubusercontent.com/$($PackageData.user)/$($PackageData.repoName)/$myDefaultBranch/$icoPath"
            Write-DebugLog "    Found ICO file in Repo: $iconUrl" -ForegroundColor Green
        }
    }

    # If still no suitable icon is found, use the owner's avatar
    if (-not $iconUrl) {
        $iconUrl = $PackageData.rootRepoObj.owner.avatar_url
        Write-DebugLog "    Using owner's avatar as icon: $iconUrl" -ForegroundColor Green
    }

    # If the owner of the root repository is an organization, use the organization name as package name
    if ($PackageData.latestReleaseObj.owner.type -eq 'Organization') {
        $orgName = $PackageData.latestReleaseObj.owner.login
        Write-DebugLog "    Updated orgName to Organization Name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $orgName
    }

    # Get the description from the root repository if it is not null or whitespace
    $description = $null
    switch ($true) {
        { -not [string]::IsNullOrWhiteSpace($PackageData.baseRepoObj.description) } {
            $description = $PackageData.baseRepoObj.description
            break
        }
        { -not [string]::IsNullOrWhiteSpace($PackageData.rootRepoObj.description) } {
            $description = $PackageData.rootRepoObj.description
            break
        }

        default {
            Write-DebugLog "Description could not be found in any source."
            $description = "Description could not be found."
        }
    }


    $description = [System.Net.WebUtility]::HtmlDecode($description)

    Write-DebugLog "    Description: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $description

    

    # If specifiedasset is not null or empty print it
    if (-not [string]::IsNullOrWhiteSpace($PackageData.specifiedAssetName)) {
        Write-DebugLog "    Specified Asset Name Found, Cleaning Before Appending to Package Name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $PackageData.specifiedAssetName 
        $cleanedSpecifiedAssetName = $PackageData.specifiedAssetName
        # If cleanedSpecifiedAssetName ends with any of the strings contained in acceptedExtensions, remove it
        foreach ($ext in $acceptedExtensions) {
            if ($cleanedSpecifiedAssetName.EndsWith($ext, [System.StringComparison]::OrdinalIgnoreCase)) {
                $cleanedSpecifiedAssetName = $cleanedSpecifiedAssetName -replace $ext, ''
            }
        }
        Write-DebugLog "    Cleaned Specified Asset Name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $cleanedSpecifiedAssetName

        # Get the original tag name
        $originalTagName = $PackageData.tag
        Write-DebugLog "    Original Tag Name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $originalTagName
    }

    # Get the latest release tag name
    $latestTagName = $retreivedLatestReleaseObj.tag_name
    Write-DebugLog "    Latest Tag Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $latestTagName

    # Set the package name
    $chocoPackageName = "$($PackageData.repoName).$($PackageData.user)"

    # If there is a specified asset, add it to the end of the package name
    if (-not [string]::IsNullOrWhiteSpace($cleanedSpecifiedAssetName)) {
        $chocoPackageName += ".$($cleanedSpecifiedAssetName)"
    }

    Write-DebugLog "    Checking if package: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $chocoPackageName -NoNewline
    Write-DebugLog " contains tag: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $latestTagName

    # If the name contains the tag exactly, remove the tag from the package name
    if ($chocoPackageName -match $latestTagName) {
        Write-DebugLog "        Package name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$chocoPackageName " -NoNewline
        Write-DebugLog " contains tag: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$latestTagName"
        $chocoPackageName = $chocoPackageName -replace $latestTagName, ''
        Write-DebugLog "        Package name after removing tag: " -NoNewline -ForegroundColor Yellow
    }

    # Remove all non-numeric characters from the tag name
    $tagNameNoAlpha = $latestTagName -replace '[^0-9.]', ''
    $originalTagNameNoAlpha = $PackageData.tag -replace '[^0-9.]', ''

    Write-DebugLog "    Checking if package: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog "$chocoPackageName" -NoNewline
    Write-DebugLog " contains tag: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog "$tagNameNoAlpha"

    # If the name contains the latest tag without the alpha characters, remove the numeric tag from the package name
    if ($chocoPackageName -match $tagNameNoAlpha) {
        Write-DebugLog "        Package name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$chocoPackageName" -NoNewline
        Write-DebugLog " contains tag: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$tagNameNoAlpha"
        $chocoPackageName = $chocoPackageName -replace $tagNameNoAlpha, ''
    }

    Write-DebugLog "    Checking if package: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $chocoPackageName -NoNewline
    Write-DebugLog " contains tag: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $originalTagNameNoAlpha

    # If the name contains the original tag without the alpha characters, remove the numeric tag from the package name
    if ($chocoPackageName -match $originalTagNameNoAlpha) {
        Write-DebugLog "        Package name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$chocoPackageName" -NoNewline
        Write-DebugLog "contains tag: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$originalTagNameNoAlpha"
        $chocoPackageName = $chocoPackageName -replace $originalTagNameNoAlpha, ''
    }

    Write-DebugLog "    Processed Package Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog "$chocoPackageName"
    # Convert to valid package name
    $chocoPackageName = ConvertTo-ValidPackageName -PackageName $chocoPackageName

    # If the org name is not null or empty, use it as the repo name
    if (-not [string]::IsNullOrWhiteSpace($orgName)) {
        $githubRepoName = $orgName
    }

    #Initialize licenseUrl
    $licenseUrl = $null
    # Set thhe license URL to the license URL of the root repository if it is not null or whitespace
    if (-not [string]::IsNullOrWhiteSpace($PackageData.latestReleaseObj.license.url)) {
        # Set the license url equal to (repo url)/blob/(default branch)/LICENSE
        $licenseUrl = "$($PackageData.latestReleaseObj.html_url)/blob/$myDefaultBranch/LICENSE"
        Write-DebugLog "    License URL: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $licenseUrl
    }
    elseif (-not [string]::IsNullOrWhiteSpace($PackageData.baseRepoObj.license.url)) {
        # Set the license url equal to (repo url)/blob/(default branch)/LICENSE
        $licenseUrl = "$($PackageData.baseRepoObj.html_url)/blob/$myDefaultBranch/LICENSE"
        Write-DebugLog "    License URL: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $licenseUrl
    }
    else {
        Write-DebugLog "    No license URL found."
    }

    #$packageSize = $selectedAsset.size

    #Write-DebugLog "    Package Size: " -NoNewline -ForegroundColor Yellow
    #Write-DebugLog $packageSize

    # Build the URL for the API request
    $hashUrl = "https://api.github.com/repos/$($PackageData.user)/$($PackageData.repoName)/git/refs/tags/$($retreivedLatestReleaseObj.tag_name)"

    # Make the API request
    $response = Invoke-RestMethod -Uri $hashUrl

    # Extract the commit hash from the response
    $commitHash = $response.object.sha

    # Output the commit hash
    Write-DebugLog "    Commit Hash: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $commitHash

    # repository variable in format : <repository type="git" url="https://github.com/NuGet/NuGet.Client.git" branch="dev" commit="e1c65e4524cd70ee6e22abe33e6cb6ec73938cb3" />
    # $nu_repoUrl = " type=`"git`" url=`"$($PackageData.latestReleaseObj.html_url)`" branch=`"$($PackageData.latestReleaseObj.default_branch)`" commit=`"$($commitHash)`" "

    # Shoule probably (maybe) use root instead
    $licenseUrl = "$($PackageData.baseRepoUrl)/blob/$myDefaultBranch/LICENSE"
    Write-DebugLog "    License URL: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $licenseUrl

    Write-DebugLog "    Repository: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $PackageData.baseRepoUrl

    $tagString = $tags -join ' '
    Write-DebugLog "    Tags: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $tagString

    # $packageTitle = Get-MostSimilarString -key "ProtonVPN_v3.2.1.exe" -strings @("maah", "ProtonVPN-win-app", "ProtonVPN")
    $packageTitle = Get-MostSimilarString -Key $selectedAsset.name -Strings @($PackageData.user, $PackageData.repoName, $PackageData.latestReleaseObj.name) #-Substring $true

    Write-DebugLog "    Package Title: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $packageTitle

    $latestReleaseNotes = [System.Net.WebUtility]::HtmlDecode($retreivedLatestReleaseObj.body)
    Write-DebugLog "    Release Notes: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $latestReleaseNotes

    # Create package metadata object as a hashtable
    $packageMetadata = @{
        PackageName        = $chocoPackageName
        Version            = $latestTagName -replace '[^0-9.]', ''
        Author             = $PackageData.user
        Description        = $description
        VersionDescription = $latestReleaseNotes
        Url                = $selectedAsset.browser_download_url
        ProjectUrl         = $PackageData.baseRepoUrl
        FileType           = $fileType
        SilentArgs         = $silentArgs
        IconUrl            = $iconUrl
        GithubRepoName     = $packageTitle
        LicenseUrl         = $licenseUrl
        #PackageSize         = $packageSize
        Tags               = $tagString
        # Repository          = $nu_repoUrl
        # ProjectSiteUrl      = $homepage
    }


    Function Set-Metadata {
        Param (
            [Parameter(Mandatory = $true)][string]$property,
            [Parameter(Mandatory = $true)][string]$value,
            [Parameter(Mandatory = $true)][object]$metadataObject,
            [Parameter(Mandatory = $true)][string]$logLabel
        )
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $metadataObject.$logLabel = $value
            Write-DebugLog "    $($logLabel): " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $value
        }
    }

    # If the file type is an exe or zip, get the product version and company name from the exe
    if ($fileType -eq 'exe' -or $fileType -eq 'zip') {
        Write-DebugLog "    File type is: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $fileType
        Write-DebugLog "    Getting product version and company name from exe... " -ForegroundColor Magenta
        $dataFromExe = Get-DataFromExe -DownloadUrl $selectedAsset.browser_download_url

        # If the data from the exe is not null or empty, set the metadata
        if ($null -ne $dataFromExe -and $dataFromExe.Count -gt 0) {
            $dataProperties = @{
                Version         = 'FileVersion';
                GithubRepoName  = 'ProductName';
                IconUrl         = 'IconUrl';
                CommandLineArgs = 'CommandLineArgs';
            }
            Write-DebugLog "EXE Info: " -ForegroundColor Magenta
            # Iterate through the properties and set the metadata
            foreach ($property in $dataProperties.GetEnumerator()) {
                # if the value is not null or empty, set the metadata
                if (-not [string]::IsNullOrWhiteSpace($dataFromExe.$($property.Value))) {
                    Write-DebugLog "    Setting metadata: " -NoNewline -ForegroundColor Yellow
                    Write-DebugLog "$($property.Key): $($dataFromExe.$($property.Value))"
                    Set-Metadata -property $property.Key -value $dataFromExe.($property.Value) -metadataObject $packageMetadata -logLabel $property.Key
                }

            }
            $dataFromExeCompanyNameNoAlpha = $dataFromExe.CompanyName -replace '[^a-zA-Z]', ''
            $packageMetadataAuthorNoAlpha = $packageMetadata.Author -replace '[^a-zA-Z]', ''
            # If the company name is not null or empty, and the values are not the same, append it to the author
            if (-not [string]::IsNullOrWhiteSpace($dataFromExe.CompanyName)) {
                if ($dataFromExeCompanyNameNoAlpha -ne $packageMetadataAuthorNoAlpha){
                    $packageMetadata.Author = "$($dataFromExe.CompanyName), $($packageMetadata.Author)"
                    Write-DebugLog "    Authors: " -NoNewline -ForegroundColor Yellow
                    Write-DebugLog $packageMetadata.Author
                }
                else {
                    $packageMetadata.Author = $dataFromExe.CompanyName
                }
            }
            # If command line args are not null or empty, CommandLineArgs is a hashtable. Use the CompleteSilentInstall key
            if (-not [string]::IsNullOrWhiteSpace($dataFromExe.CommandLineArgs)) {
                # if CompleteSilentInstall is not null or empty, set packageMetadata.SilentArgs to the value
                if (-not [string]::IsNullOrWhiteSpace($dataFromExe.CommandLineArgs.CompleteSilentInstall)) {
                    $packageMetadata.SilentArgs = "$($dataFromExe.CommandLineArgs.CompleteSilentInstall)"
                    Write-DebugLog "    Silent Args (CompleteSilentInstall): " -NoNewline -ForegroundColor Yellow
                    Write-DebugLog $packageMetadata.SilentArgs
                }
            }
        }
    }
    # If the file type is msi, get the product name from the msi
    if($fileType -eq 'msi'){
        $dataFromMsi = Get-DataFromMsi -DownloadUrl $selectedAsset.browser_download_url
        Write-DebugLog "    Data From MSI: " -ForegroundColor Magenta
        # write the content of the hashtable to the log
        $dataFromMsi.GetEnumerator() | ForEach-Object {
            Write-DebugLog "    $($_.Key): $($_.Value)"
        }
        # If the data from the msi is not null or empty, set the metadata
        if ($null -ne $dataFromMsi -and $dataFromMsi.Count -gt 0) {
            $dataProperties = @{
                GithubRepoName  = 'Subject';
                #Tags        = 'Keywords';
            }
            Write-DebugLog "MSI Info: " -ForegroundColor Magenta
            # Iterate through the properties and set the metadata
            foreach ($property in $dataProperties.GetEnumerator()) {
                # if the value is not null or empty, set the metadata
                if (-not [string]::IsNullOrWhiteSpace($dataFromMsi.$($property.Value))) {
                    Write-DebugLog "    Setting metadata: " -NoNewline -ForegroundColor Yellow
                    Write-DebugLog "$($property.Key): $($dataFromMsi.$($property.Value))"
                    Set-Metadata -property $property.Key -value $dataFromMsi.($property.Value) -metadataObject $packageMetadata -logLabel $property.Key
                    Write-DebugLog "    Updated " -NoNewline -ForegroundColor Yellow
                    Write-DebugLog "$($property.Key)"
                }

            }
        }
    }

    Write-LogFooter "Set-AssetInfo"
    return $packageMetadata
}
function Initialize-PackageData {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputGithubUrl
    )
    Write-LogHeader "Initialize-PackageData"
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

        # Get the base repository object and the latest release object
        $baseRepoObj = Get-BaseRepositoryObject -baseRepoApiUrl $baseRepoApiUrl
        # if the baseRepoObj is null, exit gracefully
        if ($null -eq $baseRepoObj) {
            Write-DebugLog "Failed to fetch base repository information. URL used: $baseRepoApiUrl"
            Write-DebugLog "Does the repository still exist?"
            return $null
        }
        $rootRepoObj = Get-RootRepositoryObject -baseRepoApiUrl $baseRepoApiUrl
        $latestReleaseObj = Get-ReleaseObject -ReleaseApiUrl $latestReleaseApiUrl        

        #region Display URL information for debugging
        Write-DebugLog "    GitHub User: " -NoNewline -ForegroundColor Magenta
        Write-DebugLog $githubUser
        Write-DebugLog "    GitHub Repo Name: " -NoNewline -ForegroundColor Magenta
        Write-DebugLog $githubRepoName
        Write-DebugLog "    Base Repo URL: " -NoNewline -ForegroundColor Magenta
        Write-DebugLog $baseRepoApiUrl
        #endregion
        
        # Check if asset was specified
        if ($urlParts.Length -gt 7 -and $urlParts[5] -eq 'releases' -and $urlParts[6] -eq 'download') {

            # Get the release tag and asset name from the provided URL
            $tag = $urlParts[7]
            $specifiedAssetName = $urlParts[-1]

            #region Display tag and asset name for debugging
            Write-DebugLog "    Release tag detected: " -NoNewline -ForegroundColor Magenta
            Write-DebugLog $tag
            Write-DebugLog "    Asset name detected: " -NoNewline -ForegroundColor Magenta
            Write-DebugLog $specifiedAssetName
            #endregion
        }
    }
    else {
        Write-Error "Please provide a valid GitHub repository URL. URL provided: $InputGithubUrl does not match the pattern of a GitHub repository URL. GithubUser/GithubRepoName is required. Current User: $githubUser, Current Repo Name: $githubRepoName "
        exit 1
    }

    # hash table to store the PackageTable and information
    $packageTable = @{
        baseRepoUrl         = $baseRepoUrl
        baseRepoApiUrl      = $baseRepoApiUrl
        user                = $githubUser
        repoName            = $githubRepoName
        latestReleaseApiUrl = $latestReleaseApiUrl
        baseRepoObj         = $baseRepoObj
        latestReleaseObj    = $latestReleaseObj
        rootRepoObj         = $rootRepoObj
    }

    # Add optional keys if they are not null or empty
    if (-not [string]::IsNullOrWhiteSpace($tag) -and -not [string]::IsNullOrWhiteSpace($specifiedAssetName)) {
        $packageTable.Add('tag', $tag)
        $packageTable.Add('specifiedAssetName', $specifiedAssetName)
        $packageTable.Add('specifiedAssetApiUrl', "$baseRepoApiUrl/releases/download/$tag/$specifiedAssetName")
    }

    # List of expected keys. This is important as other functions will expect these keys to exist
    $requiredKeys = @('baseRepoApiUrl', 'user', 'repoName', 'latestReleaseApiUrl', 'baseRepoUrl', 'baseRepoObj', 'latestReleaseObj', 'rootRepoObj')

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

    Write-LogFooter "Initialize-PackageData"

    # Return the hash table
    return $packageTable
}