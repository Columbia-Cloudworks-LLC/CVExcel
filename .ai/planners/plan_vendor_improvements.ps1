# Vendor Improvements Planner - AI Foreman Planner Script
# Plans improvements for vendor modules based on analysis

param(
    [Parameter(Mandatory=$true)]
    [string]$Analysis,

    [string]$OutputPath = ".ai/state/vendor-plan.json"
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Get-AnalysisResults {
    param([string]$AnalysisPath)

    if (-not (Test-Path $AnalysisPath)) {
        Write-Log "Analysis file not found: $AnalysisPath"
        return $null
    }

    try {
        $analysis = Get-Content $AnalysisPath | ConvertFrom-Json
        Write-Log "Processing analysis for $($analysis.total_modules) modules"
        return $analysis
    }
    catch {
        Write-Log "Error reading analysis: $($_.Exception.Message)"
        return $null
    }
}

function Plan-VendorModuleImprovements {
    param($Analysis)

    $plan = @{
        type = "vendor_module_improvements"
        description = "Improve vendor module code quality and functionality"
        changes = @()
        files_to_modify = @()
        tests_to_run = @()
        priority = "normal"
    }

    # Process each module's analysis
    foreach ($module in $Analysis.modules) {
        if ($module.score -lt 70) {
            $plan.files_to_modify += $module.file

            foreach ($improvement in $module.improvements) {
                $plan.changes += "Improve $($module.module): $improvement"
            }
        }
    }

    # Add common improvements based on analysis
    if ($Analysis.overall_score -lt 80) {
        $plan.changes += "Add comprehensive error handling to all vendor modules"
        $plan.changes += "Implement consistent logging across vendor modules"
        $plan.changes += "Add input validation and parameter checking"
        $plan.changes += "Improve security practices in vendor modules"
        $plan.changes += "Add rate limiting and retry logic for web requests"
    }

    # Add specific improvements based on common issues
    $commonIssues = $Analysis.modules | ForEach-Object { $_.issues } | Group-Object | Sort-Object Count -Descending

    foreach ($issue in $commonIssues) {
        if ($issue.Count -gt 1) {
            switch ($issue.Name) {
                "Missing try-catch error handling" {
                    $plan.changes += "Add try-catch blocks to all vendor modules for robust error handling"
                }
                "Missing logging statements" {
                    $plan.changes += "Implement verbose logging in all vendor modules for better debugging"
                }
                "Missing input validation" {
                    $plan.changes += "Add parameter validation using ValidateNotNullOrEmpty and ValidatePattern"
                }
                "Missing rate limiting for web requests" {
                    $plan.changes += "Implement rate limiting and retry logic for all web requests"
                }
                "Using basic web requests instead of Playwright" {
                    $plan.changes += "Consider upgrading to Playwright for JavaScript-heavy vendor pages"
                }
            }
        }
    }

    # Add tests
    $plan.tests_to_run += "pwsh ./tests/test-vendor-integration.ps1"
    $plan.tests_to_run += "pwsh ./tests/test-playwright-functions.ps1"
    $plan.tests_to_run += "pwsh -Command 'Get-ChildItem vendors/*.ps1 | ForEach-Object { Write-Host \"Testing $_\"; & $_ -Test }'"

    return $plan
}

function Generate-VendorModuleDiff {
    param($Plan)

    $diff = @()
    $diff += "diff --git a/VENDOR_IMPROVEMENTS_PLAN b/VENDOR_IMPROVEMENTS_PLAN"
    $diff += "new file mode 100644"
    $diff += "index 0000000..$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    $diff += "--- /dev/null"
    $diff += "+++ b/VENDOR_IMPROVEMENTS_PLAN"
    $diff += "@@ -0,0 +1,$($Plan.changes.Count) @@"

    foreach ($change in $Plan.changes) {
        $diff += "+$change"
    }

    $diff += ""
    $diff += "diff --git a/VENDOR_TESTS b/VENDOR_TESTS"
    $diff += "new file mode 100644"
    $diff += "index 0000000..$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    $diff += "--- /dev/null"
    $diff += "+++ b/VENDOR_TESTS"
    $diff += "@@ -0,0 +1,$($Plan.tests_to_run.Count) @@"

    foreach ($test in $Plan.tests_to_run) {
        $diff += "+$test"
    }

    return $diff -join "`n"
}

# Main execution
Write-Log "Starting vendor improvements planner"

$analysis = Get-AnalysisResults -AnalysisPath $Analysis
if (-not $analysis) {
    Write-Log "No valid analysis found, returning NOOP"
    Write-Output "NOOP"
    exit 0
}

# Check if improvements are needed
if ($analysis.overall_score -ge 85) {
    Write-Log "Vendor modules are in good condition (score: $($analysis.overall_score)%), returning NOOP"
    Write-Output "NOOP"
    exit 0
}

# Plan improvements
$plan = Plan-VendorModuleImprovements -Analysis $analysis

# Save the plan
$plan | ConvertTo-Json -Depth 3 | Set-Content $OutputPath
Write-Log "Vendor improvements plan saved to: $OutputPath"

# Generate unified diff for AI Foreman
$unifiedDiff = Generate-VendorModuleDiff -Plan $plan
Write-Output $unifiedDiff

Write-Log "Vendor improvements planner completed"
