# Test CVExpand-GUI scraping with Playwright for MSRC pages
# This tests the actual scraping pipeline including vendor modules

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing CVExpand-GUI MSRC Scraping" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import required assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, System.Web

# Import vendor modules
Write-Host "Loading vendor modules..." -ForegroundColor Yellow
$vendorPath = Join-Path $PSScriptRoot "..\vendors"
$vendorFiles = @("BaseVendor.ps1", "GenericVendor.ps1", "GitHubVendor.ps1", "MicrosoftVendor.ps1", "IBMVendor.ps1", "ZDIVendor.ps1", "VendorManager.ps1")

foreach ($file in $vendorFiles) {
    $filePath = Join-Path $vendorPath $file
    if (Test-Path $filePath) {
        . $filePath
    } else {
        Write-Host "⚠ Warning: $file not found at $filePath" -ForegroundColor Yellow
    }
}
Write-Host "✓ Vendor modules loaded" -ForegroundColor Green

# Import Playwright wrapper
Write-Host "Loading Playwright wrapper..." -ForegroundColor Yellow
$playwrightPath = Join-Path $PSScriptRoot "..\ui\PlaywrightWrapper.ps1"
if (Test-Path $playwrightPath) {
    . $playwrightPath
    Write-Host "✓ Playwright wrapper loaded`n" -ForegroundColor Green
} else {
    Write-Host "⚠ Warning: PlaywrightWrapper.ps1 not found at $playwrightPath" -ForegroundColor Yellow
    Write-Host "  Continuing without Playwright support`n" -ForegroundColor Yellow
}

# Initialize global variables
$outDir = Join-Path $PSScriptRoot "..\out"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$Global:LogFile = Join-Path $outDir "test_scraping_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Global:VendorManager = [VendorManager]::new()

# Simple logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $Global:LogFile -Value $logMessage -ErrorAction SilentlyContinue

    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "  $Message" -ForegroundColor $color
}

Write-Log "Starting MSRC scraping test" -Level "INFO"

# Test URL
$testUrl = "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-21302"
Write-Host "Testing URL: $testUrl`n" -ForegroundColor Cyan

# Try Playwright first
Write-Host "Attempting Playwright rendering..." -ForegroundColor Yellow
try {
    $playwrightResult = Invoke-PlaywrightBrowser -Url $testUrl -WaitForSelector "body" -Timeout 30000

    if ($playwrightResult.Success) {
        Write-Log "✓ Playwright rendered page: $($playwrightResult.Content.Length) bytes" -Level "SUCCESS"
        $htmlContent = $playwrightResult.Content
        $method = "Playwright"
    } else {
        Write-Log "Playwright failed: $($playwrightResult.Error)" -Level "WARNING"
        Write-Host "Falling back to HTTP..." -ForegroundColor Yellow

        $httpResponse = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 30
        $htmlContent = $httpResponse.Content
        $method = "HTTP"
        Write-Log "HTTP fetched: $($htmlContent.Length) bytes" -Level "INFO"
    }
}
catch {
    Write-Log "Error during fetch: $($_.Exception.Message)" -Level "ERROR"
    $htmlContent = $null
}

if ($htmlContent) {
    Write-Host "`nExtracting data with vendor modules..." -ForegroundColor Yellow

    # Use VendorManager to extract
    $extracted = $Global:VendorManager.ExtractData($htmlContent, $testUrl)

    Write-Host "`nExtraction Results:" -ForegroundColor Cyan
    Write-Host "  Method: $method" -ForegroundColor White
    Write-Host "  Vendor Used: $($extracted.VendorUsed)" -ForegroundColor White
    Write-Host "  HTML Size: $($htmlContent.Length) bytes" -ForegroundColor White
    Write-Host "  Patch ID: $($extracted.PatchID)" -ForegroundColor White
    Write-Host "  Download Links: $($extracted.DownloadLinks.Count)" -ForegroundColor White

    # Check for KB articles in HTML
    $kbMatches = [regex]::Matches($htmlContent, 'KB(\d{6,7})')
    Write-Host "  KB Articles in HTML: $($kbMatches.Count)" -ForegroundColor White

    if ($extracted.DownloadLinks.Count -gt 0) {
        Write-Host "`n  Download Links Found:" -ForegroundColor Green
        foreach ($link in $extracted.DownloadLinks) {
            Write-Host "    • $link" -ForegroundColor Gray
        }
        Write-Host "`n✓ SUCCESS: Download links extracted!" -ForegroundColor Green
    } else {
        Write-Host "`n✗ FAILED: No download links found" -ForegroundColor Red

        # Show sample of HTML for debugging
        Write-Host "`nHTML Sample (first 500 chars):" -ForegroundColor Yellow
        Write-Host $htmlContent.Substring(0, [Math]::Min(500, $htmlContent.Length)) -ForegroundColor DarkGray
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Complete - Log: $($Global:LogFile)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
