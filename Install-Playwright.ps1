<#
.SYNOPSIS
    Installs Microsoft Playwright for PowerShell-based web scraping.

.DESCRIPTION
    This script installs Playwright dependencies including the .NET package
    and browser binaries. It provides automated installation with fallback
    options and detailed logging.

.PARAMETER Force
    Force reinstallation even if Playwright is already installed.

.PARAMETER BrowserType
    Browser to install (chromium, firefox, webkit). Default: chromium

.EXAMPLE
    .\Install-Playwright.ps1

.EXAMPLE
    .\Install-Playwright.ps1 -Force -BrowserType chromium
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [ValidateSet("chromium", "firefox", "webkit")]
    [string]$BrowserType = "chromium"
)

$ErrorActionPreference = "Stop"

# -------------------- Helper Functions --------------------

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Test-DotNetVersion {
    try {
        $dotnetVersion = dotnet --version 2>$null
        if (-not $dotnetVersion) {
            return $false
        }

        $version = [version]$dotnetVersion
        $requiredVersion = [version]"6.0.0"

        return $version -ge $requiredVersion
    } catch {
        return $false
    }
}

function Install-PlaywrightPackage {
    param(
        [string]$PackageDir
    )

    Write-ColorOutput "`n📦 Installing Playwright NuGet package..." "Cyan"

    # Create package directory
    if (-not (Test-Path $PackageDir)) {
        New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null
        Write-ColorOutput "✓ Created package directory: $PackageDir" "Green"
    }

    # Use dotnet add package to install Playwright
    # This approach downloads the package and all dependencies to the global NuGet cache
    # Then we'll copy the DLL to our local packages directory

    Write-ColorOutput "  Installing Playwright via dotnet add package..." "Yellow"

    # Create a simple console app project
    $projectFile = Join-Path $PackageDir "PlaywrightInstaller.csproj"
    $projectContent = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net6.0</TargetFramework>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>
</Project>
"@

    $projectContent | Out-File -FilePath $projectFile -Encoding UTF8 -Force

    # Add Playwright package
    Push-Location $PackageDir

    try {
        Write-ColorOutput "  Adding Microsoft.Playwright package..." "Yellow"
        $addOutput = dotnet add package Microsoft.Playwright --version 1.40.0 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "✗ Failed to add Playwright package" "Red"
            Write-ColorOutput "  Error: $addOutput" "Red"
            return $false
        }

        Write-ColorOutput "  Restoring packages..." "Yellow"
        $restoreOutput = dotnet restore 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "✗ Failed to restore packages" "Red"
            return $false
        }

        # Find Playwright DLL in NuGet cache
        $nugetCache = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.playwright"
        if (Test-Path $nugetCache) {
            $playwrightDll = Get-ChildItem -Path $nugetCache -Recurse -Filter "Microsoft.Playwright.dll" |
            Where-Object { $_.FullName -match "net6\.0|netstandard2\.0" } |
            Select-Object -First 1

            if ($playwrightDll) {
                # Copy DLL and dependencies to our packages directory
                $libDir = Join-Path $PackageDir "lib"
                if (-not (Test-Path $libDir)) {
                    New-Item -ItemType Directory -Path $libDir -Force | Out-Null
                }

                $sourceDllDir = Split-Path $playwrightDll.FullName -Parent
                Write-ColorOutput "  Copying Playwright DLLs from NuGet cache..." "Yellow"

                # Copy all DLLs from the source directory
                Get-ChildItem -Path $sourceDllDir -Filter "*.dll" | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $libDir -Force
                }

                Write-ColorOutput "✓ Playwright package installed successfully" "Green"
                Write-ColorOutput "✓ Playwright DLL copied to: $libDir" "Green"
                return $true
            } else {
                Write-ColorOutput "⚠ Playwright DLL not found in NuGet cache" "Yellow"
                return $false
            }
        } else {
            Write-ColorOutput "⚠ NuGet cache not found" "Yellow"
            return $false
        }
    } finally {
        Pop-Location
    }
}

$playwrightScript = Get-ChildItem -Path $PackageDir -Recurse -Filter "playwright.ps1" | Select-Object -First 1

Write-ColorOutput "✗ Failed to install Playwright package" "Red"
Write-ColorOutput "  Error: $restoreOutput" "Red"d" "Red"
        return $false
    }

    Write-ColorOutput "  Installing $BrowserType browser..." "Yellow"

    try {
        $output = & $playwrightScript.FullName install $BrowserType --with-deps 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "✓ Browser installed successfully" "Green"
            return $true
        } else {
            Write-ColorOutput "⚠ Browser installation completed with warnings" "Yellow"
            Write-ColorOutput "  Note: Some system dependencies may require manual installation" "Yellow"
            return $true  # Continue anyway as browser might work
        }
    }
    catch {
        Write-ColorOutput "✗ Failed to install browser: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Test-PlaywrightInstallation {
    param(
        [string]$PackageDir
    )

    Write-ColorOutput "`n🔍 Verifying Playwright installation..." "Cyan"

    # Check for Playwright DLL
    $playwrightDll = Get-ChildItem -Path $PackageDir -Recurse -Filter "Microsoft.Playwright.dll" | Select-Object -First 1

    if (-not $playwrightDll) {
        Write-ColorOutput "✗ Playwright DLL not found" "Red"
        return $false
    }

    Write-ColorOutput "✓ Playwright DLL found: $($playwrightDll.FullName)" "Green"
    # Check for Playwright DLL in lib directory
    $libDir = Join-Path $PackageDir "lib"
    $playwrightDll = Get-ChildItem -Path $libDir -Filter "Microsoft.Playwright.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    try {
        Add-Type -Path $playwrightDll.FullName
        Write-ColorOutput "✗ Playwright DLL not found in $libDir" "Red"essfully" "Green"
return $true
}
catch {
    Write-ColorOutput "✗ Failed to load Playwright assembly: $($_.Exception.Message)" "Red"
    return $false
}
}

# -------------------- Main Installation --------------------

Write-ColorOutput @"

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║         Playwright Installation for CVScraper                ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@ "Cyan"

# Check .NET version
Write-ColorOutput "🔍 Checking prerequisites..." "Cyan"
if (-not (Test-DotNetVersion)) {
    Write-ColorOutput @"

✗ .NET 6.0 or later is required but not found.

Please install .NET 6.0 SDK or later from:
https://dotnet.microsoft.com/download/dotnet/6.0

After installation, run this script again.

"@ "Red"
    exit 1
}

Write-ColorOutput "✓ .NET 6.0+ detected" "Green"

# Set up paths
$Root = Get-Location
$PackageDir = Join-Path $Root "packages"

# Check if already installed
if (-not $Force) {
    $existingDll = Get-ChildItem -Path $PackageDir -Recurse -Filter "Microsoft.Playwright.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingDll) {
        Write-ColorOutput @"

ℹ Playwright is already installed.

Use -Force to reinstall.

"@ "Yellow"
        exit 0
    }
}

# Install Playwright package
$packageSuccess = Install-PlaywrightPackage -PackageDir $PackageDir
if (-not $packageSuccess) {
    Write-ColorOutput "`n✗ Installation failed. Please check the errors above." "Red"
    exit 1
}

# Install browser binaries
$browserSuccess = Install-PlaywrightBrowsers -PackageDir $PackageDir -BrowserType $BrowserType
if (-not $browserSuccess) {
    Write-ColorOutput "`n⚠ Browser installation had issues, but continuing..." "Yellow"
}

# Verify installation
$verifySuccess = Test-PlaywrightInstallation -PackageDir $PackageDir
if (-not $verifySuccess) {
    Write-ColorOutput "`n✗ Installation verification failed." "Red"
    exit 1
}

# Success!
Write-ColorOutput @"

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║         ✅ Playwright Installation Complete!                  ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

Next steps:
1. Run: .\CVScrape.ps1
2. MSRC pages will now render with full JavaScript content
3. Check logs for "Successfully rendered MSRC page with Playwright"

Installation location: $PackageDir

"@ "Green"

exit 0
1. Run: .\CVScrape.ps1
2. MSRC pages will now render with full JavaScript content
3. Check logs for "Successfully rendered MSRC page with Playwright"

Installation location: $PackageDir

"@ "Green"

exit 0
