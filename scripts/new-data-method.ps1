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
                    $downloadedFilePaths = Get-ChildItem -Path $tempDir -Recurse -Filter "*.exe" | Select-Object -ExpandProperty FullName

                    # Output the list of .exe files
                    if ($downloadedFilePaths) {
                        Write-DebugLog "    Exe files extracted from zip file: " -NoNewline -ForegroundColor Cyan
                        Write-DebugLog "$downloadedFilePaths"
                        $downloadedFilePath = $downloadedFilePaths[0]
                        Write-DebugLog "    Downloaded file path: " -NoNewline -ForegroundColor Cyan
                        Write-DebugLog "$downloadedFilePath"
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
        
        # Extract version information and upload icon
        $versionInfo = Get-VersionInfo -FilePath "$($metadataPath)\VERSIONINFO.rc"

        # Find the path of the fime names MANIFEST*.txt in the metadata directory
        $manifestPath = Get-ChildItem -Path $metadataPath -Filter "MANIFEST*.txt" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

        # Get the installer type from the manifest file
        $installerUsed = Get-InstallerUsed -ManifestPath $manifestPath.FullName

        if ($installerUsed) {
            Write-DebugLog "    Installer used: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $installerUsed
    
            # Get silent args based on installer type
            $installerArgs = Get-InstallerArgs -InstallerType $installerUsed
            Write-DebugLog "    Silent args: " -NoNewline -ForegroundColor Yellow
            Write-DebugLog $installerArgs

            # Add silent args to version info
            $versionInfo += @{CommandLineArgs = $installerArgs}
            Write-DebugLog "    Added Silent args: " -NoNewline -ForegroundColor Yellow

            # Print the content of the hashtable to the console
            foreach ($key in $versionInfo.CommandLineArgs.Keys) {
                Write-DebugLog "    $($key): " -NoNewline -ForegroundColor Cyan
                Write-DebugLog $versionInfo.CommandLineArgs[$key]
            }
        }



        if (-not $versionInfo) {
            Write-DebugLog "    Version information not found" -ForegroundColor Red
            Clear-Directory -DirectoryPath "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"
            return
        }

        Move-IconToDirectory -IconPath $iconPath -VersionInfo $versionInfo -Destination "$rootDir\icons"

        # Variable for icon name that will work in url
        $iconName = $versionInfo.ProductName -replace " ", "%20"
        # Variable for icon url
        $icoFileUrl = "https://raw.githubusercontent.com/DalphinLoser/CustomPackages/main/icons/$iconName.ico"

        # Add icon url to version info
        $versionInfo.IconUrl = $icoFileUrl

        if (-not $versionInfo.IconUrl) {
            Write-DebugLog "Icon url not found"
            Clear-Directory -DirectoryPath "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"
            return $versionInfo
        }

        # Clean up RH-Get directory
        Clear-Directory -DirectoryPath "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"
        
        Write-LogFooter "Get-DataFromExe"
        return $versionInfo
            
    }
    catch {
        Write-Error "An error occurred: $_"
    }
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

    $iconFile = Get-ChildItem -Path $IconPath -Filter "*.ico" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $iconFile) {
        Write-Error "Icon file not found in path: $IconPath"
        return
    }

    # Ensure the destination directory exists
    if (-not (Test-Path -Path $Destination -PathType Container)) {
        New-Item -Path $Destination -ItemType Directory -Force -ErrorAction Stop
    }

    # Move the icon to the destination directory and rename it to the product name
    Move-Item -Path $iconFile.FullName -Destination "$Destination\$($VersionInfo.ProductName).ico" -Force -ErrorAction Stop
}
function Get-VersionInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    try {
        # Check if the file exists
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            Write-DebugLog "    File not found at path: $FilePath" -ForegroundColor Red
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
            "CompleteSilentInstall" = @("/VERYSILENT");
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

