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
        continue
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
            continue
        }
    
        Write-DebugLog "Checking for updates for: $($dirInfo.Name)" -ForegroundColor Magenta
        $package = $dirInfo.Name
    
        # Find the last .nupkg file in the directory (used to use last write time, but that doesn't work if the file is copied as it is in github actions) - theres probably a better way to do this but this works for now
        $nupkgFile = Get-ChildItem -Path "$($dirInfo.FullName)" -Filter "*.nupkg" -File | Select-Object -Last 1
    
        if ($null -eq $nupkgFile) {
            Write-Warning "No .nupkg file found in $($dirInfo.FullName)"
            continue
        }
    
        # Temporary directory to extract the contents of the .nupkg file
        try {
            # Generate a random file name
            $randomFileName = [System.IO.Path]::GetRandomFileName()

            # Remove the extension to use it as a directory name
            $randomDirName = $randomFileName -replace "\..*$", ""

            # Combine the temp path with the random directory name
            $tempExtractPath = Join-Path -Path $env:TEMP -ChildPath $randomDirName
            # Ensure the directory is created
            New-Item -ItemType Directory -Path $tempExtractPath -Force | Out-Null
            Write-DebugLog "Created Temp Directory: $($tempExtractPath)"
        }
        catch {
            Write-Error "Unable to create temporary directory at $env:TEMP with random name."
            continue
        }

        # Verify the NuGet package file exists
        if (-not (Test-Path -Path $nupkgFile.FullName)) {
            Write-Error "NuGet package file not found: $($nupkgFile.FullName)"
            continue
        }
        Write-DebugLog "Found NuGet package file: $($nupkgFile.FullName)"

        try {
            # Load the assembly for the Expand-Archive cmdlet
            Write-DebugLog "Loading System.IO.Compression.FileSystem assembly"
            Add-Type -AssemblyName System.IO.Compression.FileSystem
        }
        catch {
            Write-Error "Failed to load System.IO.Compression.FileSystem assembly: $($_.Exception.Message)"
        }

        try {
            # Extract the contents of the NuGet package file to the temp directory
            Write-DebugLog "Extracting NuGet package file $($nupkgFile.FullName) to: $($tempExtractPath)"
            [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkgFile.FullName, $tempExtractPath)
        }
        catch {
            Write-DebugLog "Failed to extract NuGet package file: $($_.Exception.Message)"
            continue
        }

        $toolsPath = Join-Path -Path $tempExtractPath -ChildPath "tools"
        # Verify the tools directory exists
        Write-DebugLog "Verifying 'tools' directory exists at $toolsPath"
        if (-not (Test-Path -Path $toolsPath)) {
            Write-Error "The 'tools' directory does not exist in the path: $toolsPath"
            continue
        }

        Write-DebugLog "Getting chocolateyInstall.ps1"
        try {
            $installFile = Get-ChildItem -Path $toolsPath -Filter "chocolateyInstall.ps1" -File | Select-Object -First 1
            if ($null -eq $installFile) {
                Write-Error "chocolateyInstall.ps1 not found in $toolsPath"
                continue # Skip to the next package if the file is not found
            }
            Write-DebugLog "The installFile is: $installFile"
        }
        catch {
            Write-Error "An error occurred while searching for chocolateyInstall.ps1 in $toolsPath."
            continue # Skip to the next package if an error occurs
        }
  
        # If the install file doesn't exist, skip this package
        if (-not $installFile) {
            Write-Error "No install file found in directory $toolsPath"
            continue
        }

        # Get the contents of the install file
        try {
            $installFileContent = Get-Content -Path $installFile.FullName -Raw
        }
        catch {
            Write-Error "Unable to get contents of install file: $($installFile.FullName)"
            continue
        }

        # Find the value of the url field in the install file
        if ($installFileContent -match 'url\s*=\s*["''](.*)["'']') {
            $url = $matches[1]
            Write-DebugLog "    Current URL From Install: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $url

        }
        else {
            Write-Error "No url found."
            continue
        }

        # Find the .nuspec file
        try {
            $nuspecFile = Get-ChildItem -Path "$tempExtractPath" -Filter "*.nuspec" -File | Select-Object -First 1
        }
        catch {
            Write-Error "Unable to get .nuspec file from directory: $tempExtractPath"
            continue
        }

        # If the nuspec file doesn't exist, skip this package
        if (-not $nuspecFile) {
            Write-Error "No .nuspec file found in directory $($tempExtractPath)"
            continue
        }

        $nuspecFileContent = Get-Content -Path $nuspecFile.FullName -Raw
        # Find the value of the packageSourceUrl field in the nuspec file
        if ($nuspecFileContent -match '<packageSourceUrl>(.*?)<\/packageSourceUrl>') {
            $packageSourceUrl = $matches[1]
        }
        else {
            Write-Error "No <packageSourceUrl> tag found."
            continue
        }
        # Find the version number in the nuspec file
        if ($nuspecFileContent -match '<version>(.*?)<\/version>') {
            $version = $matches[1]
        }
        else {
            Write-Error "No <version> tag found."
            continue
        }
        # Find the release notes in the nuspec file
        if ($nuspecFileContent -match '<releaseNotes>((.|\n|\r)*)<\/releaseNotes>') {
            $releaseNotes = $matches[1]
        }
        else {
            Write-Error "No <releaseNotes> tag found in $($nuspecFile.FullName)"
            continue
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

            # Save the updated nuspec file
            $nuspecFileContent | Set-Content -Path $nuspecFile.FullName -Force
            Write-DebugLog "    Nuspec file updated successfully." -ForegroundColor Green
            # Save the updated install file
            $installFileContent | Set-Content -Path $installFile.FullName -Force
            Write-DebugLog "    Install file updated successfully." -ForegroundColor Green

            $newPkg = New-ChocolateyPackage -NuspecPath "$($nuspecFile.FullName)" -PackageDir "$($dirInfo.FullName)"

            # Append the path to the new nupkg file to the list of updated packages
            [void]($updatedPackages += $newPkg)
            
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

    Write-LogFooter "Get-Updates"
    return $updatedPackages
}
