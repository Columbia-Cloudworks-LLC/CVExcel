# CVExcel

A PowerShell-based GUI tool that queries the **NIST NVD CVE API v2.0** and exports vulnerability data to CSV. Perfect for security analysts who need to track CVEs for specific products or CPEs.

---

## Features

- **🎨 Simple GUI**: WPF-based interface with product dropdown and date range pickers
- **🔍 Flexible Search**: 
  - Keyword search (e.g., "microsoft windows")
  - CPE-based search (e.g., "cpe:2.3:o:microsoft:windows_10:*:*:*:*:*:*:*:*")
  - Automatic CPE resolution when keyword search returns 0 results
- **📊 Comprehensive Data**: 
  - CVE metadata (ID, published date, last modified)
  - CVSS scores (v3.1, v3.0, v2 with automatic fallback)
  - Severity ratings (Critical/High/Medium/Low)
  - Affected products with vendor/product/version breakdowns
  - Reference URLs
- **🚀 Robust Error Handling**:
  - Automatic retry with exponential backoff
  - Fallback from last-modified to publication dates on 404
  - Public API access fallback if API key is invalid
  - Comprehensive diagnostic tools
- **✅ NIST Compliance**: 
  - Follows NVD API best practices
  - Respects rate limits (6-second delays between requests)
  - Proper API key header formatting
- **📁 Clean Output**: Timestamped CSV files in `./out/` directory

---

## Requirements

- **Windows PowerShell 5.1+** or **PowerShell 7+**
- Internet connection to `services.nvd.nist.gov`
- (Recommended) **NVD API key** for higher rate limits

---

## Quick Start

### 1. Request an NVD API Key (Recommended)

1. Visit https://nvd.nist.gov/developers/request-an-api-key
2. Fill out the form and submit
3. **Check your email** and click the activation link (expires in 7 days)
4. **Copy the API key** from the activation page
5. Save it to `nvd.api.key` file next to the script:
   ```powershell
   "your-api-key-here" | Out-File -FilePath .\nvd.api.key -NoNewline
   ```
   Or set as environment variable:
   ```powershell
   $env:NVD_API_KEY = "your-api-key-here"
   ```

**Important**: Without an API key, you're limited to **5 requests per 30 seconds**. With a key, you get **50 requests per 30 seconds**.

### 2. Create Your Products List

Create a `products.txt` file with one product or CPE per line:

```text
# Keywords (broad search)
microsoft windows
mozilla firefox
google chrome

# CPE 2.3 URIs (precise search)
cpe:2.3:o:microsoft:windows_10:*:*:*:*:*:*:*:*
cpe:2.3:a:adobe:acrobat_reader:*:*:*:*:*:*:*:*
```

### 3. Run the Script

```powershell
.\CVExcel.ps1
```

### 4. Use the GUI

1. **Select a product** from the dropdown
2. **Choose date range** (defaults to last 7 days, UTC)
3. **Options**:
   - ✅ "Use last-modified dates" (recommended for tracking changes)
   - ☐ "Validate product only (no dates)" (test query without date filter)
4. **Test API** button - Verify connectivity and API key status
5. **OK** - Export CVEs to CSV

### 5. Find Your Results

CSV files are saved to `./out/` with format: `<product>_<yyyyMMdd_HHmmss>.csv`

---

## Usage Details

### GUI Options

- **Product**: Select from your `products.txt` list
- **Start/End Date (UTC)**: Date range for CVE publication or modification
- **Use last-modified dates**: 
  - ✅ Checked: Search by when CVEs were last modified (good for tracking updates)
  - ☐ Unchecked: Search by publication date (default)
- **Validate product only**: 
  - ✅ Checked: Runs query without date filters (useful for testing)
  - ☐ Unchecked: Uses date range (default)
- **Test API**: Runs diagnostic tests to verify:
  - API endpoint connectivity
  - API key validity
  - Keyword search functionality
  - Rate limit status

### Output CSV Schema

| Column | Description |
|--------|-------------|
| `ProductFilter` | Selected product from GUI |
| `CVE` | CVE identifier (e.g., CVE-2025-12345) |
| `Published` | NVD publication timestamp |
| `LastModified` | Last modified timestamp |
| `CVSS_BaseScore` | Base score (v3.1 → v3.0 → v2 fallback) |
| `Severity` | Critical/High/Medium/Low |
| `Summary` | English description |
| `RefUrls` | Reference URLs (pipe-separated) |
| `Vendor` | Vendor from CPE (if available) |
| `Product` | Product from CPE (if available) |
| `Version` | Version from CPE (if available) |
| `CPE23Uri` | Full CPE 2.3 URI (if available) |

---

## How It Works

### Query Flow

1. **Product Selection**:
   - If product starts with `cpe:2.3:` → uses CPE name filter
   - Otherwise → uses keyword search
2. **Keyword Search Fallback**:
   - If keyword search returns 0 results
   - Automatically resolves top 5 CPE candidates
   - Retries with CPE-based search
3. **Date Filtering**:
   - Uses last-modified dates (if checkbox selected)
   - Falls back to publication dates on 404 error
4. **API Key Management**:
   - Tries with API key first
   - Falls back to public access if key is invalid
   - Shows clear warnings about rate limits
5. **Pagination**:
   - Fetches up to 2000 results per page
   - Automatically handles multiple pages
   - Respects 6-second delay between requests

### Error Handling

- **Automatic retries** with exponential backoff (3 attempts)
- **Fallback strategies**:
  - Invalid API key → public access
  - Last-modified dates 404 → publication dates
  - Keyword returns 0 → CPE resolution
- **User-friendly error messages** with troubleshooting guidance
- **Comprehensive logging** with `-Verbose` flag support

---

## API Key Troubleshooting

### "API key returned 404 - likely invalid/expired"

**Causes**:
1. Key not activated (you must click the email link within 7 days)
2. Key expired or revoked
3. Key has incorrect format (should be UUID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

**Solution**:
1. Request new key at https://nvd.nist.gov/developers/request-an-api-key
2. **Check your email** and click the activation link
3. Copy the activated key from the webpage
4. Update `nvd.api.key` file or `$env:NVD_API_KEY`

**Note**: The tool will automatically fall back to public access (5 requests/30sec) if your key is invalid.

---

## Best Practices

### Rate Limiting
- **With API key**: Up to 50 requests per 30 seconds
- **Without API key**: Only 5 requests per 30 seconds
- Script automatically sleeps 6 seconds between requests
- Use narrow date ranges to reduce requests

### Search Strategy
1. **Test with "Validate product only"** to verify product name
2. **Use CPE for precision** when you know the exact product
3. **Use keywords for discovery** when exploring
4. **Narrow date ranges** for faster exports

### Data Maintenance
- Run **weekly** with last-modified dates to catch CVE updates
- Keep **separate `products.txt`** files per client/project
- Use **version control** for `products.txt` to track changes

---

## Troubleshooting

### GUI doesn't appear
- Ensure you're running in a **desktop session** (not headless)
- PowerShell 7 on Windows supports WPF
- Try running as administrator if permissions issue

### Empty/No results
- Check date range (remember: **UTC timezone**)
- Verify product name with "Validate product only"
- Try broader keyword first, then refine to CPE
- Check verbose output: `.\CVExcel.ps1 -Verbose`

### Rate limit errors
- Ensure API key is properly activated
- Check rate limit with "Test API" button
- Reduce date range or number of products
- Wait 30 seconds before retrying

### 404 errors
- Run "Test API" diagnostic to check connectivity
- Regenerate API key if test shows it's invalid
- Verify internet connection to `services.nvd.nist.gov`
- Check firewall/proxy settings

---

## Advanced Usage

### Command Line Parameters

The GUI runs automatically, but you can access verbose logging:

```powershell
.\CVExcel.ps1 -Verbose
```

### API Key Priority

The script checks for API key in this order:
1. `./nvd.api.key` file (in script directory)
2. `$env:NVD_API_KEY` environment variable
3. Falls back to public access if neither exists

### Custom Products List

You can create multiple product files:
```powershell
# Copy products.txt to products_client1.txt
Copy-Item products.txt products_client1.txt

# Edit for specific client
notepad products_client1.txt

# Rename for script to use
Move-Item products_client1.txt products.txt -Force
.\CVExcel.ps1
```

---

## Technical Details

### NVD API v2.0
- Base URL: `https://services.nvd.nist.gov/rest/json/cves/2.0`
- Supports: CPE name filter, keyword search, date ranges
- Rate limits: 5/30sec (public), 50/30sec (with key)
- Max results per page: 2000

### Date Handling
- All dates in **ISO-8601 UTC** format
- DatePicker input converted: `YYYY-MM-DD 00:00:00.000Z` (start) to `YYYY-MM-DD 23:59:59.999Z` (end)
- Supports both publication dates and last-modified dates

### CPE 2.3 Format
```
cpe:2.3:part:vendor:product:version:update:edition:language:sw_edition:target_sw:target_hw:other
```

---

## CVScrape - Advisory Scraper

A companion tool (`CVScrape.ps1`) scrapes advisory URLs from exported CSV files to extract:
- Download links (patches, updates)
- Patch IDs (KB articles, fix versions)
- Remediation information
- Affected versions

### Features
- **Complete Download Chain**: Automatically generates `catalog.update.microsoft.com` links from KB articles, bridging CVE → Advisory → KB → Patch Download
- **MSRC Dynamic Page Handling**: Multi-tier extraction (API → HTML scrape → KB extraction) for JavaScript-heavy Microsoft pages
- **Session-Based Requests**: Maintains cookies across requests to bypass basic anti-bot protection
- **403 Graceful Handling**: Marks blocked URLs for manual review instead of failing
- **Force Re-scrape**: Optional checkbox to override existing ScrapedDate and re-process files
- **Enhanced Headers**: Uses realistic browser headers with Referer and encoding support
- **Idempotent**: Won't re-scrape already processed files (unless forced)
- **Detailed Logging**: Creates timestamped log files with comprehensive statistics
- **Progress Tracking**: Real-time progress bar and status updates

### Usage
1. Run `CVExcel.ps1` to export CVE data to CSV
2. Run `CVScrape.ps1` and select the CSV file
3. (Optional) Enable "Force re-scrape" to override existing data
4. Click "Scrape" to fetch and parse advisory pages
5. Review blocked URLs (if any) in the completion summary

### Output
- Enhanced CSV with new columns: `DownloadLinks`, `ExtractedData`, `ScrapeStatus`, `ScrapedDate`
- **DownloadLinks** column includes direct links to Microsoft Update Catalog (e.g., `https://catalog.update.microsoft.com/v7/site/Search.aspx?q=KB5062560`)
- Backup CSV (`*_backup.csv`) of original file
- Detailed log file (`scrape_log_*.log`) in `./out/`

### Download Chain Example
```
CVE-2024-21302 
  → https://msrc.microsoft.com/update-guide/vulnerability/CVE-2024-21302
  → KB5062560 (auto-extracted)
  → https://catalog.update.microsoft.com/v7/site/Search.aspx?q=KB5062560 (auto-generated)
  → [Download Button on Catalog Page]
```
See `DOWNLOAD_CHAIN_VALIDATION.md` for technical details.

---

## Roadmap

- [x] **Advisory scraping tool** - Extract patches and remediation from URLs
- [x] **MSRC API fallback** - Handle dynamic Microsoft pages
- [ ] **CISA KEV integration** - Flag known exploited vulnerabilities
- [ ] **Excel export** - Multi-sheet XLSX with formatting
- [ ] **Scheduled exports** - Automated weekly/monthly runs
- [ ] **Email notifications** - Send reports automatically
- [ ] **Filters** - By CVSS score, severity, or date range
- [ ] **Saved profiles** - Reusable configurations per client
- [ ] **Webhook support** - Push to Teams/Slack channels

---

## Important Notices

### NVD Data Usage

**This product uses data from the NVD API but is not endorsed or certified by the NVD.**

Data is provided by NIST NVD and is in the public domain per Title 17 of the United States Code. You may not use the NVD name to imply endorsement.

For citation information, see: https://nvd.nist.gov/general/faq

### Rate Limits

Per NIST NVD API best practices:
- Sleep 6 seconds between requests (implemented)
- Request API key for production use (recommended)
- Check for updates no more than once every 2 hours

---

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly with both public and authenticated access
4. Submit a pull request with description

---

## License

MIT License - See `LICENSE` file for details

---

## Support

- **Issues**: GitHub Issues tracker
- **NVD API**: https://nvd.nist.gov/developers
- **NVD Support**: nvd@nist.gov

---

## Acknowledgments

- **NIST National Vulnerability Database** for providing the CVE API v2.0
- **CPE 2.3 Specification** for product identification standards
- PowerShell community for WPF examples and best practices
