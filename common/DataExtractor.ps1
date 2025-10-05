<#
.SYNOPSIS
    Consolidated data extraction module for CVExcel project.

.DESCRIPTION
    Provides unified data extraction utilities for:
    - HTML content cleaning and normalization
    - CVE identifier extraction
    - Version and patch information parsing
    - Download link extraction and validation
    - Text pattern matching and regex utilities
    - Data quality assessment

.NOTES
    Created: October 5, 2025
    Part of: CVExcel Phase 2 Consolidation
    Replaces: Duplicate extraction logic across vendor modules
#>

# Import common logging
. "$PSScriptRoot\Logging.ps1"

class DataExtractor {
    [string]$LogFile
    [hashtable]$CommonPatterns
    [hashtable]$ExcludedExtensions

    DataExtractor([string]$logFile) {
        $this.LogFile = $logFile

        # Common regex patterns used across all extraction logic
        $this.CommonPatterns = @{
            # CVE patterns
            CVE              = 'CVE-\d{4}-\d+'
            CVEStrict        = '^CVE-(\d{4})-(\d+)$'

            # Microsoft KB patterns
            KB               = 'KB(\d+)'
            KBStrict         = '^KB(\d+)$'
            MSRCUpdate       = '(\d{4}-[A-Z][a-z]{2})'

            # Version patterns
            Version          = 'v?([\d\.]+(?:-[a-z]+)?)'
            VersionStrict    = '^\d+\.\d+(?:\.\d+)?(?:\.\d+)?$'
            SemanticVersion  = '(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'

            # Patch/Fix patterns
            PatchID          = '(?i)(patch|fix|hotfix|update)[\s:-]*([A-Z0-9-]+)'
            CommitHash       = '(?i)commit[\s:-]*([a-f0-9]{7,40})'

            # URL patterns
            HttpUrl          = 'https?://[^\s<>"\'']{10,}'
            DownloadUrl      = 'https?://[^\s<>"\'']+\.(?:msi|exe|zip|tar\.gz|tgz|rpm|deb|dmg|pkg)'

            # HTML entities
            HtmlEntity       = '&[a-z]+;|&#\d+;|&#x[a-f0-9]+;'

            # Common security keywords
            SecurityKeywords = '(?i)(vulnerability|exploit|patch|fix|remediation|mitigation|workaround|security\s+update|security\s+advisory)'
        }

        # File extensions to exclude from download links
        $this.ExcludedExtensions = @(
            'css', 'js', 'json', 'xml', 'svg',
            'png', 'jpg', 'jpeg', 'gif', 'ico', 'webp',
            'woff', 'woff2', 'ttf', 'eot', 'otf',
            'map', 'txt', 'md', 'pdf', 'doc', 'docx'
        )
    }

    #region HTML Cleaning

    <#
    .SYNOPSIS
        Cleans HTML content by removing tags, scripts, and normalizing text.
    #>
    [string] CleanHtml([string]$htmlContent) {
        if (-not $htmlContent) { return '' }

        $cleaned = $htmlContent

        # Remove dangerous/non-content elements first
        $cleaned = $cleaned -replace '(?s)<script[^>]*>.*?</script>', ' '
        $cleaned = $cleaned -replace '(?s)<style[^>]*>.*?</style>', ' '
        $cleaned = $cleaned -replace '(?s)<noscript[^>]*>.*?</noscript>', ' '
        $cleaned = $cleaned -replace '(?s)<!--.*?-->', ' '

        # Remove HTML tags but preserve line breaks
        $cleaned = $cleaned -replace '<br\s*/?>',  "`n"
        $cleaned = $cleaned -replace '</?p>', "`n"
        $cleaned = $cleaned -replace '</?div>', "`n"
        $cleaned = $cleaned -replace '<[^>]+>', ' '

        # Decode HTML entities
        $cleaned = $this.DecodeHtmlEntities($cleaned)

        # Remove JavaScript artifacts
        $cleaned = $cleaned -replace '(?i)\b(placeholder|undefined|null\s*[,}])\b', ''
        $cleaned = $cleaned -replace '(?i)\b(var\s+|let\s+|const\s+|function\s+|return\s+)', ''
        $cleaned = $cleaned -replace '(?i)\b(hasSkip|aX\.tag|aX\.card)\b.*?[,}]', ''
        $cleaned = $cleaned -replace '\{[^}]{0,50}\}', ''  # Remove small JSON-like objects

        # Normalize whitespace
        $cleaned = $cleaned -replace '\s+', ' '
        $cleaned = $cleaned.Trim()

        # Remove leading/trailing artifacts
        $cleaned = $cleaned -replace '^[,}\s\[\]]+', ''
        $cleaned = $cleaned -replace '[,}\s\[\]]+$', ''

        return $cleaned
    }

    <#
    .SYNOPSIS
        Cleans and truncates HTML text for display/storage.
    #>
    [string] CleanHtmlText([string]$text, [int]$maxLength = 300) {
        if (-not $text) { return '' }

        $cleaned = $this.CleanHtml($text)

        # Truncate if needed
        if ($maxLength -gt 0 -and $cleaned.Length -gt $maxLength) {
            $cleaned = $cleaned.Substring(0, $maxLength - 3) + "..."
        }

        return $cleaned
    }

    <#
    .SYNOPSIS
        Decodes common HTML entities to their text equivalents.
    #>
    [string] DecodeHtmlEntities([string]$text) {
        if (-not $text) { return '' }

        $decoded = $text

        # Named entities
        $decoded = $decoded -replace '&nbsp;', ' '
        $decoded = $decoded -replace '&lt;', '<'
        $decoded = $decoded -replace '&gt;', '>'
        $decoded = $decoded -replace '&amp;', '&'
        $decoded = $decoded -replace '&quot;', '"'
        $decoded = $decoded -replace '&#39;', "'"
        $decoded = $decoded -replace '&apos;', "'"
        $decoded = $decoded -replace '&ndash;', '-'
        $decoded = $decoded -replace '&mdash;', '-'
        $decoded = $decoded -replace '&hellip;', '...'
        $decoded = $decoded -replace '&trade;', '™'
        $decoded = $decoded -replace '&copy;', '©'
        $decoded = $decoded -replace '&reg;', '®'
        $decoded = $decoded -replace '&bull;', '•'

        return $decoded
    }

    #endregion

    #region Pattern Extraction

    <#
    .SYNOPSIS
        Extracts all CVE identifiers from text.
    #>
    [string[]] ExtractCVEs([string]$text) {
        if (-not $text) { return @() }

        $pattern = $this.CommonPatterns.CVE
        $regexMatches = [regex]::Matches($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        $cves = @()
        foreach ($match in $regexMatches) {
            $cve = $match.Value.ToUpper()
            if ($cves -notcontains $cve) {
                $cves += $cve
            }
        }

        return $cves
    }

    <#
    .SYNOPSIS
        Extracts Microsoft KB article numbers from text.
    #>
    [string[]] ExtractKBNumbers([string]$text) {
        if (-not $text) { return @() }

        $pattern = $this.CommonPatterns.KB
        $regexMatches = [regex]::Matches($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        $kbs = @()
        foreach ($match in $regexMatches) {
            $kb = "KB$($match.Groups[1].Value)"
            if ($kbs -notcontains $kb) {
                $kbs += $kb
            }
        }

        return $kbs
    }

    <#
    .SYNOPSIS
        Extracts version numbers from text.
    #>
    [string[]] ExtractVersions([string]$text) {
        if (-not $text) { return @() }

        $pattern = $this.CommonPatterns.Version
        $regexMatches = [regex]::Matches($text, $pattern)

        $versions = @()
        foreach ($match in $regexMatches) {
            $version = $match.Groups[1].Value
            # Validate version format
            if ($version -match '^\d+\.\d+') {
                if ($versions -notcontains $version) {
                    $versions += $version
                }
            }
        }

        return $versions
    }

    <#
    .SYNOPSIS
        Extracts commit hashes from text or URLs.
    #>
    [string[]] ExtractCommitHashes([string]$text) {
        if (-not $text) { return @() }

        $hashes = @()

        # Pattern 1: Explicit "commit: <hash>" format
        if ($text -match $this.CommonPatterns.CommitHash) {
            $regexMatches = [regex]::Matches($text, $this.CommonPatterns.CommitHash, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            foreach ($match in $regexMatches) {
                $hash = $match.Groups[1].Value
                if ($hash.Length -ge 7 -and $hashes -notcontains $hash) {
                    $hashes += $hash
                }
            }
        }

        # Pattern 2: GitHub commit URLs
        if ($text -match '/commit/([a-f0-9]{7,40})') {
            $urlMatches = [regex]::Matches($text, '/commit/([a-f0-9]{7,40})')
            foreach ($match in $urlMatches) {
                $hash = $match.Groups[1].Value
                if ($hashes -notcontains $hash) {
                    $hashes += $hash
                }
            }
        }

        return $hashes
    }

    <#
    .SYNOPSIS
        Extracts all URLs from HTML content.
    #>
    [string[]] ExtractUrls([string]$htmlContent) {
        if (-not $htmlContent) { return @() }

        $urls = @()

        # Extract from href attributes
        $hrefPattern = 'href=["'']([^"'']+)[\"'']'
        $regexMatches = [regex]::Matches($htmlContent, $hrefPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        foreach ($match in $regexMatches) {
            $url = $match.Groups[1].Value

            # Basic URL validation
            if ($url -match '^https?://' -and
                $url -notlike '*javascript:*' -and
                $url -notlike '#*' -and
                $urls -notcontains $url) {
                $urls += $url
            }
        }

        return $urls
    }

    #endregion

    #region Download Link Extraction

    <#
    .SYNOPSIS
        Extracts download links from HTML content with filtering.
    #>
    [string[]] ExtractDownloadLinks([string]$htmlContent, [string]$baseUrl) {
        if (-not $htmlContent) { return @() }

        $links = @()

        # Download file patterns
        $downloadPatterns = @(
            # Direct file links
            'href=["'']([^"'']*\.(?:msi|exe|zip|tar\.gz|tgz|rpm|deb|dmg|pkg|patch|bin|run|jar|war|ear|rar|7z|gz|bz2|xz|iso|cab)[^"'']*)[\"'']'
            # IBM Fix Central
            'href=["'']([^"'']*fixcentral[^"'']*)[\"'']'
            # Microsoft Update Catalog
            'href=["'']([^"'']*catalog\.update\.microsoft\.com[^"'']*)[\"'']'
            # GitHub releases
            'href=["'']([^"'']*github\.com[^"'']*(?:releases/download|archive|\.zip|\.tar\.gz)[^"'']*)[\"'']'
            # Red Hat Customer Portal
            'href=["'']([^"'']*access\.redhat\.com/downloads[^"'']*)[\"'']'
            # VMware downloads
            'href=["'']([^"'']*my\.vmware\.com/.*download[^"'']*)[\"'']'
        )

        foreach ($pattern in $downloadPatterns) {
            $regexMatches = [regex]::Matches($htmlContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

            foreach ($match in $regexMatches) {
                if ($match.Groups.Count -ge 2) {
                    $link = $match.Groups[1].Value

                    # Filter excluded extensions
                    if ($this.IsExcludedLink($link)) {
                        continue
                    }

                    # Convert relative to absolute URLs
                    $absoluteLink = $this.ConvertToAbsoluteUrl($link, $baseUrl)

                    if ($absoluteLink -and $links -notcontains $absoluteLink) {
                        $links += $absoluteLink
                    }
                }
            }
        }

        Write-Log -Message "Extracted $($links.Count) download links" -Level "DEBUG" -LogFile $this.LogFile
        return $links
    }

    <#
    .SYNOPSIS
        Checks if a link should be excluded based on extension.
    #>
    [bool] IsExcludedLink([string]$link) {
        foreach ($ext in $this.ExcludedExtensions) {
            if ($link -match "\.$ext(\?|$|#)") {
                return $true
            }
        }

        # Additional filters
        if ($link -like '*javascript:*' -or
            $link -like '*jquery*' -or
            $link -like '*bootstrap*' -or
            $link -like '*/themes/*' -or
            $link -like '*/core/modules/*') {
            return $true
        }

        return $false
    }

    <#
    .SYNOPSIS
        Converts relative URL to absolute URL.
    #>
    [string] ConvertToAbsoluteUrl([string]$relativeUrl, [string]$baseUrl) {
        if (-not $relativeUrl) { return $null }

        # Already absolute
        if ($relativeUrl -match '^https?://') {
            return $relativeUrl
        }

        # Try to convert relative to absolute
        try {
            $baseUri = New-Object System.Uri($baseUrl)
            $absoluteUri = New-Object System.Uri($baseUri, $relativeUrl)
            return $absoluteUri.AbsoluteUri
        } catch {
            Write-Log -Message "Failed to convert relative URL '$relativeUrl' with base '$baseUrl'" -Level "WARNING" -LogFile $this.LogFile
            return $null
        }
    }

    #endregion

    #region Data Quality Assessment

    <#
    .SYNOPSIS
        Assesses the quality of extracted data.
    #>
    [hashtable] AssessDataQuality([hashtable]$extractedData) {
        $qualityScore = 0
        $issues = @()
        $warnings = @()

        # Score based on presence of key fields
        if ($extractedData.PatchID -and $extractedData.PatchID -ne '') {
            $qualityScore += 25
        } else {
            $warnings += "Missing PatchID"
        }

        if ($extractedData.FixVersion -and $extractedData.FixVersion -ne '') {
            $qualityScore += 25
        } else {
            $warnings += "Missing FixVersion"
        }

        if ($extractedData.AffectedVersions -and $extractedData.AffectedVersions -ne '') {
            $qualityScore += 25
        } else {
            $warnings += "Missing AffectedVersions"
        }

        if ($extractedData.Remediation -and $extractedData.Remediation -ne '') {
            $qualityScore += 25
        } else {
            $warnings += "Missing Remediation"
        }

        # Check for problematic content
        $allText = ($extractedData.Values | Where-Object { $_ -is [string] }) -join ' '

        if ($allText -match '(javascript|function\s*\(|var\s+\w+\s*=)') {
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

        if ($allText -match '\{[^}]{0,20}\}') {
            $qualityScore -= 10
            $issues += "Contains JSON fragments"
        }

        # Ensure score is within bounds
        $finalScore = [Math]::Max(0, [Math]::Min(100, $qualityScore))

        return @{
            QualityScore  = $finalScore
            Issues        = $issues
            Warnings      = $warnings
            IsGoodQuality = $finalScore -ge 50
            Classification = if ($finalScore -ge 75) { 'Excellent' }
                            elseif ($finalScore -ge 50) { 'Good' }
                            elseif ($finalScore -ge 25) { 'Poor' }
                            else { 'Failed' }
        }
    }

    #endregion

    #region Validation Methods

    <#
    .SYNOPSIS
        Validates if a string is a proper CVE identifier.
    #>
    [bool] IsValidCVE([string]$cve) {
        if (-not $cve) { return $false }
        return $cve -match $this.CommonPatterns.CVEStrict
    }

    <#
    .SYNOPSIS
        Validates if a string is a proper version number.
    #>
    [bool] IsValidVersion([string]$version) {
        if (-not $version) { return $false }
        return $version -match $this.CommonPatterns.VersionStrict
    }

    <#
    .SYNOPSIS
        Validates if a string is a proper KB number.
    #>
    [bool] IsValidKB([string]$kb) {
        if (-not $kb) { return $false }
        return $kb -match $this.CommonPatterns.KBStrict
    }

    <#
    .SYNOPSIS
        Validates if a string is a valid HTTP(S) URL.
    #>
    [bool] IsValidUrl([string]$url) {
        if (-not $url) { return $false }

        try {
            $uri = [System.Uri]$url
            return $uri.Scheme -in @('http', 'https')
        } catch {
            return $false
        }
    }

    #endregion

    #region Utility Methods

    <#
    .SYNOPSIS
        Extracts security-related keywords and their context.
    #>
    [hashtable] ExtractSecurityContext([string]$text, [int]$contextLength = 100) {
        if (-not $text) {
            return @{
                Keywords = @()
                Contexts = @()
            }
        }

        $keywords = @()
        $contexts = @()

        $pattern = $this.CommonPatterns.SecurityKeywords
        $regexMatches = [regex]::Matches($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

        foreach ($match in $regexMatches) {
            $keyword = $match.Value
            if ($keywords -notcontains $keyword) {
                $keywords += $keyword

                # Extract context around the keyword
                $start = [Math]::Max(0, $match.Index - $contextLength)
                $length = [Math]::Min($text.Length - $start, $contextLength * 2)
                $context = $text.Substring($start, $length).Trim()
                $contexts += $context
            }
        }

        return @{
            Keywords = $keywords
            Contexts = $contexts
        }
    }

    <#
    .SYNOPSIS
        Normalizes whitespace in text.
    #>
    [string] NormalizeWhitespace([string]$text) {
        if (-not $text) { return '' }

        $normalized = $text -replace '\s+', ' '
        $normalized = $normalized.Trim()
        return $normalized
    }

    #endregion
}

#region Module-Level Functions

<#
.SYNOPSIS
    Creates a new DataExtractor instance.

.PARAMETER LogFile
    Path to the log file for this extractor instance.

.EXAMPLE
    $extractor = New-DataExtractor -LogFile "out/scrape_log.log"

.OUTPUTS
    DataExtractor instance
#>
function New-DataExtractor {
    [CmdletBinding()]
    [OutputType([DataExtractor])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    return [DataExtractor]::new($LogFile)
}

<#
.SYNOPSIS
    Convenience function to clean HTML text.

.PARAMETER HtmlText
    The HTML text to clean.

.PARAMETER MaxLength
    Maximum length of cleaned text (0 for no limit).

.EXAMPLE
    $cleaned = ConvertFrom-Html -HtmlText $rawHtml -MaxLength 200

.OUTPUTS
    Cleaned text string
#>
function ConvertFrom-Html {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$HtmlText,

        [int]$MaxLength = 0
    )

    # Use a temporary extractor for standalone cleaning
    $tempLog = Join-Path $env:TEMP "dataextractor_temp.log"
    $extractor = [DataExtractor]::new($tempLog)

    if ($MaxLength -gt 0) {
        return $extractor.CleanHtmlText($HtmlText, $MaxLength)
    } else {
        return $extractor.CleanHtml($HtmlText)
    }
}

#endregion

# Export module members
Export-ModuleMember -Function New-DataExtractor, ConvertFrom-Html
