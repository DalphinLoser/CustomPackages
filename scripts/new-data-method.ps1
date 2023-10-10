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

    } catch {
        # Handle errors and exceptions
        Write-Error "An error occurred: $_"
    }
}
