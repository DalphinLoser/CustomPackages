. "$PSScriptRoot\logging-functions.ps1"
. "$PSScriptRoot\get-package-data.ps1"
. "$PSScriptRoot\create-package-github.ps1"

# Global Variables
$Global:EnableDebugMode = $true

function Get-Updates {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PackagesDir
    )
    Write-LogHeader "Get-Updates function"

    # Initialize variable to hold messages displaying if a package was updated or not
    $updatedPackages = @()

    if (-not (Test-Path $PackagesDir)) {
        Write-Error "Path is not valid: $PackagesDir"
        exit 1
    }
    Write-DebugLog "Path is valid: $PackagesDir" -ForegroundColor Green

    $packageDirNames = Get-ChildItem -Path $PackagesDir -Directory

    foreach ($dirInfo in $packageDirNames) {
        if ([string]::IsNullOrWhiteSpace($dirInfo)) {
            Write-Error "dirInfo is null or empty"
            exit 1
        }

        Write-DebugLog "Checking for updates for: $($dirInfo.Name)" -ForegroundColor Magenta
        $package = $dirInfo.Name

        $latestReleaseObj = Get-LatestReleaseObject -LatestReleaseApiUrl "https://api.github.com/repos/$($($package -split '\.')[0])/$($($package -split '\.')[1])/releases/latest"

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
        
        Write-DebugLog "    Current URL: $packageSourceUrl"
        # Extract the old version number using regex. This assumes the version follows right after '/download/'
        if ($packageSourceUrl -match '/download/([^/]+)/') {
            $oldTag = $matches[1]
        } else {
            Write-Error "Could not find the version number in the URL."
            exit 1
        }

        # Get the URL of the asset that matches the packageSourceUrl with the version number replaced the newest version number
        $latestReleaseUrl_Update = $packageSourceUrl -replace [regex]::Escape($oldTag), $latestReleaseObj.tag_name
        Write-DebugLog "    Latest  URL: $latestReleaseUrl_Update"
        # Compare the two URLs
        if ($latestReleaseUrl_Update -eq $packageSourceUrl) {
            Write-DebugLog "    The URLs are identical. No new version seems to be available." -ForegroundColor Yellow
        } else {
            Write-DebugLog "    The URLs are different. A new version appears to be available." -ForegroundColor Yellow
            Write-DebugLog "    Old URL: $packageSourceUrl"
            Write-DebugLog "    New URL: $latestReleaseUrl_Update"
        }
        Write-DebugLog "    Current Version: $oldTag"
        Write-DebugLog "    Latest Version: $($latestReleaseObj.tag_name)"
        # If the URLs are different, update the metadata for the package
        if ($latestReleaseUrl_Update -ne $packageSourceUrl) {
            
            # Remove the old nuspec file
            Remove-Item -Path $nuspecFile -Force

            Write-DebugLog "    Updating metadata for $package"
            Write-DebugLog "    The latest release URL is: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $latestReleaseUrl_Update
            # Get the new metadata
            # TODO handle when asset iss specified (problem with version number)
            Initialize-GithubPackage -InputUrl "$latestReleaseUrl_Update"
            $updatedPackages += $latestReleaseUrl_Update
            # Remove the old nuspec file
            Write-DebugLog "    Removing old nuspec file"
            
        } else {
            Write-DebugLog "    No updates found for $package" -ForegroundColor Cyan
        }
    }
    if($updatedPackages.Count -eq 0) {
        Write-DebugLog "No updates found for any packages." -ForegroundColor Green
    } else {
        Write-DebugLog "Automatically Updated Packages: " -ForegroundColor Green
        $updatedPackages | ForEach-Object {
            Write-DebugLog "    $_"
        }
    }

    # return the list of packages that were updated as a comma-separated string
    $updatedPackages -join ','
    Write-DebugLog "Updated packages: " -NoNewline -ForegroundColor Green
    Write-DebugLog $updatedPackages

    Write-LogFooter "Get-Updates function"
    return $updatedPackages
}