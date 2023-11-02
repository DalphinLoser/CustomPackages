. "$PSScriptRoot\logging-functions.ps1"
. "$PSScriptRoot\get-package-data.ps1"
. "$PSScriptRoot\package-functions.ps1"
. "$PSScriptRoot\process-and-validate.ps1"
. "$PSScriptRoot\get-icons.ps1"
. "$PSScriptRoot\new-data-method.ps1"

# Global Variables
$Global:EnableDebugMode = $true
# Variable that stores the location of the scripts directory regardless of where the script is run from
$Global:scriptsDir = $PSScriptRoot
# Parent of PSScriptRoot
$Global:rootDir = Split-Path $scriptsDir -Parent
# Variable that stores the location of the resources dir, within root
$Global:resourcesDir = Join-Path $rootDir "resources"

$packageDir = Join-Path $rootDir "packages"

function Initialize-GithubPackage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputUrl
    )
    Write-LogHeader "Initialize-GithubPackage"

    if (-not $Global:acceptedExtensions) {
        $Global:acceptedExtensions = @('exe', 'msi', 'zip')
        Write-DebugLog "acceptedExtensions set to: " -NoNewline -ForegroundColor Magenta
        Write-DebugLog $Global:acceptedExtensions
    }
    else {
        Write-DebugLog "acceptedExtensions already set to: " -NoNewline -ForegroundColor Magenta
        Write-DebugLog $Global:acceptedExtensions
    }

    # Write the locations of each directory to the console
    Write-DebugLog "rootDir: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $rootDir
    Write-DebugLog "scriptsDir: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $scriptsDir
    Write-DebugLog "resourcesDir: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $resourcesDir
    Write-DebugLog "packageDir: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $packageDir
    Write-DebugLog "acceptedExtensions: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $acceptedExtensions
    Write-DebugLog "Input Received: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $InputUrl

    # Create a hashtable to store the PackageTable
    $retrievedPackageTable = Initialize-PackageData -InputGithubUrl $InputUrl
    
#region Get Asset Info
    # retrievedAssetTable

    $myMetadata = Set-AssetInfo -PackageData $retrievedPackageTable

    # Set the path to the package directory and create it if it doesn't exist
    $thisPackageDir = Join-Path $packageDir "$($myMetadata.PackageName)"
    Write-DebugLog "    Package Directory: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $packageDir
    Confirm-DirectoryExists -DirectoryPath $thisPackageDir -DirectoryName "$($myMetadata.PackageName)"
    Write-DebugLog "    This Package Directory: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $thisPackageDir

    # Explicitly set the path to the tools directory and create it if it doesn't exist
    $toolsDir = Join-Path $thisPackageDir "tools"
    Confirm-DirectoryExists -DirectoryPath $toolsDir -DirectoryName 'tools'

#endregion
#region Create Nuspec File and Install Script

    # Create the nuspec file and install script
    Write-DebugLog "    Creating Nuspec File..." -NoNewline -ForegroundColor Yellow

    $nuspecPath = New-NuspecFile -Metadata $myMetadata -PackageDir $thisPackageDir

    Write-DebugLog "    Nuspec File Created Successfully" -ForegroundColor Green
    Write-DebugLog "    Nuspec File Path: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog "$nuspecPath"
    Write-DebugLog "    Creating Instal Script..." -NoNewline -ForegroundColor Yellow

    $installpath = New-InstallScript -Metadata $myMetadata -ToolsDir $toolsDir

    Write-DebugLog "    Install Script Created Successfully" -ForegroundColor Green
    Write-DebugLog "    Install Script Path: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog "$installpath"

#endregion
#region Create Chocolatey Package

    # Create the Chocolatey package
    #New-ChocolateyPackage -NuspecPath "$nuspecPath" -PackageDir $thisPackageDir
    # Create the Chocolatey package and save the path as a variable
    $chocolateyPackagePath = New-ChocolateyPackage -NuspecPath "$nuspecPath" -PackageDir $thisPackageDir
    Write-DebugLog "    Chocolatey Package Created Successfully" -ForegroundColor Green
    Write-DebugLog "    Chocolatey Package Path: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog "$chocolateyPackagePath"

#endregion

return $chocolateyPackagePath
Write-LogFooter "Initialize-GithubPackage"
}