<#
.SYNOPSIS
    Manages dependencies and auto-installation for CVScrape.

.DESCRIPTION
    Handles automatic installation and configuration of required dependencies
    including Playwright, Selenium, and other scraping tools. Provides
    intelligent fallback mechanisms when dependencies are unavailable.
#>

# Script-level state for dependency tracking
$script:DependencyState = @{
    PlaywrightAvailable = $false
    SeleniumAvailable = $false
    PlaywrightBrowsersInstalled = $false
    LastCheck = $null
}

class DependencyManager {
    [string]$RootPath
    [hashtable]$InstallationStatus
    [string]$LogFile

    DependencyManager([string]$rootPath, [string]$logFile) {
        $this.RootPath = $rootPath
        $this.LogFile = $logFile
        $this.InstallationStatus = @{
            Playwright = @{ Available = $false; BrowsersInstalled = $false; Error = $null }
            Selenium = @{ Available = $false; Error = $null }
            Chrome = @{ Available = $false; Path = $null }
            Firefox = @{ Available = $false; Path = $null }
            Msrc = @{ Available = $false; Version = $null; Error = $null }
        }
    }

    # Check all dependencies and return comprehensive status
    [hashtable] CheckAllDependencies() {
        Write-Log -Message "Checking all dependencies..." -Level "INFO" -LogFile $this.LogFile

        $this.CheckPlaywright()
        $this.CheckSelenium()
        $this.CheckSystemBrowsers()
        $this.CheckMsrcModule()

        return $this.InstallationStatus
    }

    # Check Playwright availability and browser installation
    [void] CheckPlaywright() {
        try {
            $packageDir = Join-Path $this.RootPath "packages"
            $libDir = Join-Path $packageDir "lib"
            $playwrightDll = Join-Path $libDir "Microsoft.Playwright.dll"

            if (-not (Test-Path $playwrightDll)) {
                $this.InstallationStatus.Playwright.Available = $false
                $this.InstallationStatus.Playwright.Error = "Playwright DLL not found at: $playwrightDll"
                Write-Log -Message "Playwright DLL not found" -Level "WARNING" -LogFile $this.LogFile
                return
            }

            # Test DLL loading
            try {
                Add-Type -Path $playwrightDll -ErrorAction Stop
                $this.InstallationStatus.Playwright.Available = $true
                Write-Log -Message "Playwright DLL loaded successfully" -Level "SUCCESS" -LogFile $this.LogFile
            } catch {
                $this.InstallationStatus.Playwright.Available = $false
                $this.InstallationStatus.Playwright.Error = "Failed to load Playwright DLL: $($_.Exception.Message)"
                Write-Log -Message "Failed to load Playwright DLL: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
                return
            }

            # Check for browser installation
            $this.CheckPlaywrightBrowsers()

        } catch {
            $this.InstallationStatus.Playwright.Available = $false
            $this.InstallationStatus.Playwright.Error = $_.Exception.Message
            Write-Log -Message "Error checking Playwright: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
        }
    }

    # Check if Playwright browsers are installed
    [void] CheckPlaywrightBrowsers() {
        try {
            # Check for .playwright directory in project root
            $playwrightDir = Join-Path $this.RootPath ".playwright"

            if (Test-Path $playwrightDir) {
                # Check for browser executables
                $chromiumPath = Join-Path $playwrightDir "chromium-*\chrome-win\chrome.exe"
                $chromiumExists = (Get-ChildItem -Path $chromiumPath -ErrorAction SilentlyContinue).Count -gt 0

                if ($chromiumExists) {
                    $this.InstallationStatus.Playwright.BrowsersInstalled = $true
                    Write-Log -Message "Playwright browsers found and ready" -Level "SUCCESS" -LogFile $this.LogFile
                    return
                }
            }

            # Check system-wide Playwright installation
            $userPlaywrightDir = "$env:USERPROFILE\.cache\ms-playwright"
            if (Test-Path $userPlaywrightDir) {
                $chromiumPath = Join-Path $userPlaywrightDir "chromium-*\chrome-win\chrome.exe"
                $chromiumExists = (Get-ChildItem -Path $chromiumPath -ErrorAction SilentlyContinue).Count -gt 0

                if ($chromiumExists) {
                    $this.InstallationStatus.Playwright.BrowsersInstalled = $true
                    Write-Log -Message "Playwright browsers found in user cache" -Level "SUCCESS" -LogFile $this.LogFile
                    return
                }
            }

            $this.InstallationStatus.Playwright.BrowsersInstalled = $false
            Write-Log -Message "Playwright browsers not installed" -Level "WARNING" -LogFile $this.LogFile

        } catch {
            $this.InstallationStatus.Playwright.BrowsersInstalled = $false
            Write-Log -Message "Error checking Playwright browsers: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
        }
    }

    # Check Selenium availability
    [void] CheckSelenium() {
        try {
            $seleniumModule = Get-Module -ListAvailable -Name Selenium -ErrorAction SilentlyContinue

            if ($seleniumModule) {
                $this.InstallationStatus.Selenium.Available = $true
                Write-Log -Message "Selenium module available (version $($seleniumModule.Version))" -Level "SUCCESS" -LogFile $this.LogFile
            } else {
                $this.InstallationStatus.Selenium.Available = $false
                Write-Log -Message "Selenium module not available" -Level "WARNING" -LogFile $this.LogFile
            }
        } catch {
            $this.InstallationStatus.Selenium.Available = $false
            $this.InstallationStatus.Selenium.Error = $_.Exception.Message
            Write-Log -Message "Error checking Selenium: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
        }
    }

    # Check for system browsers
    [void] CheckSystemBrowsers() {
        # Check Chrome
        $chromePaths = @(
            "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
        )

        foreach ($path in $chromePaths) {
            if (Test-Path $path) {
                $this.InstallationStatus.Chrome.Available = $true
                $this.InstallationStatus.Chrome.Path = $path
                Write-Log -Message "Chrome found at: $path" -Level "SUCCESS" -LogFile $this.LogFile
                break
            }
        }

        # Check Firefox
        $firefoxPaths = @(
            "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
            "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
        )

        foreach ($path in $firefoxPaths) {
            if (Test-Path $path) {
                $this.InstallationStatus.Firefox.Available = $true
                $this.InstallationStatus.Firefox.Path = $path
                Write-Log -Message "Firefox found at: $path" -Level "SUCCESS" -LogFile $this.LogFile
                break
            }
        }
    }

    # Check MSRC module availability
    [void] CheckMsrcModule() {
        try {
            $module = Get-Module -ListAvailable -Name MsrcSecurityUpdates -ErrorAction SilentlyContinue

            if ($module) {
                $this.InstallationStatus.Msrc.Available = $true
                $this.InstallationStatus.Msrc.Version = $module.Version.ToString()
                Write-Log -Message "MsrcSecurityUpdates available (version $($module.Version))" -Level "SUCCESS" -LogFile $this.LogFile
            } else {
                $this.InstallationStatus.Msrc.Available = $false
                Write-Log -Message "MsrcSecurityUpdates module not available" -Level "WARNING" -LogFile $this.LogFile
            }
        } catch {
            $this.InstallationStatus.Msrc.Available = $false
            $this.InstallationStatus.Msrc.Error = $_.Exception.Message
            Write-Log -Message "Error checking MsrcSecurityUpdates: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
        }
    }

    # Install MSRC module
    [hashtable] InstallMsrcModule([bool]$autoConfirm = $false) {
        $result = @{
            Success = $false
            Error = $null
            Version = $null
        }

        try {
            # Check if already available
            if ($this.InstallationStatus.Msrc.Available) {
                return @{
                    Success = $true
                    Version = $this.InstallationStatus.Msrc.Version
                }
            }

            Write-Log -Message "Installing MsrcSecurityUpdates module..." -Level "INFO" -LogFile $this.LogFile

            # Ask for user confirmation if not auto-confirmed
            if (-not $autoConfirm -and -not (Show-InstallationPrompt -Title "Install MSRC Module?" -Message "Install 'MsrcSecurityUpdates' PowerShell module (CurrentUser scope)?")) {
                $result.Error = "User declined installation"
                return $result
            }

            # Ensure NuGet package provider is available
            if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                Write-Log -Message "Installing NuGet package provider..." -Level "INFO" -LogFile $this.LogFile
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop
            }

            # Ensure PSGallery is trusted
            $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            if ($repo -and $repo.InstallationPolicy -ne 'Trusted') {
                Write-Log -Message "Setting PSGallery as trusted repository..." -Level "INFO" -LogFile $this.LogFile
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            }

            # Install the module
            Write-Log -Message "Installing MsrcSecurityUpdates module from PSGallery..." -Level "INFO" -LogFile $this.LogFile
            Install-Module -Name MsrcSecurityUpdates -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop

            # Import the module to verify installation
            Import-Module MsrcSecurityUpdates -ErrorAction Stop

            # Re-check status
            $this.CheckMsrcModule()

            if ($this.InstallationStatus.Msrc.Available) {
                Write-Log -Message "MsrcSecurityUpdates installed successfully (version $($this.InstallationStatus.Msrc.Version))" -Level "SUCCESS" -LogFile $this.LogFile
                $result.Success = $true
                $result.Version = $this.InstallationStatus.Msrc.Version
            } else {
                $result.Error = "Module installed but not detected"
                Write-Log -Message "Module installed but not detected after installation" -Level "ERROR" -LogFile $this.LogFile
            }
        } catch {
            $result.Error = $_.Exception.Message
            Write-Log -Message "MsrcSecurityUpdates installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
        }

        return $result
    }

    # Auto-install missing dependencies
    [hashtable] InstallMissingDependencies([bool]$autoConfirm = $false) {
        $installResults = @{
            PlaywrightInstalled = $false
            SeleniumInstalled = $false
            PlaywrightBrowsersInstalled = $false
            MsrcInstalled = $false
            Errors = @()
        }

        # Install Selenium if missing
        if (-not $this.InstallationStatus.Selenium.Available) {
            try {
                Write-Log -Message "Installing Selenium module..." -Level "INFO" -LogFile $this.LogFile

                if ($autoConfirm -or (Show-InstallationPrompt -Title "Install Selenium?" -Message "Selenium module is required for JavaScript rendering. Install now?")) {
                    Install-Module -Name Selenium -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                    $installResults.SeleniumInstalled = $true
                    Write-Log -Message "Selenium installed successfully" -Level "SUCCESS" -LogFile $this.LogFile

                    # Re-check status
                    $this.CheckSelenium()
                }
            } catch {
                $installResults.Errors += "Selenium installation failed: $($_.Exception.Message)"
                Write-Log -Message "Selenium installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
            }
        }

        # Install Playwright browsers if Playwright is available but browsers are missing
        if ($this.InstallationStatus.Playwright.Available -and -not $this.InstallationStatus.Playwright.BrowsersInstalled) {
            try {
                Write-Log -Message "Installing Playwright browsers..." -Level "INFO" -LogFile $this.LogFile

                if ($autoConfirm -or (Show-InstallationPrompt -Title "Install Playwright Browsers?" -Message "Playwright browsers are required for JavaScript rendering. Install now?")) {
                    $browserInstallResult = $this.InstallPlaywrightBrowsers()
                    $installResults.PlaywrightBrowsersInstalled = $browserInstallResult.Success

                    if ($browserInstallResult.Success) {
                        Write-Log -Message "Playwright browsers installed successfully" -Level "SUCCESS" -LogFile $this.LogFile
                        $this.CheckPlaywrightBrowsers()
                    } else {
                        $installResults.Errors += "Playwright browser installation failed: $($browserInstallResult.Error)"
                    }
                }
            } catch {
                $installResults.Errors += "Playwright browser installation failed: $($_.Exception.Message)"
                Write-Log -Message "Playwright browser installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
            }
        }

        # Install MSRC module if missing
        if (-not $this.InstallationStatus.Msrc.Available) {
            try {
                Write-Log -Message "Installing MSRC module..." -Level "INFO" -LogFile $this.LogFile

                $msrcResult = $this.InstallMsrcModule($autoConfirm)
                if ($msrcResult.Success) {
                    $installResults.MsrcInstalled = $true
                    Write-Log -Message "MSRC module installed successfully" -Level "SUCCESS" -LogFile $this.LogFile
                } else {
                    $installResults.Errors += "MSRC module installation failed: $($msrcResult.Error)"
                    Write-Log -Message "MSRC module installation failed: $($msrcResult.Error)" -Level "ERROR" -LogFile $this.LogFile
                }
            } catch {
                $installResults.Errors += "MSRC module installation failed: $($_.Exception.Message)"
                Write-Log -Message "MSRC module installation failed: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
            }
        }

        return $installResults
    }

    # Install Playwright browsers using the installer
    [hashtable] InstallPlaywrightBrowsers() {
        try {
            $installScript = Join-Path $this.RootPath "Install-Playwright.ps1"

            if (-not (Test-Path $installScript)) {
                return @{
                    Success = $false
                    Error = "Install-Playwright.ps1 not found"
                }
            }

            Write-Log -Message "Running Playwright browser installer..." -Level "INFO" -LogFile $this.LogFile

            # Run the installer
            & $installScript

            if ($LASTEXITCODE -eq 0) {
                return @{
                    Success = $true
                    Message = "Playwright browsers installed successfully"
                }
            } else {
                return @{
                    Success = $false
                    Error = "Installation script returned exit code: $LASTEXITCODE"
                }
            }
        } catch {
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }

    # Get recommended scraping method based on available dependencies
    [string] GetRecommendedScrapingMethod() {
        if ($this.InstallationStatus.Playwright.Available -and $this.InstallationStatus.Playwright.BrowsersInstalled) {
            return "Playwright"
        } elseif ($this.InstallationStatus.Selenium.Available) {
            return "Selenium"
        } elseif ($this.InstallationStatus.Chrome.Available -or $this.InstallationStatus.Firefox.Available) {
            return "SystemBrowser"
        } else {
            return "HTTP"
        }
    }

    # Get status summary for user display
    [string] GetStatusSummary() {
        $summary = "Dependency Status:`n"

        if ($this.InstallationStatus.Playwright.Available) {
            $browserStatus = if ($this.InstallationStatus.Playwright.BrowsersInstalled) { "Ready" } else { "Browsers missing" }
            $summary += "• Playwright: $browserStatus`n"
        } else {
            $summary += "• Playwright: Not available`n"
        }

        if ($this.InstallationStatus.Selenium.Available) {
            $summary += "• Selenium: Ready`n"
        } else {
            $summary += "• Selenium: Not available`n"
        }

        if ($this.InstallationStatus.Msrc.Available) {
            $summary += "• MSRC Module: Ready (v$($this.InstallationStatus.Msrc.Version))`n"
        } else {
            $summary += "• MSRC Module: Not available`n"
        }

        $systemBrowsers = @()
        if ($this.InstallationStatus.Chrome.Available) { $systemBrowsers += "Chrome" }
        if ($this.InstallationStatus.Firefox.Available) { $systemBrowsers += "Firefox" }

        if ($systemBrowsers.Count -gt 0) {
            $summary += "• System Browsers: $($systemBrowsers -join ', ')`n"
        } else {
            $summary += "• System Browsers: None found`n"
        }

        $recommended = $this.GetRecommendedScrapingMethod()
        $summary += "`nRecommended method: $recommended"

        return $summary
    }
}

# Helper function to show installation prompts
function Show-InstallationPrompt {
    param(
        [string]$Title,
        [string]$Message
    )

    try {
        # Try to show a GUI prompt if WPF is available
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

        $result = [System.Windows.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        return $result -eq [System.Windows.MessageBoxResult]::Yes
    } catch {
        # Fallback to console prompt
        Write-Host "`n$Title" -ForegroundColor Yellow
        Write-Host $Message -ForegroundColor White
        $response = Read-Host "Install now? (y/n)"
        return $response -match '^[yY]'
    }
}

# DependencyManager class and helper functions are now available
