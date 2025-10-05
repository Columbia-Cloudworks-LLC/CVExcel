# Vendor Modules Directory

This directory contains vendor-specific scraping modules for the CVE Advisory Scraper. Each vendor module implements a consistent interface for extracting advisory data from different security vendor websites.

## Module Structure

### Base Classes

- **`BaseVendor.ps1`** - Base class that defines the common interface and shared functionality for all vendor scrapers
- **`VendorManager.ps1`** - Manages and coordinates between different vendor scrapers

### Vendor-Specific Modules

- **`GitHubVendor.ps1`** - Handles GitHub repository URLs using the GitHub API
- **`MicrosoftVendor.ps1`** - Handles Microsoft MSRC, Learn, and other Microsoft URLs
- **`IBMVendor.ps1`** - Handles IBM security advisory URLs
- **`ZDIVendor.ps1`** - Handles Zero Day Initiative security advisory URLs
- **`GenericVendor.ps1`** - Handles vendors that don't have specific modules

## Usage

The vendor modules are automatically loaded and managed by the `VendorManager` class. The main `CVScraper.ps1` script uses the vendor manager to:

1. **Route URLs** to the appropriate vendor module
2. **Extract data** using vendor-specific methods
3. **Handle API calls** for vendors that support them
4. **Provide consistent interfaces** across all vendors

## Adding New Vendors

To add support for a new vendor:

1. **Create a new vendor class** that inherits from `BaseVendor`
2. **Implement required methods**:
   - `ExtractData()` - Extract data from HTML content
   - `GetApiData()` - Make API calls if supported
3. **Add the vendor** to the `VendorManager` constructor
4. **Update the module manifest** (`vendors.psd1`)

### Example New Vendor Module

```powershell
# NewVendor.ps1
. "$PSScriptRoot\BaseVendor.ps1"

class NewVendor : BaseVendor {
    NewVendor() : base("New Vendor", @("newvendor.com")) {}
    
    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        # Implement API calls if supported
        return @{
            Success = $false
            Method = 'New Vendor API'
            Error = 'No API support'
        }
    }
    
    [hashtable] ExtractData([string]$htmlContent, [string]$url) {
        # Implement HTML parsing logic
        $info = @{
            PatchID = $null
            FixVersion = $null
            AffectedVersions = $null
            Remediation = $null
            DownloadLinks = @()
        }
        
        # Add vendor-specific extraction logic here
        
        return $info
    }
}

Export-ModuleMember -Type NewVendor
```

## Benefits of Modular Design

1. **Maintainability** - Each vendor's logic is isolated and easier to maintain
2. **Extensibility** - New vendors can be added without modifying existing code
3. **Consistency** - All vendors implement the same interface
4. **Testing** - Individual vendor modules can be tested independently
5. **Code Reuse** - Common functionality is shared through the base class

## Module Dependencies

- All vendor modules depend on `BaseVendor.ps1`
- `VendorManager.ps1` depends on all vendor modules
- The main `CVScraper.ps1` script depends on `VendorManager.ps1`

## Error Handling

Each vendor module should handle errors gracefully and return consistent error information. The `VendorManager` provides fallback mechanisms and error reporting.

## Performance Considerations

- Vendor modules are loaded once at startup
- The `VendorManager` caches vendor instances for performance
- API calls are made only when supported by the vendor
- HTML parsing is optimized for each vendor's specific patterns
