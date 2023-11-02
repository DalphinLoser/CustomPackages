. "$PSScriptRoot\logging-functions.ps1"

function New-NuspecFile {
    param (
        [Parameter(Mandatory = $true)]
        [System.Object]$Metadata,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir
    )

    Write-LogHeader "New-NuspecFile"

    $elementMapping = @{
        id               = 'PackageName'
        title            = 'GithubRepoName'
        version          = 'Version'
        authors          = 'Author'
        description      = 'Description'
        projectUrl       = 'ProjectUrl'
        packageSourceUrl = 'Url'
        releaseNotes     = 'VersionDescription'
        licenseUrl       = 'LicenseUrl'
        iconUrl          = 'IconUrl'
        tags             = 'Tags'
    }

    Write-DebugLog "Element Mapping:" -ForegroundColor Yellow
    $null = $elementMapping.GetEnumerator() | ForEach-Object {
        Write-DebugLog "    $($_.Key) -> $($_.Value)"
    }

    $elementOrder = @('id', 'version', 'title', 'authors', 'packageSourceUrl', 'releaseNotes', 'licenseUrl')

    $xmlDoc = New-Object System.Xml.XmlDocument

    $null = $xmlDoc.LoadXml('<?xml version="1.0"?><package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"><metadata></metadata></package>')
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $null = $nsManager.AddNamespace('ns', 'http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd')
    $metadataElem = $xmlDoc.SelectSingleNode('/ns:package/ns:metadata', $nsManager)

    Write-DebugLog "Appending required elements to metadata: " -ForegroundColor Yellow

    $namespaceUri = "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"

    # Combine the elements in the order specified with any elements not in the order specified
    $allElementsInOrder = $elementOrder + ($elementMapping.Keys | Where-Object { $elementOrder -notcontains $_ })

    Write-DebugLog "Appending elements to metadata... " -ForegroundColor Yellow

    foreach ($elementName in $allElementsInOrder) {
        $key = $elementMapping[$elementName]
        $value = $Metadata.$key

        if (-not $value) {
            Write-DebugLog "Value for $key is null" -ForegroundColor Yellow
        }
        else {
            Write-DebugLog "    Creating element: " -ForegroundColor Magenta
            Write-DebugLog "    name: " -NoNewline -ForegroundColor Cyan
            Write-DebugLog "$elementName" -ForegroundColor White
            Write-DebugLog "    value: " -NoNewline -ForegroundColor Cyan
            Write-DebugLog "$value" -ForegroundColor White

            $elem = $xmlDoc.CreateElement($elementName, $namespaceUri)
            $elem.InnerText = $value
            $null = $metadataElem.AppendChild($elem)
        }
    }

    $nuspecPath = Join-Path $PackageDir "$($Metadata.PackageName).nuspec"
    $null = $xmlDoc.Save($nuspecPath)

    Write-DebugLog "Nuspec file created at: $nuspecPath" -ForegroundColor Green
    Write-LogFooter "New-NuspecFile"

    return $nuspecPath
}
function New-InstallScript {
    param (
        [Parameter(Mandatory = $true)]
        [System.Object]$Metadata,
        
        [Parameter(Mandatory = $true)]
        [string]$ToolsDir
    )

    Write-LogHeader "New-InstallScript"

    # Validation
    if (-not $Metadata.PackageName -or -not $Metadata.ProjectUrl -or -not $Metadata.Url -or -not $Metadata.Version -or -not $Metadata.Author -or -not $Metadata.Description) {
        Write-Error "Missing mandatory metadata for install script."
        return
    }

    # Check the file type
    if ($Metadata.FileType -eq "zip") {
        $globalInstallDir = "C:\AutoPackages\$($Metadata.PackageName)"

        $installScriptContent = @"
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

# Dynamically find all .exe files in the extracted directory and create a shortcut for the largest one
`$exes = Get-ChildItem -Path `$toolsDir -Recurse -Include *.exe | Sort-Object -Property Length -Descending

# Select the largest exe file
`$largestExe = `$exes[0]

`$exeName = [System.IO.Path]::GetFileNameWithoutExtension(`$largestExe.Name)

# Create Desktop Shortcut
`$desktopShortcutPath = Join-Path `$desktopDir "`$exeName.lnk"
`$WshShell = New-Object -comObject WScript.Shell
`$DesktopShortcut = `$WshShell.CreateShortcut(`$desktopShortcutPath)
`$DesktopShortcut.TargetPath = `$largestExe.FullName
`$DesktopShortcut.Save()

# Create Start Menu Shortcut
`$startMenuShortcutPath = Join-Path `$startMenuDir "`$exeName.lnk"
`$StartMenuShortcut = `$WshShell.CreateShortcut(`$startMenuShortcutPath)
`$DesktopShortcut.TargetPath = `$largestExe.FullName
`$StartMenuShortcut.Save()

"@
        # Generate Uninstall Script
        $uninstallScriptContent = @"
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
        $uninstallScriptPath = Join-Path $ToolsDir "chocolateyUninstall.ps1"
        Out-File -InputObject $uninstallScriptContent -FilePath $uninstallScriptPath -Encoding utf8
        Write-DebugLog "    Uninstall script created at: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $uninstallScriptPath    
    }
    else {
        $installScriptContent = @"
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

        # Create BeforeModify Script
        $beforeModifyScriptContent = @"
`$ErrorActionPreference = 'Stop';

# Define variables
`$softwareName = "$($Metadata.GithubRepoName)"
`$installDir = Get-AppInstallLocation `$softwareName

# Use Get-AppInstallLocation to find the installation directory
Write-Host "Method: Using Get-AppInstallLocation" -ForegroundColor Cyan
`$installDir = Get-AppInstallLocation `$softwareName
if (`$installDir) {
    Write-Host "    Resolved Installation Directory: `$installDir"
    # Find the name of the executable using chocolatey-core extensions
    `$executableName = Get-ChildItem `$installDir | Where-Object {`$_.Extension -eq ".exe"} | Select-Object -ExpandProperty Name
} else {
    Write-Host "  Could not resolve installation directory"
}

# Stop each executable that is running
Write-Host "Method: Using Get-Process" -ForegroundColor Cyan
`$processName = `$executableName -replace '\.exe$'
`$process = Get-Process `$processName -ErrorAction SilentlyContinue
if (`$process) {
    # For each process name found, stop the process and log the result to the console
    `$process | ForEach-Object {
        Write-Host "    Stopping process `$(`$_.Name) with ID `$(`$_.Id)"
        Stop-Process -Id `$_.Id -Force
    }
} else {
    Write-Host "    Could not find processes: `$processName"
}
"@
        # Write the before modify script to the tools directory
        $beforeModifyScriptPath = Join-Path $ToolsDir "chocolateyBeforeModify.ps1"
        Out-File -InputObject $beforeModifyScriptContent -FilePath $beforeModifyScriptPath -Encoding utf8
        Write-DebugLog "    BeforeModify script created at: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog "$beforeModifyScriptPath"
    }

    # Write the install script to the tools directory
    $installScriptPath = Join-Path $ToolsDir "chocolateyInstall.ps1"
    Out-File -InputObject $installScriptContent -FilePath $installScriptPath -Encoding utf8
    Write-DebugLog "    Install script created at: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog "$installScriptPath"



    Write-LogFooter "New-InstallScript"
    return $installScriptPath
}
function New-ChocolateyPackage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$NuspecPath,
        [Parameter(Mandatory = $true)]
        [string]$PackageDir
    )
    Write-LogHeader "New-ChocolateyPackage"
    # Write the content of the nuspecPath

    # Check for Nuspec File
    Write-DebugLog "    Checking for nuspec file..."
    if (-not (Test-Path $NuspecPath)) {
        Write-Error "Nuspec file not found at: $NuspecPath"
        exit 1
    }
    else {
        Write-DebugLog "    Nuspec file found at: " -NoNewline -ForegroundColor Green
        Write-DebugLog $NuspecPath
    }
    # Remove any existing packages in the package directory
    Write-DebugLog "    Removing existing packages from package directory..."
    Remove-Item -Path "$PackageDir\*.nupkg" -Force
    # Create Chocolatey package and save the path
    try {
        Write-DebugLog "    Creating Chocolatey package..."
        $output = choco pack $NuspecPath -Force --out $PackageDir
        Write-DebugLog "    Output: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $output
        # Set the package path to the nupkg file in PackageDir if it exists. Select the most recent package if multiple packages exist.
        $packagePath = Get-ChildItem -Path $PackageDir -Filter "*.nupkg" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    catch {
        Write-Error "Failed to create Chocolatey package... Exception: $_"
        exit 1
    }
    Write-DebugLog "    Chocolatey package created at: " -NoNewline -ForegroundColor Green
    Write-DebugLog $packagePath
    
    Write-LogFooter "New-ChocolateyPackage"
    return $packagePath
}