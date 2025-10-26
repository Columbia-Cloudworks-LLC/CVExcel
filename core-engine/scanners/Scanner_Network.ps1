# Scanner_Network.ps1 - Network vulnerability scanner for non-credentialed checks
# Performs port scans, service detection, and network-based vulnerability checks

# Import common modules
. "$PSScriptRoot/../common/ModuleLoader.ps1"
. "$PSScriptRoot/../common/DataSchemas.ps1"

# Common logging function for scanner modules
function Write-ScannerLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$ModuleName = "Scanner_Network"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [Scanner:$ModuleName] $Message"

    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "INFO" { "Cyan" }
        "DEBUG" { "Gray" }
        default { "White" }
    }

    Write-Host $logEntry -ForegroundColor $color
}

class Scanner_Network {
    [string]$ModuleName
    [hashtable]$Configuration
    [datetime]$LastScan
    [bool]$IsEnabled

    Scanner_Network() {
        $this.ModuleName = "Scanner_Network"
        $this.IsEnabled = $true
        $this.LastScan = Get-Date
        $this.Configuration = @{
            DefaultPorts = @(21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 993, 995, 1433, 3389, 5985, 5986)
            CommonPorts = @(1..1024)
            ExtendedPorts = @(1..65535)
            ScanTimeout = 5000
            MaxConcurrentScans = 50
            ServiceDetection = $true
            BannerGrabbing = $true
            VulnerabilityChecks = $true
            RateLimitDelay = 100
        }
    }

    # Main scanning method
    [Finding[]] ScanAsset([Asset]$asset) {
        Write-ScannerLog "Starting network scan for asset: $($asset.Hostname)" -Level "INFO"

        $findings = @()

        try {
            # Port scanning
            $openPorts = $this.ScanPorts($asset.IPAddress)

            # Service detection
            if ($this.Configuration.ServiceDetection) {
                $services = $this.DetectServices($asset.IPAddress, $openPorts)
            }

            # Vulnerability checks
            if ($this.Configuration.VulnerabilityChecks) {
                $vulnFindings = $this.CheckVulnerabilities($asset, $openPorts)
                $findings += $vulnFindings
            }

            Write-ScannerLog "Network scan completed for $($asset.Hostname). Found $($findings.Count) findings" -Level "SUCCESS"
            return $findings
        }
        catch {
            Write-ScannerLog "Network scan failed for $($asset.Hostname): $($_.Exception.Message)" -Level "ERROR"
            return $findings
        }
    }

    # Scan ports on target
    [hashtable[]] ScanPorts([string]$ipAddress) {
        Write-ScannerLog "Scanning ports on $ipAddress" -Level "DEBUG"

        $openPorts = @()
        $portsToScan = $this.Configuration.DefaultPorts

        foreach ($port in $portsToScan) {
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                $connectTask = $tcpClient.ConnectAsync($ipAddress, $port)

                if ($connectTask.Wait($this.Configuration.ScanTimeout)) {
                    if ($tcpClient.Connected) {
                        $openPorts += @{
                            Port = $port
                            Protocol = "TCP"
                            State = "Open"
                            Service = $this.GetServiceName($port)
                        }
                        Write-ScannerLog "Port $port is open on $ipAddress" -Level "DEBUG"
                    }
                }

                $tcpClient.Close()
            }
            catch {
                # Port is closed or filtered
            }

            # Rate limiting
            Start-Sleep -Milliseconds $this.Configuration.RateLimitDelay
        }

        return $openPorts
    }

    # Detect services running on open ports
    [hashtable[]] DetectServices([string]$ipAddress, [hashtable[]]$openPorts) {
        Write-ScannerLog "Detecting services on $ipAddress" -Level "DEBUG"

        $services = @()

        foreach ($portInfo in $openPorts) {
            $port = $portInfo.Port

            try {
                # Banner grabbing
                if ($this.Configuration.BannerGrabbing) {
                    $banner = $this.GrabBanner($ipAddress, $port)
                    if ($banner) {
                        $portInfo.Banner = $banner
                        $portInfo.Service = $this.IdentifyService($banner, $port)
                    }
                }

                $services += $portInfo
            }
            catch {
                Write-ScannerLog "Service detection failed for port $port: $($_.Exception.Message)" -Level "WARNING"
            }
        }

        return $services
    }

    # Grab banner from service
    [string] GrabBanner([string]$ipAddress, [int]$port) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $tcpClient.Connect($ipAddress, $port)

            $stream = $tcpClient.GetStream()
            $stream.ReadTimeout = 3000

            # Send a simple request or just read initial response
            $buffer = New-Object byte[] 1024
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)

            $banner = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytesRead)

            $stream.Close()
            $tcpClient.Close()

            return $banner.Trim()
        }
        catch {
            return $null
        }
    }

    # Identify service from banner
    [string] IdentifyService([string]$banner, [int]$port) {
        $bannerLower = $banner.ToLower()

        # Common service identification
        if ($bannerLower -match 'ssh') { return "SSH" }
        if ($bannerLower -match 'ftp') { return "FTP" }
        if ($bannerLower -match 'smtp') { return "SMTP" }
        if ($bannerLower -match 'http') { return "HTTP" }
        if ($bannerLower -match 'pop3') { return "POP3" }
        if ($bannerLower -match 'imap') { return "IMAP" }
        if ($bannerLower -match 'telnet') { return "Telnet" }
        if ($bannerLower -match 'microsoft') { return "Microsoft" }

        # Fallback to port-based identification
        return $this.GetServiceName($port)
    }

    # Get service name by port
    [string] GetServiceName([int]$port) {
        $serviceMap = @{
            21 = "FTP"
            22 = "SSH"
            23 = "Telnet"
            25 = "SMTP"
            53 = "DNS"
            80 = "HTTP"
            110 = "POP3"
            135 = "RPC"
            139 = "NetBIOS"
            143 = "IMAP"
            443 = "HTTPS"
            445 = "SMB"
            993 = "IMAPS"
            995 = "POP3S"
            1433 = "SQL Server"
            3389 = "RDP"
            5985 = "WinRM HTTP"
            5986 = "WinRM HTTPS"
        }

        return $serviceMap[$port] ?? "Unknown"
    }

    # Check for common vulnerabilities
    [Finding[]] CheckVulnerabilities([Asset]$asset, [hashtable[]]$openPorts) {
        Write-ScannerLog "Checking vulnerabilities for $($asset.Hostname)" -Level "DEBUG"

        $findings = @()

        foreach ($portInfo in $openPorts) {
            $port = $portInfo.Port
            $service = $portInfo.Service

            # Check for specific vulnerabilities based on open ports
            switch ($port) {
                21 { # FTP
                    $ftpFindings = $this.CheckFTPVulnerabilities($asset, $portInfo)
                    $findings += $ftpFindings
                }
                23 { # Telnet
                    $telnetFinding = $this.CreateFinding($asset, "TELNET_ENABLED", "High", "Telnet service is enabled", "Disable Telnet service and use SSH instead")
                    $findings += $telnetFinding
                }
                135 { # RPC
                    $rpcFindings = $this.CheckRPCVulnerabilities($asset, $portInfo)
                    $findings += $rpcFindings
                }
                139 { # NetBIOS
                    $netbiosFinding = $this.CreateFinding($asset, "NETBIOS_ENABLED", "Medium", "NetBIOS service is enabled", "Disable NetBIOS over TCP/IP if not needed")
                    $findings += $netbiosFinding
                }
                445 { # SMB
                    $smbFindings = $this.CheckSMBVulnerabilities($asset, $portInfo)
                    $findings += $smbFindings
                }
                3389 { # RDP
                    $rdpFindings = $this.CheckRDPVulnerabilities($asset, $portInfo)
                    $findings += $rdpFindings
                }
            }
        }

        return $findings
    }

    # Check FTP vulnerabilities
    [Finding[]] CheckFTPVulnerabilities([Asset]$asset, [hashtable]$portInfo) {
        $findings = @()

        # Check for anonymous FTP
        try {
            $ftpClient = New-Object System.Net.FtpWebRequest
            $ftpClient.Credentials = New-Object System.Net.NetworkCredential("anonymous", "anonymous@")
            $ftpClient.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
            $ftpClient.Uri = "ftp://$($asset.IPAddress):$($portInfo.Port)/"

            $response = $ftpClient.GetResponse()
            $response.Close()

            $finding = $this.CreateFinding($asset, "FTP_ANONYMOUS", "High", "Anonymous FTP access is enabled", "Disable anonymous FTP access")
            $findings += $finding
        }
        catch {
            # Anonymous FTP not available - this is good
        }

        return $findings
    }

    # Check RPC vulnerabilities
    [Finding[]] CheckRPCVulnerabilities([Asset]$asset, [hashtable]$portInfo) {
        $findings = @()

        # Check for RPC endpoint mapper
        try {
            $rpcClient = New-Object System.Net.Sockets.TcpClient
            $rpcClient.Connect($asset.IPAddress, 135)

            if ($rpcClient.Connected) {
                $finding = $this.CreateFinding($asset, "RPC_ENDPOINT_MAPPER", "Medium", "RPC Endpoint Mapper is accessible", "Restrict RPC access to authorized networks")
                $findings += $finding
            }

            $rpcClient.Close()
        }
        catch {
            # RPC not accessible
        }

        return $findings
    }

    # Check SMB vulnerabilities
    [Finding[]] CheckSMBVulnerabilities([Asset]$asset, [hashtable]$portInfo) {
        $findings = @()

        # Check for SMBv1 (if possible to detect)
        try {
            $smbClient = New-Object System.Net.Sockets.TcpClient
            $smbClient.Connect($asset.IPAddress, 445)

            if ($smbClient.Connected) {
                # This is a simplified check - real SMB version detection would be more complex
                $finding = $this.CreateFinding($asset, "SMB_ENABLED", "Medium", "SMB service is accessible", "Ensure SMB is properly secured and consider disabling SMBv1")
                $findings += $finding
            }

            $smbClient.Close()
        }
        catch {
            # SMB not accessible
        }

        return $findings
    }

    # Check RDP vulnerabilities
    [Finding[]] CheckRDPVulnerabilities([Asset]$asset, [hashtable]$portInfo) {
        $findings = @()

        # Check for RDP accessibility
        try {
            $rdpClient = New-Object System.Net.Sockets.TcpClient
            $rdpClient.Connect($asset.IPAddress, 3389)

            if ($rdpClient.Connected) {
                $finding = $this.CreateFinding($asset, "RDP_ENABLED", "High", "RDP service is accessible", "Ensure RDP is properly secured with strong authentication and consider restricting access")
                $findings += $finding
            }

            $rdpClient.Close()
        }
        catch {
            # RDP not accessible
        }

        return $findings
    }

    # Create a finding object
    [Finding] CreateFinding([Asset]$asset, [string]$checkType, [string]$severity, [string]$description, [string]$remediation) {
        $finding = [Finding]::new()
        $finding.AssetId = $asset.AssetId
        $finding.CheckModule = $this.ModuleName
        $finding.CheckType = $checkType
        $finding.Severity = $severity
        $finding.Status = "Open"
        $finding.Title = $checkType
        $finding.Description = $description
        $finding.Remediation = $remediation
        $finding.Confidence = "High"
        $finding.DetectedAt = Get-Date
        $finding.LastVerified = Get-Date

        return $finding
    }

    # Get module information
    [hashtable] GetModuleInfo() {
        return @{
            Name = $this.ModuleName
            Type = "Scanner"
            Enabled = $this.IsEnabled
            LastScan = $this.LastScan
            Configuration = $this.Configuration
        }
    }
}

# Export the network scanner class
Export-ModuleMember -Type 'Scanner_Network'
Export-ModuleMember -Function 'Write-ScannerLog'
