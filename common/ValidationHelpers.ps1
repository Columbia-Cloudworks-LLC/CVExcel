<#
.SYNOPSIS
    Validation helper functions for CVExcel project.

.DESCRIPTION
    Provides common validation utilities for:
    - Parameter validation
    - URL validation
    - File path validation
    - Data format validation
    - Security checks

.NOTES
    Created: October 5, 2025
    Part of: CVExcel Phase 2 Consolidation
#>

# Import common logging
. "$PSScriptRoot\Logging.ps1"

#region URL Validation

<#
.SYNOPSIS
    Validates if a string is a properly formatted URL.

.PARAMETER Url
    The URL string to validate.

.PARAMETER RequireHttps
    If true, only HTTPS URLs are considered valid.

.EXAMPLE
    Test-ValidUrl -Url "https://example.com"

.OUTPUTS
    Boolean indicating if URL is valid
#>
function Test-ValidUrl {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Url,

        [switch]$RequireHttps
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    try {
        $uri = [System.Uri]$Url

        if ($RequireHttps) {
            return $uri.Scheme -eq 'https'
        } else {
            return $uri.Scheme -in @('http', 'https')
        }
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    Validates if a URL is from an allowed domain.

.PARAMETER Url
    The URL to check.

.PARAMETER AllowedDomains
    Array of allowed domain patterns (supports wildcards).

.EXAMPLE
    Test-AllowedDomain -Url "https://github.com/user/repo" -AllowedDomains @("github.com", "*.microsoft.com")

.OUTPUTS
    Boolean indicating if domain is allowed
#>
function Test-AllowedDomain {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedDomains
    )

    try {
        $uri = [System.Uri]$Url
        $domain = $uri.Host

        foreach ($allowedDomain in $AllowedDomains) {
            if ($domain -like $allowedDomain) {
                return $true
            }
        }

        return $false
    } catch {
        return $false
    }
}

#endregion

#region File Path Validation

<#
.SYNOPSIS
    Validates if a file path is safe and within allowed boundaries.

.PARAMETER Path
    The file path to validate.

.PARAMETER AllowedRoot
    Optional root directory - path must be within this directory.

.PARAMETER CheckExists
    If true, also checks if the file exists.

.EXAMPLE
    Test-SafeFilePath -Path "C:\Data\file.csv" -AllowedRoot "C:\Data"

.OUTPUTS
    Hashtable with IsValid and optional Error message
#>
function Test-SafeFilePath {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$AllowedRoot = '',

        [switch]$CheckExists
    )

    # Check for path traversal attempts
    if ($Path -match '\.\.' -or $Path -match '[<>"|?*]') {
        return @{
            IsValid = $false
            Error   = "Path contains invalid characters or traversal attempts"
        }
    }

    # Normalize path
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return @{
            IsValid = $false
            Error   = "Invalid path format: $($_.Exception.Message)"
        }
    }

    # Check if within allowed root
    if ($AllowedRoot) {
        try {
            $fullRoot = [System.IO.Path]::GetFullPath($AllowedRoot)
            if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
                return @{
                    IsValid = $false
                    Error   = "Path is outside allowed root directory"
                }
            }
        } catch {
            return @{
                IsValid = $false
                Error   = "Invalid root directory: $($_.Exception.Message)"
            }
        }
    }

    # Check existence if requested
    if ($CheckExists -and -not (Test-Path -Path $fullPath)) {
        return @{
            IsValid = $false
            Error   = "Path does not exist"
        }
    }

    return @{
        IsValid  = $true
        FullPath = $fullPath
    }
}

<#
.SYNOPSIS
    Validates if a file extension is allowed.

.PARAMETER Path
    The file path or name to check.

.PARAMETER AllowedExtensions
    Array of allowed extensions (with or without dot).

.EXAMPLE
    Test-AllowedExtension -Path "file.csv" -AllowedExtensions @("csv", "txt")

.OUTPUTS
    Boolean indicating if extension is allowed
#>
function Test-AllowedExtension {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions
    )

    $extension = [System.IO.Path]::GetExtension($Path).TrimStart('.')

    foreach ($allowed in $AllowedExtensions) {
        $cleanAllowed = $allowed.TrimStart('.')
        if ($extension -eq $cleanAllowed) {
            return $true
        }
    }

    return $false
}

#endregion

#region Data Format Validation

<#
.SYNOPSIS
    Validates if a string is a valid CVE identifier.

.PARAMETER CVE
    The CVE string to validate.

.EXAMPLE
    Test-ValidCVE -CVE "CVE-2024-1234"

.OUTPUTS
    Boolean indicating if CVE is valid
#>
function Test-ValidCVE {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$CVE
    )

    return $CVE -match '^CVE-\d{4}-\d+$'
}

<#
.SYNOPSIS
    Validates if a string is a valid version number.

.PARAMETER Version
    The version string to validate.

.PARAMETER AllowPrerelease
    If true, allows prerelease suffixes (e.g., "1.0.0-beta").

.EXAMPLE
    Test-ValidVersion -Version "1.2.3.4"

.OUTPUTS
    Boolean indicating if version is valid
#>
function Test-ValidVersion {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Version,

        [switch]$AllowPrerelease
    )

    if ($AllowPrerelease) {
        return $Version -match '^\d+\.\d+(?:\.\d+)?(?:\.\d+)?(?:-[a-z0-9]+)?$'
    } else {
        return $Version -match '^\d+\.\d+(?:\.\d+)?(?:\.\d+)?$'
    }
}

<#
.SYNOPSIS
    Validates if a string is a valid Microsoft KB number.

.PARAMETER KB
    The KB string to validate.

.EXAMPLE
    Test-ValidKB -KB "KB5001234"

.OUTPUTS
    Boolean indicating if KB is valid
#>
function Test-ValidKB {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$KB
    )

    return $KB -match '^KB\d+$'
}

#endregion

#region Parameter Validation

<#
.SYNOPSIS
    Validates that required parameters are present in a hashtable.

.PARAMETER Parameters
    The hashtable to validate.

.PARAMETER RequiredKeys
    Array of required key names.

.EXAMPLE
    $result = Test-RequiredParameters -Parameters $config -RequiredKeys @("Url", "OutputPath")

.OUTPUTS
    Hashtable with IsValid and MissingKeys properties
#>
function Test-RequiredParameters {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredKeys
    )

    $missingKeys = @()

    foreach ($key in $RequiredKeys) {
        if (-not $Parameters.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($Parameters[$key])) {
            $missingKeys += $key
        }
    }

    return @{
        IsValid     = $missingKeys.Count -eq 0
        MissingKeys = $missingKeys
    }
}

<#
.SYNOPSIS
    Validates that a value is within an allowed set.

.PARAMETER Value
    The value to check.

.PARAMETER AllowedValues
    Array of allowed values.

.PARAMETER IgnoreCase
    If true, comparison is case-insensitive.

.EXAMPLE
    Test-AllowedValue -Value "chromium" -AllowedValues @("chromium", "firefox", "webkit")

.OUTPUTS
    Boolean indicating if value is allowed
#>
function Test-AllowedValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedValues,

        [bool]$IgnoreCase = $true
    )

    if ($IgnoreCase) {
        return $AllowedValues -contains $Value -or $AllowedValues.ToLower() -contains $Value.ToLower()
    } else {
        return $AllowedValues -contains $Value
    }
}

#endregion

#region Security Validation

<#
.SYNOPSIS
    Validates that a string does not contain malicious patterns.

.PARAMETER Input
    The string to validate.

.EXAMPLE
    $result = Test-NoMaliciousContent -Input $userInput

.OUTPUTS
    Hashtable with IsSafe and optional DetectedPatterns
#>
function Test-NoMaliciousContent {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Input
    )

    $maliciousPatterns = @(
        # Command injection
        '[;&|`$()]'
        # Path traversal
        '\.\.[/\\]'
        # Script tags
        '<script[^>]*>'
        # SQL injection basic patterns
        '(?i)(union.*select|insert.*into|drop.*table|exec\s*\()'
    )

    $detected = @()

    foreach ($pattern in $maliciousPatterns) {
        if ($Input -match $pattern) {
            $detected += $pattern
        }
    }

    return @{
        IsSafe           = $detected.Count -eq 0
        DetectedPatterns = $detected
    }
}

#endregion

# Export all functions
Export-ModuleMember -Function @(
    'Test-ValidUrl',
    'Test-AllowedDomain',
    'Test-SafeFilePath',
    'Test-AllowedExtension',
    'Test-ValidCVE',
    'Test-ValidVersion',
    'Test-ValidKB',
    'Test-RequiredParameters',
    'Test-AllowedValue',
    'Test-NoMaliciousContent'
)
