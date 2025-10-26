# Vendor Module Analysis - AI Foreman Check Script
# Analyzes vendor modules for improvement opportunities

param(
    [string]$OutputPath = ".ai/state/vendor-analysis.json"
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Analyze-VendorModule {
    param(
        [string]$FilePath,
        [string]$ModuleName
    )

    $analysis = @{
        module = $ModuleName
        file = $FilePath
        issues = @()
        improvements = @()
        score = 0
    }

    try {
        $content = Get-Content $FilePath -Raw
        $lines = $content -split "`n"

        # Check for error handling
        if ($content -notmatch "try\s*\{") {
            $analysis.issues += "Missing try-catch error handling"
            $analysis.improvements += "Add comprehensive error handling with try-catch blocks"
        }

        # Check for logging
        if ($content -notmatch "Write-Verbose|Write-Debug|Write-Log") {
            $analysis.issues += "Missing logging statements"
            $analysis.improvements += "Add verbose logging for debugging and monitoring"
        }

        # Check for input validation
        if ($content -notmatch "ValidateNotNullOrEmpty|ValidatePattern|ValidateRange") {
            $analysis.issues += "Missing input validation"
            $analysis.improvements += "Add parameter validation and input sanitization"
        }

        # Check for security practices
        if ($content -notmatch "SecureString|ConvertTo-SecureString") {
            if ($content -match "password|secret|key|token") {
                $analysis.issues += "Potential security issue with credential handling"
                $analysis.improvements += "Use SecureString for sensitive data handling"
            }
        }

        # Check for rate limiting
        if ($content -notmatch "Start-Sleep|Wait-|rate.*limit") {
            if ($content -match "Invoke-WebRequest|Invoke-RestMethod") {
                $analysis.issues += "Missing rate limiting for web requests"
                $analysis.improvements += "Add rate limiting and retry logic for API calls"
            }
        }

        # Check for Playwright integration
        if ($content -match "Invoke-WebRequest" -and $content -notmatch "Playwright") {
            $analysis.issues += "Using basic web requests instead of Playwright"
            $analysis.improvements += "Consider Playwright for JavaScript-heavy pages"
        }

        # Calculate improvement score
        $totalChecks = 6
        $passedChecks = $totalChecks - $analysis.issues.Count
        $analysis.score = [math]::Round(($passedChecks / $totalChecks) * 100, 2)

        Write-Log "Analyzed $ModuleName - Score: $($analysis.score)% - Issues: $($analysis.issues.Count)"

        return $analysis
    }
    catch {
        Write-Log "Error analyzing $ModuleName : $($_.Exception.Message)"
        $analysis.issues += "Analysis error: $($_.Exception.Message)"
        return $analysis
    }
}

function Get-VendorModules {
    $vendorFiles = Get-ChildItem "vendors/*Vendor.ps1" -ErrorAction SilentlyContinue
    $modules = @()

    foreach ($file in $vendorFiles) {
        $moduleName = $file.BaseName
        $modules += @{
            name = $moduleName
            path = $file.FullName
            size = $file.Length
            lastModified = $file.LastWriteTime
        }
    }

    return $modules
}

# Main execution
Write-Log "Starting vendor module analysis"

$vendorModules = Get-VendorModules
$analysisResults = @{
    timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    total_modules = $vendorModules.Count
    modules = @()
    overall_score = 0
    recommendations = @()
}

$totalScore = 0

foreach ($module in $vendorModules) {
    $analysis = Analyze-VendorModule -FilePath $module.path -ModuleName $module.name
    $analysisResults.modules += $analysis
    $totalScore += $analysis.score
}

# Calculate overall score
if ($vendorModules.Count -gt 0) {
    $analysisResults.overall_score = [math]::Round($totalScore / $vendorModules.Count, 2)
}

# Generate recommendations
$commonIssues = $analysisResults.modules | ForEach-Object { $_.issues } | Group-Object | Sort-Object Count -Descending

foreach ($issue in $commonIssues) {
    if ($issue.Count -gt 1) {
        $analysisResults.recommendations += "Common issue: $($issue.Name) (affects $($issue.Count) modules)"
    }
}

# Save analysis results
$analysisResults | ConvertTo-Json -Depth 4 | Set-Content $OutputPath
Write-Log "Vendor module analysis completed - Overall score: $($analysisResults.overall_score)%"
Write-Log "Analysis saved to: $OutputPath"

# Output summary for AI Foreman
if ($analysisResults.overall_score -lt 70) {
    Write-Output "VENDOR_MODULES_NEED_IMPROVEMENT"
} else {
    Write-Output "VENDOR_MODULES_OK"
}
