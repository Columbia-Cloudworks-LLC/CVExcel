# run-all-tests.ps1 - Comprehensive test runner for CVExcel project
# This script runs all tests in the correct order and provides detailed reporting

param(
    [switch]$Verbose,
    [switch]$SkipSelenium,
    [switch]$SkipVendorTests,
    [string]$TestFilter = "*"
)

# Set execution policy for current session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Colors for output
$Colors = @{
    Header = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "White"
    Debug = "Gray"
}

# Test results tracking
$Global:TestResults = @{
    Total = 0
    Passed = 0
    Failed = 0
    Skipped = 0
    StartTime = Get-Date
    Results = @()
}

function Write-TestHeader {
    param([string]$TestName)

    Write-Host "`n" -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor $Colors.Header
    Write-Host "║  $($TestName.PadRight(63)) ║" -ForegroundColor $Colors.Header
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor $Colors.Header
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message = ""
    )

    $Global:TestResults.Total++

    switch ($Status) {
        "PASSED" {
            Write-Host "✓ $TestName" -ForegroundColor $Colors.Success
            $Global:TestResults.Passed++
            $Global:TestResults.Results += @{
                Name = $TestName
                Status = "PASSED"
                Message = $Message
            }
        }
        "FAILED" {
            Write-Host "✗ $TestName" -ForegroundColor $Colors.Error
            if ($Message) { Write-Host "  $Message" -ForegroundColor $Colors.Error }
            $Global:TestResults.Failed++
            $Global:TestResults.Results += @{
                Name = $TestName
                Status = "FAILED"
                Message = $Message
            }
        }
        "SKIPPED" {
            Write-Host "⚠ $TestName (SKIPPED)" -ForegroundColor $Colors.Warning
            if ($Message) { Write-Host "  $Message" -ForegroundColor $Colors.Warning }
            $Global:TestResults.Skipped++
            $Global:TestResults.Results += @{
                Name = $TestName
                Status = "SKIPPED"
                Message = $Message
            }
        }
    }
}

function Invoke-Test {
    param(
        [string]$TestName,
        [string]$ScriptPath,
        [string]$Description = ""
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-TestResult -TestName $TestName -Status "FAILED" -Message "Test script not found: $ScriptPath"
        return
    }

    try {
        Write-Host "Running: $TestName" -ForegroundColor $Colors.Info
        if ($Description) {
            Write-Host "Description: $Description" -ForegroundColor $Colors.Debug
        }

        $startTime = Get-Date
        $output = & $ScriptPath 2>&1
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        if ($LASTEXITCODE -eq 0) {
            Write-TestResult -TestName $TestName -Status "PASSED" -Message "Completed in $([Math]::Round($duration, 2))s"
        } else {
            Write-TestResult -TestName $TestName -Status "FAILED" -Message "Exit code: $LASTEXITCODE"
            if ($Verbose -and $output) {
                Write-Host "Output:" -ForegroundColor $Colors.Debug
                $output | ForEach-Object { Write-Host "  $_" -ForegroundColor $Colors.Debug }
            }
        }
    }
    catch {
        Write-TestResult -TestName $TestName -Status "FAILED" -Message $_.Exception.Message
        if ($Verbose) {
            Write-Host "Exception:" -ForegroundColor $Colors.Debug
            Write-Host "  $_" -ForegroundColor $Colors.Debug
        }
    }
}

# Main test execution
Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor $Colors.Header
Write-Host "║  CVExcel Project Test Suite                                  ║" -ForegroundColor $Colors.Header
Write-Host "║  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                      ║" -ForegroundColor $Colors.Header
Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor $Colors.Header

# Test 1: Environment Setup
Write-TestHeader "Environment Setup Tests"

Invoke-Test -TestName "PowerShell Version Check" -ScriptPath ".\tests\test-powershell-version.ps1" -Description "Verify PowerShell version compatibility"

Invoke-Test -TestName "Required Modules Check" -ScriptPath ".\tests\test-required-modules.ps1" -Description "Check for required PowerShell modules"

# Test 2: Vendor Module Tests
if (-not $SkipVendorTests) {
    Write-TestHeader "Vendor Module Tests"

    Invoke-Test -TestName "Vendor Module Loading" -ScriptPath ".\tests\SIMPLE_VENDOR_TEST.ps1" -Description "Test vendor module loading and basic functionality"

    if ($TestFilter -eq "*" -or $TestFilter -like "*vendor*") {
        Invoke-Test -TestName "Comprehensive Vendor Tests" -ScriptPath ".\tests\TEST_VENDOR_MODULES.ps1" -Description "Full vendor module functionality tests"
    }
}

# Test 3: Core Functionality Tests
Write-TestHeader "Core Functionality Tests"

Invoke-Test -TestName "CVScraper Basic Tests" -ScriptPath ".\tests\SIMPLE_TEST.ps1" -Description "Basic CVScraper functionality tests"

if ($TestFilter -eq "*" -or $TestFilter -like "*scraper*") {
    Invoke-Test -TestName "CVScraper Improvements" -ScriptPath ".\tests\TEST_CVSCRAPE_IMPROVEMENTS.ps1" -Description "Test CVScraper enhancements"
}

# Test 4: Selenium Tests
if (-not $SkipSelenium) {
    Write-TestHeader "Selenium Integration Tests"

    if ($TestFilter -eq "*" -or $TestFilter -like "*selenium*") {
        Invoke-Test -TestName "Selenium Fixes" -ScriptPath ".\tests\TEST_SELENIUM_FIXES.ps1" -Description "Test Selenium integration and fixes"
    }
}

# Test 5: Auto-Install Tests
Write-TestHeader "Auto-Install Feature Tests"

if ($TestFilter -eq "*" -or $TestFilter -like "*install*") {
    Invoke-Test -TestName "Auto-Install Features" -ScriptPath ".\tests\TEST_AUTO_INSTALL.ps1" -Description "Test automatic module installation"
}

# Test 6: Integration Tests
Write-TestHeader "Integration Tests"

Invoke-Test -TestName "CVExcel Integration" -ScriptPath ".\tests\test-cvexcel-integration.ps1" -Description "Test CVExcel main script integration"

# Generate Test Report
$endTime = Get-Date
$totalDuration = ($endTime - $Global:TestResults.StartTime).TotalSeconds

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor $Colors.Header
Write-Host "║  Test Suite Results                                        ║" -ForegroundColor $Colors.Header
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor $Colors.Header

Write-Host "`nSummary:" -ForegroundColor $Colors.Info
Write-Host "  Total Tests: $($Global:TestResults.Total)" -ForegroundColor $Colors.Info
Write-Host "  Passed: $($Global:TestResults.Passed)" -ForegroundColor $Colors.Success
Write-Host "  Failed: $($Global:TestResults.Failed)" -ForegroundColor $Colors.Error
Write-Host "  Skipped: $($Global:TestResults.Skipped)" -ForegroundColor $Colors.Warning
Write-Host "  Duration: $([Math]::Round($totalDuration, 2)) seconds" -ForegroundColor $Colors.Info

if ($Global:TestResults.Failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor $Colors.Error
    $Global:TestResults.Results | Where-Object { $_.Status -eq "FAILED" } | ForEach-Object {
        Write-Host "  ✗ $($_.Name)" -ForegroundColor $Colors.Error
        if ($_.Message) {
            Write-Host "    $($_.Message)" -ForegroundColor $Colors.Error
        }
    }
}

if ($Global:TestResults.Skipped -gt 0) {
    Write-Host "`nSkipped Tests:" -ForegroundColor $Colors.Warning
    $Global:TestResults.Results | Where-Object { $_.Status -eq "SKIPPED" } | ForEach-Object {
        Write-Host "  ⚠ $($_.Name)" -ForegroundColor $Colors.Warning
        if ($_.Message) {
            Write-Host "    $($_.Message)" -ForegroundColor $Colors.Warning
        }
    }
}

# Exit with appropriate code
if ($Global:TestResults.Failed -gt 0) {
    Write-Host "`nTest suite completed with failures." -ForegroundColor $Colors.Error
    exit 1
} else {
    Write-Host "`nAll tests passed successfully!" -ForegroundColor $Colors.Success
    exit 0
}
