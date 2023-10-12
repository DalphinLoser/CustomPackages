. "$PSScriptRoot\logging-functions.ps1"

function Find-IcoInRepo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$owner,

        [Parameter(Mandatory = $true)]
        [string]$repo,

        [Parameter(Mandatory = $true)]
        [string]$defaultBranch
    )

    Write-LogHeader "Find-IcoInRepo"
    $token = $env:GITHUB_TOKEN

    Write-DebugLog "Default branch recieved: $defaultBranch"

    if (-not $token) {
        Write-Error "ERROR: GITHUB_TOKEN environment variable not set. Please set it before proceeding."
        exit 1
    }

    $headers = @{
        "Authorization" = "Bearer $token"
        "User-Agent"    = "PowerShell"
    }

    # Using the Trees API now
    $apiUrl = "https://api.github.com/repos/${owner}/${repo}/git/trees/${defaultBranch}?recursive=1"
    Write-DebugLog "Query URL: $apiUrl" -ForegroundColor Yellow

    try {
        $webResponse = Invoke-WebRequest -Uri $apiUrl -Headers $headers
        $response = $webResponse.Content | ConvertFrom-Json
        # Write-DebugLog "Response Status Code: $($webResponse.StatusCode)" -ForegroundColor Yellow
        # Write-DebugLog "Response Content:" -ForegroundColor Yellow
        # Write-DebugLog $webResponse.Content
    }
    catch {
        Write-Error "ERROR: Failed to query GitHub API."
        exit 1
    }

    # Filter for files with .ico and .svg extensions
    $icoFiles = $response.tree | Where-Object { $_.type -eq 'blob' -and $_.path -like '*.ico' -or $_.path -like '*.svg' }

    # Check the sizes of the icons
    foreach ($icoFile in $icoFiles) {
        $icoFileUrl = "https://raw.githubusercontent.com/${owner}/${repo}/${defaultBranch}/$($icoFile.path)"
        Write-DebugLog "    Checking icon: " -NoNewline -ForegroundColor Yellow
        Write-DebugLog $icoFileUrl
        $tempFile = Get-TempIcon -iconUrl $icoFileUrl
        if ($null -ne $tempFile) {
            $dimensions = Get-IconDimensions -filePath $tempFile
            Remove-Item -Path $tempFile  # Delete the temporary file
            if ($null -ne $dimensions) {
                $currentDimensions = $dimensions.Width * $dimensions.Height
                # Write the current item and its dimensions
                Write-DebugLog "    Current Dimensions: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$currentDimensions pixels"
                # Write the highest quality item and its dimensions
                Write-DebugLog "    Highest Quality Dimensions: " -NoNewline -ForegroundColor Yellow
                Write-DebugLog "$highestQualityDimensions pixels"
                if ($currentDimensions -gt $highestQualityDimensions) {
                    $highestQualityIcon = $icoFileUrl
                    $highestQualityDimensions = $currentDimensions
                }
                # If they are the same size, use the one with the shorter name
                elseif ($currentDimensions -eq $highestQualityDimensions) {
                    Write-DebugLog "    Same dimensions, using the one with the shorter name" -ForegroundColor Cyan
                    Write-DebugLog "    Current: " -NoNewline -ForegroundColor Yellow
                    Write-DebugLog $icoFile.path
                    Write-DebugLog "    Highest Quality: " -NoNewline -ForegroundColor Yellow
                    Write-DebugLog $highestQualityIcon.path
                    # Compare the lengths of the file names and use the shorter one
                    if ($icoFile.Length -lt $highestQualityIcon.Length) {
                        $highestQualityIcon = $icoFileUrl
                        $highestQualityDimensions = $currentDimensions
                        Write-DebugLog "    Current is shorter, using current" -ForegroundColor Cyan
                    }
                    else {
                        Write-DebugLog "    Highest Quality is shorter, using highest quality" -ForegroundColor Cyan
                    }

                }
            }
        }
    }

    if ($null -ne $highestQualityIcon) {
        Write-DebugLog "    Highest Quality Icon in Repo: $highestQualityIcon ($highestQualityDimensions pixels)" -ForegroundColor Green
        Write-DebugLog "----------- Script End -----------" -ForegroundColor Cyan
        return @{
            url    = $highestQualityIcon
            width  = [Math]::Sqrt($highestQualityDimensions)
            height = [Math]::Sqrt($highestQualityDimensions)
        }
    }
    else {
        Write-LogFooter "Find-IcoInRepo (Not Found)"
        return
    }
}
function Get-Favicon {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Homepage
    )

    Write-DebugLog "---------- Script Start ----------" -ForegroundColor Cyan

    #region Fetching webpage content
    Write-DebugLog "Fetching webpage content from $Homepage" -ForegroundColor Yellow
    try {
        $webRequest = Invoke-WebRequest -Uri $Homepage
    }
    catch {
        Write-DebugLog "Failed to fetch webpage content. Please check your internet connection and the URL." -ForegroundColor Red
        return $null
    }
    #endregion
    #if the url is a github.io page, strip everything after the repo name
    if ($Homepage -match "github.io") {
        $HomepageTld = $Homepage -replace '^(https?://[^/]+/[^/]+/[^/]+).*', '$1'
    }
    else {
        # Strip everything after the domain name
        $HomepageTld = $Homepage -replace '^(https?://[^/]+).*', '$1'
    }

    # Output Information
    Write-DebugLog "    Homepage: " -ForegroundColor Yellow -NoNewline
    Write-DebugLog "$Homepage"
    Write-DebugLog "    Homepage TLD: " -ForegroundColor Yellow -NoNewline
    Write-DebugLog "$HomepageTld"

    # Regex for matching all icon links including png and svg
    $regex = '<link[^>]*rel="(icon|shortcut icon|mask-icon|apple-touch-icon)"[^>]*href="([^"]+)"'
    $regex += "|<div[^>]*class=[`"`'](?:.*navbar.*|.*logo.*)[`"`'][^>]*>.*?<img [^>]*src=[`"`']([^`"']+)[`"`']"
    $iconMatches = $webRequest.Content | Select-String -Pattern $regex -AllMatches

    if ($null -ne $iconMatches) {
        $icons = $iconMatches.Matches | ForEach-Object { 
            $faviconRelativeLink = $_.Groups[2].Value
            if ($faviconRelativeLink -match "^(https?:\/\/)") {
                $faviconRelativeLink  # It's already an absolute URL
            }
            elseif ($faviconRelativeLink -match "^/") {
                "$HomepageTld$faviconRelativeLink"
            }
            else {
                "$HomepageTld/$faviconRelativeLink"
            }
        }  
        
        Write-DebugLog "    Available Icons: " -ForegroundColor Yellow
        Write-DebugLog "    $($icons -join ', ')"

        # Find the highest quality icon
        $highestQualityIcon = $null
        $highestQualityDimensions = 0
        foreach ($iconUrl in $icons) {
            $tempFile = Get-TempIcon -iconUrl $iconUrl
            if ($null -ne $tempFile) {
                $dimensions = Get-IconDimensions -filePath $tempFile
                Remove-Item -Path $tempFile  # Delete the temporary file
                if ($null -ne $dimensions) {
                    $currentDimensions = $dimensions.Width * $dimensions.Height
                    if ($currentDimensions -gt $highestQualityDimensions) {
                        $highestQualityIcon = $iconUrl
                        $highestQualityDimensions = $currentDimensions
                    }
                }
            }
        }
        
        if ($null -ne $highestQualityIcon) {
            Write-DebugLog "    Highest Quality Icon: $highestQualityIcon ($highestQualityDimensions pixels)" -ForegroundColor Green
            Write-DebugLog "----------- Script End -----------" -ForegroundColor Cyan
            return @{
                url    = $highestQualityIcon
                width  = [Math]::Sqrt($highestQualityDimensions)
                height = [Math]::Sqrt($highestQualityDimensions)
            }
        }
        else {
            Write-DebugLog "No suitable icon found." -ForegroundColor Red
            Write-DebugLog "----------- Script End -----------" -ForegroundColor Cyan
            return $null
        }

    }
    else {
        Write-DebugLog "No favicon link found in HTML" -ForegroundColor Red
        Write-DebugLog "----------- Script End -----------" -ForegroundColor Cyan
        return $null
    }
}
function Get-IconDimensions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$filePath
    )

    Write-DebugLog "Analyzing file: $filePath" -ForegroundColor Yellow

    # Ensure the file exists before proceeding
    if (-not (Test-Path -Path $filePath)) {
        Write-DebugLog "File not found: $filePath" -ForegroundColor Red
        return $null
    }

    # Create a Uri object from the file path
    $uri = New-Object System.Uri $filePath

    # Now get the extension from the LocalPath property of the Uri object
    $extension = [System.IO.Path]::GetExtension($uri.LocalPath).ToLower().Trim()

    switch ($extension) {
        '.svg' {
            Write-DebugLog "SVG Identified, returning dummy dimensions" -ForegroundColor Cyan
            # SVG dimension retrieval logic
            # As SVG is a vector format, it doesn't have a fixed dimension in pixels.
            return @{
                Width  = 999 # As SVG is a vector format, it doesn't have a fixed dimension in pixels.
                Height = 999
            }
        }
        '.ico' {
            # ICO dimension retrieval logic
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                # Initialize variables to keep track of the largest dimensions
                $maxWidth = 0
                $maxHeight = 0
                
                $fileStream.Seek(4, [System.IO.SeekOrigin]::Begin) | Out-Null  # Skip to the Count field in ICONDIR
                $buffer = New-Object byte[] 2
                $fileStream.Read($buffer, 0, 2) | Out-Null
                $imageCount = [BitConverter]::ToUInt16($buffer, 0)

                for ($i = 0; $i -lt $imageCount; $i++) {
                    $buffer = New-Object byte[] 16
                    $fileStream.Read($buffer, 0, 16) | Out-Null  # Read ICONDIRENTRY
                    $width = $buffer[0]
                    $height = $buffer[1]

                    # Handle dimensions reported as 0 (which actually means 256)
                    $width = if ($width -eq 0) { 256 } else { $width }
                    $height = if ($height -eq 0) { 256 } else { $height }

                    if ($width * $height -gt $maxWidth * $maxHeight) {
                        $maxWidth = $width
                        $maxHeight = $height
                    }
                }

                Write-DebugLog "ICO Dimensions: " -ForegroundColor Green -NoNewline
                Write-DebugLog "$maxWidth x $maxHeight"
                return @{
                    Width  = $maxWidth
                    Height = $maxHeight
                }
            }
            finally {
                $fileStream.Close()
            }
        }
        '.png' {
            # PNG dimension retrieval logic
            $fileStream = [System.IO.File]::OpenRead($filePath)
            try {
                $fileStream.Seek(16, [System.IO.SeekOrigin]::Begin) | Out-Null
                $buffer = New-Object byte[] 8
                $fileStream.Read($buffer, 0, 8) | Out-Null
                [Array]::Reverse($buffer, 0, 4)
                [Array]::Reverse($buffer, 4, 4)
                $width = [BitConverter]::ToUInt32($buffer, 0)
                $height = [BitConverter]::ToUInt32($buffer, 4)
                Write-DebugLog "    PNG Dimensions: " -ForegroundColor Green -NoNewline
                Write-DebugLog "$width x $height"
                return @{
                    Width  = $width
                    Height = $height
                }
            }
            finally {
                $fileStream.Close()
            }
        }
        default {
            Write-DebugLog "Unsupported file extension: " -ForegroundColor Red -NoNewline
            Write-DebugLog "$extension"
            return $null
        }
    }
}
function Get-TempIcon {
    param (
        [Parameter(Mandatory = $true)]
        [string]$iconUrl
    )

    # Get file extension and create temporary file with the correct extension
    $extension = [System.IO.Path]::GetExtension($iconUrl)
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $validExtension = ($extension -split "([?])")[0] -replace "[$invalidChars]", ""
    $tempFile = [System.IO.Path]::GetTempFileName() + $validExtension

    try {
        Invoke-WebRequest -Uri $iconUrl -OutFile $tempFile
        return $tempFile
    }
    catch {
        Write-DebugLog "Failed to download icon from $iconUrl" -ForegroundColor Red
        return $null
    }
}