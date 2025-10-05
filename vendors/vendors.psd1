# Module manifest for vendor-specific scraping modules
# This manifest defines the vendors module structure

@{
    # Module metadata
    ModuleVersion      = '1.0.0'
    GUID               = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author             = 'Columbia Cloudworks LLC'
    CompanyName        = 'Columbia Cloudworks LLC'
    Copyright          = '(c) Columbia Cloudworks LLC. All rights reserved. Licensed under MIT License.'
    Description        = 'Vendor-specific scraping modules for CVE advisory data extraction'
    PowerShellVersion  = '5.1'

    # Required modules
    RequiredModules    = @()

    # Required assemblies
    RequiredAssemblies = @()

    # Script files to process
    ScriptsToProcess   = @()

    # Types to process
    TypesToProcess     = @()

    # Formats to process
    FormatsToProcess   = @()

    # Nested modules
    NestedModules      = @(
        'BaseVendor.ps1',
        'GitHubVendor.ps1',
        'MicrosoftVendor.ps1',
        'IBMVendor.ps1',
        'ZDIVendor.ps1',
        'GenericVendor.ps1',
        'VendorManager.ps1'
    )

    # Functions to export
    FunctionsToExport  = @()

    # Cmdlets to export
    CmdletsToExport    = @()

    # Variables to export
    VariablesToExport  = @()

    # Aliases to export
    AliasesToExport    = @()

    # Module list
    ModuleList         = @(
        'BaseVendor',
        'GitHubVendor',
        'MicrosoftVendor',
        'IBMVendor',
        'ZDIVendor',
        'GenericVendor',
        'VendorManager'
    )

    # File list
    FileList           = @(
        'BaseVendor.ps1',
        'GitHubVendor.ps1',
        'MicrosoftVendor.ps1',
        'IBMVendor.ps1',
        'ZDIVendor.ps1',
        'GenericVendor.ps1',
        'VendorManager.ps1',
        'vendors.psd1'
    )

    # Private data
    PrivateData        = @{
        PSData = @{
            Tags         = @('CVE', 'Security', 'Scraping', 'Advisory', 'Vendor')
            ProjectUri   = 'https://github.com/Columbia-Cloudworks-LLC/CVExcel'
            LicenseUri   = 'https://github.com/Columbia-Cloudworks-LLC/CVExcel/blob/main/LICENSE'
            ReleaseNotes = 'Initial release of vendor-specific scraping modules'
        }
    }
}
