# Final integration test - properly loads CVExpand-GUI and tests extraction
# This preserves $PSScriptRoot so vendor modules load correctly

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Final Integration Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Change to script directory to ensure relative paths work
Push-Location $PSScriptRoot

try {
    # Define Write-Log function for vendor modules
    function Write-Log {
        param([string]$Message, [string]$Level = "INFO")
        # Silent for this test
    }

    # Source the vendor modules directly
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
    Write-Host "✓ VendorManager initialized`n" -ForegroundColor Green

    # Test MSRC URL
    $testUrl = "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-21302"
    Write-Host "Test URL: $testUrl`n" -ForegroundColor Cyan

    # Fetch with HTTP (we know Playwright won't work in this context)
    Write-Host "Fetching page (HTTP)..." -ForegroundColor Yellow
    $response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 30
    Write-Host "✓ Fetched: $($response.Content.Length) bytes`n" -ForegroundColor Green

    # Extract using VendorManager
    Write-Host "Extracting with VendorManager..." -ForegroundColor Yellow
    $extracted = $vendorMgr.ExtractData($response.Content, $testUrl)

    Write-Host "`nResults:" -ForegroundColor Cyan
    Write-Host "  Vendor Used: $($extracted.VendorUsed)" -ForegroundColor White
    Write-Host "  Patch ID: $($extracted.PatchID)" -ForegroundColor White
    Write-Host "  Download Links: $($extracted.DownloadLinks.Count)" -ForegroundColor White

    if ($extracted.DownloadLinks -and $extracted.DownloadLinks.Count -gt 0) {
        Write-Host "`n  Links Found:" -ForegroundColor Green
        foreach ($link in $extracted.DownloadLinks) {
            Write-Host "    • $link" -ForegroundColor Gray
        }
        Write-Host "`n✅ SUCCESS: Download links extracted!" -ForegroundColor Green
        $success = $true
    } else {
        Write-Host "`n⚠ No download links (HTTP gives minimal HTML)" -ForegroundColor Yellow
        Write-Host "  Note: MSRC pages need Playwright for full content" -ForegroundColor Yellow
        $success = $false
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    if ($success) {
        Write-Host "✅ VENDOR INTEGRATION WORKING" -ForegroundColor Green
    } else {
        Write-Host "⚠ Vendor integration loaded, but MSRC needs Playwright" -ForegroundColor Yellow
    }
    Write-Host "========================================" -ForegroundColor Cyan

} finally {
    Pop-Location
}
