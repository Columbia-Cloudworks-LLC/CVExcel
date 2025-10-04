# GenericVendor.ps1 - Generic vendor scraping module
# Handles vendors that don't have specific modules

. "$PSScriptRoot\BaseVendor.ps1"

class GenericVendor : BaseVendor {
    GenericVendor() : base("Generic", @("*")) {}

    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        # Generic vendor doesn't have API support
        return @{
            Success = $false
            Method = 'Generic API'
            Error = 'No API support for generic vendor'
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

        # Generic remediation patterns - look for text within specific HTML sections
        $remediationPatterns = @(
            # Look for remediation section content
            '(?s)<[^>]*(?:class|id)[^>]*remediation[^>]*>(.*?)</[^>]+>'
            # Look for mitigation section content
            '(?s)<[^>]*(?:class|id)[^>]*mitigation[^>]*>(.*?)</[^>]+>'
            # Look for "Remediation:" followed by content in paragraph or div
            '(?s)Remediation[:\s]*<[^>]*>(.*?)</[^>]+>'
            # Simple text patterns
            'Remediation[\s:]+([^\r\n<]{30,300})'
            'Mitigation[\s:]+([^\r\n<]{30,300})'
            'Workaround[\s:]+([^\r\n<]{30,300})'
        )

        foreach ($pattern in $remediationPatterns) {
            if ($htmlContent -match $pattern) {
                $rawText = $matches[1].Trim()
                # Clean HTML from extracted text
                $cleanedText = $this.CleanHtmlText($rawText)
                if ($cleanedText -and $cleanedText.Length -gt 10) {
                    $info.Remediation = $cleanedText
                    break
                }
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

# GenericVendor class is now available for use
