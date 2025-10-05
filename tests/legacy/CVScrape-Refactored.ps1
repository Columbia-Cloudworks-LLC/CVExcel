<#
.SYNOPSIS
    Refactored CVE Advisory Scraper with enhanced reliability and auto-installation.

.DESCRIPTION
    A comprehensive CVE advisory scraper that automatically installs dependencies,
    provides multiple scraping methods with intelligent fallbacks, and maintains
    detailed logging and progress tracking. Designed to "just work" out of the box.

.FEATURES
    - Automatic dependency installation (Playwright, Selenium)
    - Multiple scraping methods with intelligent fallbacks
    - Vendor-specific optimizations and retry strategies
    - Enhanced anti-bot protection and rate limiting
    - Comprehensive logging and error reporting
    - GUI with progress tracking and status updates
    - Session management and cookie persistence
#>

# Import required assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, System.Web

# Import core modules
. "$PSScriptRoot\DependencyManager.ps1"
. "$PSScriptRoot\ScrapingEngine.ps1"

# -------------------- Global Variables --------------------
$Global:LogFile = $null
$Global:DependencyManager = $null
$Global:ScrapingEngine = $null

# -------------------- Paths --------------------
$Root = Get-Location
$OutDir = Join-Path $Root "out"
if (-not (Test-Path $OutDir)) {
    Write-Error "Missing 'out' directory. Please ensure the 'out' directory exists."
    return
}

# -------------------- Logging Infrastructure --------------------
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
CVE Advisory Scraper Log (Refactored Version)
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

# -------------------- Initialization Functions --------------------
function Initialize-ScrapingSystem {
    [CmdletBinding()]
    param(
        [string]$LogFile
    )

    Write-Log -Message "Initializing scraping system..." -Level "INFO" -LogFile $LogFile

    try {
        # Initialize dependency manager
        $Global:DependencyManager = [DependencyManager]::new($Root, $LogFile)

        # Check all dependencies
        $dependencyStatus = $Global:DependencyManager.CheckAllDependencies()

        # Show dependency status
        $statusSummary = $Global:DependencyManager.GetStatusSummary()
        Write-Log -Message $statusSummary -Level "INFO" -LogFile $LogFile

        # Auto-install missing dependencies if possible
        $installResults = $Global:DependencyManager.InstallMissingDependencies($true)

        if ($installResults.Errors.Count -gt 0) {
            Write-Log -Message "Dependency installation completed with errors:" -Level "WARNING" -LogFile $LogFile
            foreach ($error in $installResults.Errors) {
                Write-Log -Message "  - $error" -Level "WARNING" -LogFile $LogFile
            }
        } else {
            Write-Log -Message "All dependencies ready" -Level "SUCCESS" -LogFile $LogFile
        }

        # Re-check dependencies after installation
        $dependencyStatus = $Global:DependencyManager.CheckAllDependencies()

        # Initialize scraping engine
        $Global:ScrapingEngine = [ScrapingEngine]::new($LogFile, $dependencyStatus)

        Write-Log -Message "Scraping system initialized successfully" -Level "SUCCESS" -LogFile $LogFile

        return @{
            Success = $true
            DependencyStatus = $dependencyStatus
            RecommendedMethod = $Global:DependencyManager.GetRecommendedScrapingMethod()
        }

    } catch {
        Write-Log -Message "Failed to initialize scraping system: $($_.Exception.Message)" -Level "ERROR" -LogFile $LogFile
        return @{
            Success = $false
            ErrorMessage = $_.Exception.Message
        }
    }
}

# -------------------- CSV Processing Functions --------------------
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

function Invoke-CsvProcessing {
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
            Success = $false
            Message = "File already scraped. Enable 'Force re-scrape' option to override."
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
        TotalUrls = $uniqueUrls.Count
        SuccessCount = 0
        FailedCount = 0
        BlockedCount = 0
        EmptyCount = 0
        LinksFound = 0
        DataExtracted = 0
        BlockedUrls = @()
        ErrorTypes = @{}
    }

    # Scrape each unique URL
    foreach ($url in $uniqueUrls) {
        $currentUrl++

        if ($StatusText) {
            $StatusText.Dispatcher.Invoke([Action] {
                $StatusText.Text = "Scraping URL $currentUrl of $($uniqueUrls.Count): $($url.Substring(0, [Math]::Min(50, $url.Length)))..."
            })
        }

        if ($ProgressBar) {
            $ProgressBar.Dispatcher.Invoke([Action] {
                $ProgressBar.Value = $currentUrl
            })
        }

        Write-Host "  [$currentUrl/$($uniqueUrls.Count)] $url" -ForegroundColor Gray

        # Scrape using the enhanced engine
        $result = $Global:ScrapingEngine.ScrapeUrl($url)

        # Update statistics
        switch ($result.Status) {
            'Success' { $stats.SuccessCount++ }
            'Failed' { $stats.FailedCount++ }
            'Blocked' {
                $stats.BlockedCount++
                $stats.BlockedUrls += $url
            }
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
- Blocked - 403 anti-bot: $($stats.BlockedCount)
- Empty URLs: $($stats.EmptyCount)
- URLs with download links: $($stats.LinksFound)
- URLs with extracted data: $($stats.DataExtracted)
- CSV rows updated: $($csvData.Count)

Performance Metrics:
- Total processing time: $([Math]::Round($totalProcessingTime, 2)) seconds
- Average time per URL: $avgTimePerUrl seconds
- Recommended scraping method: $($Global:DependencyManager.GetRecommendedScrapingMethod())

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

    if ($stats.BlockedUrls.Count -gt 0) {
        $statsMessage += "`nBlocked URLs (require manual review):`n"
        foreach ($blockedUrl in $stats.BlockedUrls) {
            $statsMessage += "- $blockedUrl`n"
        }
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
        Success = $true
        Message = $statsMessage
        Stats = $stats
        TotalProcessingTime = $totalProcessingTime
        AvgTimePerUrl = $avgTimePerUrl
    }
}

# -------------------- GUI --------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CVE Advisory Scraper (Enhanced)" Height="400" Width="700"
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

    <TextBlock x:Name="DependencyStatusText" Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2"
               Margin="0,8,0,0" TextWrapping="Wrap" Foreground="Blue" FontSize="11"/>

    <TextBlock Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,12,0,4">
      <Run FontWeight="Bold">Enhanced Features:</Run>
    </TextBlock>

    <TextBlock Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,0" TextWrapping="Wrap">
      • Auto-installs dependencies (Playwright, Selenium)
      <LineBreak/>
      • Multiple scraping methods with intelligent fallbacks
      <LineBreak/>
      • Enhanced anti-bot protection and rate limiting
      <LineBreak/>
      • Vendor-specific optimizations and retry strategies
      <LineBreak/>
      • Session management and cookie persistence
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
$dependencyStatusText = $window.FindName('DependencyStatusText')
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

function Update-DependencyStatus {
    if ($Global:DependencyManager) {
        $status = $Global:DependencyManager.GetStatusSummary()
        $dependencyStatusText.Text = $status
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
            $warningMessage = "This CSV file contains $urlCount unique URLs to scrape.`n`nEstimated time: ~$estimatedTime minute(s)`n`nThis operation will use enhanced scraping methods with automatic fallbacks.`n`nDo you want to proceed?"

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
        Write-Log -Message "Starting enhanced scraping operation for file: $selectedFile" -Level "INFO"

        # Initialize scraping system
        $initResult = Initialize-ScrapingSystem -LogFile $Global:LogFile

        if (-not $initResult.Success) {
            [System.Windows.MessageBox]::Show(
                "Failed to initialize scraping system:`n`n$($initResult.ErrorMessage)",
                "Initialization Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }

        # Update dependency status display
        Update-DependencyStatus

        # Check force re-scrape option
        $forceRescrape = [bool]$forceRescrapeChk.IsChecked
        if ($forceRescrape) {
            Write-Log -Message "Force re-scrape option enabled" -Level "INFO"
        }

        # Process the CSV
        $result = Invoke-CsvProcessing -CsvPath $selectedFile -ProgressBar $progressBar -StatusText $statusText -ForceRescrape:$forceRescrape

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
            $summaryMessage = "Enhanced scraping completed successfully!`n`n$($result.Message)`n`nFiles created:`n- Backup: $($selectedFile -replace '\.csv$', '_backup.csv')`n- Log file: $logFileName"

            if ($result.Stats.BlockedUrls -and $result.Stats.BlockedUrls.Count -gt 0) {
                $summaryMessage += "`n`n⚠ BLOCKED URLS (require manual review):`n"
                foreach ($blockedUrl in $result.Stats.BlockedUrls) {
                    $summaryMessage += "• $blockedUrl`n"
                }
                $summaryMessage += "`nThese URLs were blocked by anti-bot protection.`nConsider visiting them manually in a browser."
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
        # Cleanup
        if ($Global:ScrapingEngine) {
            $Global:ScrapingEngine.Cleanup()
        }

        $window.Cursor = 'Arrow'
        $scrapeButton.Content = "Scrape"
        $scrapeButton.IsEnabled = $true
        $statusText.Text = ""
        $progressBar.Value = 0
    }
})

$cancelButton.Add_Click({
    # Cleanup before closing
    if ($Global:ScrapingEngine) {
        $Global:ScrapingEngine.Cleanup()
    }
    $window.Close()
})

# -------------------- Initialize and Show Window --------------------
Write-Host "`n╔═══════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                          CVE Advisory Scraper (Enhanced)                              ║" -ForegroundColor Cyan
Write-Host "║                                                                                       ║" -ForegroundColor Cyan
Write-Host "║  • Auto-installs dependencies (Playwright, Selenium)                                  ║" -ForegroundColor Cyan
Write-Host "║  • Multiple scraping methods with intelligent fallbacks                               ║" -ForegroundColor Cyan
Write-Host "║  • Enhanced anti-bot protection and rate limiting                                     ║" -ForegroundColor Cyan
Write-Host "║  • Vendor-specific optimizations and retry strategies                                ║" -ForegroundColor Cyan
Write-Host "║  • Session management and cookie persistence                                          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Update-CsvList
[void]$window.ShowDialog()
