# CVExcel Test Suite

This directory contains comprehensive tests for the CVExcel project, covering all major components and functionality.

## Test Structure

### Quick Tests

- **`test-powershell-version.ps1`** - PowerShell version compatibility
- **`SIMPLE_TEST.ps1`** - Basic CVScraper functionality
- **`SIMPLE_VENDOR_TEST.ps1`** - Basic vendor module tests

### Comprehensive Tests

- **`TEST_VENDOR_MODULES.ps1`** - Full vendor module functionality
- **`TEST_CVSCRAPE_IMPROVEMENTS.ps1`** - CVScraper enhancements
- **`TEST_SELENIUM_FIXES.ps1`** - Selenium integration
- **`TEST_AUTO_INSTALL.ps1`** - Auto-install features
- **`test-cvexcel-integration.ps1`** - Main CVExcel integration

### Test Infrastructure

- **`run-all-tests.ps1`** - Comprehensive test runner
- **`test-config.json`** - Test configuration and settings
- **`test-required-modules.ps1`** - Module dependency checks

## Running Tests

### Run All Tests

```powershell
# Run complete test suite
.\tests\run-all-tests.ps1

# Run with verbose output
.\tests\run-all-tests.ps1 -Verbose

# Skip selenium tests
.\tests\run-all-tests.ps1 -SkipSelenium

# Skip vendor tests
.\tests\run-all-tests.ps1 -SkipVendorTests

# Filter tests
.\tests\run-all-tests.ps1 -TestFilter "vendor"
```

### Run Individual Tests

```powershell
# Run specific test
.\tests\SIMPLE_TEST.ps1

# Run vendor tests
.\tests\TEST_VENDOR_MODULES.ps1

# Run selenium tests
.\tests\TEST_SELENIUM_FIXES.ps1
```

### Test Suites

```powershell
# Quick smoke tests
.\tests\run-all-tests.ps1 -TestFilter "quick"

# Vendor-specific tests
.\tests\run-all-tests.ps1 -TestFilter "vendor"

# Integration tests
.\tests\run-all-tests.ps1 -TestFilter "integration"
```

## Test Configuration

The `test-config.json` file contains:

- **Test Suites**: Predefined sets of tests
- **Environments**: Different testing configurations
- **Skip Conditions**: Automatic test skipping based on conditions
- **Settings**: Timeout, retry, and output configurations

## Test Results

Tests generate detailed reports including:

- Pass/Fail status for each test
- Execution time
- Error messages and details
- Summary statistics

## Prerequisites

### PowerShell Modules

- PowerShell 5.1 or later
- WebAdministration (for IIS tests)
- PSScriptAnalyzer (for code quality tests)

### Optional Dependencies

- Chrome/Edge browser (for Selenium tests)
- Network connectivity (for web scraping tests)

## Troubleshooting

### Common Issues

1. **Execution Policy**

   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
   ```

2. **Missing Modules**

   ```powershell
   # Install required modules
   Install-Module -Name PSScriptAnalyzer -Force
   ```

3. **Selenium Issues**

   ```powershell
   # Skip selenium tests if browser not available
   .\tests\run-all-tests.ps1 -SkipSelenium
   ```

### Test Logs

Test logs are saved to the `test-logs` directory when enabled in configuration.

## Adding New Tests

1. Create test file following naming convention: `test-*.ps1`
2. Include proper error handling and exit codes
3. Add to appropriate test suite in `test-config.json`
4. Document in this README

## Test Categories

- **Unit Tests**: Individual function testing
- **Integration Tests**: Component interaction testing
- **System Tests**: End-to-end functionality testing
- **Performance Tests**: Speed and resource usage testing
- **Compatibility Tests**: Cross-platform and version testing
