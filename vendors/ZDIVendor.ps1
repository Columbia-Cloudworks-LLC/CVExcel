# ZDIVendor.ps1 - Zero Day Initiative specific scraping module
# Handles ZDI security advisory URLs

. "$PSScriptRoot\BaseVendor.ps1"

class ZDIVendor : BaseVendor {
    ZDIVendor() : base("Zero Day Initiative", @("zerodayinitiative.com")) {}

    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        # ZDI doesn't have a public API for security advisories
        # All data extraction is done via HTML parsing
        return @{
            Success = $false
            Method = 'ZDI API'
            Error = 'No public API available'
        }
    }

    [hashtable] ExtractData([string]$htmlContent, [string]$url) {
        $info = @{
            PatchID = $null
            FixVersion = $null
            AffectedVersions = $null
            Remediation = $null
            DownloadLinks = @()
        }

        # ZDI patterns
        if ($url -like '*zerodayinitiative.com*') {
            # Extract ZDI ID
            if ($url -match 'ZDI-(\d+-\d+)') {
                $info.PatchID = "ZDI-$($matches[1])"
            }
        }

        # Extract download links using base class method
        $info.DownloadLinks = $this.ExtractDownloadLinks($htmlContent, $url)

        # Clean and validate all extracted data
        $cleanedInfo = @{}
        foreach ($key in $info.Keys) {
            $value = $info[$key]
            if ($value -and $value -ne '') {
                if ($key -eq 'DownloadLinks' -and $value -is [array]) {
                    $cleanedInfo[$key] = $value
                } else {
                    $cleanedValue = $this.CleanHtmlText($value)
                    if ($cleanedValue -and $cleanedValue.Length -gt 3) {
                        $cleanedInfo[$key] = $cleanedValue
                    }
                }
            }
        }

        return $cleanedInfo
    }
}

# ZDIVendor class is now available for use
