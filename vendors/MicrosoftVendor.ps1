# MicrosoftVendor.ps1 - Microsoft-specific scraping module
# Handles Microsoft MSRC, Learn, and other Microsoft URLs
# Note: BaseVendor.ps1 must be loaded before this module

class MicrosoftVendor : BaseVendor {
    MicrosoftVendor() : base("Microsoft", @("microsoft.com", "msrc.microsoft.com", "learn.microsoft.com")) {}

    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        # Extract CVE ID from URL for MSRC API calls
        if ($url -match 'CVE-\d{4}-\d+') {
            $cveId = $matches[0]
            return $this.GetMsrcAdvisoryData($cveId, $session)
        }

        return @{
            Success = $false
            Method  = 'Microsoft API'
            Error   = 'No CVE ID found in URL'
        }
    }

    [hashtable] GetMsrcAdvisoryData([string]$cveId, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        try {
            Write-Log -Message "Attempting official MSRC PowerShell module for $cveId" -Level "INFO"

            $extractedInfo = @{
                PatchID          = $null
                AffectedVersions = $null
                Remediation      = $null
                DownloadLinks    = @()
            }

            # Try using the official MsrcSecurityUpdates PowerShell module
            try {
                Write-Log -Message "Starting MSRC API attempt for $cveId" -Level "DEBUG"

                # Check if module is available
                if (-not (Get-Module -ListAvailable -Name MsrcSecurityUpdates)) {
                    Write-Log -Message "MsrcSecurityUpdates module not installed, trying alternate method" -Level "WARNING"
                    throw "Module not available"
                }

                Write-Log -Message "Module is available, checking if loaded" -Level "DEBUG"

                # Import if not already loaded
                if (-not (Get-Module -Name MsrcSecurityUpdates)) {
                    Write-Log -Message "Importing MsrcSecurityUpdates module" -Level "DEBUG"
                    Import-Module MsrcSecurityUpdates -ErrorAction Stop
                    Write-Log -Message "Module imported successfully" -Level "DEBUG"
                } else {
                    Write-Log -Message "Module already loaded" -Level "DEBUG"
                }

                Write-Log -Message "Using official MSRC API module for $cveId" -Level "INFO"

                # Extract year from CVE ID (CVE-YYYY-NNNNN)
                if ($cveId -match 'CVE-(\d{4})-\d+') {
                    $cveYear = [int]$matches[1]
                } else {
                    throw "Invalid CVE ID format: $cveId"
                }

                # Get security updates for the CVE year and surrounding years
                # (CVEs can be published in bulletins from different years)
                $yearsToSearch = @($cveYear, ($cveYear + 1), ($cveYear - 1))
                $foundCve = $false
                $cvrf = $null
                $updateId = $null

                foreach ($year in $yearsToSearch) {
                    Write-Log -Message "Searching security updates for year $year" -Level "DEBUG"

                    try {
                        $updatesResponse = Get-MsrcSecurityUpdate -Year $year -ErrorAction SilentlyContinue

                        Write-Log -Message "API response for year $year`: $($updatesResponse -ne $null)" -Level "DEBUG"

                        if (-not $updatesResponse -or -not $updatesResponse.value) {
                            Write-Log -Message "No updates found for year $year or value property is empty" -Level "DEBUG"
                            continue
                        }

                        Write-Log -Message "Found $($updatesResponse.value.Count) updates for year $year" -Level "DEBUG"

                        # Search through each update for the CVE
                        foreach ($update in $updatesResponse.value) {
                            try {
                                if (-not $update.ID) {
                                    continue
                                }

                                Write-Log -Message "Checking update: $($update.ID)" -Level "DEBUG"
                                $cvrf = Get-MsrcCvrfDocument -ID $update.ID -ErrorAction Stop

                                # Check if this update contains our CVE
                                $cveData = $cvrf.Vulnerability | Where-Object { $_.CVE -eq $cveId }

                                if ($cveData) {
                                    $updateId = $update.ID
                                    $foundCve = $true
                                    Write-Log -Message "Found CVE $cveId in security update: $updateId" -Level "SUCCESS"
                                    break
                                }
                            } catch {
                                Write-Log -Message "Error checking update $($update.ID): $($_.Exception.Message)" -Level "DEBUG"
                                # Continue to next update
                                continue
                            }
                        }

                        if ($foundCve) {
                            break
                        }
                    } catch {
                        Write-Log -Message "Error searching year $year`: $($_.Exception.Message)" -Level "WARNING"
                        continue
                    }
                }

                if ($foundCve -and $cvrf -and $updateId) {
                    # Find the specific CVE in the document
                    $cveData = $cvrf.Vulnerability | Where-Object { $_.CVE -eq $cveId }

                    if ($cveData -and $cveData.Remediations) {
                        # Extract KB articles and download links
                        $kbList = @()
                        $catalogLinks = @()

                        foreach ($remediation in $cveData.Remediations) {
                            # Extract KB numbers and catalog links
                            if ($remediation.URL) {
                                if ($remediation.URL -match 'KB(\d+)') {
                                    $kbNum = $matches[1]
                                    $kb = "KB$kbNum"
                                    if ($kbList -notcontains $kb) {
                                        $kbList += $kb
                                    }

                                    # Add catalog link
                                    if ($remediation.URL -match 'catalog\.update\.microsoft\.com') {
                                        $catalogLinks += $remediation.URL
                                    } else {
                                        # Generate catalog link
                                        $catalogLinks += "https://catalog.update.microsoft.com/v7/site/Search.aspx?q=KB$kbNum"
                                    }
                                }
                                # Extract support.microsoft.com links
                                elseif ($remediation.URL -match 'support\.microsoft\.com') {
                                    if ($extractedInfo.DownloadLinks -notcontains $remediation.URL) {
                                        $extractedInfo.DownloadLinks += $remediation.URL
                                    }
                                }
                            }

                            # Extract description as remediation
                            if ($remediation.Description -and $remediation.Description.Value) {
                                if (-not $extractedInfo.Remediation) {
                                    $extractedInfo.Remediation = $remediation.Description.Value
                                }
                            }
                        }

                        # Add unique catalog links
                        foreach ($link in ($catalogLinks | Select-Object -Unique)) {
                            if ($extractedInfo.DownloadLinks -notcontains $link) {
                                $extractedInfo.DownloadLinks += $link
                            }
                        }

                        if ($kbList.Count -gt 0) {
                            $extractedInfo.PatchID = ($kbList | Select-Object -Unique) -join ', '
                            Write-Log -Message "Extracted $($kbList.Count) KB articles from official MSRC API: $($extractedInfo.PatchID)" -Level "SUCCESS"
                        }

                        # Extract affected products
                        if ($cveData.ProductStatuses) {
                            $affected = $cveData.ProductStatuses | Where-Object { $_.Type -eq 'Known Affected' }
                            if ($affected -and $affected.ProductID) {
                                # Get product names from ProductTree
                                $productNames = @()
                                foreach ($prodId in ($affected.ProductID | Select-Object -First 3)) {
                                    $product = $cvrf.ProductTree.FullProductName | Where-Object { $_.ProductID -eq $prodId }
                                    if ($product -and $product.Value) {
                                        $productNames += $product.Value
                                    }
                                }
                                if ($productNames.Count -gt 0) {
                                    $extractedInfo.AffectedVersions = ($productNames -join '; ')
                                    Write-Log -Message "Extracted affected products from MSRC API" -Level "SUCCESS"
                                }
                            }
                        }

                        Write-Log -Message "Official MSRC API extraction successful for $cveId - found $($extractedInfo.DownloadLinks.Count) links" -Level "SUCCESS"
                        return @{
                            Success = $true
                            Method  = 'Official MSRC PowerShell Module'
                            Data    = $extractedInfo
                        }
                    } else {
                        Write-Log -Message "No remediation data found for $cveId in update $updateId" -Level "WARNING"
                    }
                } else {
                    Write-Log -Message "No security update found for $cveId - may be too old or not in MSRC database" -Level "INFO"
                }
            } catch {
                $apiError = $_.Exception.Message
                Write-Log -Message "Official MSRC module failed: $apiError, trying fallback method" -Level "WARNING"
            }

            # Fallback: Try to fetch the actual MSRC page with a real browser session
            # The page is JavaScript-heavy, but we can try to get the raw HTML and look for KB references
            $msrcUrl = "https://msrc.microsoft.com/update-guide/vulnerability/$cveId"

            $pageHeaders = @{
                'User-Agent'      = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
                'Accept-Language' = 'en-US,en;q=0.9'
                'Accept-Encoding' = 'gzip, deflate, br'
                'Referer'         = 'https://msrc.microsoft.com/update-guide/'
            }

            $invokeParams = @{
                Uri             = $msrcUrl
                Headers         = $pageHeaders
                TimeoutSec      = 30
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            if ($session) {
                $invokeParams['WebSession'] = $session
            }

            $pageResponse = Invoke-WebRequest @invokeParams
            $htmlContent = $pageResponse.Content

            Write-Log -Message "Fetched MSRC page for $cveId (size: $($htmlContent.Length) bytes)" -Level "INFO"

            # Extract KB articles from HTML (even if it's minimal/dynamic)
            $kbMatches = [regex]::Matches($htmlContent, 'KB(\d{6,7})')
            if ($kbMatches.Count -gt 0) {
                $kbList = @()
                foreach ($match in $kbMatches) {
                    $kbNum = $match.Groups[1].Value
                    $kb = "KB$kbNum"
                    if ($kbList -notcontains $kb) {
                        $kbList += $kb
                        # Generate catalog.update.microsoft.com link
                        $extractedInfo.DownloadLinks += "https://catalog.update.microsoft.com/v7/site/Search.aspx?q=KB$kbNum"
                    }
                }
                $extractedInfo.PatchID = ($kbList | Select-Object -First 5) -join ', '
                Write-Log -Message "Extracted $($kbList.Count) KB articles from MSRC HTML for $cveId" -Level "SUCCESS"
            }

            # Also look for direct catalog.update.microsoft.com links in the HTML
            $catalogMatches = [regex]::Matches($htmlContent, 'catalog\.update\.microsoft\.com[^"''<>\s]*')
            foreach ($match in $catalogMatches) {
                $link = "https://$($match.Value)"
                if ($extractedInfo.DownloadLinks -notcontains $link) {
                    $extractedInfo.DownloadLinks += $link
                }
            }

            if ($extractedInfo.PatchID -or $extractedInfo.DownloadLinks.Count -gt 0) {
                Write-Log -Message "Successfully extracted data from MSRC page for $cveId" -Level "SUCCESS"
                return @{
                    Success = $true
                    Method  = 'MSRC Page'
                    Data    = $extractedInfo
                }
            } else {
                Write-Log -Message "No KB articles or download links found in MSRC page for $cveId" -Level "WARNING"
                return @{
                    Success = $false
                    Method  = 'MSRC Page'
                    Error   = 'No data found'
                }
            }
        } catch {
            Write-Log -Message "MSRC data extraction failed for $cveId`: $($_.Exception.Message)" -Level "WARNING"
            return @{
                Success = $false
                Method  = 'MSRC API'
                Error   = $_.Exception.Message
            }
        }
    }

    [hashtable] ExtractData([string]$htmlContent, [string]$url) {
        $info = @{
            PatchID          = $null
            FixVersion       = $null
            AffectedVersions = $null
            Remediation      = $null
            DownloadLinks    = @()
        }

        # Check for dynamic/too-small content from MSRC
        Write-Log -Message "Checking MSRC conditions: URL='$url', Length=$($htmlContent.Length)" -Level "DEBUG"

        if ($url -like '*msrc.microsoft.com*' -and $htmlContent.Length -lt 5000) {
            Write-Log -Message "MSRC page appears to be dynamic (size: $($htmlContent.Length) bytes), attempting enhanced extraction" -Level "INFO"

            # Extract CVE ID from URL
            if ($url -match 'CVE-\d{4}-\d+') {
                $cveId = $matches[0]
                Write-Log -Message "Extracting CVE ID from URL: $cveId" -Level "DEBUG"

                Write-Log -Message "Calling GetMsrcAdvisoryData for $cveId" -Level "DEBUG"
                $apiData = $this.GetMsrcAdvisoryData($cveId, $null)

                if ($apiData.Success) {
                    Write-Log -Message "Successfully extracted data for $cveId via API fallback" -Level "SUCCESS"

                    # Merge download links with any already extracted
                    $info.PatchID = $apiData.Data.PatchID
                    $info.AffectedVersions = $apiData.Data.AffectedVersions
                    $info.Remediation = $apiData.Data.Remediation

                    # Return info with download links to be merged later
                    $info.DownloadLinks = $apiData.Data.DownloadLinks
                    return $info
                } else {
                    Write-Log -Message "API fallback did not return useful data for $cveId" -Level "WARNING"
                }
            } else {
                Write-Log -Message "Could not extract CVE ID from MSRC URL: $url" -Level "WARNING"
            }
        }

        # Microsoft patterns (enhanced)
        if ($url -like '*microsoft.com*') {
            # Extract KB articles (may have multiple) and generate catalog links
            $kbMatches = [regex]::Matches($htmlContent, 'KB(\d{6,7})')
            if ($kbMatches.Count -gt 0) {
                $kbList = @()
                foreach ($match in $kbMatches) {
                    $kbNum = $match.Groups[1].Value
                    $kb = "KB$kbNum"
                    if ($kbList -notcontains $kb) {
                        $kbList += $kb
                        # Generate direct link to Microsoft Update Catalog
                        $catalogLink = "https://catalog.update.microsoft.com/v7/site/Search.aspx?q=KB$kbNum"
                        if ($info.DownloadLinks -notcontains $catalogLink) {
                            $info.DownloadLinks += $catalogLink
                        }
                    }
                }
                $info.PatchID = (($kbList | Select-Object -First 5) -join ', ')
                Write-Log -Message "Generated $($kbList.Count) catalog.update.microsoft.com links for KB articles" -Level "DEBUG"
            }

            # Extract affected versions
            if ($htmlContent -match 'Affected [Pp]roducts?[\s:]+([^\r\n<]+)') {
                $info.AffectedVersions = $matches[1].Trim()
            }

            # Extract mitigation/workaround from Learn docs
            if ($url -like '*learn.microsoft.com*') {
                if ($htmlContent -match '(?s)Mitigation[s]?[:\s]*<[^>]*>(.*?)</[^>]+>') {
                    $rawText = $matches[1].Trim()
                    $cleanedText = $this.CleanHtmlText($rawText)
                    if ($cleanedText -and $cleanedText.Length -gt 10) {
                        $info.Remediation = $cleanedText
                    }
                } elseif ($htmlContent -match '(?s)Workaround[s]?[:\s]*<[^>]*>(.*?)</[^>]+>') {
                    $rawText = $matches[1].Trim()
                    $cleanedText = $this.CleanHtmlText($rawText)
                    if ($cleanedText -and $cleanedText.Length -gt 10) {
                        $info.Remediation = $cleanedText
                    }
                }
            }
        }

        # Extract download links using base class method
        $baseDownloadLinks = $this.ExtractDownloadLinks($htmlContent, $url)
        foreach ($link in $baseDownloadLinks) {
            if ($info.DownloadLinks -notcontains $link) {
                $info.DownloadLinks += $link
            }
        }

        # Clean and validate all extracted data
        $cleanedInfo = @{}
        foreach ($key in $info.Keys) {
            $value = $info[$key]
            if ($value -and $value -ne '') {
                if ($key -eq 'DownloadLinks' -and $value -is [array]) {
                    $cleanedInfo[$key] = $value
                } else {
                    $cleanedValue = $this.CleanHtmlText($value)
                    if ($cleanedValue -and $cleanedValue.Length -gt 3) {
                        $cleanedInfo[$key] = $cleanedValue
                    }
                }
            }
        }

        return $cleanedInfo
    }
}

# MicrosoftVendor class is now available for use
