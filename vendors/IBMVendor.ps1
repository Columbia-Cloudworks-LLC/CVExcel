# IBMVendor.ps1 - IBM-specific scraping module
# Handles IBM security advisory URLs

# Note: BaseVendor.ps1 must be loaded before this module

class IBMVendor : BaseVendor {
    IBMVendor() : base("IBM", @("ibm.com")) {}

    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        # IBM doesn't have a public API for security advisories
        # All data extraction is done via HTML parsing
        return @{
            Success = $false
            Method = 'IBM API'
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

        # IBM patterns
        if ($url -like '*ibm.com*') {
            # Extract IBM Fix ID (PH numbers, APAR, etc.)
            if ($htmlContent -match '\b(PH\d{5})\b') {
                $info.PatchID = $matches[1]
            }
            elseif ($htmlContent -match '(?:Fix ID|Bulletin ID|APAR)[\s:]+([A-Z0-9\-]+)') {
                $info.PatchID = $matches[1]
            }

            # Extract affected versions with better pattern
            if ($htmlContent -match '(?s)Affected [Vv]ersion[s]?[^<]*<[^>]*>([^<]+)') {
                $info.AffectedVersions = $matches[1].Trim()
            }
            elseif ($htmlContent -match 'Affected [Vv]ersion[s]?[\s:]+([^\r\n<]{5,100})') {
                $info.AffectedVersions = $matches[1].Trim()
            }

            # Extract fix version
            if ($htmlContent -match '(?:Fixed in|Remediated in|Fixed In Version)[^\d]*([\d\.]+)') {
                $info.FixVersion = $matches[1]
            }

            # IBM remediation often in specific sections
            if ($htmlContent -match '(?s)(?:Remediation/Fix|REMEDIATION)[^<]*<[^>]*>([^<]+)') {
                $info.Remediation = $matches[1].Trim()
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

# IBMVendor class is now available for use
