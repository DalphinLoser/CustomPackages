. "$PSScriptRoot\logging-functions.ps1"

function Get-DataFromExe {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DownloadUrl
    )

    Write-LogHeader "Get-DataFromExe"

    try {
        # Create temporary directory for downloaded file
        $tempDir = New-Item -Path $rootDir -Name "temp" -ItemType Directory -Force -ErrorAction Stop

        # Download file using WebClient
        $webClient = New-Object System.Net.WebClient
        $downloadType = $DownloadUrl.Split(".")[-1]
        # Set path for downloaded file based on download type (exe or zip) using switch
        switch ($downloadType) {
            "exe" {
                $downloadedFilePath = Join-Path $tempDir.FullName "downloadedFile.exe"
                $webClient.DownloadFile($DownloadUrl, $downloadedFilePath)
            }
            "zip" {
                Write-DebugLog "    Download type is zip" -ForegroundColor Magenta
                Write-DebugLog "    Downloading zip file" -ForegroundColor Yellow
                $downloadedFileZip = Join-Path $tempDir.FullName "downloadedFile.zip"
                Write-DebugLog "    Downloaded file path: " -NoNewline -ForegroundColor Cyan
                Write-DebugLog "$downloadedFileZip"
                $webClient.DownloadFile($DownloadUrl, $downloadedFileZip)
                Write-DebugLog "    Extracting exe files from zip file" -ForegroundColor Yellow
                try {
                    # Extract the zip file to the temporary directory
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadedFileZip, $tempDir)
                    # Get the list of .exe files
                    $downloadedFilePaths = Get-ChildItem -Path $tempDir -Recurse -Filter "*.exe"
                    
                    # Output the list of .exe files
                    if ($downloadedFilePaths) {
                        Write-DebugLog "    Exe files extracted from zip file: " -ForegroundColor Cyan
                        foreach ($downloadedFilePath in $downloadedFilePaths) {
                            Write-DebugLog "    File: " -NoNewline -ForegroundColor Cyan
                            Write-DebugLog $downloadedFilePath.FullName
                        }
                        # Use the largest .exe file
                        $downloadedFilePath = $downloadedFilePaths | Sort-Object -Property Length -Descending | Select-Object -First 1
                        Write-DebugLog "    Using largest exe file found: " -NoNewline -ForegroundColor Cyan
                        Write-DebugLog $downloadedFilePath
                    }
                }
                catch {
                    Write-Error "An error occurred while processing the ZIP file: $_"
                }
                if (-not $downloadedFilePaths) {
                    Write-Error "   No exe files found in zip file"
                    return
                }
            }
            default {
                Write-Error "Download type not supported for extraction method: $downloadType"
                return
            }
        }


        # Set paths for Resource Hacker and associated files
        $resourceHackerPath = Join-Path $rootDir "resources\RH-Get\resource_hacker\ResourceHacker.exe"
        $infoAndIconPath = Join-Path $rootDir "resources\RH-Get\InfoAndIcon.txt"
        $logPath = Join-Path $rootDir "resources\RH-Get\log.txt"
        $metadataPath = Join-Path $rootDir "resources\RH-Get\metadata"
        $iconPath = Join-Path $rootDir "resources\RH-Get\icon"

        # Write to InfoAndIcon.txt for Resource Hacker script
        Set-Content -Path $infoAndIconPath -Value @"
[FILENAMES]
Exe=    $($downloadedFilePath)
Log=    $($logPath)
[COMMANDS]
-extract $($metadataPath)\VERSIONINFO.rc, VERSIONINFO,
-extract $($metadataPath)\MANIFEST.rc, MANIFEST,
-extract $($iconPath)\ICON.rc, ICONGROUP,
"@

        try {
            # Execute Resource Hacker to extract resources
            Start-Process -FilePath $resourceHackerPath -ArgumentList "-script `"$infoAndIconPath`"" -Wait -NoNewWindow
            Write-DebugLog "Resources extracted successfully" -ForegroundColor Green
        }
        catch {
            Write-DebugLog "Failed to extract resources with Resource Hacker: $_"
            return
        }

        # Clean up temporary directory
        Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction Continue

        # Create object to hold content of versioninfo and manifest files
        $exeData = @{}
        
        # Extract version information and upload icon
        $versionInfo = Get-VersionInfo -FilePath "$($metadataPath)\VERSIONINFO.rc"

        # If version info is not null or empty add it to the exeData object
        if ($versionInfo) {
            Write-DebugLog "    Version info: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $versionInfo

            $iconMoved = Move-IconToDirectory -IconPath $iconPath -VersionInfo $versionInfo -Destination "$rootDir\icons"
            # If iconMoved true add icon url to version info
            if ($iconMoved) {
                $versionInfo.IconUrl = "https://raw.githubusercontent.com/DalphinLoser/CustomPackages/main/icons/$($versionInfo.ProductName).ico"
                Write-DebugLog "    Icon moved to icons directory" -ForegroundColor Green
            }
            else {
                Write-DebugLog "    Failed to move icon to icons directory" -ForegroundColor Red
            }
            # Add the objects from version info to the exeData object
            $exeData += $versionInfo

            Write-DebugLog "    Version info added to exeData object" -ForegroundColor Green
        }
        else {
            Write-DebugLog "    Version info not found" -ForegroundColor Red
        }

        # Find the path of the fime names MANIFEST*.txt in the metadata directory
        $manifestPath = Get-ChildItem -Path $metadataPath -Filter "MANIFEST*.txt" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

        # Get the installer type from the manifest file if it exists and is not empty
        if ($manifestPath) {
            Write-DebugLog "    Manifest file found: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $manifestPath.FullName
            $installerUsed = Get-InstallerUsed -ManifestPath $manifestPath.FullName
        }
        else {
            Write-DebugLog "    Manifest file not found" -ForegroundColor Red
        }

        if ($installerUsed) {
            Write-DebugLog "    Installer used: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $installerUsed
    
            # Get args based on installer type
            $installerArgs = Get-InstallerArgs -InstallerType $installerUsed

            # If args are not null or empty add them to the exeData object
            if ($installerArgs) {
                $exeData += @{CommandLineArgs = $installerArgs}
                # Print the content of the hashtable to the console
                Write-DebugLog "    Command Line Args: " -NoNewline -ForegroundColor Yellow
                foreach ($key in $exeData.CommandLineArgs.Keys) {
                    Write-DebugLog "    $($key): " -NoNewline -ForegroundColor Cyan
                    Write-DebugLog $exeData.CommandLineArgs[$key]
                }
            }
        }

        # Clean up RH-Get directory
        Clear-Directory -DirectoryPath "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"

        # Print the content of the hashtable to the console
        Write-DebugLog "    ExeData object: " -ForegroundColor Yellow
        foreach ($key in $exeData.Keys) {
            Write-DebugLog "    $($key): " -NoNewline -ForegroundColor Cyan
            Write-DebugLog $exeData[$key]
        }
        
        Write-LogFooter "Get-DataFromExe"
        return $exeData
            
    }
    catch {
        Write-Error "An error occurred: $_"
    }
}
function Get-DataFromMsi{
    param (
        [Parameter(Mandatory = $true)]
        [string]$DownloadUrl
    )
    Write-LogHeader "Get-DataFromMsi"

    # Create temporary directory for downloaded file
    $tempDir = New-Item -Path $rootDir -Name "temp" -ItemType Directory -Force -ErrorAction Stop

    # Download file using WebClient
    $webClient = New-Object System.Net.WebClient

    $downloadedFilePath = Join-Path $tempDir.FullName "downloadedFile.msi"
    Write-DebugLog "    Downloaded file path: " -NoNewline -ForegroundColor Cyan
    Write-DebugLog $downloadedFilePath
    $webClient.DownloadFile($DownloadUrl, $downloadedFilePath)

    
    # Get the file name of the MSI file
    $fileName = [System.IO.Path]::GetFileName($downloadedFilePath)

    # Initialize the Shell.Application COM object
    $shell = New-Object -COMObject Shell.Application

    # Get the shell folder object for the parent directory
    $shellFolder = $shell.NameSpace($tempDir.FullName)

    # Get the shell item object for the MSI file
    $shellFile = $shellFolder.ParseName($fileName)
    $versionInfo = @{}
    # Loop through a range of indices to get all possible details
    for ($i = 0; $i -le 200; $i++) {
        $propertyValue = $shellFolder.GetDetailsOf($shellFile, $i)
        $propertyName = $shellFolder.GetDetailsOf($null, $i)
    
        # Save the Subject, Authros and Tags properties to the hashtable if they exist
        foreach ($property in $propertyName) {
            if ($property -eq "Subject" -or $property -eq "Authors" -or $property -eq "Tags") {
                $versionInfo[$property] = $propertyValue
            }
        }
    }
    # Display elements and values of the hashtable
    Write-DebugLog "    Version Info (MSI): " -ForegroundColor Yellow
    foreach ($key in $versionInfo.Keys) {
        Write-Host "    $($key): " -NoNewline -ForegroundColor Magenta
        Write-Host $versionInfo[$key]
    }     
    Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction Continue

    Write-LogFooter "Get-DataFromMsi"
    return $versionInfo    
    }
function Clear-Directory {
    param (
        [string]$DirectoryPath,
        [string]$Exclude
    )

    Get-ChildItem -Path $DirectoryPath -Exclude $Exclude | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Continue
    }
}
function Move-IconToDirectory {
    param (
        [string]$IconPath,
        [hashtable]$VersionInfo,
        [string]$Destination
    )

    Write-LogHeader "Move-IconToDirectory"

    $iconFiles = Get-ChildItem -Path $IconPath -Filter "*.ico" -Recurse -ErrorAction SilentlyContinue
    # Choose the largest icon file
    $iconFile = $iconFiles | Sort-Object -Property Length -Descending | Select-Object -First 1
    if (-not $iconFile) {
        Write-DebugLog "Icon file not found in path: $IconPath"
        return $null
    }
    else {
        Write-DebugLog "    Icon file found: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $iconFile.FullName
    }

    # Ensure the destination directory exists
    if (-not (Test-Path -Path $Destination -PathType Container)) {
        New-Item -Path $Destination -ItemType Directory -Force -ErrorAction Stop
        Write-DebugLog "    Destination directory created: " -NoNewline -ForegroundColor Cyan
        Write-DebugLog $Destination
    }
    else {
        Write-DebugLog "    Destination directory already exists: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $Destination
    }

    # Move the icon to the destination directory and rename it to the product name
    Move-Item -Path $iconFile.FullName -Destination "$Destination\$($VersionInfo.ProductName).ico" -Force -ErrorAction Stop
    Write-DebugLog "    Icon moved to destination directory: " -NoNewline -ForegroundColor Cyan
    Write-DebugLog "$Destination\$($VersionInfo.ProductName).ico"

    Write-LogFooter "Move-IconToDirectory"
    return $true
}
function Get-VersionInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    Write-LogHeader "Get-VersionInfo"

    try {
        # Check if the file exists
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            Write-DebugLog "    Version Info File not found at path: $FilePath" -ForegroundColor Yellow
            Write-LogFooter "Get-VersionInfo"
            return
        }

        # Read the content of the file
        $fileContent = Get-Content -Path $FilePath -Raw

        # Initialize a hashtable to store the extracted values
        $versionInfo = @{}

        # Extract other values inside the BLOCK "StringFileInfo"
        if ($fileContent -match '(?s)BLOCK "StringFileInfo"(.*?)BLOCK "VarFileInfo"') {
            $stringFileInfo = $matches[1]
            $stringFileInfo -split "`n" | ForEach-Object {
                if ($_ -match 'VALUE "(.+?)", "(.+?)"') {
                    $versionInfo[$matches[1]] = $matches[2].Trim()
                }
            }
        }        
        Write-LogFooter "Get-VersionInfo"
        # Return the extracted values
        return $versionInfo

    }
    catch {
        # Handle errors and exceptions
        Write-Error "An error occurred: $_"
    }
}
function Get-InstallerUsed{
    param (
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )
    Write-LogHeader "Get-InstallerUsed"
    # Check if the manifest file exists
    if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
        Write-Error "Manifest file not found at path: $ManifestPath"
        return
    }

    # Read the content of the manifest file, which will be in xml format. Set the content to a variable
    $manifestContent = Get-Content -Path $ManifestPath -Raw


    # Extract the value of the "InstallerUsed" node
    if ($manifestContent -match '<description>(.+?)</description>') {
        $installerDescription = $matches[1]
        Write-DebugLog "    Installer description: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $installerDescription
        # Handle different installer types based on if the description contains its name.
        if ($installerDescription -match "Nullsoft") {
            $installerUsed = "NSIS"
        }
        elseif ($installerDescription -match "Inno") {
            $installerUsed = "InnoSetup"
        }
        elseif ($installerDescription -match "WiX") {
            $installerUsed = "WiX"
        }
        else {
            Write-DebugLog "    Installer type not found in description" -ForegroundColor Red
            return
        }

    }

    Write-LogFooter "Get-InstallerUsed"
    # Return the extracted values
    return $installerUsed

}
function Get-InstallerArgs {
    param (
        [string]$installerType
    )

    $argsMap = @{
        # TODO: Implement MSI detection
        "MSI" = @{
            "CompleteSilentInstall" = @("/quiet");
            "SilentUninstall" = @("/quiet", "/uninstall {0}");
            "LoggedInstall" = @("/quiet", "/l* {0}");
            "NoReboot" = @("/quiet", "/norestart");
            "ForceReboot" = @("/quiet", "/forcerestart");
            "RepairInstallation" = @("/quiet", "/fpecms {0}");
            "CustomInstallPath" = @("/quiet", "INSTALLDIR={0}");
            "AllUsersInstall" = @("/quiet", "ALLUSERS=1");
            "Update" = @("/update {0}");
            "LanguageSelection" = @("/quiet", "TRANSFORMS={0}.mst");
        };
        "NSIS" = @{
            "CompleteSilentInstall" = @("/S");
            "SilentUninstall" = @("/S", "/uninstall");
            "CustomInstallPath" = @("/S", "/D={0}");
            "LoggedInstall" = @("/S", "/LOG={0}");
            "ForceOverwrite" = @("/S", "/overwrite");
            "StopRunningPrograms" = @("/S", "/CLOSEAPPLICATIONS");
            "Update" = @("/S", "/UPDATE");
            "IgnorePreRequisites" = @("/S", "/NOREQCHECK");
            "LanguageSelection" = @("/S", "/LANG={0}");
            "LicenseKeyInsertion" = @("/S", "/LICENSE_KEY={0}");
            "NoDesktopShortcut" = @("/S", "/NODESKTOP");
            "ForceRemoveOld" = @("/S", "/REMOVE_OLD");
        };
        "InnoSetup" = @{
            "CompleteSilentInstall" = @("/VERYSILENT", "/NORESTART");
            "SilentUninstall" = @("/VERYSILENT", "/uninstall");
            "CustomInstallPath" = @("/VERYSILENT", "/DIR={0}");
            "NoReboot" = @("/VERYSILENT", "/NORESTART");
            "AllUsersInstall" = @("/VERYSILENT", "/ALLUSERS");
            "LoggedInstall" = @("/VERYSILENT", "/LOG={0}");
            "RepairInstallation" = @("/VERYSILENT", "/REPAIR");
            "StopRunningPrograms" = @("/VERYSILENT", "/CLOSEAPPLICATIONS");
            "Update" = @("/VERYSILENT", "/UPDATE");
            "IgnorePreRequisites" = @("/VERYSILENT", "/NOCHECK");
            "LanguageSelection" = @("/VERYSILENT", "/LANG={0}");
            "LicenseKeyInsertion" = @("/VERYSILENT", "/LICENSE_KEY={0}");
            "CustomConfiguration" = @("/VERYSILENT", "/LOADINF={0}");
            "NoDesktopShortcut" = @("/VERYSILENT", "/NODESKTOP");
        };
        "WiX" = @{
            "CompleteSilentInstall" = @("/quiet");
            "SilentUninstall" = @("/quiet", "/uninstall");
            "LogInstallation" = @("/quiet", "/log {0}");
            "NoReboot" = @("/quiet", "/norestart");
            "RepairInstallation" = @("/quiet", "/repair");
            "LimitedUIInstall" = @("/passive");
            "Update" = @("/quiet", "/update");
            "NetworkInstall" = @("/quiet", "/source={0}");
            "CustomConfiguration" = @("/quiet", "/config={0}");
            "NoDesktopShortcut" = @("/quiet", "/NODESKTOP");
            "ForceRemoveOld" = @("/quiet", "/REMOVEROLDER");
        };
    }

    $installerArgs = $argsMap[$installerType]

    if ($null -eq $installerArgs) {
        Write-DebugLog "Unknown installer type: $installerType" -ForegroundColor Red
        return $null
    }

    return $installerArgs
}

