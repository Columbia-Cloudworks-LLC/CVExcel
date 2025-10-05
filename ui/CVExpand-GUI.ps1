<#
.SYNOPSIS
    CVExpand-GUI - Enhanced CVE Advisory Scraper with Proven Playwright Integration

.DESCRIPTION
    A comprehensive CVE advisory scraper that combines CVExpand's proven scraping functionality
    with CVScrape's user-friendly GUI interface. Uses Playwright for JavaScript rendering
    with HTTP fallback for maximum reliability.

.FEATURES
    - Proven Playwright integration for JavaScript-heavy pages (MSRC, etc.)
    - HTTP fallback when Playwright unavailable
    - GUI interface for CSV file selection and progress tracking
    - Batch processing of advisory URLs from CSV files
    - Comprehensive logging and error handling
    - Automatic backup creation and data validation
    - Works out of the box with minimal setup

.PARAMETER None
    This script launches a GUI interface for interactive use.

.EXAMPLE
    .\CVExpand-GUI.ps1
    Launches the GUI interface for CVE advisory scraping.
#>

# Import required assemblies for GUI
Add-Type -AssemblyName PresentationFramework, PresentationCore, System.Web

# -------------------- Import Vendor Modules --------------------
# Load vendor-specific scraping modules for enhanced extraction
# Vendors folder is in root directory (one level up from ui/)
$rootDir = Split-Path $PSScriptRoot -Parent
. "$rootDir\vendors\BaseVendor.ps1"
. "$rootDir\vendors\GenericVendor.ps1"
. "$rootDir\vendors\GitHubVendor.ps1"
. "$rootDir\vendors\MicrosoftVendor.ps1"
. "$rootDir\vendors\IBMVendor.ps1"
. "$rootDir\vendors\ZDIVendor.ps1"
. "$rootDir\vendors\VendorManager.ps1"

# -------------------- Paths --------------------
$Root = Get-Location
$OutDir = Join-Path $Root "out"
if (-not (Test-Path $OutDir)) {
    Write-Error "Missing 'out' directory. Please ensure the 'out' directory exists."
    return
}

# -------------------- Logging Infrastructure --------------------
$Global:LogFile = $null
$Global:VendorManager = $null

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
CVE Advisory Scraper Log (CVExpand-GUI Version)
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

# -------------------- Import Playwright Wrapper --------------------
# PlaywrightWrapper.ps1 is in the same directory (ui/)
. "$PSScriptRoot\PlaywrightWrapper.ps1"

# -------------------- Import Dependency Manager --------------------
# DependencyManager.ps1 is in the same directory (ui/)
. "$PSScriptRoot\DependencyManager.ps1"

# -------------------- Core Scraping Functions (from CVExpand) --------------------

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

function Get-WebPage {
    <#
    .SYNOPSIS
        Fetches web page content using Playwright with HTTP fallback.

    .DESCRIPTION
        Uses Playwright for JavaScript rendering when available, falls back to HTTP
        requests when Playwright is not available or fails.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    Write-Log -Message "Fetching URL: $Url" -Level "INFO"

    # Check if Playwright is available
    $playwrightAvailable = Test-PlaywrightAvailability
    if (-not $playwrightAvailable) {
        Write-Log -Message "Playwright not available, falling back to HTTP request" -Level "WARNING"
        return Get-WebPageHTTP -Url $Url
    }

    try {
        # Initialize Playwright browser
        Write-Log -Message "Initializing Playwright browser..." -Level "INFO"
        $initResult = New-PlaywrightBrowser -BrowserType chromium -TimeoutSeconds 30

        if (-not $initResult.Success) {
            Write-Log -Message "Failed to initialize Playwright: $($initResult.Error)" -Level "ERROR"
            return Get-WebPageHTTP -Url $Url
        }

        Write-Log -Message "Playwright browser initialized successfully" -Level "SUCCESS"

        # Navigate to page with extended wait for dynamic content
        $result = Invoke-PlaywrightNavigate -Url $Url -WaitSeconds 8

        if ($result.Success) {
            Write-Log -Message "Successfully rendered page with Playwright - $($result.Size) bytes" -Level "SUCCESS"
            return @{
                Success    = $true
                Content    = $result.Content
                StatusCode = $result.StatusCode
                Method     = "Playwright"
            }
        } else {
            Write-Log -Message "Playwright navigation failed: $($result.Error)" -Level "WARNING"
            return Get-WebPageHTTP -Url $Url
        }
    } catch {
        Write-Log -Message "Playwright error: $($_.Exception.Message)" -Level "ERROR"
        return Get-WebPageHTTP -Url $Url
    } finally {
        # Always cleanup browser
        Close-PlaywrightBrowser
        Write-Log -Message "Playwright browser closed" -Level "DEBUG"
    }
}

function Get-WebPageHTTP {
    <#
    .SYNOPSIS
        Fallback HTTP request function when Playwright is not available.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    Write-Log -Message "Fetching URL with HTTP: $Url" -Level "INFO"

    $headers = @{
        'User-Agent'                = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        'Accept'                    = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8'
        'Accept-Language'           = 'en-US,en;q=0.9'
        'Accept-Encoding'           = 'gzip, deflate, br'
        'DNT'                       = '1'
        'Upgrade-Insecure-Requests' = '1'
        'Sec-Fetch-Dest'            = 'document'
        'Sec-Fetch-Mode'            = 'navigate'
        'Sec-Fetch-Site'            = 'none'
        'Cache-Control'             = 'max-age=0'
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -Headers $headers -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
        Write-Log -Message "Successfully fetched page with HTTP - Status: $($response.StatusCode), Size: $($response.Content.Length) bytes" -Level "SUCCESS"
        return @{
            Success    = $true
            Content    = $response.Content
            StatusCode = $response.StatusCode
            Method     = "HTTP"
        }
    } catch {
        Write-Log -Message "Failed to fetch page with HTTP: $($_.Exception.Message)" -Level "ERROR"
        return @{
            Success = $false
            Error   = $_.Exception.Message
            Method  = "HTTP"
        }
    }
}

function Extract-MSRCData {
    <#
    .SYNOPSIS
        Enhanced data extraction function using vendor-specific modules.

    .DESCRIPTION
        Routes URLs to appropriate vendor modules (Microsoft, GitHub, IBM, etc.)
        for specialized extraction including KB articles, download links, and patches.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$HtmlContent,
        [Parameter(Mandatory)]
        [string]$Url
    )

    Write-Log -Message "Extracting data from advisory page using vendor modules..." -Level "INFO"

    # Initialize result structure
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
        VendorUsed       = "Generic"
    }

    # Initialize VendorManager if not already done
    if ($null -eq $Global:VendorManager) {
        try {
            $Global:VendorManager = [VendorManager]::new()
            Write-Log -Message "VendorManager initialized successfully" -Level "DEBUG"
        } catch {
            Write-Log -Message "Failed to initialize VendorManager: $($_.Exception.Message). Using generic extraction." -Level "WARNING"
            $Global:VendorManager = $null
        }
    }

    # Use VendorManager for extraction if available
    if ($null -ne $Global:VendorManager) {
        try {
            $vendorResult = $Global:VendorManager.ExtractData($HtmlContent, $Url)

            # Log vendor used
            if ($vendorResult.VendorUsed) {
                Write-Log -Message "Using $($vendorResult.VendorUsed) vendor for extraction" -Level "INFO"
            }

            # Merge vendor results into result structure
            if ($vendorResult.PatchID) { $result.PatchID = $vendorResult.PatchID }
            if ($vendorResult.AffectedVersions) { $result.AffectedVersions = $vendorResult.AffectedVersions }
            if ($vendorResult.Remediation) { $result.Remediation = $vendorResult.Remediation }
            if ($vendorResult.FixVersion) { $result.BuildNumber = $vendorResult.FixVersion }
            if ($vendorResult.VendorUsed) { $result.VendorUsed = $vendorResult.VendorUsed }

            # Merge download links
            if ($vendorResult.DownloadLinks -and $vendorResult.DownloadLinks.Count -gt 0) {
                foreach ($link in $vendorResult.DownloadLinks) {
                    if ($result.DownloadLinks -notcontains $link) {
                        $result.DownloadLinks += $link
                    }
                }
                Write-Log -Message "Vendor extracted $($vendorResult.DownloadLinks.Count) download link(s)" -Level "SUCCESS"
            }
        } catch {
            Write-Log -Message "Vendor extraction error: $($_.Exception.Message)" -Level "WARNING"
        }
    }

    # Supplement with generic extraction patterns

    # Extract CVE ID from URL if not already found
    if (-not $result.PatchID -and $Url -match 'CVE-(\d{4}-\d+)') {
        $result.PatchID = "CVE-$($matches[1])"
        Write-Log -Message "Extracted CVE ID: $($result.PatchID)" -Level "SUCCESS"
    }

    # Extract product information
    if (-not $result.Product) {
        if ($HtmlContent -match 'Microsoft Remote Desktop') {
            $result.Product = "Microsoft Remote Desktop"
            Write-Log -Message "Found product: $($result.Product)" -Level "SUCCESS"
        } elseif ($HtmlContent -match 'Microsoft Windows|Windows \d+') {
            $result.Product = "Microsoft Windows"
            Write-Log -Message "Found product: $($result.Product)" -Level "SUCCESS"
        }
    }

    # Extract build number if not already found
    if (-not $result.BuildNumber -and $HtmlContent -match '(\d+\.\d+\.\d+\.\d+)') {
        $result.BuildNumber = $matches[1]
        Write-Log -Message "Found build number: $($result.BuildNumber)" -Level "SUCCESS"
    }

    # Extract release date
    if (-not $result.ReleaseDate -and $HtmlContent -match 'Released:\s*([^<]+)') {
        $result.ReleaseDate = $matches[1].Trim()
        Write-Log -Message "Found release date: $($result.ReleaseDate)" -Level "SUCCESS"
    }

    # Extract severity
    if (-not $result.Severity -and $HtmlContent -match 'Max Severity.*?(Critical|Important|Moderate|Low)') {
        $result.Severity = $matches[1]
        Write-Log -Message "Found severity: $($result.Severity)" -Level "SUCCESS"
    }

    # Extract impact
    if (-not $result.Impact -and $HtmlContent -match 'Impact.*?(Information Disclosure|Remote Code Execution|Elevation of Privilege|Denial of Service)') {
        $result.Impact = $matches[1]
        Write-Log -Message "Found impact: $($result.Impact)" -Level "SUCCESS"
    }

    # Extract go.microsoft.com download links
    $downloadMatches = [regex]::Matches($HtmlContent, 'https://go\.microsoft\.com/fwlink/\?[^"''<>\s]*')
    foreach ($match in $downloadMatches) {
        $link = $match.Value
        if ($result.DownloadLinks -notcontains $link) {
            $result.DownloadLinks += $link
            Write-Log -Message "Found download link: $link" -Level "SUCCESS"
        }
    }

    # Extract learn.microsoft.com links (release notes)
    $learnMatches = [regex]::Matches($HtmlContent, 'https://learn\.microsoft\.com/[^"''<>\s]*')
    foreach ($match in $learnMatches) {
        $link = $match.Value
        if ($result.DownloadLinks -notcontains $link) {
            $result.DownloadLinks += $link
            Write-Log -Message "Found release notes link: $link" -Level "SUCCESS"
        }
    }

    return $result
}

# -------------------- CSV Processing Functions (from CVScrape) --------------------

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

function Scrape-AdvisoryUrl {
    <#
    .SYNOPSIS
        Scrapes a single advisory URL using CVExpand's proven methods.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    if (-not $Url -or $Url -eq '') {
        Write-Log -Message "Empty URL provided to Scrape-AdvisoryUrl" -Level "WARNING"
        return @{
            Url           = $Url
            Status        = 'Empty'
            DownloadLinks = ''
            ExtractedData = ''
            Error         = 'Empty URL'
        }
    }

    Write-Log -Message "Starting to scrape advisory URL: $Url" -Level "INFO"

    try {
        $startTime = Get-Date

        # Fetch the page using CVExpand's proven method
        $pageResult = Get-WebPage -Url $Url
        $fetchTime = (Get-Date) - $startTime

        if (-not $pageResult.Success) {
            Write-Log -Message "Failed to fetch page content for URL: $Url" -Level "ERROR"
            return @{
                Url            = $Url
                Status         = 'Failed'
                DownloadLinks  = ''
                ExtractedData  = 'Failed to fetch page'
                Error          = $pageResult.Error
                FetchTime      = $fetchTime.TotalSeconds
                TotalTime      = $fetchTime.TotalSeconds
                LinksFound     = 0
                DataPartsFound = 0
            }
        }

        Write-Log -Message "Successfully fetched page content (Size: $($pageResult.Content.Length) bytes, Time: $($fetchTime.TotalSeconds)s)" -Level "SUCCESS"

        # Extract data using CVExpand's proven extraction
        $extractStartTime = Get-Date
        $extractedData = Extract-MSRCData -HtmlContent $pageResult.Content -Url $Url
        $extractTime = (Get-Date) - $extractStartTime

        # Build extracted data summary
        $extractedParts = @()
        if ($extractedData.PatchID) { $extractedParts += "Patch: $($extractedData.PatchID)" }
        if ($extractedData.Product) { $extractedParts += "Product: $($extractedData.Product)" }
        if ($extractedData.BuildNumber) { $extractedParts += "Build: $($extractedData.BuildNumber)" }
        if ($extractedData.AffectedVersions) { $extractedParts += "Affected: $($extractedData.AffectedVersions)" }
        if ($extractedData.Severity) { $extractedParts += "Severity: $($extractedData.Severity)" }
        if ($extractedData.Impact) { $extractedParts += "Impact: $($extractedData.Impact)" }

        $extractedDataSummary = if ($extractedParts.Count -gt 0) { $extractedParts -join ' | ' } else { 'No specific data extracted' }

        $totalTime = (Get-Date) - $startTime

        Write-Log -Message "Successfully scraped URL: $Url - Total time: $($totalTime.TotalSeconds)s, Links: $($extractedData.DownloadLinks.Count), Data parts: $($extractedParts.Count)" -Level "SUCCESS"

        return @{
            Url            = $Url
            Status         = 'Success'
            DownloadLinks  = ($extractedData.DownloadLinks -join ' | ')
            ExtractedData  = $extractedDataSummary
            Error          = $null
            FetchTime      = $fetchTime.TotalSeconds
            ExtractTime    = $extractTime.TotalSeconds
            TotalTime      = $totalTime.TotalSeconds
            LinksFound     = $extractedData.DownloadLinks.Count
            DataPartsFound = $extractedParts.Count
            Method         = $pageResult.Method
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
        }
    } finally {
        # Small delay with jitter to be respectful to servers
        $delay = Get-Random -Minimum 500 -Maximum 1000
        Start-Sleep -Milliseconds $delay
    }
}

function Process-CsvFile {
    <#
    .SYNOPSIS
        Processes a CSV file by scraping all advisory URLs and updating with extracted data.
    #>
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

    # Update progress
    if ($ProgressBar) {
        $ProgressBar.Maximum = $uniqueUrls.Count
        $ProgressBar.Value = 0
    }

    # Track statistics
    $stats = @{
        TotalUrls     = $uniqueUrls.Count
        SuccessCount  = 0
        FailedCount   = 0
        EmptyCount    = 0
        LinksFound    = 0
        DataExtracted = 0
        ErrorTypes    = @{}
    }

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

        # Scrape using CVExpand's proven method
        $result = Scrape-AdvisoryUrl -Url $url

        # Update statistics
        switch ($result.Status) {
            'Success' { $stats.SuccessCount++ }
            'Failed' { $stats.FailedCount++ }
            'Empty' { $stats.EmptyCount++ }
            default { $stats.FailedCount++ }
        }

        if ($result.LinksFound -gt 0) { $stats.LinksFound++ }
        if ($result.DataPartsFound -gt 0) { $stats.DataExtracted++ }

        # Track error types
        if ($result.Error) {
            $errorType = $result.Error.Split(':')[0]
            if ($stats.ErrorTypes.ContainsKey($errorType)) {
                $stats.ErrorTypes[$errorType]++
            } else {
                $stats.ErrorTypes[$errorType] = 1
            }
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

    # Calculate performance metrics
    $totalProcessingTime = ((Get-Date) - $processStartTime).TotalSeconds
    $avgTimePerUrl = if ($uniqueUrls.Count -gt 0) { [Math]::Round($totalProcessingTime / $uniqueUrls.Count, 2) } else { 0 }

    # Generate comprehensive statistics
    $statsMessage = @"
================================================================================
SCRAPING COMPLETED - ENHANCED STATISTICS
================================================================================
Overall Results:
- Total unique URLs processed: $($stats.TotalUrls)
- Successfully scraped: $($stats.SuccessCount)
- Failed: $($stats.FailedCount)
- Empty URLs: $($stats.EmptyCount)
- URLs with download links: $($stats.LinksFound)
- URLs with extracted data: $($stats.DataExtracted)
- CSV rows updated: $($csvData.Count)

Performance Metrics:
- Total processing time: $([Math]::Round($totalProcessingTime, 2)) seconds
- Average time per URL: $avgTimePerUrl seconds
- Playwright available: $(if (Test-PlaywrightAvailability) { "Yes" } else { "No (HTTP fallback used)" })

Error Analysis:
"@

    if ($stats.ErrorTypes.Count -gt 0) {
        $statsMessage += "`n"
        foreach ($errorType in $stats.ErrorTypes.GetEnumerator() | Sort-Object Value -Descending) {
            $statsMessage += "- $($errorType.Key): $($errorType.Value) occurrences`n"
        }
    } else {
        $statsMessage += "- No errors recorded`n"
    }

    $statsMessage += "`n================================================================================`n"

    Write-Log -Message $statsMessage -Level "INFO"

    # Log individual URL results for debugging
    Write-Log -Message "Individual URL Results:" -Level "DEBUG"
    foreach ($url in $uniqueUrls) {
        if ($urlCache.ContainsKey($url)) {
            $result = $urlCache[$url]
            Write-Log -Message "URL: $url | Status: $($result.Status) | Links: $($result.LinksFound) | Data: $($result.DataPartsFound) | Time: $($result.TotalTime)s | Method: $($result.Method)" -Level "DEBUG"
        }
    }

    return @{
        Success             = $true
        Message             = $statsMessage
        Stats               = $stats
        TotalProcessingTime = $totalProcessingTime
        AvgTimePerUrl       = $avgTimePerUrl
    }
}

# -------------------- GUI --------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CVE Advisory Scraper (CVExpand-GUI)" Height="400" Width="700"
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

    <TextBlock x:Name="PlaywrightStatusText" Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2"
               Margin="0,8,0,0" TextWrapping="Wrap" Foreground="Blue" FontSize="11"/>

    <TextBlock Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,12,0,4">
      <Run FontWeight="Bold">Enhanced Features:</Run>
    </TextBlock>

    <TextBlock Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,0" TextWrapping="Wrap">
      • Proven Playwright integration for JavaScript rendering
      <LineBreak/>
      • HTTP fallback when Playwright unavailable
      <LineBreak/>
      • Enhanced MSRC page extraction with download links
      <LineBreak/>
      • Comprehensive logging and error handling
      <LineBreak/>
      • Automatic backup creation and data validation
    </TextBlock>

    <CheckBox x:Name="ForceRescrapeChk" Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2"
              Margin="0,12,0,0" Content="Force re-scrape (ignore existing ScrapedDate)"/>

    <ProgressBar x:Name="ProgressBar" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="2"
                 Height="20" Margin="0,12,0,0" Minimum="0" Maximum="100" Value="0"/>

    <TextBlock x:Name="StatusText" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="2"
               HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="11" Foreground="White"/>

    <StackPanel Grid.Row="7" Grid.Column="1" Orientation="Horizontal"
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
$playwrightStatusText = $window.FindName('PlaywrightStatusText')
$forceRescrapeChk = $window.FindName('ForceRescrapeChk')
$progressBar = $window.FindName('ProgressBar')
$statusText = $window.FindName('StatusText')
$refreshButton = $window.FindName('RefreshButton')
$scrapeButton = $window.FindName('ScrapeButton')
$cancelButton = $window.FindName('CancelButton')

# -------------------- GUI Functions --------------------
function Update-CsvList {
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

function Update-PlaywrightStatus {
    $playwrightAvailable = Test-PlaywrightAvailability
    if ($playwrightAvailable) {
        $playwrightStatusText.Text = "[OK] Playwright available - JavaScript rendering enabled"
        $playwrightStatusText.Foreground = "Green"
    } else {
        $playwrightStatusText.Text = "[WARN] Playwright not available - HTTP fallback mode (install Playwright for better results)"
        $playwrightStatusText.Foreground = "Orange"
    }
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

# -------------------- Button Handlers --------------------
$refreshButton.Add_Click({
        Update-CsvList
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
                $warningMessage = "This CSV file contains $urlCount unique URLs to scrape.`n`nEstimated time: ~$estimatedTime minute(s)`n`nThis operation will use CVExpand's proven scraping methods with Playwright and HTTP fallback.`n`nDo you want to proceed?"

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
            Write-Log -Message "Starting CVExpand-GUI scraping operation for file: $selectedFile" -Level "INFO"

            # Initialize dependency manager and check/install MSRC module
            Write-Log -Message "Initializing dependency manager..." -Level "INFO"
            $Global:DependencyManager = [DependencyManager]::new($rootDir, $Global:LogFile)
            $null = $Global:DependencyManager.CheckAllDependencies()

            # Auto-install MSRC module if missing
            $msrcInstall = $Global:DependencyManager.InstallMsrcModule($true)
            if ($msrcInstall.Success) {
                Write-Log -Message "MSRC module ready (version $($msrcInstall.Version))" -Level "SUCCESS"
            } else {
                Write-Log -Message "MSRC module install failed or declined: $($msrcInstall.Error)" -Level "WARNING"
            }

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

                # Build summary message
                $summaryMessage = "CVExpand-GUI scraping completed successfully!`n`n$($result.Message)`n`nFiles created:`n- Backup: $($selectedFile -replace '\.csv$', '_backup.csv')`n- Log file: $logFileName"

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

# -------------------- Initialize and Show Window --------------------
Write-Host "`n===============================================================================" -ForegroundColor Cyan
Write-Host "                          CVE Advisory Scraper (CVExpand-GUI)" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  * Proven Playwright integration for JavaScript rendering" -ForegroundColor Cyan
Write-Host "  * HTTP fallback when Playwright unavailable" -ForegroundColor Cyan
Write-Host "  * Enhanced MSRC page extraction with download links" -ForegroundColor Cyan
Write-Host "  * Comprehensive logging and error handling" -ForegroundColor Cyan
Write-Host "  * Automatic backup creation and data validation" -ForegroundColor Cyan
Write-Host "===============================================================================`n" -ForegroundColor Cyan

Update-CsvList
Update-PlaywrightStatus
[void]$window.ShowDialog()
