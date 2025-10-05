# CVExcel UI Components

This folder contains the GUI and supporting modules for CVExcel.

---

## 📁 Contents

### Main Application
- **CVExpand-GUI.ps1** - Main GUI application for interactive CVE processing

### Supporting Modules
- **DependencyManager.ps1** - Manages PowerShell module dependencies
- **ScrapingEngine.ps1** - Core scraping engine with retry logic
- **PlaywrightWrapper.ps1** - Playwright browser automation wrapper

---

## 🚀 Usage

### Launch GUI
```powershell
.\CVExpand-GUI.ps1
```

The GUI provides:
- File selection dialog for CSV input
- Progress tracking and status updates
- Batch processing of multiple CVEs
- Real-time logging
- Error handling and retry logic

---

## 🏗️ Architecture

### CVExpand-GUI.ps1
Main WPF-based GUI application that:
- Loads CSV files with CVE data
- Displays progress and status
- Coordinates scraping operations
- Saves enriched data to output CSV

### DependencyManager.ps1
Handles automatic installation and loading of:
- MsrcSecurityUpdates module
- Playwright (optional)
- Other required dependencies

### ScrapingEngine.ps1
Core scraping functionality:
- HTTP requests with retry logic
- Playwright integration
- Rate limiting
- Error handling

### PlaywrightWrapper.ps1
Simplified Playwright interface:
- Browser initialization
- Page navigation
- JavaScript execution
- Screenshot capture
- Cleanup and disposal

---

## 🔧 Module Dependencies

These modules integrate with:
- **vendors/** - Vendor-specific extraction modules
- **config/** - Configuration files
- **out/** - Output directory for results

---

## 📝 Development

### Adding New Features

When extending the GUI:

1. **Update CVExpand-GUI.ps1** for UI changes
2. **Extend ScrapingEngine.ps1** for new scraping methods
3. **Update DependencyManager.ps1** for new dependencies
4. **Test thoroughly** with sample CSV files

### Testing

Test scripts are located in `../tests/`:
```powershell
# Run test suite
..\tests\run-all-tests.ps1

# Test specific component
..\tests\TEST_VENDOR_MODULES.ps1
```

---

## 🐛 Troubleshooting

### GUI Won't Launch
- Ensure PowerShell 7.x is installed
- Check for .NET Framework 4.8+
- Review error logs in `../out/scrape_log_*.log`

### Playwright Issues
- Run `Install-Playwright.ps1` from project root
- Check DLL exists in `../packages/lib/`
- Verify browser binaries installed

### Module Not Found
- DependencyManager should auto-install
- Manual install: `Install-Module -Name ModuleName`
- Check PowerShell Gallery access

---

## 📚 Documentation

- **[Main Documentation](../docs/INDEX.md)** - Complete docs index
- **[API Reference](../docs/API_REFERENCE.md)** - Function reference
- **[Implementation Details](../docs/IMPLEMENTATION_COMPLETE_CVEXPAND_GUI.md)** - Technical details

---

## 🔄 Version History

### October 2025
- Integrated vendor module system
- Added official MSRC API support
- Enhanced error handling
- Improved progress tracking

---

**For more information, see the [main project documentation](../docs/INDEX.md).**
