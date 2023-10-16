function Write-DebugLog {
    param (
        [Parameter(Mandatory = $false)]  # Set Mandatory to $false
        [psobject]$Message = "", # Set default value to empty string
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White,
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black, # New parameter with default value
        [switch]$EnableDebug = $Global:EnableDebugMode,
        [switch]$NoNewline
    )

    # if EnableDebugMode is null or white space, set it to $false
    if ([string]::IsNullOrWhiteSpace($EnableDebugMode)) {
        $EnableDebugMode = $false
    }
    
    if ($EnableDebug) {
        $MessageString = if (-not $Message) { "" } else { $Message }  # Convert message to string or use empty string if $Message is $null
        if ($NoNewline) {
            Write-Host -NoNewline $MessageString -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor  # Include BackgroundColor
        }
        else {
            Write-Host $MessageString -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor  # Include BackgroundColor
        }
    }
}
function Write-LogHeader {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ConsoleColor]$ForegroundColor = 'DarkGray'
    )
    Write-DebugLog "`n=== [ ENTER: $Message ] ===" -ForegroundColor $ForegroundColor
}
function Write-LogFooter {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ConsoleColor]$ForegroundColor = 'DarkGray'
    )
    Write-DebugLog "=== [ EXIT: $Message ] ===" -ForegroundColor $ForegroundColor
    Write-DebugLog ""
}
function Write-ObjectProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Object]$Object,

        [Parameter()]
        [int]$MaxDepth = 4
    )

    $currentColor = 'DarkGreen'

    function Get-InternalProperties {
        param (
            [Object]$Obj,
            [string]$Indent,
            [int]$Depth
        )
    
        if ($Depth -ge $MaxDepth) {
            Write-DebugLog "${Indent}... (max depth reached)" -ForegroundColor DarkYellow
            return
        }
    
        $props = if ($Obj -is [PSCustomObject]) {
            $Obj.PSObject.Properties
        }
        elseif ($Obj -is [Hashtable]) {
            $Obj.GetEnumerator() | ForEach-Object { 
                New-Object PSObject -Property @{
                    Name  = $_.Key
                    Value = $_.Value
                }
            }
        }
        elseif ($Obj -is [Array]) {
            $Obj | ForEach-Object -Begin { $i = 0 } -Process {
                New-Object PSObject -Property @{
                    Name  = "Index $i"
                    Value = $_
                }
                $i++
            }
        }
        elseif ($Obj -is [String]) {
            $Obj | ForEach-Object -Begin { $i = 0 } -Process {
                New-Object PSObject -Property @{
                    Name  = "Index $i"
                    Value = $_
                }
                $i++
            }
        }
        else {
            Write-DebugLog "${Indent}Unsupported type: $($Obj.GetType().Name)" -ForegroundColor Red
            return
        }
    
        foreach ($prop in $props) {
            $propType = if ($null -ne $prop.Value) { $prop.Value.GetType().Name } else { '<null>' }
            $propValue = if (-not [string]::IsNullOrWhiteSpace($prop.Value)) {
                $prop.Value.ToString() -replace "`r`n|`r|`n", " "
            }
            else {
                '<empty or whitespace>'
            }
    
            # Toggle color for the whole group
            $currentColor = if ($currentColor -eq 'DarkGreen') { 'DarkCyan' } else { 'DarkGreen' }
    
            Write-DebugLog "$Depth" -NoNewline
            Write-DebugLog "$Indent| Name: " -NoNewline -ForegroundColor $currentColor
            Write-DebugLog "$($prop.Name)" -BackgroundColor DarkGray
            Write-DebugLog "$Depth" -NoNewline
    
            if ($prop.Value -is [PSCustomObject] -or $prop.Value -is [Hashtable]) {
                # Handling complex objects
                Get-InternalProperties -Obj $prop.Value -Indent "$Indent    " -Depth ($Depth + 1)
            }
            elseif ($prop.Value -is [Array]) {
                # Handling arrays
                if ($prop.Value -is [String[]]) {
                    # Handling arrays of strings or other simple types
                    $propValue = "<array of $($prop.Value.Length) strings>"
                    Write-DebugLog "$Indent| Type: $propType" -ForegroundColor $currentColor
                    Write-DebugLog "$Depth" -NoNewline
                    Write-DebugLog "$Indent| Value: $propValue" -ForegroundColor $currentColor
                }
                else {
                    # Handling arrays of complex objects
                    $index = 0
                    foreach ($item in $prop.Value) {
                        Write-DebugLog "$Indent| Type: $propType" -ForegroundColor $currentColor
                        Get-InternalProperties -Obj $item -Indent "$Indent    " -Depth ($Depth + 1)
                        $index++
                    }
                }
            }
            else {
                # Handling simple types
                Write-DebugLog "$Indent| Type: $propType" -ForegroundColor $currentColor
                Write-DebugLog "$Depth" -NoNewline
                Write-DebugLog "$Indent| Value: $propValue" -ForegroundColor $currentColor
            }
        }
    }
    

    Get-InternalProperties -Obj $Object -Indent "   " -Depth 1
}