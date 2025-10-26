# Cursor Chat Changes Planner - AI Foreman Planner Script
# Plans changes based on Cursor chat requests

param(
    [Parameter(Mandatory=$true)]
    [string]$Request,

    [string]$OutputPath = ".ai/state/cursor-plan.json"
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Get-RequestDetails {
    param([string]$RequestPath)

    if (-not (Test-Path $RequestPath)) {
        Write-Log "Request file not found: $RequestPath"
        return $null
    }

    try {
        $request = Get-Content $RequestPath | ConvertFrom-Json
        Write-Log "Processing request: $($request.type) - $($request.description)"
        return $request
    }
    catch {
        Write-Log "Error reading request: $($_.Exception.Message)"
        return $null
    }
}

function Plan-CodeChanges {
    param($Request)

    $plan = @{
        type = "code_changes"
        description = $Request.description
        changes = @()
        files_to_modify = @()
        tests_to_run = @()
        priority = $Request.priority
    }

    switch ($Request.type.ToLower()) {
        "add_feature" {
            $plan.changes += "Add new feature: $($Request.description)"
            $plan.files_to_modify += "vendors/", "tests/", "docs/"
            $plan.tests_to_run += "pwsh ./tests/test-vendor-integration.ps1"
        }
        "fix_bug" {
            $plan.changes += "Fix bug: $($Request.description)"
            $plan.files_to_modify += $Request.files
            $plan.tests_to_run += "pwsh ./tests/run-all-tests.ps1"
        }
        "improve_scraping" {
            $plan.changes += "Improve scraping accuracy: $($Request.description)"
            $plan.files_to_modify += "vendors/*Vendor.ps1"
            $plan.tests_to_run += "pwsh ./tests/test-playwright-functions.ps1"
        }
        "security_fix" {
            $plan.changes += "Security improvement: $($Request.description)"
            $plan.files_to_modify += "vendors/", "ui/", "tests/"
            $plan.tests_to_run += "pwsh -Command 'Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error'"
        }
        "documentation" {
            $plan.changes += "Update documentation: $($Request.description)"
            $plan.files_to_modify += "docs/", "README.md"
            $plan.tests_to_run += "pwsh ./tests/VERIFY_PROJECT_STRUCTURE.ps1"
        }
        default {
            $plan.changes += "General improvement: $($Request.description)"
            $plan.files_to_modify += $Request.files
            $plan.tests_to_run += "pwsh ./tests/run-all-tests.ps1"
        }
    }

    return $plan
}

function Plan-VendorModuleChanges {
    param($Request)

    $plan = @{
        type = "vendor_module_improvements"
        description = $Request.description
        changes = @()
        files_to_modify = @()
        tests_to_run = @()
        priority = $Request.priority
    }

    # Analyze vendor modules for improvements
    $vendorFiles = Get-ChildItem "vendors/*Vendor.ps1" -ErrorAction SilentlyContinue

    foreach ($file in $vendorFiles) {
        $content = Get-Content $file.FullName -Raw
        $plan.files_to_modify += $file.FullName

        # Check for common improvement opportunities
        if ($content -notmatch "try\s*\{") {
            $plan.changes += "Add error handling to $($file.Name)"
        }

        if ($content -notmatch "Write-Verbose|Write-Debug") {
            $plan.changes += "Add logging to $($file.Name)"
        }

        if ($content -notmatch "ValidateNotNullOrEmpty") {
            $plan.changes += "Add input validation to $($file.Name)"
        }
    }

    $plan.tests_to_run += "pwsh ./tests/test-vendor-integration.ps1"
    $plan.tests_to_run += "pwsh ./tests/test-playwright-functions.ps1"

    return $plan
}

function Plan-SecurityImprovements {
    param($Request)

    $plan = @{
        type = "security_compliance"
        description = $Request.description
        changes = @()
        files_to_modify = @()
        tests_to_run = @()
        priority = $Request.priority
    }

    # Security-focused improvements
    $plan.changes += "Implement NIST security guidelines compliance"
    $plan.changes += "Add input validation and sanitization"
    $plan.changes += "Improve error handling without information disclosure"
    $plan.changes += "Add comprehensive logging for audit trails"

    $plan.files_to_modify += "vendors/", "ui/", "tests/"
    $plan.tests_to_run += "pwsh -Command 'Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error'"
    $plan.tests_to_run += "pwsh ./tests/test-security-compliance.ps1"

    return $plan
}

function Generate-UnifiedDiff {
    param($Plan)

    $diff = @()
    $diff += "diff --git a/AI_FOREMAN_PLAN b/AI_FOREMAN_PLAN"
    $diff += "new file mode 100644"
    $diff += "index 0000000..$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    $diff += "--- /dev/null"
    $diff += "+++ b/AI_FOREMAN_PLAN"
    $diff += "@@ -0,0 +1,$($Plan.changes.Count) @@"

    foreach ($change in $Plan.changes) {
        $diff += "+$change"
    }

    $diff += ""
    $diff += "diff --git a/AI_FOREMAN_TESTS b/AI_FOREMAN_TESTS"
    $diff += "new file mode 100644"
    $diff += "index 0000000..$(Get-Random -Minimum 1000000 -Maximum 9999999)"
    $diff += "--- /dev/null"
    $diff += "+++ b/AI_FOREMAN_TESTS"
    $diff += "@@ -0,0 +1,$($Plan.tests_to_run.Count) @@"

    foreach ($test in $Plan.tests_to_run) {
        $diff += "+$test"
    }

    return $diff -join "`n"
}

# Main execution
Write-Log "Starting Cursor chat changes planner"

$request = Get-RequestDetails -RequestPath $Request
if (-not $request) {
    Write-Log "No valid request found, returning NOOP"
    Write-Output "NOOP"
    exit 0
}

# Plan changes based on request type
$plan = switch ($request.type.ToLower()) {
    "vendor_module" { Plan-VendorModuleChanges -Request $request }
    "security" { Plan-SecurityImprovements -Request $request }
    default { Plan-CodeChanges -Request $request }
}

# Save the plan
$plan | ConvertTo-Json -Depth 3 | Set-Content $OutputPath
Write-Log "Plan saved to: $OutputPath"

# Generate unified diff for AI Foreman
$unifiedDiff = Generate-UnifiedDiff -Plan $plan
Write-Output $unifiedDiff

Write-Log "Cursor chat changes planner completed"
