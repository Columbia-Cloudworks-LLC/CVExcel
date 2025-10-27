# test-powershell-version.ps1 - PowerShell version compatibility test

Write-Host "Testing PowerShell version compatibility..." -ForegroundColor Cyan

try {
    $psVersion = $PSVersionTable.PSVersion
    $psMajor = $psVersion.Major

    Write-Host "Current PowerShell Version: $psVersion" -ForegroundColor White

    # Check minimum requirements
    if ($psMajor -ge 5) {
        Write-Host "PowerShell version is compatible (5.0+)" -ForegroundColor Green

        # Check for specific features
        if ($psMajor -ge 6) {
            Write-Host "PowerShell Core/7+ detected - Full feature support" -ForegroundColor Green
        } else {
            Write-Host "Windows PowerShell 5.x detected - Compatible" -ForegroundColor Green
        }

        # Check execution policy
        $executionPolicy = Get-ExecutionPolicy
        Write-Host "Execution Policy: $executionPolicy" -ForegroundColor Gray

        if ($executionPolicy -eq "Restricted") {
            Write-Host "Warning: Execution policy is Restricted" -ForegroundColor Yellow
            Write-Host "  Consider running: Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process" -ForegroundColor Yellow
        } else {
            Write-Host "Execution policy allows script execution" -ForegroundColor Green
        }

        Write-Host "`nPowerShell version test: PASSED" -ForegroundColor Green
        exit 0

    } else {
        Write-Host "PowerShell version is too old (requires 5.0+)" -ForegroundColor Red
        Write-Host "  Current: $psVersion" -ForegroundColor Red
        Write-Host "  Required: 5.0 or higher" -ForegroundColor Red
        exit 1
    }

} catch {
    Write-Host "PowerShell version test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
