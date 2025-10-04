# CVExcel API Reference

## Core Scripts

### CVScrape.ps1

Main CVE data scraping script that orchestrates the entire scraping process.

#### Parameters

- `-InputFile` (string): Path to input CSV file (optional, defaults to latest in `out` directory)
- `-OutputFile` (string): Path to output CSV file (optional, auto-generated)
- `-Verbose` (switch): Enable verbose logging
- `-SkipSelenium` (switch): Skip Selenium-based scraping
- `-MaxConcurrent` (int): Maximum concurrent scraping operations (default: 5)

#### Usage Examples

```powershell
# Basic usage
.\CVScrape.ps1

# With specific input file
.\CVScrape.ps1 -InputFile "C:\data\cves.csv"

# With verbose logging
.\CVScrape.ps1 -Verbose

# Skip Selenium tests
.\CVScrape.ps1 -SkipSelenium

# Limit concurrent operations
.\CVScrape.ps1 -MaxConcurrent 3
```

#### Return Values

- Exit code 0: Success
- Exit code 1: General error
- Exit code 2: Configuration error
- Exit code 3: Network error

### CVExcel.ps1

Main application script with GUI interface.

#### Parameters

- `-NoGUI` (switch): Run without GUI interface
- `-ConfigFile` (string): Path to configuration file
- `-LogLevel` (string): Logging level (DEBUG, INFO, WARNING, ERROR)

#### Usage Examples

```powershell
# Launch GUI application
.\CVExcel.ps1

# Run without GUI
.\CVExcel.ps1 -NoGUI

# With custom configuration
.\CVExcel.ps1 -ConfigFile "C:\config\custom.json"

# Set log level
.\CVExcel.ps1 -LogLevel "DEBUG"
```

## Vendor Modules

### BaseVendor Class

Abstract base class for all vendor-specific scraping modules.

#### Properties

- `VendorName` (string): Name of the vendor
- `BaseUrlPattern` (string): Regex pattern for matching vendor URLs

#### Methods

##### MatchesUrl([string]$url)

Checks if a URL matches this vendor's pattern.

**Parameters:**

- `$url` (string): URL to check

**Returns:**

- `[bool]`: True if URL matches vendor pattern

**Example:**

```powershell
$vendor = [MicrosoftVendor]::new()
$matches = $vendor.MatchesUrl("https://msrc.microsoft.com/update-guide/vulnerability/CVE-2023-1234")
```

##### GetApiData([string]$url, [WebRequestSession]$session)

Extracts data using vendor-specific API.

**Parameters:**

- `$url` (string): URL to scrape
- `$session` (WebRequestSession): Web session for requests

**Returns:**

- `[hashtable]`: Contains Success, Method, DownloadLinks, ExtractedData, RawData, VendorUsed

**Example:**

```powershell
$result = $vendor.GetApiData("https://github.com/owner/repo", $session)
if ($result.Success) {
    Write-Host "Download links: $($result.DownloadLinks.Count)"
}
```

##### ExtractData([string]$htmlContent, [string]$url)

Extracts structured data from HTML content.

**Parameters:**

- `$htmlContent` (string): HTML content to parse
- `$url` (string): Source URL for context

**Returns:**

- `[hashtable]`: Contains PatchID, FixVersion, AffectedVersions, Remediation, DownloadLinks, VendorUsed

**Example:**

```powershell
$data = $vendor.ExtractData($html, "https://example.com/advisory")
Write-Host "Patch ID: $($data.PatchID)"
```

##### ExtractDownloadLinks([string]$htmlContent, [string]$baseUrl)

Extracts download links from HTML content.

**Parameters:**

- `$htmlContent` (string): HTML content to parse
- `$baseUrl` (string): Base URL for resolving relative links

**Returns:**

- `[string[]]`: Array of download links

**Example:**

```powershell
$links = $vendor.ExtractDownloadLinks($html, "https://example.com")
foreach ($link in $links) {
    Write-Host "Download: $link"
}
```

##### CleanHtmlText([string]$text)

Cleans HTML text by removing tags and artifacts.

**Parameters:**

- `$text` (string): Text to clean

**Returns:**

- `[string]`: Cleaned text

**Example:**

```powershell
$cleaned = $vendor.CleanHtmlText("<p>Some <b>HTML</b> text</p>")
# Result: "Some HTML text"
```

##### TestDataQuality([hashtable]$extractedData)

Tests the quality of extracted data.

**Parameters:**

- `$extractedData` (hashtable): Data to test

**Returns:**

- `[hashtable]`: Contains QualityScore, Issues, IsGoodQuality

**Example:**

```powershell
$quality = $vendor.TestDataQuality($extractedData)
if ($quality.IsGoodQuality) {
    Write-Host "Quality score: $($quality.QualityScore)"
}
```

### GitHubVendor Class

Vendor module for GitHub advisory scraping.

#### Constructor

```powershell
$githubVendor = [GitHubVendor]::new()
```

#### Special Methods

##### GetApiData([string]$url, [WebRequestSession]$session)

Enhanced API data extraction for GitHub repositories.

**Features:**

- Repository metadata extraction
- README content retrieval
- Release information
- Download link generation

**Example:**

```powershell
$result = $githubVendor.GetApiData("https://github.com/microsoft/vscode", $session)
if ($result.Success) {
    Write-Host "Repository: $($result.RawData.Description)"
    Write-Host "Releases: $($result.RawData.Releases.Count)"
}
```

### MicrosoftVendor Class

Vendor module for Microsoft MSRC advisory scraping.

#### Constructor

```powershell
$microsoftVendor = [MicrosoftVendor]::new()
```

#### Special Methods

##### GetMsrcAdvisoryData([string]$cveId, [WebRequestSession]$session)

Extracts data from MSRC API and pages.

**Parameters:**

- `$cveId` (string): CVE identifier (e.g., "CVE-2023-1234")
- `$session` (WebRequestSession): Web session for requests

**Returns:**

- `[hashtable]`: Contains Success, Data with PatchID, AffectedVersions, Remediation, DownloadLinks

**Example:**

```powershell
$result = $microsoftVendor.GetMsrcAdvisoryData("CVE-2023-1234", $session)
if ($result.Success) {
    Write-Host "KB Articles: $($result.Data.PatchID)"
    Write-Host "Download Links: $($result.Data.DownloadLinks.Count)"
}
```

### IBMVendor Class

Vendor module for IBM advisory scraping.

#### Constructor

```powershell
$ibmVendor = [IBMVendor]::new()
```

#### Special Features

- IBM Fix ID extraction (PH numbers, APAR)
- Affected version parsing
- Fix version identification
- Remediation text extraction

### ZDIVendor Class

Vendor module for Zero Day Initiative advisory scraping.

#### Constructor

```powershell
$zdiVendor = [ZDIVendor]::new()
```

#### Special Features

- ZDI ID extraction
- Vulnerability disclosure information

### GenericVendor Class

Fallback vendor module for unknown sources.

#### Constructor

```powershell
$genericVendor = [GenericVendor]::new()
```

#### Special Features

- Generic download link extraction
- Common remediation patterns
- Fallback data extraction

## VendorManager Class

Manages and coordinates vendor-specific scraping modules.

#### Constructor

```powershell
$vendorManager = [VendorManager]::new()
```

#### Methods

##### GetVendor([string]$url)

Returns the appropriate vendor module for a given URL.

**Parameters:**

- `$url` (string): URL to match

**Returns:**

- `[BaseVendor]`: Vendor module instance

**Example:**

```powershell
$vendor = $vendorManager.GetVendor("https://msrc.microsoft.com/update-guide/vulnerability/CVE-2023-1234")
Write-Host "Using vendor: $($vendor.VendorName)"
```

##### ExtractData([string]$htmlContent, [string]$url)

Delegates data extraction to the appropriate vendor.

**Parameters:**

- `$htmlContent` (string): HTML content to parse
- `$url` (string): Source URL

**Returns:**

- `[hashtable]`: Extracted data

**Example:**

```powershell
$data = $vendorManager.ExtractData($html, "https://example.com/advisory")
```

##### ExtractDownloadLinks([string]$htmlContent, [string]$url)

Delegates download link extraction to the appropriate vendor.

**Parameters:**

- `$htmlContent` (string): HTML content to parse
- `$url` (string): Source URL

**Returns:**

- `[string[]]`: Download links

**Example:**

```powershell
$links = $vendorManager.ExtractDownloadLinks($html, "https://example.com")
```

##### GetApiData([string]$url, [WebRequestSession]$session)

Delegates API data extraction to the appropriate vendor.

**Parameters:**

- `$url` (string): URL to scrape
- `$session` (WebRequestSession): Web session

**Returns:**

- `[hashtable]`: API data

**Example:**

```powershell
$apiData = $vendorManager.GetApiData("https://api.github.com/repos/owner/repo", $session)
```

## Utility Functions

### Write-Log Function

Logging utility for consistent log formatting.

#### Parameters

- `-Message` (string): Log message
- `-Level` (string): Log level (DEBUG, INFO, SUCCESS, WARNING, ERROR)
- `-NoConsole` (switch): Suppress console output

#### Usage Examples

```powershell
# Basic logging
Write-Log -Message "Starting scraping process" -Level "INFO"

# Error logging
Write-Log -Message "Failed to connect to server" -Level "ERROR"

# Debug logging
Write-Log -Message "Processing URL: $url" -Level "DEBUG"
```

### Test-ExtractedDataQuality Function

Tests the quality of extracted data.

#### Parameters

- `$extractedData` (hashtable): Data to test

#### Returns

- `[hashtable]`: Quality assessment

#### Usage Example

```powershell
$quality = Test-ExtractedDataQuality $extractedData
if ($quality.IsGoodQuality) {
    Write-Host "Data quality is good: $($quality.QualityScore)"
} else {
    Write-Host "Data quality issues: $($quality.Issues -join ', ')"
}
```

### Clean-HtmlText Function

Cleans HTML text by removing tags and artifacts.

#### Parameters

- `$text` (string): Text to clean

#### Returns

- `[string]`: Cleaned text

#### Usage Example

```powershell
$cleaned = Clean-HtmlText "<p>Some <b>HTML</b> text</p>"
# Result: "Some HTML text"
```

## Error Handling

### Exception Types

#### ScrapingException

Custom exception for scraping-related errors.

**Properties:**

- `Message`: Error message
- `Url`: URL that caused the error
- `Vendor`: Vendor that encountered the error

#### ConfigurationException

Custom exception for configuration-related errors.

**Properties:**

- `Message`: Error message
- `ConfigKey`: Configuration key that caused the error

### Error Handling Patterns

#### Try-Catch Blocks

```powershell
try {
    $result = $vendor.ExtractData($html, $url)
} catch [ScrapingException] {
    Write-Log -Message "Scraping failed for $($_.Url): $($_.Message)" -Level "ERROR"
} catch {
    Write-Log -Message "Unexpected error: $($_.Exception.Message)" -Level "ERROR"
}
```

#### Retry Logic

```powershell
$maxRetries = 3
$retryCount = 0

do {
    try {
        $result = $vendor.ExtractData($html, $url)
        break
    } catch {
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            throw
        }
        Start-Sleep -Seconds (2 * $retryCount)
    }
} while ($retryCount -lt $maxRetries)
```

## Performance Considerations

### Concurrent Processing

```powershell
# Limit concurrent operations
$maxConcurrent = 5
$semaphore = New-Object System.Threading.Semaphore($maxConcurrent, $maxConcurrent)

# Process URLs concurrently
$jobs = @()
foreach ($url in $urls) {
    $jobs += Start-Job -ScriptBlock {
        param($url, $semaphore)
        $semaphore.WaitOne()
        try {
            # Process URL
        } finally {
            $semaphore.Release()
        }
    } -ArgumentList $url, $semaphore
}

# Wait for all jobs to complete
$jobs | Wait-Job | Receive-Job
```

### Memory Management

```powershell
# Clear variables to free memory
$html = $null
$result = $null
[System.GC]::Collect()
```

### Timeout Handling

```powershell
# Set timeout for web requests
$timeout = 30
$response = Invoke-WebRequest -Uri $url -TimeoutSec $timeout
```

## Best Practices

### Code Organization

- Use consistent naming conventions
- Implement proper error handling
- Document all public methods
- Use type annotations where possible

### Performance

- Implement concurrent processing where appropriate
- Use efficient regex patterns
- Minimize memory usage
- Implement proper cleanup

### Security

- Validate all inputs
- Sanitize output data
- Use secure communication protocols
- Implement proper authentication where needed

### Testing

- Write comprehensive unit tests
- Test error conditions
- Validate data quality
- Test performance under load
