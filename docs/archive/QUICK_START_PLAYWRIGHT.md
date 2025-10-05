# Playwright Quick Start Guide

## ✅ Status: WORKING & READY TO USE

All Playwright functionality is **fully operational** and tested.

## Installation (Already Complete)

The following has been completed for you:

1. ✅ Playwright DLL installed to `packages/lib/`
2. ✅ Chromium browser downloaded
3. ✅ Driver infrastructure set up at `.playwright/`
4. ✅ Function-based wrapper created

## Quick Start

### 1. Basic Usage

```powershell
# Import the wrapper
. .\PlaywrightWrapper.ps1

# Initialize browser
$initResult = New-PlaywrightBrowser

if ($initResult.Success) {
    # Navigate to a page
    $page = Invoke-PlaywrightNavigate -Url "https://example.com"

    if ($page.Success) {
        # Process the content
        Write-Host "Page size: $($page.Size) bytes"
        Write-Host "Status: $($page.StatusCode)"

        # Access HTML content
        $html = $page.Content

        # Parse with your preferred method
        # Example: $html -match '<pattern>'
    }

    # Cleanup
    Close-PlaywrightBrowser
}
```

### 2. With Error Handling

```powershell
. .\PlaywrightWrapper.ps1

try {
    # Initialize
    $result = New-PlaywrightBrowser -TimeoutSeconds 30 -Verbose
    if (-not $result.Success) {
        throw "Failed to initialize: $($result.Error)"
    }

    # Navigate
    $page = Invoke-PlaywrightNavigate -Url $targetUrl -WaitSeconds 5
    if (-not $page.Success) {
        throw "Failed to navigate: $($page.Error)"
    }

    # Process content
    $cves = Extract-CVEsFromHTML -Html $page.Content

    # Optional: Take screenshot for debugging
    Save-PlaywrightScreenshot -OutputPath "debug.png"
}
finally {
    # Always cleanup
    Close-PlaywrightBrowser
}
```

### 3. Integration with CVScrape.ps1

The `CVScrape.ps1` script automatically uses Playwright when needed:

```powershell
# Just run as normal - Playwright is used automatically for JS-heavy sites
.\CVScrape.ps1 -Product "vendor name"
```

The script will:
1. Check if Playwright is available
2. Use it for sites requiring JavaScript rendering
3. Fall back to `Invoke-WebRequest` for simple sites

## Available Functions

### `New-PlaywrightBrowser`
Initialize and launch a browser instance.

**Parameters:**
- `-BrowserType` (chromium/firefox/webkit) - Default: chromium
- `-TimeoutSeconds` (int) - Navigation timeout - Default: 30
- `-Headless` (bool) - Run headless - Default: true
- `-ExecutablePath` (string) - Custom browser path (optional)

**Returns:** Hashtable with `Success` and `Message` or `Error`

### `Invoke-PlaywrightNavigate`
Navigate to a URL and return page content.

**Parameters:**
- `-Url` (string) - Required - The URL to visit
- `-WaitSeconds` (int) - Additional wait time - Default: 5

**Returns:** Hashtable with:
- `Success` (bool)
- `Content` (string) - HTML content if successful
- `Size` (int) - Content size in bytes
- `StatusCode` (int) - HTTP status code
- `Method` (string) - Always "Playwright"
- `Error` (string) - Error message if failed

### `Save-PlaywrightScreenshot`
Capture a screenshot of the current page.

**Parameters:**
- `-OutputPath` (string) - Required - Where to save PNG
- `-FullPage` (bool) - Capture full scrollable page - Default: true

**Returns:** `$true` if successful, `$false` otherwise

### `Wait-PlaywrightSelector`
Wait for a CSS selector to appear.

**Parameters:**
- `-Selector` (string) - Required - CSS selector
- `-TimeoutSeconds` (int) - Max wait time - Default: 10

**Returns:** `$true` if element found, `$false` otherwise

### `Close-PlaywrightBrowser`
Cleanup all resources.

**Parameters:** None

### `Get-PlaywrightState`
Check current state (for debugging).

**Returns:** Hashtable with state information

### `Test-PlaywrightDll`
Check if DLL is available and load it.

**Returns:** `$true` if DLL available, `$false` otherwise

## Testing

Run the comprehensive test suite:

```powershell
.\test-playwright-functions.ps1
```

Expected output:
```
=== Playwright Function-Based Test ===
[1/5] Testing DLL availability... ✓
[2/5] Initializing Playwright browser... ✓
[3/5] Checking Playwright state... ✓
[4/5] Navigating to example.com... ✓
[5/5] Taking screenshot... ✓
[Cleanup] Closing browser... ✓
=== All Tests Passed! ===
```

## Troubleshooting

### Browser Won't Launch

**Symptom:** "Driver not found" error

**Solution:** Ensure `.playwright/` directory exists in project root:
```powershell
Copy-Item packages/bin/Debug/net6.0/.playwright . -Recurse -Force
```

### Browser Installation Failed

**Symptom:** "Browser not downloaded" error

**Solution:** Reinstall browsers:
```powershell
cd packages
dotnet run
```

### Type Errors

**Symptom:** "Cannot convert type" errors

**Solution:** Reload the DLL:
```powershell
Remove-Module PlaywrightWrapper -ErrorAction SilentlyContinue
. .\PlaywrightWrapper.ps1
```

## Performance Tips

1. **Reuse Browser Instance**: Don't create new browser for each page
   ```powershell
   New-PlaywrightBrowser  # Once
   Invoke-PlaywrightNavigate -Url $url1
   Invoke-PlaywrightNavigate -Url $url2  # Reuses same browser
   Close-PlaywrightBrowser  # At end
   ```

2. **Adjust Wait Times**: Reduce for fast sites, increase for slow ones
   ```powershell
   Invoke-PlaywrightNavigate -Url $url -WaitSeconds 2  # Fast site
   ```

3. **Use Headless Mode**: Enabled by default for better performance
   ```powershell
   New-PlaywrightBrowser -Headless $true
   ```

## Advanced Usage

### Custom Browser Executable

Use your system's Chrome installation:
```powershell
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
New-PlaywrightBrowser -ExecutablePath $chromePath
```

### Wait for Specific Element

```powershell
Invoke-PlaywrightNavigate -Url $url
$found = Wait-PlaywrightSelector -Selector "#content" -TimeoutSeconds 15
if ($found) {
    # Element loaded, safe to scrape
}
```

### Debug with Screenshots

```powershell
Invoke-PlaywrightNavigate -Url $url
Save-PlaywrightScreenshot -OutputPath "before.png"
# ... do something ...
Save-PlaywrightScreenshot -OutputPath "after.png"
```

## Next Steps

1. **Test with Real CVE Sources**
   ```powershell
   .\CVScrape.ps1 -Product "Microsoft Windows"
   ```

2. **Monitor Performance**
   - Check `out/*.log` files for timing information
   - Adjust timeouts as needed

3. **Handle Edge Cases**
   - Add retry logic for network failures
   - Implement rate limiting if needed

4. **Extend Functionality**
   - Add more vendor-specific scrapers
   - Implement custom JavaScript execution
   - Add cookie management

## Files Reference

- `PlaywrightWrapper.ps1` - Main wrapper functions
- `Install-Playwright.ps1` - DLL installation
- `packages/Program.cs` - Browser installer
- `test-playwright-functions.ps1` - Test suite
- `.playwright/` - Driver infrastructure (don't commit)
- `PLAYWRIGHT_SUCCESS.md` - Detailed implementation notes

## Support

For issues or questions:
1. Check `PLAYWRIGHT_SUCCESS.md` for troubleshooting
2. Review test output in `out/*.log`
3. Run tests with `-Verbose` flag for details

---

**Status**: ✅ Production Ready
**Last Updated**: October 4, 2025
**Version**: 1.0.0
