# Security Audit - AI Foreman Check Script
# Performs security compliance audit based on NIST guidelines

param(
    [string]$OutputPath = ".ai/state/security-audit.json"
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Test-SecurityCompliance {
    param(
        [string]$FilePath,
        [string]$FileName
    )
    
    $audit = @{
        file = $FileName
        path = $FilePath
        issues = @()
        severity = "low"
        compliance_score = 0
    }
    
    try {
        $content = Get-Content $FilePath -Raw
        
        # Check for input validation (NIST SP 800-53 SI-10)
        if ($content -notmatch "ValidateNotNullOrEmpty|ValidatePattern|ValidateRange") {
            if ($content -match "param\s*\(") {
                $audit.issues += "Missing input validation on parameters"
            }
        }
        
        # Check for secure coding practices (NIST SP 800-53 SA-15)
        if ($content -match "Invoke-Expression|iex\s|\.\s*\\") {
            $audit.issues += "Potential code injection vulnerability"
            $audit.severity = "high"
        }
        
        # Check for credential handling (NIST SP 800-53 IA-5)
        if ($content -match "password.*=.*[\"'].*[\"']|secret.*=.*[\"'].*[\"']") {
            $audit.issues += "Hardcoded credentials detected"
            $audit.severity = "high"
        }
        
        # Check for error handling (NIST SP 800-53 SI-11)
        if ($content -notmatch "try\s*\{.*catch\s*\{") {
            if ($content -match "Invoke-WebRequest|Invoke-RestMethod|Start-Process") {
                $audit.issues += "Missing error handling for external operations"
            }
        }
        
        # Check for logging (NIST SP 800-53 AU-2)
        if ($content -notmatch "Write-Verbose|Write-Debug|Write-Log|Write-EventLog") {
            if ($content -match "Invoke-WebRequest|Invoke-RestMethod|Start-Process") {
                $audit.issues += "Missing audit logging for security-relevant operations"
            }
        }
        
        # Check for secure random number generation (NIST SP 800-53 SC-12)
        if ($content -match "Get-Random" -and $content -notmatch "Get-Random.*-Count") {
            $audit.issues += "Insecure random number generation"
        }
        
        # Check for SQL injection prevention (NIST SP 800-53 SI-10)
        if ($content -match "Invoke-Sqlcmd" -and $content -notmatch "parameterized|prepared") {
            $audit.issues += "Potential SQL injection vulnerability"
            $audit.severity = "high"
        }
        
        # Check for path traversal prevention (NIST SP 800-53 SI-10)
        if ($content -match "Get-Content|Set-Content|Remove-Item" -and $content -notmatch "Resolve-Path|Test-Path") {
            $audit.issues += "Potential path traversal vulnerability"
        }
        
        # Check for XSS prevention (NIST SP 800-53 SI-10)
        if ($content -match "Write-Output.*\$" -and $content -notmatch "Escape|Encode") {
            $audit.issues += "Potential XSS vulnerability in output"
        }
        
        # Calculate compliance score
        $totalChecks = 9
        $passedChecks = $totalChecks - $audit.issues.Count
        $audit.compliance_score = [math]::Round(($passedChecks / $totalChecks) * 100, 2)
        
        # Adjust severity based on score
        if ($audit.compliance_score -lt 50) {
            $audit.severity = "critical"
        } elseif ($audit.compliance_score -lt 70) {
            $audit.severity = "high"
        } elseif ($audit.compliance_score -lt 85) {
            $audit.severity = "medium"
        }
        
        Write-Log "Audited $FileName - Score: $($audit.compliance_score)% - Severity: $($audit.severity)"
        
        return $audit
    }
    catch {
        Write-Log "Error auditing $FileName : $($_.Exception.Message)"
        $audit.issues += "Audit error: $($_.Exception.Message)"
        $audit.severity = "high"
        return $audit
    }
}

function Get-SecurityFiles {
    $filePatterns = @("*.ps1", "*.psm1", "*.cs", "*.ts")
    $files = @()
    
    foreach ($pattern in $filePatterns) {
        $foundFiles = Get-ChildItem -Path . -Filter $pattern -Recurse -ErrorAction SilentlyContinue
        $files += $foundFiles
    }
    
    # Filter out test files and documentation
    $files = $files | Where-Object { 
        $_.FullName -notmatch "\\tests\\|\\docs\\|\\\.ai\\|\\\.git\\" 
    }
    
    return $files
}

function Invoke-ScriptAnalyzerSecurity {
    try {
        if (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue) {
            $results = Invoke-ScriptAnalyzer -Path . -Recurse -Severity @("Error", "Warning") -ErrorAction SilentlyContinue
            return $results
        }
    }
    catch {
        Write-Log "PSScriptAnalyzer not available: $($_.Exception.Message)"
    }
    
    return @()
}

# Main execution
Write-Log "Starting security compliance audit"

$securityFiles = Get-SecurityFiles
$auditResults = @{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    total_files = $securityFiles.Count
    files = @()
    overall_compliance_score = 0
    critical_issues = 0
    high_issues = 0
    medium_issues = 0
    low_issues = 0
    recommendations = @()
}

$totalScore = 0
$criticalCount = 0
$highCount = 0
$mediumCount = 0
$lowCount = 0

foreach ($file in $securityFiles) {
    $audit = Test-SecurityCompliance -FilePath $file.FullName -FileName $file.Name
    $auditResults.files += $audit
    $totalScore += $audit.compliance_score
    
    switch ($audit.severity) {
        "critical" { $criticalCount++ }
        "high" { $highCount++ }
        "medium" { $mediumCount++ }
        "low" { $lowCount++ }
    }
}

$auditResults.critical_issues = $criticalCount
$auditResults.high_issues = $highCount
$auditResults.medium_issues = $mediumCount
$auditResults.low_issues = $lowCount

# Calculate overall compliance score
if ($securityFiles.Count -gt 0) {
    $auditResults.overall_compliance_score = [math]::Round($totalScore / $securityFiles.Count, 2)
}

# Run PSScriptAnalyzer for additional checks
$scriptAnalyzerResults = Invoke-ScriptAnalyzerSecurity
if ($scriptAnalyzerResults.Count -gt 0) {
    $auditResults.recommendations += "PSScriptAnalyzer found $($scriptAnalyzerResults.Count) issues"
}

# Generate recommendations based on findings
if ($criticalCount -gt 0) {
    $auditResults.recommendations += "CRITICAL: Address $criticalCount critical security issues immediately"
}

if ($highCount -gt 0) {
    $auditResults.recommendations += "HIGH: Address $highCount high-severity security issues"
}

if ($auditResults.overall_compliance_score -lt 80) {
    $auditResults.recommendations += "Overall compliance score below 80% - comprehensive security review needed"
}

# Save audit results
$auditResults | ConvertTo-Json -Depth 4 | Set-Content $OutputPath
Write-Log "Security audit completed - Overall compliance: $($auditResults.overall_compliance_score)%"
Write-Log "Critical: $criticalCount, High: $highCount, Medium: $mediumCount, Low: $lowCount"
Write-Log "Audit saved to: $OutputPath"

# Output summary for AI Foreman
if ($criticalCount -gt 0) {
    Write-Output "SECURITY_CRITICAL_ISSUES"
} elseif ($highCount -gt 0) {
    Write-Output "SECURITY_HIGH_ISSUES"
} elseif ($auditResults.overall_compliance_score -lt 80) {
    Write-Output "SECURITY_COMPLIANCE_LOW"
} else {
    Write-Output "SECURITY_COMPLIANCE_OK"
}
