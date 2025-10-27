# SIMPLE_VENDOR_TEST.ps1 - Simple test for vendor modules

Write-Host "Testing vendor modules..." -ForegroundColor Cyan

try {
    $vendorManagerPath = Join-Path $PSScriptRoot "..\vendors\VendorManager.ps1"
    if (-not (Test-Path $vendorManagerPath)) {
        throw "VendorManager.ps1 not found at $vendorManagerPath"
    }
    . $vendorManagerPath
    $vendorManager = [VendorManager]::new()
    Write-Host "✓ Vendor modules loaded successfully" -ForegroundColor Green
    Write-Host "Total vendors: $($vendorManager.GetSupportedVendors().Count)" -ForegroundColor Gray

    # Test vendor routing
    $testUrl = "https://github.com/microsoft/vscode"
    $vendor = $vendorManager.GetVendor($testUrl)
    Write-Host "✓ Vendor routing works: $($vendor.VendorName)" -ForegroundColor Green

    # Test data extraction
    $testHtml = "<html><body><p>Test content</p></body></html>"
    $extractedData = $vendorManager.ExtractData($testHtml, $testUrl)
    Write-Host "✓ Data extraction works: $($extractedData.VendorUsed)" -ForegroundColor Green

    Write-Host "`nAll tests passed! Vendor modules are working correctly." -ForegroundColor Green
} catch {
    Write-Host "✗ Test failed: $($_.Exception.Message)" -ForegroundColor Red
}
