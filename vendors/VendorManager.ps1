# VendorManager.ps1 - Manages vendor-specific scraping modules
# This module coordinates between different vendor scrapers

# Import all vendor modules in correct order
. "$PSScriptRoot\BaseVendor.ps1"
. "$PSScriptRoot\GenericVendor.ps1"
. "$PSScriptRoot\GitHubVendor.ps1"
. "$PSScriptRoot\MicrosoftVendor.ps1"
. "$PSScriptRoot\IBMVendor.ps1"
. "$PSScriptRoot\ZDIVendor.ps1"

class VendorManager {
    [BaseVendor[]]$Vendors

    VendorManager() {
        # Initialize all vendor modules in order of specificity
        $this.Vendors = @(
            [GitHubVendor]::new()
            [MicrosoftVendor]::new()
            [IBMVendor]::new()
            [ZDIVendor]::new()
            [GenericVendor]::new()  # Generic should be last
        )
    }

    # Get the appropriate vendor for a given URL
    [BaseVendor] GetVendor([string]$url) {
        foreach ($vendor in $this.Vendors) {
            if ($vendor.CanHandle($url)) {
                return $vendor
            }
        }

        # Fallback to generic vendor
        return $this.Vendors[-1]  # Last vendor is always GenericVendor
    }

    # Extract data using the appropriate vendor
    [hashtable] ExtractData([string]$htmlContent, [string]$url) {
        $vendor = $this.GetVendor($url)
        Write-Log -Message "Using $($vendor.VendorName) vendor for URL: $url" -Level "DEBUG"

        try {
            $result = $vendor.ExtractData($htmlContent, $url)

            # Add vendor information to the result
            $result['VendorUsed'] = $vendor.VendorName
            $result['VendorMethod'] = 'HTML Extraction'

            return $result
        }
        catch {
            Write-Log -Message "Error extracting data with $($vendor.VendorName): $($_.Exception.Message)" -Level "ERROR"
            return @{
                VendorUsed = $vendor.VendorName
                VendorMethod = 'HTML Extraction'
                Error = $_.Exception.Message
            }
        }
    }

    # Get API data using the appropriate vendor
    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        $vendor = $this.GetVendor($url)
        Write-Log -Message "Using $($vendor.VendorName) vendor for API call: $url" -Level "DEBUG"

        try {
            $result = $vendor.GetApiData($url, $session)

            # Add vendor information to the result
            $result['VendorUsed'] = $vendor.VendorName

            return $result
        }
        catch {
            Write-Log -Message "Error getting API data with $($vendor.VendorName): $($_.Exception.Message)" -Level "ERROR"
            return @{
                Success = $false
                VendorUsed = $vendor.VendorName
                Error = $_.Exception.Message
            }
        }
    }

    # Get list of supported vendors
    [string[]] GetSupportedVendors() {
        return $this.Vendors | ForEach-Object { $_.VendorName }
    }

    # Get vendor statistics
    [hashtable] GetVendorStats() {
        $stats = @{
            TotalVendors = $this.Vendors.Count
            VendorList = @()
        }

        foreach ($vendor in $this.Vendors) {
            $stats.VendorList += @{
                Name = $vendor.VendorName
                Domains = $vendor.SupportedDomains
            }
        }

        return $stats
    }
}

# VendorManager class is now available for use
