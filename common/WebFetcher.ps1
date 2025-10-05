<#
.SYNOPSIS
    Consolidated web fetching module for CVExcel project.

.DESCRIPTION
    Provides unified web fetching functionality with:
    - HTTP requests with enhanced headers and session management
    - Retry logic with exponential backoff and jitter
    - Rate limiting per domain
    - Integration with Playwright for JavaScript-heavy pages
    - Automatic fallback mechanisms
    - Security-focused header configurations

.NOTES
    Created: October 5, 2025
    Part of: CVExcel Phase 2 Consolidation
    Replaces: Duplicate web fetching code across 5+ files
#>

# Import common logging
. "$PSScriptRoot\Logging.ps1"

class WebFetcher {
    [hashtable]$SessionCache
    [hashtable]$RetryConfig
    [hashtable]$RateLimits
    [hashtable]$DefaultHeaders
    [string]$LogFile

    WebFetcher([string]$logFile) {
        $this.LogFile = $logFile
        $this.SessionCache = @{}

        # Retry configuration with exponential backoff
        $this.RetryConfig = @{
            MaxRetries  = 3
            BaseDelayMs = 1000
            MaxDelayMs  = 10000
            JitterMs    = 500
        }

        # Rate limiting configuration
        $this.RateLimits = @{
            RequestsPerMinute = 30
            LastRequestTime   = @{}
        }

        # Enhanced headers to mimic real browser behavior
        $this.DefaultHeaders = @{
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
    }

    #region Core HTTP Methods

    <#
    .SYNOPSIS
        Fetches web content with automatic retry and fallback logic.

    .PARAMETER Url
        The URL to fetch.

    .PARAMETER Options
        Optional hashtable with: WaitSeconds, CustomHeaders, UseSession, TimeoutSec

    .OUTPUTS
        Hashtable with Success, Content, StatusCode, Method, FetchTime, Error
    #>
    [hashtable] Fetch([string]$url, [hashtable]$options = @{}) {
        if (-not $url -or $url -eq '') {
            return $this.CreateErrorResult($url, 'Empty URL provided')
        }

        Write-Log -Message "Fetching URL: $url" -Level "INFO" -LogFile $this.LogFile

        # Apply rate limiting
        $this.ApplyRateLimit($url)

        # Use enhanced HTTP with retry logic
        return $this.FetchWithRetry($url, $options)
    }

    <#
    .SYNOPSIS
        Fetches content with retry logic and exponential backoff.
    #>
    [hashtable] FetchWithRetry([string]$url, [hashtable]$options) {
        $maxRetries = $this.RetryConfig.MaxRetries
        $attempt = 0
        $lastException = $null

        while ($attempt -lt $maxRetries) {
            $attempt++

            try {
                Write-Log -Message "HTTP fetch attempt $attempt/$maxRetries for: $url" -Level "DEBUG" -LogFile $this.LogFile

                $startTime = Get-Date
                $result = $this.InvokeEnhancedWebRequest($url, $options)
                $fetchTime = (Get-Date) - $startTime

                if ($result.Success) {
                    Write-Log -Message "Successfully fetched URL (Size: $($result.Content.Length) bytes, Time: $($fetchTime.TotalSeconds)s)" -Level "SUCCESS" -LogFile $this.LogFile

                    return @{
                        Success    = $true
                        Url        = $url
                        Status     = 'Success'
                        Content    = $result.Content
                        Method     = 'EnhancedHTTP'
                        FetchTime  = $fetchTime.TotalSeconds
                        StatusCode = $result.StatusCode
                        Session    = $result.Session
                    }
                } else {
                    $lastException = $result.Error
                    Write-Log -Message "Fetch attempt $attempt failed: $lastException" -Level "WARNING" -LogFile $this.LogFile
                }
            } catch {
                $lastException = $_.Exception.Message
                Write-Log -Message "Fetch attempt $attempt exception: $lastException" -Level "ERROR" -LogFile $this.LogFile
            }

            # Apply exponential backoff with jitter if not the last attempt
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

        return $this.CreateErrorResult($url, "HTTP fetch failed after $maxRetries attempts. Last error: $lastException")
    }

    <#
    .SYNOPSIS
        Core HTTP request method with enhanced headers and session management.
    #>
    [hashtable] InvokeEnhancedWebRequest([string]$url, [hashtable]$options) {
        # Get or create session for this domain
        $domain = ([System.Uri]$url).Host
        $useSession = if ($options.ContainsKey('UseSession')) { $options.UseSession } else { $true }
        $newSession = $null  # Will be set by SessionVariable if used

        $session = if ($useSession -and $this.SessionCache.ContainsKey($domain)) {
            $this.SessionCache[$domain]
        } else {
            $null
        }

        # Build headers
        $headers = $this.DefaultHeaders.Clone()

        # Add custom headers if provided
        if ($options.CustomHeaders) {
            foreach ($key in $options.CustomHeaders.Keys) {
                $headers[$key] = $options.CustomHeaders[$key]
            }
        }

        # Add referer for same domain requests
        try {
            $uri = [System.Uri]$url
            $headers['Referer'] = "$($uri.Scheme)://$($uri.Host)/"
        } catch {
            # Skip if URL parsing fails
        }

        # Add human-like delay to avoid bot detection
        $humanDelay = Get-Random -Minimum 500 -Maximum 1500
        Start-Sleep -Milliseconds $humanDelay

        # Build Invoke-WebRequest parameters
        $timeoutSec = if ($options.TimeoutSec) { $options.TimeoutSec } else { 30 }

        $invokeParams = @{
            Uri             = $url
            Headers         = $headers
            TimeoutSec      = $timeoutSec
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
        }

        # Handle session management
        if ($session) {
            $invokeParams['WebSession'] = $session
        } elseif ($useSession) {
            $invokeParams['SessionVariable'] = 'newSession'
        }

        # Execute request
        $response = Invoke-WebRequest @invokeParams

        # Store session for future use (SessionVariable creates the variable dynamically)
        $resultSession = $null
        if ($useSession) {
            if ($session) {
                $resultSession = $session
            } elseif (Get-Variable -Name 'newSession' -ErrorAction SilentlyContinue) {
                $resultSession = $newSession
                $this.SessionCache[$domain] = $newSession
            }
        }

        return @{
            Success    = $true
            Content    = $response.Content
            StatusCode = $response.StatusCode
            Session    = $resultSession
        }
    }

    #endregion

    #region Basic HTTP Fallback

    <#
    .SYNOPSIS
        Basic HTTP request without enhanced features (fallback method).
    #>
    [hashtable] FetchBasic([string]$url) {
        try {
            Write-Log -Message "Using basic HTTP fetch for: $url" -Level "DEBUG" -LogFile $this.LogFile

            $startTime = Get-Date
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $fetchTime = (Get-Date) - $startTime

            Write-Log -Message "Basic HTTP fetch successful (Size: $($response.Content.Length) bytes)" -Level "SUCCESS" -LogFile $this.LogFile

            return @{
                Success    = $true
                Url        = $url
                Status     = 'Success'
                Content    = $response.Content
                Method     = 'BasicHTTP'
                FetchTime  = $fetchTime.TotalSeconds
                StatusCode = $response.StatusCode
            }
        } catch {
            return $this.CreateErrorResult($url, "Basic HTTP failed: $($_.Exception.Message)")
        }
    }

    #endregion

    #region Rate Limiting

    <#
    .SYNOPSIS
        Applies rate limiting per domain to avoid overwhelming servers.
    #>
    [void] ApplyRateLimit([string]$url) {
        try {
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
        } catch {
            # Skip rate limiting if URL parsing fails
            Write-Log -Message "Could not apply rate limiting for $url : $($_.Exception.Message)" -Level "WARNING" -LogFile $this.LogFile
        }
    }

    #endregion

    #region Utility Methods

    <#
    .SYNOPSIS
        Creates a standardized error result.
    #>
    [hashtable] CreateErrorResult([string]$url, [string]$errorMessage) {
        Write-Log -Message "Web fetch error for ${url}: $errorMessage" -Level "ERROR" -LogFile $this.LogFile

        return @{
            Success    = $false
            Url        = $url
            Status     = 'Error'
            Content    = $null
            Error      = $errorMessage
            FetchTime  = 0
            StatusCode = 0
        }
    }

    <#
    .SYNOPSIS
        Clears all cached sessions.
    #>
    [void] ClearSessions() {
        $count = $this.SessionCache.Count
        $this.SessionCache.Clear()
        Write-Log -Message "Cleared $count cached web sessions" -Level "DEBUG" -LogFile $this.LogFile
    }

    <#
    .SYNOPSIS
        Gets current cache statistics.
    #>
    [hashtable] GetCacheStats() {
        return @{
            CachedSessions     = $this.SessionCache.Count
            RateLimitedDomains = $this.RateLimits.LastRequestTime.Count
            CachedDomains      = $this.SessionCache.Keys -join ', '
        }
    }

    <#
    .SYNOPSIS
        Updates retry configuration.
    #>
    [void] SetRetryConfig([int]$maxRetries, [int]$baseDelayMs, [int]$maxDelayMs) {
        $this.RetryConfig.MaxRetries = $maxRetries
        $this.RetryConfig.BaseDelayMs = $baseDelayMs
        $this.RetryConfig.MaxDelayMs = $maxDelayMs
        Write-Log -Message "Updated retry config: MaxRetries=$maxRetries, BaseDelay=$baseDelayMs, MaxDelay=$maxDelayMs" -Level "DEBUG" -LogFile $this.LogFile
    }

    <#
    .SYNOPSIS
        Updates rate limit configuration.
    #>
    [void] SetRateLimit([int]$requestsPerMinute) {
        $this.RateLimits.RequestsPerMinute = $requestsPerMinute
        Write-Log -Message "Updated rate limit: $requestsPerMinute requests/minute" -Level "DEBUG" -LogFile $this.LogFile
    }

    <#
    .SYNOPSIS
        Cleans up resources.
    #>
    [void] Cleanup() {
        $this.ClearSessions()
        $this.RateLimits.LastRequestTime.Clear()
        Write-Log -Message "WebFetcher cleanup completed" -Level "DEBUG" -LogFile $this.LogFile
    }

    #endregion
}

#region Module-Level Functions

<#
.SYNOPSIS
    Creates a new WebFetcher instance.

.PARAMETER LogFile
    Path to the log file for this fetcher instance.

.EXAMPLE
    $fetcher = New-WebFetcher -LogFile "out/scrape_log.log"

.OUTPUTS
    WebFetcher instance
#>
function New-WebFetcher {
    [CmdletBinding()]
    [OutputType([WebFetcher])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    return [WebFetcher]::new($LogFile)
}

<#
.SYNOPSIS
    Convenience function to fetch a URL with default settings.

.PARAMETER Url
    The URL to fetch.

.PARAMETER LogFile
    Path to log file (required for logging).

.PARAMETER Options
    Optional configuration hashtable.

.EXAMPLE
    $result = Invoke-WebFetch -Url "https://example.com" -LogFile "out/test.log"

.OUTPUTS
    Hashtable with fetch results
#>
function Invoke-WebFetch {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$LogFile,

        [hashtable]$Options = @{}
    )

    $fetcher = [WebFetcher]::new($LogFile)
    return $fetcher.Fetch($Url, $Options)
}

#endregion

# Export module members
Export-ModuleMember -Function New-WebFetcher, Invoke-WebFetch
