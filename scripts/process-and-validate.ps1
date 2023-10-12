. "$PSScriptRoot\logging-functions.ps1"

function ConvertTo-ValidPackageName {
    param (
        [string]$PackageName
    )

    Write-LogHeader "ConvertTo-ValidPackageName"
    Write-DebugLog "Package name before conversion: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $PackageName

    # Step 1: Normalize the String
    $PackageName = $PackageName.ToLower() -replace ' ', '-'
    Write-DebugLog "Package name after normalizing: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $PackageName

    # Step 2: Remove Invalid Characters
    $PackageName = $PackageName -replace '[^a-z0-9._-]', ''
    Write-DebugLog "Package name after removing invalid characters: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $PackageName

    # Step 3: Step through the string one character at a time. If the character is a period, hyphen, or underscore, check the next character. If the next character is a period, hyphen, or underscore, remove it until the next character is not a period, hyphen, or underscore.     # If the first character is not a period and the second character is a period, replace the first character with a period and remove the second character then continue with the loop
    $i = 0
    while ($i -lt $PackageName.Length) {
        $currentChar = $PackageName[$i]
        $nextChar = if ($i -lt ($PackageName.Length - 1)) { $PackageName[$i + 1] } else { '' }
        # If the current character is - or _ and the next character is a period, remove the current character
        if (($currentChar -eq '-' -or $currentChar -eq '_') -and $nextChar -eq '.') {
            $PackageName = $PackageName.Remove($i, 1)
            # Decrease the index by 1 to account for the removed character
        }
        # Else, if the current character is a period, hyphen, or underscore, and the next character is too, remove the next character
        elseif (($currentChar -eq '.' -or $currentChar -eq '-' -or $currentChar -eq '_') -and ($nextChar -eq '.' -or $nextChar -eq '-' -or $nextChar -eq '_')) {
            $PackageName = $PackageName.Remove($i + 1, 1)
            # Decrease the index by 1 to account for the removed character
        }
        else{
            # Continue to the next character
            $i++
        }
    }
    Write-DebugLog "Package name after removing consecutive special characters: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $PackageName

    # Step 5: Trim Special Characters
    $PackageName = $PackageName.Trim('-._')
    Write-DebugLog "Package name after trimming special characters: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $PackageName

    Write-DebugLog "Final package name after conversion: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $PackageName

    Write-LogFooter "ConvertTo-ValidPackageName"

    return $PackageName 
}
function Confirm-DirectoryExists {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath,
        [Parameter(Mandatory=$true)]
        [string]$DirectoryName
    )
    Write-LogHeader "Confirm-DirectoryExists"
    Write-DebugLog "    Checking for $DirectoryName directory..."
    if (-not (Test-Path $DirectoryPath)) {
        Write-DebugLog "    No $DirectoryName directory found, creating $DirectoryName directory..."
        New-Item -Path $DirectoryPath -ItemType Directory | Out-Null
        Write-DebugLog "    $DirectoryName directory created at: $" -NoNewline -ForegroundColor Yellow
    Write-DebugLog $DirectoryPath
    }
    else {
        Write-DebugLog "    $DirectoryName directory found at: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $DirectoryPath
    }
    Write-LogFooter "Confirm-DirectoryExists"
}
function Get-MostSimilarString {
    param (
        [string]$key,
        [string[]]$strings
    )

    # Helper function to calculate Jaccard similarity
    function Get-JaccardSimilarity {
        param (
            [string]$str1,
            [string]$str2
        )
        $set1 = $str1.ToCharArray() | Sort-Object | Get-Unique
        $set2 = $str2.ToCharArray() | Sort-Object | Get-Unique
        $intersection = $set1 | Where-Object { $set2 -contains $_ }
        $union = $set1 + $set2 | Sort-Object | Get-Unique
        return ($intersection.Count / $union.Count)
    }

    # Helper function to find longest common substring
    function Get-LongestCommonSubstring {
        param (
            [string]$str1,
            [string]$str2
        )
        $result = ""
        $str1Length = $str1.Length
        $str2Length = $str2.Length
        $len = 0
        
        # Initialize the table as a hashtable
        $table = @{}
        for ($i = 0; $i -le $str1Length; $i++) {
            for ($j = 0; $j -le $str2Length; $j++) {
                $table["$i,$j"] = 0
            }
        }

        for ($i = 1; $i -le $str1Length; $i++) {
            for ($j = 1; $j -le $str2Length; $j++) {
                if ($str1[$i - 1] -eq $str2[$j - 1]) {
                    $table["$i,$j"] = $table["$($i - 1),$($j - 1)"] + 1
                    if ($table["$i,$j"] -gt $len) {
                        $len = $table["$i,$j"]
                        $result = $str1.Substring($i - $len, $len)
                    }
                }
            }
        }
        return $result
    }

    # Main logic of Get-MostSimilarString
    $maxSimilarity = 0
    $mostSimilarStrings = @()

    foreach ($string in $strings) {
        $similarity = Get-JaccardSimilarity -str1 $key -str2 $string
        if ($similarity -gt $maxSimilarity) {
            $maxSimilarity = $similarity
            $mostSimilarStrings = @($string)
        } elseif ($similarity -eq $maxSimilarity) {
            $mostSimilarStrings += $string
        }
    }

    $maxLcsLength = 0
    $finalString = ""

    foreach ($string in $mostSimilarStrings) {
        $lcs = Get-LongestCommonSubstring -str1 $key.ToLower() -str2 $string.ToLower()
        if ($lcs.Length -gt $maxLcsLength) {
            $maxLcsLength = $lcs.Length
            $finalString = $string
        }
    }

    $finalLcs = Get-LongestCommonSubstring -str1 $key.ToLower() -str2 $finalString.ToLower()
    return $finalString.Substring($finalString.ToLower().IndexOf($finalLcs), $finalLcs.Length)
}