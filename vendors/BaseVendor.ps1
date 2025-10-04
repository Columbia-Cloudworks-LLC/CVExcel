# BaseVendor.ps1 - Base class for vendor-specific scraping modules
# This module defines the common interface and shared functionality for all vendor scrapers

class BaseVendor {
    [string]$VendorName
    [string[]]$SupportedDomains
    [hashtable]$DefaultHeaders

    BaseVendor([string]$name, [string[]]$domains) {
        $this.VendorName = $name
        $this.SupportedDomains = $domains
        $this.DefaultHeaders = @{
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
    }

    # Abstract method that must be implemented by each vendor
    [hashtable] ExtractData([string]$htmlContent, [string]$url) {
        throw "ExtractData method must be implemented by vendor-specific classes"
    }

    # Abstract method for vendor-specific API calls
    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        throw "GetApiData method must be implemented by vendor-specific classes"
    }

    # Check if this vendor can handle the given URL
    [bool] CanHandle([string]$url) {
        foreach ($domain in $this.SupportedDomains) {
            if ($url -like "*$domain*") {
                return $true
            }
        }
        return $false
    }

    # Common method to clean HTML text
    [string] CleanHtmlText([string]$text) {
        if (-not $text) { return '' }

        # Remove JavaScript/CSS first (most problematic)
        $cleaned = $text -replace '(?s)<script[^>]*>.*?</script>', ' '
        $cleaned = $cleaned -replace '(?s)<style[^>]*>.*?</style>', ' '

        # Remove HTML tags
        $cleaned = $cleaned -replace '<[^>]+>', ' '

        # Decode common HTML entities
        $cleaned = $cleaned -replace '&nbsp;', ' '
        $cleaned = $cleaned -replace '&lt;', '<'
        $cleaned = $cleaned -replace '&gt;', '>'
        $cleaned = $cleaned -replace '&amp;', '&'
        $cleaned = $cleaned -replace '&quot;', '"'
        $cleaned = $cleaned -replace '&#39;', "'"
        $cleaned = $cleaned -replace '&apos;', "'"
        $cleaned = $cleaned -replace '&ndash;', '-'
        $cleaned = $cleaned -replace '&mdash;', '-'
        $cleaned = $cleaned -replace '&hellip;', '...'

        # Remove common placeholder text and artifacts
        $cleaned = $cleaned -replace '(?i)\b(placeholder|undefined|null\s*[,}])\b', ''
        $cleaned = $cleaned -replace '(?i)\b(var\s+|let\s+|const\s+|function\s+)', ''
        $cleaned = $cleaned -replace '(?i)\b(hasSkip|aX\.tag|aX\.card)\b.*?[,}]', ''

        # Remove excessive whitespace and normalize
        $cleaned = $cleaned -replace '\s+', ' '
        $cleaned = $cleaned.Trim()

        # Remove common artifacts from scraping
        $cleaned = $cleaned -replace '^[,}\s]+', ''
        $cleaned = $cleaned -replace '[,}\s]+$', ''

        # Limit length to prevent overly long strings
        if ($cleaned.Length -gt 300) {
            $cleaned = $cleaned.Substring(0, 297) + "..."
        }

        return $cleaned
    }

    # Common method to extract download links
    [string[]] ExtractDownloadLinks([string]$htmlContent, [string]$baseUrl) {
        if (-not $htmlContent) { return @() }

        $links = @()

        # Exclude these non-download file types
        $excludeExtensions = @('css', 'js', 'json', 'xml', 'svg', 'png', 'jpg', 'jpeg', 'gif', 'ico', 'woff', 'woff2', 'ttf', 'eot')

        # Common download file extensions and catalog patterns
        $downloadPatterns = @(
            # Direct file links
            'href=["'']([^"'']*\.(?:msi|exe|zip|tar\.gz|tgz|rpm|deb|dmg|pkg|patch|bin|run|jar|war|ear|rar|7z|gz|bz2|xz|iso|cab)[^"'']*)[\"'']'
            # IBM Fix Central patterns (but not CSS/JS)
            'href=["'']([^"'']*fixcentral[^"'']*)[\"'']'
            # Microsoft Update Catalog (including KB search links)
            'href=["'']([^"'']*catalog\.update\.microsoft\.com[^"'']*)[\"'']'
            # Direct KB references to catalog (even if not full URL)
            'catalog\.update\.microsoft\.com/v7/site/Search\.aspx\?q=(KB\d+)'
            # GitHub releases and tags (not just any github link)
            'href=["'']([^"'']*github\.com[^"'']*(?:releases/download|archive|\.zip|\.tar\.gz)[^"'']*)[\"'']'
        )

        foreach ($pattern in $downloadPatterns) {
            if ($htmlContent -match $pattern) {
                $matches = [regex]::Matches($htmlContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($match in $matches) {
                    if ($match.Groups.Count -ge 2) {
                        $link = $match.Groups[1].Value

                        # Check if link has excluded extension
                        $hasExcludedExt = $false
                        foreach ($ext in $excludeExtensions) {
                            if ($link -match "\.$ext(\?|$)") {
                                $hasExcludedExt = $true
                                break
                            }
                        }
                        if ($hasExcludedExt) { continue }

                        # Convert relative URLs to absolute
                        if ($link -notmatch '^https?://') {
                            try {
                                $baseUri = New-Object System.Uri($baseUrl)
                                $absoluteUri = New-Object System.Uri($baseUri, $link)
                                $link = $absoluteUri.AbsoluteUri
                            }
                            catch {
                                # Skip invalid URLs
                                continue
                            }
                        }

                        # Additional filters
                        if ($link -and
                            $link -notlike '*javascript:*' -and
                            $link -notlike '*#*' -and
                            $link -notlike '*.css*' -and
                            $link -notlike '*.js*' -and
                            $link -notlike '*jquery*' -and
                            $link -notlike '*bootstrap*' -and
                            $link -notlike '*/themes/*' -and
                            $link -notlike '*/core/modules/*') {
                            $links += $link
                        }
                    }
                }
            }
        }

        return ($links | Select-Object -Unique)
    }

    # Common method to test data quality
    [hashtable] TestDataQuality([hashtable]$extractedData) {
        $qualityScore = 0
        $issues = @()

        # Check for meaningful content
        if ($extractedData.PatchID -and $extractedData.PatchID -ne '') {
            $qualityScore += 25
        }
        if ($extractedData.FixVersion -and $extractedData.FixVersion -ne '') {
            $qualityScore += 25
        }
        if ($extractedData.AffectedVersions -and $extractedData.AffectedVersions -ne '') {
            $qualityScore += 25
        }
        if ($extractedData.Remediation -and $extractedData.Remediation -ne '') {
            $qualityScore += 25
        }

        # Check for problematic content
        $allText = ($extractedData.Values -join ' ').ToLower()
        if ($allText -match '(javascript|function|var\s|let\s|const\s)') {
            $qualityScore -= 30
            $issues += "Contains JavaScript code"
        }
        if ($allText -match '(placeholder|undefined|null\s*[,}])') {
            $qualityScore -= 20
            $issues += "Contains placeholder text"
        }
        if ($allText.Length -lt 10) {
            $qualityScore -= 20
            $issues += "Content too short"
        }

        return @{
            QualityScore = [Math]::Max(0, $qualityScore)
            Issues = $issues
            IsGoodQuality = $qualityScore -ge 50
        }
    }
}

# BaseVendor class is now available for use
