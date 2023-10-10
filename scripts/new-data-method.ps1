. "$PSScriptRoot\logging-functions.ps1"

# Variable for the path to the root directory, parent of PSScriptRoot
$Global:rootDir = Split-Path $PSScriptRoot -Parent

# Function that takes in the url of the download link for the package
function Get-DataFromExe {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DownloadUrl
    )

    try {
        # Create a temp directory to store the downloaded file, if it already exists, delete it and create a new one
        $tempDir = New-Item -Path $rootDir -Name "temp" -ItemType Directory -Force -ErrorAction Stop
        if (-not $tempDir) {
            throw "Failed to create temporary directory."
        }

        # Download the file using WebClient for faster download
        $webClient = New-Object System.Net.WebClient
        $downloadedFilePath = Join-Path $tempDir.FullName "downloadedFile.exe" # Adjust the file name as necessary
        $webClient.DownloadFile($DownloadUrl, $downloadedFilePath)

        # Set paths for InfoAndIcon.txt
        $resourceHackerPath = Join-Path $rootDir "resources\RH-Get\resource_hacker\ResourceHacker.exe"
        $infoAndIconPath = Join-Path $rootDir "resources\RH-Get\InfoAndIcon.txt"
        
        # Dynamic file creation
        $logPath = Join-Path $rootDir "resources\RH-Get\log.txt"
        $metadataPath = Join-Path $rootDir "resources\RH-Get\metadata"
        $iconPath = Join-Path $rootDir "resources\RH-Get\icon"
        
        # Writing to InfoAndIcon.txt
        $infoAndIconContent = @"
[FILENAMES]
Exe=    $($downloadedFilePath)
Log=    $($logPath)

[COMMANDS]
-extract $($metadataPath)\VERSIONINFO.rc, VERSIONINFO,
-extract $($metadataPath)\MANIFEST.rc, MANIFEST,
-extract $($iconPath)\ICON.rc, ICONGROUP,
"@
        Set-Content -Path $infoAndIconPath -Value $infoAndIconContent
        
        # Command
        $resourceHackerCommand = "`"$resourceHackerPath`" -script `"$infoAndIconPath`""
                
        # Run the command to get the resources from the downloaded file
        Write-DebugLog "    Getting resources from downloaded file..." -ForegroundColor Yellow
        Write-DebugLog "Using Command: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $resourceHackerCommand
        # Use Start-Process with -Wait to ensure the process completes before moving on
        Start-Process -FilePath $resourceHackerPath -ArgumentList "-script `"$infoAndIconPath`"" -Wait -NoNewWindow

        # Once resourceHackerCommand is completed, remove the temp directory
        Write-DebugLog "    Resources extracted successfully" -ForegroundColor Green
        try {
            Remove-Item -Path $tempDir.FullName -Recurse -Force
            Write-DebugLog "    Temporary directory removed successfully" -ForegroundColor Green
        } catch {
            Write-Error "Failed to remove temporary directory: $_"
        }
        
        # PSCustonObject to hold the extracted data 
        $versionInfo = Get-VersionInfo -FilePath "$($metadataPath)\VERSIONINFO.rc"

        # Move the icon into the icons directory. If the directory doesn't exist, create it. It should be located in the root directory
        Write-DebugLog "    The Current Content of the Icons Directory is: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog (Get-ChildItem -Path $iconPath -ErrorAction SilentlyContinue)


        # Path to current .ico. Find it in the icon directory by looking for any file with the .ico extension
        $currentIconPath = Get-ChildItem -Path $iconPath -Filter "*.ico" -Recurse -ErrorAction SilentlyContinue
        Write-DebugLog "    The Current Icon Path is: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $currentIconPath.FullName

        # If the icons directory doesn't exist, create 
        $newIconPath = $rootDir + "\icons"
        if (-not (Test-Path $newIconPath)) {
            New-Item -Path $newIconPath -ItemType Directory -Force -ErrorAction Stop
        }
        # Move the icon to the icons directory and rename it to the product name
        Move-Item -Path $currentIconPath.FullName -Destination "$($newIconPath)\$($versionInfo.ProductName).ico" -Force -ErrorAction Stop

        # Remove everything in the resources\RH-Get directory except for the resource_hacker folder and its contents
        $RHGetDir = Get-ChildItem -Path "$($rootDir)\resources\RH-Get" -Exclude "resource_hacker"
        foreach ($item in $RHGetDir) {
            Write-DebugLog "Removing " -NoNewline -ForegroundColor Yellow
            Write-DebugLog "$($item.FullName)"
            Remove-Item -Path $item.FullName -Recurse -Force
        }

        return $versionInfo
            
    } catch {
        # Handle errors and exceptions
        Write-Error "An error occurred: $_"
    }
}
function Get-VersionInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    try {
        # Check if the file exists
        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            throw "File not found at path: $FilePath"
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

        # Return the extracted values
        return $versionInfo

    } catch {
        # Handle errors and exceptions
        Write-Error "An error occurred: $_"
    }
}