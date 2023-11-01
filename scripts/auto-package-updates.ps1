. "$PSScriptRoot\logging-functions.ps1"
. "$PSScriptRoot\get-package-data.ps1"
. "$PSScriptRoot\process-and-validate.ps1"
. "$PSScriptRoot\package-functions.ps1"

# Global Variables
$Global:EnableDebugMode = $true

function Get-Updates {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackagesDir
    )
    Write-LogHeader "Get-Updates"
    
    # Initialize variable to hold messages displaying if a package was updated or not
    $updatedPackages = @()

    if (-not (Test-Path $PackagesDir)) {
        Write-Error "Path is not valid: $PackagesDir"
        exit 1
    }
    Write-DebugLog "Path is valid: $PackagesDir" -ForegroundColor Green

    $packageDirNames = Get-ChildItem -Path $PackagesDir -Directory

    # Print the names of the directories in the packages directory
    Write-DebugLog "Directories in PackagesDir: " -ForegroundColor Magenta
    # One per line
    $packageDirNames | ForEach-Object {
        Write-DebugLog "    $($_.FullName)"
    }

    foreach ($dirInfo in $packageDirNames) {
        if ([string]::IsNullOrWhiteSpace($dirInfo)) {
            Write-Error "dirInfo is null or empty"
            exit 1
        }

        Write-DebugLog "Checking for updates for: $($dirInfo.Name)" -ForegroundColor Magenta
        $package = $dirInfo.Name

        $nuspecFile = Get-ChildItem -Path "$($dirInfo.FullName)" -Filter "*.nuspec" -File | Select-Object -First 1

        # Get the install file for the package. Located under the tools directory within the package directory. File will be named chocolateyInstall.ps1
        $installFile = Get-ChildItem -Path "$($dirInfo.FullName)\tools" -Filter "chocolateyInstall.ps1" -File | Select-Object -First 1

        # If the install file doesn't exist, skip this package
        if (-not $installFile) {
            Write-Error "No install file found in directory $($dirInfo.FullName)"
            exit 1
        }

        # Get the contents of the install file
        $installFileContent = Get-Content -Path $installFile.FullName -Raw

        # Find the value of the url field in the install file
        if ($installFileContent -match 'url\s*=\s*["''](.*)["'']') {
            $url = $matches[1]
            Write-DebugLog "    Current URL From Install: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $url

        }
        else {
            Write-Error "No url found."
            exit 1
        }

        # If the nuspec file doesn't exist, skip this package
        if (-not $nuspecFile) {
            Write-Error "No .nuspec file found in directory $($dirInfo.FullName)"
            continue
        }

        $nuspecFileContent = Get-Content -Path $nuspecFile.FullName -Raw
        # Find the value of the packageSourceUrl field in the nuspec file
        if ($nuspecFileContent -match '<packageSourceUrl>(.*?)<\/packageSourceUrl>') {
            $packageSourceUrl = $matches[1]
        }
        else {
            Write-Error "No <packageSourceUrl> tag found."
            exit 1
        }
        # Find the version number in the nuspec file
        if ($nuspecFileContent -match '<version>(.*?)<\/version>') {
            $version = $matches[1]
        }
        else {
            Write-Error "No <version> tag found."
            exit 1
        }
        # Find the release notes in the nuspec file
        if ($nuspecFileContent -match '<releaseNotes>((.|\n|\r)*)<\/releaseNotes>') {
            $releaseNotes = $matches[1]
        }
        else {
            Write-Error "No <releaseNotes> tag found in $($nuspecFile.FullName)"
            exit 1
        }
        
        # Find the value of the packageSourceUrl field in the nuspec file


        Write-DebugLog "    Current URL from nuspec: $packageSourceUrl"
  
        $updateData = Initialize-PackageData -InputGithubUrl $packageSourceUrl

        # if the $updateData is null, skip this package
        if (-not $updateData) {
            Write-DebugLog "Unable to get data for $package"
            continue
        }

        $latestReleaseObj = $updateData.latestReleaseObj

        # if the $updateData.specifiedAssetName is not null or empty, use that to find the latest release
        if (-not [string]::IsNullOrWhiteSpace($updateData.specifiedAssetName)) {
            Write-DebugLog "    Current Asset Name: $($updateData.specifiedAssetName)"
            Write-DebugLog "    Current Asset URL: $($updateData.specifiedAssetApiUrl)"

            $currentAssetName = $updateData.specifiedAssetName

            $currentTag = $updateData.tag
            $latestTag = $latestReleaseObj.tag_name
            
            $currentVersion = $currentTag -replace '[a-zA-Z]', ''
            $latestVersion = $latestTag -replace '[a-zA-Z]', ''

            if ($currentVersion -eq $latestVersion) {
                Write-DebugLog "    No update available for: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$currentAssetName"
                continue
            }

            Write-DebugLog "    Checking if package: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$currentAssetName" -NoNewline
            Write-DebugLog " contains tag: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$currentVersion"
            # If the name contains the original tag without the alpha characters, remove the numeric tag from the package name
            if ($currentAssetName -match $currentVersion) {
                Write-DebugLog "        Package name: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$currentAssetName" -NoNewline
                Write-DebugLog " contains tag: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$currentVersion"
                $latestAssetName = $currentAssetName -replace $currentVersion, $latestVersion
            }
            else {
                Write-DebugLog "        Package name: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$currentAssetName" -NoNewline
                Write-DebugLog " does not contain tag: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$currentVersion"
                $latestAssetName = $currentAssetName
            }
            Write-DebugLog "    Latest Asset Name: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$latestAssetName"

            Write-DebugLog "    Selecting asset by name: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$latestAssetName" -NoNewline
            Write-DebugLog " from list of assets: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$($latestReleaseObj.assets.name)"

            $latestAsset = Select-AssetByName -Assets $($latestReleaseObj.assets) -AssetName $latestAssetName
            Write-DebugLog "    Latest Asset Name: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$($latestAsset.name)"

            $latestReleaseUrl = $latestAsset.browser_download_url
            Write-DebugLog "    Latest Asset URL: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$($latestAsset.browser_download_url)"
        } 
        else {
            # Get the URL of the asset that matches the packageSourceUrl with the version number replaced the newest version number
            $latestReleaseUrl = $packageSourceUrl -replace [regex]::Escape($currentVersion), $latestVersion
            Write-DebugLog "    Latest  URL: $latestReleaseUrl"
            # Compare the two URLs
            if ($latestReleaseUrl -eq $packageSourceUrl) {
                Write-DebugLog "    The URLs are identical. No new version seems to be available." -ForegroundColor Yellow
            }
            else {
                Write-DebugLog "    The URLs are different. A new version appears to be available." -ForegroundColor Yellow
                Write-DebugLog "    Old URL: $packageSourceUrl"
                Write-DebugLog "    New URL: $latestReleaseUrl"

                $latestAsset = Select-AssetByDownloadURL -Assets $($latestReleaseObj.assets) -DownloadURL $latestReleaseUrl
                Write-DebugLog "    Latest Asset Name: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$($latestAsset.name)"

                $latestReleaseUrl = $latestAsset.browser_download_url
                Write-DebugLog "    Latest Asset URL: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$($latestAsset.browser_download_url)"
            }
        }
  
        # If the URLs are different, update the metadata for the package
        if ($latestReleaseUrl -ne $packageSourceUrl) {
            
            Write-DebugLog "    Updating metadata for " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$package"
            Write-DebugLog "    The nuspec file is: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $nuspecFile.FullName

            Write-DebugLog "    The latest release URL is: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $latestReleaseUrl
            # Replace the packageSourceUrl in the nuspec file with the new URL
            $nuspecFileContent = $nuspecFileContent -replace [regex]::Escape($packageSourceUrl), $latestReleaseUrl
            Write-DebugLog "    The latest version is:     " -NoNewline -ForegroundColor Yellow
            # tag_name without any alpha characters
            Write-DebugLog $latestVersion

            # Compare versions
            $areVersionsSame = Compare-VersionNumbers $currentVersion $version

            if ($areVersionsSame) {
                $nuspecFileContent = $nuspecFileContent -replace [regex]::Escape($version), $latestVersion
            }
            else {
                Write-DebugLog "    Version number from nuspec: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog $version
                Write-DebugLog "    Version number from Tag:    " -NoNewline -ForegroundColor Yellow
                Write-DebugLog $currentVersion
                Write-DebugLog "    The version number is not the tag..."
            }

            # Decode HTML entities in the release notes
            $latestReleaseNotes = [System.Net.WebUtility]::HtmlDecode($latestReleaseObj.body)

            # Update the release notes
            $nuspecFileContent = $nuspecFileContent -replace [regex]::Escape($releaseNotes), $latestReleaseNotes

            # Update the install file with the new URL
            $installFileContent = $installFileContent -replace [regex]::Escape($url), $latestReleaseUrl


            [void]($updatedPackages += $latestAsset.name)

            # Save the updated nuspec file
            $nuspecFileContent | Set-Content -Path $nuspecFile.FullName -Force
            Write-DebugLog "    Nuspec file updated successfully." -ForegroundColor Green
            # Save the updated install file
            $installFileContent | Set-Content -Path $installFile.FullName -Force
            Write-DebugLog "    Install file updated successfully." -ForegroundColor Green

            $newPkg = New-ChocolateyPackage -NuspecPath "$($nuspecFile.FullName)" -PackageDir "$($dirInfo.FullName)"
            
        }
        else {
            Write-DebugLog "    No updates found for $package" -ForegroundColor Cyan
        }
    }
    if ($updatedPackages.Count -eq 0) {
        Write-DebugLog "No updates found for any packages." -ForegroundColor Green
    }
    else {
        Write-DebugLog "Automatically Updated Packages: " -ForegroundColor Green
        $updatedPackages | ForEach-Object {
            Write-DebugLog "    $_"
        }
    }

    # return the list of packages that were updated as a comma-separated string
    $output = $updatedPackages -join ', '

    Write-LogFooter "Get-Updates"
    return ("$output")
}