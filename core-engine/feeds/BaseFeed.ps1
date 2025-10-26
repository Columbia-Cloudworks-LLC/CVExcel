# BaseFeed.ps1 - Base class for vulnerability data feed modules
# This module defines the common interface for all vulnerability data feeds

# Import common modules
. "$PSScriptRoot/../common/ModuleLoader.ps1"
. "$PSScriptRoot/../common/DataSchemas.ps1"

# Common logging function for all feed modules
function Write-FeedLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$FeedName = "BaseFeed"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [Feed:$FeedName] $Message"

    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "INFO" { "Cyan" }
        "DEBUG" { "Gray" }
        default { "White" }
    }

    Write-Host $logEntry -ForegroundColor $color
}

# Base class for all vulnerability data feeds
class BaseFeed {
    [string]$FeedName
    [string]$FeedType
    [string[]]$SupportedDomains
    [hashtable]$DefaultHeaders
    [hashtable]$Configuration
    [datetime]$LastUpdate
    [bool]$IsEnabled

    BaseFeed([string]$name, [string]$type, [string[]]$domains) {
        $this.FeedName = $name
        $this.FeedType = $type
        $this.SupportedDomains = $domains
        $this.IsEnabled = $true
        $this.LastUpdate = Get-Date
        $this.Configuration = @{}

        $this.DefaultHeaders = @{
            'User-Agent' = 'CVExcel-CoreEngine/1.0 (Vulnerability Data Feed)'
            'Accept' = 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
            'Accept-Language' = 'en-US,en;q=0.9'
            'Accept-Encoding' = 'gzip, deflate, br'
            'Connection' = 'keep-alive'
            'Cache-Control' = 'no-cache'
        }
    }

    # Abstract method - must be implemented by each feed
    [hashtable] GetVulnerabilityData([string]$cveId) {
        throw "GetVulnerabilityData method must be implemented by feed-specific classes"
    }

    # Abstract method - must be implemented by each feed
    [hashtable] GetBulkVulnerabilityData([string[]]$cveIds) {
        throw "GetBulkVulnerabilityData method must be implemented by feed-specific classes"
    }

    # Abstract method - must be implemented by each feed
    [hashtable] SearchVulnerabilities([hashtable]$searchCriteria) {
        throw "SearchVulnerabilities method must be implemented by feed-specific classes"
    }

    # Check if this feed can handle the given CVE or URL
    [bool] CanHandle([string]$identifier) {
        foreach ($domain in $this.SupportedDomains) {
            if ($identifier -like "*$domain*") {
                return $true
            }
        }
        return $false
    }

    # Common method to clean and validate data
    [hashtable] CleanVulnerabilityData([hashtable]$rawData) {
        $cleanedData = @{
            CVE = $null
            Title = $null
            Description = $null
            Severity = $null
            CVSSScore = $null
            CVSSVector = $null
            References = @()
            AffectedProducts = @()
            Remediation = $null
            PublishedDate = $null
            LastModifiedDate = $null
            Source = $this.FeedName
            Confidence = "Medium"
        }

        # Clean and validate each field
        foreach ($key in $rawData.Keys) {
            $value = $rawData[$key]

            if ($value -and $value -ne '') {
                switch ($key.ToLower()) {
                    'cve' {
                        if ($value -match 'CVE-\d{4}-\d+') {
                            $cleanedData.CVE = $value
                        }
                    }
                    'title' {
                        $cleanedData.Title = $this.CleanText($value)
                    }
                    'description' {
                        $cleanedData.Description = $this.CleanText($value)
                    }
                    'severity' {
                        $validSeverities = @("Critical", "High", "Medium", "Low", "Informational")
                        if ($validSeverities -contains $value) {
                            $cleanedData.Severity = $value
                        }
                    }
                    'cvssscore' {
                        if ($value -match '^\d+(\.\d+)?$' -and [double]$value -ge 0 -and [double]$value -le 10) {
                            $cleanedData.CVSSScore = [double]$value
                        }
                    }
                    'cvssvector' {
                        $cleanedData.CVSSVector = $this.CleanText($value)
                    }
                    'references' {
                        if ($value -is [array]) {
                            $cleanedData.References = $value
                        } else {
                            $cleanedData.References = @($value)
                        }
                    }
                    'affectedproducts' {
                        if ($value -is [array]) {
                            $cleanedData.AffectedProducts = $value
                        } else {
                            $cleanedData.AffectedProducts = @($value)
                        }
                    }
                    'remediation' {
                        $cleanedData.Remediation = $this.CleanText($value)
                    }
                    'publisheddate' {
                        if ($value -is [datetime]) {
                            $cleanedData.PublishedDate = $value
                        } else {
                            try {
                                $cleanedData.PublishedDate = [datetime]::Parse($value)
                            } catch {
                                Write-FeedLog "Invalid date format: $value" -Level "WARNING" -FeedName $this.FeedName
                            }
                        }
                    }
                    'lastmodifieddate' {
                        if ($value -is [datetime]) {
                            $cleanedData.LastModifiedDate = $value
                        } else {
                            try {
                                $cleanedData.LastModifiedDate = [datetime]::Parse($value)
                            } catch {
                                Write-FeedLog "Invalid date format: $value" -Level "WARNING" -FeedName $this.FeedName
                            }
                        }
                    }
                }
            }
        }

        return $cleanedData
    }

    # Common method to clean text content
    [string] CleanText([string]$text) {
        if (-not $text) { return '' }

        # Remove HTML tags
        $cleaned = $text -replace '<[^>]+>', ' '

        # Decode HTML entities
        $cleaned = $cleaned -replace '&nbsp;', ' '
        $cleaned = $cleaned -replace '&lt;', '<'
        $cleaned = $cleaned -replace '&gt;', '>'
        $cleaned = $cleaned -replace '&amp;', '&'
        $cleaned = $cleaned -replace '&quot;', '"'
        $cleaned = $cleaned -replace '&#39;', "'"
        $cleaned = $cleaned -replace '&apos;', "'"

        # Remove excessive whitespace
        $cleaned = $cleaned -replace '\s+', ' '
        $cleaned = $cleaned.Trim()

        # Limit length
        if ($cleaned.Length -gt 1000) {
            $cleaned = $cleaned.Substring(0, 997) + "..."
        }

        return $cleaned
    }

    # Common method to make HTTP requests with retry logic
    [hashtable] Invoke-SafeWebRequest {
        param(
            [string]$Uri,
            [hashtable]$Headers = @{},
            [string]$Method = "GET",
            [int]$TimeoutSeconds = 30,
            [int]$MaxRetries = 3
        )

        $retryCount = 0
        $lastError = $null

        do {
            try {
                $requestHeaders = $this.DefaultHeaders.Clone()
                foreach ($key in $Headers.Keys) {
                    $requestHeaders[$key] = $Headers[$key]
                }

                $response = Invoke-WebRequest -Uri $Uri -Headers $requestHeaders -Method $Method -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop

                return @{
                    Success = $true
                    StatusCode = $response.StatusCode
                    Content = $response.Content
                    Headers = $response.Headers
                    Method = "HTTP"
                }
            } catch {
                $retryCount++
                $lastError = $_.Exception.Message

                Write-FeedLog "Request failed (attempt $retryCount): $lastError" -Level "WARNING" -FeedName $this.FeedName

                if ($retryCount -lt $MaxRetries) {
                    $delay = [Math]::Pow(2, $retryCount - 1) * 1000  # Exponential backoff
                    Write-FeedLog "Retrying in $delay ms..." -Level "DEBUG" -FeedName $this.FeedName
                    Start-Sleep -Milliseconds $delay
                }
            }
        } while ($retryCount -lt $MaxRetries)

        return @{
            Success = $false
            Error   = $lastError
            Method  = "HTTP"
        }
    }

    # Common method to make API requests with JSON response
    [hashtable] Invoke-SafeApiRequest {
        param(
            [string]$Uri,
            [hashtable]$Headers = @{},
            [string]$Method = "GET",
            [hashtable]$Body = @{},
            [int]$TimeoutSeconds = 30,
            [int]$MaxRetries = 3
        )

        $retryCount = 0
        $lastError = $null

        do {
            try {
                $requestHeaders = $this.DefaultHeaders.Clone()
                $requestHeaders['Accept'] = 'application/json'
                $requestHeaders['Content-Type'] = 'application/json'

                foreach ($key in $Headers.Keys) {
                    $requestHeaders[$key] = $Headers[$key]
                }

                $invokeParams = @{
                    Uri             = $Uri
                    Headers         = $requestHeaders
                    Method          = $Method
                    TimeoutSec      = $TimeoutSeconds
                    UseBasicParsing = $true
                    ErrorAction     = 'Stop'
                }

                if ($Body.Count -gt 0 -and $Method -in @('POST', 'PUT', 'PATCH')) {
                    $invokeParams['Body'] = ($Body | ConvertTo-Json -Depth 10)
                }

                $response = Invoke-RestMethod @invokeParams

                return @{
                    Success = $true
                    Data    = $response
                    Method  = "API"
                }
            } catch {
                $retryCount++
                $lastError = $_.Exception.Message

                Write-FeedLog "API request failed (attempt $retryCount): $lastError" -Level "WARNING" -FeedName $this.FeedName

                if ($retryCount -lt $MaxRetries) {
                    $delay = [Math]::Pow(2, $retryCount - 1) * 1000
                    Write-FeedLog "Retrying in $delay ms..." -Level "DEBUG" -FeedName $this.FeedName
                    Start-Sleep -Milliseconds $delay
                }
            }
        } while ($retryCount -lt $MaxRetries)

        return @{
            Success = $false
            Error   = $lastError
            Method  = "API"
        }
    }

    # Update feed status
    [void] UpdateStatus([string]$status) {
        $this.LastUpdate = Get-Date
        Write-FeedLog "Feed status updated: $status" -Level "INFO" -FeedName $this.FeedName
    }

    # Get feed information
    [hashtable] GetFeedInfo() {
        return @{
            Name          = $this.FeedName
            Type          = $this.FeedType
            Domains       = $this.SupportedDomains
            Enabled       = $this.IsEnabled
            LastUpdate    = $this.LastUpdate
            Configuration = $this.Configuration
        }
    }
}

# Export the base class
Export-ModuleMember -Type 'BaseFeed'
Export-ModuleMember -Function 'Write-FeedLog'
