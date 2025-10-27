# test-required-modules.ps1 - Required PowerShell modules check

Write-Host "Checking required PowerShell modules..." -ForegroundColor Cyan

$requiredModules = @(
    @{ Name = "WebAdministration"; Optional = $true; Description = "IIS management (optional)" },
    @{ Name = "PSScriptAnalyzer"; Optional = $true; Description = "Code analysis (optional)" },
    @{ Name = "Pester"; Optional = $true; Description = "Testing framework (optional)" }
)

$missingModules = @()
$availableModules = @()

Write-Host "`nChecking module availability:" -ForegroundColor Yellow

foreach ($module in $requiredModules) {
    try {
        $moduleInfo = Get-Module -ListAvailable -Name $module.Name -ErrorAction SilentlyContinue

        if ($moduleInfo) {
            $version = $moduleInfo.Version | Sort-Object -Descending | Select-Object -First 1
            Write-Host "✓ $($module.Name) v$version - Available" -ForegroundColor Green
            $availableModules += $module
        } else {
            if ($module.Optional) {
                Write-Host "⚠ $($module.Name) - Not available (optional)" -ForegroundColor Yellow
            } else {
                Write-Host "✗ $($module.Name) - Missing (required)" -ForegroundColor Red
                $missingModules += $module
            }
        }
    } catch {
        if ($module.Optional) {
            Write-Host "⚠ $($module.Name) - Error checking (optional)" -ForegroundColor Yellow
        } else {
            Write-Host "✗ $($module.Name) - Error checking (required)" -ForegroundColor Red
            $missingModules += $module
        }
    }
}

# Check for .NET assemblies
Write-Host "`nChecking .NET assemblies:" -ForegroundColor Yellow

$requiredAssemblies = @(
    "System.Web",
    "PresentationFramework",
    "PresentationCore"
)

foreach ($assembly in $requiredAssemblies) {
    try {
        Add-Type -AssemblyName $assembly -ErrorAction Stop
        Write-Host "✓ $assembly - Available" -ForegroundColor Green
    } catch {
        Write-Host "✗ $assembly - Missing" -ForegroundColor Red
        $missingModules += @{ Name = $assembly; Optional = $false; Description = ".NET Assembly" }
    }
}

# Summary
Write-Host "`nModule Check Summary:" -ForegroundColor Cyan
Write-Host "  Available modules: $($availableModules.Count)" -ForegroundColor Green
Write-Host "  Missing modules: $($missingModules.Count)" -ForegroundColor Red

if ($missingModules.Count -eq 0) {
    Write-Host "`n✓ All required modules are available!" -ForegroundColor Green
    Write-Host "`nOptional module installation commands:" -ForegroundColor Yellow
    Write-Host "  Install-Module -Name PSScriptAnalyzer -Force" -ForegroundColor Gray
    Write-Host "  Install-Module -Name Pester -Force" -ForegroundColor Gray
    Write-Host "  Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole" -ForegroundColor Gray
    exit 0
} else {
    Write-Host "`n✗ Some required modules are missing:" -ForegroundColor Red
    foreach ($module in $missingModules) {
        Write-Host "  - $($module.Name): $($module.Description)" -ForegroundColor Red
    }

    Write-Host "`nInstallation commands:" -ForegroundColor Yellow
    foreach ($module in $missingModules) {
        if ($module.Name -like "System.*" -or $module.Name -like "Presentation*") {
            Write-Host "  # $($module.Name) - Install .NET Framework or Windows Features" -ForegroundColor Gray
        } else {
            Write-Host "  Install-Module -Name $($module.Name) -Force" -ForegroundColor Gray
        }
    }
    exit 1
}
