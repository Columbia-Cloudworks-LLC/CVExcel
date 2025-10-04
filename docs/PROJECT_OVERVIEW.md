# CVExcel Project Overview

## Project Description

CVExcel is a comprehensive PowerShell-based CVE (Common Vulnerabilities and Exposures) data scraping and analysis tool. It provides automated collection of vulnerability information from multiple vendor sources, with a modular architecture designed for extensibility and maintainability.

## Key Features

### Core Functionality

- **Automated CVE Data Collection**: Scrapes CVE information from multiple vendor sources
- **Modular Vendor Support**: Extensible vendor-specific scraping modules
- **Data Processing**: Cleans, validates, and structures vulnerability data
- **Export Capabilities**: Outputs data in CSV format for analysis
- **Logging**: Comprehensive logging with different levels (DEBUG, INFO, SUCCESS, WARNING, ERROR)

### Advanced Features

- **Selenium Integration**: JavaScript rendering for dynamic content
- **API Fallbacks**: Multiple data sources for comprehensive coverage
- **Auto-Installation**: Automatic dependency management
- **Error Handling**: Robust error handling with retry mechanisms
- **Data Validation**: Quality checks and data cleaning

## Project Structure

```
CVExcel/
├── docs/                          # Project documentation
│   ├── PROJECT_OVERVIEW.md       # This file
│   ├── API_REFERENCE.md          # API documentation
│   ├── DEPLOYMENT_GUIDE.md       # Deployment instructions
│   └── ...                       # Other documentation
├── tests/                         # Test suite
│   ├── run-all-tests.ps1         # Comprehensive test runner
│   ├── test-config.json          # Test configuration
│   ├── SIMPLE_TEST.ps1           # Basic functionality tests
│   ├── TEST_VENDOR_MODULES.ps1   # Vendor module tests
│   └── ...                       # Other test files
├── vendors/                       # Vendor-specific modules
│   ├── BaseVendor.ps1            # Base vendor class
│   ├── GitHubVendor.ps1          # GitHub advisory scraper
│   ├── MicrosoftVendor.ps1       # Microsoft MSRC scraper
│   ├── IBMVendor.ps1             # IBM advisory scraper
│   ├── ZDIVendor.ps1             # Zero Day Initiative scraper
│   └── GenericVendor.ps1         # Generic fallback scraper
├── scripts/                       # Utility scripts
├── .vscode/                       # VSCode configuration
│   ├── tasks.json                # Build and test tasks
│   ├── launch.json               # Debug configurations
│   ├── settings.json             # Workspace settings
│   └── extensions.json           # Recommended extensions
├── out/                          # Output directory
├── CVScrape.ps1                  # Main scraper script
├── CVExcel.ps1                   # Main application script
└── README.md                     # Project README
```

## Architecture

### Modular Design

The project uses a modular architecture with vendor-specific scraping modules:

1. **BaseVendor**: Abstract base class defining common functionality
2. **Vendor-Specific Modules**: Implementations for different vendors
3. **VendorManager**: Coordinates between vendor modules
4. **Generic Fallback**: Handles unknown vendors

### Data Flow

1. **Input**: CVE CSV file with vulnerability references
2. **Processing**: Vendor-specific data extraction
3. **Validation**: Data quality checks and cleaning
4. **Output**: Enhanced CSV with extracted information

### Key Components

#### CVScrape.ps1

- Main scraping orchestrator
- Handles CSV input/output
- Manages scraping sessions
- Coordinates vendor modules

#### Vendor Modules

- **GitHubVendor**: GitHub API and repository scraping
- **MicrosoftVendor**: MSRC API and page scraping
- **IBMVendor**: IBM advisory page scraping
- **ZDIVendor**: Zero Day Initiative scraping
- **GenericVendor**: Fallback for unknown sources

#### Test Suite

- **Unit Tests**: Individual component testing
- **Integration Tests**: Component interaction testing
- **System Tests**: End-to-end functionality testing

## Supported Vendors

### Primary Vendors

- **Microsoft**: MSRC advisories and security updates
- **GitHub**: Security advisories and repository information
- **IBM**: Security bulletins and fix information
- **Zero Day Initiative**: Vulnerability disclosures

### Generic Support

- Any vendor with standard HTML advisory pages
- Download link extraction
- Basic data extraction patterns

## Data Output

### CSV Structure

The tool outputs enhanced CSV files with the following columns:

- **ProductFilter**: Product filter used
- **CVE**: CVE identifier
- **Published**: Publication date
- **LastModified**: Last modification date
- **CVSS_BaseScore**: CVSS base score
- **Severity**: Severity rating
- **Summary**: Vulnerability summary
- **RefUrls**: Reference URLs
- **Vendor**: Vendor name
- **Product**: Product name
- **Version**: Product version
- **CPE23Uri**: CPE identifier
- **DownloadLinks**: Extracted download links
- **ExtractedData**: Additional extracted data
- **ScrapeStatus**: Scraping status
- **ScrapedDate**: Scraping timestamp

### Log Files

- **Timestamped logs**: Detailed operation logs
- **Error tracking**: Failed operations and reasons
- **Performance metrics**: Scraping statistics

## Development Workflow

### Getting Started

1. Clone the repository
2. Install required PowerShell modules
3. Run tests to verify setup
4. Configure vendor-specific settings

### Development

1. Use VSCode with PowerShell extension
2. Run tests frequently
3. Follow modular architecture patterns
4. Document new features

### Testing

1. **Quick Tests**: Basic functionality verification
2. **Vendor Tests**: Vendor-specific functionality
3. **Integration Tests**: End-to-end testing
4. **Full Test Suite**: Complete system testing

## Configuration

### VSCode Integration

- **Tasks**: Predefined build and test tasks
- **Debugging**: Launch configurations for debugging
- **Settings**: Workspace-specific settings
- **Extensions**: Recommended development extensions

### Test Configuration

- **Test Suites**: Predefined test collections
- **Environments**: Different testing configurations
- **Skip Conditions**: Automatic test skipping
- **Reporting**: Detailed test results

## Deployment

### Requirements

- PowerShell 5.1 or later
- Windows 10/11 or Windows Server 2016+
- Internet connectivity for scraping
- Optional: Chrome/Edge for Selenium tests

### Installation

1. Download or clone the project
2. Set execution policy: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`
3. Run tests to verify installation
4. Configure vendor-specific settings

### Usage

1. **Basic Usage**: Run `CVExcel.ps1`
2. **Scraping Only**: Run `CVScrape.ps1`
3. **Testing**: Run `tests/run-all-tests.ps1`

## Contributing

### Code Standards

- Follow PowerShell best practices
- Use consistent naming conventions
- Document all public functions
- Include comprehensive tests

### Adding New Vendors

1. Create new vendor class inheriting from BaseVendor
2. Implement required methods
3. Add to VendorManager
4. Create tests for new vendor
5. Update documentation

### Testing Requirements

- All new code must have tests
- Tests must pass before submission
- Include both positive and negative test cases
- Document test scenarios

## Troubleshooting

### Common Issues

1. **Execution Policy**: Set to Bypass for current process
2. **Module Dependencies**: Install required modules
3. **Network Issues**: Check connectivity and proxies
4. **Selenium Issues**: Verify browser installation

### Debug Mode

- Enable verbose logging
- Use VSCode debugger
- Check test logs
- Verify vendor module loading

## Performance Considerations

### Optimization

- Parallel processing where possible
- Efficient regex patterns
- Minimal memory usage
- Caching mechanisms

### Monitoring

- Execution time tracking
- Memory usage monitoring
- Error rate tracking
- Success rate metrics

## Security Considerations

### Data Handling

- No sensitive data storage
- Secure network communications
- Input validation
- Output sanitization

### Dependencies

- Regular dependency updates
- Security vulnerability scanning
- Minimal dependency footprint
- Trusted sources only

## Future Enhancements

### Planned Features

- Additional vendor support
- Enhanced data processing
- Web interface
- API endpoints
- Database integration

### Community Contributions

- Vendor module contributions
- Test improvements
- Documentation updates
- Performance optimizations
