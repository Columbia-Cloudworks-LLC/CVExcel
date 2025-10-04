# GitHubVendor.ps1 - GitHub-specific scraping module
# Handles GitHub repository URLs using the GitHub API

. "$PSScriptRoot\BaseVendor.ps1"

class GitHubVendor : BaseVendor {
    GitHubVendor() : base("GitHub", @("github.com")) {}

    [hashtable] GetApiData([string]$url, [Microsoft.PowerShell.Commands.WebRequestSession]$session) {
        # Extract owner and repo from URL
        if ($url -match 'github\.com/([^/]+)/([^/]+)') {
            $owner = $matches[1]
            $repo = $matches[2] -replace '\.git$', ''  # Remove .git suffix if present
            $repo = $repo -replace '/.*$', ''  # Remove any trailing path

            Write-Log -Message "Fetching GitHub API data for $owner/$repo" -Level "INFO"

            $headers = @{
                'User-Agent' = 'CVE-Advisory-Scraper/1.0'
                'Accept' = 'application/vnd.github.v3+json'
            }

            try {
                # Get repository metadata
                $apiUrl = "https://api.github.com/repos/$owner/$repo"
                $repoData = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30 -ErrorAction Stop

                Write-Log -Message "Successfully retrieved GitHub repository metadata" -Level "SUCCESS"

                # Get README content
                $readmeHeaders = @{
                    'User-Agent' = 'CVE-Advisory-Scraper/1.0'
                    'Accept' = 'application/vnd.github.v3.raw'
                }
                $readme = $null
                try {
                    $readme = Invoke-RestMethod -Uri "$apiUrl/readme" -Headers $readmeHeaders -TimeoutSec 30 -ErrorAction SilentlyContinue
                    if ($readme) {
                        Write-Log -Message "Successfully retrieved README ($($readme.Length) chars)" -Level "SUCCESS"
                    }
                }
                catch {
                    Write-Log -Message "No README found for repository" -Level "DEBUG"
                }

                # Get releases if available
                $releases = @()
                try {
                    $releasesData = Invoke-RestMethod -Uri "$apiUrl/releases" -Headers $headers -TimeoutSec 30 -ErrorAction SilentlyContinue
                    if ($releasesData -and $releasesData.Count -gt 0) {
                        $releases = $releasesData
                        Write-Log -Message "Found $($releases.Count) releases" -Level "INFO"
                    }
                }
                catch {
                    Write-Log -Message "No releases found for repository" -Level "DEBUG"
                }

                # Build structured result
                $extractedParts = @()
                $downloadLinks = @()

                # Add description
                if ($repoData.description) {
                    $extractedParts += "Description: $($repoData.description)"
                }

                # Add README content (truncate if too long)
                if ($readme) {
                    $readmePreview = if ($readme.Length -gt 500) { $readme.Substring(0, 500) + "..." } else { $readme }
                    $extractedParts += "README: $readmePreview"
                }

                # Add release information and download links
                if ($releases.Count -gt 0) {
                    $latestRelease = $releases[0]
                    $extractedParts += "Latest Release: $($latestRelease.tag_name) ($($latestRelease.published_at))"

                    # Extract download links from release assets
                    foreach ($release in $releases) {
                        if ($release.assets) {
                            foreach ($asset in $release.assets) {
                                $downloadLinks += $asset.browser_download_url
                            }
                        }
                        # Also include source code archives
                        if ($release.zipball_url) {
                            $downloadLinks += $release.zipball_url
                        }
                        if ($release.tarball_url) {
                            $downloadLinks += $release.tarball_url
                        }
                    }
                }

                # Add repository metadata
                $extractedParts += "Created: $($repoData.created_at)"
                $extractedParts += "Updated: $($repoData.updated_at)"
                $extractedParts += "Stars: $($repoData.stargazers_count)"

                return @{
                    Success = $true
                    Method = 'GitHub API'
                    DownloadLinks = $downloadLinks
                    ExtractedData = $extractedParts -join ' | '
                    RawData = @{
                        Description = $repoData.description
                        README = $readme
                        Releases = $releases
                    }
                }
            }
            catch {
                Write-Log -Message "GitHub API error: $_" -Level "ERROR"
                return @{
                    Success = $false
                    Method = 'GitHub API'
                    Error = $_.Exception.Message
                }
            }
        }
        else {
            Write-Log -Message "Not a valid GitHub repository URL" -Level "WARNING"
            return @{
                Success = $false
                Method = 'GitHub API'
                Error = 'Invalid GitHub URL format'
            }
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

        # Extract version from releases
        if ($htmlContent -match '(?:Version|Release)[\s:]+v?([\d\.]+)') {
            $info.FixVersion = $matches[1]
        }

        # Extract commit hash
        if ($url -match '/commit/([a-f0-9]{7,40})') {
            $info.PatchID = "Commit: $($matches[1].Substring(0, [Math]::Min(10, $matches[1].Length)))"
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

# GitHubVendor class is now available for use
