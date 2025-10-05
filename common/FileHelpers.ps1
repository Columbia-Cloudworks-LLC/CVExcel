<#
.SYNOPSIS
    File operation helper functions for CVExcel project.

.DESCRIPTION
    Provides common file operation utilities for:
    - Safe file reading/writing with locking
    - CSV file operations
    - Directory management
    - File cleanup and backup
    - Atomic file operations

.NOTES
    Created: October 5, 2025
    Part of: CVExcel Phase 2 Consolidation
#>

# Import common modules
. "$PSScriptRoot\Logging.ps1"
. "$PSScriptRoot\ValidationHelpers.ps1"

#region File Reading/Writing

<#
.SYNOPSIS
    Safely reads a file with error handling.

.PARAMETER Path
    Path to the file to read.

.PARAMETER Encoding
    File encoding (default: UTF8).

.EXAMPLE
    $content = Read-FileSafe -Path "data.csv"

.OUTPUTS
    Hashtable with Success, Content, and optional Error
#>
function Read-FileSafe {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$Encoding = 'UTF8'
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            return @{
                Success = $false
                Error   = "File not found: $Path"
            }
        }

        $content = Get-Content -Path $Path -Encoding $Encoding -Raw -ErrorAction Stop

        return @{
            Success = $true
            Content = $content
            Size    = (Get-Item -Path $Path).Length
        }
    } catch {
        return @{
            Success = $false
            Error   = "Failed to read file: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Safely writes content to a file with backup option.

.PARAMETER Path
    Path to the file to write.

.PARAMETER Content
    Content to write to the file.

.PARAMETER Encoding
    File encoding (default: UTF8).

.PARAMETER CreateBackup
    If true, creates a backup of existing file before overwriting.

.PARAMETER Force
    If true, creates parent directories if they don't exist.

.EXAMPLE
    Write-FileSafe -Path "output.csv" -Content $data -CreateBackup

.OUTPUTS
    Hashtable with Success, BackupPath (if created), and optional Error
#>
function Write-FileSafe {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [string]$Encoding = 'UTF8',

        [switch]$CreateBackup,

        [switch]$Force
    )

    try {
        # Ensure parent directory exists
        $parentDir = Split-Path -Path $Path -Parent
        if ($parentDir -and -not (Test-Path -Path $parentDir)) {
            if ($Force) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            } else {
                return @{
                    Success = $false
                    Error   = "Parent directory does not exist: $parentDir"
                }
            }
        }

        $result = @{
            Success = $true
        }

        # Create backup if requested and file exists
        if ($CreateBackup -and (Test-Path -Path $Path)) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupPath = "$Path.$timestamp.bak"
            Copy-Item -Path $Path -Destination $backupPath -Force
            $result.BackupPath = $backupPath
        }

        # Write content
        Set-Content -Path $Path -Value $Content -Encoding $Encoding -ErrorAction Stop

        return $result
    } catch {
        return @{
            Success = $false
            Error   = "Failed to write file: $($_.Exception.Message)"
        }
    }
}

#endregion

#region CSV Operations

<#
.SYNOPSIS
    Safely reads a CSV file with validation.

.PARAMETER Path
    Path to the CSV file.

.PARAMETER RequiredColumns
    Array of required column names.

.PARAMETER Delimiter
    CSV delimiter (default: comma).

.EXAMPLE
    $result = Read-CsvSafe -Path "data.csv" -RequiredColumns @("CVE", "URL")

.OUTPUTS
    Hashtable with Success, Data (array of objects), and optional Error
#>
function Read-CsvSafe {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$RequiredColumns = @(),

        [string]$Delimiter = ','
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            return @{
                Success = $false
                Error   = "CSV file not found: $Path"
            }
        }

        $data = Import-Csv -Path $Path -Delimiter $Delimiter -ErrorAction Stop

        # Validate required columns
        if ($RequiredColumns.Count -gt 0 -and $data.Count -gt 0) {
            $actualColumns = $data[0].PSObject.Properties.Name
            $missingColumns = $RequiredColumns | Where-Object { $_ -notin $actualColumns }

            if ($missingColumns.Count -gt 0) {
                return @{
                    Success        = $false
                    Error          = "Missing required columns: $($missingColumns -join ', ')"
                    MissingColumns = $missingColumns
                }
            }
        }

        return @{
            Success    = $true
            Data       = $data
            RowCount   = $data.Count
            Columns    = if ($data.Count -gt 0) { $data[0].PSObject.Properties.Name } else { @() }
        }
    } catch {
        return @{
            Success = $false
            Error   = "Failed to read CSV: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Safely writes data to a CSV file with backup.

.PARAMETER Path
    Path to the CSV file.

.PARAMETER Data
    Array of objects to write to CSV.

.PARAMETER Delimiter
    CSV delimiter (default: comma).

.PARAMETER CreateBackup
    If true, creates backup of existing file.

.PARAMETER Append
    If true, appends to existing file instead of overwriting.

.EXAMPLE
    Write-CsvSafe -Path "output.csv" -Data $results -CreateBackup

.OUTPUTS
    Hashtable with Success, RowCount, and optional Error/BackupPath
#>
function Write-CsvSafe {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object[]]$Data,

        [string]$Delimiter = ',',

        [switch]$CreateBackup,

        [switch]$Append
    )

    try {
        # Ensure parent directory exists
        $parentDir = Split-Path -Path $Path -Parent
        if ($parentDir -and -not (Test-Path -Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        $result = @{
            Success  = $true
            RowCount = $Data.Count
        }

        # Create backup if requested and file exists
        if ($CreateBackup -and (Test-Path -Path $Path)) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $extension = [System.IO.Path]::GetExtension($Path)
            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($Path)
            $directory = [System.IO.Path]::GetDirectoryName($Path)
            $backupPath = Join-Path $directory "${nameWithoutExt}_${timestamp}_backup${extension}"

            Copy-Item -Path $Path -Destination $backupPath -Force
            $result.BackupPath = $backupPath
        }

        # Write CSV
        if ($Append -and (Test-Path -Path $Path)) {
            $Data | Export-Csv -Path $Path -Delimiter $Delimiter -NoTypeInformation -Append -ErrorAction Stop
        } else {
            $Data | Export-Csv -Path $Path -Delimiter $Delimiter -NoTypeInformation -ErrorAction Stop
        }

        return $result
    } catch {
        return @{
            Success = $false
            Error   = "Failed to write CSV: $($_.Exception.Message)"
        }
    }
}

#endregion

#region Directory Operations

<#
.SYNOPSIS
    Initializes a directory, creating it if it doesn't exist.

.PARAMETER Path
    Path to the directory.

.EXAMPLE
    Initialize-Directory -Path "C:\Output\Reports"

.OUTPUTS
    Hashtable with Success, Created (bool), and optional Error
#>
function Initialize-Directory {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $created = $false

        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            $created = $true
        }

        return @{
            Success = $true
            Path    = (Resolve-Path -Path $Path).Path
            Created = $created
        }
    } catch {
        return @{
            Success = $false
            Error   = "Failed to create directory: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Safely removes old files from a directory based on age.

.PARAMETER Path
    Directory path.

.PARAMETER DaysOld
    Remove files older than this many days.

.PARAMETER Pattern
    File name pattern to match (default: *).

.PARAMETER LogFile
    Optional log file path for logging operations.

.EXAMPLE
    Remove-OldFiles -Path "C:\Logs" -DaysOld 30 -Pattern "*.log"

.OUTPUTS
    Hashtable with Success, FilesRemoved (count), and optional Error
#>
function Remove-OldFiles {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$DaysOld,

        [string]$Pattern = '*',

        [string]$LogFile = ''
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            return @{
                Success = $false
                Error   = "Directory not found: $Path"
            }
        }

        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        $files = Get-ChildItem -Path $Path -Filter $Pattern -File |
                 Where-Object { $_.LastWriteTime -lt $cutoffDate }

        $removedCount = 0
        foreach ($file in $files) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $removedCount++

                if ($LogFile) {
                    Write-Log -Message "Removed old file: $($file.Name)" -Level "INFO" -LogFile $LogFile
                }
            } catch {
                if ($LogFile) {
                    Write-Log -Message "Failed to remove file $($file.Name): $($_.Exception.Message)" -Level "WARNING" -LogFile $LogFile
                }
            }
        }

        return @{
            Success       = $true
            FilesRemoved  = $removedCount
            TotalFiles    = $files.Count
        }
    } catch {
        return @{
            Success = $false
            Error   = "Failed to remove old files: $($_.Exception.Message)"
        }
    }
}

#endregion

#region File Operations

<#
.SYNOPSIS
    Generates a unique filename by appending a timestamp.

.PARAMETER BasePath
    Base file path or name.

.PARAMETER Separator
    Separator between base name and timestamp (default: _).

.EXAMPLE
    $uniquePath = Get-UniqueFilePath -BasePath "output.csv"
    # Returns: output_20251005_123456.csv

.OUTPUTS
    String with unique file path
#>
function Get-UniqueFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [string]$Separator = '_'
    )

    $directory = [System.IO.Path]::GetDirectoryName($BasePath)
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
    $extension = [System.IO.Path]::GetExtension($BasePath)
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    if ($directory) {
        return Join-Path $directory "${fileName}${Separator}${timestamp}${extension}"
    } else {
        return "${fileName}${Separator}${timestamp}${extension}"
    }
}

<#
.SYNOPSIS
    Gets a safe file name by removing invalid characters.

.PARAMETER FileName
    The file name to sanitize.

.PARAMETER Replacement
    Character to replace invalid characters with (default: _).

.EXAMPLE
    $safeName = Get-SafeFileName -FileName "Report: 2024/10/05"
    # Returns: Report__2024_10_05

.OUTPUTS
    String with safe file name
#>
function Get-SafeFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [string]$Replacement = '_'
    )

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $safeName = $FileName

    foreach ($char in $invalidChars) {
        $safeName = $safeName.Replace($char, $Replacement)
    }

    # Also replace multiple consecutive replacement characters with single one
    $safeName = $safeName -replace "($([regex]::Escape($Replacement)))+", $Replacement

    return $safeName
}

#endregion

#region Atomic Operations

<#
.SYNOPSIS
    Performs an atomic file write using a temporary file and rename.

.PARAMETER Path
    Target file path.

.PARAMETER Content
    Content to write.

.PARAMETER Encoding
    File encoding (default: UTF8).

.EXAMPLE
    Write-FileAtomic -Path "important.csv" -Content $data

.OUTPUTS
    Hashtable with Success and optional Error
#>
function Write-FileAtomic {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [string]$Encoding = 'UTF8'
    )

    $tempPath = "$Path.tmp.$(Get-Random)"

    try {
        # Write to temporary file
        Set-Content -Path $tempPath -Value $Content -Encoding $Encoding -ErrorAction Stop

        # Atomic rename
        Move-Item -Path $tempPath -Destination $Path -Force -ErrorAction Stop

        return @{
            Success = $true
        }
    } catch {
        # Clean up temporary file if it exists
        if (Test-Path -Path $tempPath) {
            try {
                Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            } catch {
                # Ignore cleanup errors
            }
        }

        return @{
            Success = $false
            Error   = "Atomic write failed: $($_.Exception.Message)"
        }
    }
}

#endregion

# Export all functions
Export-ModuleMember -Function @(
    'Read-FileSafe',
    'Write-FileSafe',
    'Read-CsvSafe',
    'Write-CsvSafe',
    'Initialize-Directory',
    'Remove-OldFiles',
    'Get-UniqueFilePath',
    'Get-SafeFileName',
    'Write-FileAtomic'
)
