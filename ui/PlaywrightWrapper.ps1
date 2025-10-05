<#
.SYNOPSIS
    PowerShell wrapper for Microsoft Playwright browser automation.

.DESCRIPTION
    Provides a simplified interface for using Playwright in PowerShell scripts.
    Handles browser initialization, navigation, and cleanup with proper error handling.
    Uses function-based approach to avoid PowerShell class type resolution issues.
#>

# Script-level state storage
$script:PlaywrightState = @{
    BrowserType    = "chromium"
    TimeoutSeconds = 30
    UserDataDir    = $null
    Playwright     = $null
    Browser        = $null
    Context        = $null
    Page           = $null
    IsInitialized  = $false
    DllLoaded      = $false
}

#region DLL Loading

function Test-PlaywrightDll {
    <#
    .SYNOPSIS
        Checks if Playwright DLL is available and loads it.
    #>
    [CmdletBinding()]
    param()

    if ($script:PlaywrightState.DllLoaded) {
        return $true
    }

    # packages folder is in root directory (one level up from ui/)
    $rootDir = Split-Path $PSScriptRoot -Parent
    $packageDir = Join-Path $rootDir "packages"
    $libDir = Join-Path $packageDir "lib"
    $playwrightDll = Join-Path $libDir "Microsoft.Playwright.dll"

    if (-not (Test-Path $playwrightDll)) {
        Write-Warning "Playwright DLL not found at: $playwrightDll"
        Write-Warning "Please run Install-Playwright.ps1 first."
        return $false
    }

    try {
        # Check if already loaded
        $assemblyLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.Location -eq $playwrightDll }

        if (-not $assemblyLoaded) {
            Add-Type -Path $playwrightDll
            Write-Verbose "Playwright DLL loaded successfully"
        }

        $script:PlaywrightState.DllLoaded = $true
        return $true
    } catch {
        Write-Warning "Failed to load Playwright DLL: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Core Functions

function New-PlaywrightBrowser {
    <#
    .SYNOPSIS
        Initializes Playwright and launches a browser instance.

    .PARAMETER BrowserType
        Browser to launch: chromium, firefox, or webkit. Default is chromium.

    .PARAMETER TimeoutSeconds
        Navigation timeout in seconds. Default is 30.

    .PARAMETER Headless
        Run browser in headless mode. Default is true.

    .PARAMETER ExecutablePath
        Optional path to browser executable. If not specified, uses Playwright's bundled browsers.

    .EXAMPLE
        New-PlaywrightBrowser -BrowserType chromium
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('chromium', 'firefox', 'webkit')]
        [string]$BrowserType = 'chromium',

        [int]$TimeoutSeconds = 30,

        [bool]$Headless = $true,

        [string]$ExecutablePath = $null
    )

    try {
        Write-Verbose "Initializing Playwright wrapper..."

        # Load DLL if not already loaded
        if (-not (Test-PlaywrightDll)) {
            throw "Playwright DLL not available. Run Install-Playwright.ps1 first."
        }

        # Store configuration
        $script:PlaywrightState.BrowserType = $BrowserType
        $script:PlaywrightState.TimeoutSeconds = $TimeoutSeconds
        $script:PlaywrightState.UserDataDir = Join-Path $env:TEMP "playwright-userdata-$(Get-Random)"

        # Get Playwright type dynamically
        $playwrightType = [Type]::GetType('Microsoft.Playwright.Playwright, Microsoft.Playwright')
        if (-not $playwrightType) {
            throw "Could not load Playwright type"
        }

        # Create Playwright instance
        $createMethod = $playwrightType.GetMethod('CreateAsync')
        $playwrightTask = $createMethod.Invoke($null, @())
        $script:PlaywrightState.Playwright = $playwrightTask.GetAwaiter().GetResult()

        Write-Verbose "Playwright instance created"

        # Get browser launcher
        $browserLauncher = switch ($BrowserType.ToLower()) {
            'chromium' { $script:PlaywrightState.Playwright.Chromium }
            'firefox' { $script:PlaywrightState.Playwright.Firefox }
            'webkit' { $script:PlaywrightState.Playwright.Webkit }
            default { $script:PlaywrightState.Playwright.Chromium }
        }

        # Create launch options dynamically
        $launchOptionsType = [Type]::GetType('Microsoft.Playwright.BrowserTypeLaunchOptions, Microsoft.Playwright')
        $launchOptions = [Activator]::CreateInstance($launchOptionsType)
        $launchOptions.Headless = $Headless

        # Convert PowerShell array to proper IEnumerable<string>
        $argsList = New-Object 'System.Collections.Generic.List[string]'
        @(
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-blink-features=AutomationControlled',
            '--disable-extensions'
        ) | ForEach-Object { $argsList.Add($_) }
        $launchOptions.Args = $argsList

        # Use custom executable path if provided
        if ($ExecutablePath) {
            $launchOptions.ExecutablePath = $ExecutablePath
            Write-Verbose "Using custom browser at: $ExecutablePath"
        }

        # Launch browser
        $launchTask = $browserLauncher.LaunchAsync($launchOptions)
        $script:PlaywrightState.Browser = $launchTask.GetAwaiter().GetResult()

        Write-Verbose "Browser launched: $BrowserType"

        # Create context with realistic settings
        $contextOptionsType = [Type]::GetType('Microsoft.Playwright.BrowserNewContextOptions, Microsoft.Playwright')
        $contextOptions = [Activator]::CreateInstance($contextOptionsType)
        $contextOptions.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        $contextOptions.Locale = 'en-US'
        $contextOptions.TimezoneId = 'America/New_York'

        # Set viewport
        $viewportType = [Type]::GetType('Microsoft.Playwright.ViewportSize, Microsoft.Playwright')
        $viewport = [Activator]::CreateInstance($viewportType)
        $viewport.Width = 1920
        $viewport.Height = 1080
        $contextOptions.ViewportSize = $viewport

        $contextTask = $script:PlaywrightState.Browser.NewContextAsync($contextOptions)
        $script:PlaywrightState.Context = $contextTask.GetAwaiter().GetResult()

        Write-Verbose "Browser context created"

        # Create page
        $pageTask = $script:PlaywrightState.Context.NewPageAsync()
        $script:PlaywrightState.Page = $pageTask.GetAwaiter().GetResult()

        Write-Verbose "Page created successfully"

        $script:PlaywrightState.IsInitialized = $true

        return @{
            Success = $true
            Message = "Playwright browser initialized successfully"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "Failed to initialize Playwright: $errorMsg"

        $script:PlaywrightState.IsInitialized = $false

        return @{
            Success = $false
            Error   = $errorMsg
        }
    }
}

function Invoke-PlaywrightNavigate {
    <#
    .SYNOPSIS
        Navigates to a URL and returns the page content.

    .PARAMETER Url
        The URL to navigate to.

    .PARAMETER WaitSeconds
        Additional seconds to wait for dynamic content. Default is 5.

    .EXAMPLE
        Invoke-PlaywrightNavigate -Url "https://example.com"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [int]$WaitSeconds = 5
    )

    if (-not $script:PlaywrightState.IsInitialized) {
        return @{
            Success = $false
            Error   = "Playwright not initialized. Call New-PlaywrightBrowser first."
            Method  = "Playwright"
        }
    }

    try {
        Write-Verbose "Navigating to: $Url"

        $page = $script:PlaywrightState.Page

        # Create goto options dynamically
        $gotoOptionsType = [Type]::GetType('Microsoft.Playwright.PageGotoOptions, Microsoft.Playwright')
        $gotoOptions = [Activator]::CreateInstance($gotoOptionsType)
        $gotoOptions.Timeout = $script:PlaywrightState.TimeoutSeconds * 1000

        # Set WaitUntil to NetworkIdle
        $waitUntilType = [Type]::GetType('Microsoft.Playwright.WaitUntilState, Microsoft.Playwright')
        $networkIdleValue = [Enum]::Parse($waitUntilType, 'NetworkIdle')
        $gotoOptions.WaitUntil = $networkIdleValue

        # Navigate
        $navigateTask = $page.GotoAsync($Url, $gotoOptions)
        $response = $navigateTask.GetAwaiter().GetResult()

        if (-not $response) {
            throw "Navigation failed - no response received"
        }

        Write-Verbose "Page loaded, waiting for dynamic content..."

        # Wait for dynamic content
        Start-Sleep -Seconds $WaitSeconds

        # Get page content
        $contentTask = $page.ContentAsync()
        $htmlContent = $contentTask.GetAwaiter().GetResult()

        $contentSize = $htmlContent.Length
        Write-Verbose "Successfully loaded page: $contentSize bytes"

        return @{
            Success    = $true
            Content    = $htmlContent
            Size       = $contentSize
            Method     = "Playwright"
            StatusCode = $response.Status
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "Failed to navigate to ${Url}: $errorMsg"

        return @{
            Success = $false
            Error   = $errorMsg
            Method  = "Playwright"
        }
    }
}

function Save-PlaywrightScreenshot {
    <#
    .SYNOPSIS
        Takes a screenshot of the current page.

    .PARAMETER OutputPath
        Path where the screenshot will be saved.

    .PARAMETER FullPage
        Capture the full scrollable page. Default is true.

    .EXAMPLE
        Save-PlaywrightScreenshot -OutputPath "screenshot.png"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [bool]$FullPage = $true
    )

    if (-not $script:PlaywrightState.IsInitialized -or -not $script:PlaywrightState.Page) {
        Write-Warning "Cannot take screenshot - page not initialized"
        return $false
    }

    try {
        $page = $script:PlaywrightState.Page

        # Create screenshot options
        $screenshotOptionsType = [Type]::GetType('Microsoft.Playwright.PageScreenshotOptions, Microsoft.Playwright')
        $screenshotOptions = [Activator]::CreateInstance($screenshotOptionsType)
        $screenshotOptions.Path = $OutputPath
        $screenshotOptions.FullPage = $FullPage

        $screenshotTask = $page.ScreenshotAsync($screenshotOptions)
        $screenshotTask.GetAwaiter().GetResult() | Out-Null

        Write-Verbose "Screenshot saved: $OutputPath"
        return $true
    } catch {
        Write-Warning "Failed to take screenshot: $($_.Exception.Message)"
        return $false
    }
}

function Wait-PlaywrightSelector {
    <#
    .SYNOPSIS
        Waits for a specific CSS selector to appear on the page.

    .PARAMETER Selector
        CSS selector to wait for.

    .PARAMETER TimeoutSeconds
        Maximum seconds to wait. Default is 10.

    .EXAMPLE
        Wait-PlaywrightSelector -Selector "#content"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Selector,

        [int]$TimeoutSeconds = 10
    )

    if (-not $script:PlaywrightState.IsInitialized -or -not $script:PlaywrightState.Page) {
        Write-Warning "Page not initialized"
        return $false
    }

    try {
        $page = $script:PlaywrightState.Page

        # Create wait options
        $waitOptionsType = [Type]::GetType('Microsoft.Playwright.PageWaitForSelectorOptions, Microsoft.Playwright')
        $waitOptions = [Activator]::CreateInstance($waitOptionsType)
        $waitOptions.Timeout = $TimeoutSeconds * 1000

        $waitTask = $page.WaitForSelectorAsync($Selector, $waitOptions)
        $element = $waitTask.GetAwaiter().GetResult()

        return $element -ne $null
    } catch {
        Write-Verbose "Timeout waiting for selector: $Selector"
        return $false
    }
}

function Close-PlaywrightBrowser {
    <#
    .SYNOPSIS
        Closes the browser and disposes all Playwright resources.

    .EXAMPLE
        Close-PlaywrightBrowser
    #>
    [CmdletBinding()]
    param()

    try {
        # Close page
        if ($script:PlaywrightState.Page) {
            try {
                $closeTask = $script:PlaywrightState.Page.CloseAsync()
                $closeTask.GetAwaiter().GetResult() | Out-Null
            } catch {
                # Ignore close errors
            }
            $script:PlaywrightState.Page = $null
        }

        # Close context
        if ($script:PlaywrightState.Context) {
            try {
                $closeTask = $script:PlaywrightState.Context.CloseAsync()
                $closeTask.GetAwaiter().GetResult() | Out-Null
            } catch {
                # Ignore close errors
            }
            $script:PlaywrightState.Context = $null
        }

        # Close browser
        if ($script:PlaywrightState.Browser) {
            try {
                $closeTask = $script:PlaywrightState.Browser.CloseAsync()
                $closeTask.GetAwaiter().GetResult() | Out-Null
            } catch {
                # Ignore close errors
            }
            $script:PlaywrightState.Browser = $null
        }

        # Dispose Playwright
        if ($script:PlaywrightState.Playwright) {
            try {
                $script:PlaywrightState.Playwright.Dispose()
            } catch {
                # Ignore dispose errors
            }
            $script:PlaywrightState.Playwright = $null
        }

        # Clean up user data directory
        if ($script:PlaywrightState.UserDataDir -and (Test-Path $script:PlaywrightState.UserDataDir)) {
            try {
                Remove-Item -Path $script:PlaywrightState.UserDataDir -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                # Ignore cleanup errors
            }
        }

        $script:PlaywrightState.IsInitialized = $false
        Write-Verbose "Playwright resources disposed successfully"
    } catch {
        Write-Warning "Error disposing Playwright resources: $($_.Exception.Message)"
    }
}

function Get-PlaywrightState {
    <#
    .SYNOPSIS
        Returns the current Playwright state for debugging.

    .EXAMPLE
        Get-PlaywrightState
    #>
    [CmdletBinding()]
    param()

    return @{
        IsInitialized = $script:PlaywrightState.IsInitialized
        DllLoaded     = $script:PlaywrightState.DllLoaded
        BrowserType   = $script:PlaywrightState.BrowserType
        HasBrowser    = $script:PlaywrightState.Browser -ne $null
        HasPage       = $script:PlaywrightState.Page -ne $null
    }
}

#endregion

# Note: Functions are automatically available when dot-sourced
