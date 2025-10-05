<#
.SYNOPSIS
    NVD Tab - NVD CVE Exporter tab component for CVExcel GUI

.DESCRIPTION
    Modular component containing all logic for the NVD CVE Exporter tab including:
    - Product combo initialization
    - Date picker configuration
    - API testing functionality
    - CVE export operations
    - Event handlers for all NVD tab controls

.NOTES
    This module is loaded by CVExcel-GUI.ps1 and operates on GUI controls
    passed as parameters to Initialize-NvdTab.

.AUTHOR
    Columbia Cloudworks LLC
    https://github.com/Columbia-Cloudworks-LLC/CVExcel
#>

function Initialize-NvdTab {
    <#
    .SYNOPSIS
        Initializes the NVD CVE Exporter tab with all controls and event handlers.

    .PARAMETER Window
        The main WPF window object

    .PARAMETER Controls
        Hashtable containing all NVD tab control references

    .PARAMETER RootDir
        Root directory of the CVExcel installation

    .PARAMETER OutDir
        Output directory for CSV exports

    .PARAMETER ProductsFile
        Path to the products.txt file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [hashtable]$Controls,

        [Parameter(Mandatory)]
        [string]$RootDir,

        [Parameter(Mandatory)]
        [string]$OutDir,

        [Parameter(Mandatory)]
        [string]$ProductsFile
    )

    Write-Host "Initializing NVD CVE Exporter tab..." -ForegroundColor Cyan

    # -------------------- Load Products --------------------

    if (Test-Path $ProductsFile) {
        $Products = Get-Content $ProductsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
        if ($Products) {
            $Products | ForEach-Object { [void]$Controls.ProductCombo.Items.Add($_) }
            $Controls.ProductCombo.SelectedIndex = 0
            Write-Host "  Loaded $($Products.Count) products" -ForegroundColor Green
        } else {
            Write-Host "  Warning: products.txt has no usable entries" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Warning: products.txt not found at $ProductsFile" -ForegroundColor Yellow
    }

    # -------------------- Set Default Dates --------------------
    # Defer date picker initialization until window is loaded to avoid WPF timing issues
    $startPicker = $Controls.StartDatePicker
    $endPicker = $Controls.EndDatePicker

    $Window.Add_Loaded({
            try {
                $endPicker.SelectedDate = [DateTime]::UtcNow.Date
                $startPicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-30)
            } catch {
                Write-Host "  Warning: Could not set default dates - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }.GetNewClosure())

    $Controls.UseLastModCb.IsChecked = $true
    $Controls.NoDateChk.IsChecked = $false

    # -------------------- Get API Key --------------------

    $script:NvdApiKey = Get-NvdApiKey -Root $RootDir

    # -------------------- Quick Date Selector Buttons --------------------
    # Capture controls for use in closures
    $noDateChk = $Controls.NoDateChk

    $Controls.Quick30Button.Add_Click({
            $endPicker.SelectedDate = [DateTime]::UtcNow.Date
            $startPicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-30)
            $noDateChk.IsChecked = $false
        }.GetNewClosure())

    $Controls.Quick60Button.Add_Click({
            $endPicker.SelectedDate = [DateTime]::UtcNow.Date
            $startPicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-60)
            $noDateChk.IsChecked = $false
        }.GetNewClosure())

    $Controls.Quick90Button.Add_Click({
            $endPicker.SelectedDate = [DateTime]::UtcNow.Date
            $startPicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-90)
            $noDateChk.IsChecked = $false
        }.GetNewClosure())

    $Controls.Quick120Button.Add_Click({
            $endPicker.SelectedDate = [DateTime]::UtcNow.Date
            $startPicker.SelectedDate = ([DateTime]::UtcNow.Date).AddDays(-120)
            $noDateChk.IsChecked = $false
        }.GetNewClosure())

    $Controls.QuickAllButton.Add_Click({
            $noDateChk.IsChecked = $true
            Write-Host "ALL selected - will retrieve complete dataset without date filtering" -ForegroundColor Yellow
        }.GetNewClosure())

    # -------------------- Test API Button --------------------

    $Controls.TestButton.Add_Click({
            try {
                $Controls.TestButton.Content = "Testing..."
                $Controls.TestButton.IsEnabled = $false
                $Window.Cursor = 'Wait'

                Write-Host "`n=== NVD API Diagnostic Test ===" -ForegroundColor Magenta

                Write-Host "`nAPI Key Status:" -ForegroundColor Yellow
                if ($script:NvdApiKey) {
                    Write-Host "✓ API Key is configured (length: $($script:NvdApiKey.Length) characters)" -ForegroundColor Green
                } else {
                    Write-Host "⚠ No API key configured - using unauthenticated requests" -ForegroundColor Yellow
                    Write-Host "  Note: Unauthenticated requests have lower rate limits" -ForegroundColor Gray
                }

                $apiWorking = Get-NvdApiStatus -ApiKey $script:NvdApiKey

                $keywordTestOk = $false
                if ($apiWorking) {
                    $keywordTestOk = Test-NvdApiKeywordSearch -Keyword "microsoft windows" -ApiKey $script:NvdApiKey
                }

                Write-Host "`n=== Test Summary ===" -ForegroundColor Magenta
                if ($apiWorking -and $keywordTestOk) {
                    Write-Host "✓ All tests passed! The NVD API is working correctly." -ForegroundColor Green
                    [System.Windows.MessageBox]::Show("API tests passed successfully! The NVD API is working correctly.", "Test Results", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                } elseif ($apiWorking) {
                    Write-Host "⚠ Basic connectivity works, but keyword search failed." -ForegroundColor Yellow
                    Write-Host "  This might indicate an issue with search parameters or API changes." -ForegroundColor Gray
                    [System.Windows.MessageBox]::Show("Basic API connectivity works, but keyword search failed. Check the console output for details.", "Test Results", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                } else {
                    Write-Host "✗ API connectivity failed. The NVD API may be down or experiencing issues." -ForegroundColor Red
                    Write-Host "  Check the recommendations above for next steps." -ForegroundColor Gray
                    [System.Windows.MessageBox]::Show("API connectivity test failed. The NVD API may be experiencing issues. Check the console output for details and recommendations.", "Test Results", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                }

                Write-Host "`n=== End Diagnostic Test ===" -ForegroundColor Magenta
            } catch {
                Write-Host "Error during API testing: $($_.Exception.Message)" -ForegroundColor Red
                [System.Windows.MessageBox]::Show("Error during API testing: $($_.Exception.Message)", "Test Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            } finally {
                $Controls.TestButton.Content = "Test API"
                $Controls.TestButton.IsEnabled = $true
                $Window.Cursor = 'Arrow'
            }
        })

    # -------------------- Export CVEs Button --------------------

    $Controls.ExportButton.Add_Click({
            $product = [string]$Controls.ProductCombo.SelectedItem
            $sd = $Controls.StartDatePicker.SelectedDate
            $ed = $Controls.EndDatePicker.SelectedDate
            $useLM = [bool]$Controls.UseLastModCb.IsChecked
            $noDates = [bool]$Controls.NoDateChk.IsChecked

            if (-not $product) { [System.Windows.MessageBox]::Show("Pick a product.", "Validation"); return }
            if (-not $noDates) {
                if (-not $sd -or -not $ed) { [System.Windows.MessageBox]::Show("Pick both start and end dates.", "Validation"); return }
                if ($ed -lt $sd) { [System.Windows.MessageBox]::Show("End date must be on/after start date.", "Validation"); return }
            }

            $startIso = if (-not $noDates) { ConvertTo-Iso8601Z -DateTime $sd -TimePart "00:00:00.000" } else { $null }
            $endIso = if (-not $noDates) { ConvertTo-Iso8601Z -DateTime $ed -TimePart "23:59:59.999" } else { $null }

            try {
                $Window.Cursor = 'Wait'
                $Controls.ExportButton.Content = "Processing..."
                $Controls.ExportButton.IsEnabled = $false

                Write-Host "Starting CVE search for product: $product" -ForegroundColor Green
                if (-not $noDates) {
                    Write-Host "Date range: $startIso to $endIso" -ForegroundColor Cyan
                    $dateType = if ($useLM) { 'last-modified' } else { 'publication' }
                    Write-Host "Using $dateType dates" -ForegroundColor Cyan
                } else {
                    Write-Host "No date filter (validation mode)" -ForegroundColor Yellow
                }

                Write-Host "Querying NVD API..." -ForegroundColor Yellow
                $rowsRaw = Get-NvdCves -KeywordOrCpe $product `
                    -StartIso $startIso -EndIso $endIso `
                    -ApiKey $script:NvdApiKey `
                    -UseLastModified:$useLM `
                    -NoDateFilter:$noDates `
                    -Verbose

                Write-Host "Initial query returned $($rowsRaw.Count) CVEs" -ForegroundColor Green

                # If 0 rows and the product was a keyword, auto-resolve to CPEs and retry
                if (($product -notlike 'cpe:2.3:*') -and ($rowsRaw.Count -eq 0)) {
                    Write-Host "No results found, attempting CPE resolution..." -ForegroundColor Yellow
                    $cpeList = Resolve-CpeCandidates -Keyword $product -Max 5 -ApiKey $script:NvdApiKey
                    if ($cpeList -and $cpeList.Count -gt 0) {
                        Write-Host "Found $($cpeList.Count) CPE candidates, retrying..." -ForegroundColor Cyan
                        $cpeList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
                        $rowsRaw = Get-NvdCves -CpeNames $cpeList `
                            -StartIso $startIso -EndIso $endIso `
                            -ApiKey $script:NvdApiKey `
                            -UseLastModified:$useLM `
                            -NoDateFilter:$noDates `
                            -Verbose
                        Write-Host "CPE-based query returned $($rowsRaw.Count) CVEs" -ForegroundColor Green
                    } else {
                        Write-Host "No CPE candidates found for keyword: $product" -ForegroundColor Yellow
                    }
                }

                # Flatten for CSV
                Write-Host "Processing CVE data for CSV export..." -ForegroundColor Yellow
                $rows = New-Object System.Collections.Generic.List[object]
                foreach ($v in $rowsRaw) {
                    $cve = $v.cve
                    $id = $cve.id
                    $desc = ($cve.descriptions | Where-Object { $_.lang -eq "en" } | Select-Object -First 1).value
                    if (-not $desc) { $desc = ($cve.descriptions | Select-Object -First 1).value }
                    $score = Get-CvssScore -Metrics $cve.metrics
                    $sev = if ($score -ge 9) { "Critical" } elseif ($score -ge 7) { "High" } elseif ($score -ge 4) { "Medium" } elseif ($score -gt 0) { "Low" } else { $null }

                    $refs = @()
                    $references = if ($cve.references) { $cve.references } else { @() }
                    foreach ($r in $references) { if ($r.url) { $refs += $r.url } }
                    $refsJoined = ($refs -join " | ")

                    $cpeRows = Expand-CPEs -Configurations $cve.configurations
                    if (-not $cpeRows -or $cpeRows.Count -eq 0) {
                        $rows.Add([PSCustomObject]@{
                                ProductFilter  = $product
                                CVE            = $id
                                Published      = $cve.published
                                LastModified   = $cve.lastModified
                                CVSS_BaseScore = $score
                                Severity       = $sev
                                Summary        = $desc
                                RefUrls        = $refsJoined
                                Vendor         = ''
                                Product        = ''
                                Version        = ''
                                CPE23Uri       = ''
                            })
                    } else {
                        foreach ($c in $cpeRows) {
                            $rows.Add([PSCustomObject]@{
                                    ProductFilter  = $product
                                    CVE            = $id
                                    Published      = $cve.published
                                    LastModified   = $cve.lastModified
                                    CVSS_BaseScore = $score
                                    Severity       = $sev
                                    Summary        = $desc
                                    RefUrls        = $refsJoined
                                    Vendor         = $c.Vendor
                                    Product        = $c.Product
                                    Version        = $c.Version
                                    CPE23Uri       = $c.CPE23Uri
                                })
                        }
                    }
                }

                $ts = (Get-Date -Format "yyyyMMdd_HHmmss")
                $safe = ($product -replace '[^\w\.\-]+', '_').Trim('_'); if (-not $safe) { $safe = "product" }
                $outPath = Join-Path $OutDir ("{0}_{1}.csv" -f $safe, $ts)
                $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
                Write-Host "Export completed successfully!" -ForegroundColor Green
                Write-Host "IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD." -ForegroundColor Yellow
                [System.Windows.MessageBox]::Show("Exported $($rows.Count) row(s) to:`n$outPath`n`nIMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.", "Done")
            } catch {
                $errorMsg = $_.Exception.Message
                Write-Host "Error occurred: $errorMsg" -ForegroundColor Red

                $userFriendlyMsg = if ($errorMsg -like "*HTTP error 404*") {
                    "The NVD API returned a 404 error. This could indicate:`n`n" +
                    "• The API endpoint is temporarily unavailable`n" +
                    "• The search parameters are invalid (date range > 120 days)`n" +
                    "• Rate limiting or authentication issues`n`n" +
                    "Technical details: $errorMsg"
                } elseif ($errorMsg -like "*timeout*") {
                    "The request timed out. The NVD API may be slow or unavailable.`n`n" +
                    "Technical details: $errorMsg"
                } elseif ($errorMsg -like "*authentication*" -or $errorMsg -like "*401*") {
                    "Authentication failed. Please check your API key.`n`n" +
                    "Technical details: $errorMsg"
                } else {
                    "An unexpected error occurred:`n`n$errorMsg"
                }

                [System.Windows.MessageBox]::Show($userFriendlyMsg, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            } finally {
                $Window.Cursor = 'Arrow'
                $Controls.ExportButton.Content = "Export CVEs"
                $Controls.ExportButton.IsEnabled = $true
            }
        })GetNewClosure())

Write-Host "  NVD tab initialized successfully" -ForegroundColor Green
}

# Function is available for direct calling in script mode
