<#
.SYNOPSIS
    CVExcel - Main entry point for CVExcel Multi-Tool CVE Processing Suite

.DESCRIPTION
    Unified entry point for CVE processing tools with three modes:
    1. GUI Mode: When run without parameters, launches the GUI interface
    2. Direct URL Scraping: When provided with a URL parameter, scrapes the URL
    3. Tool Selection: When provided with a Tool parameter, launches specific tab

.AUTHOR
    Columbia Cloudworks LLC
    https://github.com/Columbia-Cloudworks-LLC/CVExcel

.LICENSE
    MIT License

.PARAMETER Tool
    Optional: Specify which tool to run directly (nvd, scraper, gui)
    If not provided, launches the unified GUI.

.PARAMETER Url
    Optional: Direct URL to scrape. When provided, runs in command-line mode
    and scrapes the specified advisory URL for CVE information.

.EXAMPLE
    .\CVExcel.ps1
    Launches the unified GUI with all tools.

.EXAMPLE
    .\CVExcel.ps1 -Tool nvd
    Launches directly to the NVD exporter tab.

.EXAMPLE
    .\CVExcel.ps1 -Url "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2023-28290"
    Scrapes the specified URL in command-line mode (legacy CVExpand functionality).

.NOTES
    IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.
    Rate Limits: 5 requests/30sec (public) or 50 requests/30sec (with API key)

    NOTE: CVExpand functionality has been merged into this script.
    Use -Url parameter for direct URL scraping (former CVExpand command-line mode).
#>

[CmdletBinding()]
param(
    [ValidateSet('nvd', 'scraper', 'gui')]
    [string]$Tool = 'gui',

    [string]$Url
)

# -------------------- Entry Point Logic --------------------

Write-Host "`n===============================================================================" -ForegroundColor Cyan
Write-Host "                          CVExcel - CVE Processing Suite" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan

# -------------------- Command-Line URL Scraping Mode (Legacy CVExpand) --------------------
if ($Url) {
    Write-Host "Running in command-line scraping mode..." -ForegroundColor Cyan
    Write-Host "Target URL: $Url" -ForegroundColor White
    Write-Host ""

    # Import common modules
    . "$PSScriptRoot\common\Logging.ps1"
    . "$PSScriptRoot\ui\PlaywrightWrapper.ps1"

    # Function to get web page with Playwright for JavaScript rendering
    function Get-WebPage {
        param([string]$Url)

        Write-Log "Fetching URL with Playwright: $Url" -Level "INFO"

        # Check if Playwright is available
        $playwrightAvailable = Test-PlaywrightAvailability
        if (-not $playwrightAvailable) {
            Write-Log "Playwright not available, falling back to standard HTTP request" -Level "WARNING"
            return Get-WebPageHTTP -Url $Url
        }

        try {
            # Initialize Playwright browser
            Write-Log "Initializing Playwright browser..." -Level "INFO"
            $initResult = New-PlaywrightBrowser -BrowserType chromium -TimeoutSeconds 30

            if (-not $initResult.Success) {
                Write-Log "Failed to initialize Playwright: $($initResult.Error)" -Level "ERROR"
                return Get-WebPageHTTP -Url $Url
            }

            Write-Log "Playwright browser initialized successfully" -Level "SUCCESS"

            # Navigate to page with extended wait for MSRC content
            $result = Invoke-PlaywrightNavigate -Url $Url -WaitSeconds 8

            if ($result.Success) {
                Write-Log "Successfully rendered page with Playwright - $($result.Size) bytes" -Level "SUCCESS"
                return @{
                    Success    = $true
                    Content    = $result.Content
                    StatusCode = $result.StatusCode
                    Method     = "Playwright"
                }
            } else {
                Write-Log "Playwright navigation failed: $($result.Error)" -Level "WARNING"
                return Get-WebPageHTTP -Url $Url
            }
        } catch {
            Write-Log "Playwright error: $($_.Exception.Message)" -Level "ERROR"
            return Get-WebPageHTTP -Url $Url
        } finally {
            # Always cleanup browser
            Close-PlaywrightBrowser
            Write-Log "Playwright browser closed" -Level "DEBUG"
        }
    }

    # Fallback HTTP request function
    function Get-WebPageHTTP {
        param([string]$Url)

        Write-Log "Fetching URL with HTTP: $Url" -Level "INFO"

        $headers = @{
            'User-Agent'                = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            'Accept'                    = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8'
            'Accept-Language'           = 'en-US,en;q=0.9'
            'Accept-Encoding'           = 'gzip, deflate, br'
            'DNT'                       = '1'
            'Upgrade-Insecure-Requests' = '1'
        }

        try {
            $response = Invoke-WebRequest -Uri $Url -Headers $headers -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
            Write-Log "Successfully fetched page with HTTP - Status: $($response.StatusCode), Size: $($response.Content.Length) bytes" -Level "SUCCESS"
            return @{
                Success    = $true
                Content    = $response.Content
                StatusCode = $response.StatusCode
                Method     = "HTTP"
            }
        } catch {
            Write-Log "Failed to fetch page with HTTP: $($_.Exception.Message)" -Level "ERROR"
            return @{
                Success = $false
                Error   = $_.Exception.Message
                Method  = "HTTP"
            }
        }
    }

    # Enhanced data extraction function for advisory pages
    function Get-AdvisoryData {
        param(
            [string]$HtmlContent,
            [string]$Url
        )

        Write-Log "Extracting data from advisory page..." -Level "INFO"

        $result = @{
            PatchID          = $null
            AffectedVersions = $null
            Remediation      = $null
            DownloadLinks    = @()
            BuildNumber      = $null
            Product          = $null
            ReleaseDate      = $null
            Severity         = $null
            Impact           = $null
        }

        # Extract CVE ID from URL
        if ($Url -match 'CVE-(\d{4}-\d+)') {
            $result.PatchID = "CVE-$($matches[1])"
            Write-Log "Extracted CVE ID: $($result.PatchID)" -Level "SUCCESS"
        }

        # Extract product information
        if ($HtmlContent -match 'Microsoft Remote Desktop') {
            $result.Product = "Microsoft Remote Desktop"
            Write-Log "Found product: $($result.Product)" -Level "SUCCESS"
        } elseif ($HtmlContent -match 'Microsoft Windows|Windows \d+') {
            $result.Product = "Microsoft Windows"
            Write-Log "Found product: $($result.Product)" -Level "SUCCESS"
        }

        # Extract build number
        if ($HtmlContent -match '(\d+\.\d+\.\d+\.\d+)') {
            $result.BuildNumber = $matches[1]
            Write-Log "Found build number: $($result.BuildNumber)" -Level "SUCCESS"
        }

        # Extract release date
        if ($HtmlContent -match 'Released:\s*([^<]+)') {
            $result.ReleaseDate = $matches[1].Trim()
            Write-Log "Found release date: $($result.ReleaseDate)" -Level "SUCCESS"
        }

        # Extract severity
        if ($HtmlContent -match 'Max Severity.*?(Critical|Important|Moderate|Low)') {
            $result.Severity = $matches[1]
            Write-Log "Found severity: $($result.Severity)" -Level "SUCCESS"
        }

        # Extract impact
        if ($HtmlContent -match 'Impact.*?(Information Disclosure|Remote Code Execution|Elevation of Privilege|Denial of Service)') {
            $result.Impact = $matches[1]
            Write-Log "Found impact: $($result.Impact)" -Level "SUCCESS"
        }

        # Extract download links - look for go.microsoft.com links
        $downloadMatches = [regex]::Matches($HtmlContent, 'https://go\.microsoft\.com/fwlink/\?[^"''<>\s]*')
        foreach ($match in $downloadMatches) {
            $link = $match.Value
            if ($result.DownloadLinks -notcontains $link) {
                $result.DownloadLinks += $link
                Write-Log "Found download link: $link" -Level "SUCCESS"
            }
        }

        # Extract learn.microsoft.com links (release notes)
        $learnMatches = [regex]::Matches($HtmlContent, 'https://learn\.microsoft\.com/[^"''<>\s]*')
        foreach ($match in $learnMatches) {
            $link = $match.Value
            if ($result.DownloadLinks -notcontains $link) {
                $result.DownloadLinks += $link
                Write-Log "Found release notes link: $link" -Level "SUCCESS"
            }
        }

        # Extract KB articles
        $kbMatches = [regex]::Matches($HtmlContent, 'KB(\d{6,7})')
        if ($kbMatches.Count -gt 0) {
            $kbList = @()
            foreach ($match in $kbMatches) {
                $kbNum = $match.Groups[1].Value
                $kb = "KB$kbNum"
                if ($kbList -notcontains $kb) {
                    $kbList += $kb
                    # Generate catalog link
                    $catalogLink = "https://catalog.update.microsoft.com/v7/site/Search.aspx?q=KB$kbNum"
                    if ($result.DownloadLinks -notcontains $catalogLink) {
                        $result.DownloadLinks += $catalogLink
                    }
                }
            }
            Write-Log "Found KB articles: $($kbList -join ', ')" -Level "SUCCESS"
        }

        # Extract affected versions
        if ($HtmlContent -match 'Affected [Pp]roducts?[\s:]+([^\r\n<]+)') {
            $result.AffectedVersions = $matches[1].Trim()
            Write-Log "Found affected versions: $($result.AffectedVersions)" -Level "SUCCESS"
        }

        # Look for existing catalog links
        $catalogMatches = [regex]::Matches($HtmlContent, 'catalog\.update\.microsoft\.com[^"''<>\s]*')
        foreach ($match in $catalogMatches) {
            $link = "https://$($match.Value)"
            if ($result.DownloadLinks -notcontains $link) {
                $result.DownloadLinks += $link
            }
        }

        return $result
    }

    # Main scraping execution
    Write-Log "=== CVExcel - Command Line URL Scraping ===" -Level "INFO"
    Write-Log "Target URL: $Url" -Level "INFO"

    # Fetch the page
    $pageResult = Get-WebPage -Url $Url

    if (-not $pageResult.Success) {
        Write-Log "Failed to fetch page. Exiting." -Level "ERROR"
        exit 1
    }

    # Extract data
    $extractedData = Get-AdvisoryData -HtmlContent $pageResult.Content -Url $Url

    # Display results
    Write-Log "=== EXTRACTION RESULTS ===" -Level "INFO"
    Write-Log "Method Used: $($pageResult.Method)" -Level "INFO"
    Write-Log "CVE ID: $($extractedData.PatchID)" -Level "INFO"
    Write-Log "Product: $($extractedData.Product)" -Level "INFO"
    Write-Log "Build Number: $($extractedData.BuildNumber)" -Level "INFO"
    Write-Log "Release Date: $($extractedData.ReleaseDate)" -Level "INFO"
    Write-Log "Severity: $($extractedData.Severity)" -Level "INFO"
    Write-Log "Impact: $($extractedData.Impact)" -Level "INFO"
    Write-Log "Affected Versions: $($extractedData.AffectedVersions)" -Level "INFO"
    Write-Log "Download Links:" -Level "INFO"
    foreach ($link in $extractedData.DownloadLinks) {
        Write-Log "  - $link" -Level "INFO"
    }

    # Save results to file for inspection
    $outputFile = "expand_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $htmlFile = "msrc_page_content_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $output = @"
CVExcel URL Scraping Results - $(Get-Date)
URL: $Url
Method: $($pageResult.Method)
Status Code: $($pageResult.StatusCode)
Content Size: $($pageResult.Content.Length) bytes

EXTRACTED DATA:
CVE ID: $($extractedData.PatchID)
Product: $($extractedData.Product)
Build Number: $($extractedData.BuildNumber)
Release Date: $($extractedData.ReleaseDate)
Severity: $($extractedData.Severity)
Impact: $($extractedData.Impact)
Affected Versions: $($extractedData.AffectedVersions)
Download Links:
$($extractedData.DownloadLinks | ForEach-Object { "  - $_" } | Out-String)

RAW HTML CONTENT (first 2000 chars):
$($pageResult.Content.Substring(0, [Math]::Min(2000, $pageResult.Content.Length)))
"@

    $output | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Log "Results saved to: $outputFile" -Level "SUCCESS"

    # Also save full HTML content for detailed inspection
    $pageResult.Content | Out-File -FilePath $htmlFile -Encoding UTF8
    Write-Log "Full HTML content saved to: $htmlFile" -Level "SUCCESS"

    Write-Log "=== SCRAPING COMPLETE ===" -Level "SUCCESS"
    exit 0
}

# -------------------- GUI Launch Mode --------------------
# Check if we should launch GUI
if ($Tool -eq 'gui' -or $Tool -eq 'nvd' -or $Tool -eq 'scraper') {
    Write-Host "Launching unified GUI..." -ForegroundColor Cyan

    $guiPath = Join-Path $PSScriptRoot "ui\CVExcel-GUI.ps1"

    if (Test-Path $guiPath) {
        try {
            Write-Host "Starting CVExcel unified GUI..." -ForegroundColor Green
            & $guiPath
        } catch {
            Write-Host "Failed to launch GUI: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Error details:" -ForegroundColor Yellow
            Write-Host $_.Exception -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "GUI file not found at: $guiPath" -ForegroundColor Red
        Write-Host "Please ensure the ui folder exists and contains CVExcel-GUI.ps1" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "Invalid tool specified: $Tool" -ForegroundColor Red
    Write-Host "Valid options: nvd, scraper, gui" -ForegroundColor Yellow
    exit 1
}
