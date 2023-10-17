. "$PSScriptRoot\logging-functions.ps1"
. "$PSScriptRoot\get-package-data.ps1"
. "$PSScriptRoot\process-and-validate.ps1"

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
            continue
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
        
        # Find the value of the packageSourceUrl field in the nuspec file


        Write-DebugLog "    Current URL: $packageSourceUrl"
        # Extract the old version number using regex. This assumes the version follows right after '/download/'
        if ($packageSourceUrl -match '/download/([^/]+)/') {
            $oldTag = $matches[1]
            $Global:acceptedExtensions = Get-FileType -FileName $packageSourceUrl
            Write-DebugLog "    Accepted Extensions Set To: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $Global:acceptedExtensions
        }
        else {
            Write-Error "Could not find the tag in the URL."
            exit 1
        }

        $latestReleaseObj = Get-ReleaseObject -ReleaseApiUrl "https://api.github.com/repos/$($($package -split '\.')[0])/$($($package -split '\.')[1])/releases/latest"

        # Get the URL of the asset that matches the packageSourceUrl with the version number replaced the newest version number
        $latestReleaseUrl = $packageSourceUrl -replace [regex]::Escape($oldTag), $latestReleaseObj.tag_name
        Write-DebugLog "    Latest  URL: $latestReleaseUrl"
        # Compare the two URLs
        if ($latestReleaseUrl -eq $packageSourceUrl) {
            Write-DebugLog "    The URLs are identical. No new version seems to be available." -ForegroundColor Yellow
        }
        else {
            Write-DebugLog "    The URLs are different. A new version appears to be available." -ForegroundColor Yellow
            Write-DebugLog "    Old URL: $packageSourceUrl"
            Write-DebugLog "    New URL: $latestReleaseUrl"
        }
        Write-DebugLog "    Current Tag: $oldTag"
        Write-DebugLog "    Latest Tag:  $($latestReleaseObj.tag_name)"
        # If the URLs are different, update the metadata for the package
        if ($latestReleaseUrl -ne $packageSourceUrl) {
            
            Write-DebugLog "    Updating metadata for " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $package -NoNewline -ForegroundColor Yellow
            Write-DebugLog "    The nuspec file is: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $nuspecFile.FullName

            Write-DebugLog "    The latest release URL is: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $latestReleaseUrl
            # Replace the packageSourceUrl in the nuspec file with the new URL
            $nuspecFileContent = $nuspecFileContent -replace [regex]::Escape($packageSourceUrl), $latestReleaseUrl
            Write-DebugLog "    The latest version is:     " -NoNewline -ForegroundColor Yellow
            # tag_name without any alpha characters
            $currentVersion = $oldTag -replace '[a-zA-Z]', ''
            $latestVersion = $latestReleaseObj.tag_name -replace '[a-zA-Z]', ''
            Write-DebugLog $latestVersion
            # if the version from the nuget package is the same as the current version, update the version number
            if ($currentVersion -eq $version) {
                $nuspecFileContent = $nuspecFileContent -replace [regex]::Escape($version), $latestVersion
            }
            else {
                Write-DebugLog "    Version number from nuspec: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog $version
                Write-DebugLog "    Version number from Tag:    " -NoNewline -ForegroundColor Yellow
                Write-DebugLog $currentVersion
                Write-Error "    The version numbers is not the tag..."
            }

            # Update the install file with the new URL
            $installFileContent = $installFileContent -replace [regex]::Escape($url), $latestReleaseUrl


            [void]($updatedPackages += $latestReleaseUrl)

            # Save the updated nuspec file
            $nuspecFileContent | Set-Content -Path $nuspecFile.FullName -Force
            Write-DebugLog "    Nuspec file updated successfully." -ForegroundColor Green
            # Save the updated install file
            $installFileContent | Set-Content -Path $installFile.FullName -Force
            Write-DebugLog "    Install file updated successfully." -ForegroundColor Green
            
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
    Write-DebugLog "Updated packages: " -NoNewline -ForegroundColor Green
    Write-DebugLog $output

    Write-LogFooter "Get-Updates"
    return ("$output")
}