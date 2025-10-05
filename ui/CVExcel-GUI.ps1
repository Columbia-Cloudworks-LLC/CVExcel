<#
.SYNOPSIS
    CVExcel Unified GUI - Multi-tool CVE processing interface

.DESCRIPTION
    Unified interface with tabbed navigation for:
    - NVD CVE Exporter: Query and export CVEs from NVD database
    - Advisory Scraper: Scrape CVE advisory URLs for patches and download links
    - Expandable for future tools

.NOTES
    This is the main GUI entry point for the CVExcel project.
    Launched automatically by CVExcel.ps1 when run without parameters.
#>

# Import required assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, System.Web

# -------------------- Setup Paths --------------------
$script:RootDir = Split-Path $PSScriptRoot -Parent
$script:OutDir = Join-Path $script:RootDir "out"
$script:ProductsFile = Join-Path $script:RootDir "products.txt"
$script:KeyFile = Join-Path $script:RootDir "nvd.api.key"

# Ensure out directory exists
if (-not (Test-Path $script:OutDir)) {
    New-Item -ItemType Directory -Path $script:OutDir | Out-Null
}

# -------------------- Import Modules --------------------
Write-Host "Loading CVExcel modules..." -ForegroundColor Cyan

# Import NVD Engine
. "$PSScriptRoot\NVDEngine.ps1"

# Import CVExpand modules (for Advisory Scraper tab)
. "$PSScriptRoot\PlaywrightWrapper.ps1"
. "$PSScriptRoot\DependencyManager.ps1"

# Import Vendor Modules
. "$script:RootDir\vendors\BaseVendor.ps1"
. "$script:RootDir\vendors\GenericVendor.ps1"
. "$script:RootDir\vendors\GitHubVendor.ps1"
. "$script:RootDir\vendors\MicrosoftVendor.ps1"
. "$script:RootDir\vendors\IBMVendor.ps1"
. "$script:RootDir\vendors\ZDIVendor.ps1"
. "$script:RootDir\vendors\VendorManager.ps1"

Write-Host "All modules loaded successfully." -ForegroundColor Green

# -------------------- Global State --------------------
$Global:LogFile = $null
$Global:VendorManager = $null
$Global:DependencyManager = $null

# -------------------- Logging Infrastructure --------------------
function Initialize-LogFile {
    [CmdletBinding()]
    param([string]$LogDir = $script:OutDir)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFileName = "cvexcel_log_$timestamp.log"
    $logFilePath = Join-Path $LogDir $logFileName

    $header = @"
================================================================================
CVExcel Unified GUI Log
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
        Write-Host "[$Level] $Message"
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8

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

# -------------------- CVExpand Helper Functions --------------------

function Test-PlaywrightAvailability {
    try {
        $packageDir = Join-Path $script:RootDir "packages"
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
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    Write-Log -Message "Fetching URL: $Url" -Level "INFO"

    $playwrightAvailable = Test-PlaywrightAvailability
    if (-not $playwrightAvailable) {
        Write-Log -Message "Playwright not available, falling back to HTTP request" -Level "WARNING"
        return Get-WebPageHTTP -Url $Url
    }

    try {
        Write-Log -Message "Initializing Playwright browser..." -Level "INFO"
        $initResult = New-PlaywrightBrowser -BrowserType chromium -TimeoutSeconds 30

        if (-not $initResult.Success) {
            Write-Log -Message "Failed to initialize Playwright: $($initResult.Error)" -Level "ERROR"
            return Get-WebPageHTTP -Url $Url
        }

        Write-Log -Message "Playwright browser initialized successfully" -Level "SUCCESS"

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
        Close-PlaywrightBrowser
        Write-Log -Message "Playwright browser closed" -Level "DEBUG"
    }
}

function Get-WebPageHTTP {
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
    param(
        [Parameter(Mandatory)]
        [string]$HtmlContent,
        [Parameter(Mandatory)]
        [string]$Url
    )

    Write-Log -Message "Extracting data from advisory page using vendor modules..." -Level "INFO"

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

    if ($null -eq $Global:VendorManager) {
        try {
            $Global:VendorManager = [VendorManager]::new()
            Write-Log -Message "VendorManager initialized successfully" -Level "DEBUG"
        } catch {
            Write-Log -Message "Failed to initialize VendorManager: $($_.Exception.Message). Using generic extraction." -Level "WARNING"
            $Global:VendorManager = $null
        }
    }

    if ($null -ne $Global:VendorManager) {
        try {
            $vendorResult = $Global:VendorManager.ExtractData($HtmlContent, $Url)

            if ($vendorResult.VendorUsed) {
                Write-Log -Message "Using $($vendorResult.VendorUsed) vendor for extraction" -Level "INFO"
            }

            if ($vendorResult.PatchID) { $result.PatchID = $vendorResult.PatchID }
            if ($vendorResult.AffectedVersions) { $result.AffectedVersions = $vendorResult.AffectedVersions }
            if ($vendorResult.Remediation) { $result.Remediation = $vendorResult.Remediation }
            if ($vendorResult.FixVersion) { $result.BuildNumber = $vendorResult.FixVersion }
            if ($vendorResult.VendorUsed) { $result.VendorUsed = $vendorResult.VendorUsed }

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

    # Extract CVE ID from URL if not already found
    if (-not $result.PatchID -and $Url -match 'CVE-(\d{4}-\d+)') {
        $result.PatchID = "CVE-$($matches[1])"
        Write-Log -Message "Extracted CVE ID: $($result.PatchID)" -Level "SUCCESS"
    }

    return $result
}

function Get-CsvFiles {
    $csvFiles = Get-ChildItem -Path $script:OutDir -Filter "*.csv" -File | Sort-Object LastWriteTime -Descending
    return $csvFiles
}

function Test-CsvAlreadyScraped {
    param([string]$CsvPath)

    $firstLine = Get-Content -Path $CsvPath -First 1
    if ($firstLine -match '"?ScrapedDate"?') {
        return $true
    }
    return $false
}

function Scrape-AdvisoryUrl {
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

        $extractStartTime = Get-Date
        $extractedData = Extract-MSRCData -HtmlContent $pageResult.Content -Url $Url
        $extractTime = (Get-Date) - $extractStartTime

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

    $allUrls = @()
    foreach ($row in $csvData) {
        if ($row.RefUrls -and $row.RefUrls -ne '') {
            $urls = $row.RefUrls -split '\s*\|\s*'
            $allUrls += $urls
        }
    }

    $uniqueUrls = $allUrls | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique
    Write-Log -Message "Found $($uniqueUrls.Count) unique URLs to scrape from $($allUrls.Count) total URLs" -Level "INFO"

    $processStartTime = Get-Date
    $urlCache = @{}
    $currentUrl = 0

    if ($ProgressBar) {
        $ProgressBar.Maximum = $uniqueUrls.Count
        $ProgressBar.Value = 0
    }

    $stats = @{
        TotalUrls     = $uniqueUrls.Count
        SuccessCount  = 0
        FailedCount   = 0
        EmptyCount    = 0
        LinksFound    = 0
        DataExtracted = 0
        ErrorTypes    = @{}
    }

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

        $result = Scrape-AdvisoryUrl -Url $url

        switch ($result.Status) {
            'Success' { $stats.SuccessCount++ }
            'Failed' { $stats.FailedCount++ }
            'Empty' { $stats.EmptyCount++ }
            default { $stats.FailedCount++ }
        }

        if ($result.LinksFound -gt 0) { $stats.LinksFound++ }
        if ($result.DataPartsFound -gt 0) { $stats.DataExtracted++ }

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

    $enhancedData = @()
    foreach ($row in $csvData) {
        $newRow = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $newRow[$prop.Name] = $prop.Value
        }

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

        $newRow['DownloadLinks'] = ($rowDownloadLinks | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ' | '
        $newRow['ExtractedData'] = ($rowExtractedData | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ' | '
        $newRow['ScrapeStatus'] = ($rowStatuses -join ',')
        $newRow['ScrapedDate'] = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

        $enhancedData += [PSCustomObject]$newRow
    }

    $backupPath = $CsvPath -replace '\.csv$', '_backup.csv'
    Copy-Item -Path $CsvPath -Destination $backupPath -Force
    Write-Host "Created backup: $backupPath" -ForegroundColor Yellow

    $enhancedData | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Enhanced CSV saved: $CsvPath" -ForegroundColor Green

    $totalProcessingTime = ((Get-Date) - $processStartTime).TotalSeconds
    $avgTimePerUrl = if ($uniqueUrls.Count -gt 0) { [Math]::Round($totalProcessingTime / $uniqueUrls.Count, 2) } else { 0 }

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

================================================================================
"@

    Write-Log -Message $statsMessage -Level "INFO"

    return @{
        Success             = $true
        Message             = $statsMessage
        Stats               = $stats
        TotalProcessingTime = $totalProcessingTime
        AvgTimePerUrl       = $avgTimePerUrl
    }
}

# -------------------- GUI XAML Definition --------------------

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CVExcel - Multi-Tool CVE Processing Suite"
        Height="550" Width="820"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        MinHeight="500" MinWidth="750">
    <Grid Margin="10">
        <TabControl x:Name="MainTabControl">
            <!-- ========== Tab 1: NVD CVE Exporter ========== -->
            <TabItem Header="📊 NVD CVE Exporter" x:Name="NvdTab">
                <Grid Margin="15">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="170"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Row="0" Grid.Column="0" VerticalAlignment="Center" Margin="0,0,8,0">Product</TextBlock>
                    <ComboBox x:Name="ProductCombo" Grid.Row="0" Grid.Column="1" Height="26" />

                    <TextBlock Grid.Row="1" Grid.Column="0" VerticalAlignment="Center" Margin="0,8,8,0">Start date (UTC)</TextBlock>
                    <DatePicker x:Name="StartDatePicker" Grid.Row="1" Grid.Column="1" Margin="0,8,0,0" />

                    <TextBlock Grid.Row="2" Grid.Column="0" VerticalAlignment="Center" Margin="0,8,8,0">End date (UTC)</TextBlock>
                    <DatePicker x:Name="EndDatePicker" Grid.Row="2" Grid.Column="1" Margin="0,8,0,0" />

                    <TextBlock Grid.Row="3" Grid.Column="0" VerticalAlignment="Center" Margin="0,8,8,0">Quick Select</TextBlock>
                    <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" Margin="0,8,0,0">
                        <Button x:Name="Quick30" Content="30 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="Quick60" Content="60 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="Quick90" Content="90 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="Quick120" Content="120 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="QuickAll" Content="ALL" Width="60" Height="24" FontSize="11"/>
                    </StackPanel>

                    <CheckBox x:Name="UseLastMod" Grid.Row="4" Grid.Column="1" Margin="0,8,0,0"
                              Content="Use last-modified dates (not publication)" />
                    <CheckBox x:Name="NoDateChk" Grid.Row="5" Grid.Column="1" Margin="0,8,0,0"
                              Content="Validate product only (no dates)" />

                    <StackPanel Grid.Row="6" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
                        <Button x:Name="TestButton" Content="Test API" Width="80" Height="28" Margin="0,0,8,0"/>
                        <Button x:Name="ExportButton" Content="Export CVEs" Width="96" Height="28" Margin="0,0,8,0"/>
                    </StackPanel>

                    <TextBlock Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,12,0,0"
                               TextWrapping="Wrap" FontSize="10" Foreground="Gray">
                        IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.
                    </TextBlock>
                </Grid>
            </TabItem>

            <!-- ========== Tab 2: Advisory Scraper ========== -->
            <TabItem Header="🔍 Advisory Scraper" x:Name="ExpandTab">
                <Grid Margin="15">
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

                    <TextBlock Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,0" TextWrapping="Wrap" FontSize="11">
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
                                HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,16,0,40">
                        <Button x:Name="RefreshButton" Content="Refresh List" Width="100" Height="28" Margin="0,0,8,0"/>
                        <Button x:Name="ScrapeButton" Content="Scrape" Width="96" Height="28" Margin="0,0,8,0"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- ========== Tab 3: About ========== -->
            <TabItem Header="ℹ️ About" x:Name="AboutTab">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock FontSize="18" FontWeight="Bold" Margin="0,0,0,10">CVExcel - Multi-Tool CVE Processing Suite</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,10">
                            A comprehensive PowerShell-based CVE processing toolkit with GUI interface.
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Tools Available:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            <Bold>📊 NVD CVE Exporter:</Bold> Query and export CVE data from the NVD database.
                            <LineBreak/>
                            • Supports keyword and CPE searches
                            <LineBreak/>
                            • Date range filtering with automatic chunking
                            <LineBreak/>
                            • API key support for higher rate limits
                            <LineBreak/>
                            • CSV export with full CVE details
                        </TextBlock>

                        <TextBlock TextWrapping="Wrap" Margin="10,10,0,5">
                            <Bold>🔍 Advisory Scraper:</Bold> Scrape CVE advisory URLs for patches and download links.
                            <LineBreak/>
                            • Playwright integration for JavaScript-heavy pages
                            <LineBreak/>
                            • HTTP fallback for reliability
                            <LineBreak/>
                            • Vendor-specific extraction modules
                            <LineBreak/>
                            • Batch CSV processing
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Security &amp; Compliance:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            • Follows NIST secure coding guidelines
                            <LineBreak/>
                            • Implements rate limiting for NVD API
                            <LineBreak/>
                            • Comprehensive logging and error handling
                            <LineBreak/>
                            • Input validation and sanitization
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Project Information:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            Version: 2.0 (Unified GUI)
                            <LineBreak/>
                            Maintained by: Columbia Cloudworks LLC
                            <LineBreak/>
                            License: MIT License
                            <LineBreak/>
                            Documentation: See docs/ folder
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Links:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            <Hyperlink x:Name="GitHubLink" NavigateUri="https://github.com/Columbia-Cloudworks-LLC/CVExcel">erlink_RequestNavigate">erlink_RequestNavigate">
                                GitHub Repository
                            </Hyperlink>
                        </TextBlock>

                        <TextBlock FontSize="10" FontStyle="Italic" Margin="0,20,0,0" Foreground="Gray" TextWrapping="Wrap">
                            IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.
                        </TextBlock>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Close button at bottom -->
        <Button x:Name="CloseButton" Content="Close" Width="80" Height="28"
                HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,20,15"/>
    </Grid>
</Window>
"@

# -------------------- Load and Initialize GUI --------------------

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# -------------------- Get GUI Elements --------------------

# Tab controls
$mainTabControl = $window.FindName('MainTabControl')
$nvdTab = $window.FindName('NvdTab')
$expandTab = $window.FindName('ExpandTab')
$aboutTab = $window.FindName('AboutTab')

# NVD Tab controls
$productCombo = $window.FindName('ProductCombo')
$startDatePicker = $window.FindName('StartDatePicker')
$endDatePicker = $window.FindName('EndDatePicker')
$useLastModCb = $window.FindName('UseLastMod')
$noDateChk = $window.FindName('NoDateChk')
$quick30Button = $window.FindName('Quick30')
$quick60Button = $window.FindName('Quick60')
$quick90Button = $window.FindName('Quick90')
$quick120Button = $window.FindName('Quick120')
$quickAllButton = $window.FindName('QuickAll')
$testButton = $window.FindName('TestButton')
$exportButton = $window.FindName('ExportButton')

# Advisory Scraper Tab controls
$csvCombo = $window.FindName('CsvCombo')
$fileInfoText = $window.FindName('FileInfoText')
$playwrightStatusText = $window.FindName('PlaywrightStatusText')
$forceRescrapeChk = $window.FindName('ForceRescrapeChk')
$progressBar = $window.FindName('ProgressBar')
$statusText = $window.FindName('StatusText')
$refreshButton = $window.FindName('RefreshButton')
$scrapeButton = $window.FindName('ScrapeButton')

# Global controls
$closeButton = $window.FindName('CloseButton')

# -------------------- Initialize NVD Tab --------------------

# Load products.txt
if (Test-Path $script:ProductsFile) {
    $Products = Get-Content $script:ProductsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
    if ($Products) {
        $Products | ForEach-Object { [void]$productCombo.Items.Add($_) }
        $productCombo.SelectedIndex = 0
    } else {
        Write-Host "Warning: products.txt has no usable entries" -ForegroundColor Yellow
    }
} else {
    Write-Host "Warning: products.txt not found at $script:ProductsFile" -ForegroundColor Yellow
}

# Set default dates
$endDatePicker.SelectedDate = [DateTime]::UtcNow.Date
$startDatePicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-30)
$useLastModCb.IsChecked = $true
$noDateChk.IsChecked = $false

# Get API key
$script:NvdApiKey = Get-NvdApiKey -Root $script:RootDir

# -------------------- NVD Tab Event Handlers --------------------

# Quick date selector buttons
$quick30Button.Add_Click({
        $endDatePicker.SelectedDate = [DateTime]::UtcNow.Date
        $startDatePicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-30)
        $noDateChk.IsChecked = $false
    })

$quick60Button.Add_Click({
        $endDatePicker.SelectedDate = [DateTime]::UtcNow.Date
        $startDatePicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-60)
        $noDateChk.IsChecked = $false
    })

$quick90Button.Add_Click({
        $endDatePicker.SelectedDate = [DateTime]::UtcNow.Date
        $startDatePicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-90)
        $noDateChk.IsChecked = $false
    })

$quick120Button.Add_Click({
        $endDatePicker.SelectedDate = [DateTime]::UtcNow.Date
        $startDatePicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-120)
        $noDateChk.IsChecked = $false
    })

$quickAllButton.Add_Click({
        $noDateChk.IsChecked = $true
        Write-Host "ALL selected - will retrieve complete dataset without date filtering" -ForegroundColor Yellow
    })

# Test API button
$testButton.Add_Click({
        try {
            $testButton.Content = "Testing..."
            $testButton.IsEnabled = $false
            $window.Cursor = 'Wait'

            Write-Host "`n=== NVD API Diagnostic Test ===" -ForegroundColor Magenta

            Write-Host "`nAPI Key Status:" -ForegroundColor Yellow
            if ($script:NvdApiKey) {
                Write-Host "✓ API Key is configured (length: $($script:NvdApiKey.Length) characters)" -ForegroundColor Green
            } else {
                Write-Host "⚠ No API key configured - using unauthenticated requests" -ForegroundColor Yellow
                Write-Host "  Note: Unauthenticated requests have lower rate limits" -ForegroundColor Gray
            }

            $apiWorking = Get-NvdApiStatus -ApiKey $script:NvdApiKey

            $keywordTestOk = $false
            if ($apiWorking) {
                $keywordTestOk = Test-NvdApiKeywordSearch -Keyword "microsoft windows" -ApiKey $script:NvdApiKey
            }

            Write-Host "`n=== Test Summary ===" -ForegroundColor Magenta
            if ($apiWorking -and $keywordTestOk) {
                Write-Host "✓ All tests passed! The NVD API is working correctly." -ForegroundColor Green
                [System.Windows.MessageBox]::Show("API tests passed successfully! The NVD API is working correctly.", "Test Results", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } elseif ($apiWorking) {
                Write-Host "⚠ Basic connectivity works, but keyword search failed." -ForegroundColor Yellow
                Write-Host "  This might indicate an issue with search parameters or API changes." -ForegroundColor Gray
                [System.Windows.MessageBox]::Show("Basic API connectivity works, but keyword search failed. Check the console output for details.", "Test Results", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            } else {
                Write-Host "✗ API connectivity failed. The NVD API may be down or experiencing issues." -ForegroundColor Red
                Write-Host "  Check the recommendations above for next steps." -ForegroundColor Gray
                [System.Windows.MessageBox]::Show("API connectivity test failed. The NVD API may be experiencing issues. Check the console output for details and recommendations.", "Test Results", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }

            Write-Host "`n=== End Diagnostic Test ===" -ForegroundColor Magenta
        } catch {
            Write-Host "Error during API testing: $($_.Exception.Message)" -ForegroundColor Red
            [System.Windows.MessageBox]::Show("Error during API testing: $($_.Exception.Message)", "Test Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        } finally {
            $testButton.Content = "Test API"
            $testButton.IsEnabled = $true
            $window.Cursor = 'Arrow'
        }
    })

# Export CVEs button
$exportButton.Add_Click({
        $product = [string]$productCombo.SelectedItem
        $sd = $startDatePicker.SelectedDate
        $ed = $endDatePicker.SelectedDate
        $useLM = [bool]$useLastModCb.IsChecked
        $noDates = [bool]$noDateChk.IsChecked

        if (-not $product) { [System.Windows.MessageBox]::Show("Pick a product.", "Validation"); return }
        if (-not $noDates) {
            if (-not $sd -or -not $ed) { [System.Windows.MessageBox]::Show("Pick both start and end dates.", "Validation"); return }
            if ($ed -lt $sd) { [System.Windows.MessageBox]::Show("End date must be on/after start date.", "Validation"); return }
        }

        $startIso = if (-not $noDates) { ConvertTo-Iso8601Z -DateTime $sd -TimePart "00:00:00.000" } else { $null }
        $endIso = if (-not $noDates) { ConvertTo-Iso8601Z -DateTime $ed -TimePart "23:59:59.999" } else { $null }

        try {
            $window.Cursor = 'Wait'
            $exportButton.Content = "Processing..."
            $exportButton.IsEnabled = $false

            Write-Host "Starting CVE search for product: $product" -ForegroundColor Green
            if (-not $noDates) {
                Write-Host "Date range: $startIso to $endIso" -ForegroundColor Cyan
                $dateType = if ($useLM) { 'last-modified' } else { 'publication' }
                Write-Host "Using $dateType dates" -ForegroundColor Cyan
            } else {
                Write-Host "No date filter (validation mode)" -ForegroundColor Yellow
            }

            Write-Host "Querying NVD API..." -ForegroundColor Yellow
            $rowsRaw = Get-NvdCves -KeywordOrCpe $product `
                -StartIso $startIso -EndIso $endIso `
                -ApiKey $script:NvdApiKey `
                -UseLastModified:$useLM `
                -NoDateFilter:$noDates `
                -Verbose

            Write-Host "Initial query returned $($rowsRaw.Count) CVEs" -ForegroundColor Green

            # If 0 rows and the product was a keyword, auto-resolve to CPEs and retry
            if (($product -notlike 'cpe:2.3:*') -and ($rowsRaw.Count -eq 0)) {
                Write-Host "No results found, attempting CPE resolution..." -ForegroundColor Yellow
                $cpeList = Resolve-CpeCandidates -Keyword $product -Max 5 -ApiKey $script:NvdApiKey
                if ($cpeList -and $cpeList.Count -gt 0) {
                    Write-Host "Found $($cpeList.Count) CPE candidates, retrying..." -ForegroundColor Cyan
                    $cpeList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
                    $rowsRaw = Get-NvdCves -CpeNames $cpeList `
                        -StartIso $startIso -EndIso $endIso `
                        -ApiKey $script:NvdApiKey `
                        -UseLastModified:$useLM `
                        -NoDateFilter:$noDates `
                        -Verbose
                    Write-Host "CPE-based query returned $($rowsRaw.Count) CVEs" -ForegroundColor Green
                } else {
                    Write-Host "No CPE candidates found for keyword: $product" -ForegroundColor Yellow
                }
            }

            # Flatten for CSV
            Write-Host "Processing CVE data for CSV export..." -ForegroundColor Yellow
            $rows = New-Object System.Collections.Generic.List[object]
            foreach ($v in $rowsRaw) {
                $cve = $v.cve
                $id = $cve.id
                $desc = ($cve.descriptions | Where-Object { $_.lang -eq "en" } | Select-Object -First 1).value
                if (-not $desc) { $desc = ($cve.descriptions | Select-Object -First 1).value }
                $score = Get-CvssScore -Metrics $cve.metrics
                $sev = if ($score -ge 9) { "Critical" } elseif ($score -ge 7) { "High" } elseif ($score -ge 4) { "Medium" } elseif ($score -gt 0) { "Low" } else { $null }

                $refs = @()
                $references = if ($cve.references) { $cve.references } else { @() }
                foreach ($r in $references) { if ($r.url) { $refs += $r.url } }
                $refsJoined = ($refs -join " | ")

                $cpeRows = Expand-CPEs -Configurations $cve.configurations
                if (-not $cpeRows -or $cpeRows.Count -eq 0) {
                    $rows.Add([PSCustomObject]@{
                            ProductFilter  = $product
                            CVE            = $id
                            Published      = $cve.published
                            LastModified   = $cve.lastModified
                            CVSS_BaseScore = $score
                            Severity       = $sev
                            Summary        = $desc
                            RefUrls        = $refsJoined
                            Vendor         = ''
                            Product        = ''
                            Version        = ''
                            CPE23Uri       = ''
                        })
                } else {
                    foreach ($c in $cpeRows) {
                        $rows.Add([PSCustomObject]@{
                                ProductFilter  = $product
                                CVE            = $id
                                Published      = $cve.published
                                LastModified   = $cve.lastModified
                                CVSS_BaseScore = $score
                                Severity       = $sev
                                Summary        = $desc
                                RefUrls        = $refsJoined
                                Vendor         = $c.Vendor
                                Product        = $c.Product
                                Version        = $c.Version
                                CPE23Uri       = $c.CPE23Uri
                            })
                    }
                }
            }

            $ts = (Get-Date -Format "yyyyMMdd_HHmmss")
            $safe = ($product -replace '[^\w\.\-]+', '_').Trim('_'); if (-not $safe) { $safe = "product" }
            $outPath = Join-Path $script:OutDir ("{0}_{1}.csv" -f $safe, $ts)
            $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
            Write-Host "Export completed successfully!" -ForegroundColor Green
            Write-Host "IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD." -ForegroundColor Yellow
            [System.Windows.MessageBox]::Show("Exported $($rows.Count) row(s) to:`n$outPath`n`nIMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.", "Done")
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Host "Error occurred: $errorMsg" -ForegroundColor Red

            $userFriendlyMsg = if ($errorMsg -like "*HTTP error 404*") {
                "The NVD API returned a 404 error. This could indicate:`n`n" +
                "• The API endpoint is temporarily unavailable`n" +
                "• The search parameters are invalid (date range > 120 days)`n" +
                "• Rate limiting or authentication issues`n`n" +
                "Technical details: $errorMsg"
            } elseif ($errorMsg -like "*timeout*") {
                "The request timed out. The NVD API may be slow or unavailable.`n`n" +
                "Technical details: $errorMsg"
            } elseif ($errorMsg -like "*authentication*" -or $errorMsg -like "*401*") {
                "Authentication failed. Please check your API key.`n`n" +
                "Technical details: $errorMsg"
            } else {
                "An unexpected error occurred:`n`n$errorMsg"
            }

            [System.Windows.MessageBox]::Show($userFriendlyMsg, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        } finally {
            $window.Cursor = 'Arrow'
            $exportButton.Content = "Export CVEs"
            $exportButton.IsEnabled = $true
        }
    })

# -------------------- Initialize Advisory Scraper Tab --------------------

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
            $selectedFile = Join-Path $script:OutDir $csvCombo.SelectedItem
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

# -------------------- Advisory Scraper Event Handlers --------------------

$refreshButton.Add_Click({
        Update-CsvList
        [System.Windows.MessageBox]::Show("CSV file list refreshed.", "Refresh")
    })

$scrapeButton.Add_Click({
        if (-not $csvCombo.SelectedItem) {
            [System.Windows.MessageBox]::Show("Please select a CSV file first.", "Validation")
            return
        }

        $selectedFile = Join-Path $script:OutDir $csvCombo.SelectedItem

        try {
            $csvData = Import-Csv -Path $selectedFile -Encoding UTF8

            $allUrls = @()
            foreach ($row in $csvData) {
                if ($row.RefUrls -and $row.RefUrls -ne '') {
                    $urls = $row.RefUrls -split '\s*\|\s*'
                    $allUrls += $urls
                }
            }
            $uniqueUrls = $allUrls | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique
            $urlCount = $uniqueUrls.Count

            if ($urlCount -gt 50) {
                $estimatedTime = [Math]::Ceiling($urlCount * 0.5 / 60)
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

            $Global:LogFile = Initialize-LogFile -LogDir $script:OutDir
            Write-Log -Message "Starting CVExpand-GUI scraping operation for file: $selectedFile" -Level "INFO"

            Write-Log -Message "Initializing dependency manager..." -Level "INFO"
            $Global:DependencyManager = [DependencyManager]::new($script:RootDir, $Global:LogFile)
            $null = $Global:DependencyManager.CheckAllDependencies()

            $msrcInstall = $Global:DependencyManager.InstallMsrcModule($true)
            if ($msrcInstall.Success) {
                Write-Log -Message "MSRC module ready (version $($msrcInstall.Version))" -Level "SUCCESS"
            } else {
                Write-Log -Message "MSRC module install failed or declined: $($msrcInstall.Error)" -Level "WARNING"
            }

            $forceRescrape = [bool]$forceRescrapeChk.IsChecked
            if ($forceRescrape) {
                Write-Log -Message "Force re-scrape option enabled" -Level "INFO"
            }

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

                $summaryMessage = "CVExpand-GUI scraping completed successfully!`n`n$($result.Message)`n`nFiles created:`n- Backup: $($selectedFile -replace '\.csv$', '_backup.csv')`n- Log file: $logFileName"

                [System.Windows.MessageBox]::Show(
                    $summaryMessage,
                    "Success",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )

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

# -------------------- Global Event Handlers --------------------

# Hyperlink handler for GitHub link in About tab
$gitHubLink = $window.FindName('GitHubLink')
if ($gitHubLink) {
    $gitHubLink.Add_RequestNavigate({
            param($sender, $e)
            Start-Process $e.Uri.AbsoluteUri
            $e.Handled = $true
        })
}

$closeButton.Add_Click({ $window.Close() })

# -------------------- Initialize and Show Window --------------------

Write-Host "`n===============================================================================" -ForegroundColor Cyan
Write-Host "                 CVExcel - Multi-Tool CVE Processing Suite" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  📊 NVD CVE Exporter - Query and export from NVD database" -ForegroundColor Cyan
Write-Host "  🔍 Advisory Scraper - Extract patches and download links" -ForegroundColor Cyan
Write-Host "  ℹ️ About - Project information and documentation" -ForegroundColor Cyan
Write-Host "===============================================================================`n" -ForegroundColor Cyan

# Initialize Advisory Scraper tab
Update-CsvList
Update-PlaywrightStatus

# Show the window
[void]$window.ShowDialog()
