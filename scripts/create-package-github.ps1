. "$PSScriptRoot\logging-functions.ps1"
. "$PSScriptRoot\get-package-data.ps1"
. "$PSScriptRoot\package-functions.ps1"
. "$PSScriptRoot\process-and-validate.ps1"
. "$PSScriptRoot\get-icons.ps1"
. "$PSScriptRoot\new-get-package-data.ps1"

# Global Variables
$Global:acceptedExtensions = @('exe', 'msi', 'zip')
$Global:EnableDebugMode = $true
# Variable that stores the location of the scripts directory regardless of where the script is run from
$Global:scriptsDir = $PSScriptRoot
# Parent of PSScriptRoot
$Global:rootDir = Split-Path $scriptsDir -Parent
# Variable that stores the location of the resources dir, within root
$Global:resourcesDir = Join-Path $rootDir "resources"

# Write the locations of each directory to the console
Write-DebugLog "rootDir: " -NoNewline -ForegroundColor Magenta
Write-DebugLog $rootDir
Write-DebugLog "scriptsDir: " -NoNewline -ForegroundColor Magenta
Write-DebugLog $scriptsDir
Write-DebugLog "resourcesDir: " -NoNewline -ForegroundColor Magenta
Write-DebugLog $resourcesDir

function Initialize-GithubPackage{
    param (
        [Parameter(Mandatory=$true)]
        [string]$InputUrl
    )
    Write-LogHeader "Initialize-GithubPackage function"
    Write-DebugLog "    Input Received: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $InputUrl

    # Create a hashtable to store the PackageTable
    $retrievedPackageTable = Initialize-PackageData -InputGithubUrl $InputUrl
    
    #region Get Asset Info
    # retrievedAssetTable

    $myMetadata = Set-AssetInfo -PackageData $retrievedPackageTable

    # Set the path to the package directory and create it if it doesn't exist
    $packageDir = Join-Path (Get-Location).Path $myMetadata.PackageName
    Confirm-DirectoryExists -p_path $packageDir -p_name 'package'

    # Explicitly set the path to the tools directory and create it if it doesn't exist
    $toolsDir = Join-Path $packageDir "tools"
    Confirm-DirectoryExists -p_path $toolsDir -p_name 'tools'

    #endregion
    #region Create Nuspec File and Install Script

    # Create the nuspec file and install script
    New-NuspecFile -Metadata $myMetadata -PackageDir $packageDir
    Write-DebugLog "    Nuspec File Created Successfully" -ForegroundColor Green
    
    Write-DebugLog "    Creating Instal Script..." -NoNewline -ForegroundColor Yellow
    New-InstallScript -Metadata $myMetadata -p_toolsDir $toolsDir
    Write-DebugLog "    Install Script Created Successfully" -ForegroundColor Green

    #endregion
    #region Create Chocolatey Package

    Write-DebugLog "Type of packageDir before New-ChocolateyPackage: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $($packageDir.GetType().Name)

    $nuspecPath = Join-Path $packageDir "$($myMetadata.PackageName).nuspec"

    # Check the nuspecPath System Object or string before passing it to New-ChocolateyPackage
    Write-DebugLog "nuspecPath before New-ChocolateyPackage: " -NoNewline -ForegroundColor Magenta
    Write-DebugLog $nuspecPath

    #endregion

    
    # Create the Chocolatey package
    New-ChocolateyPackage -NuspecPath "$nuspecPath" -PackageDir $packageDir

    #endregion
    Write-LogFooter "Initialize-GithubPackage function"
}