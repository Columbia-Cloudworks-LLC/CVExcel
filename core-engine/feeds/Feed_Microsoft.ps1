# Feed_Microsoft.ps1 - Microsoft vulnerability data feed
# Handles Microsoft MSRC, Learn, and other Microsoft vulnerability sources

# Import base feed class
. "$PSScriptRoot/BaseFeed.ps1"

class Feed_Microsoft : BaseFeed {
    Feed_Microsoft() : base("Microsoft", "Vendor", @("microsoft.com", "msrc.microsoft.com", "learn.microsoft.com")) {
        $this.Configuration = @{
            ApiKey = $null
            UseOfficialModule = $true
            FallbackToScraping = $true
            RateLimitDelay = 1000
        }
    }

    [hashtable] GetVulnerabilityData([string]$cveId) {
        Write-FeedLog "Getting vulnerability data for CVE: $cveId" -Level "INFO" -FeedName $this.FeedName

        # Validate CVE format
        if ($cveId -notmatch 'CVE-\d{4}-\d+') {
            return @{
                Success = $false
                Error = "Invalid CVE format: $cveId"
                Source = $this.FeedName
            }
        }

        # Try official MSRC PowerShell module first
        if ($this.Configuration.UseOfficialModule) {
            $apiResult = $this.GetMsrcApiData($cveId)
            if ($apiResult.Success) {
                return $apiResult
            }
        }

        # Fallback to web scraping
        if ($this.Configuration.FallbackToScraping) {
            $scrapingResult = $this.GetMsrcWebData($cveId)
            if ($scrapingResult.Success) {
                return $scrapingResult
            }
        }

        return @{
            Success = $false
            Error = "Failed to retrieve data from all sources"
            Source = $this.FeedName
        }
    }

    [hashtable] GetBulkVulnerabilityData([string[]]$cveIds) {
        Write-FeedLog "Getting bulk vulnerability data for $($cveIds.Count) CVEs" -Level "INFO" -FeedName $this.FeedName

        $results = @()
        $successCount = 0

        foreach ($cveId in $cveIds) {
            $result = $this.GetVulnerabilityData($cveId)
            $results += $result

            if ($result.Success) {
                $successCount++
            }

            # Rate limiting
            Start-Sleep -Milliseconds $this.Configuration.RateLimitDelay
        }

        return @{
            Success = $successCount -gt 0
            Results = $results
            TotalRequested = $cveIds.Count
            SuccessCount = $successCount
            Source = $this.FeedName
        }
    }

    [hashtable] SearchVulnerabilities([hashtable]$searchCriteria) {
        Write-FeedLog "Searching vulnerabilities with criteria: $($searchCriteria | ConvertTo-Json -Compress)" -Level "INFO" -FeedName $this.FeedName

        # Extract search parameters
        $product = $searchCriteria.Product
        $severity = $searchCriteria.Severity
        $dateFrom = $searchCriteria.DateFrom
        $dateTo = $searchCriteria.DateTo

        # Try MSRC API search
        $apiResult = $this.SearchMsrcApi($searchCriteria)
        if ($apiResult.Success) {
            return $apiResult
        }

        # Fallback to web search
        $webResult = $this.SearchMsrcWeb($searchCriteria)
        return $webResult
    }

    [hashtable] GetMsrcApiData([string]$cveId) {
        try {
            Write-FeedLog "Attempting MSRC API for CVE: $cveId" -Level "DEBUG" -FeedName $this.FeedName

            # Check if MsrcSecurityUpdates module is available
            if (-not (Get-Module -ListAvailable -Name MsrcSecurityUpdates)) {
                Write-FeedLog "MsrcSecurityUpdates module not available" -Level "WARNING" -FeedName $this.FeedName
                return @{ Success = $false; Error = "Module not available" }
            }

            # Import module if not loaded
            if (-not (Get-Module -Name MsrcSecurityUpdates)) {
                Import-Module MsrcSecurityUpdates -ErrorAction Stop
            }

            # Extract year from CVE
            if ($cveId -match 'CVE-(\d{4})-\d+') {
                $cveYear = [int]$matches[1]
            } else {
                return @{ Success = $false; Error = "Invalid CVE format" }
            }

            # Search security updates for the CVE year and surrounding years
            $yearsToSearch = @($cveYear, ($cveYear + 1), ($cveYear - 1))
            $foundCve = $false
            $cvrf = $null
            $updateId = $null

            foreach ($year in $yearsToSearch) {
                try {
                    $updatesResponse = Get-MsrcSecurityUpdate -Year $year -ErrorAction SilentlyContinue

                    if (-not $updatesResponse -or -not $updatesResponse.value) {
                        continue
                    }

                    # Search through each update for the CVE
                    foreach ($update in $updatesResponse.value) {
                        try {
                            if (-not $update.ID) { continue }

                            $cvrf = Get-MsrcCvrfDocument -ID $update.ID -ErrorAction Stop

                            # Check if this update contains our CVE
                            $cveData = $cvrf.Vulnerability | Where-Object { $_.CVE -eq $cveId }

                            if ($cveData) {
                                $updateId = $update.ID
                                $foundCve = $true
                                Write-FeedLog "Found CVE $cveId in security update: $updateId" -Level "SUCCESS" -FeedName $this.FeedName
                                break
                            }
                        } catch {
                            continue
                        }
                    }

                    if ($foundCve) { break }
                } catch {
                    continue
                }
            }

            if ($foundCve -and $cvrf -and $updateId) {
                $cveData = $cvrf.Vulnerability | Where-Object { $_.CVE -eq $cveId }
                $cleanedData = $this.ExtractMsrcCvrfData($cveData, $cvrf)

                return @{
                    Success = $true
                    Data = $cleanedData
                    Method = "MSRC API"
                    Source = $this.FeedName
                }
            }

            return @{ Success = $false; Error = "CVE not found in MSRC database" }
        }
        catch {
            Write-FeedLog "MSRC API error: $($_.Exception.Message)" -Level "ERROR" -FeedName $this.FeedName
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }

    [hashtable] GetMsrcWebData([string]$cveId) {
        try {
            Write-FeedLog "Attempting MSRC web scraping for CVE: $cveId" -Level "DEBUG" -FeedName $this.FeedName

            $msrcUrl = "https://msrc.microsoft.com/update-guide/vulnerability/$cveId"

            $headers = @{
                'User-Agent' = 'CVExcel-CoreEngine/1.0 (Microsoft Feed)'
                'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
                'Accept-Language' = 'en-US,en;q=0.9'
                'Referer' = 'https://msrc.microsoft.com/update-guide/'
            }

            $response = $this.Invoke-SafeWebRequest -Uri $msrcUrl -Headers $headers

            if (-not $response.Success) {
                return @{ Success = $false; Error = $response.Error }
            }

            $cleanedData = $this.ExtractMsrcWebData($response.Content, $cveId)

            return @{
                Success = $true
                Data = $cleanedData
                Method = "MSRC Web"
                Source = $this.FeedName
            }
        }
        catch {
            Write-FeedLog "MSRC web scraping error: $($_.Exception.Message)" -Level "ERROR" -FeedName $this.FeedName
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }

    [hashtable] ExtractMsrcCvrfData([object]$cveData, [object]$cvrf) {
        $data = @{
            CVE = $cveData.CVE
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
            Confidence = "High"
        }

        # Extract description
        if ($cveData.Notes) {
            $description = $cveData.Notes | Where-Object { $_.Type -eq "Description" } | Select-Object -First 1
            if ($description -and $description.Value) {
                $data.Description = $this.CleanText($description.Value)
            }
        }

        # Extract CVSS data
        if ($cveData.CVSSScoreSets) {
            $cvssData = $cveData.CVSSScoreSets | Select-Object -First 1
            if ($cvssData) {
                $data.CVSSScore = $cvssData.BaseScore
                $data.CVSSVector = $cvssData.VectorString

                # Determine severity based on CVSS score
                if ($cvssData.BaseScore -ge 9.0) { $data.Severity = "Critical" }
                elseif ($cvssData.BaseScore -ge 7.0) { $data.Severity = "High" }
                elseif ($cvssData.BaseScore -ge 4.0) { $data.Severity = "Medium" }
                elseif ($cvssData.BaseScore -gt 0) { $data.Severity = "Low" }
            }
        }

        # Extract affected products
        if ($cveData.ProductStatuses) {
            $affected = $cveData.ProductStatuses | Where-Object { $_.Type -eq 'Known Affected' }
            if ($affected -and $affected.ProductID) {
                $productNames = @()
                foreach ($prodId in ($affected.ProductID | Select-Object -First 5)) {
                    $product = $cvrf.ProductTree.FullProductName | Where-Object { $_.ProductID -eq $prodId }
                    if ($product -and $product.Value) {
                        $productNames += $product.Value
                    }
                }
                $data.AffectedProducts = $productNames
            }
        }

        # Extract remediation information
        if ($cveData.Remediations) {
            $remediationText = @()
            foreach ($remediation in $cveData.Remediations) {
                if ($remediation.Description -and $remediation.Description.Value) {
                    $remediationText += $remediation.Description.Value
                }
            }
            if ($remediationText.Count -gt 0) {
                $data.Remediation = ($remediationText -join "; ")
            }
        }

        # Extract references
        if ($cveData.References) {
            $references = @()
            foreach ($ref in $cveData.References) {
                if ($ref.URL) {
                    $references += $ref.URL
                }
            }
            $data.References = $references
        }

        return $this.CleanVulnerabilityData($data)
    }

    [hashtable] ExtractMsrcWebData([string]$htmlContent, [string]$cveId) {
        $data = @{
            CVE = $cveId
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

        # Extract KB articles
        $kbMatches = [regex]::Matches($htmlContent, 'KB(\d{6,7})')
        if ($kbMatches.Count -gt 0) {
            $kbList = @()
            foreach ($match in $kbMatches) {
                $kbNum = $match.Groups[1].Value
                $kb = "KB$kbNum"
                if ($kbList -notcontains $kb) {
                    $kbList += $kb
                }
            }
            $data.Remediation = "Apply updates: " + ($kbList -join ", ")
        }

        # Extract severity
        if ($htmlContent -match 'Max Severity.*?(Critical|High|Medium|Low|Important)') {
            $data.Severity = $matches[1]
        }

        # Extract affected products
        if ($htmlContent -match 'Affected [Pp]roducts?[\s:]+([^\r\n<]+)') {
            $data.AffectedProducts = @($matches[1].Trim())
        }

        # Extract download links as references
        $downloadMatches = [regex]::Matches($htmlContent, 'https://catalog\.update\.microsoft\.com[^"''<>\s]*')
        foreach ($match in $downloadMatches) {
            $link = $match.Value
            if ($data.References -notcontains $link) {
                $data.References += $link
            }
        }

        return $this.CleanVulnerabilityData($data)
    }

    [hashtable] SearchMsrcApi([hashtable]$searchCriteria) {
        # Implementation for MSRC API search
        # This would use the MSRC API to search for vulnerabilities
        return @{ Success = $false; Error = "MSRC API search not implemented" }
    }

    [hashtable] SearchMsrcWeb([hashtable]$searchCriteria) {
        # Implementation for MSRC web search
        # This would scrape the MSRC website for search results
        return @{ Success = $false; Error = "MSRC web search not implemented" }
    }
}

# Export the Microsoft feed class
Export-ModuleMember -Type 'Feed_Microsoft'
