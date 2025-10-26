# Security Fixes Planner - AI Foreman Planner Script
# Plans security fixes based on audit results

param(
    [Parameter(Mandatory=$true)]
    [string]$Audit,
    
    [string]$OutputPath = ".ai/state/security-plan.json"
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Get-AuditResults {
    param([string]$AuditPath)
    
    if (-not (Test-Path $AuditPath)) {
        Write-Log "Audit file not found: $AuditPath"
        return $null
    }
    
    try {
        $audit = Get-Content $AuditPath | ConvertFrom-Json
        Write-Log "Processing security audit for $($audit.total_files) files"
        return $audit
    }
    catch {
        Write-Log "Error reading audit: $($_.Exception.Message)"
        return $null
    }
}

function Plan-SecurityFixes {
    param($Audit)
    
    $plan = @{
        type = "security_compliance"
        description = "Implement NIST security guidelines compliance"
        changes = @()
        files_to_modify = @()
        tests_to_run = @()
        priority = "high"
    }
    
    # Process critical and high severity issues first
    $criticalFiles = $Audit.files | Where-Object { $_.severity -eq "critical" }
    $highFiles = $Audit.files | Where-Object { $_.severity -eq "high" }
    
    foreach ($file in $criticalFiles) {
        $plan.files_to_modify += $file.path
        $plan.changes += "CRITICAL: Fix security issues in $($file.file)"
        
        foreach ($issue in $file.issues) {
            $plan.changes += "  - $issue"
        }
    }
    
    foreach ($file in $highFiles) {
        $plan.files_to_modify += $file.path
        $plan.changes += "HIGH: Address security issues in $($file.file)"
        
        foreach ($issue in $file.issues) {
            $plan.changes += "  - $issue"
        }
    }
    
    # Add general security improvements
    if ($Audit.overall_compliance_score -lt 80) {
        $plan.changes += "Implement comprehensive input validation across all modules"
        $plan.changes += "Add secure error handling without information disclosure"
        $plan.changes += "Implement proper logging for security-relevant operations"
        $plan.changes += "Add credential handling using SecureString"
        $plan.changes += "Implement rate limiting and retry logic for external calls"
        $plan.changes += "Add path traversal prevention for file operations"
        $plan.changes += "Implement XSS prevention in output operations"
    }
    
    # Add specific fixes based on common issues
    $allIssues = $Audit.files | ForEach-Object { $_.issues } | Group-Object | Sort-Object Count -Descending
    
    foreach ($issue in $allIssues) {
        if ($issue.Count -gt 2) {
            switch ($issue.Name) {
                "Missing input validation on parameters" {
                    $plan.changes += "Add ValidateNotNullOrEmpty and ValidatePattern to all parameters"
                }
                "Potential code injection vulnerability" {
                    $plan.changes += "Replace Invoke-Expression with safer alternatives"
                }
                "Hardcoded credentials detected" {
                    $plan.changes += "Replace hardcoded credentials with SecureString or environment variables"
                }
                "Missing error handling for external operations" {
                    $plan.changes += "Add try-catch blocks around all external operations"
                }
                "Missing audit logging for security-relevant operations" {
                    $plan.changes += "Add comprehensive logging for all security-relevant operations"
                }
                "Potential SQL injection vulnerability" {
                    $plan.changes += "Use parameterized queries for all database operations"
                }
                "Potential path traversal vulnerability" {
                    $plan.changes += "Add path validation and use Resolve-Path for file operations"
                }
                "Potential XSS vulnerability in output" {
                    $plan.changes += "Escape or encode all user-controlled output"
                }
            }
        }
    }
    
    # Add security-focused tests
    $plan.tests_to_run += "pwsh -Command 'Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error'"
    $plan.tests_to_run += "pwsh ./tests/test-security-compliance.ps1"
    $plan.tests_to_run += "pwsh ./tests/run-all-tests.ps1"
    
    # Add PSScriptAnalyzer security rules
    $plan.tests_to_run += "pwsh -Command 'Invoke-ScriptAnalyzer -Path . -Recurse -IncludeRule @(\"PSAvoidUsingInvokeExpression\", \"PSAvoidUsingPlainTextForPassword\", \"PSAvoidUsingUsernameAndPasswordParams\")'"
    
    return $plan
}

function Generate-SecurityDiff {
    param($Plan)
    
    $diff = @()
    $diff += "diff --git a/SECURITY_FIXES_PLAN b/SECURITY_FIXES_PLAN"
    $diff += "new file mode 100644"
    $diff += "index 0000000..$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    $diff += "--- /dev/null"
    $diff += "+++ b/SECURITY_FIXES_PLAN"
    $diff += "@@ -0,0 +1,$($Plan.changes.Count) @@"
    
    foreach ($change in $Plan.changes) {
        $diff += "+$change"
    }
    
    $diff += ""
    $diff += "diff --git a/SECURITY_TESTS b/SECURITY_TESTS"
    $diff += "new file mode 100644"
    $diff += "index 0000000..$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    $diff += "--- /dev/null"
    $diff += "+++ b/SECURITY_TESTS"
    $diff += "@@ -0,0 +1,$($Plan.tests_to_run.Count) @@"
    
    foreach ($test in $Plan.tests_to_run) {
        $diff += "+$test"
    }
    
    return $diff -join "`n"
}

# Main execution
Write-Log "Starting security fixes planner"

$audit = Get-AuditResults -AuditPath $Audit
if (-not $audit) {
    Write-Log "No valid audit found, returning NOOP"
    Write-Output "NOOP"
    exit 0
}

# Check if security fixes are needed
if ($audit.critical_issues -eq 0 -and $audit.high_issues -eq 0 -and $audit.overall_compliance_score -ge 85) {
    Write-Log "Security compliance is good (score: $($audit.overall_compliance_score)%), returning NOOP"
    Write-Output "NOOP"
    exit 0
}

# Plan security fixes
$plan = Plan-SecurityFixes -Audit $audit

# Save the plan
$plan | ConvertTo-Json -Depth 3 | Set-Content $OutputPath
Write-Log "Security fixes plan saved to: $OutputPath"

# Generate unified diff for AI Foreman
$unifiedDiff = Generate-SecurityDiff -Plan $plan
Write-Output $unifiedDiff

Write-Log "Security fixes planner completed"
