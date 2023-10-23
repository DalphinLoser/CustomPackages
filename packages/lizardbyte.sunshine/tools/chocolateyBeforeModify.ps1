$ErrorActionPreference = 'Stop';

# Define variables
$softwareName = "sne"
$installDir = Get-AppInstallLocation $softwareName

# Use Get-AppInstallLocation to find the installation directory
Write-Host "Method: Using Get-AppInstallLocation" -ForegroundColor Cyan
$installDir = Get-AppInstallLocation $softwareName
if ($installDir) {
    Write-Host "    Resolved Installation Directory: $installDir"
    # Find the name of the executable using chocolatey-core extensions
    $executableName = Get-ChildItem $installDir | Where-Object {$_.Extension -eq ".exe"} | Select-Object -ExpandProperty Name
} else {
    Write-Host "  Could not resolve installation directory"
}

# Stop each executable that is running
Write-Host "Method: Using Get-Process" -ForegroundColor Cyan
$processName = $executableName -replace '\.exe$'
$process = Get-Process $processName -ErrorAction SilentlyContinue
if ($process) {
    # For each process name found, stop the process and log the result to the console
    $process | ForEach-Object {
        Write-Host "    Stopping process $($_.Name) with ID $($_.Id)"
        Stop-Process -Id $_.Id -Force
    }
} else {
    Write-Host "    Could not find processes: $processName"
}
