<#
.SYNOPSIS
    Advisory Tab - CVE Advisory Scraper tab component for CVExcel GUI

.DESCRIPTION
    Modular component containing all logic for the Advisory Scraper tab including:
    - CSV file selection and management
    - Web scraping functions (Playwright + HTTP fallback)
    - Data extraction from advisory pages
    - Background processing with runspaces
    - Progress tracking and UI updates
    - Event handlers for all Advisory tab controls

.NOTES
    This module is loaded by CVExcel-GUI.ps1 and operates on GUI controls
    passed as parameters to Initialize-AdvisoryTab.

.AUTHOR
    Columbia Cloudworks LLC
    https://github.com/Columbia-Cloudworks-LLC/CVExcel
#>

# -------------------- Helper Functions --------------------

function Get-WebPage {
    <#
    .SYNOPSIS
        Fetches web page content using Playwright with HTTP fallback.
    #>
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

function Get-MSRCData {
    <#
    .SYNOPSIS
        Extracts data from advisory pages using vendor-specific modules.
    #>
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
    <#
    .SYNOPSIS
        Gets list of CSV files from output directory.
    #>
    param([string]$OutDir)

    $csvFiles = Get-ChildItem -Path $OutDir -Filter "*.csv" -File | Sort-Object LastWriteTime -Descending
    return $csvFiles
}

function Test-CsvAlreadyScraped {
    <#
    .SYNOPSIS
        Checks if a CSV file has already been scraped.
    #>
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
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    try {
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

function Invoke-AdvisoryUrlScrape {
    <#
    .SYNOPSIS
        Scrapes a single advisory URL.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    if (-not $Url -or $Url -eq '') {
        Write-Log -Message "Empty URL provided to Invoke-AdvisoryUrlScrape" -Level "WARNING"
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
        $extractedData = Get-MSRCData -HtmlContent $pageResult.Content -Url $Url
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

function Invoke-BackgroundScraping {
    <#
    .SYNOPSIS
        Executes CSV scraping in a background runspace to keep GUI responsive.
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
        [Parameter(Mandatory)]
        [string]$RootDir,
        [Parameter(Mandatory)]
        [string]$OutDir,
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
    $runspace.SessionStateProxy.SetVariable("RootDir", $RootDir)
    $runspace.SessionStateProxy.SetVariable("OutDir", $OutDir)
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

                function Get-MSRCData {
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

                function Invoke-AdvisoryUrlScrape {
                    param([string]$Url)
                    if (-not $Url -or $Url -eq '') {
                        return @{ Url = $Url; Status = 'Empty'; DownloadLinks = ''; ExtractedData = ''; Error = 'Empty URL'; LinksFound = 0; DataPartsFound = 0 }
                    }
                    try {
                        $pageResult = Get-WebPage -Url $Url
                        if (-not $pageResult.Success) {
                            return @{ Url = $Url; Status = 'Failed'; DownloadLinks = ''; ExtractedData = 'Failed to fetch page'; Error = $pageResult.Error; LinksFound = 0; DataPartsFound = 0 }
                        }
                        $extractedData = Get-MSRCData -HtmlContent $pageResult.Content -Url $Url
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
                    $result = Invoke-AdvisoryUrlScrape -Url $url

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
        }).AddArgument($syncHash).AddArgument($CsvPath).AddArgument($ForceRescrape).AddArgument($CreateBackup).AddArgument($RootDir).AddArgument($OutDir).AddArgument($Global:LogFile)

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
                                $selectedFile = Join-Path $OutDir $CsvCombo.SelectedItem
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

# -------------------- Main Initialization Function --------------------

function Initialize-AdvisoryTab {
    <#
    .SYNOPSIS
        Initializes the Advisory Scraper tab with all controls and event handlers.

    .PARAMETER Window
        The main WPF window object

    .PARAMETER Controls
        Hashtable containing all Advisory tab control references

    .PARAMETER RootDir
        Root directory of the CVExcel installation

    .PARAMETER OutDir
        Output directory for CSV files
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [hashtable]$Controls,

        [Parameter(Mandatory)]
        [string]$RootDir,

        [Parameter(Mandatory)]
        [string]$OutDir
    )

    Write-Host "Initializing Advisory Scraper tab..." -ForegroundColor Cyan

    # -------------------- Helper Functions for Tab --------------------

    function Update-CsvList {
        $Controls.CsvCombo.Items.Clear()
        $csvFiles = Get-CsvFiles -OutDir $OutDir

        if ($csvFiles.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No CSV files found in 'out' directory.", "No Files")
            return
        }

        foreach ($file in $csvFiles) {
            [void]$Controls.CsvCombo.Items.Add($file.Name)
        }

        $Controls.CsvCombo.SelectedIndex = 0
    }

    function Update-PlaywrightStatus {
        $playwrightAvailable = Test-PlaywrightAvailability
        if ($playwrightAvailable) {
            $Controls.PlaywrightStatusText.Text = "[OK] Playwright available - JavaScript rendering enabled"
            $Controls.PlaywrightStatusText.Foreground = "Green"
        } else {
            $Controls.PlaywrightStatusText.Text = "[WARN] Playwright not available - HTTP fallback mode (install Playwright for better results)"
            $Controls.PlaywrightStatusText.Foreground = "Orange"
        }
    }

    # -------------------- CSV ComboBox Selection Handler --------------------

    $Controls.CsvCombo.Add_SelectionChanged({
            if ($Controls.CsvCombo.SelectedItem) {
                $selectedFile = Join-Path $OutDir $Controls.CsvCombo.SelectedItem
                if (Test-Path $selectedFile) {
                    $fileInfo = Get-Item $selectedFile
                    $csvData = Import-Csv -Path $selectedFile -Encoding UTF8
                    $isScraped = Test-CsvAlreadyScraped -CsvPath $selectedFile

                    $scrapedStatus = if ($isScraped) { "Already scraped" } else { "Not yet scraped" }
                    $Controls.FileInfoText.Text = "File: $($fileInfo.Name) | Size: $([Math]::Round($fileInfo.Length/1KB, 2)) KB | Rows: $($csvData.Count) | Status: $scrapedStatus"

                    if ($isScraped) {
                        $Controls.FileInfoText.Foreground = "Green"
                    } else {
                        $Controls.FileInfoText.Foreground = "Gray"
                    }
                }
            }
        })

    # -------------------- Refresh Button Handler --------------------

    $Controls.RefreshButton.Add_Click({
            Update-CsvList
            [System.Windows.MessageBox]::Show("CSV file list refreshed.", "Refresh")
        })

    # -------------------- Scrape Button Handler --------------------

    $Controls.ScrapeButton.Add_Click({
            if (-not $Controls.CsvCombo.SelectedItem) {
                [System.Windows.MessageBox]::Show("Please select a CSV file first.", "Validation")
                return
            }

            $selectedFile = Join-Path $OutDir $Controls.CsvCombo.SelectedItem

            # Pre-check: Test file availability
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
            $Window.Cursor = 'Wait'
            $Controls.ScrapeButton.Content = "Processing..."
            $Controls.ScrapeButton.IsEnabled = $false
            $Controls.ProgressBar.Value = 0
            $Controls.StatusText.Text = "Initializing..."

            $Global:LogFile = Initialize-LogFile -LogDir $OutDir
            Write-Log -Message "Starting background scraping operation for file: $selectedFile" -Level "INFO"

            # Initialize dependency manager
            Write-Log -Message "Initializing dependency manager..." -Level "INFO"
            $Global:DependencyManager = [DependencyManager]::new($RootDir, $Global:LogFile)
            $null = $Global:DependencyManager.CheckAllDependencies()

            $msrcInstall = $Global:DependencyManager.InstallMsrcModule($true)
            if ($msrcInstall.Success) {
                Write-Log -Message "MSRC module ready (version $($msrcInstall.Version))" -Level "SUCCESS"
            } else {
                Write-Log -Message "MSRC module install failed or declined: $($msrcInstall.Error)" -Level "WARNING"
            }

            # Start background scraping
            $forceRescrape = [bool]$Controls.ForceRescrapeChk.IsChecked
            if ($forceRescrape) {
                Write-Log -Message "Force re-scrape option enabled" -Level "INFO"
            }

            $createBackup = [bool]$Controls.CreateBackupChk.IsChecked
            if ($createBackup) {
                Write-Log -Message "Backup creation enabled" -Level "INFO"
            } else {
                Write-Log -Message "Backup creation disabled by user" -Level "INFO"
            }

            Invoke-BackgroundScraping -CsvPath $selectedFile `
                -ProgressBar $Controls.ProgressBar `
                -StatusText $Controls.StatusText `
                -ScrapeButton $Controls.ScrapeButton `
                -Window $Window `
                -CsvCombo $Controls.CsvCombo `
                -FileInfoText $Controls.FileInfoText `
                -RootDir $RootDir `
                -OutDir $OutDir `
                -ForceRescrape:$forceRescrape `
                -CreateBackup:$createBackup
        })

    # -------------------- Initialize Tab --------------------

    Update-CsvList
    Update-PlaywrightStatus

    Write-Host "  Advisory Scraper tab initialized successfully" -ForegroundColor Green
}

# Functions are available for direct calling in script mode
