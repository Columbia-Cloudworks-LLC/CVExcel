# CVExcel Core Engine - Module Development Guide

## Overview

This guide explains how to develop custom modules for the CVExcel Core Engine. The modular architecture allows you to extend functionality by creating new feeds, inventory modules, scanners, assessments, and output modules.

## Module Architecture

### Base Classes

All modules inherit from base classes that provide common functionality:

- **BaseFeed**: For vulnerability data feeds
- **BaseInventory**: For asset discovery modules
- **BaseScanner**: For vulnerability detection modules
- **BaseAssessment**: For risk scoring modules
- **BaseOutput**: For data export modules

### Common Interface

All modules must implement:
- `GetModuleInfo()`: Return module information and status
- Module-specific interface methods (varies by type)

## Module Types

### 1. Feed Modules

Feed modules provide vulnerability data from external sources.

#### Base Class: BaseFeed

```powershell
class Feed_Custom : BaseFeed {
    Feed_Custom() : base("Custom", "Vendor", @("custom.com", "api.custom.com")) {
        $this.Configuration = @{
            ApiKey = $null
            RateLimitDelay = 1000
            CacheEnabled = $true
        }
    }

    [hashtable] GetVulnerabilityData([string]$cveId) {
        # Implementation for single CVE lookup
    }

    [hashtable] GetBulkVulnerabilityData([string[]]$cveIds) {
        # Implementation for bulk CVE lookup
    }

    [hashtable] SearchVulnerabilities([hashtable]$searchCriteria) {
        # Implementation for vulnerability search
    }
}
```

#### Required Methods

- `GetVulnerabilityData(cveId)`: Get data for specific CVE
- `GetBulkVulnerabilityData(cveIds)`: Get data for multiple CVEs
- `SearchVulnerabilities(criteria)`: Search vulnerabilities by criteria

#### Example: Custom API Feed

```powershell
# Feed_CustomAPI.ps1
. "$PSScriptRoot/BaseFeed.ps1"

class Feed_CustomAPI : BaseFeed {
    [string]$ApiKey
    [string]$BaseUrl

    Feed_CustomAPI() : base("CustomAPI", "API", @("api.custom.com")) {
        $this.ApiKey = $env:CUSTOM_API_KEY
        $this.BaseUrl = "https://api.custom.com/v1"
    }

    [hashtable] GetVulnerabilityData([string]$cveId) {
        try {
            $url = "$($this.BaseUrl)/cve/$cveId"
            $headers = @{
                'Authorization' = "Bearer $($this.ApiKey)"
                'Accept' = 'application/json'
            }

            $response = $this.Invoke-SafeApiRequest -Uri $url -Headers $headers

            if ($response.Success) {
                $cleanedData = $this.CleanVulnerabilityData($response.Data)
                return @{
                    Success = $true
                    Data = $cleanedData
                    Method = "Custom API"
                    Source = $this.FeedName
                }
            } else {
                return @{
                    Success = $false
                    Error = $response.Error
                    Source = $this.FeedName
                }
            }
        }
        catch {
            return @{
                Success = $false
                Error = $_.Exception.Message
                Source = $this.FeedName
            }
        }
    }

    [hashtable] GetBulkVulnerabilityData([string[]]$cveIds) {
        $results = @()
        $successCount = 0

        foreach ($cveId in $cveIds) {
            $result = $this.GetVulnerabilityData($cveId)
            $results += $result

            if ($result.Success) {
                $successCount++
            }

            Start-Sleep -Milliseconds $this.Configuration.RateLimitDelay
        }

        return @{
            Success = $successCount -gt 0
            Results = $results
            TotalRequested = $cveIds.Count
            SuccessCount = $successCount
            Source = $this.FeedName
        }
    }

    [hashtable] SearchVulnerabilities([hashtable]$searchCriteria) {
        try {
            $url = "$($this.BaseUrl)/search"
            $headers = @{
                'Authorization' = "Bearer $($this.ApiKey)"
                'Accept' = 'application/json'
            }

            $body = @{
                query = $searchCriteria.Query
                severity = $searchCriteria.Severity
                dateFrom = $searchCriteria.DateFrom
                dateTo = $searchCriteria.DateTo
            }

            $response = $this.Invoke-SafeApiRequest -Uri $url -Headers $headers -Method "POST" -Body $body

            if ($response.Success) {
                return @{
                    Success = $true
                    Results = $response.Data.results
                    TotalCount = $response.Data.totalCount
                    Source = $this.FeedName
                }
            } else {
                return @{
                    Success = $false
                    Error = $response.Error
                    Source = $this.FeedName
                }
            }
        }
        catch {
            return @{
                Success = $false
                Error = $_.Exception.Message
                Source = $this.FeedName
            }
        }
    }
}

Export-ModuleMember -Type 'Feed_CustomAPI'
```

### 2. Inventory Modules

Inventory modules discover and enumerate assets.

#### Base Class: BaseInventory

```powershell
class Inventory_Custom : BaseInventory {
    Inventory_Custom() : base("Custom", "Cloud") {
        $this.Configuration = @{
            ApiKey = $null
            Region = "us-east-1"
            ScanTimeout = 300
        }
    }

    [Asset[]] DiscoverAssets([string[]]$targets) {
        # Implementation for asset discovery
    }
}
```

#### Required Methods

- `DiscoverAssets(targets)`: Discover and enumerate assets
- `GetModuleInfo()`: Return module information and status

#### Example: AWS EC2 Inventory

```powershell
# Inventory_AWS.ps1
. "$PSScriptRoot/../common/DataSchemas.ps1"

class Inventory_AWS : BaseInventory {
    [string]$AccessKey
    [string]$SecretKey
    [string]$Region

    Inventory_AWS() : base("AWS", "Cloud") {
        $this.AccessKey = $env:AWS_ACCESS_KEY_ID
        $this.SecretKey = $env:AWS_SECRET_ACCESS_KEY
        $this.Region = "us-east-1"
        $this.Configuration = @{
            Regions = @("us-east-1", "us-west-2")
            InstanceTypes = @("t2.micro", "t2.small", "t2.medium")
            ScanTimeout = 300
        }
    }

    [Asset[]] DiscoverAssets([string[]]$targets) {
        $assets = @()

        try {
            # Initialize AWS SDK
            $awsProfile = New-AWSCredential -AccessKey $this.AccessKey -SecretKey $this.SecretKey
            Set-AWSCredential -Credential $awsProfile
            Set-DefaultAWSRegion -Region $this.Region

            # Get EC2 instances
            $instances = Get-EC2Instance -Region $this.Region

            foreach ($instance in $instances.Instances) {
                $asset = [Asset]::new()
                $asset.Hostname = $instance.Tags | Where-Object { $_.Key -eq "Name" } | Select-Object -ExpandProperty Value
                $asset.IPAddress = $instance.PublicIpAddress
                $asset.Domain = "AWS"
                $asset.Environment = "Cloud"
                $asset.BusinessCriticality = "Medium"
                $asset.LastScanTime = Get-Date

                # Get instance details
                $asset.CustomAttributes = @{
                    InstanceId = $instance.InstanceId
                    InstanceType = $instance.InstanceType
                    State = $instance.State.Name
                    LaunchTime = $instance.LaunchTime
                    SecurityGroups = $instance.SecurityGroups.GroupName
                    VpcId = $instance.VpcId
                    SubnetId = $instance.SubnetId
                }

                $assets += $asset
            }

            Write-InventoryLog "Discovered $($assets.Count) AWS instances" -Level "SUCCESS" -ModuleName $this.ModuleName
        }
        catch {
            Write-InventoryLog "AWS discovery failed: $($_.Exception.Message)" -Level "ERROR" -ModuleName $this.ModuleName
        }

        return $assets
    }

    [hashtable] GetModuleInfo() {
        return @{
            Name = $this.ModuleName
            Type = "Inventory"
            Enabled = $this.IsEnabled
            LastScan = $this.LastScan
            Configuration = $this.Configuration
        }
    }
}

Export-ModuleMember -Type 'Inventory_AWS'
```

### 3. Scanner Modules

Scanner modules detect vulnerabilities in assets.

#### Base Class: BaseScanner

```powershell
class Scanner_Custom : BaseScanner {
    Scanner_Custom() : base("Custom", "Web") {
        $this.Configuration = @{
            ScanTimeout = 30
            MaxConcurrentScans = 10
            VulnerabilityChecks = $true
        }
    }

    [Finding[]] ScanAsset([Asset]$asset) {
        # Implementation for vulnerability scanning
    }
}
```

#### Required Methods

- `ScanAsset(asset)`: Scan specific asset for vulnerabilities
- `GetModuleInfo()`: Return module information and status

#### Example: Web Application Scanner

```powershell
# Scanner_WebApp.ps1
. "$PSScriptRoot/../common/DataSchemas.ps1"

class Scanner_WebApp : BaseScanner {
    Scanner_WebApp() : base("WebApp", "Web") {
        $this.Configuration = @{
            ScanTimeout = 30
            MaxConcurrentScans = 5
            VulnerabilityChecks = $true
            CheckSSL = $true
            CheckHeaders = $true
            CheckForms = $true
        }
    }

    [Finding[]] ScanAsset([Asset]$asset) {
        $findings = @()

        try {
            # Check if asset has web services
            $webPorts = @(80, 443, 8080, 8443)
            $hasWebService = $false

            foreach ($port in $webPorts) {
                if ($this.TestPort($asset.IPAddress, $port)) {
                    $hasWebService = $true
                    break
                }
            }

            if (-not $hasWebService) {
                return $findings
            }

            # Scan web application
            $webFindings = $this.ScanWebApplication($asset)
            $findings += $webFindings

            Write-ScannerLog "Web application scan completed for $($asset.Hostname). Found $($findings.Count) findings" -Level "SUCCESS" -ModuleName $this.ModuleName
        }
        catch {
            Write-ScannerLog "Web application scan failed for $($asset.Hostname): $($_.Exception.Message)" -Level "ERROR" -ModuleName $this.ModuleName
        }

        return $findings
    }

    [Finding[]] ScanWebApplication([Asset]$asset) {
        $findings = @()

        # Check SSL/TLS configuration
        if ($this.Configuration.CheckSSL) {
            $sslFindings = $this.CheckSSLConfiguration($asset)
            $findings += $sslFindings
        }

        # Check HTTP security headers
        if ($this.Configuration.CheckHeaders) {
            $headerFindings = $this.CheckSecurityHeaders($asset)
            $findings += $headerFindings
        }

        # Check for common web vulnerabilities
        if ($this.Configuration.VulnerabilityChecks) {
            $vulnFindings = $this.CheckWebVulnerabilities($asset)
            $findings += $vulnFindings
        }

        return $findings
    }

    [Finding[]] CheckSSLConfiguration([Asset]$asset) {
        $findings = @()

        try {
            $url = "https://$($asset.IPAddress)"
            $request = [System.Net.WebRequest]::Create($url)
            $request.Timeout = $this.Configuration.ScanTimeout * 1000

            $response = $request.GetResponse()
            $response.Close()

            # Check SSL certificate
            $cert = $request.ServicePoint.Certificate
            if ($cert) {
                $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)

                # Check certificate expiration
                if ($certObj.NotAfter -lt (Get-Date).AddDays(30)) {
                    $finding = $this.CreateFinding($asset, "SSL_CERT_EXPIRING", "High", "SSL certificate expires within 30 days", "Renew SSL certificate")
                    $findings += $finding
                }

                # Check certificate strength
                if ($certObj.PublicKey.Key.KeySize -lt 2048) {
                    $finding = $this.CreateFinding($asset, "SSL_WEAK_KEY", "Medium", "SSL certificate uses weak key size", "Upgrade to stronger SSL certificate")
                    $findings += $finding
                }
            }
        }
        catch {
            # SSL not available or error
        }

        return $findings
    }

    [Finding[]] CheckSecurityHeaders([Asset]$asset) {
        $findings = @()

        try {
            $url = "http://$($asset.IPAddress)"
            $response = Invoke-WebRequest -Uri $url -TimeoutSec $this.Configuration.ScanTimeout -UseBasicParsing

            $requiredHeaders = @{
                "Strict-Transport-Security" = "HSTS header missing"
                "X-Content-Type-Options" = "X-Content-Type-Options header missing"
                "X-Frame-Options" = "X-Frame-Options header missing"
                "X-XSS-Protection" = "X-XSS-Protection header missing"
            }

            foreach ($header in $requiredHeaders.Keys) {
                if (-not $response.Headers.ContainsKey($header)) {
                    $finding = $this.CreateFinding($asset, "MISSING_SECURITY_HEADER", "Medium", $requiredHeaders[$header], "Add missing security header: $header")
                    $findings += $finding
                }
            }
        }
        catch {
            # Web request failed
        }

        return $findings
    }

    [Finding[]] CheckWebVulnerabilities([Asset]$asset) {
        $findings = @()

        # Check for common web vulnerabilities
        $vulnerabilities = @(
            @{
                Name = "SQL_INJECTION"
                Severity = "High"
                Description = "Potential SQL injection vulnerability"
                Remediation = "Use parameterized queries and input validation"
            },
            @{
                Name = "XSS_VULNERABILITY"
                Severity = "Medium"
                Description = "Potential cross-site scripting vulnerability"
                Remediation = "Implement proper input validation and output encoding"
            }
        )

        foreach ($vuln in $vulnerabilities) {
            # Simplified vulnerability check
            $finding = $this.CreateFinding($asset, $vuln.Name, $vuln.Severity, $vuln.Description, $vuln.Remediation)
            $findings += $finding
        }

        return $findings
    }

    [bool] TestPort([string]$ipAddress, [int]$port) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $tcpClient.Connect($ipAddress, $port)
            $tcpClient.Close()
            return $true
        }
        catch {
            return $false
        }
    }

    [Finding] CreateFinding([Asset]$asset, [string]$checkType, [string]$severity, [string]$description, [string]$remediation) {
        $finding = [Finding]::new()
        $finding.AssetId = $asset.AssetId
        $finding.CheckModule = $this.ModuleName
        $finding.CheckType = $checkType
        $finding.Severity = $severity
        $finding.Status = "Open"
        $finding.Title = $checkType
        $finding.Description = $description
        $finding.Remediation = $remediation
        $finding.Confidence = "Medium"
        $finding.DetectedAt = Get-Date
        $finding.LastVerified = Get-Date

        return $finding
    }

    [hashtable] GetModuleInfo() {
        return @{
            Name = $this.ModuleName
            Type = "Scanner"
            Enabled = $this.IsEnabled
            LastScan = $this.LastScan
            Configuration = $this.Configuration
        }
    }
}

Export-ModuleMember -Type 'Scanner_WebApp'
```

### 4. Assessment Modules

Assessment modules calculate risk scores and priorities.

#### Base Class: BaseAssessment

```powershell
class Assessment_Custom : BaseAssessment {
    Assessment_Custom() : base("Custom", "ML") {
        $this.Configuration = @{
            Algorithm = "machine_learning"
            ModelPath = "models/risk_model.pkl"
            ConfidenceThreshold = 0.8
        }
    }

    [RiskResult[]] AssessRisk([Asset]$asset, [Finding[]]$findings) {
        # Implementation for risk assessment
    }
}
```

#### Required Methods

- `AssessRisk(asset, findings)`: Calculate risk scores
- `GetModuleInfo()`: Return module information and status

### 5. Output Modules

Output modules export data in various formats.

#### Base Class: BaseOutput

```powershell
class Output_Custom : BaseOutput {
    Output_Custom() : base("Custom", "JSON") {
        $this.Configuration = @{
            Format = "json"
            IncludeMetadata = $true
            CompressOutput = $false
        }
    }

    [hashtable] ExportData([hashtable]$data, [string]$format) {
        # Implementation for data export
    }
}
```

#### Required Methods

- `ExportData(data, format)`: Export data in specified format
- `GetModuleInfo()`: Return module information and status

## Module Development Best Practices

### 1. Error Handling

Always implement comprehensive error handling:

```powershell
try {
    # Module logic here
    return $result
}
catch {
    Write-ModuleLog "Error in module operation: $($_.Exception.Message)" -Level "ERROR"
    return @{
        Success = $false
        Error = $_.Exception.Message
    }
}
```

### 2. Logging

Use consistent logging throughout modules:

```powershell
function Write-ModuleLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$ModuleName = "CustomModule"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [Module:$ModuleName] $Message"

    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "INFO" { "Cyan" }
        "DEBUG" { "Gray" }
        default { "White" }
    }

    Write-Host $logEntry -ForegroundColor $color
}
```

### 3. Configuration

Make modules configurable through the main configuration:

```powershell
# In config.json
{
  "modules": {
    "feeds": ["Feed_Custom"],
    "scanners": ["Scanner_Custom"]
  },
  "customModule": {
    "apiKey": "your-api-key",
    "timeout": 30,
    "retries": 3
  }
}
```

### 4. Data Validation

Always validate input data:

```powershell
[bool] ValidateInput([hashtable]$input) {
    if (-not $input.ContainsKey("requiredField")) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($input.requiredField)) {
        return $false
    }

    return $true
}
```

### 5. Resource Management

Properly manage resources and cleanup:

```powershell
try {
    $resource = New-Object SomeResource
    # Use resource
}
finally {
    if ($resource) {
        $resource.Dispose()
    }
}
```

## Testing Modules

### 1. Unit Testing

Create test scripts for your modules:

```powershell
# Test_Feed_Custom.ps1
Describe "Feed_Custom Tests" {
    BeforeAll {
        . "$PSScriptRoot/../core-engine/feeds/Feed_Custom.ps1"
        $feed = [Feed_Custom]::new()
    }

    It "Should get vulnerability data for valid CVE" {
        $result = $feed.GetVulnerabilityData("CVE-2023-1234")
        $result.Success | Should -Be $true
        $result.Data.CVE | Should -Be "CVE-2023-1234"
    }

    It "Should handle invalid CVE gracefully" {
        $result = $feed.GetVulnerabilityData("INVALID-CVE")
        $result.Success | Should -Be $false
    }
}
```

### 2. Integration Testing

Test module integration with the core engine:

```powershell
# Test_Integration.ps1
Describe "Module Integration Tests" {
    It "Should load custom module successfully" {
        . "$PSScriptRoot/../core-engine/common/ModuleLoader.ps1"
        $initResult = Initialize-ModuleLoader
        $initResult | Should -Be $true

        $modules = Get-LoadedModules -ModuleType "Feeds"
        $modules.ContainsKey("Feed_Custom") | Should -Be $true
    }
}
```

## Module Deployment

### 1. File Structure

Organize your module files properly:

```
core-engine/
├── feeds/
│   ├── BaseFeed.ps1
│   ├── Feed_Custom.ps1
│   └── Test_Feed_Custom.ps1
├── scanners/
│   ├── BaseScanner.ps1
│   ├── Scanner_Custom.ps1
│   └── Test_Scanner_Custom.ps1
└── common/
    ├── ModuleLoader.ps1
    └── DataSchemas.ps1
```

### 2. Configuration Updates

Update the main configuration to include your module:

```json
{
  "modules": {
    "feeds": [
      "Feed_Microsoft",
      "Feed_Custom"
    ],
    "scanners": [
      "Scanner_Network",
      "Scanner_Custom"
    ]
  }
}
```

### 3. Documentation

Document your module:

```powershell
<#
.SYNOPSIS
    Custom vulnerability feed module

.DESCRIPTION
    This module provides vulnerability data from a custom API source.
    It implements the BaseFeed interface and provides CVE data retrieval.

.PARAMETER ApiKey
    API key for authentication

.EXAMPLE
    $feed = [Feed_Custom]::new()
    $result = $feed.GetVulnerabilityData("CVE-2023-1234")

.NOTES
    Author: Your Name
    Version: 1.0.0
#>
```

## Conclusion

This guide provides the foundation for developing custom modules for CVExcel Core Engine. Follow the established patterns and best practices to ensure your modules integrate seamlessly with the platform.

For additional help and examples, refer to the existing modules in the codebase and the comprehensive documentation.
