<#
.SYNOPSIS
    Centralized logging module for CVExcel project

.DESCRIPTION
    Provides standardized logging functions with consistent formatting,
    color coding, and file output across all CVExcel modules.

.NOTES
    Part of CVExcel Multi-Tool CVE Processing Suite
    Follows NIST security guidelines and PowerShell best practices
#>

function Initialize-LogFile {
    <#
    .SYNOPSIS
        Creates a new timestamped log file in the specified directory.

    .DESCRIPTION
        Initializes a log file with a standardized header and timestamp.
        Returns the full path to the created log file.

    .PARAMETER LogDir
        Directory where the log file should be created. Defaults to current directory.

    .PARAMETER LogPrefix
        Prefix for the log filename. Defaults to 'cvexcel_log'.

    .EXAMPLE
        $logFile = Initialize-LogFile -LogDir "C:\logs"
        Creates a log file like C:\logs\cvexcel_log_20251005_123456.log

    .OUTPUTS
        [string] Full path to the created log file
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$LogDir = $PWD,

        [Parameter()]
        [string]$LogPrefix = 'cvexcel_log'
    )

    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        try {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
            Write-Verbose "Created log directory: $LogDir"
        } catch {
            Write-Warning "Failed to create log directory: $($_.Exception.Message)"
            $LogDir = $PWD
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFileName = "${LogPrefix}_${timestamp}.log"
    $logFilePath = Join-Path $LogDir $logFileName

    $header = @"
================================================================================
CVExcel Log File
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Log File: $logFileName
================================================================================

"@

    try {
        Add-Content -Path $logFilePath -Value $header -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "Log file created: $logFilePath"
        return $logFilePath
    } catch {
        Write-Warning "Failed to create log file: $($_.Exception.Message)"
        return $null
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a formatted log entry to file and console.

    .DESCRIPTION
        Standardized logging function that writes to both log file and console
        with color-coded output based on severity level. Follows NIST logging
        guidelines with timestamps, severity levels, and structured format.

    .PARAMETER Message
        The message to log. Required.

    .PARAMETER Level
        Severity level: INFO, WARNING, ERROR, DEBUG, or SUCCESS. Defaults to INFO.

    .PARAMETER LogFile
        Path to log file. If not specified or file doesn't exist, only writes to console.

    .EXAMPLE
        Write-Log -Message "Starting process" -Level INFO

    .EXAMPLE
        Write-Log -Message "Failed to connect" -Level ERROR -LogFile $logPath

    .NOTES
        - INFO: General informational messages (white)
        - SUCCESS: Successful operations (green)
        - WARNING: Warning conditions (yellow)
        - ERROR: Error conditions (red)
        - DEBUG: Debug-level messages (gray)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO",

        [Parameter(Position = 2)]
        [string]$LogFile
    )

    # Format log entry with timestamp and level
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Write to file if specified and exists
    if ($LogFile -and (Test-Path $LogFile)) {
        try {
            Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        } catch {
            # Silently fail file write to avoid disrupting flow
            # Could enhance with Write-Warning if verbose logging needed
        }
    }

    # Determine console color based on level
    $color = switch ($Level) {
        "INFO"    { "White" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        "DEBUG"   { "Gray" }
        default   { "White" }
    }

    # Write to console with color
    Write-Host $logEntry -ForegroundColor $color
}

# Note: Functions are automatically available when dot-sourced
# Export-ModuleMember is only needed when this file is imported as a module
