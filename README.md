# CVExcel - CVE Advisory Scraper

**Automated CVE data extraction and patch information gathering tool**

[![PowerShell](https://img.shields.io/badge/PowerShell-7.x-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-production-brightgreen.svg)]()

---

## 🚀 Quick Start

### Prerequisites
- **PowerShell 7.x** or higher
- **Windows 10/11** or Windows Server 2016+
- **Internet connection** for API access

### Installation

1. **Clone or download this repository**

2. **Install the Microsoft Security Updates API module** (required for MSRC data):
   ```powershell
   Install-Module -Name MsrcSecurityUpdates -Scope CurrentUser -Force
   ```

3. **Optional: Install Playwright** for JavaScript-heavy sites:
   ```powershell
   .\Install-Playwright.ps1
   ```

### Usage

**GUI Mode** (Recommended):
```powershell
.\ui\CVExpand-GUI.ps1
```

**Command Line Mode**:
```powershell
.\CVExpand.ps1 -InputFile "input.csv" -OutputFile "results.csv"
```

---

## 📋 What It Does

CVExcel automates the extraction of vulnerability and patch information from multiple security vendor sources:

✅ **Microsoft Security Response Center (MSRC)** - via official API
✅ **GitHub Security Advisories** - via GitHub API
✅ **IBM Security Bulletins** - via web scraping
✅ **Zero Day Initiative (ZDI)** - via web scraping
✅ **Other vendors** - extensible vendor system

### Features

- 🎯 **Automatic KB Article Extraction** - Gets patch download links from Microsoft
- 🔄 **Vendor-Specific Handlers** - Optimized extraction for each vendor
- 📊 **CSV Input/Output** - Easy integration with existing workflows
- 🖥️ **GUI Interface** - User-friendly interface for batch processing
- 📝 **Comprehensive Logging** - Detailed logs for troubleshooting
- 🔒 **NIST Security Compliant** - Follows security best practices

---

## 📊 Output Format

CVExcel enriches your CVE data with:

| Field | Description |
|-------|-------------|
| **CVE** | CVE identifier |
| **DownloadLinks** | Direct links to KB articles, patches, and security updates |
| **PatchID** | KB article numbers or patch identifiers |
| **Vendor** | Source vendor information |
| **AffectedVersions** | List of affected software versions |
| **Remediation** | Remediation steps and guidance |
| **ScrapeStatus** | Success/failure status |
| **ScrapedDate** | Timestamp of data extraction |

---

## 🏗️ Project Structure

```
CVExcel/
├── CVExcel.ps1                 # Main entry point
├── CVExpand.ps1                # Core expansion logic
├── Install-Playwright.ps1      # Playwright setup
├── README.md                   # This file
│
├── ui/                         # GUI modules
│   ├── CVExpand-GUI.ps1       # GUI application
│   ├── DependencyManager.ps1  # Dependency manager
│   ├── ScrapingEngine.ps1     # Scraping engine
│   └── PlaywrightWrapper.ps1  # Playwright wrapper
│
├── vendors/                    # Vendor-specific modules
│   ├── MicrosoftVendor.ps1    # Microsoft MSRC
│   ├── GitHubVendor.ps1       # GitHub Security
│   ├── IBMVendor.ps1          # IBM Security
│   ├── ZDIVendor.ps1          # Zero Day Initiative
│   └── VendorManager.ps1      # Vendor coordinator
│
├── tests/                      # Test scripts
├── docs/                       # Documentation
│   └── INDEX.md               # Documentation index
│
├── out/                        # Output directory
└── config/                     # Configuration files
```

---

## 📚 Documentation

**📖 [Complete Documentation Index](docs/INDEX.md)**

### Essential Guides
- **[Quick Start Guide](docs/QUICK_START.md)** - Get up and running
- **[MSRC API Solution](docs/MSRC_API_SOLUTION.md)** ⭐ **RECOMMENDED** - Microsoft CVE extraction
- **[Vendor Module Guide](docs/VENDOR_MODULARIZATION_SUMMARY.md)** - Adding custom vendors
- **[Deployment Guide](docs/DEPLOYMENT_GUIDE.md)** - Production deployment

### Technical Documentation
- **[API Reference](docs/API_REFERENCE.md)** - Function reference
- **[Project Overview](docs/PROJECT_OVERVIEW.md)** - Architecture overview
- **[Implementation Details](docs/IMPLEMENTATION_COMPLETE_CVEXPAND_GUI.md)** - Technical details

---

## 🎯 Key Features

### Official Microsoft API Integration ⭐

**NEW:** Uses the official [Microsoft Security Updates API](https://github.com/microsoft/MSRC-Microsoft-Security-Updates-API) for reliable, fast CVE data extraction.

**Benefits:**
- ✅ No web scraping needed for MSRC pages
- ✅ Direct KB article and download link extraction
- ✅ Fast and reliable (~2 seconds per CVE)
- ✅ Official Microsoft support

**Example Output:**
```
CVE-2024-21302
  KB Articles: KB5062557, KB5055526, KB5055518, KB5041580...
  Download Links: 18 links
    • https://catalog.update.microsoft.com/v7/site/Search.aspx?q=KB5062557
    • https://support.microsoft.com/help/5062557
    ... (16 more)
```

### Vendor Module Architecture

Extensible vendor-specific extraction modules:
- **BaseVendor** - Common functionality
- **MicrosoftVendor** - MSRC and Microsoft sites
- **GitHubVendor** - GitHub repositories
- **IBMVendor** - IBM security bulletins
- **ZDIVendor** - Zero Day Initiative advisories
- **GenericVendor** - Fallback for other sites

**Add your own vendor** - See [Vendor Module Guide](docs/VENDOR_MODULARIZATION_SUMMARY.md)

---

## 🛠️ Requirements

### System Requirements
- **OS:** Windows 10/11, Windows Server 2016+
- **PowerShell:** Version 7.x or higher
- **Memory:** 2GB RAM minimum
- **Disk:** 500MB free space

### PowerShell Modules
- **MsrcSecurityUpdates** (required for Microsoft CVEs)
  ```powershell
  Install-Module -Name MsrcSecurityUpdates -Scope CurrentUser
  ```

- **Playwright** (optional, for JavaScript-heavy sites)
  ```powershell
  .\Install-Playwright.ps1
  ```

---

## 📖 Examples

### Example 1: Process a CSV file via GUI
```powershell
# Launch GUI
.\ui\CVExpand-GUI.ps1

# Select your CSV file
# Click "Start Scraping"
# Results saved with enriched data
```

### Example 2: Command line processing
```powershell
# Process a specific CSV
.\CVExpand.ps1 -InputFile ".\data\cves.csv" -OutputFile ".\out\results.csv"

# Check the results
Import-Csv ".\out\results.csv" | Select-Object CVE, DownloadLinks
```

### Example 3: Get KB articles for a specific CVE
```powershell
# Using the official API directly
Import-Module MsrcSecurityUpdates
$update = Get-MsrcSecurityUpdate -Vulnerability CVE-2024-21302
$cvrf = Get-MsrcCvrfDocument -ID $update.value[0].ID
$cvrf.Vulnerability | Where-Object {$_.CVE -eq 'CVE-2024-21302'} |
    Select-Object -ExpandProperty Remediations |
    Where-Object {$_.URL -match 'catalog.update.microsoft.com'}
```

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Check existing documentation and issues
2. Follow PowerShell best practices
3. Include tests for new features
4. Update documentation as needed

See [docs/](docs/) for coding standards and architecture.

---

## 🔒 Security

This project follows NIST security guidelines. See the [Security Policy](SECURITY.md) for details.

**Security Features:**
- Input validation on all user-provided data
- Secure API authentication
- Comprehensive logging for audit trails
- Rate limiting and retry logic
- Error handling without information disclosure

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Microsoft Security Response Center** - For the official Security Updates API
- **PowerShell Community** - For excellent modules and support
- **Security Researchers** - For CVE data and advisories

---

## 📞 Support

### Documentation
- **[Documentation Index](docs/INDEX.md)** - Complete documentation
- **[Quick Start](docs/QUICK_START.md)** - Get started quickly
- **[FAQ](docs/README.md)** - Frequently asked questions

### Issues
- Check [existing documentation](docs/INDEX.md) first
- Review [archived docs](docs/archive/) for historical context
- Create an issue if needed with:
  - Clear description
  - Steps to reproduce
  - Expected vs actual behavior
  - Log files (from `out/scrape_log_*.log`)

---

## 🔄 Version History

### Latest (October 2025)
- ✨ **NEW:** Official Microsoft Security Updates API integration
- ✨ **NEW:** Vendor module architecture
- ✨ **NEW:** CVExpand-GUI with enhanced features
- 🐛 Fixed MSRC page scraping issues
- 📚 Comprehensive documentation overhaul

### Previous Versions
See [docs/archive/](docs/archive/) for historical documentation.

---

## 🌟 Star History

If you find this tool useful, please consider giving it a star! ⭐

---

**Built with ❤️ and PowerShell**
