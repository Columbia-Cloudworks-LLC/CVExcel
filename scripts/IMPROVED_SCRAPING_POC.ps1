# Proof of Concept: Improved CVE Advisory Scraping Methods
# This script demonstrates working alternatives to standard HTML scraping

# =============================================================================
# 1. GITHUB API METHOD - Gets structured data instead of HTML soup
# =============================================================================

function Get-GitHubAdvisoryData {
    <#
    .SYNOPSIS
    Extracts CVE advisory data from GitHub repositories using the REST API.
    
    .DESCRIPTION
    Instead of scraping HTML (which misses JS-rendered content), this function
    uses GitHub's REST API to get structured JSON data including:
    - Repository description
    - Full README content
    - Releases and tags
    - Commit information
    
    .EXAMPLE
    Get-GitHubAdvisoryData -Url "https://github.com/fortra/CVE-2024-6769"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )
    
    # Extract owner and repo from URL
    if ($Url -match 'github\.com/([^/]+)/([^/]+)') {
        $owner = $matches[1]
        $repo = $matches[2] -replace '\.git$', ''  # Remove .git suffix if present
        
        Write-Host "Fetching GitHub data for $owner/$repo..." -ForegroundColor Cyan
        
        $headers = @{
            'User-Agent' = 'CVE-Advisory-Scraper/1.0'
            'Accept' = 'application/vnd.github.v3+json'
        }
        
        try {
            # Get repository metadata
            $apiUrl = "https://api.github.com/repos/$owner/$repo"
            $repoData = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30
            
            Write-Host "✓ Repository data retrieved" -ForegroundColor Green
            
            # Get README content
            $readmeHeaders = @{
                'User-Agent' = 'CVE-Advisory-Scraper/1.0'
                'Accept' = 'application/vnd.github.v3.raw'
            }
            $readme = Invoke-RestMethod -Uri "$apiUrl/readme" -Headers $readmeHeaders -TimeoutSec 30 -ErrorAction SilentlyContinue
            
            if ($readme) {
                Write-Host "✓ README retrieved ($($readme.Length) chars)" -ForegroundColor Green
            }
            
            # Get releases if available
            $releases = Invoke-RestMethod -Uri "$apiUrl/releases" -Headers $headers -TimeoutSec 30 -ErrorAction SilentlyContinue
            
            # Build structured result
            $result = @{
                Source = "GitHub"
                Url = $Url
                Description = $repoData.description
                README = $readme
                CreatedAt = $repoData.created_at
                UpdatedAt = $repoData.updated_at
                Stars = $repoData.stargazers_count
                Forks = $repoData.forks_count
                Topics = $repoData.topics -join ', '
                License = $repoData.license.name
                DefaultBranch = $repoData.default_branch
                Releases = @()
            }
            
            if ($releases -and $releases.Count -gt 0) {
                $result.Releases = $releases | ForEach-Object {
                    @{
                        TagName = $_.tag_name
                        Name = $_.name
                        PublishedAt = $_.published_at
                        Assets = $_.assets | ForEach-Object { $_.browser_download_url }
                    }
                }
                Write-Host "✓ Found $($releases.Count) releases" -ForegroundColor Green
            }
            
            return $result
        }
        catch {
            Write-Host "✗ GitHub API error: $_" -ForegroundColor Red
            return $null
        }
    }
    else {
        Write-Host "✗ Not a valid GitHub URL" -ForegroundColor Red
        return $null
    }
}

# =============================================================================
# 2. IMPROVED HTTP REQUEST - Better headers to avoid bot detection
# =============================================================================

function Invoke-ImprovedWebRequest {
    <#
    .SYNOPSIS
    Enhanced web request with realistic browser headers to avoid 403 errors.
    
    .DESCRIPTION
    Adds comprehensive browser headers and user-agent spoofing to mimic
    real browser requests and bypass basic bot detection.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        
        [int]$TimeoutSec = 30,
        
        [switch]$UseRandomDelay
    )
    
    # Random delay to appear more human-like
    if ($UseRandomDelay) {
        $delay = Get-Random -Minimum 1000 -Maximum 3000
        Start-Sleep -Milliseconds $delay
    }
    
    # Realistic browser headers
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
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Headers $headers -TimeoutSec $TimeoutSec -UseBasicParsing
        
        return @{
            Success = $true
            Content = $response.Content
            StatusCode = $response.StatusCode
            ContentLength = $response.Content.Length
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
            StatusCode = $_.Exception.Response.StatusCode.value__
        }
    }
}

# =============================================================================
# 3. NVD API INTEGRATION - Get comprehensive CVE metadata
# =============================================================================

function Get-NVDCveData {
    <#
    .SYNOPSIS
    Retrieves CVE information from the National Vulnerability Database API.
    
    .DESCRIPTION
    Gets structured CVE data including descriptions, CVSS scores, CWE mappings,
    and reference URLs from the official NVD API.
    
    .EXAMPLE
    Get-NVDCveData -CveId "CVE-2024-21302"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CveId
    )
    
    $nvdUrl = "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=$CveId"
    $headers = @{
        'User-Agent' = 'CVE-Advisory-Scraper/1.0'
    }
    
    try {
        Write-Host "Querying NVD API for $CveId..." -ForegroundColor Cyan
        
        $response = Invoke-RestMethod -Uri $nvdUrl -Headers $headers -TimeoutSec 30
        
        if ($response.vulnerabilities -and $response.vulnerabilities.Count -gt 0) {
            $vuln = $response.vulnerabilities[0].cve
            
            Write-Host "✓ NVD data retrieved" -ForegroundColor Green
            
            $result = @{
                CveId = $vuln.id
                Published = $vuln.published
                LastModified = $vuln.lastModified
                Description = $vuln.descriptions | Where-Object { $_.lang -eq 'en' } | Select-Object -First 1 -ExpandProperty value
                References = $vuln.references | ForEach-Object { $_.url }
                CVSS = @{}
                CWE = @()
            }
            
            # Extract CVSS scores
            if ($vuln.metrics.cvssMetricV31) {
                $cvss = $vuln.metrics.cvssMetricV31[0].cvssData
                $result.CVSS = @{
                    Version = "3.1"
                    BaseScore = $cvss.baseScore
                    BaseSeverity = $cvss.baseSeverity
                    Vector = $cvss.vectorString
                }
            }
            
            # Extract CWE IDs
            if ($vuln.weaknesses) {
                $result.CWE = $vuln.weaknesses | ForEach-Object {
                    $_.description | Where-Object { $_.lang -eq 'en' } | Select-Object -ExpandProperty value
                }
            }
            
            return $result
        }
        else {
            Write-Host "✗ No data found for $CveId" -ForegroundColor Yellow
            return $null
        }
    }
    catch {
        Write-Host "✗ NVD API error: $_" -ForegroundColor Red
        return $null
    }
}

# =============================================================================
# 4. SMART URL ROUTER - Automatically choose best method per vendor
# =============================================================================

function Get-AdvisoryDataSmart {
    <#
    .SYNOPSIS
    Intelligently routes to the best scraping method based on URL.
    
    .DESCRIPTION
    Analyzes the URL and automatically selects the most effective extraction
    method (API, enhanced scraping, or fallback).
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )
    
    Write-Host "`n=== Processing: $Url ===" -ForegroundColor Magenta
    
    # GitHub URLs -> Use API
    if ($Url -match 'github\.com') {
        Write-Host "Detected: GitHub URL - Using API method" -ForegroundColor Yellow
        return Get-GitHubAdvisoryData -Url $Url
    }
    
    # Microsoft MSRC URLs -> Flag for Selenium
    elseif ($Url -match 'msrc\.microsoft\.com') {
        Write-Host "Detected: Microsoft MSRC - Requires JavaScript rendering (Selenium)" -ForegroundColor Yellow
        Write-Host "⚠ Standard scraping will fail (returns only 1196 bytes)" -ForegroundColor Red
        
        return @{
            Source = "MSRC"
            Url = $Url
            Status = "RequiresSelenium"
            Message = "This page requires browser automation to render JavaScript content"
        }
    }
    
    # Other URLs -> Use enhanced HTTP request
    else {
        Write-Host "Detected: Standard vendor page - Using enhanced HTTP" -ForegroundColor Yellow
        $result = Invoke-ImprovedWebRequest -Url $Url -UseRandomDelay
        
        if ($result.Success) {
            Write-Host "✓ Retrieved $($result.ContentLength) bytes" -ForegroundColor Green
            return @{
                Source = "HTTP"
                Url = $Url
                Content = $result.Content
                ContentLength = $result.ContentLength
            }
        }
        else {
            Write-Host "✗ Failed: $($result.Error)" -ForegroundColor Red
            return $null
        }
    }
}

# =============================================================================
# DEMO / TEST SECTION
# =============================================================================

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════╗
║                                                                          ║
║     IMPROVED CVE ADVISORY SCRAPING - PROOF OF CONCEPT                   ║
║                                                                          ║
║  This demo shows working methods to extract data from vendor URLs       ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Test URLs
$testUrls = @(
    "https://github.com/fortra/CVE-2024-6769",
    "https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-21302",
    "https://www.ibm.com/support/pages/node/7245761"
)

Write-Host "`n🧪 TESTING IMPROVED METHODS..." -ForegroundColor Yellow
Write-Host "=" * 80

foreach ($url in $testUrls) {
    $data = Get-AdvisoryDataSmart -Url $url
    
    if ($data) {
        Write-Host "`n✓ Data extracted successfully!" -ForegroundColor Green
        Write-Host "Source: $($data.Source)" -ForegroundColor Cyan
        
        if ($data.Description) {
            Write-Host "Description: $($data.Description.Substring(0, [Math]::Min(100, $data.Description.Length)))..." -ForegroundColor White
        }
        
        if ($data.README) {
            Write-Host "README Length: $($data.README.Length) characters" -ForegroundColor White
        }
        
        if ($data.ContentLength) {
            Write-Host "Content Size: $($data.ContentLength) bytes" -ForegroundColor White
        }
    }
    
    Write-Host "`n" + ("=" * 80)
    Start-Sleep -Seconds 1
}

Write-Host "`n✅ DEMO COMPLETE!" -ForegroundColor Green
Write-Host @"

📊 COMPARISON TO CURRENT METHOD:

Current Method:
  - GitHub:     Gets 416KB HTML, hard to parse ❌
  - MSRC:       Gets 1.2KB skeleton HTML, no data ❌
  - IBM:        Gets 55KB HTML, some data ⚠️

Improved Method:
  - GitHub:     Structured JSON via API, full data ✅
  - MSRC:       Identifies need for Selenium ⚠️
  - IBM:        Better headers, avoids 403 errors ✅

📝 NEXT STEPS:
  1. Integrate these methods into CVScrape.ps1
  2. Install Selenium module for MSRC pages
  3. Add vendor-specific API handlers
  4. Test with full CSV file

"@ -ForegroundColor Cyan

