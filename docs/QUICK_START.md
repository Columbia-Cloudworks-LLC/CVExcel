# CVExcel Quick Start Guide

## Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- Internet connectivity

## Installation

1. **Clone or Download** the project to your local machine

2. **Set Execution Policy** (required for PowerShell scripts):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
   ```

3. **Verify Installation** by running tests:
   ```powershell
   .\tests\run-all-tests.ps1 -TestFilter "quick"
   ```

## Quick Usage

### Option 1: Full CVExcel Application
```powershell
.\CVExcel.ps1
```
This launches the full GUI application with all features.

### Option 2: Scraping Only
```powershell
.\CVScrape.ps1
```
This runs just the CVE scraping functionality.

### Option 3: Test Individual Components
```powershell
# Test vendor modules
.\tests\SIMPLE_VENDOR_TEST.ps1

# Test basic functionality
.\tests\SIMPLE_TEST.ps1
```

## VSCode Development

If using VSCode for development:

1. **Install Extensions**:
   - PowerShell (ms-vscode.powershell)
   - EditorConfig (EditorConfig.EditorConfig)

2. **Use Tasks** (Ctrl+Shift+P → "Tasks: Run Task"):
   - "Run CVScraper" - Run the main scraper
   - "Run Quick Tests" - Run basic tests
   - "Run Comprehensive Test Suite" - Run all tests

3. **Debug** (F5):
   - "Launch CVScrape.ps1" - Debug the main scraper
   - "Launch Test Script" - Debug tests

## Basic Workflow

1. **Prepare Input**: Ensure you have a CVE CSV file in the `out` directory
2. **Run Scraping**: Execute the scraper to collect additional data
3. **Review Output**: Check the enhanced CSV file in the `out` directory
4. **Check Logs**: Review log files for any issues or warnings

## Common Commands

```powershell
# Run all tests
.\tests\run-all-tests.ps1

# Run tests with verbose output
.\tests\run-all-tests.ps1 -Verbose

# Skip selenium tests (if browser issues)
.\tests\run-all-tests.ps1 -SkipSelenium

# Run only vendor tests
.\tests\run-all-tests.ps1 -TestFilter "vendor"

# Clean output directory
Remove-Item -Path ".\out\*" -Force -Recurse -ErrorAction SilentlyContinue
```

## Troubleshooting

### Issue: Execution Policy Error
**Solution**: Run this command:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
```

### Issue: Module Not Found
**Solution**: Install required modules:
```powershell
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name Selenium -Force
```

### Issue: Selenium Tests Fail
**Solution**: Skip selenium tests or install Chrome/Edge:
```powershell
.\tests\run-all-tests.ps1 -SkipSelenium
```

### Issue: Network Errors
**Solution**: Check internet connectivity and proxy settings

## Getting Help

1. **Check Logs**: Look in the `out` directory for log files
2. **Run Tests**: Use the test suite to identify issues
3. **Review Documentation**: Check the `docs` directory
4. **Enable Verbose**: Use `-Verbose` flag for detailed output

## Next Steps

- Review the [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) for detailed information
- Check [API_REFERENCE.md](API_REFERENCE.md) for technical details
- See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for production deployment
- Explore the test suite in the `tests` directory
