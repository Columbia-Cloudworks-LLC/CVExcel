<#
.SYNOPSIS
    Tests Playwright integration for CVScraper.

.DESCRIPTION
    Comprehensive test suite for Playwright browser automation integration.
    Tests installation, initialization, navigation, and data extraction.

.PARAMETER TestUrls
    Array of URLs to test. Defaults to common MSRC and Microsoft URLs.

.PARAMETER IncludeScreenshots
    Take screenshots during tests for debugging.

.EXAMPLE
    .\Test-PlaywrightIntegration.ps1

.EXAMPLE
    .\Test-PlaywrightIntegration.ps1 -IncludeScreenshots
#>

[CmdletBinding()]
param(
    [string[]]$TestUrls = @(
        "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-21302",
        "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2023-28290",
        "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/microsoft-recommended-driver-block-rules"
    ),
    [switch]$IncludeScreenshots
)

$ErrorActionPreference = "Continue"

# Import required modules
. "$PSScriptRoot\PlaywrightWrapper.ps1"
. "$PSScriptRoot\vendors\BaseVendor.ps1"
. "$PSScriptRoot\vendors\MicrosoftVendor.ps1"

# Initialize logging
$Global:LogFile = Join-Path $PSScriptRoot "out\playwright_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logDir = Split-Path $Global:LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    Add-Content -Path $Global:LogFile -Value $logEntry -Encoding UTF8

    $color = switch ($Level) {
        "INFO"    { "White" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        "DEBUG"   { "Gray" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }

    Write-Host $logEntry -ForegroundColor $color
}

function Test-PlaywrightInstallation {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Test 1: Playwright Installation Check                       ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    $packageDir = Join-Path $PSScriptRoot "packages"

    if (-not (Test-Path $packageDir)) {
        Write-Log -Message "❌ Packages directory not found: $packageDir" -Level "ERROR"
        return $false
    }

    Write-Log -Message "✓ Packages directory exists" -Level "SUCCESS"

    $playwrightDll = Get-ChildItem -Path $packageDir -Recurse -Filter "Microsoft.Playwright.dll" -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $playwrightDll) {
        Write-Log -Message "❌ Playwright DLL not found" -Level "ERROR"
        Write-Log -Message "Run: .\Install-Playwright.ps1" -Level "INFO"
        return $false
    }

    Write-Log -Message "✓ Playwright DLL found: $($playwrightDll.FullName)" -Level "SUCCESS"

    try {
        Add-Type -Path $playwrightDll.FullName
        Write-Log -Message "✓ Playwright assembly loaded successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log -Message "❌ Failed to load Playwright assembly: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Test-PlaywrightInitialization {
    Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Test 2: Playwright Browser Initialization                   ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    $playwright = $null
    try {
        $playwright = [PlaywrightWrapper]::new("chromium")
        Write-Log -Message "✓ PlaywrightWrapper instance created" -Level "SUCCESS"

        $initResult = $playwright.Initialize()

        if ($initResult) {
            Write-Log -Message "✓ Playwright browser initialized successfully" -Level "SUCCESS"
            return $true
        } else {
            Write-Log -Message "❌ Playwright initialization failed" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-Log -Message "❌ Exception during initialization: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    finally {
        if ($playwright) {
            $playwright.Dispose()
            Write-Log -Message "✓ Playwright resources disposed" -Level "DEBUG"
        }
    }
}

function Test-PlaywrightNavigation {
    param(
        [string]$Url,
        [switch]$TakeScreenshot
    )

    Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Test 3: Page Navigation                                     ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Log -Message "Testing URL: $Url" -Level "INFO"

    $playwright = $null
    try {
        $playwright = [PlaywrightWrapper]::new("chromium")

        if (-not $playwright.Initialize()) {
            throw "Failed to initialize browser"
        }

        $startTime = Get-Date
        $result = $playwright.NavigateToPage($Url, 8)
        $duration = (Get-Date) - $startTime

        if ($result.Success) {
            Write-Log -Message "✓ Navigation successful" -Level "SUCCESS"
            Write-Log -Message "  Content size: $($result.Size) bytes" -Level "INFO"
            Write-Log -Message "  Duration: $($duration.TotalSeconds.ToString('F2')) seconds" -Level "INFO"
            Write-Log -Message "  Status code: $($result.StatusCode)" -Level "INFO"

            # Check for MSRC-specific content
            if ($result.Content -match '(CVE|vulnerability|security|update|patch|KB)') {
                Write-Log -Message "✓ MSRC-specific content detected" -Level "SUCCESS"
            } else {
                Write-Log -Message "⚠ No MSRC-specific content detected" -Level "WARNING"
            }

            # Take screenshot if requested
            if ($TakeScreenshot) {
                $screenshotPath = Join-Path $PSScriptRoot "out\screenshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
                if ($playwright.TakeScreenshot($screenshotPath)) {
                    Write-Log -Message "✓ Screenshot saved: $screenshotPath" -Level "SUCCESS"
                }
            }

            return @{
                Success = $true
                Size = $result.Size
                Duration = $duration.TotalSeconds
                Content = $result.Content
            }
        } else {
            Write-Log -Message "❌ Navigation failed: $($result.Error)" -Level "ERROR"
            return @{
                Success = $false
                Error = $result.Error
            }
        }
    }
    catch {
        Write-Log -Message "❌ Exception during navigation: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
    finally {
        if ($playwright) {
            $playwright.Dispose()
        }
    }
}

function Test-DataExtraction {
    param(
        [string]$Url,
        [string]$Content
    )

    Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Test 4: Data Extraction                                     ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Log -Message "Extracting data from: $Url" -Level "INFO"

    try {
        $vendor = [MicrosoftVendor]::new()
        $extractedData = $vendor.ExtractData($Content, $Url)

        Write-Log -Message "Extraction Results:" -Level "INFO"
        Write-Log -Message "  PatchID: $($extractedData.PatchID)" -Level "INFO"
        Write-Log -Message "  DownloadLinks: $($extractedData.DownloadLinks.Count)" -Level "INFO"
        Write-Log -Message "  AffectedVersions: $($extractedData.AffectedVersions)" -Level "INFO"
        Write-Log -Message "  Remediation: $(if ($extractedData.Remediation) { $extractedData.Remediation.Substring(0, [Math]::Min(50, $extractedData.Remediation.Length)) + '...' } else { 'None' })" -Level "INFO"

        $hasData = $extractedData.PatchID -or $extractedData.DownloadLinks.Count -gt 0

        if ($hasData) {
            Write-Log -Message "✓ Data extraction successful" -Level "SUCCESS"
            return $true
        } else {
            Write-Log -Message "⚠ No data extracted (may be normal for some URLs)" -Level "WARNING"
            return $false
        }
    }
    catch {
        Write-Log -Message "❌ Data extraction failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# ==================== Main Test Execution ====================

Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║         Playwright Integration Test Suite                    ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Log -Message "Starting Playwright integration tests" -Level "INFO"
Write-Log -Message "Log file: $Global:LogFile" -Level "INFO"

$testResults = @{
    Installation = $false
    Initialization = $false
    Navigation = @()
    DataExtraction = @()
}

# Test 1: Installation
$testResults.Installation = Test-PlaywrightInstallation

if (-not $testResults.Installation) {
    Write-Host "`n❌ Playwright not installed. Run .\Install-Playwright.ps1 first." -ForegroundColor Red
    exit 1
}

# Test 2: Initialization
$testResults.Initialization = Test-PlaywrightInitialization

if (-not $testResults.Initialization) {
    Write-Host "`n❌ Playwright initialization failed. Check the log for details." -ForegroundColor Red
    exit 1
}

# Test 3 & 4: Navigation and Data Extraction
foreach ($url in $TestUrls) {
    $navResult = Test-PlaywrightNavigation -Url $url -TakeScreenshot:$IncludeScreenshots
    $testResults.Navigation += $navResult

    if ($navResult.Success) {
        $extractResult = Test-DataExtraction -Url $url -Content $navResult.Content
        $testResults.DataExtraction += $extractResult
    } else {
        $testResults.DataExtraction += $false
    }

    Start-Sleep -Seconds 2  # Brief pause between tests
}

# ==================== Test Summary ====================

Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Test Summary                                                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$successCount = ($testResults.Navigation | Where-Object { $_.Success }).Count
$totalTests = $testResults.Navigation.Count

Write-Host "`nInstallation: $(if ($testResults.Installation) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($testResults.Installation) { 'Green' } else { 'Red' })
Write-Host "Initialization: $(if ($testResults.Initialization) { '✓ PASS' } else { '❌ FAIL' })" -ForegroundColor $(if ($testResults.Initialization) { 'Green' } else { 'Red' })
Write-Host "Navigation: $successCount/$totalTests passed" -ForegroundColor $(if ($successCount -eq $totalTests) { 'Green' } else { 'Yellow' })

$extractionSuccess = ($testResults.DataExtraction | Where-Object { $_ }).Count
Write-Host "Data Extraction: $extractionSuccess/$totalTests successful" -ForegroundColor $(if ($extractionSuccess -gt 0) { 'Green' } else { 'Yellow' })

if ($successCount -eq $totalTests -and $testResults.Installation -and $testResults.Initialization) {
    Write-Host "`n✅ All tests passed!" -ForegroundColor Green
    Write-Log -Message "All tests passed successfully" -Level "SUCCESS"
    exit 0
} else {
    Write-Host "`n⚠ Some tests failed. Check the log for details: $Global:LogFile" -ForegroundColor Yellow
    Write-Log -Message "Some tests failed" -Level "WARNING"
    exit 1
}
