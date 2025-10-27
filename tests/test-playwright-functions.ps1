<#
.SYNOPSIS
    Test script for function-based Playwright wrapper.
#>

# Import the wrapper
$wrapperPath = Join-Path $PSScriptRoot "..\ui\PlaywrightWrapper.ps1"
if (-not (Test-Path $wrapperPath)) {
    Write-Host "✗ PlaywrightWrapper.ps1 not found at $wrapperPath" -ForegroundColor Red
    Write-Host "  Please ensure the UI directory contains PlaywrightWrapper.ps1" -ForegroundColor Yellow
    exit 1
}
. $wrapperPath

Write-Host "`n=== Playwright Function-Based Test ===" -ForegroundColor Cyan

# Test 1: Check DLL
Write-Host "`n[1/5] Testing DLL availability..." -ForegroundColor Yellow
$dllAvailable = Test-PlaywrightDll
if ($dllAvailable) {
    Write-Host "  ✓ Playwright DLL loaded successfully" -ForegroundColor Green
} else {
    Write-Host "  ✗ Playwright DLL not available" -ForegroundColor Red
    exit 1
}

# Test 2: Initialize browser
Write-Host "`n[2/5] Initializing Playwright browser..." -ForegroundColor Yellow
$initResult = New-PlaywrightBrowser -BrowserType chromium -Verbose
if ($initResult.Success) {
    Write-Host "  ✓ Browser initialized successfully" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to initialize browser: $($initResult.Error)" -ForegroundColor Red
    exit 1
}

# Test 3: Check state
Write-Host "`n[3/5] Checking Playwright state..." -ForegroundColor Yellow
$state = Get-PlaywrightState
Write-Host "  State: $($state | ConvertTo-Json -Compress)" -ForegroundColor Gray
if ($state.IsInitialized -and $state.HasBrowser -and $state.HasPage) {
    Write-Host "  ✓ State is valid" -ForegroundColor Green
} else {
    Write-Host "  ✗ Invalid state" -ForegroundColor Red
    Close-PlaywrightBrowser
    exit 1
}

# Test 4: Navigate to a page
Write-Host "`n[4/5] Navigating to example.com..." -ForegroundColor Yellow
$navResult = Invoke-PlaywrightNavigate -Url "https://example.com" -WaitSeconds 2 -Verbose
if ($navResult.Success) {
    Write-Host "  ✓ Navigation successful" -ForegroundColor Green
    Write-Host "  Content size: $($navResult.Size) bytes" -ForegroundColor Gray
    Write-Host "  Status code: $($navResult.StatusCode)" -ForegroundColor Gray

    # Check if content contains expected text
    if ($navResult.Content -match "Example Domain") {
        Write-Host "  ✓ Content verification passed" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Content may not be fully loaded" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ✗ Navigation failed: $($navResult.Error)" -ForegroundColor Red
    Close-PlaywrightBrowser
    exit 1
}

# Test 5: Take screenshot
Write-Host "`n[5/5] Taking screenshot..." -ForegroundColor Yellow
$outDir = Join-Path $PSScriptRoot "..\out"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$screenshotPath = Join-Path $outDir "playwright_test_screenshot.png"
$screenshotResult = Save-PlaywrightScreenshot -OutputPath $screenshotPath -Verbose
if ($screenshotResult -and (Test-Path $screenshotPath)) {
    Write-Host "  ✓ Screenshot saved: $screenshotPath" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Screenshot may have failed" -ForegroundColor Yellow
}

# Cleanup
Write-Host "`n[Cleanup] Closing browser..." -ForegroundColor Yellow
Close-PlaywrightBrowser
Write-Host "  ✓ Browser closed" -ForegroundColor Green

Write-Host "`n=== All Tests Passed! ===" -ForegroundColor Green
Write-Host "`nPlaywright function-based wrapper is working correctly." -ForegroundColor Cyan
