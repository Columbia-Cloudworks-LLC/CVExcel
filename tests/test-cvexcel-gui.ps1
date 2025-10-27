<#
.SYNOPSIS
Test script to verify CVExcel.ps1 GUI functionality and detect issues

.DESCRIPTION
This script tests CVExcel.ps1 GUI application by:
1. Checking PowerShell version
2. Verifying required files exist
3. Checking for dependencies
4. Testing API connectivity
5. Validating script syntax

.NOTES
Author: CVExcel Test Suite
Created: 2025-01-27
#>

Write-Host "=== CVExcel GUI Test Suite ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: PowerShell Version
Write-Host "Test 1: Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "  PowerShell Version: $($psVersion.Major).$($psVersion.Minor).$($psVersion.Patch)" -ForegroundColor Gray
if ($psVersion.Major -ge 7) {
    Write-Host "  ✓ PowerShell 7.x detected" -ForegroundColor Green
} else {
    Write-Host "  ✗ PowerShell 7.x required. Current version: $($psVersion.Major).$($psVersion.Minor)" -ForegroundColor Red
    Write-Host "  Download PowerShell 7: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
    return
}
Write-Host ""

# Test 2: Required Files
Write-Host "Test 2: Checking required files..." -ForegroundColor Yellow
$requiredFiles = @(
    "CVExcel.ps1",
    "products.txt"
)

$allFilesExist = $true
foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "  ✓ $file exists" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $file missing" -ForegroundColor Red
        $allFilesExist = $false
    }
}
Write-Host ""

if (-not $allFilesExist) {
    Write-Host "Required files are missing. Exiting tests." -ForegroundColor Red
    return
}

# Test 3: Output Directory
Write-Host "Test 3: Checking output directory..." -ForegroundColor Yellow
if (-not (Test-Path "out")) {
    New-Item -ItemType Directory -Path "out" | Out-Null
    Write-Host "  ✓ Created out/ directory" -ForegroundColor Green
} else {
    Write-Host "  ✓ out/ directory exists" -ForegroundColor Green
}
Write-Host ""

# Test 4: Script Syntax Check
Write-Host "Test 4: Checking script syntax..." -ForegroundColor Yellow
try {
    $parseErrors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw -Path "CVExcel.ps1"), [ref]$parseErrors)

    if ($parseErrors.Count -eq 0) {
        Write-Host "  ✓ No syntax errors detected" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Syntax errors found:" -ForegroundColor Red
        foreach ($parseError in $parseErrors) {
            Write-Host "    Line $($parseError.StartLine): $($parseError.Message)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  ✗ Failed to check syntax: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 5: API Key Check
Write-Host "Test 5: Checking API key configuration..." -ForegroundColor Yellow
$apiKey = $null
if (Test-Path "nvd.api.key") {
    $apiKey = Get-Content -Raw -Path "nvd.api.key"
    Write-Host "  ✓ API key file found" -ForegroundColor Green
} elseif ($env:NVD_API_KEY) {
    $apiKey = $env:NVD_API_KEY
    Write-Host "  ✓ API key from environment variable" -ForegroundColor Green
} else {
    Write-Host "  ℹ No API key configured (using public rate limits)" -ForegroundColor Yellow
    Write-Host "    Get a free API key at: https://nvd.nist.gov/developers/request-an-api-key" -ForegroundColor Gray
}

if ($apiKey) {
    $apiKey = $apiKey.Trim().Trim('"', '"', '"')
    if ($apiKey.Length -eq 36 -and $apiKey -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        Write-Host "  ✓ API key format valid (UUID format)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ API key format appears invalid (expected UUID, length 36)" -ForegroundColor Yellow
    }
}
Write-Host ""

# Test 6: Products File Validation
Write-Host "Test 6: Validating products.txt..." -ForegroundColor Yellow
try {
    $products = Get-Content "products.txt" | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
    if ($products.Count -gt 0) {
        Write-Host "  ✓ Found $($products.Count) valid products" -ForegroundColor Green
        Write-Host "    Sample products:" -ForegroundColor Gray
        $products | Select-Object -First 5 | ForEach-Object { Write-Host "      - $_" -ForegroundColor Gray }
    } else {
        Write-Host "  ✗ No valid products found in products.txt" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Failed to read products.txt: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 7: Assembly Dependencies
Write-Host "Test 7: Checking WPF assemblies..." -ForegroundColor Yellow
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore -ErrorAction Stop
    Write-Host "  ✓ WPF assemblies loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to load WPF assemblies: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    This might indicate missing .NET Framework or incompatible PowerShell version" -ForegroundColor Yellow
}
Write-Host ""

# Test 8: Network Connectivity
Write-Host "Test 8: Testing network connectivity to NVD API..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://nvd.nist.gov" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    Write-Host "  ✓ NVD website is reachable (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Cannot reach NVD website: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Check your internet connection" -ForegroundColor Yellow
}
Write-Host ""

# Test 9: Script Execution Test (Dry Run)
Write-Host "Test 9: Testing script execution (dry run)..." -ForegroundColor Yellow
try {
    # Test if script can be dot-sourced without errors
    Write-Host "  Attempting to validate script structure..." -ForegroundColor Gray

    # Check if script has required functions
    $scriptContent = Get-Content -Raw -Path "CVExcel.ps1"
    $requiredFunctions = @(
        'Get-NvdApiKey',
        'ConvertTo-Iso8601Z',
        'Get-CvssScore',
        'Expand-CPEs',
        'Invoke-NvdPage',
        'Get-NvdCves',
        'Resolve-CpeCandidates'
    )

    $functionsFound = @()
    foreach ($func in $requiredFunctions) {
        if ($scriptContent -match "function $func") {
            $functionsFound += $func
        }
    }

    if ($functionsFound.Count -eq $requiredFunctions.Count) {
        Write-Host "  ✓ All required functions found" -ForegroundColor Green
    } else {
        $missing = $requiredFunctions | Where-Object { $functionsFound -notcontains $_ }
        Write-Host "  ✗ Missing functions: $($missing -join ', ')" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Failed to validate script structure: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "To run the CVExcel GUI application:" -ForegroundColor Yellow
Write-Host "  pwsh -ExecutionPolicy Bypass -File CVExcel.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host "Expected behavior:" -ForegroundColor Yellow
Write-Host "  - GUI window should open" -ForegroundColor Gray
Write-Host "  - Products dropdown should be populated" -ForegroundColor Gray
Write-Host "  - Date pickers should be accessible" -ForegroundColor Gray
Write-Host "  - 'Test API' button should work" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: The GUI is an interactive application." -ForegroundColor Yellow
Write-Host "Run the command above to launch the GUI." -ForegroundColor Gray
Write-Host ""
