. "$PSScriptRoot\logging-functions.ps1"
. "$PSScriptRoot\new-data-method.ps1"

function Select-Asset {
    param (
        [Parameter(Mandatory=$true)]
        [System.Object[]]$LatestReleaseObj,

        [Parameter(Mandatory=$true)]
        [hashtable]$PackageData
    )

    Write-LogHeader "Select-Asset function"

    # Validate that assets is not null or empty
    if ($null -eq $LatestReleaseObj.assets -or $LatestReleaseObj.assets.Count -eq 0) {
        Write-Error "No assets found for the latest release. LatestReleaseObj is Null or Empty"
        exit 1
    }

    # If an asset name is providid, select the asset with that name. If not, select the first asset with a supported type.
    if (-not [string]::IsNullOrWhiteSpace($PackageData.specifiedAssetName)) {
        # if the specified asset name contains the version number, replace it with the version number from the latest release
        if ($PackageData.specifiedAssetName -match $PackageData.tag) {
            $cleanedSpecifiedAssetName = $PackageData.specifiedAssetName -replace $PackageData.tag, $LatestReleaseObj.tag_name
            Write-DebugLog "    Specified Asset Name contains version number. Replacing with version number from latest release: " -ForegroundColor Yellow
            Write-DebugLog "    `"$PackageData.specifiedAssetName`""
            # Remove all special characters from the specified asset name except fot ._-
            $cleanedSpecifiedAssetName = $cleanedSpecifiedAssetName -replace '[^a-zA-Z0-9._-]', ''
            Write-DebugLog "    Specified Asset Name after removing special characters: " -ForegroundColor Yellow
            Write-DebugLog "    `"$cleanedSpecifiedAssetName`""
            $cleanedSpecifiedAssetName = $cleanedSpecifiedAssetName.Trim('-._')  # Remove leading and trailing hyphens, underscores, and dots
            Write-DebugLog "    Specified Asset Name after removing leading and trailing hyphens, underscores, and dots: " -ForegroundColor Yellow
            Write-DebugLog "    `"$cleanedSpecifiedAssetName`""
            $PackageData.specifiedAssetName = $cleanedSpecifiedAssetName
        }
        Write-DebugLog "    Selecting asset with name: " -ForegroundColor Yellow -NoNewline
        Write-DebugLog "`"$PackageData.specifiedAssetName`""
        $latestSelectedAsset = $LatestReleaseObj.assets | Where-Object { $_.name -eq $PackageData.specifiedAssetName }
        # If there is no match for the asset name, throw an error
        if ($null -eq $latestSelectedAsset) {
            # If there is still no match, throw an error
            Write-Error "No asset found with name: `"$PackageData.specifiedAssetName`""
            exit 1
        }
    } else {
        # Select the first asset with a supported type
        $latestSelectedAsset = $LatestReleaseObj.assets | 
        Where-Object { 
            if ($_.name -match '\.([^.]+)$') {
                return $acceptedExtensions -contains $matches[1]
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
        Write-DebugLog "    Selected asset after sorting: $($latestSelectedAsset.name)"
    }
    # Validation check for the selected asset
    if ($null -eq $latestSelectedAsset) {
        Write-Error "No suitable asset found for the latest release. Selected Asset is Null"
        exit 1
    }

    Write-LogFooter "Selected Asset"
    return $latestSelectedAsset
}
function Get-BaseRepositoryObject {
    param (
        [Parameter(Mandatory=$true)]
        [string]$baseRepoApiUrl
    )
    Write-LogHeader "Get-BaseRepoObject function"
    Write-DebugLog "    Getting base repository for: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $baseRepoApiUrl

    # Fetch the repository information
    try {
        Write-DebugLog "    Repository information fetched successfully: " -NoNewline -ForegroundColor Yellow
        $repoObj= (Invoke-WebRequest -Uri $baseRepoApiUrl) | ConvertFrom-Json
        Write-DebugLog $repoObj.full_name
    }
    catch {
        Write-Error "Failed to fetch repository information."
        return $null
    }

    # Check if the repository is a fork
    if ($repoObj.fork -eq $true) {
        # If it's a fork, recurse into its parent
        $rootRepo = Get-BaseRepoObject -baseRepoApiUrl $repoObj.parent.url
        return $rootRepo
    } else {
        # If it's not a fork, return the current repository info
        Write-LogFooter "base repository info"
        return $repoObj
    }
}
function Get-RootRepositoryObject {
    param (
        [Parameter(Mandatory=$true)]
        [string]$baseRepoApiUrl
        # expects to be in this format: https://api.github.com/repos/USER/REPONAME
    )
    Write-LogHeader "Get-RootRepositoryObject function"
    Write-DebugLog "    Getting root repository for: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $baseRepoApiUrl

    # Fetch the repository information
    try {
        Write-DebugLog "    Repository information fetched successfully: " -NoNewline -ForegroundColor Yellow
        $repoObj= (Invoke-WebRequest -Uri $baseRepoApiUrl) | ConvertFrom-Json
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
    } else {
        # If it's not a fork, return the current repository info
        Write-LogFooter "root repository info"
        return $repoObj
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
            $extToReturn = $ext
            break
        }
    }
    
    if ($found) {
        # The file name ends with one of the accepted extensions
        Write-DebugLog "    File name ends with an accepted extension" -ForegroundColor Yellow
        # return the extension that was found
        Write-LogFooter "File Type"
        return $extToReturn
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
        [string]$baseRepoApiUrl,
        [string[]]$validFileTypes = @('.exe', '.msi')
    )

    try { # Fetch the release information 

        # Print response of rate limit info as an error if the API call fails (rate limit url: 'https://api.github.com/rate_limit') otherwise do not display it
        $rateLimitResponse = Invoke-WebRequest -Uri 'https://api.github.com/rate_limit'
        if ($rateLimitResponse.StatusCode -ne 200) {
            Write-Error "Rate limit status code: $($rateLimitResponse.StatusCode)"
            Write-Error "$($rateLimitResponse.Content)"
        }
        # PSObject containing the release information
        $releasesObj = (Invoke-WebRequest -Uri "$baseRepoApiUrl/releases").Content | ConvertFrom-Json
    }
    catch { # Write an error if the API call fails
        Write-Error "Failed to fetch release information."
        return $null
    }

    if ($null -eq $releasesObj -or $releasesObj.Count -eq 0) {
        Write-DebugLog "No releases found."
        return $null
    }

    # Iterate through the releases and return the URL of the first release that contains a valid asset
    foreach ($release in $releasesObj) {
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

    Write-DebugLog "No valid release found."
    return $null
}
function Get-LatestReleaseObject {
    param (
        [Parameter(Mandatory=$true)]
        [string]$LatestReleaseApiUrl
    )

    Write-LogHeader "Get-LatestReleaseObject"
    Write-DebugLog "    Target GitHub API URL: $LatestReleaseApiUrl"

    Write-DebugLog "    Fetching latest release information..."
    $latestReleaseObj = (Invoke-WebRequest -Uri "$LatestReleaseApiUrl").Content | ConvertFrom-Json
    
    # Content of latestReleaseObj
    Write-DebugLog "Type of latestReleaseObj: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $latestReleaseObj.GetType().Name
    
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
function Set-AssetInfo {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$PackageData
    )
    Write-LogHeader "Set-AssetInfo function"
    
    $retreivedLatestReleaseObj = Get-LatestReleaseObject -LatestReleaseApiUrl $PackageData.latestReleaseApiUrl

    # Select the best asset based on supported types
    $selectedAsset = Select-Asset -LatestReleaseObj $retreivedLatestReleaseObj -PackageData $PackageData
    Write-DebugLog "Selected asset name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $selectedAsset.name

    # Determine file type from asset name
    $fileType = Get-Filetype -p_fileName $selectedAsset.name
    Write-DebugLog "    File type: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $fileType
    # Determine silent installation arguments based on file type
    $silentArgs = Get-SilentArgs -p_fileType $fileType
    Write-DebugLog "    Silent arguments: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $silentArgs

    # Find the root repository
    # get the url from the latest release info and replace everything after the repo name with nothing
    $PackageData.baseRepoApiUrl = $retreivedLatestReleaseObj.url -replace '/releases/.*', ''

    $myDefaultBranch = "$($PackageData.baseRepoObj.default_branch)"
    Write-DebugLog "Default Branch (Root): " -ForegroundColor Yellow
    Write-DebugLog "`"$myDefaultBranch`""
    

    # Array table to store the tags. Uses the topics json result from the GitHub API
    $tags = @()
    # If the result is not null or empty or whitespace, add the tags to the hash table from the base repo info. Otherwise, add the tags from the root repo info.
    if (-not [string]::IsNullOrWhiteSpace($PackageData.baseRepoObj.topics)) {
        $tags += $PackageData.baseRepoObj.topics
        Write-DebugLog "    Tags from base repo info: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$($PackageData.baseRepoObj.topics)"
    } elseif (-not [string]::IsNullOrWhiteSpace($PackageData.latestReleaseObj.topics)) {
        $tags += $PackageData.latestReleaseObj.topics
        Write-DebugLog "    Tags from root repo info: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$($PackageData.latestReleaseObj.topics)"
    }
    else {
        Write-DebugLog "No tags found."
    }
    

    Write-DebugLog "Tags is of type: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $tags.GetType().Name

    # if the tags array is not null or empty, print the tags
    if ($null -ne $tags -and $tags.Count -gt 0) {
        Write-DebugLog "    Tags: " -ForegroundColor Yellow
        $tags | ForEach-Object {
            Write-DebugLog "    $_"
        }
    } else {
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
            if($null -ne $homePageiconInfo.url -and $homePageiconInfo.width -gt $iconInfo.width -and $homePageiconInfo.height -gt $iconInfo.height){
                $iconInfo = $homePageiconInfo
                Write-DebugLog "    Found Favicon on Homepage: " -ForegroundColor Yellow -NoNewline
                Write-DebugLog $homePageiconInfo.url
                $iconUrl = $homePageiconInfo.url
            }else {
                Write-DebugLog "    No Favicon found on Homepage. Looking for alternatives..." -ForegroundColor Yellow
        }
    }
    # TODO Check if broken. Its late an I might have messed up fixing other things
    # If the icon does not end in .svg, check if the repo has an svg icon
    if ($null -ne $iconInfo -and $iconInfo.width -lt 900 -and $iconInfo.height -lt 900) {
        $repoIconInfo = Find-IcoInRepo -owner $PackageData.user -repo $PackageData.repoName -defaultBranch $myDefaultBranch
        if ($null -ne $repoIconInfo) {
            # If the icon is larger than the current icon, use it instead
            if($null -ne $repoIconInfo.url -and $repoIconInfo.width -gt $iconInfo.width -and $repoIconInfo.height -gt $iconInfo.height){
                $iconInfo = $repoIconInfo
                Write-DebugLog "    Found Icon file in Repo: " -ForegroundColor Yellow -NoNewline
                Write-DebugLog $repoIconInfo.url
                $iconUrl = $repoIconInfo.url
            }else {
                Write-DebugLog "    No Icon file found in Repo. Looking for alternatives..." -ForegroundColor Yellow
            }

        }
        if ($null -ne $icoPath) {
            $iconUrl = "https://raw.githubusercontent.com/$($PackageData.user)/$($PackageData.repoName)/$myDefaultBranch/$icoPath"
            Write-DebugLog "    Found ICO file in Repo: $iconUrl" -ForegroundColor Green
        }
    }

    # If still no suitable icon is found, use the owner's avatar
    if ($null -eq $iconUrl) {
        $iconUrl = $PackageData.rootRepoObj.owner.avatar_url
        Write-DebugLog "    Using owner's avatar as icon: $iconUrl" -ForegroundColor Green
    }

    # If the owner of the root repository is an organization, use the organization name as package name
    if ($PackageData.latestReleaseObj.owner.type -eq 'Organization') {
        $orgName = $PackageData.latestReleaseObj.owner.login
        Write-DebugLog "    Updated orgName to Organization Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $orgName
    }


    # Get the content of the readme file of the base and root repositories
    #$baseRepoReadme = (Invoke-WebRequest -Uri "$($PackageData.baseRepoApiUrl)/readme").Content | ConvertFrom-Json
    #$rootRepoReadme = (Invoke-WebRequest -Uri "$($PackageData.latestReleaseObj.url)/readme").Content | ConvertFrom-Json

    # Get the description from the root repository if it is not null or whitespace
    $description = $null
    switch ($true) {
        { -not [string]::IsNullOrWhiteSpace($PackageData.baseRepoObj.description) } {
            $description = $PackageData.baseRepoObj.description
            break
        }
        { -not [string]::IsNullOrWhiteSpace($PackageData.latestReleaseObj.description) } {
            $description = $PackageData.latestReleaseObj.description
            break
        }

        default {
            Write-DebugLog "Description could not be found in any source."
            $description = "Description could not be found."
        }
    }

    Write-DebugLog "    Description: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $description

    # Get the latest release version number
    $latestTagName = $retreivedLatestReleaseObj.tag_name
    Write-DebugLog "    Latest Tag Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $latestTagName

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
    }

    # Set the package name
    $chocoPackageName = "$($PackageData.user).$($PackageData.repoName)"
    # If there is a specified asset, add it to the end of the package name
    if (-not [string]::IsNullOrWhiteSpace($cleanedSpecifiedAssetName)) {
        $chocoPackageName += ".$($cleanedSpecifiedAssetName)"
    }
    # If the name contains the version number exactly, remove the version number from the package name
    if ($chocoPackageName -match $latestTagName) {
        Write-DebugLog "Package name: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $chocoPackageName -NoNewline
        Write-DebugLog " contains version number: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $latestTagName
        $chocoPackageName = $chocoPackageName -replace $latestTagName, ''
    }
    Write-DebugLog "    Package Name: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $chocoPackageName
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
    } elseif (-not [string]::IsNullOrWhiteSpace($PackageData.baseRepoObj.license.url)) {
        # Set the license url equal to (repo url)/blob/(default branch)/LICENSE
        $licenseUrl = "$($PackageData.baseRepoObj.html_url)/blob/$myDefaultBranch/LICENSE"
        Write-DebugLog "    License URL: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $licenseUrl
    } else {
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

    Write-DebugLog "    Repository: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $nu_repoUrl

    $tagString = $tags -join ' '

    # $packageTitle = Get-MostSimilarString -key "ProtonVPN_v3.2.1.exe" -strings @("maah", "ProtonVPN-win-app", "ProtonVPN")
    $packageTitle = Get-MostSimilarString -key $selectedAsset.name -strings @($PackageData.user, $PackageData.repoName, $PackageData.latestReleaseObj.name)

    Write-DebugLog "    Package Title: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $packageTitle

    # Create package metadata object as a hashtable
    $packageMetadata        = @{
        PackageName         = $chocoPackageName
        Version             = $latestTagName -replace '[^0-9.]', ''
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
        #PackageSize         = $packageSize
        Tags                = $tagString
        # Repository          = $nu_repoUrl
        # ProjectSiteUrl      = $homepage
    }

    # If the file type is an exe, get the product version and company name from the exe
    if ($fileType -eq 'exe') {
        Write-DebugLog "File type is: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $fileType
        Write-DebugLog "    Getting product version and company name from exe: " -ForegroundColor Yellow
        $dataFromExe = Get-DataFromExe -DownloadUrl $selectedAsset.browser_download_url
        # If the product version, company name, or icon url is null or empty, do nothing
        if ([string]::IsNullOrWhiteSpace($dataFromExe.ProductVersion) -or [string]::IsNullOrWhiteSpace($dataFromExe.CompanyName) -or [string]::IsNullOrWhiteSpace($dataFromExe.IconUrl)) {
            Write-DebugLog "    Product version, company name, or icon url is null or empty. Exiting..."
        }
        else {
            $packageMetadata.Version = $dataFromExe.ProductVersion
            $packageMetadata.Author = $dataFromExe.CompanyName
            $packageMetadata.IconUrl = $dataFromExe.IconUrl
            $packageMetadata.GithubRepoName = $dataFromExe.ProductName
        }
    }

    if ($packageMetadata -is [System.Collections.Hashtable]) {
        Write-DebugLog "    Type of packageMetadata before return: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $($packageMetadata.GetType().Name)
    } else {
        Write-DebugLog "    Type of packageMetadata before return: NOT Hashtable"
    }
    
    Write-DebugLog "    Final Check of packageMetadata: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $($packageMetadata.GetType().Name)
    Write-LogFooter "Set-AssetInfo function"
    # Ensure that the package metadata is returned as a hashtable
    return $packageMetadata
}
function Initialize-PackageData {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputGithubUrl
    )
    Write-LogHeader "Initialize-PackageData function"
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
        $rootRepoObj = Get-RootRepositoryObject -baseRepoApiUrl $baseRepoApiUrl
        $latestReleaseObj = Get-LatestReleaseObject -LatestReleaseApiUrl $latestReleaseApiUrl        

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
        baseRepoUrl             = $baseRepoUrl
        baseRepoApiUrl          = $baseRepoApiUrl
        user                    = $githubUser
        repoName                = $githubRepoName
        latestReleaseApiUrl     = $latestReleaseApiUrl
        baseRepoObj             = $baseRepoObj
        latestReleaseObj        = $latestReleaseObj
        rootRepoObj             = $rootRepoObj
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

    Write-LogFooter "Initialize-PackageData function"

    # Return the hash table
    return $packageTable
}
