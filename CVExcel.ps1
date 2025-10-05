<#
.SYNOPSIS
    CVExcel - Main entry point for CVExcel Multi-Tool CVE Processing Suite

.DESCRIPTION
    Unified entry point for CVE processing tools. When run without parameters,
    launches the GUI interface with tabbed navigation for:
    - NVD CVE Exporter: Query and export CVEs from NVD database
    - Advisory Scraper: Scrape CVE advisory URLs for patches and links
    - Future tools (expandable design)

.AUTHOR
    Columbia Cloudworks LLC
    https://github.com/Columbia-Cloudworks-LLC/CVExcel

.LICENSE
    MIT License

.PARAMETER Tool
    Optional: Specify which tool to run directly (nvd, scraper)
    If not provided, launches the unified GUI.

.EXAMPLE
    .\CVExcel.ps1
    Launches the unified GUI with all tools.

.EXAMPLE
    .\CVExcel.ps1 -Tool nvd
    Launches directly to the NVD exporter tab.

.NOTES
    IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.
    Rate Limits: 5 requests/30sec (public) or 50 requests/30sec (with API key)
#>

[CmdletBinding()]
param(
    [ValidateSet('nvd', 'scraper', 'gui')]
    [string]$Tool = 'gui'
)

# -------------------- Entry Point Logic --------------------

Write-Host "`n===============================================================================" -ForegroundColor Cyan
Write-Host "                          CVExcel - CVE Processing Suite" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan

# Check if we should launch GUI
if ($Tool -eq 'gui' -or $Tool -eq 'nvd' -or $Tool -eq 'scraper') {
    Write-Host "Launching unified GUI..." -ForegroundColor Cyan

    $guiPath = Join-Path $PSScriptRoot "ui\CVExcel-GUI.ps1"

    if (Test-Path $guiPath) {
        try {
            Write-Host "Starting CVExcel unified GUI..." -ForegroundColor Green
            & $guiPath
        } catch {
            Write-Host "Failed to launch GUI: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Error details:" -ForegroundColor Yellow
            Write-Host $_.Exception -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host "GUI file not found at: $guiPath" -ForegroundColor Red
        Write-Host "Please ensure the ui folder exists and contains CVExcel-GUI.ps1" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "Invalid tool specified: $Tool" -ForegroundColor Red
    Write-Host "Valid options: nvd, scraper, gui" -ForegroundColor Yellow
    exit 1
}
