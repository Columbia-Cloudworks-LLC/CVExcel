# DataSchemas.ps1 - Core data schemas and validation for CVExcel Core Engine
# Defines the structure for Assets, Findings, and RiskResults

# Asset schema definition
class Asset {
    [string]$AssetId
    [string]$Hostname
    [string]$IPAddress
    [string]$OSVersion
    [string]$OSBuild
    [string]$Architecture
    [string[]]$Roles
    [string[]]$Features
    [string]$Domain
    [string]$DomainRole
    [string]$LastBootTime
    [string]$LastScanTime
    [string]$BusinessCriticality
    [string]$Environment
    [bool]$InternetFacing
    [bool]$ExternalExposure
    [string]$Location
    [string]$Owner
    [string]$Contact
    [string]$Notes
    [hashtable]$CustomAttributes
    [datetime]$CreatedAt
    [datetime]$UpdatedAt

    Asset() {
        $this.AssetId = [System.Guid]::NewGuid().ToString()
        $this.CreatedAt = Get-Date
        $this.UpdatedAt = Get-Date
        $this.CustomAttributes = @{}
        $this.Roles = @()
        $this.Features = @()
    }

    [void] UpdateTimestamp() {
        $this.UpdatedAt = Get-Date
    }

    [bool] Validate() {
        if ([string]::IsNullOrWhiteSpace($this.Hostname) -and [string]::IsNullOrWhiteSpace($this.IPAddress)) {
            return $false
        }
        return $true
    }
}

# Finding schema definition
class Finding {
    [string]$FindingId
    [string]$AssetId
    [string]$CVE
    [string]$CheckModule
    [string]$CheckType
    [string]$Severity
    [string]$Status
    [string]$Title
    [string]$Description
    [string]$Remediation
    [string]$References
    [string]$CVSSScore
    [string]$CVSSVector
    [string]$Exploitability
    [string]$Impact
    [string]$Confidence
    [string]$FalsePositive
    [string]$Notes
    [hashtable]$TechnicalDetails
    [datetime]$DetectedAt
    [datetime]$LastVerified
    [datetime]$CreatedAt
    [datetime]$UpdatedAt

    Finding() {
        $this.FindingId = [System.Guid]::NewGuid().ToString()
        $this.DetectedAt = Get-Date
        $this.LastVerified = Get-Date
        $this.CreatedAt = Get-Date
        $this.UpdatedAt = Get-Date
        $this.TechnicalDetails = @{}
    }

    [void] UpdateTimestamp() {
        $this.UpdatedAt = Get-Date
    }

    [bool] Validate() {
        if ([string]::IsNullOrWhiteSpace($this.AssetId) -or [string]::IsNullOrWhiteSpace($this.CheckModule)) {
            return $false
        }
        return $true
    }
}

# RiskResult schema definition
class RiskResult {
    [string]$RiskResultId
    [string]$AssetId
    [string]$FindingId
    [double]$RiskScore
    [string]$RiskLevel
    [string]$PriorityCategory
    [string]$RiskFactors
    [string]$MitigationStatus
    [string]$MitigationPlan
    [datetime]$MitigationDeadline
    [string]$AssignedTo
    [string]$Status
    [string]$Notes
    [hashtable]$RiskMetrics
    [datetime]$CalculatedAt
    [datetime]$LastReviewed
    [datetime]$CreatedAt
    [datetime]$UpdatedAt

    RiskResult() {
        $this.RiskResultId = [System.Guid]::NewGuid().ToString()
        $this.CalculatedAt = Get-Date
        $this.LastReviewed = Get-Date
        $this.CreatedAt = Get-Date
        $this.UpdatedAt = Get-Date
        $this.RiskMetrics = @{}
    }

    [void] UpdateTimestamp() {
        $this.UpdatedAt = Get-Date
    }

    [void] CalculateRiskLevel([hashtable]$thresholds) {
        if ($this.RiskScore -ge $thresholds.critical) {
            $this.RiskLevel = "Critical"
        } elseif ($this.RiskScore -ge $thresholds.high) {
            $this.RiskLevel = "High"
        } elseif ($this.RiskScore -ge $thresholds.medium) {
            $this.RiskLevel = "Medium"
        } elseif ($this.RiskScore -ge $thresholds.low) {
            $this.RiskLevel = "Low"
        } else {
            $this.RiskLevel = "Informational"
        }
    }

    [bool] Validate() {
        if ([string]::IsNullOrWhiteSpace($this.AssetId) -or [string]::IsNullOrWhiteSpace($this.FindingId)) {
            return $false
        }
        if ($this.RiskScore -lt 0 -or $this.RiskScore -gt 10) {
            return $false
        }
        return $true
    }
}

# ScanJob schema definition
class ScanJob {
    [string]$ScanJobId
    [string]$JobName
    [string]$JobType
    [string]$Status
    [string[]]$TargetAssets
    [string[]]$EnabledModules
    [hashtable]$Parameters
    [datetime]$ScheduledAt
    [datetime]$StartedAt
    [datetime]$CompletedAt
    [string]$CreatedBy
    [string]$Notes
    [hashtable]$Results
    [datetime]$CreatedAt
    [datetime]$UpdatedAt

    ScanJob() {
        $this.ScanJobId = [System.Guid]::NewGuid().ToString()
        $this.CreatedAt = Get-Date
        $this.UpdatedAt = Get-Date
        $this.Parameters = @{}
        $this.Results = @{}
        $this.TargetAssets = @()
        $this.EnabledModules = @()
    }

    [void] UpdateTimestamp() {
        $this.UpdatedAt = Get-Date
    }

    [bool] Validate() {
        if ([string]::IsNullOrWhiteSpace($this.JobName) -or [string]::IsNullOrWhiteSpace($this.JobType)) {
            return $false
        }
        return $true
    }
}

# Data validation functions
function Test-AssetData {
    [CmdletBinding()]
    param(
        [Asset]$Asset
    )

    $validationResults = @{
        IsValid  = $true
        Errors   = @()
        Warnings = @()
    }

    # Required field validation
    if ([string]::IsNullOrWhiteSpace($Asset.Hostname) -and [string]::IsNullOrWhiteSpace($Asset.IPAddress)) {
        $validationResults.Errors += "Either Hostname or IPAddress must be provided"
        $validationResults.IsValid = $false
    }

    # IP Address format validation
    if ($Asset.IPAddress -and $Asset.IPAddress -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
        $validationResults.Warnings += "IP Address format may be invalid: $($Asset.IPAddress)"
    }

    # Business criticality validation
    $validCriticalities = @("Critical", "High", "Medium", "Low", "Informational")
    if ($Asset.BusinessCriticality -and $validCriticalities -notcontains $Asset.BusinessCriticality) {
        $validationResults.Warnings += "Business criticality should be one of: $($validCriticalities -join ', ')"
    }

    return $validationResults
}

function Test-FindingData {
    [CmdletBinding()]
    param(
        [Finding]$Finding
    )

    $validationResults = @{
        IsValid  = $true
        Errors   = @()
        Warnings = @()
    }

    # Required field validation
    if ([string]::IsNullOrWhiteSpace($Finding.AssetId)) {
        $validationResults.Errors += "AssetId is required"
        $validationResults.IsValid = $false
    }

    if ([string]::IsNullOrWhiteSpace($Finding.CheckModule)) {
        $validationResults.Errors += "CheckModule is required"
        $validationResults.IsValid = $false
    }

    # Severity validation
    $validSeverities = @("Critical", "High", "Medium", "Low", "Informational")
    if ($Finding.Severity -and $validSeverities -notcontains $Finding.Severity) {
        $validationResults.Warnings += "Severity should be one of: $($validSeverities -join ', ')"
    }

    # CVSS Score validation
    if ($Finding.CVSSScore -and ($Finding.CVSSScore -lt 0 -or $Finding.CVSSScore -gt 10)) {
        $validationResults.Warnings += "CVSS Score should be between 0 and 10"
    }

    return $validationResults
}

function Test-RiskResultData {
    [CmdletBinding()]
    param(
        [RiskResult]$RiskResult
    )

    $validationResults = @{
        IsValid  = $true
        Errors   = @()
        Warnings = @()
    }

    # Required field validation
    if ([string]::IsNullOrWhiteSpace($RiskResult.AssetId)) {
        $validationResults.Errors += "AssetId is required"
        $validationResults.IsValid = $false
    }

    if ([string]::IsNullOrWhiteSpace($RiskResult.FindingId)) {
        $validationResults.Errors += "FindingId is required"
        $validationResults.IsValid = $false
    }

    # Risk score validation
    if ($RiskResult.RiskScore -lt 0 -or $RiskResult.RiskScore -gt 10) {
        $validationResults.Errors += "Risk score must be between 0 and 10"
        $validationResults.IsValid = $false
    }

    # Risk level validation
    $validRiskLevels = @("Critical", "High", "Medium", "Low", "Informational")
    if ($RiskResult.RiskLevel -and $validRiskLevels -notcontains $RiskResult.RiskLevel) {
        $validationResults.Warnings += "Risk level should be one of: $($validRiskLevels -join ', ')"
    }

    return $validationResults
}

# Data conversion functions
function ConvertTo-AssetObject {
    [CmdletBinding()]
    param(
        [hashtable]$Data
    )

    $asset = [Asset]::new()

    foreach ($key in $Data.Keys) {
        $property = $asset.GetType().GetProperty($key)
        if ($property -and $property.CanWrite) {
            $property.SetValue($asset, $Data[$key])
        }
    }

    return $asset
}

function ConvertTo-FindingObject {
    [CmdletBinding()]
    param(
        [hashtable]$Data
    )

    $finding = [Finding]::new()

    foreach ($key in $Data.Keys) {
        $property = $finding.GetType().GetProperty($key)
        if ($property -and $property.CanWrite) {
            $property.SetValue($finding, $Data[$key])
        }
    }

    return $finding
}

function ConvertTo-RiskResultObject {
    [CmdletBinding()]
    param(
        [hashtable]$Data
    )

    $riskResult = [RiskResult]::new()

    foreach ($key in $Data.Keys) {
        $property = $riskResult.GetType().GetProperty($key)
        if ($property -and $property.CanWrite) {
            $property.SetValue($riskResult, $Data[$key])
        }
    }

    return $riskResult
}

# Export classes and functions
Export-ModuleMember -Type @(
    'Asset',
    'Finding',
    'RiskResult',
    'ScanJob'
)

Export-ModuleMember -Function @(
    'Test-AssetData',
    'Test-FindingData',
    'Test-RiskResultData',
    'ConvertTo-AssetObject',
    'ConvertTo-FindingObject',
    'ConvertTo-RiskResultObject'
)
