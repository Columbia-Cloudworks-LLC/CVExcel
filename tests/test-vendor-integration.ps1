# Test script to verify vendor module integration in CVExpand-GUI.ps1
# Tests extraction of KB articles and download links from MSRC pages

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing Vendor Module Integration" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Define Write-Log stub for vendor modules
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    # Show vendor log messages
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "DEBUG" { "DarkGray" }
        default { "Gray" }
    }
    Write-Host "    [$Level] $Message" -ForegroundColor $color
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
Write-Host "Initializing VendorManager..." -ForegroundColor Yellow
$vendorManager = [VendorManager]::new()
Write-Host "✓ VendorManager initialized`n" -ForegroundColor Green

# Test URLs
$testUrls = @(
    "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-21302",
    "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2025-49685"
)

foreach ($url in $testUrls) {
    Write-Host "Testing URL: $url" -ForegroundColor Cyan

    # Get vendor for URL
    $vendor = $vendorManager.GetVendor($url)
    Write-Host "  Vendor selected: $($vendor.VendorName)" -ForegroundColor White

    # Fetch page (simple HTTP request)
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        Write-Host "  Page fetched: $($response.Content.Length) bytes" -ForegroundColor White

        # Check if it's an MSRC page with minimal HTML
        if ($url -like '*msrc.microsoft.com*' -and $response.Content.Length -lt 5000) {
            Write-Host "  ⚠ MSRC page with minimal HTML detected ($($response.Content.Length) bytes)" -ForegroundColor Yellow
            Write-Host "  Testing enhanced extraction..." -ForegroundColor Yellow

            # Check for KB articles in HTML
            $kbMatches = [regex]::Matches($response.Content, 'KB(\d{6,7})')
            Write-Host "  KB articles found in HTML: $($kbMatches.Count)" -ForegroundColor White
        }

        # Extract data using vendor
        $extractedData = $vendor.ExtractData($response.Content, $url)

        Write-Host "  Results:" -ForegroundColor White
        Write-Host "    - PatchID: $($extractedData.PatchID)" -ForegroundColor Gray
        Write-Host "    - Affected Versions: $($extractedData.AffectedVersions)" -ForegroundColor Gray
        Write-Host "    - Download Links: $($extractedData.DownloadLinks.Count)" -ForegroundColor Gray

        if ($extractedData.DownloadLinks.Count -gt 0) {
            foreach ($link in $extractedData.DownloadLinks) {
                Write-Host "      • $link" -ForegroundColor DarkGray
            }
            Write-Host "  ✓ Download links extracted!" -ForegroundColor Green
        } else {
            Write-Host "  ✗ No download links found" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
