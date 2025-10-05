<#
.SYNOPSIS
    Core scraping engine for CVScrape with enhanced reliability and fallback mechanisms.

.DESCRIPTION
    Provides a robust scraping engine with multiple fallback methods, intelligent
    retry logic, and vendor-specific optimizations. Handles Playwright, Selenium,
    and HTTP-based scraping with automatic method selection.
#>

# Import required modules
. "$PSScriptRoot\..\common\Logging.ps1"
. "$PSScriptRoot\..\common\WebFetcher.ps1"
. "$PSScriptRoot\..\vendors\BaseVendor.ps1"
. "$PSScriptRoot\..\vendors\GenericVendor.ps1"
. "$PSScriptRoot\..\vendors\GitHubVendor.ps1"
. "$PSScriptRoot\..\vendors\MicrosoftVendor.ps1"
. "$PSScriptRoot\..\vendors\IBMVendor.ps1"
. "$PSScriptRoot\..\vendors\ZDIVendor.ps1"
. "$PSScriptRoot\..\vendors\VendorManager.ps1"
. "$PSScriptRoot\PlaywrightWrapper.ps1"

class ScrapingEngine {
    [string]$LogFile
    [object]$VendorManager
    [object]$WebFetcher
    [hashtable]$DependencyStatus

    ScrapingEngine([string]$logFile, [hashtable]$dependencyStatus) {
        $this.LogFile = $logFile
        $this.DependencyStatus = $dependencyStatus
        $this.VendorManager = [VendorManager]::new()
        $this.WebFetcher = [WebFetcher]::new($logFile)
    }

    # Main scraping method with intelligent fallback
    [hashtable] ScrapeUrl([string]$url, [hashtable]$options = @{}) {
        if (-not $url -or $url -eq '') {
            return $this.CreateErrorResult($url, 'Empty URL provided')
        }

        Write-Log -Message "Starting to scrape advisory URL: $url" -Level "INFO" -LogFile $this.LogFile

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
            'GitHubAPI'    = @('EnhancedHTTP')
            'Playwright'   = @('Selenium', 'EnhancedHTTP')
            'Selenium'     = @('EnhancedHTTP')
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
                    Success        = $true
                    Url            = $url
                    Status         = 'Success'
                    Content        = $result.Content
                    DownloadLinks  = $result.DownloadLinks -join ' | '
                    ExtractedData  = $result.ExtractedData
                    Method         = 'GitHubAPI'
                    FetchTime      = $totalTime.TotalSeconds
                    TotalTime      = $totalTime.TotalSeconds
                    LinksFound     = $result.DownloadLinks.Count
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
                    Success     = $true
                    Url         = $url
                    Status      = 'Success'
                    Content     = $result.Content
                    Method      = 'Playwright'
                    FetchTime   = $totalTime.TotalSeconds
                    TotalTime   = $totalTime.TotalSeconds
                    ContentSize = $contentSize
                    Warning     = if (-not $hasGoodContent) { 'Content may be incomplete' } else { $null }
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

    # Enhanced HTTP scraping with retry logic and better headers (using WebFetcher)
    [hashtable] ScrapeWithEnhancedHTTP([string]$url, [hashtable]$options) {
        # Use WebFetcher which handles retry, rate limiting, and session management
        $result = $this.WebFetcher.Fetch($url, $options)

        if ($result.Success) {
            # Ensure result has expected fields for ScrapingEngine
            if (-not $result.ContainsKey('TotalTime')) {
                $result.TotalTime = $result.FetchTime
            }
            if (-not $result.ContainsKey('Status')) {
                $result.Status = 'Success'
            }
        }

        return $result
    }

    # Basic HTTP scraping (fallback using WebFetcher)
    [hashtable] ScrapeWithBasicHTTP([string]$url, [hashtable]$options) {
        $result = $this.WebFetcher.FetchBasic($url)

        if ($result.Success) {
            # Ensure result has expected fields
            if (-not $result.ContainsKey('TotalTime')) {
                $result.TotalTime = $result.FetchTime
            }
        }

        return $result
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


    # Create standardized error result
    [hashtable] CreateErrorResult([string]$url, [string]$errorMessage) {
        return @{
            Success        = $false
            Url            = $url
            Status         = 'Error'
            DownloadLinks  = ''
            ExtractedData  = "Error: $errorMessage"
            Error          = $errorMessage
            FetchTime      = 0
            TotalTime      = 0
            LinksFound     = 0
            DataPartsFound = 0
        }
    }

    # Clean up resources
    [void] Cleanup() {
        try {
            # Close any remaining Playwright browsers
            Close-PlaywrightBrowser

            # Cleanup WebFetcher resources
            $this.WebFetcher.Cleanup()

            Write-Log -Message "ScrapingEngine cleanup completed" -Level "DEBUG" -LogFile $this.LogFile
        } catch {
            Write-Log -Message "Error during cleanup: $($_.Exception.Message)" -Level "WARNING" -LogFile $this.LogFile
        }
    }
}

# Class is available for direct instantiation in script mode
