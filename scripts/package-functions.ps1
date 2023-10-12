. "$PSScriptRoot\logging-functions.ps1"

function New-NuspecFile {
    param (
        [Parameter(Mandatory=$true)]
        [System.Object]$Metadata,
        [Parameter(Mandatory=$true)]
        [string]$PackageDir
    )

    Write-LogHeader "New-NuspecFile"

    $elementMapping = @{
        id = 'PackageName'
        title = 'GithubRepoName'
        version = 'Version'
        authors = 'Author'
        description = 'Description'
        projectUrl = 'ProjectUrl'
        packageSourceUrl = 'Url'
        releaseNotes = 'VersionDescription'
        licenseUrl = 'LicenseUrl'
        iconUrl = 'IconUrl'
        tags = 'Tags'
    }

    Write-DebugLog "Element Mapping:" -ForegroundColor Yellow
    $null = $elementMapping.GetEnumerator() | ForEach-Object {
        Write-DebugLog "    $($_.Key) -> $($_.Value)"
    }

    $elementOrder = @('id', 'version', 'title',  'authors', 'packageSourceUrl', 'releaseNotes', 'licenseUrl')

    $xmlDoc = New-Object System.Xml.XmlDocument

    $null = $xmlDoc.LoadXml('<?xml version="1.0"?><package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"><metadata></metadata></package>')
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $null = $nsManager.AddNamespace('ns', 'http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd')
    $metadataElem = $xmlDoc.SelectSingleNode('/ns:package/ns:metadata', $nsManager)

    Write-DebugLog "Appending required elements to metadata: " -ForegroundColor Yellow

    $namespaceUri = "http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"

    foreach ($elementName in $elementOrder) {
        if (-not $elementMapping.PSObject.Properties.Name -contains $elementName) {
            Write-DebugLog "Warning: $elementName not found in elementMapping" -ForegroundColor Yellow
        }

        $key = $elementMapping.$elementName

        if (-not $Metadata.PSObject.Properties.Name -contains $key) {
            Write-DebugLog "Warning: $key not found in Metadata" -ForegroundColor Yellow
        }

        $value = $Metadata.$key

        if ($null -eq $value) {
            Write-DebugLog "Warning: Value for $key is null" -ForegroundColor Yellow
        }

        Write-DebugLog "Creating element with " -NoNewline -ForegroundColor Green
        Write-DebugLog "name: " -NoNewline -ForegroundColor Cyan
        Write-DebugLog "$elementName" -NoNewline -ForegroundColor White
        Write-DebugLog " value: " -NoNewline -ForegroundColor Cyan
        Write-DebugLog "$value" -ForegroundColor White -NoNewline

        $elem = $xmlDoc.CreateElement($elementName, $namespaceUri)
        $elem.InnerText = $value
        $null = $metadataElem.AppendChild($elem)
    }

    $remainingElements = $elementMapping.Keys | Where-Object { $elementOrder -notcontains $_ }
    Write-DebugLog "Appending optional elements to metadata... " -ForegroundColor Yellow
    foreach ($elementName in $remainingElements) {
        Write-DebugLog "Creating element with " -NoNewline -ForegroundColor Green
        Write-DebugLog "name: " -NoNewline -ForegroundColor Cyan
        Write-DebugLog "$elementName" -NoNewline -ForegroundColor White
        Write-DebugLog " value: " -NoNewline -ForegroundColor Cyan
        Write-DebugLog "$value" -ForegroundColor White -NoNewline

        $key = $elementMapping[$elementName]
        $value = $Metadata.$key

        if ($null -eq $value) {
            Write-DebugLog "Warning: Value for $key is null" -ForegroundColor Yellow
        }

        $elem = $xmlDoc.CreateElement($elementName, $namespaceUri)
        $elem.InnerText = $value
        $null = $metadataElem.AppendChild($elem)
    }

    $nuspecPath = Join-Path $PackageDir "$($Metadata.PackageName).nuspec"
    $null = $xmlDoc.Save($nuspecPath)

    Write-DebugLog "Nuspec file created at: $nuspecPath" -ForegroundColor Green
    Write-LogFooter "New-NuspecFile"
}
function New-InstallScript {
    param (
        [Parameter(Mandatory=$true)]
        [System.Object]$Metadata,
        
        [Parameter(Mandatory=$true)]
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
    } else {
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
    }

    $installScriptPath = Join-Path $ToolsDir "chocolateyInstall.ps1"
    Out-File -InputObject $installScriptContent -FilePath $installScriptPath -Encoding utf8
    Write-DebugLog "    Install script created at: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $installScriptPath



    Write-LogFooter "New-InstallScript"
    return $installScriptPath
}
function New-ChocolateyPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$NuspecPath,
        [Parameter(Mandatory=$true)]
        [string]$PackageDir
    )
    Write-LogHeader "New-ChocolateyPackage"
    # Check the type of the nuspecPath
    Write-DebugLog "    The type of NuspecPath is: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $NuspecPath.GetType().Name -ForegroundColor Blue
    # Write the content of the nuspecPath

    # Check for Nuspec File
    Write-DebugLog "    Checking for nuspec file..."
    if (-not (Test-Path $NuspecPath)) {
        Write-Error "Nuspec file not found at: $NuspecPath"
        exit 1
    }
    else {
        Write-DebugLog "    Nuspec file found at: $NuspecPath" -ForegroundColor Yellow
    }

    # Create Chocolatey package
    try {
        Write-DebugLog "    Creating Chocolatey package..."
        choco pack $NuspecPath -Force -Verbose --out $PackageDir
    } catch {
        Write-Error "Failed to create Chocolatey package."
        exit 1
    }
    Write-LogFooter "New-ChocolateyPackage"
}