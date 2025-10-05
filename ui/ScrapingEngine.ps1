<#
.SYNOPSIS
    Core scraping engine for CVScrape with enhanced reliability and fallback mechanisms.

.DESCRIPTION
    Provides a robust scraping engine with multiple fallback methods, intelligent
    retry logic, and vendor-specific optimizations. Handles Playwright, Selenium,
    and HTTP-based scraping with automatic method selection.
#>

# Import required modules
. "$PSScriptRoot\vendors\BaseVendor.ps1"
. "$PSScriptRoot\vendors\GenericVendor.ps1"
. "$PSScriptRoot\vendors\GitHubVendor.ps1"
. "$PSScriptRoot\vendors\MicrosoftVendor.ps1"
. "$PSScriptRoot\vendors\IBMVendor.ps1"
. "$PSScriptRoot\vendors\ZDIVendor.ps1"
. "$PSScriptRoot\vendors\VendorManager.ps1"
. "$PSScriptRoot\PlaywrightWrapper.ps1"

class ScrapingEngine {
    [string]$LogFile
    [object]$VendorManager
    [hashtable]$DependencyStatus
    [hashtable]$SessionCache
    [hashtable]$RetryConfig
    [hashtable]$RateLimits

    ScrapingEngine([string]$logFile, [hashtable]$dependencyStatus) {
        $this.LogFile = $logFile
        $this.DependencyStatus = $dependencyStatus
        $this.VendorManager = [VendorManager]::new()
        $this.SessionCache = @{}
        $this.RetryConfig = @{
            MaxRetries = 3
            BaseDelayMs = 1000
            MaxDelayMs = 10000
            JitterMs = 500
        }
        $this.RateLimits = @{
            RequestsPerMinute = 30
            LastRequestTime = @{}
        }
    }

    # Main scraping method with intelligent fallback
    [hashtable] ScrapeUrl([string]$url, [hashtable]$options = @{}) {
        if (-not $url -or $url -eq '') {
            return $this.CreateErrorResult($url, 'Empty URL provided')
        }

        Write-Log -Message "Starting to scrape advisory URL: $url" -Level "INFO" -LogFile $this.LogFile

        # Rate limiting
        $this.ApplyRateLimit($url)

        # Determine best scraping method
        $method = $this.DetermineScrapingMethod($url)
        Write-Log -Message "Using scraping method: $method for URL: $url" -Level "DEBUG" -LogFile $this.LogFile

        # Try scraping with selected method and fallbacks
        $result = $this.ScrapeWithMethod($url, $method, $options)

        # Apply vendor-specific post-processing
        $result = $this.ApplyVendorPostProcessing($url, $result)

        return $result
    }

    # Determine the best scraping method for a URL
    [string] DetermineScrapingMethod([string]$url) {
        # GitHub URLs - prefer API
        if ($url -match 'github\.com') {
            return 'GitHubAPI'
        }

        # MSRC URLs - prefer Playwright if available
        if ($url -match 'msrc\.microsoft\.com') {
            if ($this.DependencyStatus.Playwright.Available -and $this.DependencyStatus.Playwright.BrowsersInstalled) {
                return 'Playwright'
            } elseif ($this.DependencyStatus.Selenium.Available) {
                return 'Selenium'
            } else {
                return 'EnhancedHTTP'
            }
        }

        # Other dynamic sites - prefer Playwright/Selenium
        if ($this.IsDynamicSite($url)) {
            if ($this.DependencyStatus.Playwright.Available -and $this.DependencyStatus.Playwright.BrowsersInstalled) {
                return 'Playwright'
            } elseif ($this.DependencyStatus.Selenium.Available) {
                return 'Selenium'
            }
        }

        # Default to enhanced HTTP
        return 'EnhancedHTTP'
    }

    # Check if a site is likely to be dynamic/JavaScript-heavy
    [bool] IsDynamicSite([string]$url) {
        $dynamicPatterns = @(
            'msrc\.microsoft\.com',
            'security\.adobe\.com',
            'portal\.msrc\.microsoft\.com',
            'www\.oracle\.com.*security',
            'support\.apple\.com.*security'
        )

        foreach ($pattern in $dynamicPatterns) {
            if ($url -match $pattern) {
                return $true
            }
        }

        return $false
    }

    # Scrape using the specified method with fallbacks
    [hashtable] ScrapeWithMethod([string]$url, [string]$method, [hashtable]$options) {
        $methods = @($method)

        # Define fallback chain
        $fallbackMap = @{
            'GitHubAPI' = @('EnhancedHTTP')
            'Playwright' = @('Selenium', 'EnhancedHTTP')
            'Selenium' = @('EnhancedHTTP')
            'EnhancedHTTP' = @('BasicHTTP')
        }

        if ($fallbackMap.ContainsKey($method)) {
            $methods += $fallbackMap[$method]
        }

        $lastError = $null

        foreach ($currentMethod in $methods) {
            try {
                Write-Log -Message "Attempting to scrape with method: $currentMethod" -Level "DEBUG" -LogFile $this.LogFile

                $result = switch ($currentMethod) {
                    'GitHubAPI' { $this.ScrapeWithGitHubAPI($url, $options) }
                    'Playwright' { $this.ScrapeWithPlaywright($url, $options) }
                    'Selenium' { $this.ScrapeWithSelenium($url, $options) }
                    'EnhancedHTTP' { $this.ScrapeWithEnhancedHTTP($url, $options) }
                    'BasicHTTP' { $this.ScrapeWithBasicHTTP($url, $options) }
                }

                if ($result.Success) {
                    $result.Method = $currentMethod
                    return $result
                } else {
                    $lastError = $result.Error
                    Write-Log -Message "Method $currentMethod failed: $lastError" -Level "WARNING" -LogFile $this.LogFile
                }
            } catch {
                $lastError = $_.Exception.Message
                Write-Log -Message "Method $currentMethod threw exception: $lastError" -Level "ERROR" -LogFile $this.LogFile
            }
        }

        # All methods failed
        return $this.CreateErrorResult($url, "All scraping methods failed. Last error: $lastError")
    }

    # GitHub API scraping
    [hashtable] ScrapeWithGitHubAPI([string]$url, [hashtable]$options) {
        try {
            $startTime = Get-Date
            $result = $this.VendorManager.GetApiData($url, $null)
            $totalTime = (Get-Date) - $startTime

            if ($result.Success) {
                Write-Log -Message "Successfully extracted GitHub data via API" -Level "SUCCESS" -LogFile $this.LogFile
                return @{
                    Success = $true
                    Url = $url
                    Status = 'Success'
                    Content = $result.Content
                    DownloadLinks = $result.DownloadLinks -join ' | '
                    ExtractedData = $result.ExtractedData
                    Method = 'GitHubAPI'
                    FetchTime = $totalTime.TotalSeconds
                    TotalTime = $totalTime.TotalSeconds
                    LinksFound = $result.DownloadLinks.Count
                    DataPartsFound = if ($result.ExtractedData) { ($result.ExtractedData -split '\|').Count } else { 0 }
                }
            } else {
                return $this.CreateErrorResult($url, "GitHub API failed: $($result.Error)")
            }
        } catch {
            return $this.CreateErrorResult($url, "GitHub API exception: $($_.Exception.Message)")
        }
    }

    # Playwright scraping
    [hashtable] ScrapeWithPlaywright([string]$url, [hashtable]$options) {
        try {
            if (-not $this.DependencyStatus.Playwright.Available -or -not $this.DependencyStatus.Playwright.BrowsersInstalled) {
                return $this.CreateErrorResult($url, "Playwright not available or browsers not installed")
            }

            Write-Log -Message "Using Playwright to render page: $url" -Level "INFO" -LogFile $this.LogFile

            $startTime = Get-Date

            # Initialize Playwright browser
            Write-Log -Message "Initializing Playwright browser..." -Level "DEBUG" -LogFile $this.LogFile
            $initResult = New-PlaywrightBrowser -BrowserType chromium -TimeoutSeconds 30

            if (-not $initResult.Success) {
                return $this.CreateErrorResult($url, "Failed to initialize Playwright browser: $($initResult.Error)")
            }

            Write-Log -Message "Playwright browser initialized successfully" -Level "SUCCESS" -LogFile $this.LogFile

            # Navigate to page
            $waitSeconds = if ($options.WaitSeconds) { $options.WaitSeconds } else { 8 }
            $result = Invoke-PlaywrightNavigate -Url $url -WaitSeconds $waitSeconds

            if ($result.Success) {
                $totalTime = (Get-Date) - $startTime

                # Validate content quality
                $contentSize = $result.Size
                $hasGoodContent = $contentSize -gt 10000 -and $result.Content -match '(CVE|vulnerability|security|update|patch|KB)'

                if ($hasGoodContent) {
                    Write-Log -Message "Successfully rendered page with Playwright - ${contentSize} bytes" -Level "SUCCESS" -LogFile $this.LogFile
                } else {
                    Write-Log -Message "Page rendered but content appears incomplete - ${contentSize} bytes" -Level "WARNING" -LogFile $this.LogFile
                }

                return @{
                    Success = $true
                    Url = $url
                    Status = 'Success'
                    Content = $result.Content
                    Method = 'Playwright'
                    FetchTime = $totalTime.TotalSeconds
                    TotalTime = $totalTime.TotalSeconds
                    ContentSize = $contentSize
                    Warning = if (-not $hasGoodContent) { 'Content may be incomplete' } else { $null }
                }
            } else {
                return $this.CreateErrorResult($url, "Playwright navigation failed: $($result.Error)")
            }
        } catch {
            return $this.CreateErrorResult($url, "Playwright exception: $($_.Exception.Message)")
        } finally {
            # Always cleanup browser
            try {
                Close-PlaywrightBrowser
                Write-Log -Message "Playwright browser closed" -Level "DEBUG" -LogFile $this.LogFile
            } catch {
                Write-Log -Message "Error closing Playwright browser: $($_.Exception.Message)" -Level "WARNING" -LogFile $this.LogFile
            }
        }
    }

    # Selenium scraping (placeholder - implement if needed)
    [hashtable] ScrapeWithSelenium([string]$url, [hashtable]$options) {
        return $this.CreateErrorResult($url, "Selenium scraping not implemented yet")
    }

    # Enhanced HTTP scraping with retry logic and better headers
    [hashtable] ScrapeWithEnhancedHTTP([string]$url, [hashtable]$options) {
        $maxRetries = $this.RetryConfig.MaxRetries
        $attempt = 0
        $lastException = $null

        while ($attempt -lt $maxRetries) {
            $attempt++

            try {
                Write-Log -Message "Attempting enhanced HTTP fetch (attempt $attempt/$maxRetries): $url" -Level "DEBUG" -LogFile $this.LogFile

                $startTime = Get-Date
                $result = $this.InvokeEnhancedWebRequest($url, $options)
                $fetchTime = (Get-Date) - $startTime

                if ($result.Success) {
                    Write-Log -Message "Successfully fetched page content (Size: $($result.Content.Length) bytes, Time: $($fetchTime.TotalSeconds)s)" -Level "SUCCESS" -LogFile $this.LogFile

                    return @{
                        Success = $true
                        Url = $url
                        Status = 'Success'
                        Content = $result.Content
                        Method = 'EnhancedHTTP'
                        FetchTime = $fetchTime.TotalSeconds
                        TotalTime = $fetchTime.TotalSeconds
                        StatusCode = $result.StatusCode
                        Session = $result.Session
                    }
                } else {
                    $lastException = $result.Error
                    Write-Log -Message "Enhanced HTTP attempt $attempt failed: $lastException" -Level "WARNING" -LogFile $this.LogFile
                }
            } catch {
                $lastException = $_.Exception.Message
                Write-Log -Message "Enhanced HTTP attempt $attempt exception: $lastException" -Level "ERROR" -LogFile $this.LogFile
            }

            # Apply retry delay if not the last attempt
            if ($attempt -lt $maxRetries) {
                $delay = [Math]::Min(
                    $this.RetryConfig.BaseDelayMs * [Math]::Pow(2, $attempt - 1),
                    $this.RetryConfig.MaxDelayMs
                )
                $jitter = Get-Random -Minimum 0 -Maximum $this.RetryConfig.JitterMs
                $totalDelay = $delay + $jitter

                Write-Log -Message "Retrying in $totalDelay ms..." -Level "INFO" -LogFile $this.LogFile
                Start-Sleep -Milliseconds $totalDelay
            }
        }

        return $this.CreateErrorResult($url, "Enhanced HTTP failed after $maxRetries attempts. Last error: $lastException")
    }

    # Basic HTTP scraping (fallback)
    [hashtable] ScrapeWithBasicHTTP([string]$url, [hashtable]$options) {
        try {
            $startTime = Get-Date

            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $fetchTime = (Get-Date) - $startTime

            Write-Log -Message "Basic HTTP fetch successful (Size: $($response.Content.Length) bytes, Time: $($fetchTime.TotalSeconds)s)" -Level "SUCCESS" -LogFile $this.LogFile

            return @{
                Success = $true
                Url = $url
                Status = 'Success'
                Content = $response.Content
                Method = 'BasicHTTP'
                FetchTime = $fetchTime.TotalSeconds
                TotalTime = $fetchTime.TotalSeconds
                StatusCode = $response.StatusCode
            }
        } catch {
            return $this.CreateErrorResult($url, "Basic HTTP failed: $($_.Exception.Message)")
        }
    }

    # Enhanced web request with better headers and session management
    [hashtable] InvokeEnhancedWebRequest([string]$url, [hashtable]$options) {
        # Get or create session for this domain
        $domain = ([System.Uri]$url).Host
        $session = if ($this.SessionCache.ContainsKey($domain)) { $this.SessionCache[$domain] } else { $null }

        # Enhanced headers to mimic real browser and avoid bot detection
        $headers = @{
            'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8'
            'Accept-Language' = 'en-US,en;q=0.9'
            'Accept-Encoding' = 'gzip, deflate, br'
            'DNT' = '1'
            'Connection' = 'keep-alive'
            'Upgrade-Insecure-Requests' = '1'
            'Sec-Fetch-Dest' = 'document'
            'Sec-Fetch-Mode' = 'navigate'
            'Sec-Fetch-Site' = 'none'
            'Cache-Control' = 'max-age=0'
        }

        # Add referer for same domain
        try {
            $uri = [System.Uri]$url
            $headers['Referer'] = "$($uri.Scheme)://$($uri.Host)/"
        } catch {
            # Skip if URL parsing fails
        }

        # Add small random delay to appear more human-like
        $humanDelay = Get-Random -Minimum 500 -Maximum 1500
        Start-Sleep -Milliseconds $humanDelay

        $invokeParams = @{
            Uri = $url
            Headers = $headers
            TimeoutSec = 30
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }

        # Use session if available
        if ($session) {
            $invokeParams['WebSession'] = $session
        } else {
            $invokeParams['SessionVariable'] = 'newSession'
        }

        $response = Invoke-WebRequest @invokeParams

        # Store session for future use
        if ($newSession) {
            $this.SessionCache[$domain] = $newSession
        }

        return @{
            Success = $true
            Content = $response.Content
            StatusCode = $response.StatusCode
            Session = if ($session) { $session } elseif ($newSession) { $newSession } else { $null }
        }
    }

    # Apply vendor-specific post-processing
    [hashtable] ApplyVendorPostProcessing([string]$url, [hashtable]$result) {
        if (-not $result.Success -or -not $result.Content) {
            return $result
        }

        try {
            # Extract data using vendor manager
            $extractedData = $this.VendorManager.ExtractData($result.Content, $url)

            # Extract download links
            $vendor = $this.VendorManager.GetVendor($url)
            $downloadLinks = $vendor.ExtractDownloadLinks($result.Content, $url)

            # Build result summary
            $extractedParts = @()
            if ($extractedData.PatchID) { $extractedParts += "Patch: $($extractedData.PatchID)" }
            if ($extractedData.FixVersion) { $extractedParts += "Fix: $($extractedData.FixVersion)" }
            if ($extractedData.AffectedVersions) { $extractedParts += "Affected: $($extractedData.AffectedVersions)" }
            if ($extractedData.Remediation) { $extractedParts += "Remediation: $($extractedData.Remediation)" }

            $result.DownloadLinks = ($downloadLinks -join ' | ')
            $result.ExtractedData = if ($extractedParts.Count -gt 0) { $extractedParts -join ' | ' } else { 'No specific data extracted' }
            $result.LinksFound = $downloadLinks.Count
            $result.DataPartsFound = $extractedParts.Count

            # Add vendor information
            $result.VendorUsed = $extractedData.VendorUsed
            $result.VendorMethod = $extractedData.VendorMethod

            # Log extraction results
            $vendorForQuality = $this.VendorManager.GetVendor($url)
            $dataQuality = $vendorForQuality.TestDataQuality($extractedData)
            $qualityStatus = if ($dataQuality.IsGoodQuality) { "GOOD" } else { "LOW" }

            Write-Log -Message "Extracted patch info for $url using $($extractedData.VendorUsed) - Quality: $qualityStatus ($($dataQuality.QualityScore)/100)" -Level "DEBUG" -LogFile $this.LogFile

        } catch {
            Write-Log -Message "Error in vendor post-processing: $($_.Exception.Message)" -Level "ERROR" -LogFile $this.LogFile
        }

        return $result
    }

    # Apply rate limiting
    [void] ApplyRateLimit([string]$url) {
        $domain = ([System.Uri]$url).Host
        $now = Get-Date

        if ($this.RateLimits.LastRequestTime.ContainsKey($domain)) {
            $lastRequest = $this.RateLimits.LastRequestTime[$domain]
            $timeSinceLastRequest = ($now - $lastRequest).TotalMilliseconds
            $minInterval = 60000 / $this.RateLimits.RequestsPerMinute  # Convert to milliseconds

            if ($timeSinceLastRequest -lt $minInterval) {
                $delay = $minInterval - $timeSinceLastRequest
                Write-Log -Message "Rate limiting: waiting $([Math]::Round($delay))ms for domain $domain" -Level "DEBUG" -LogFile $this.LogFile
                Start-Sleep -Milliseconds $delay
            }
        }

        $this.RateLimits.LastRequestTime[$domain] = $now
    }

    # Create standardized error result
    [hashtable] CreateErrorResult([string]$url, [string]$errorMessage) {
        return @{
            Success = $false
            Url = $url
            Status = 'Error'
            DownloadLinks = ''
            ExtractedData = "Error: $errorMessage"
            Error = $errorMessage
            FetchTime = 0
            TotalTime = 0
            LinksFound = 0
            DataPartsFound = 0
        }
    }

    # Clean up resources
    [void] Cleanup() {
        try {
            # Close any remaining Playwright browsers
            Close-PlaywrightBrowser

            # Clear session cache
            $this.SessionCache.Clear()

            Write-Log -Message "ScrapingEngine cleanup completed" -Level "DEBUG" -LogFile $this.LogFile
        } catch {
            Write-Log -Message "Error during cleanup: $($_.Exception.Message)" -Level "WARNING" -LogFile $this.LogFile
        }
    }
}

# Export the class
Export-ModuleMember -Type ScrapingEngine
