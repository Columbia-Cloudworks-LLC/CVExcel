# Project Structure Verification Script
# Verifies all paths and dependencies after cleanup

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     CVExcel Project Structure Verification              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true
$testCount = 0
$passCount = 0

function Test-File {
    param(
        [string]$Path,
        [string]$Description
    )

    $script:testCount++
    if (Test-Path $Path) {
        Write-Host "   ✓ $Description" -ForegroundColor Green
        $script:passCount++
        return $true
    } else {
        Write-Host "   ✗ $Description - NOT FOUND: $Path" -ForegroundColor Red
        $script:allPassed = $false
        return $false
    }
}

# Test Root Directory Structure
Write-Host "📂 ROOT DIRECTORY" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Test-File ".\CVExcel.ps1" "CVExcel.ps1 (main entry point)"
Test-File ".\CVExpand.ps1" "CVExpand.ps1 (core logic)"
Test-File ".\Install-Playwright.ps1" "Install-Playwright.ps1 (setup)"
Test-File ".\README.md" "README.md (project docs)"
Write-Host ""

# Test UI Folder
Write-Host "📂 UI FOLDER" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Test-File ".\ui\CVExpand-GUI.ps1" "CVExpand-GUI.ps1"
Test-File ".\ui\DependencyManager.ps1" "DependencyManager.ps1"
Test-File ".\ui\ScrapingEngine.ps1" "ScrapingEngine.ps1"
Test-File ".\ui\PlaywrightWrapper.ps1" "PlaywrightWrapper.ps1"
Test-File ".\ui\README.md" "README.md"
Write-Host ""

# Test Vendors Folder
Write-Host "📂 VENDORS FOLDER" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Test-File ".\vendors\BaseVendor.ps1" "BaseVendor.ps1"
Test-File ".\vendors\MicrosoftVendor.ps1" "MicrosoftVendor.ps1 (with official API)"
Test-File ".\vendors\VendorManager.ps1" "VendorManager.ps1"
Write-Host ""

# Test Docs Folder
Write-Host "📂 DOCS FOLDER" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Test-File ".\docs\INDEX.md" "INDEX.md (navigation)"
Test-File ".\docs\README.md" "README.md"
Test-File ".\docs\QUICK_START.md" "QUICK_START.md"
Test-File ".\docs\MSRC_API_SOLUTION.md" "MSRC_API_SOLUTION.md (latest solution)"
Test-File ".\docs\PATH_FIXES_POST_CLEANUP.md" "PATH_FIXES_POST_CLEANUP.md"
Write-Host ""

# Test Tests Folder
Write-Host "📂 TESTS FOLDER" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Test-File ".\tests\run-all-tests.ps1" "run-all-tests.ps1"
Test-File ".\tests\legacy" "legacy/ subfolder"
Write-Host ""

# Test Package Dependencies
Write-Host "📦 DEPENDENCIES" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Test-File ".\packages\lib\Microsoft.Playwright.dll" "Playwright DLL"

# Check for MSRC module
if (Get-Module -ListAvailable -Name MsrcSecurityUpdates) {
    Write-Host "   ✓ MsrcSecurityUpdates module installed" -ForegroundColor Green
    $passCount++
} else {
    Write-Host "   ⚠ MsrcSecurityUpdates module not installed (recommended)" -ForegroundColor Yellow
    Write-Host "     Run: Install-Module -Name MsrcSecurityUpdates -Scope CurrentUser" -ForegroundColor Gray
}
$testCount++

Write-Host ""

# Summary
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host ""
Write-Host "📊 RESULTS: $passCount / $testCount tests passed" -ForegroundColor $(if($passCount -eq $testCount){"Green"}else{"Yellow"})
Write-Host ""

if ($allPassed -and $passCount -eq $testCount) {
    Write-Host "✅ ALL CHECKS PASSED!" -ForegroundColor Green
    Write-Host "   Project structure is correct and ready to use." -ForegroundColor White
    Write-Host ""
    Write-Host "🚀 Next steps:" -ForegroundColor Cyan
    Write-Host "   1. Read: .\README.md" -ForegroundColor White
    Write-Host "   2. Run:  .\CVExpand.ps1" -ForegroundColor White
    Write-Host "   3. Run:  .\ui\CVExpand-GUI.ps1" -ForegroundColor White
} else {
    Write-Host "⚠️  Some checks failed. Review the output above." -ForegroundColor Yellow
}

Write-Host ""
