<#
.SYNOPSIS
    NVD API Engine - Core functionality for querying NVD CVE Database

.DESCRIPTION
    Provides functions for interacting with the NVD API 2.0, including:
    - API key management
    - CVE queries with pagination
    - CPE resolution
    - Diagnostic and testing functions
    - NIST-compliant rate limiting and error handling

.NOTES
    IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.
    Rate Limits: 5 requests/30sec (public) or 50 requests/30sec (with API key)
#>

# -------------------- API Key Management --------------------

function Get-NvdApiKey {
    <#
    .SYNOPSIS
        Retrieves NVD API key from file or environment variable.
    #>
    param(
        [string]$KeyFile,
        [string]$Root
    )

    $keyPath = if ($KeyFile) { $KeyFile } else { Join-Path $Root "nvd.api.key" }
    $k = $null

    if (Test-Path $keyPath) {
        $k = Get-Content -Raw -Path $keyPath
    } elseif ($env:NVD_API_KEY) {
        $k = $env:NVD_API_KEY
    }

    if ($k) {
        return $k.Trim().Trim('"', '"', '"')
    }

    return $null
}

# -------------------- Helper Functions --------------------

function ConvertTo-Iso8601Z {
    <#
    .SYNOPSIS
        Converts DateTime to ISO 8601 UTC format.
    #>
    param(
        [Parameter(Mandatory)]
        [DateTime]$DateTime,
        [string]$TimePart = "00:00:00.000"
    )

    # DatePicker gives Unspecified; compose local clock then convert to UTC Z
    $dateStr = $DateTime.ToString("yyyy-MM-dd")
    $full = [DateTime]::Parse("$dateStr $TimePart", [System.Globalization.CultureInfo]::InvariantCulture)
    return $full.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
}

function Get-CvssScore {
    <#
    .SYNOPSIS
        Extracts CVSS base score from CVE metrics.
    #>
    param($Metrics)

    if ($Metrics.cvssMetricV31) { return $Metrics.cvssMetricV31[0].cvssData.baseScore }
    if ($Metrics.cvssMetricV30) { return $Metrics.cvssMetricV30[0].cvssData.baseScore }
    if ($Metrics.cvssMetricV2) { return $Metrics.cvssMetricV2[0].cvssData.baseScore }
    return $null
}

function Expand-CPEs {
    <#
    .SYNOPSIS
        Expands CPE configurations into flat list.
    #>
    param($Configurations)

    $rows = New-Object System.Collections.Generic.List[object]
    if (-not $Configurations) { return $rows }

    function Walk([object]$nodes) {
        foreach ($node in $nodes) {
            if ($node.cpeMatch) {
                foreach ($m in $node.cpeMatch) {
                    $cpe = $m.criteria
                    if (-not $cpe) { continue }

                    $parts = $cpe -split ':'
                    $vendor = if ($parts.Count -ge 4) { $parts[3] } else { '' }
                    $product = if ($parts.Count -ge 5) { $parts[4] } else { '' }
                    $version = if ($parts.Count -ge 6) { $parts[5] } else { '' }

                    $rows.Add([PSCustomObject]@{
                            CPE23Uri   = $cpe
                            Vendor     = $vendor
                            Product    = $product
                            Version    = $version
                            Vulnerable = [bool]$m.vulnerable
                        })
                }
            }
            if ($node.children) { Walk $node.children }
        }
    }

    if ($Configurations.nodes) { Walk $Configurations.nodes }
    return $rows
}

# -------------------- NVD API Core Functions --------------------

function Invoke-NvdPage {
    <#
    .SYNOPSIS
        Makes a single request to NVD API with retry logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Query,
        [string]$ApiKey,
        [int]$MaxRetries = 3,
        [int]$RetryDelayMs = 1000,
        [string]$BaseUri = 'https://services.nvd.nist.gov/rest/json/cves/2.0',
        [bool]$ForcePublic = $false
    )

    if ($ApiKey) { $ApiKey = $ApiKey.Trim().Trim('"', '"', '"') }

    # Enhanced headers with proper user agent and content type
    $headers = @{
        'User-Agent' = 'CVExcel-PowerShell/1.0 (NVD CVE Exporter)'
        'Accept'     = 'application/json'
    }
    if ($ApiKey -and -not $ForcePublic) { $headers['apiKey'] = $ApiKey }

    # Build query: keep ISO timestamps literal; encode only CPE/keyword values
    $parts = @()
    foreach ($k in $Query.Keys) {
        $v = $Query[$k]
        if ($null -eq $v) { continue }

        if ($k -in @('cpeName', 'keywordSearch')) {
            if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
                foreach ($item in $v) {
                    $parts += "$k=" + [uri]::EscapeDataString("$item")
                }
            } else {
                $parts += "$k=" + [uri]::EscapeDataString("$v")
            }
        } else {
            $parts += "$k=$v"
        }
    }

    $ub = [System.UriBuilder]$BaseUri
    $ub.Query = ($parts -join '&')
    $uri = $ub.Uri.AbsoluteUri

    # Log the request for debugging
    Write-Verbose "NVD API Request: $uri"
    Write-Verbose "Headers: $($headers | ConvertTo-Json -Compress)"

    $retryCount = 0
    do {
        try {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -TimeoutSec 120
            Write-Verbose "NVD API Response: Success (attempt $($retryCount + 1))"
            return $response
        } catch {
            $retryCount++
            $status = $_.Exception.Response.StatusCode.Value__ 2>$null
            $reason = $_.Exception.Response.StatusDescription 2>$null
            $body = $null

            try {
                $sr = New-Object IO.StreamReader $_.Exception.Response.GetResponseStream()
                $body = $sr.ReadToEnd()
                $sr.Close()
            } catch {}

            Write-Verbose "NVD API Error (attempt $retryCount): $status $reason"
            Write-Verbose "Response Body: $body"

            # If it's a 404 or 500 error, don't retry
            if ($status -eq 404 -or $status -eq 500 -or $retryCount -ge $MaxRetries) {
                throw "HTTP error $status $reason querying:`n$uri`nBody:`n$body"
            }

            # Wait before retry with exponential backoff
            if ($retryCount -lt $MaxRetries) {
                $delay = $RetryDelayMs * [math]::Pow(2, $retryCount - 1)
                Write-Verbose "Retrying in $delay ms..."
                Start-Sleep -Milliseconds $delay
            }
        }
    } while ($retryCount -lt $MaxRetries)

    # Always sleep between requests to respect rate limits
    Start-Sleep -Seconds 6
}

function Get-NvdCves {
    <#
    .SYNOPSIS
        Retrieves CVEs from NVD API with automatic pagination and date chunking.
    #>
    [CmdletBinding()]
    param(
        [string]$KeywordOrCpe,
        [string[]]$CpeNames,
        [string]$StartIso,
        [string]$EndIso,
        [string]$ApiKey,
        [switch]$UseLastModified,
        [switch]$NoDateFilter,
        [bool]$ForcePublic = $false
    )

    # Parameter validation
    if (-not $KeywordOrCpe -and -not $CpeNames) {
        throw "Either KeywordOrCpe or CpeNames must be provided"
    }

    $useCpeArray = ($CpeNames -and $CpeNames.Count -gt 0)
    $isCpeSingle = (-not $useCpeArray) -and ($KeywordOrCpe -like 'cpe:2.3:*')

    # Handle date range chunking for large ranges
    if (-not $NoDateFilter -and $StartIso -and $EndIso) {
        $startDate = [DateTime]::Parse($StartIso)
        $endDate = [DateTime]::Parse($EndIso)
        $totalDays = ($endDate - $startDate).TotalDays

        # NVD API 2.0 has a 120-day limit per request
        if ($totalDays -gt 120) {
            $chunkCount = [math]::Ceiling($totalDays / 120)
            Write-Host "Date range exceeds 120 days ($([math]::Round($totalDays)) days). Splitting into $chunkCount chunks..." -ForegroundColor Yellow

            $allResults = @()
            $currentStart = $startDate

            while ($currentStart -lt $endDate) {
                $currentEnd = [DateTime]::Min($currentStart.AddDays(120), $endDate)
                $chunkStartIso = $currentStart.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
                $chunkEndIso = $currentEnd.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")

                Write-Host "Processing chunk: $($currentStart.ToString('yyyy-MM-dd')) to $($currentEnd.ToString('yyyy-MM-dd'))" -ForegroundColor Gray

                try {
                    $chunkResults = Get-NvdCves -KeywordOrCpe $KeywordOrCpe -CpeNames $CpeNames -StartIso $chunkStartIso -EndIso $chunkEndIso -ApiKey $ApiKey -UseLastModified:$UseLastModified -NoDateFilter:$false -ForcePublic:$ForcePublic
                    $allResults += $chunkResults
                    Write-Host "Retrieved $($chunkResults.Count) CVEs from this chunk" -ForegroundColor Green
                } catch {
                    Write-Host "Failed to retrieve chunk: $($_.Exception.Message)" -ForegroundColor Red
                    throw
                }

                $currentStart = $currentEnd.AddSeconds(1)

                # Rate limiting between chunks
                Start-Sleep -Seconds 2
            }

            Write-Host "Total CVEs retrieved across all chunks: $($allResults.Count)" -ForegroundColor Green
            return $allResults
        }
    }

    # Single request (within 120-day limit or no date filter)
    $resultsPerPage = 2000
    $startIndex = 0
    $all = @()

    do {
        $q = @{ resultsPerPage = $resultsPerPage; startIndex = $startIndex }

        if (-not $NoDateFilter) {
            if (-not $StartIso -or -not $EndIso) {
                throw "StartIso/EndIso required unless -NoDateFilter is set."
            }
            $dateStartParam = if ($UseLastModified) { 'lastModStartDate' } else { 'pubStartDate' }
            $dateEndParam = if ($UseLastModified) { 'lastModEndDate' } else { 'pubEndDate' }
            $q[$dateStartParam] = $StartIso
            $q[$dateEndParam] = $EndIso
        }

        if ($useCpeArray) { $q['cpeName'] = $CpeNames }
        elseif ($isCpeSingle) { $q['cpeName'] = $KeywordOrCpe }
        elseif ($KeywordOrCpe) { $q['keywordSearch'] = $KeywordOrCpe }

        try {
            $resp = Invoke-NvdPage -Query $q -ApiKey $ApiKey -ForcePublic:$ForcePublic
        } catch {
            # Check if it's a 404 with API key - fallback to public
            if ($_.Exception.Message -like "*HTTP error 404*" -and $ApiKey -and -not $ForcePublic) {
                Write-Verbose "API key failed - retrying with public access"
                Write-Host "Using public access (API key invalid)" -ForegroundColor Yellow
                try {
                    $resp = Invoke-NvdPage -Query $q -ApiKey $null -ForcePublic:$true
                } catch {
                    Write-Verbose "Public access also failed: $($_.Exception.Message)"
                    throw
                }
            } else {
                # Enhanced error handling with fallback strategies
                if (-not $NoDateFilter -and $UseLastModified -and $_.Exception.Message -like 'HTTP error 404*') {
                    Write-Verbose "Last-modified date search failed with 404, retrying with publication dates..."
                    $q.Remove('lastModStartDate'); $q.Remove('lastModEndDate')
                    $q['pubStartDate'] = $StartIso; $q['pubEndDate'] = $EndIso
                    try {
                        $resp = Invoke-NvdPage -Query $q -ApiKey $ApiKey -ForcePublic:$ForcePublic
                    } catch {
                        Write-Verbose "Publication date fallback also failed: $($_.Exception.Message)"
                        throw "Both last-modified and publication date searches failed. Original error: $($_.Exception.Message)"
                    }
                } else {
                    Write-Verbose "API request failed: $($_.Exception.Message)"
                    throw
                }
            }
        }

        if ($resp.vulnerabilities) { $all += $resp.vulnerabilities }

        $totalResults = if ($resp.totalResults) { [int]$resp.totalResults } else { 0 }
        $pageSize = if ($resp.resultsPerPage) { [int]$resp.resultsPerPage } else { $resultsPerPage }
        $startIndex += $pageSize

        Write-Verbose "Retrieved $($all.Count) of $totalResults total results"
    } while ($all.Count -lt $totalResults)

    Write-Verbose "Total CVEs retrieved: $($all.Count)"
    return $all
}

function Resolve-CpeCandidates {
    <#
    .SYNOPSIS
        Resolves keyword to CPE candidates using NVD CPE API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Keyword,
        [int]$Max = 5,
        [string]$ApiKey
    )

    try {
        $base = 'https://services.nvd.nist.gov/rest/json/cpes/2.0'
        if ($ApiKey) { $ApiKey = $ApiKey.Trim().Trim('"', '"', '"') }

        $baseHeaders = @{
            'User-Agent' = 'CVExcel-PowerShell/1.0 (NVD CVE Exporter)'
            'Accept'     = 'application/json'
        }

        $pairs = @(
            'keywordSearch=' + [uri]::EscapeDataString($Keyword)
            'resultsPerPage=200'
            'startIndex=0'
        )
        $ub = [System.UriBuilder]$base
        $ub.Query = ($pairs -join '&')
        $uri = $ub.Uri.AbsoluteUri

        Write-Verbose "CPE resolution query: $uri"

        # Try with API key first, fallback to public on 404
        if ($ApiKey) {
            $headers = $baseHeaders.Clone()
            $headers['apiKey'] = $ApiKey
            try {
                $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -TimeoutSec 120
            } catch {
                $status = $_.Exception.Response.StatusCode.Value__ 2>$null
                if ($status -eq 404) {
                    Write-Verbose "API key failed for CPE resolution - using public access"
                    $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $baseHeaders -TimeoutSec 120
                } else {
                    throw
                }
            }
        } else {
            $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $baseHeaders -TimeoutSec 120
        }

        $candidates = @()
        $products = if ($resp.products) { $resp.products } else { @() }
        foreach ($r in $products) {
            $c = $r.cpe
            if ($c.cpeName) { $candidates += $c.cpeName }
        }

        $ranked = $candidates | Sort-Object {
            $p = $_ -split ':'
            $s = 0
            if ($p.Length -ge 4 -and $p[3] -eq 'microsoft') { $s -= 10 }
            if ($p.Length -ge 3 -and $p[2] -eq 'o') { $s -= 5 }
            $s
        }

        Write-Verbose "Found $($candidates.Count) CPE candidates for '$Keyword'"
        return $ranked | Select-Object -First $Max
    } catch {
        Write-Verbose "CPE resolution failed for '$Keyword': $($_.Exception.Message)"
        return @()
    }
}

# -------------------- Diagnostic Functions --------------------

function Test-NvdApiConnectivity {
    <#
    .SYNOPSIS
        Tests basic NVD API connectivity.
    #>
    [CmdletBinding()]
    param([string]$ApiKey)

    Write-Host "Testing NVD API connectivity..." -ForegroundColor Yellow
    Write-Host "Note: Rate limit is 5 requests/30sec (public) or 50 requests/30sec (with API key)" -ForegroundColor Gray

    $testUri = "https://services.nvd.nist.gov/rest/json/cves/2.0?resultsPerPage=1&startIndex=0"

    $baseHeaders = @{
        'User-Agent' = 'CVExcel-PowerShell/1.0 (NVD CVE Exporter)'
        'Accept'     = 'application/json'
    }

    $publicMode = $false

    if ($ApiKey) {
        # Validate key format
        if ($ApiKey.Length -ne 36 -or $ApiKey -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            Write-Host "⚠ API key format invalid (should be UUID, length 36). Falling back to public access." -ForegroundColor Yellow
            $publicMode = $true
        } else {
            $headers = $baseHeaders.Clone()
            $headers['apiKey'] = $ApiKey
            Write-Host "Using API key: $($ApiKey.Substring(0,8))..." -ForegroundColor Gray
            Write-Host "Rate limit: 50 requests per 30 seconds" -ForegroundColor Gray

            try {
                Write-Host "  Testing with API key..." -ForegroundColor Cyan
                $response = Invoke-RestMethod -Uri $testUri -Headers $headers -TimeoutSec 30
                Write-Host "    ✓ Success with API key" -ForegroundColor Green
                if ($response.totalResults) {
                    Write-Host "    Total CVEs available: $($response.totalResults)" -ForegroundColor Gray
                }
                return $true
            } catch {
                $status = $_.Exception.Response.StatusCode.Value__ 2>$null
                if ($status -eq 404) {
                    Write-Host "  API key returned 404 - likely invalid/expired. Falling back to public access." -ForegroundColor Yellow
                    $publicMode = $true
                } else {
                    throw
                }
            }
        }
    } else {
        $publicMode = $true
        Write-Host "No API key provided - using public rate limit (5 requests per 30 seconds)" -ForegroundColor Yellow
    }

    if ($publicMode) {
        $headers = $baseHeaders
        try {
            Write-Host "  Testing public access..." -ForegroundColor Cyan
            $response = Invoke-RestMethod -Uri $testUri -Headers $headers -TimeoutSec 30
            Write-Host "    ✓ Success (public access)" -ForegroundColor Green
            if ($response.totalResults) {
                Write-Host "    Total CVEs available: $($response.totalResults)" -ForegroundColor Gray
            }
            Write-Host "Note: Public access has lower rate limits. Consider regenerating API key at https://nvd.nist.gov/developers/request-an-api-key" -ForegroundColor Yellow
            return $true
        } catch {
            Write-Host "    ✗ Public access also failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    return $true
}

function Test-NvdApiKeywordSearch {
    <#
    .SYNOPSIS
        Tests NVD API keyword search functionality.
    #>
    [CmdletBinding()]
    param(
        [string]$Keyword = "microsoft windows",
        [string]$ApiKey
    )

    $publicMode = $false
    $baseHeaders = @{
        'User-Agent' = 'CVExcel-PowerShell/1.0 (NVD CVE Exporter)'
        'Accept'     = 'application/json'
    }

    $testQuery = @{
        keywordSearch  = $Keyword
        resultsPerPage = 10
        startIndex     = 0
    }

    if ($ApiKey) {
        $headers = $baseHeaders.Clone()
        $headers['apiKey'] = $ApiKey
        Write-Host "Testing keyword search with API key..." -ForegroundColor Cyan
        try {
            $response = Invoke-NvdPage -Query $testQuery -ApiKey $ApiKey -Verbose
            Write-Host "✓ Keyword search test passed (with key)" -ForegroundColor Green
            Write-Host "  Found $($response.vulnerabilities.Count) CVEs for '$Keyword'" -ForegroundColor Gray
            return $true
        } catch {
            if ($_.Exception.Message -like "*HTTP error 404*") {
                Write-Host "  API key failed for keyword search - falling back to public access." -ForegroundColor Yellow
                $publicMode = $true
            } else {
                Write-Host "✗ Keyword search test failed: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
    } else {
        $publicMode = $true
    }

    if ($publicMode) {
        $headers = $baseHeaders
        Write-Host "Testing keyword search (public access)..." -ForegroundColor Yellow
        try {
            $response = Invoke-NvdPage -Query $testQuery -ApiKey $null -Verbose
            Write-Host "✓ Keyword search test passed (public access)" -ForegroundColor Green
            Write-Host "  Found $($response.vulnerabilities.Count) CVEs for '$Keyword'" -ForegroundColor Gray
            return $true
        } catch {
            Write-Host "✗ Keyword search failed even in public access: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    return $true
}

function Test-AlternativeEndpoints {
    <#
    .SYNOPSIS
        Tests alternative NVD endpoints.
    #>
    [CmdletBinding()]
    param([string]$ApiKey)

    Write-Host "Testing alternative NVD endpoints (with rate limiting)..." -ForegroundColor Yellow

    # Only test CPE API since CVE API was already tested
    $alternativeEndpoints = @(
        @{
            Name    = "CPE API v2.0"
            BaseUri = "https://services.nvd.nist.gov/rest/json/cpes/2.0"
        }
    )

    $headers = @{
        'User-Agent' = 'CVExcel-PowerShell/1.0 (NVD CVE Exporter)'
        'Accept'     = 'application/json'
    }
    if ($ApiKey) { $headers['apiKey'] = $ApiKey }

    $workingEndpoints = @()
    foreach ($endpoint in $alternativeEndpoints) {
        try {
            Write-Host "  Testing: $($endpoint.Name)" -ForegroundColor Cyan
            $testUri = "$($endpoint.BaseUri)?resultsPerPage=1&startIndex=0"

            $response = Invoke-RestMethod -Method GET -Uri $testUri -Headers $headers -TimeoutSec 30
            Write-Host "    ✓ Working" -ForegroundColor Green
            if ($response.totalResults) {
                Write-Host "    Total CPEs: $($response.totalResults)" -ForegroundColor Gray
            }
            $workingEndpoints += $endpoint

            # Sleep between requests to respect rate limits
            Write-Host "    Sleeping 6 seconds to respect rate limits..." -ForegroundColor Gray
            Start-Sleep -Seconds 6
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.Value__ 2>$null
            Write-Host "    ✗ Failed: $statusCode" -ForegroundColor Red
        }
    }

    return $workingEndpoints
}

function Get-NvdApiStatus {
    <#
    .SYNOPSIS
        Comprehensive NVD API status check with diagnostics.
    #>
    [CmdletBinding()]
    param([string]$ApiKey)

    Write-Host "`n=== NVD API Status Check ===" -ForegroundColor Magenta

    # Check if we can reach the main NVD website
    try {
        Write-Host "Checking NVD website accessibility..." -ForegroundColor Yellow
        $response = Invoke-WebRequest -Uri "https://nvd.nist.gov" -TimeoutSec 10 -UseBasicParsing
        Write-Host "✓ NVD website is accessible (Status: $($response.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "✗ Cannot reach NVD website: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Test API endpoints
    $connectivityOk = Test-NvdApiConnectivity -ApiKey $ApiKey
    $workingEndpoints = Test-AlternativeEndpoints -ApiKey $ApiKey

    Write-Host "`nWorking endpoints:" -ForegroundColor Yellow
    if ($workingEndpoints.Count -gt 0) {
        foreach ($endpoint in $workingEndpoints) {
            Write-Host "  ✓ $($endpoint.Name)" -ForegroundColor Green
        }
    } else {
        Write-Host "  ✗ No working endpoints found" -ForegroundColor Red
    }

    # Provide recommendations
    Write-Host "`nRecommendations:" -ForegroundColor Yellow
    if (-not $connectivityOk) {
        Write-Host "  • Check your internet connection and firewall settings" -ForegroundColor Yellow
        Write-Host "  • Regenerate your API key at https://nvd.nist.gov/developers/request-an-api-key" -ForegroundColor Gray
        Write-Host "  • Contact NVD support if issues persist: nvd@nist.gov" -ForegroundColor Gray
    } else {
        Write-Host "  • API connectivity is working normally" -ForegroundColor Green
        if ($ApiKey) {
            Write-Host "  • Your API key appears invalid/expired - regenerate at https://nvd.nist.gov/developers/request-an-api-key" -ForegroundColor Yellow
        } else {
            Write-Host "  • Consider obtaining an API key for higher rate limits" -ForegroundColor Yellow
        }
    }

    return $connectivityOk
}
