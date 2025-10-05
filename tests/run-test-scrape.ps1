# Simple script to test CVExpand-GUI scraping on test CSV
# Processes test_msrc_single.csv and checks results

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running CVExpand-GUI Test Scrape" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$testCsv = ".\out\test_msrc_single.csv"

if (-not (Test-Path $testCsv)) {
    Write-Host "✗ Test CSV not found: $testCsv" -ForegroundColor Red
    exit 1
}

Write-Host "Test CSV: $testCsv" -ForegroundColor White
Write-Host "Starting scrape...`n" -ForegroundColor Yellow

# Import CVExpand-GUI core functions (without launching GUI)
$cvExpandScript = Get-Content ".\CVExpand-GUI.ps1" -Raw

# Extract just the functions we need (not the GUI part)
$functionsOnly = $cvExpandScript -replace '(?s)# -------------------- GUI.*', ''

# Execute the functions
Invoke-Expression $functionsOnly

# Initialize log
$Global:LogFile = Initialize-LogFile

# Process the CSV
Write-Host "Processing CSV..." -ForegroundColor Yellow
$csv = Import-Csv -Path $testCsv

Write-Host "Found $($csv.Count) row(s)" -ForegroundColor White
Write-Host "URL to scrape: $($csv[0].RefUrls)`n" -ForegroundColor White

# Scrape the single URL
$url = ($csv[0].RefUrls -split '\|')[0].Trim()
Write-Host "Scraping: $url" -ForegroundColor Cyan

$result = Get-WebPage -Url $url

if ($result.Success) {
    Write-Host "✓ Page fetched: $($result.Content.Length) bytes ($($result.Method))" -ForegroundColor Green

    # Extract data
    $extracted = Extract-MSRCData -HtmlContent $result.Content -Url $url

    Write-Host "`nExtraction Results:" -ForegroundColor Cyan
    Write-Host "  Vendor: $($extracted.VendorUsed)" -ForegroundColor White
    Write-Host "  Patch ID: $($extracted.PatchID)" -ForegroundColor White
    Write-Host "  Download Links: $($extracted.DownloadLinks.Count)" -ForegroundColor White

    if ($extracted.DownloadLinks.Count -gt 0) {
        Write-Host "`n  Links:" -ForegroundColor Green
        foreach ($link in $extracted.DownloadLinks) {
            Write-Host "    • $link" -ForegroundColor Gray
        }
        Write-Host "`n✓ SUCCESS!" -ForegroundColor Green
    } else {
        Write-Host "`n✗ No download links extracted" -ForegroundColor Red
    }
} else {
    Write-Host "✗ Failed to fetch page: $($result.Error)" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Log file: $($Global:LogFile)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
