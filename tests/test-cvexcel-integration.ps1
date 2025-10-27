# test-cvexcel-integration.ps1 - CVExcel main script integration test

Write-Host "Testing CVExcel main script integration..." -ForegroundColor Cyan

# Test 1: Check main script files exist
Write-Host "`nTest 1: Checking main script files..." -ForegroundColor Yellow

$mainScripts = @(
    @{ Path = "..\CVExcel.ps1"; Name = "CVExcel Main Script" },
    @{ Path = "..\CVExpand.ps1"; Name = "CVExpand Script" },
    @{ Path = "..\products.txt"; Name = "Products Configuration" }
)

$missingFiles = @()

foreach ($script in $mainScripts) {
    $fullPath = Join-Path $PSScriptRoot $script.Path
    if (Test-Path $fullPath) {
        Write-Host "✓ $($script.Name) - Found" -ForegroundColor Green
    } else {
        Write-Host "✗ $($script.Name) - Missing at $fullPath" -ForegroundColor Red
        $missingFiles += $script
    }
}

# Test 2: Check directory structure
Write-Host "`nTest 2: Checking directory structure..." -ForegroundColor Yellow

$requiredDirs = @(
    @{ Path = "..\vendors"; Name = "Vendors Directory" },
    @{ Path = "..\out"; Name = "Output Directory" },
    @{ Path = "..\ui"; Name = "UI Directory" },
    @{ Path = "..\tests"; Name = "Tests Directory" }
)

foreach ($dir in $requiredDirs) {
    $fullPath = Join-Path $PSScriptRoot $dir.Path
    if (Test-Path $fullPath) {
        Write-Host "✓ $($dir.Name) - Found" -ForegroundColor Green
    } else {
        Write-Host "✗ $($dir.Name) - Missing at $fullPath" -ForegroundColor Red
        $missingFiles += $dir
    }
}

# Test 3: Check vendor modules
Write-Host "`nTest 3: Checking vendor modules..." -ForegroundColor Yellow

$vendorPath = Join-Path $PSScriptRoot "..\vendors"
if (Test-Path $vendorPath) {
    $vendorFiles = Get-ChildItem -Path $vendorPath -Filter "*.ps1" | Where-Object { $_.Name -ne "README.md" }
    Write-Host "✓ Found $($vendorFiles.Count) vendor modules" -ForegroundColor Green

    foreach ($file in $vendorFiles) {
        Write-Host "  - $($file.Name)" -ForegroundColor Gray
    }
} else {
    Write-Host "✗ Vendors directory not found" -ForegroundColor Red
}

# Test 4: Check configuration files
Write-Host "`nTest 4: Checking configuration files..." -ForegroundColor Yellow

$configPath = Join-Path $PSScriptRoot "..\config.json"
if (Test-Path $configPath) {
    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        Write-Host "✓ Configuration file is valid JSON" -ForegroundColor Green

        # Check for required configuration keys
        $requiredKeys = @("apiSettings", "scrapingSettings", "outputSettings")
        foreach ($key in $requiredKeys) {
            if ($config.PSObject.Properties.Name -contains $key) {
                Write-Host "  ✓ $key configuration present" -ForegroundColor Green
            } else {
                Write-Host "  ⚠ $key configuration missing" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "✗ Configuration file is invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⚠ Configuration file not found (optional)" -ForegroundColor Yellow
}

# Test 5: Check products.txt
Write-Host "`nTest 5: Checking products.txt..." -ForegroundColor Yellow

$productsPath = Join-Path $PSScriptRoot "..\products.txt"
if (Test-Path $productsPath) {
    try {
        $products = Get-Content -Path $productsPath | Where-Object { $_ -and -not $_.StartsWith('#') }
        Write-Host "✓ Found $($products.Count) product entries" -ForegroundColor Green

        if ($products.Count -gt 0) {
            Write-Host "  Sample entries:" -ForegroundColor Gray
            $products | Select-Object -First 3 | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
        }
    } catch {
        Write-Host "✗ Error reading products.txt: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "✗ products.txt not found" -ForegroundColor Red
    $missingFiles += @{ Name = "products.txt"; Path = $productsPath }
}

# Summary
Write-Host "`nIntegration Test Summary:" -ForegroundColor Cyan
Write-Host "  Missing files: $($missingFiles.Count)" -ForegroundColor Red

if ($missingFiles.Count -eq 0) {
    Write-Host "`n✓ CVExcel integration test: PASSED" -ForegroundColor Green
    Write-Host "All required files and directories are present." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ CVExcel integration test: FAILED" -ForegroundColor Red
    Write-Host "Missing files:" -ForegroundColor Red
    foreach ($file in $missingFiles) {
        Write-Host "  - $($file.Name)" -ForegroundColor Red
    }
    exit 1
}
