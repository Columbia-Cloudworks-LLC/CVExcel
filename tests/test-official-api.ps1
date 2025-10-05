# Test the enhanced MicrosoftVendor with official MSRC PowerShell module
# This should extract KB articles without needing Playwright

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing Official MSRC API Integration" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Define Write-Log
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "INFO" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

# Import vendor modules
Write-Host "Loading vendor modules..." -ForegroundColor Yellow
. ".\vendors\BaseVendor.ps1"
. ".\vendors\GenericVendor.ps1"
. ".\vendors\GitHubVendor.ps1"
. ".\vendors\MicrosoftVendor.ps1"
. ".\vendors\IBMVendor.ps1"
. ".\vendors\ZDIVendor.ps1"
. ".\vendors\VendorManager.ps1"
Write-Host "✓ Vendor modules loaded`n" -ForegroundColor Green

# Initialize VendorManager
$vendorMgr = [VendorManager]::new()

# Test CVE
$testUrl = "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-21302"
Write-Host "Test URL: $testUrl`n" -ForegroundColor Cyan

# Get HTTP content (minimal HTML)
Write-Host "Fetching page (HTTP - expect minimal HTML)..." -ForegroundColor Yellow
$response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 30
Write-Host "✓ Fetched: $($response.Content.Length) bytes`n" -ForegroundColor Gray

# Extract using enhanced VendorManager
Write-Host "Extracting with enhanced MicrosoftVendor (using official API)..." -ForegroundColor Yellow
$extracted = $vendorMgr.ExtractData($response.Content, $testUrl)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Vendor Used: $($extracted.VendorUsed)" -ForegroundColor White
Write-Host "Patch ID: $($extracted.PatchID)" -ForegroundColor White
Write-Host "Download Links: $($extracted.DownloadLinks.Count)" -ForegroundColor White

if ($extracted.DownloadLinks -and $extracted.DownloadLinks.Count -gt 0) {
    Write-Host "`nDownload Links:" -ForegroundColor Green
    foreach ($link in $extracted.DownloadLinks) {
        Write-Host "  • $link" -ForegroundColor Gray
    }
    Write-Host "`n✅ SUCCESS! Official API extracted KB articles!" -ForegroundColor Green
    Write-Host "   No Playwright needed! 🎉" -ForegroundColor Green
} else {
    Write-Host "`n⚠ No links extracted" -ForegroundColor Yellow
}

Write-Host "`n========================================"  -ForegroundColor Cyan
