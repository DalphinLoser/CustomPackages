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
function Test-ConvertToValidPackageName {
    param (
        [string]$Name,
        [string]$Expected
    )

    $actual = ConvertTo-ValidPackageName -PackageName $Name
    $result = if ($actual -eq $Expected) { "PASSED" } else { "FAILED" }
    $resultColor = if ($result -eq "PASSED") { "Green" } else { "Red" }

    Write-DebugLog "`nTest Case:"
    Write-DebugLog "  Name:    `"$Name`""
    Write-DebugLog "  Expected: `"$Expected`""
    Write-DebugLog "  Actual:   `"$actual`""
    Write-DebugLog "  Result:  " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $result -ForegroundColor $resultColor
}
function Test-Begin {
    # Define test cases as an array of hashtables
    $testCases = @(
        @{ Name = "This.is.a..-test"; Expected = "this.is.a.test" },
        @{ Name = "Another--Test_Case.."; Expected = "another-test_case" },
        @{ Name = "..Leading.Special--Characters"; Expected = "leading.special-characters" },
        @{ Name = "Trailing..Special--Characters.."; Expected = "trailing.special-characters" },
        @{ Name = ".Mixed_.Special-_Characters.-Everywhere-"; Expected = "mixed.special-characters.everywhere" },
        @{ Name = "No.SpecialCharacters"; Expected = "no.specialcharacters" },
        @{ Name = "   Extra   Spaces   "; Expected = "extra-spaces" },
        @{ Name = "CAPITAL.Letters-"; Expected = "capital.letters" },
        @{ Name = "this-.__,-.._.--..-.__.is---.--a..--....-test.-.-.-...----;.-...-.-...-.-......--.--.-.-.-.-.-.-"; Expected = "this.is.a.test" },
        @{ Name = "__--this-____----_-_is___-__--_-_-_--_a---_---_--__--__---___-_-_test--__"; Expected = "this-is_a-test" }
    )
    # Run test cases
    foreach ($testCase in $testCases) {
        Test-ConvertToValidPackageName -Name $testCase.Name -Expected $testCase.Expected
    }
}
function ConvertTo-EscapedXmlContent {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Content
    )
    Write-LogHeader "ConvertTo-EscapedXmlContent function"
    Write-DebugLog "    Escaping XML Content: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $Content
    $escapedContent = $Content -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
    Write-LogFooter "ConvertTo-EscapedXmlContent function"
    return $escapedContent
}
function ConvertTo-SanitizedNugetVersion {
    param (
        [string]$p_rawVersion
    )
    Write-LogHeader "ConvertTo-SanitizedNugetVersion function"
    # Step 1: Trim leading and trailing whitespaces and remove non-numeric leading characters
    $f_cleanVersion = $p_rawVersion.Trim()
    $f_cleanVersion = $f_cleanVersion -replace '^[^0-9]*', ''
    
    # Step 2: Split into numeric and label parts
    $f_numeric = if ($f_cleanVersion -match '^[0-9.]+') { $matches[0] } else { '' }
    $f_label = if ($f_cleanVersion -match '[^-+0-9.]+([-.+].*)$') { $matches[1] } else { '' }
    
    # Step 3: Sanitize numeric part to only include numerals and periods
    $f_numeric = $f_numeric -replace '[^0-9.]', ''
    
    # Step 4: Sanitize labels to only include alphanumerics and hyphens
    $f_label = $f_label -replace '[^-a-zA-Z0-9.+]', ''
    
    # Step 5: Reassemble the version string
    $f_sanitizedVersion = "$f_numeric$f_label"
    
    # Return the sanitized version string
    Write-LogFooter "Sanitized Version"
    return $f_sanitizedVersion
}
function Confirm-DirectoryExists {
    param (
        [Parameter(Mandatory=$true)]
        [string]$p_path,
        [Parameter(Mandatory=$true)]
        [string]$p_name
    )
    Write-LogHeader "Confirm-DirectoryExists function"
    Write-DebugLog "    Checking for $p_name directory..."
    if (-not (Test-Path $p_path)) {
        Write-DebugLog "    No $p_name directory found, creating $p_name directory..."
        New-Item -Path $p_path -ItemType Directory | Out-Null
        Write-DebugLog "    $p_name directory created at: $" -NoNewline -ForegroundColor Yellow
    Write-DebugLog $p_path
    }
    else {
        Write-DebugLog "    $p_name directory found at: " -NoNewline -ForegroundColor Yellow
    Write-DebugLog $p_path
    }
    Write-LogFooter "Confirm-DirectoryExists function"
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