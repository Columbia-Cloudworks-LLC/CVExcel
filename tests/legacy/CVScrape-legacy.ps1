<#
CVScrape — Enhanced Advisory Webpage Scraper for CVE Data
- GUI: Dropdown to select CSV files from .\out\
- Scrapes advisory URLs from RefUrls column
- Extracts: download links, patches, affected versions, remediation info
- Idempotent: Detects if file already scraped (checks for ScrapedDate column)
- Adds new columns: AdvisoryContent, DownloadLinks, ExtractedData, ScrapedDate, ScrapeStatus
- Progress bar and detailed logging
- Handles various advisory formats (IBM, Microsoft, GitHub, ZDI, etc.)

ENHANCED FEATURES:
- Smart URL routing - automatically selects best scraping method
- GitHub API integration - gets structured data instead of HTML scraping
- Selenium auto-install - automatically installs if needed for MSRC pages
- Selenium support - renders JavaScript-heavy pages (MSRC)
- Improved headers - reduces bot detection/403 errors
- Fallback logic - tries multiple methods before failing
- Works out of the box - no manual setup required
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, System.Web

# -------------------- Paths --------------------
$Root = Get-Location
$OutDir = Join-Path $Root "out"
if (-not (Test-Path $OutDir)) { Write-Error "Missing 'out' directory."; return }

# -------------------- Logging Infrastructure --------------------
$Global:LogFile = $null

function Initialize-LogFile {
    [CmdletBinding()]
    param(
        [string]$LogDir = $OutDir
    )

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFileName = "scrape_log_$timestamp.log"
    $logFilePath = Join-Path $LogDir $logFileName

    # Create log file with header
    $header = @"
================================================================================
CVE Advisory Scraper Log
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Log File: $logFileName
================================================================================

"@

    Add-Content -Path $logFilePath -Value $header -Encoding UTF8
    Write-Host "Log file created: $logFilePath" -ForegroundColor Cyan

    return $logFilePath
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO",
        [string]$LogFile = $Global:LogFile
    )

    if (-not $LogFile -or -not (Test-Path $LogFile)) {
        Write-Host "Warning: Log file not initialized. Message: $Message" -ForegroundColor Yellow
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Write to log file
    Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8

    # Write to console with appropriate color
    $color = switch ($Level) {
        "INFO" { "White" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "DEBUG" { "Gray" }
        "SUCCESS" { "Green" }
        default { "White" }
    }

    Write-Host $logEntry -ForegroundColor $color
}

# -------------------- Helper Functions --------------------
# -------------------- Enhanced Scraping Functions --------------------

# Import vendor modules in correct order
. "$PSScriptRoot\vendors\BaseVendor.ps1"
. "$PSScriptRoot\vendors\GenericVendor.ps1"
. "$PSScriptRoot\vendors\GitHubVendor.ps1"
. "$PSScriptRoot\vendors\MicrosoftVendor.ps1"
. "$PSScriptRoot\vendors\IBMVendor.ps1"
. "$PSScriptRoot\vendors\ZDIVendor.ps1"
. "$PSScriptRoot\vendors\VendorManager.ps1"

# Initialize vendor manager
$Global:VendorManager = [VendorManager]::new()

function Get-GitHubAdvisoryData {
    <#
    .SYNOPSIS
    Extracts CVE advisory data from GitHub repositories using the REST API.

    .DESCRIPTION
    This function now delegates to the GitHub vendor module for consistent handling.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    return $Global:VendorManager.GetApiData($Url, $null)
}

function Install-SeleniumIfNeeded {
    <#
    .SYNOPSIS
    Automatically installs Selenium module if not present.

    .DESCRIPTION
    Checks for Selenium module and installs it automatically for better
    MSRC page scraping. Only installs once per session.
    #>

    [CmdletBinding()]
    param(
        [switch]$Force
    )

    # Check if already available
    $seleniumModule = Get-Module -ListAvailable -Name Selenium

    if ($seleniumModule -and -not $Force) {
        Write-Log -Message "Selenium module already installed (version $($seleniumModule.Version))" -Level "DEBUG"
        return @{
            Success          = $true
            AlreadyInstalled = $true
            Version          = $seleniumModule.Version
        }
    }

    try {
        Write-Log -Message "Selenium module not found. Installing automatically..." -Level "INFO"
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║  Installing Selenium for JavaScript rendering (MSRC pages)   ║" -ForegroundColor Cyan
        Write-Host "║  This is a one-time installation and will improve data        ║" -ForegroundColor Cyan
        Write-Host "║  extraction from Microsoft Security Response Center pages     ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        # Install Selenium module
        Install-Module -Name Selenium -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop

        Write-Log -Message "Successfully installed Selenium module" -Level "SUCCESS"
        Write-Host "✓ Selenium installed successfully!`n" -ForegroundColor Green

        # Verify installation
        $seleniumModule = Get-Module -ListAvailable -Name Selenium

        return @{
            Success          = $true
            AlreadyInstalled = $false
            Version          = $seleniumModule.Version
            JustInstalled    = $true
        }
    } catch {
        Write-Log -Message "Failed to install Selenium: $_" -Level "ERROR"
        Write-Host "✗ Selenium installation failed: $_`n" -ForegroundColor Red
        Write-Host "  You can install manually with:" -ForegroundColor Yellow
        Write-Host "    Install-Module -Name Selenium -Scope CurrentUser -Force`n" -ForegroundColor White

        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

# Import Playwright wrapper
. "$PSScriptRoot\PlaywrightWrapper.ps1"

function Test-PlaywrightAvailability {
    <#
    .SYNOPSIS
    Checks if Playwright is installed and available.
    #>
    try {
        $packageDir = Join-Path $PSScriptRoot "packages"
        if (-not (Test-Path $packageDir)) {
            return $false
        }
        $playwrightDll = Get-ChildItem -Path $packageDir -Recurse -Filter "Microsoft.Playwright.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
        return $null -ne $playwrightDll
    } catch {
        return $false
    }
}

function Get-MSRCPageWithPlaywright {
    <#
    .SYNOPSIS
    Fetches Microsoft MSRC pages using Playwright to render JavaScript content.

    .DESCRIPTION
    MSRC pages are React applications that require JavaScript execution.
    This function uses Microsoft Playwright to render the page with superior
    JavaScript support and bot detection avoidance compared to Selenium.
    Will automatically prompt for installation if not present.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    Write-Log -Message "Using Playwright to render MSRC page: $Url" -Level "INFO"

    # Check if Playwright is available
    $playwrightAvailable = Test-PlaywrightAvailability

    if (-not $playwrightAvailable) {
        Write-Log -Message "Playwright not available. Installation required." -Level "WARNING"
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║  Playwright not installed                                    ║" -ForegroundColor Yellow
        Write-Host "║                                                               ║" -ForegroundColor Yellow
        Write-Host "║  To enable MSRC page rendering, run:                          ║" -ForegroundColor Yellow
        Write-Host "║  .\Install-Playwright.ps1                                    ║" -ForegroundColor Yellow
        Write-Host "║                                                               ║" -ForegroundColor Yellow
        Write-Host "║  The scraper will continue with HTTP-only mode                ║" -ForegroundColor Yellow
        Write-Host "╚═══════════════════════════════════════════════════════════════╝`n" -ForegroundColor Yellow

        return @{
            Success            = $false
            Method             = 'Playwright'
            Error              = 'Playwright not available and installation failed'
            RequiresPlaywright = $true
        }
    }

    try {
        # Initialize Playwright browser (function-based API)
        Write-Log -Message "Initializing Playwright browser for MSRC page..." -Level "DEBUG"
        $initResult = New-PlaywrightBrowser -BrowserType chromium -TimeoutSeconds 30

        if (-not $initResult.Success) {
            throw "Failed to initialize Playwright browser: $($initResult.Error)"
        }

        Write-Log -Message "Playwright browser initialized successfully" -Level "SUCCESS"

        # Navigate to page with extended wait for MSRC content (8 seconds)
        $result = Invoke-PlaywrightNavigate -Url $Url -WaitSeconds 8

        if ($result.Success) {
            # Validate content quality
            $contentSize = $result.Size
            $hasGoodContent = $contentSize -gt 10000 -and $result.Content -match '(CVE|vulnerability|security|update|patch|KB)'

            if ($hasGoodContent) {
                Write-Log -Message "Successfully rendered MSRC page with Playwright - ${contentSize} bytes" -Level "SUCCESS"
                Write-Log -Message "Detected MSRC-specific content in rendered page" -Level "SUCCESS"

                return @{
                    Success = $true
                    Content = $result.Content
                    Size    = $contentSize
                    Method  = 'Playwright'
                }
            } else {
                Write-Log -Message "MSRC page rendered but content appears incomplete - ${contentSize} bytes" -Level "WARNING"

                # Still return the content, but mark as potentially incomplete
                return @{
                    Success = $true
                    Content = $result.Content
                    Size    = $contentSize
                    Method  = 'Playwright'
                    Warning = 'Content may be incomplete'
                }
            }
        } else {
            throw $result.Error
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log -Message "Playwright rendering failed: $errorMsg" -Level "ERROR"

        return @{
            Success = $false
            Method  = 'Playwright'
            Error   = $errorMsg
        }
    } finally {
        # Always cleanup browser
        Close-PlaywrightBrowser
        Write-Log -Message "Playwright browser closed" -Level "DEBUG"
    }
}

function Get-CsvFiles {
    $csvFiles = Get-ChildItem -Path $OutDir -Filter "*.csv" -File | Sort-Object LastWriteTime -Descending
    return $csvFiles
}

function Test-CsvAlreadyScraped {
    param([string]$CsvPath)

    # Read first line to check for scraped columns
    $firstLine = Get-Content -Path $CsvPath -First 1

    # Check if ScrapedDate column exists
    if ($firstLine -match '"?ScrapedDate"?') {
        return $true
    }
    return $false
}

function Invoke-WebRequestWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$MaxRetries = 3,
        [int]$TimeoutSec = 30,
        [int]$BaseDelayMs = 1000,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session = $null
    )

    $attempt = 0
    $lastException = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            Write-Log -Message "Attempting to fetch URL (attempt $attempt/$MaxRetries): $Url" -Level "DEBUG"

            # Enhanced headers to mimic real browser and avoid bot detection
            $headers = @{
                'User-Agent'                = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                'Accept'                    = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8'
                'Accept-Language'           = 'en-US,en;q=0.9'
                'Accept-Encoding'           = 'gzip, deflate, br'
                'DNT'                       = '1'
                'Connection'                = 'keep-alive'
                'Upgrade-Insecure-Requests' = '1'
                'Sec-Fetch-Dest'            = 'document'
                'Sec-Fetch-Mode'            = 'navigate'
                'Sec-Fetch-Site'            = 'none'
                'Cache-Control'             = 'max-age=0'
            }

            # Add small random delay to appear more human-like (helps avoid rate limiting)
            if ($attempt -eq 1) {
                $humanDelay = Get-Random -Minimum 500 -Maximum 1500
                Start-Sleep -Milliseconds $humanDelay
            }

            # Add Referer header for same domain (helps with anti-bot protection)
            try {
                $uri = [System.Uri]$Url
                $headers['Referer'] = "$($uri.Scheme)://$($uri.Host)/"
            } catch {
                # Skip if URL parsing fails
            }

            $invokeParams = @{
                Uri             = $Url
                Headers         = $headers
                TimeoutSec      = $TimeoutSec
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            # Use session if provided (maintains cookies across requests)
            if ($Session) {
                $invokeParams['WebSession'] = $Session
            } else {
                $invokeParams['SessionVariable'] = 'newSession'
            }

            $response = Invoke-WebRequest @invokeParams

            Write-Log -Message "Successfully fetched URL: $Url (Status: $($response.StatusCode), Size: $($response.Content.Length) bytes)" -Level "SUCCESS"

            # Return session for reuse if it was created
            $returnSession = if ($Session) { $Session } elseif ($newSession) { $newSession } else { $null }

            return @{
                Success    = $true
                Content    = $response.Content
                StatusCode = $response.StatusCode
                Attempts   = $attempt
                Error      = $null
                Session    = $returnSession
            }
        } catch {
            $lastException = $_.Exception
            $errorType = $_.Exception.GetType().Name
            $errorMessage = $_.Exception.Message

            Write-Log -Message "Failed to fetch URL (attempt $attempt/$MaxRetries): $Url - $errorType : $errorMessage" -Level "WARNING"

            # Determine if we should retry based on error type
            $shouldRetry = $false
            if ($_.Exception -is [System.Net.WebException]) {
                $webEx = $_.Exception
                switch ($webEx.Status) {
                    'Timeout' { $shouldRetry = $true }
                    'ConnectFailure' { $shouldRetry = $true }
                    'ReceiveFailure' { $shouldRetry = $true }
                    'SendFailure' { $shouldRetry = $true }
                    'PipelineFailure' { $shouldRetry = $true }
                    'KeepAliveFailure' { $shouldRetry = $true }
                    'NameResolutionFailure' { $shouldRetry = $false } # DNS issues won't resolve quickly
                    'ProtocolError' {
                        if ($webEx.Response) {
                            $statusCode = [int]$webEx.Response.StatusCode
                            $shouldRetry = $statusCode -ge 500 -or $statusCode -eq 429 # Server errors or rate limiting
                        }
                    }
                }
            } elseif ($_.Exception -is [System.OperationCanceledException]) {
                $shouldRetry = $true # Timeout
            }

            if ($shouldRetry -and $attempt -lt $MaxRetries) {
                $delay = $BaseDelayMs * [Math]::Pow(2, $attempt - 1) # Exponential backoff
                # Add small random jitter (0-500ms) to avoid thundering herd
                $jitter = Get-Random -Minimum 0 -Maximum 500
                $totalDelay = $delay + $jitter
                Write-Log -Message "Retrying in $totalDelay ms..." -Level "INFO"
                Start-Sleep -Milliseconds $totalDelay
            } else {
                break
            }
        }
    }

    # All attempts failed
    $errorDetails = @{
        'Error Type'    = $lastException.GetType().Name
        'Error Message' = $lastException.Message
        'Attempts Made' = $attempt
        'Final Status'  = if ($lastException -is [System.Net.WebException] -and $lastException.Response) {
            [int]$lastException.Response.StatusCode
        } else { 'N/A' }
    }

    Write-Log -Message "All retry attempts failed for URL: $Url - $($errorDetails | ConvertTo-Json -Compress)" -Level "ERROR"

    return @{
        Success    = $false
        Content    = $null
        StatusCode = $errorDetails.'Final Status'
        Attempts   = $attempt
        Error      = $errorDetails
    }
}

function Get-WebPageContent {
    [CmdletBinding()]
    param(
        [string]$Url,
        [int]$TimeoutSec = 30,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session = $null
    )

    if (-not $Url -or $Url -eq '') {
        Write-Log -Message "Empty URL provided to Get-WebPageContent" -Level "WARNING"
        return @{
            Content    = $null
            Session    = $Session
            StatusCode = $null
        }
    }

    $result = Invoke-WebRequestWithRetry -Url $Url -TimeoutSec $TimeoutSec -Session $Session

    if ($result.Success) {
        return @{
            Content    = $result.Content
            Session    = $result.Session
            StatusCode = $result.StatusCode
        }
    } else {
        Write-Log -Message "Failed to fetch page content for: $Url" -Level "ERROR"
        return @{
            Content    = $null
            Session    = $Session
            StatusCode = $result.StatusCode
        }
    }
}

function Extract-DownloadLinks {
    param(
        [string]$HtmlContent,
        [string]$BaseUrl
    )

    if (-not $HtmlContent) { return @() }

    # Use vendor manager to extract download links
    $vendor = $Global:VendorManager.GetVendor($BaseUrl)
    return $vendor.ExtractDownloadLinks($HtmlContent, $BaseUrl)
}

function Test-ExtractedDataQuality {
    [CmdletBinding()]
    param(
        [hashtable]$ExtractedData,
        [string]$Url = ""
    )

    # Use vendor manager to test data quality
    if ($Url) {
        $vendor = $Global:VendorManager.GetVendor($Url)
        return $vendor.TestDataQuality($ExtractedData)
    } else {
        # Fallback to generic vendor for testing
        $genericVendor = [GenericVendor]::new()
        return $genericVendor.TestDataQuality($ExtractedData)
    }
}

function Clean-HtmlText {
    param([string]$Text)

    if (-not $Text) { return '' }

    # Use vendor manager to clean HTML text
    $genericVendor = [GenericVendor]::new()
    return $genericVendor.CleanHtmlText($Text)
}

function Validate-And-Clean-Data {
    [CmdletBinding()]
    param(
        [hashtable]$RawData,
        [string]$Url = ""
    )

    $cleanedData = @{}

    foreach ($key in $RawData.Keys) {
        $value = $RawData[$key]
        if ($value -and $value -ne '') {
            $cleanedValue = Clean-HtmlText -Text $value
            if ($cleanedValue -and $cleanedValue.Length -gt 3) {
                $cleanedData[$key] = $cleanedValue
            }
        }
    }

    # Test quality of cleaned data
    $quality = Test-ExtractedDataQuality -ExtractedData $cleanedData -Url $Url

    if (-not $quality.IsGoodQuality) {
        Write-Log -Message "Low quality data extracted: Score=$($quality.QualityScore), Issues=$($quality.Issues -join ', ')" -Level "WARNING"
    }

    return $cleanedData
}

function Get-MsrcAdvisoryData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CveId,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session = $null
    )

    # Use Microsoft vendor module for MSRC data
    $microsoftVendor = [MicrosoftVendor]::new()
    $result = $microsoftVendor.GetMsrcAdvisoryData($CveId, $Session)

    if ($result.Success) {
        return $result.Data
    } else {
        return @{
            PatchID          = $null
            AffectedVersions = $null
            Remediation      = $null
            DownloadLinks    = @()
        }
    }
}

function Extract-PatchInfo {
    param(
        [string]$HtmlContent,
        [string]$Url
    )

    if (-not $HtmlContent) { return @{} }

    # Use vendor manager to extract data
    $extractedData = $Global:VendorManager.ExtractData($HtmlContent, $Url)

    # Enhanced logging with data quality assessment
    $dataQuality = $Global:VendorManager.GetVendor($Url).TestDataQuality($extractedData)
    $qualityStatus = if ($dataQuality.IsGoodQuality) { "GOOD" } else { "LOW" }

    Write-Log -Message "Extracted patch info for $Url using $($extractedData.VendorUsed) - Quality: $qualityStatus ($($dataQuality.QualityScore)/100) - PatchID: '$($extractedData.PatchID)', FixVersion: '$($extractedData.FixVersion)', AffectedVersions: '$($extractedData.AffectedVersions)', Remediation: '$($extractedData.Remediation)'" -Level "DEBUG"

    if (-not $dataQuality.IsGoodQuality -and $dataQuality.Issues.Count -gt 0) {
        Write-Log -Message "Data quality issues detected: $($dataQuality.Issues -join ', ')" -Level "WARNING"
    }

    return $extractedData
}

function Scrape-AdvisoryUrl {
    [CmdletBinding()]
    param(
        [string]$Url,
        [ref]$ProgressCallback,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session = $null
    )

    if (-not $Url -or $Url -eq '') {
        Write-Log -Message "Empty URL provided to Scrape-AdvisoryUrl" -Level "WARNING"
        return @{
            Url           = $Url
            Status        = 'Empty'
            DownloadLinks = ''
            ExtractedData = ''
            Error         = 'Empty URL'
            Session       = $Session
        }
    }

    Write-Log -Message "Starting to scrape advisory URL: $Url" -Level "INFO"

    # ==================== SMART URL ROUTING ====================
    # Route to best method based on URL pattern

    # GITHUB URLs - Use API instead of HTML scraping
    if ($Url -match 'github\.com') {
        Write-Log -Message "Detected GitHub URL - Using GitHub API method" -Level "INFO"

        $startTime = Get-Date
        $githubResult = Get-GitHubAdvisoryData -Url $Url
        $totalTime = (Get-Date) - $startTime

        if ($githubResult.Success) {
            Write-Log -Message "Successfully extracted GitHub data via API" -Level "SUCCESS"
            return @{
                Url            = $Url
                Status         = 'Success'
                DownloadLinks  = ($githubResult.DownloadLinks -join ' | ')
                ExtractedData  = $githubResult.ExtractedData
                Error          = $null
                FetchTime      = $totalTime.TotalSeconds
                ExtractTime    = $totalTime.TotalSeconds
                TotalTime      = $totalTime.TotalSeconds
                LinksFound     = $githubResult.DownloadLinks.Count
                DataPartsFound = if ($githubResult.ExtractedData) { ($githubResult.ExtractedData -split '\|').Count } else { 0 }
                Session        = $Session
                Method         = 'GitHub API'
            }
        } else {
            Write-Log -Message "GitHub API failed: $($githubResult.Error) - Falling back to standard scraping" -Level "WARNING"
            # Fall through to standard scraping
        }
    }

    # MICROSOFT MSRC URLs - Try Playwright first, fallback to standard
    if ($Url -match 'msrc\.microsoft\.com') {
        Write-Log -Message "Detected Microsoft MSRC URL - Attempting Playwright rendering" -Level "INFO"

        $startTime = Get-Date
        $playwrightResult = Get-MSRCPageWithPlaywright -Url $Url

        if ($playwrightResult.Success) {
            Write-Log -Message "Successfully rendered MSRC page with Playwright" -Level "SUCCESS"
            $htmlContent = $playwrightResult.Content
            $fetchTime = (Get-Date) - $startTime

            # Continue with standard extraction using the rendered content
            # (The rest of the function will process this content normally)
        } elseif ($playwrightResult.RequiresPlaywright) {
            Write-Log -Message "Playwright not available - MSRC page will return minimal data" -Level "WARNING"
            Write-Log -Message "To fix: .\Install-Playwright.ps1" -Level "INFO"
            # Fall through to standard scraping (will get skeleton HTML)
        } else {
            Write-Log -Message "Playwright failed: $($playwrightResult.Error) - Falling back to standard scraping" -Level "WARNING"
            # Fall through to standard scraping
        }
    }

    # ==================== STANDARD SCRAPING ====================
    # For non-special URLs or fallback cases

    try {
        $startTime = Get-Date

        # If we don't already have content from Selenium, fetch it normally
        if (-not $htmlContent) {
            $pageResult = Get-WebPageContent -Url $Url -TimeoutSec 30 -Session $Session
            $htmlContent = $pageResult.Content
        } else {
            # Use session from parameter if we got content from Selenium
            $pageResult = @{ Session = $Session; StatusCode = 200 }
        }

        $fetchTime = (Get-Date) - $startTime

        # Handle 403 Forbidden specifically (anti-bot protection)
        if ($pageResult.StatusCode -eq 403) {
            Write-Log -Message "URL blocked by anti-bot protection - 403 Forbidden: $Url" -Level "WARNING"

            # Enhanced blocked URL handling
            $blockedMessage = "Blocked - 403 Forbidden - Anti-bot protection detected. " +
            "This URL requires manual review in a browser. " +
            "Consider using a different scraping approach or manual data entry."

            return @{
                Url                  = $Url
                Status               = 'Blocked'
                DownloadLinks        = ''
                ExtractedData        = $blockedMessage
                Error                = '403 Forbidden - Anti-bot protection'
                FetchTime            = $fetchTime.TotalSeconds
                Session              = $pageResult.Session
                RequiresManualReview = $true
            }
        }

        if (-not $htmlContent) {
            Write-Log -Message "Failed to fetch page content for URL: $Url" -Level "ERROR"
            return @{
                Url           = $Url
                Status        = 'Failed'
                DownloadLinks = ''
                ExtractedData = 'Failed to fetch page'
                Error         = 'No content returned'
                FetchTime     = $fetchTime.TotalSeconds
                Session       = $pageResult.Session
            }
        }

        Write-Log -Message "Successfully fetched page content (Size: $($htmlContent.Length) bytes, Time: $($fetchTime.TotalSeconds)s)" -Level "SUCCESS"

        # Extract download links
        $downloadStartTime = Get-Date
        $downloadLinks = Extract-DownloadLinks -HtmlContent $htmlContent -BaseUrl $Url
        $downloadExtractTime = (Get-Date) - $downloadStartTime

        Write-Log -Message "Extracted $($downloadLinks.Count) download links in $($downloadExtractTime.TotalSeconds)s" -Level "DEBUG"

        # Extract patch info
        $patchStartTime = Get-Date
        $patchInfo = Extract-PatchInfo -HtmlContent $htmlContent -Url $Url
        $patchExtractTime = (Get-Date) - $patchStartTime

        Write-Log -Message "Extracted patch info in $($patchExtractTime.TotalSeconds)s" -Level "DEBUG"

        # Merge any additional download links from patch info (e.g., MSRC catalog links)
        if ($patchInfo.DownloadLinks -and $patchInfo.DownloadLinks.Count -gt 0) {
            foreach ($link in $patchInfo.DownloadLinks) {
                if ($downloadLinks -notcontains $link) {
                    $downloadLinks += $link
                }
            }
            Write-Log -Message "Added $($patchInfo.DownloadLinks.Count) catalog links from patch info" -Level "DEBUG"
        }

        # Build extracted data summary with quality assessment
        $extractedParts = @()
        if ($patchInfo.PatchID) { $extractedParts += "Patch: $($patchInfo.PatchID)" }
        if ($patchInfo.FixVersion) { $extractedParts += "Fix: $($patchInfo.FixVersion)" }
        if ($patchInfo.AffectedVersions) { $extractedParts += "Affected: $($patchInfo.AffectedVersions)" }
        if ($patchInfo.Remediation) { $extractedParts += "Remediation: $($patchInfo.Remediation)" }

        $extractedData = if ($extractedParts.Count -gt 0) { $extractedParts -join ' | ' } else { 'No specific data extracted' }

        # Add quality indicator for MSRC pages
        if ($Url -like '*msrc.microsoft.com*' -and $extractedParts.Count -eq 0) {
            $extractedData = "MSRC page - minimal data extracted (may require JavaScript rendering)"
        }

        $totalTime = (Get-Date) - $startTime

        Write-Log -Message "Successfully scraped URL: $Url - Total time: $($totalTime.TotalSeconds)s, Links: $($downloadLinks.Count), Data parts: $($extractedParts.Count)" -Level "SUCCESS"

        return @{
            Url            = $Url
            Status         = 'Success'
            DownloadLinks  = ($downloadLinks -join ' | ')
            ExtractedData  = $extractedData
            Error          = $null
            FetchTime      = $fetchTime.TotalSeconds
            ExtractTime    = $patchExtractTime.TotalSeconds
            TotalTime      = $totalTime.TotalSeconds
            LinksFound     = $downloadLinks.Count
            DataPartsFound = $extractedParts.Count
            Session        = $pageResult.Session
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log -Message "Error scraping URL: $Url - $errorMessage" -Level "ERROR"
        return @{
            Url            = $Url
            Status         = 'Error'
            DownloadLinks  = ''
            ExtractedData  = "Error: $errorMessage"
            Error          = $errorMessage
            FetchTime      = 0
            ExtractTime    = 0
            TotalTime      = 0
            LinksFound     = 0
            DataPartsFound = 0
            Session        = $Session
        }
    } finally {
        # Small delay with jitter to be respectful to servers
        $delay = Get-Random -Minimum 500 -Maximum 1000
        Start-Sleep -Milliseconds $delay
    }
}

function Process-CsvFile {
    [CmdletBinding()]
    param(
        [string]$CsvPath,
        [System.Windows.Controls.ProgressBar]$ProgressBar,
        [System.Windows.Controls.TextBlock]$StatusText,
        [switch]$ForceRescrape
    )

    Write-Log -Message "Starting CSV processing: $CsvPath" -Level "INFO"

    # Check if already scraped (unless force is enabled)
    if (-not $ForceRescrape -and (Test-CsvAlreadyScraped -CsvPath $CsvPath)) {
        Write-Log -Message "CSV already scraped (ScrapedDate column exists). Skipping." -Level "WARNING"
        return @{
            Success        = $false
            Message        = "File already scraped. Enable 'Force re-scrape' option to override."
            AlreadyScraped = $true
        }
    }

    if ($ForceRescrape) {
        Write-Log -Message "Force re-scrape enabled - will process file regardless of existing ScrapedDate" -Level "INFO"
    }

    # Read CSV
    Write-Log -Message "Reading CSV file..." -Level "INFO"
    $csvData = Import-Csv -Path $CsvPath -Encoding UTF8

    if (-not $csvData -or $csvData.Count -eq 0) {
        Write-Log -Message "CSV file is empty or invalid" -Level "ERROR"
        return @{
            Success = $false
            Message = "CSV file is empty or invalid."
        }
    }

    Write-Log -Message "Found $($csvData.Count) rows in CSV file" -Level "INFO"

    # Extract unique URLs
    $allUrls = @()
    foreach ($row in $csvData) {
        if ($row.RefUrls -and $row.RefUrls -ne '') {
            $urls = $row.RefUrls -split '\s*\|\s*'
            $allUrls += $urls
        }
    }

    $uniqueUrls = $allUrls | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique
    Write-Log -Message "Found $($uniqueUrls.Count) unique URLs to scrape from $($allUrls.Count) total URLs" -Level "INFO"

    # Record start time for performance tracking
    $processStartTime = Get-Date

    # Create URL cache for scraped data
    $urlCache = @{}
    $currentUrl = 0

    # Create shared web session for cookie persistence
    $sharedSession = $null

    # Update progress
    if ($ProgressBar) {
        $ProgressBar.Maximum = $uniqueUrls.Count
        $ProgressBar.Value = 0
    }

    # Track blocked URLs for summary
    $blockedUrls = @()

    # Scrape each unique URL
    foreach ($url in $uniqueUrls) {
        $currentUrl++

        if ($StatusText) {
            $StatusText.Dispatcher.Invoke([Action] {
                    $StatusText.Text = "Scraping URL $currentUrl of $($uniqueUrls.Count)..."
                })
        }

        if ($ProgressBar) {
            $ProgressBar.Dispatcher.Invoke([Action] {
                    $ProgressBar.Value = $currentUrl
                })
        }

        Write-Host "  [$currentUrl/$($uniqueUrls.Count)] $url" -ForegroundColor Gray

        $result = Scrape-AdvisoryUrl -Url $url -Session $sharedSession -Verbose

        # Update shared session if one was returned
        if ($result.Session) {
            $sharedSession = $result.Session
        }

        # Track blocked URLs
        if ($result.Status -eq 'Blocked') {
            $blockedUrls += $url
        }

        $urlCache[$url] = $result
    }

    Write-Host "Scraping complete. Updating CSV..." -ForegroundColor Green

    # Add new columns to each row
    $enhancedData = @()
    foreach ($row in $csvData) {
        # Create new object with all original properties
        $newRow = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $newRow[$prop.Name] = $prop.Value
        }

        # Process URLs for this row
        $rowDownloadLinks = @()
        $rowExtractedData = @()
        $rowStatuses = @()

        if ($row.RefUrls -and $row.RefUrls -ne '') {
            $urls = $row.RefUrls -split '\s*\|\s*'
            foreach ($url in $urls) {
                if ($urlCache.ContainsKey($url)) {
                    $cached = $urlCache[$url]
                    if ($cached.DownloadLinks) { $rowDownloadLinks += $cached.DownloadLinks }
                    if ($cached.ExtractedData) { $rowExtractedData += $cached.ExtractedData }
                    $rowStatuses += $cached.Status
                }
            }
        }

        # Add new columns
        $newRow['DownloadLinks'] = ($rowDownloadLinks | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ' | '
        $newRow['ExtractedData'] = ($rowExtractedData | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ' | '
        $newRow['ScrapeStatus'] = ($rowStatuses -join ',')
        $newRow['ScrapedDate'] = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

        $enhancedData += [PSCustomObject]$newRow
    }

    # Create backup
    $backupPath = $CsvPath -replace '\.csv$', '_backup.csv'
    Copy-Item -Path $CsvPath -Destination $backupPath -Force
    Write-Host "Created backup: $backupPath" -ForegroundColor Yellow

    # Save enhanced CSV
    $enhancedData | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Enhanced CSV saved: $CsvPath" -ForegroundColor Green

    # Enhanced Statistics
    $successCount = ($urlCache.Values | Where-Object { $_.Status -eq 'Success' }).Count
    $failedCount = ($urlCache.Values | Where-Object { $_.Status -in @('Failed', 'Error') }).Count
    $blockedCount = ($urlCache.Values | Where-Object { $_.Status -eq 'Blocked' }).Count
    $emptyCount = ($urlCache.Values | Where-Object { $_.Status -eq 'Empty' }).Count
    $linksFound = ($urlCache.Values | Where-Object { $_.DownloadLinks -ne '' }).Count
    $dataExtracted = ($urlCache.Values | Where-Object { $_.ExtractedData -ne '' -and $_.ExtractedData -ne 'No specific data extracted' }).Count

    # Performance statistics
    $totalFetchTime = ($urlCache.Values | Where-Object { $_.FetchTime }).FetchTime | Measure-Object -Sum
    $totalExtractTime = ($urlCache.Values | Where-Object { $_.ExtractTime }).ExtractTime | Measure-Object -Sum
    $avgFetchTime = if ($successCount -gt 0) { [Math]::Round($totalFetchTime.Sum / $successCount, 2) } else { 0 }
    $avgExtractTime = if ($successCount -gt 0) { [Math]::Round($totalExtractTime.Sum / $successCount, 2) } else { 0 }

    # Error analysis
    $errorTypes = $urlCache.Values | Where-Object { $_.Error } | Group-Object { $_.Error.Split(':')[0] } | Sort-Object Count -Descending

    $stats = "`n" +
    "================================================================================`n" +
    "SCRAPING COMPLETED - DETAILED STATISTICS`n" +
    "================================================================================`n" +
    "Overall Results:`n" +
    "- Total unique URLs processed: $($uniqueUrls.Count)`n" +
    "- Successfully scraped: $successCount`n" +
    "- Failed: $failedCount`n" +
    "- Blocked - 403 anti-bot: $blockedCount`n" +
    "- Empty URLs: $emptyCount`n" +
    "- URLs with download links: $linksFound`n" +
    "- URLs with extracted data: $dataExtracted`n" +
    "- CSV rows updated: $($csvData.Count)`n" +
    "`n" +
    "Performance Metrics:`n" +
    "- Average fetch time per URL: $avgFetchTime seconds`n" +
    "- Average extraction time per URL: $avgExtractTime seconds`n" +
    "- Total processing time: $((Get-Date) - $processStartTime).TotalSeconds seconds`n" +
    "`n" +
    "Error Analysis:`n"

    if ($errorTypes.Count -gt 0) {
        $stats += ($errorTypes | ForEach-Object { "- $($_.Name): $($_.Count) occurrences" } | Out-String)
    } else {
        $stats += "- No errors recorded`n"
    }

    if ($blockedUrls.Count -gt 0) {
        $stats += "`nBlocked URLs (require manual review):`n" + ($blockedUrls | ForEach-Object { "- $_" } | Out-String)
    }

    $stats += "`n================================================================================`n"

    Write-Log -Message $stats -Level "INFO"

    # Log individual URL results for debugging
    Write-Log -Message "Individual URL Results:" -Level "DEBUG"
    foreach ($url in $uniqueUrls) {
        if ($urlCache.ContainsKey($url)) {
            $result = $urlCache[$url]
            Write-Log -Message "URL: $url | Status: $($result.Status) | Links: $($result.LinksFound) | Data: $($result.DataPartsFound) | Time: $($result.TotalTime)s" -Level "DEBUG"
        }
    }

    return @{
        Success             = $true
        Message             = $stats
        TotalUrls           = $uniqueUrls.Count
        SuccessCount        = $successCount
        FailedCount         = $failedCount
        BlockedCount        = $blockedCount
        BlockedUrls         = $blockedUrls
        EmptyCount          = $emptyCount
        LinksFound          = $linksFound
        DataExtracted       = $dataExtracted
        AvgFetchTime        = $avgFetchTime
        AvgExtractTime      = $avgExtractTime
        TotalProcessingTime = ((Get-Date) - $processStartTime).TotalSeconds
        ErrorTypes          = $errorTypes
    }
}

# -------------------- GUI --------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CVE Advisory Scraper" Height="320" Width="600"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="140"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <TextBlock Grid.Row="0" Grid.Column="0" VerticalAlignment="Center" Margin="0,0,8,0">Select CSV File</TextBlock>
    <ComboBox x:Name="CsvCombo" Grid.Row="0" Grid.Column="1" Height="26" />

    <TextBlock x:Name="FileInfoText" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2"
               Margin="0,8,0,0" TextWrapping="Wrap" Foreground="Gray"/>

    <TextBlock Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,12,0,4">
      <Run FontWeight="Bold">Features:</Run>
    </TextBlock>

    <TextBlock Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,0" TextWrapping="Wrap">
      • Scrapes advisory URLs from RefUrls column
      <LineBreak/>
      • Extracts download links, patch IDs, and remediation info
      <LineBreak/>
      • MSRC dynamic page fallback via API
      <LineBreak/>
      • Session-based requests for anti-bot protection
      <LineBreak/>
      • Creates backup and detailed log files
    </TextBlock>

    <CheckBox x:Name="ForceRescrapeChk" Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2"
              Margin="0,12,0,0" Content="Force re-scrape (ignore existing ScrapedDate)"/>

    <ProgressBar x:Name="ProgressBar" Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2"
                 Height="20" Margin="0,12,0,0" Minimum="0" Maximum="100" Value="0"/>

    <TextBlock x:Name="StatusText" Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2"
               HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="11" Foreground="White"/>

    <StackPanel Grid.Row="6" Grid.Column="1" Orientation="Horizontal"
                HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,16,0,0">
      <Button x:Name="RefreshButton" Content="Refresh List" Width="100" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="ScrapeButton" Content="Scrape" Width="96" Height="28" Margin="0,0,8,0"/>
      <Button x:Name="CancelButton" Content="Close" Width="96" Height="28"/>
    </StackPanel>
  </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$csvCombo = $window.FindName('CsvCombo')
$fileInfoText = $window.FindName('FileInfoText')
$forceRescrapeChk = $window.FindName('ForceRescrapeChk')
$progressBar = $window.FindName('ProgressBar')
$statusText = $window.FindName('StatusText')
$refreshButton = $window.FindName('RefreshButton')
$scrapeButton = $window.FindName('ScrapeButton')
$cancelButton = $window.FindName('CancelButton')

# -------------------- Populate CSV list --------------------
function Refresh-CsvList {
    $csvCombo.Items.Clear()
    $csvFiles = Get-CsvFiles

    if ($csvFiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No CSV files found in 'out' directory.", "No Files")
        return
    }

    foreach ($file in $csvFiles) {
        [void]$csvCombo.Items.Add($file.Name)
    }

    $csvCombo.SelectedIndex = 0
}

# Update file info when selection changes
$csvCombo.Add_SelectionChanged({
        if ($csvCombo.SelectedItem) {
            $selectedFile = Join-Path $OutDir $csvCombo.SelectedItem
            if (Test-Path $selectedFile) {
                $fileInfo = Get-Item $selectedFile
                $csvData = Import-Csv -Path $selectedFile -Encoding UTF8
                $isScraped = Test-CsvAlreadyScraped -CsvPath $selectedFile

                $scrapedStatus = if ($isScraped) { "Already scraped" } else { "Not yet scraped" }
                $fileInfoText.Text = "File: $($fileInfo.Name) | Size: $([Math]::Round($fileInfo.Length/1KB, 2)) KB | Rows: $($csvData.Count) | Status: $scrapedStatus"

                if ($isScraped) {
                    $fileInfoText.Foreground = "Green"
                } else {
                    $fileInfoText.Foreground = "Gray"
                }
            }
        }
    })

# Initial population
Refresh-CsvList

# -------------------- Button Handlers --------------------
$refreshButton.Add_Click({
        Refresh-CsvList
        [System.Windows.MessageBox]::Show("CSV file list refreshed.", "Refresh")
    })

$scrapeButton.Add_Click({
        if (-not $csvCombo.SelectedItem) {
            [System.Windows.MessageBox]::Show("Please select a CSV file first.", "Validation")
            return
        }

        $selectedFile = Join-Path $OutDir $csvCombo.SelectedItem

        # Pre-check: Count unique URLs before starting
        try {
            $csvData = Import-Csv -Path $selectedFile -Encoding UTF8

            # Count unique URLs
            $allUrls = @()
            foreach ($row in $csvData) {
                if ($row.RefUrls -and $row.RefUrls -ne '') {
                    $urls = $row.RefUrls -split '\s*\|\s*'
                    $allUrls += $urls
                }
            }
            $uniqueUrls = $allUrls | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique
            $urlCount = $uniqueUrls.Count

            # Show warning if more than 50 URLs
            if ($urlCount -gt 50) {
                $estimatedTime = [Math]::Ceiling($urlCount * 0.5 / 60)  # ~0.5 seconds per URL
                $warningMessage = "This CSV file contains $urlCount unique URLs to scrape.`n`nEstimated time: ~$estimatedTime minute(s)`n`nThis operation may take a while and will:`n• Make $urlCount web requests`n• Parse HTML content from each advisory page`n• Extract download links and patch information`n`nDo you want to proceed?"

                $response = [System.Windows.MessageBox]::Show(
                    $warningMessage,
                    "Large Scraping Operation",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Warning
                )

                if ($response -eq [System.Windows.MessageBoxResult]::No) {
                    Write-Host "Scraping cancelled by user." -ForegroundColor Yellow
                    return
                }
            }
        } catch {
            [System.Windows.MessageBox]::Show(
                "Failed to read CSV file:`n`n$($_.Exception.Message)",
                "Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }

        try {
            $window.Cursor = 'Wait'
            $scrapeButton.Content = "Processing..."
            $scrapeButton.IsEnabled = $false
            $progressBar.Value = 0
            $statusText.Text = "Initializing..."

            # Initialize log file
            $Global:LogFile = Initialize-LogFile -LogDir $OutDir
            Write-Log -Message "Starting scraping operation for file: $selectedFile" -Level "INFO"

            # Check force re-scrape option
            $forceRescrape = [bool]$forceRescrapeChk.IsChecked
            if ($forceRescrape) {
                Write-Log -Message "Force re-scrape option enabled" -Level "INFO"
            }

            # Process the CSV
            $result = Process-CsvFile -CsvPath $selectedFile -ProgressBar $progressBar -StatusText $statusText -ForceRescrape:$forceRescrape

            if ($result.AlreadyScraped) {
                [System.Windows.MessageBox]::Show(
                    $result.Message,
                    "Already Scraped",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            } elseif ($result.Success) {
                $logFileName = Split-Path $Global:LogFile -Leaf

                # Build summary message with blocked URLs if any
                $summaryMessage = "Scraping completed successfully!`n`n$($result.Message)`n`nFiles created:`n- Backup: $($selectedFile -replace '\.csv$', '_backup.csv')`n- Log file: $logFileName"

                if ($result.BlockedUrls -and $result.BlockedUrls.Count -gt 0) {
                    $summaryMessage += "`n`n⚠ BLOCKED URLS (require manual review):`n"
                    foreach ($blockedUrl in $result.BlockedUrls) {
                        $summaryMessage += "• $blockedUrl`n"
                    }
                    $summaryMessage += "`nThese URLs were blocked by anti-bot protection - 403 Forbidden.`nConsider visiting them manually in a browser."
                }

                [System.Windows.MessageBox]::Show(
                    $summaryMessage,
                    "Success",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )

                # Refresh the file info to show updated status
                if ($csvCombo.SelectedItem) {
                    $fileInfo = Get-Item $selectedFile
                    $csvData = Import-Csv -Path $selectedFile -Encoding UTF8
                    $isScraped = Test-CsvAlreadyScraped -CsvPath $selectedFile

                    $scrapedStatus = if ($isScraped) { "Already scraped" } else { "Not yet scraped" }
                    $fileInfoText.Text = "File: $($fileInfo.Name) | Size: $([Math]::Round($fileInfo.Length/1KB, 2)) KB | Rows: $($csvData.Count) | Status: $scrapedStatus"

                    if ($isScraped) {
                        $fileInfoText.Foreground = "Green"
                    } else {
                        $fileInfoText.Foreground = "Gray"
                    }
                }
            } else {
                [System.Windows.MessageBox]::Show(
                    "Failed to process CSV:`n`n$($result.Message)",
                    "Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            }
        } catch {
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            [System.Windows.MessageBox]::Show(
                "An error occurred:`n`n$($_.Exception.Message)",
                "Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        } finally {
            $window.Cursor = 'Arrow'
            $scrapeButton.Content = "Scrape"
            $scrapeButton.IsEnabled = $true
            $statusText.Text = ""
            $progressBar.Value = 0
        }
    })

$cancelButton.Add_Click({ $window.Close() })

# -------------------- Show Window --------------------
Refresh-CsvList
[void]$window.ShowDialog()
