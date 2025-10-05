<#
.SYNOPSIS
    CVExcel Unified GUI - Multi-tool CVE processing interface

.DESCRIPTION
    Unified interface with tabbed navigation for:
    - NVD CVE Exporter: Query and export CVEs from NVD database
    - Advisory Scraper: Scrape CVE advisory URLs for patches and download links
    - Expandable for future tools

.NOTES
    This is the main GUI entry point for the CVExcel project.
    Launched automatically by CVExcel.ps1 when run without parameters.

    Tab-specific logic is modularized in ui/tabs/:
    - NvdTab.ps1 - NVD CVE Exporter functionality
    - AdvisoryTab.ps1 - Advisory Scraper functionality
    - AboutTab.ps1 - About/Info tab functionality

.AUTHOR
    Columbia Cloudworks LLC
    https://github.com/Columbia-Cloudworks-LLC/CVExcel
#>

# Import required assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, System.Web

# -------------------- Setup Paths --------------------
$script:RootDir = Split-Path $PSScriptRoot -Parent
$script:OutDir = Join-Path $script:RootDir "out"
$script:ProductsFile = Join-Path $script:RootDir "products.txt"
$script:KeyFile = Join-Path $script:RootDir "nvd.api.key"

# Ensure out directory exists
if (-not (Test-Path $script:OutDir)) {
    New-Item -ItemType Directory -Path $script:OutDir | Out-Null
}

# -------------------- Import Modules --------------------
Write-Host "Loading CVExcel modules..." -ForegroundColor Cyan

# Import common modules
. "$script:RootDir\common\Logging.ps1"

# Import NVD Engine
. "$PSScriptRoot\NVDEngine.ps1"

# Import Advisory Scraper modules
. "$PSScriptRoot\PlaywrightWrapper.ps1"
. "$PSScriptRoot\DependencyManager.ps1"

# Import Vendor Modules
. "$script:RootDir\vendors\BaseVendor.ps1"
. "$script:RootDir\vendors\GenericVendor.ps1"
. "$script:RootDir\vendors\GitHubVendor.ps1"
. "$script:RootDir\vendors\MicrosoftVendor.ps1"
. "$script:RootDir\vendors\IBMVendor.ps1"
. "$script:RootDir\vendors\ZDIVendor.ps1"
. "$script:RootDir\vendors\VendorManager.ps1"

# Import Tab Modules
. "$PSScriptRoot\tabs\NvdTab.ps1"
. "$PSScriptRoot\tabs\AdvisoryTab.ps1"
. "$PSScriptRoot\tabs\AboutTab.ps1"

Write-Host "All modules loaded successfully." -ForegroundColor Green

# -------------------- Global State --------------------
$Global:LogFile = $null
$Global:VendorManager = $null
$Global:DependencyManager = $null

# -------------------- GUI XAML Definition --------------------

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CVExcel - Multi-Tool CVE Processing Suite"
        Height="550" Width="820"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        MinHeight="500" MinWidth="750">
    <Grid Margin="10">
        <TabControl x:Name="MainTabControl">
            <!-- ========== Tab 1: NVD CVE Exporter ========== -->
            <TabItem Header="📊 NVD CVE Exporter" x:Name="NvdTab">
                <Grid Margin="15">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="170"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Row="0" Grid.Column="0" VerticalAlignment="Center" Margin="0,0,8,0">Product</TextBlock>
                    <ComboBox x:Name="ProductCombo" Grid.Row="0" Grid.Column="1" Height="26" />

                    <TextBlock Grid.Row="1" Grid.Column="0" VerticalAlignment="Center" Margin="0,8,8,0">Start date (UTC)</TextBlock>
                    <DatePicker x:Name="StartDatePicker" Grid.Row="1" Grid.Column="1" Margin="0,8,0,0" />

                    <TextBlock Grid.Row="2" Grid.Column="0" VerticalAlignment="Center" Margin="0,8,8,0">End date (UTC)</TextBlock>
                    <DatePicker x:Name="EndDatePicker" Grid.Row="2" Grid.Column="1" Margin="0,8,0,0" />

                    <TextBlock Grid.Row="3" Grid.Column="0" VerticalAlignment="Center" Margin="0,8,8,0">Quick Select</TextBlock>
                    <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" Margin="0,8,0,0">
                        <Button x:Name="Quick30" Content="30 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="Quick60" Content="60 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="Quick90" Content="90 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="Quick120" Content="120 days" Width="60" Height="24" Margin="0,0,4,0" FontSize="11"/>
                        <Button x:Name="QuickAll" Content="ALL" Width="60" Height="24" FontSize="11"/>
                    </StackPanel>

                    <CheckBox x:Name="UseLastMod" Grid.Row="4" Grid.Column="1" Margin="0,8,0,0"
                              Content="Use last-modified dates (not publication)" />
                    <CheckBox x:Name="NoDateChk" Grid.Row="5" Grid.Column="1" Margin="0,8,0,0"
                              Content="Validate product only (no dates)" />

                    <StackPanel Grid.Row="6" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
                        <Button x:Name="TestButton" Content="Test API" Width="80" Height="28" Margin="0,0,8,0"/>
                        <Button x:Name="ExportButton" Content="Export CVEs" Width="96" Height="28" Margin="0,0,8,0"/>
                    </StackPanel>

                    <TextBlock Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,12,0,0"
                               TextWrapping="Wrap" FontSize="10" Foreground="Gray">
                        IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.
                    </TextBlock>
                </Grid>
            </TabItem>

            <!-- ========== Tab 2: Advisory Scraper ========== -->
            <TabItem Header="🔍 Advisory Scraper" x:Name="ExpandTab">
                <Grid Margin="15">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="140"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Row="0" Grid.Column="0" VerticalAlignment="Center" Margin="0,0,8,0">Select CSV File</TextBlock>
                    <ComboBox x:Name="CsvCombo" Grid.Row="0" Grid.Column="1" Height="26" />

                    <TextBlock x:Name="FileInfoText" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2"
                               Margin="0,8,0,0" TextWrapping="Wrap" Foreground="Gray"/>

                    <TextBlock x:Name="PlaywrightStatusText" Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2"
                               Margin="0,8,0,0" TextWrapping="Wrap" Foreground="Blue" FontSize="11"/>

                    <TextBlock Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,12,0,4">
                        <Run FontWeight="Bold">Enhanced Features:</Run>
                    </TextBlock>

                    <TextBlock Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Margin="0,0,0,0" TextWrapping="Wrap" FontSize="11">
                        • Proven Playwright integration for JavaScript rendering
                        <LineBreak/>
                        • HTTP fallback when Playwright unavailable
                        <LineBreak/>
                        • Enhanced MSRC page extraction with download links
                        <LineBreak/>
                        • Comprehensive logging and error handling
                        <LineBreak/>
                        • Automatic backup creation and data validation
                    </TextBlock>

                    <CheckBox x:Name="ForceRescrapeChk" Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2"
                              Margin="0,12,0,0" Content="Force re-scrape (ignore existing ScrapedDate)"/>

                    <CheckBox x:Name="CreateBackupChk" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="2"
                              Margin="0,8,0,0" Content="Create backup before processing" IsChecked="True"/>

                    <ProgressBar x:Name="ProgressBar" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2"
                                 Height="20" Margin="0,12,0,0" Minimum="0" Maximum="100" Value="0"/>

                    <TextBlock x:Name="StatusText" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2"
                               HorizontalAlignment="Center" VerticalAlignment="Center" FontSize="11" Foreground="White"/>

                    <StackPanel Grid.Row="8" Grid.Column="1" Orientation="Horizontal"
                                HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,16,0,40">
                        <Button x:Name="RefreshButton" Content="Refresh List" Width="100" Height="28" Margin="0,0,8,0"/>
                        <Button x:Name="ScrapeButton" Content="Scrape" Width="96" Height="28" Margin="0,0,8,0"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- ========== Tab 3: About ========== -->
            <TabItem Header="ℹ️ About" x:Name="AboutTab">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock FontSize="18" FontWeight="Bold" Margin="0,0,0,10">CVExcel - Multi-Tool CVE Processing Suite</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="0,0,0,10">
                            A comprehensive PowerShell-based CVE processing toolkit with GUI interface.
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Tools Available:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            <Bold>📊 NVD CVE Exporter:</Bold> Query and export CVE data from the NVD database.
                            <LineBreak/>
                            • Supports keyword and CPE searches
                            <LineBreak/>
                            • Date range filtering with automatic chunking
                            <LineBreak/>
                            • API key support for higher rate limits
                            <LineBreak/>
                            • CSV export with full CVE details
                        </TextBlock>

                        <TextBlock TextWrapping="Wrap" Margin="10,10,0,5">
                            <Bold>🔍 Advisory Scraper:</Bold> Scrape CVE advisory URLs for patches and download links.
                            <LineBreak/>
                            • Playwright integration for JavaScript-heavy pages
                            <LineBreak/>
                            • HTTP fallback for reliability
                            <LineBreak/>
                            • Vendor-specific extraction modules
                            <LineBreak/>
                            • Batch CSV processing
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Security &amp; Compliance:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            • Follows NIST secure coding guidelines
                            <LineBreak/>
                            • Implements rate limiting for NVD API
                            <LineBreak/>
                            • Comprehensive logging and error handling
                            <LineBreak/>
                            • Input validation and sanitization
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Project Information:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            Version: 2.0 (Unified GUI)
                            <LineBreak/>
                            Maintained by: Columbia Cloudworks LLC
                            <LineBreak/>
                            License: MIT License
                            <LineBreak/>
                            Documentation: See docs/ folder
                        </TextBlock>

                        <TextBlock FontSize="14" FontWeight="Bold" Margin="0,15,0,5">Links:</TextBlock>
                        <TextBlock TextWrapping="Wrap" Margin="10,0,0,5">
                            <Hyperlink x:Name="GitHubLink" NavigateUri="https://github.com/Columbia-Cloudworks-LLC/CVExcel">
                                GitHub Repository
                            </Hyperlink>
                        </TextBlock>

                        <TextBlock FontSize="10" FontStyle="Italic" Margin="0,20,0,0" Foreground="Gray" TextWrapping="Wrap">
                            IMPORTANT: This product uses data from the NVD API but is not endorsed or certified by the NVD.
                        </TextBlock>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Close button at bottom -->
        <Button x:Name="CloseButton" Content="Close" Width="80" Height="28"
                HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,20,15"/>
    </Grid>
</Window>
"@

# -------------------- Load and Initialize GUI --------------------

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# -------------------- Get GUI Elements --------------------

# NVD Tab controls
$nvdControls = @{
    ProductCombo    = $window.FindName('ProductCombo')
    StartDatePicker = $window.FindName('StartDatePicker')
    EndDatePicker   = $window.FindName('EndDatePicker')
    UseLastModCb    = $window.FindName('UseLastMod')
    NoDateChk       = $window.FindName('NoDateChk')
    Quick30Button   = $window.FindName('Quick30')
    Quick60Button   = $window.FindName('Quick60')
    Quick90Button   = $window.FindName('Quick90')
    Quick120Button  = $window.FindName('Quick120')
    QuickAllButton  = $window.FindName('QuickAll')
    TestButton      = $window.FindName('TestButton')
    ExportButton    = $window.FindName('ExportButton')
}

# Advisory Scraper Tab controls
$advisoryControls = @{
    CsvCombo              = $window.FindName('CsvCombo')
    FileInfoText          = $window.FindName('FileInfoText')
    PlaywrightStatusText  = $window.FindName('PlaywrightStatusText')
    ForceRescrapeChk      = $window.FindName('ForceRescrapeChk')
    CreateBackupChk       = $window.FindName('CreateBackupChk')
    ProgressBar           = $window.FindName('ProgressBar')
    StatusText            = $window.FindName('StatusText')
    RefreshButton         = $window.FindName('RefreshButton')
    ScrapeButton          = $window.FindName('ScrapeButton')
}

# About Tab controls
$aboutControls = @{
    GitHubLink = $window.FindName('GitHubLink')
}

# Global controls
$closeButton = $window.FindName('CloseButton')

# -------------------- Initialize Tabs --------------------

Write-Host "`nInitializing GUI tabs..." -ForegroundColor Cyan

# Initialize NVD Tab
Initialize-NvdTab -Window $window `
    -Controls $nvdControls `
    -RootDir $script:RootDir `
    -OutDir $script:OutDir `
    -ProductsFile $script:ProductsFile

# Initialize Advisory Scraper Tab
Initialize-AdvisoryTab -Window $window `
    -Controls $advisoryControls `
    -RootDir $script:RootDir `
    -OutDir $script:OutDir

# Initialize About Tab
Initialize-AboutTab -Window $window `
    -Controls $aboutControls

Write-Host "All tabs initialized successfully.`n" -ForegroundColor Green

# -------------------- Global Event Handlers --------------------

$closeButton.Add_Click({ $window.Close() })

# -------------------- Show Window --------------------

Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "                 CVExcel - Multi-Tool CVE Processing Suite" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "  [NVD] NVD CVE Exporter - Query and export from NVD database" -ForegroundColor Cyan
Write-Host "  [ADV] Advisory Scraper - Extract patches and download links" -ForegroundColor Cyan
Write-Host "  [INFO] About - Project information and documentation" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# Show the window
[void]$window.ShowDialog()
