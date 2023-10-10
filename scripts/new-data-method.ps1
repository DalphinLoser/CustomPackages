. "$PSScriptRoot\logging-functions.ps1"

# Function that takes in the url of the download link for the package
. "$PSScriptRoot\logging-functions.ps1"

function Get-DataFromExe {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DownloadUrl
    )

    Write-LogHeader "Get-DataFromExe function"

    try {
        # Create temporary directory for downloaded file
        $tempDir = New-Item -Path $rootDir -Name "temp" -ItemType Directory -Force -ErrorAction Stop

        # Download file using WebClient
        $webClient = New-Object System.Net.WebClient
        $downloadedFilePath = Join-Path $tempDir.FullName "downloadedFile.exe"
        $webClient.DownloadFile($DownloadUrl, $downloadedFilePath)

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

        if ($null -eq $versionInfo) {
            Write-DebugLog "Version information not found"
            Clear-RHGetDirectory -DirectoryPath "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"
            return
        }

        Move-IconToDirectory -IconPath $iconPath -VersionInfo $versionInfo -Destination "$rootDir\icons"

        if ($null -eq $versionInfo.IconUrl) {
            Write-DebugLog "Icon url not found"
            Clear-RHGetDirectory -DirectoryPath "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"
            return
        }

        # Variable for icon name that will work in url
        $iconName = $versionInfo.ProductName -replace " ", "%20"
        # Variable for icon url
        $icoFileUrl = "https://raw.githubusercontent.com/DalphinLoser/CustomPackages/Modular/icons/$iconName.ico"

        # Add icon url to version info
        $versionInfo.IconUrl = $icoFileUrl

        # Clean up RH-Get directory
        Clear-RHGetDirectory -DirectoryPath "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"
        
        return $versionInfo
            
    } catch {
        Write-Error "An error occurred: $_"
    }
}

function Clear-RHGetDirectory {
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
    if ($null -eq $iconFile) {
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
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    try {
        # Check if the file exists
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            Write-DebugLog "File not found at path: $FilePath"
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
        Write-LogFooter "Get-VersionInfo function"
        # Return the extracted values
        return $versionInfo

    } catch {
        # Handle errors and exceptions
        Write-Error "An error occurred: $_"
    }
}