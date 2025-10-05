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

# Import common modules
. "$script:RootDir\common\Logging.ps1"

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

# -------------------- CVExpand Helper Functions --------------------
# Note: Test-PlaywrightAvailability is now in ui/PlaywrightWrapper.ps1

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

    try {
        if (-not $CsvPath -or -not (Test-Path $CsvPath)) {
            return $false
        }
        $firstLine = Get-Content -Path $CsvPath -First 1
        if ($firstLine -match '"?ScrapedDate"?') {
            return $true
        }
        return $false
    } catch {
        return $false
    }
}

function Test-FileAvailability {
    <#
    .SYNOPSIS
        Checks if a file is available for writing (not open by another process).
    .DESCRIPTION
        Attempts to open the file in write mode to detect if it's locked by another process.
        This helps prevent scraping operations that would ultimately fail.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    try {
        # Try to open the file in write mode with no sharing
        $fileStream = [System.IO.File]::OpenWrite($FilePath)
        $fileStream.Close()
        $fileStream.Dispose()
        return @{
            IsAvailable = $true
            Error       = $null
        }
    } catch {
        return @{
            IsAvailable = $false
            Error       = $_.Exception.Message
        }
    }
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

                    <CheckBox x:Name="CreateBackupChk" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="2"
                              Margin="0,8,0,0" Content="Create backup before processing" IsChecked="True"/>

                    <ProgressBar x:Name="ProgressBar" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2"
                                 Height="20" Margin="0,12,0,0" Minimum="0" Maximum="100" Value="0"/>

                    <TextBlock x:Name="StatusText" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2"
                               HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="11" Foreground="White"/>

                    <StackPanel Grid.Row="8" Grid.Column="1" Orientation="Horizontal"
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
                            <Hyperlink x:Name="GitHubLink" NavigateUri="https://github.com/Columbia-Cloudworks-LLC/CVExcel">erlink_RequestNavigate">erlink_RequestNavigate">erlink_RequestNavigate">erlink_RequestNavigate">erlink_RequestNavigate">erlink_RequestNavigate">
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
$createBackupChk = $window.FindName('CreateBackupChk')
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

# -------------------- Background Processing with Runspaces --------------------

function Invoke-BackgroundScraping {
    <#
    .SYNOPSIS
        Executes CSV scraping in a background runspace to keep GUI responsive.
    .DESCRIPTION
        Creates a separate thread for long-running scraping operations, allowing
        the GUI to remain responsive and the progress bar to update smoothly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CsvPath,
        [Parameter(Mandatory)]
        [System.Windows.Controls.ProgressBar]$ProgressBar,
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$StatusText,
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$ScrapeButton,
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,
        [Parameter(Mandatory)]
        [System.Windows.Controls.ComboBox]$CsvCombo,
        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$FileInfoText,
        [switch]$ForceRescrape,
        [switch]$CreateBackup
    )

    Write-Log -Message "Starting background scraping with runspace" -Level "INFO"

    # Create synchronized hashtable for thread-safe communication
    $syncHash = [hashtable]::Synchronized(@{
            ProgressValue = 0
            ProgressMax   = 100
            StatusText    = "Initializing..."
            IsComplete    = $false
            Result        = $null
            Error         = $null
        })

    # Create and configure runspace
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()

    # Pass variables to runspace
    $runspace.SessionStateProxy.SetVariable("syncHash", $syncHash)
    $runspace.SessionStateProxy.SetVariable("CsvPath", $CsvPath)
    $runspace.SessionStateProxy.SetVariable("ForceRescrape", $ForceRescrape)
    $runspace.SessionStateProxy.SetVariable("CreateBackup", $CreateBackup)
    $runspace.SessionStateProxy.SetVariable("RootDir", $script:RootDir)
    $runspace.SessionStateProxy.SetVariable("OutDir", $script:OutDir)
    $runspace.SessionStateProxy.SetVariable("LogFile", $Global:LogFile)

    # Create PowerShell pipeline with background script
    $powershell = [powershell]::Create().AddScript({
            param($syncHash, $CsvPath, $ForceRescrape, $CreateBackup, $RootDir, $OutDir, $LogFile)

            $ErrorActionPreference = 'Stop'

            # Import required modules in background thread
            . "$RootDir\vendors\BaseVendor.ps1"
            . "$RootDir\vendors\GenericVendor.ps1"
            . "$RootDir\vendors\GitHubVendor.ps1"
            . "$RootDir\vendors\MicrosoftVendor.ps1"
            . "$RootDir\vendors\IBMVendor.ps1"
            . "$RootDir\vendors\ZDIVendor.ps1"
            . "$RootDir\vendors\VendorManager.ps1"
            . "$RootDir\ui\PlaywrightWrapper.ps1"
            . "$RootDir\ui\DependencyManager.ps1"

            $Global:LogFile = $LogFile
            $Global:VendorManager = $null

            try {
                # Import common modules in runspace context
                . "$RootDir\common\Logging.ps1"
                . "$RootDir\ui\PlaywrightWrapper.ps1"

                function Get-WebPage {
                    param([string]$Url)
                    Write-Log -Message "Fetching URL: $Url" -Level "INFO"
                    $playwrightAvailable = Test-PlaywrightAvailability
                    if (-not $playwrightAvailable) {
                        return Get-WebPageHTTP -Url $Url
                    }
                    try {
                        $initResult = New-PlaywrightBrowser -BrowserType chromium -TimeoutSeconds 30
                        if (-not $initResult.Success) { return Get-WebPageHTTP -Url $Url }
                        $result = Invoke-PlaywrightNavigate -Url $Url -WaitSeconds 8
                        if ($result.Success) {
                            return @{ Success = $true; Content = $result.Content; StatusCode = $result.StatusCode; Method = "Playwright" }
                        } else {
                            return Get-WebPageHTTP -Url $Url
                        }
                    } catch {
                        return Get-WebPageHTTP -Url $Url
                    } finally {
                        Close-PlaywrightBrowser
                    }
                }

                function Get-WebPageHTTP {
                    param([string]$Url)
                    $headers = @{
                        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                        'Accept'     = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8'
                    }
                    try {
                        $response = Invoke-WebRequest -Uri $Url -Headers $headers -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
                        return @{ Success = $true; Content = $response.Content; StatusCode = $response.StatusCode; Method = "HTTP" }
                    } catch {
                        return @{ Success = $false; Error = $_.Exception.Message; Method = "HTTP" }
                    }
                }

                function Extract-MSRCData {
                    param([string]$HtmlContent, [string]$Url)
                    $result = @{ PatchID = $null; AffectedVersions = $null; Remediation = $null; DownloadLinks = @(); BuildNumber = $null; Product = $null; ReleaseDate = $null; Severity = $null; Impact = $null; VendorUsed = "Generic" }

                    if ($null -eq $Global:VendorManager) {
                        try {
                            $Global:VendorManager = [VendorManager]::new()
                            Write-Log -Message "VendorManager initialized in background thread" -Level "DEBUG"
                        } catch {
                            $Global:VendorManager = $null
                        }
                    }

                    if ($null -ne $Global:VendorManager) {
                        try {
                            $vendorResult = $Global:VendorManager.ExtractData($HtmlContent, $Url)
                            if ($vendorResult.PatchID) { $result.PatchID = $vendorResult.PatchID }
                            if ($vendorResult.AffectedVersions) { $result.AffectedVersions = $vendorResult.AffectedVersions }
                            if ($vendorResult.Remediation) { $result.Remediation = $vendorResult.Remediation }
                            if ($vendorResult.FixVersion) { $result.BuildNumber = $vendorResult.FixVersion }
                            if ($vendorResult.VendorUsed) { $result.VendorUsed = $vendorResult.VendorUsed }
                            if ($vendorResult.DownloadLinks) {
                                foreach ($link in $vendorResult.DownloadLinks) {
                                    if ($result.DownloadLinks -notcontains $link) { $result.DownloadLinks += $link }
                                }
                            }
                        } catch {
                            Write-Log -Message "Vendor extraction error: $($_.Exception.Message)" -Level "WARNING"
                        }
                    }

                    if (-not $result.PatchID -and $Url -match 'CVE-(\d{4}-\d+)') {
                        $result.PatchID = "CVE-$($matches[1])"
                    }
                    return $result
                }

                function Scrape-AdvisoryUrl {
                    param([string]$Url)
                    if (-not $Url -or $Url -eq '') {
                        return @{ Url = $Url; Status = 'Empty'; DownloadLinks = ''; ExtractedData = ''; Error = 'Empty URL'; LinksFound = 0; DataPartsFound = 0 }
                    }
                    try {
                        $pageResult = Get-WebPage -Url $Url
                        if (-not $pageResult.Success) {
                            return @{ Url = $Url; Status = 'Failed'; DownloadLinks = ''; ExtractedData = 'Failed to fetch page'; Error = $pageResult.Error; LinksFound = 0; DataPartsFound = 0 }
                        }
                        $extractedData = Extract-MSRCData -HtmlContent $pageResult.Content -Url $Url
                        $extractedParts = @()
                        if ($extractedData.PatchID) { $extractedParts += "Patch: $($extractedData.PatchID)" }
                        if ($extractedData.Product) { $extractedParts += "Product: $($extractedData.Product)" }
                        if ($extractedData.BuildNumber) { $extractedParts += "Build: $($extractedData.BuildNumber)" }
                        $extractedDataSummary = if ($extractedParts.Count -gt 0) { $extractedParts -join ' | ' } else { 'No specific data extracted' }
                        return @{
                            Url            = $Url
                            Status         = 'Success'
                            DownloadLinks  = ($extractedData.DownloadLinks -join ' | ')
                            ExtractedData  = $extractedDataSummary
                            Error          = $null
                            LinksFound     = $extractedData.DownloadLinks.Count
                            DataPartsFound = $extractedParts.Count
                            Method         = $pageResult.Method
                        }
                    } catch {
                        return @{ Url = $Url; Status = 'Error'; DownloadLinks = ''; ExtractedData = "Error: $($_.Exception.Message)"; Error = $_.Exception.Message; LinksFound = 0; DataPartsFound = 0 }
                    } finally {
                        Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 1000)
                    }
                }

                function Test-CsvAlreadyScraped {
                    param([string]$CsvPath)
                    $firstLine = Get-Content -Path $CsvPath -First 1
                    if ($firstLine -match '"?ScrapedDate"?') { return $true }
                    return $false
                }

                # Main processing logic
                Write-Log -Message "Background thread: Starting CSV processing" -Level "INFO"
                $syncHash.StatusText = "Reading CSV file..."

                # Check if already scraped
                if (-not $ForceRescrape -and (Test-CsvAlreadyScraped -CsvPath $CsvPath)) {
                    $syncHash.Result = @{ Success = $false; AlreadyScraped = $true; Message = "File already scraped. Enable 'Force re-scrape' option to override." }
                    $syncHash.IsComplete = $true
                    return
                }

                $csvData = Import-Csv -Path $CsvPath -Encoding UTF8

                if (-not $csvData -or $csvData.Count -eq 0) {
                    throw "CSV file is empty or invalid"
                }

                Write-Log -Message "Found $($csvData.Count) rows in CSV" -Level "INFO"

                # Extract unique URLs
                $allUrls = @()
                foreach ($row in $csvData) {
                    if ($row.RefUrls -and $row.RefUrls -ne '') {
                        $urls = $row.RefUrls -split '\s*\|\s*'
                        $allUrls += $urls
                    }
                }

                $uniqueUrls = $allUrls | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique
                Write-Log -Message "Found $($uniqueUrls.Count) unique URLs to scrape" -Level "INFO"

                $syncHash.ProgressMax = $uniqueUrls.Count

                # Scrape each URL
                $urlCache = @{}
                $currentUrl = 0
                $stats = @{ SuccessCount = 0; FailedCount = 0; EmptyCount = 0; LinksFound = 0; DataExtracted = 0 }

                foreach ($url in $uniqueUrls) {
                    $currentUrl++
                    $syncHash.StatusText = "Scraping URL $currentUrl of $($uniqueUrls.Count)..."
                    $syncHash.ProgressValue = $currentUrl

                    Write-Log -Message "  [$currentUrl/$($uniqueUrls.Count)] $url" -Level "DEBUG"
                    $result = Scrape-AdvisoryUrl -Url $url

                    # Update stats
                    switch ($result.Status) {
                        'Success' { $stats.SuccessCount++ }
                        'Failed' { $stats.FailedCount++ }
                        'Empty' { $stats.EmptyCount++ }
                        default { $stats.FailedCount++ }
                    }
                    if ($result.LinksFound -gt 0) { $stats.LinksFound++ }
                    if ($result.DataPartsFound -gt 0) { $stats.DataExtracted++ }

                    $urlCache[$url] = $result
                }

                $syncHash.StatusText = "Updating CSV file..."
                Write-Log -Message "Scraping complete. Updating CSV..." -Level "SUCCESS"

                # Update CSV with results
                $enhancedData = @()
                foreach ($row in $csvData) {
                    $newRow = [ordered]@{}
                    foreach ($prop in $row.PSObject.Properties) { $newRow[$prop.Name] = $prop.Value }

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

                # Create backup if enabled
                $backupPath = $null
                if ($CreateBackup) {
                    $backupPath = $CsvPath -replace '\.csv$', '_backup.csv'
                    Copy-Item -Path $CsvPath -Destination $backupPath -Force
                    Write-Log -Message "Created backup: $backupPath" -Level "INFO"
                } else {
                    Write-Log -Message "Backup creation disabled by user" -Level "INFO"
                }

                $enhancedData | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
                Write-Log -Message "Enhanced CSV saved: $CsvPath" -Level "SUCCESS"

                $resultMessage = "Successfully processed $($uniqueUrls.Count) unique URLs`n- Success: $($stats.SuccessCount)`n- Failed: $($stats.FailedCount)`n- URLs with links: $($stats.LinksFound)"
                if ($CreateBackup -and $backupPath) {
                    $resultMessage += "`n- Backup created: $(Split-Path $backupPath -Leaf)"
                }

                $syncHash.Result = @{
                    Success        = $true
                    Message        = $resultMessage
                    UrlsProcessed  = $uniqueUrls.Count
                    BackupPath     = $backupPath
                    AlreadyScraped = $false
                }

            } catch {
                $errorMsg = $_.Exception.Message
                $syncHash.Error = $errorMsg
                Write-Log -Message "Background scraping error: $errorMsg" -Level "ERROR"
            } finally {
                $syncHash.IsComplete = $true
            }
        }).AddArgument($syncHash).AddArgument($CsvPath).AddArgument($ForceRescrape).AddArgument($CreateBackup).AddArgument($script:RootDir).AddArgument($script:OutDir).AddArgument($Global:LogFile)

    $powershell.Runspace = $runspace
    $asyncResult = $powershell.BeginInvoke()

    # Create dispatcher timer to update UI from background thread
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)

    $timer.Add_Tick({
            # Update progress bar and status text from synchronized hashtable
            $ProgressBar.Maximum = $syncHash.ProgressMax
            $ProgressBar.Value = $syncHash.ProgressValue
            $StatusText.Text = $syncHash.StatusText

            # Check if background processing is complete
            if ($syncHash.IsComplete) {
                $timer.Stop()

                # Restore UI controls
                $Window.Cursor = 'Arrow'
                $ScrapeButton.Content = "Scrape"
                $ScrapeButton.IsEnabled = $true
                $StatusText.Text = ""
                $ProgressBar.Value = 0

                # Handle results
                if ($syncHash.Error) {
                    Write-Host "Error during background scraping: $($syncHash.Error)" -ForegroundColor Red
                    [System.Windows.MessageBox]::Show(
                        "Error during scraping:`n`n$($syncHash.Error)",
                        "Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                } elseif ($syncHash.Result) {
                    if ($syncHash.Result.AlreadyScraped) {
                        [System.Windows.MessageBox]::Show(
                            $syncHash.Result.Message,
                            "Already Scraped",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )
                    } elseif ($syncHash.Result.Success) {
                        $logFileName = if ($Global:LogFile) { Split-Path $Global:LogFile -Leaf } else { "N/A" }
                        $summaryMessage = "Scraping completed successfully!`n`n$($syncHash.Result.Message)`n`nFiles created:`n- Log file: $logFileName"
                        if ($syncHash.Result.BackupPath) {
                            $summaryMessage += "`n- Backup: $(Split-Path $syncHash.Result.BackupPath -Leaf)"
                        }

                        [System.Windows.MessageBox]::Show(
                            $summaryMessage,
                            "Success",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )

                        # Refresh file info display
                        if ($CsvCombo.SelectedItem) {
                            try {
                                $selectedFile = Join-Path $script:OutDir $CsvCombo.SelectedItem
                                if (Test-Path $selectedFile) {
                                    $fileInfo = Get-Item $selectedFile
                                    $csvData = Import-Csv -Path $selectedFile -Encoding UTF8
                                    $isScraped = Test-CsvAlreadyScraped -CsvPath $selectedFile
                                    $scrapedStatus = if ($isScraped) { "Already scraped" } else { "Not yet scraped" }
                                    $FileInfoText.Text = "File: $($fileInfo.Name) | Size: $([Math]::Round($fileInfo.Length/1KB, 2)) KB | Rows: $($csvData.Count) | Status: $scrapedStatus"
                                    $FileInfoText.Foreground = if ($isScraped) { "Green" } else { "Gray" }
                                }
                            } catch {
                                Write-Host "Warning: Could not refresh file info: $($_.Exception.Message)" -ForegroundColor Yellow
                            }
                        }
                    }
                }

                # Cleanup runspace resources
                $powershell.EndInvoke($asyncResult)
                $powershell.Dispose()
                $runspace.Close()
                $runspace.Dispose()

                Write-Log -Message "Background scraping completed and resources cleaned up" -Level "INFO"
            }
        }.GetNewClosure())

    $timer.Start()
    Write-Log -Message "Background scraping initiated with UI update timer" -Level "SUCCESS"
}

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

        # Pre-check: Test file availability first
        Write-Log -Message "Checking file availability for: $selectedFile" -Level "INFO"
        $fileAvailability = Test-FileAvailability -FilePath $selectedFile

        if (-not $fileAvailability.IsAvailable) {
            $errorMessage = "File is currently open by another application and cannot be processed.`n`nPlease close the file and try again.`n`nTechnical details: $($fileAvailability.Error)"
            Write-Log -Message "File availability check failed: $($fileAvailability.Error)" -Level "ERROR"

            [System.Windows.MessageBox]::Show(
                $errorMessage,
                "File Not Available",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        Write-Log -Message "File availability check passed" -Level "SUCCESS"

        # Pre-check: Count unique URLs and show warning if large operation
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
                $warningMessage = "This CSV file contains $urlCount unique URLs to scrape.`n`nEstimated time: ~$estimatedTime minute(s)`n`nThe GUI will remain responsive during the operation.`n`nDo you want to proceed?"

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

        # Initialize logging and UI state
        $window.Cursor = 'Wait'
        $scrapeButton.Content = "Processing..."
        $scrapeButton.IsEnabled = $false
        $progressBar.Value = 0
        $statusText.Text = "Initializing..."

        $Global:LogFile = Initialize-LogFile -LogDir $script:OutDir
        Write-Log -Message "Starting background scraping operation for file: $selectedFile" -Level "INFO"

        # Initialize dependency manager (runs on UI thread before background task)
        Write-Log -Message "Initializing dependency manager..." -Level "INFO"
        $Global:DependencyManager = [DependencyManager]::new($script:RootDir, $Global:LogFile)
        $null = $Global:DependencyManager.CheckAllDependencies()

        $msrcInstall = $Global:DependencyManager.InstallMsrcModule($true)
        if ($msrcInstall.Success) {
            Write-Log -Message "MSRC module ready (version $($msrcInstall.Version))" -Level "SUCCESS"
        } else {
            Write-Log -Message "MSRC module install failed or declined: $($msrcInstall.Error)" -Level "WARNING"
        }

        # Start background scraping with runspace
        $forceRescrape = [bool]$forceRescrapeChk.IsChecked
        if ($forceRescrape) {
            Write-Log -Message "Force re-scrape option enabled" -Level "INFO"
        }

        $createBackup = [bool]$createBackupChk.IsChecked
        if ($createBackup) {
            Write-Log -Message "Backup creation enabled" -Level "INFO"
        } else {
            Write-Log -Message "Backup creation disabled by user" -Level "INFO"
        }

        Invoke-BackgroundScraping -CsvPath $selectedFile `
            -ProgressBar $progressBar `
            -StatusText $statusText `
            -ScrapeButton $scrapeButton `
            -Window $window `
            -CsvCombo $csvCombo `
            -FileInfoText $fileInfoText `
            -ForceRescrape:$forceRescrape `
            -CreateBackup:$createBackup
    })

# -------------------- Global Event Handlers --------------------

# Hyperlink handler for GitHub link in About tab
$gitHubLink = $window.FindName('GitHubLink')
if ($gitHubLink) {
    $gitHubLink.Add_RequestNavigate({
            param($s, $e)
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
