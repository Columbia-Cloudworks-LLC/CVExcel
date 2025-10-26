# Inventory_Windows.ps1 - Windows Server inventory and asset discovery module
# Discovers and enumerates Windows servers, their roles, features, and configuration

# Import common modules
. "$PSScriptRoot/../common/ModuleLoader.ps1"
. "$PSScriptRoot/../common/DataSchemas.ps1"

# Common logging function for inventory modules
function Write-InventoryLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$ModuleName = "Inventory_Windows"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [Inventory:$ModuleName] $Message"

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

class Inventory_Windows {
    [string]$ModuleName
    [hashtable]$Configuration
    [datetime]$LastScan
    [bool]$IsEnabled

    Inventory_Windows() {
        $this.ModuleName = "Inventory_Windows"
        $this.IsEnabled = $true
        $this.LastScan = Get-Date
        $this.Configuration = @{
            ScanLocalMachine = $true
            ScanRemoteMachines = $false
            RemoteCredentials = $null
            ScanTimeout = 300
            IncludeServices = $true
            IncludeFeatures = $true
            IncludePatches = $true
            IncludeRegistry = $false
            MaxConcurrentScans = 5
        }
    }

    # Main inventory method
    [Asset[]] DiscoverAssets([string[]]$targetHosts = @()) {
        Write-InventoryLog "Starting Windows asset discovery" -Level "INFO"

        $assets = @()

        try {
            # Scan local machine if enabled
            if ($this.Configuration.ScanLocalMachine) {
                Write-InventoryLog "Scanning local machine" -Level "INFO"
                $localAsset = $this.ScanLocalMachine()
                if ($localAsset) {
                    $assets += $localAsset
                }
            }

            # Scan remote machines if specified
            if ($targetHosts.Count -gt 0 -and $this.Configuration.ScanRemoteMachines) {
                Write-InventoryLog "Scanning $($targetHosts.Count) remote machines" -Level "INFO"
                $remoteAssets = $this.ScanRemoteMachines($targetHosts)
                $assets += $remoteAssets
            }

            Write-InventoryLog "Asset discovery completed. Found $($assets.Count) assets" -Level "SUCCESS"
            return $assets
        }
        catch {
            Write-InventoryLog "Asset discovery failed: $($_.Exception.Message)" -Level "ERROR"
            return $assets
        }
    }

    # Scan the local machine
    [Asset] ScanLocalMachine() {
        try {
            Write-InventoryLog "Scanning local machine: $env:COMPUTERNAME" -Level "DEBUG"

            $asset = [Asset]::new()
            $asset.Hostname = $env:COMPUTERNAME
            $asset.IPAddress = $this.GetLocalIPAddress()
            $asset.Domain = $this.GetDomainInfo()
            $asset.OSVersion = $this.GetOSVersion()
            $asset.OSBuild = $this.GetOSBuild()
            $asset.Architecture = $this.GetArchitecture()
            $asset.LastBootTime = $this.GetLastBootTime()
            $asset.LastScanTime = Get-Date

            # Get roles and features
            if ($this.Configuration.IncludeFeatures) {
                $asset.Roles = $this.GetServerRoles()
                $asset.Features = $this.GetServerFeatures()
            }

            # Get domain role
            $asset.DomainRole = $this.GetDomainRole()

            # Get business criticality (default to Medium)
            $asset.BusinessCriticality = "Medium"

            # Get environment (default to Production)
            $asset.Environment = "Production"

            # Check if internet facing (basic check)
            $asset.InternetFacing = $this.IsInternetFacing($asset.IPAddress)

            Write-InventoryLog "Local machine scan completed for $($asset.Hostname)" -Level "SUCCESS"
            return $asset
        }
        catch {
            Write-InventoryLog "Local machine scan failed: $($_.Exception.Message)" -Level "ERROR"
            return $null
        }
    }

    # Scan remote machines
    [Asset[]] ScanRemoteMachines([string[]]$hostnames) {
        $assets = @()
        $jobs = @()

        foreach ($hostname in $hostnames) {
            $job = Start-Job -ScriptBlock {
                param($hostname, $config)

                # Import required modules in job context
                . "$PSScriptRoot/../common/DataSchemas.ps1"

                try {
                    # Test connectivity
                    if (-not (Test-Connection -ComputerName $hostname -Count 1 -Quiet)) {
                        return $null
                    }

                    $asset = [Asset]::new()
                    $asset.Hostname = $hostname
                    $asset.LastScanTime = Get-Date

                    # Get basic system info via WMI
                    try {
                        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $hostname -ErrorAction Stop
                        $asset.Domain = $computerSystem.Domain
                        $asset.Architecture = $computerSystem.SystemType
                    }
                    catch {
                        # Continue with limited info
                    }

                    # Get OS info via WMI
                    try {
                        $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $hostname -ErrorAction Stop
                        $asset.OSVersion = $operatingSystem.Caption
                        $asset.OSBuild = $operatingSystem.BuildNumber
                        $asset.LastBootTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($operatingSystem.LastBootUpTime)
                    }
                    catch {
                        # Continue with limited info
                    }

                    # Get network info
                    try {
                        $networkAdapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $hostname -Filter "IPEnabled=True" -ErrorAction Stop
                        $ipAddresses = @()
                        foreach ($adapter in $networkAdapters) {
                            if ($adapter.IPAddress) {
                                $ipAddresses += $adapter.IPAddress
                            }
                        }
                        if ($ipAddresses.Count -gt 0) {
                            $asset.IPAddress = $ipAddresses[0]  # Primary IP
                        }
                    }
                    catch {
                        # Continue without IP info
                    }

                    return $asset
                }
                catch {
                    return $null
                }
            } -ArgumentList $hostname, $this.Configuration

            $jobs += $job
        }

        # Wait for jobs to complete
        $jobs | Wait-Job -Timeout $this.Configuration.ScanTimeout

        # Collect results
        foreach ($job in $jobs) {
            if ($job.State -eq "Completed") {
                $result = Receive-Job -Job $job
                if ($result) {
                    $assets += $result
                }
            }
            else {
                Write-InventoryLog "Job failed or timed out for job $($job.Id)" -Level "WARNING"
            }
            Remove-Job -Job $job
        }

        Write-InventoryLog "Remote machine scanning completed. Found $($assets.Count) assets" -Level "SUCCESS"
        return $assets
    }

    # Get local IP address
    [string] GetLocalIPAddress() {
        try {
            $networkAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" }
            $primaryAdapter = $networkAdapters | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
            return $primaryAdapter.IPAddress
        }
        catch {
            return "Unknown"
        }
    }

    # Get domain information
    [string] GetDomainInfo() {
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
            return $computerSystem.Domain
        }
        catch {
            return "WORKGROUP"
        }
    }

    # Get OS version
    [string] GetOSVersion() {
        try {
            $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem
            return $operatingSystem.Caption
        }
        catch {
            return "Unknown"
        }
    }

    # Get OS build number
    [string] GetOSBuild() {
        try {
            $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem
            return $operatingSystem.BuildNumber
        }
        catch {
            return "Unknown"
        }
    }

    # Get system architecture
    [string] GetArchitecture() {
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
            return $computerSystem.SystemType
        }
        catch {
            return "Unknown"
        }
    }

    # Get last boot time
    [datetime] GetLastBootTime() {
        try {
            $operatingSystem = Get-WmiObject -Class Win32_OperatingSystem
            return [System.Management.ManagementDateTimeConverter]::ToDateTime($operatingSystem.LastBootUpTime)
        }
        catch {
            return Get-Date
        }
    }

    # Get server roles
    [string[]] GetServerRoles() {
        try {
            $roles = @()

            # Check for common server roles
            if (Get-WindowsFeature -Name "AD-Domain-Services" -ErrorAction SilentlyContinue | Where-Object { $_.InstallState -eq "Installed" }) {
                $roles += "Domain Controller"
            }

            if (Get-WindowsFeature -Name "DNS" -ErrorAction SilentlyContinue | Where-Object { $_.InstallState -eq "Installed" }) {
                $roles += "DNS Server"
            }

            if (Get-WindowsFeature -Name "DHCP" -ErrorAction SilentlyContinue | Where-Object { $_.InstallState -eq "Installed" }) {
                $roles += "DHCP Server"
            }

            if (Get-WindowsFeature -Name "FileAndStorage-Services" -ErrorAction SilentlyContinue | Where-Object { $_.InstallState -eq "Installed" }) {
                $roles += "File Server"
            }

            if (Get-WindowsFeature -Name "Web-Server" -ErrorAction SilentlyContinue | Where-Object { $_.InstallState -eq "Installed" }) {
                $roles += "Web Server"
            }

            if (Get-WindowsFeature -Name "Print-Services" -ErrorAction SilentlyContinue | Where-Object { $_.InstallState -eq "Installed" }) {
                $roles += "Print Server"
            }

            return $roles
        }
        catch {
            return @()
        }
    }

    # Get server features
    [string[]] GetServerFeatures() {
        try {
            $features = @()

            # Get installed features
            $installedFeatures = Get-WindowsFeature | Where-Object { $_.InstallState -eq "Installed" }

            foreach ($feature in $installedFeatures) {
                if ($feature.Name -notlike "*Role*") {  # Exclude roles, only include features
                    $features += $feature.Name
                }
            }

            return $features
        }
        catch {
            return @()
        }
    }

    # Get domain role
    [string] GetDomainRole() {
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem

            switch ($computerSystem.DomainRole) {
                0 { return "Standalone Workstation" }
                1 { return "Member Workstation" }
                2 { return "Standalone Server" }
                3 { return "Member Server" }
                4 { return "Backup Domain Controller" }
                5 { return "Primary Domain Controller" }
                default { return "Unknown" }
            }
        }
        catch {
            return "Unknown"
        }
    }

    # Check if machine is internet facing
    [bool] IsInternetFacing([string]$ipAddress) {
        try {
            # Simple check - if IP is not in private ranges
            $privateRanges = @(
                "10.0.0.0/8",
                "172.16.0.0/12",
                "192.168.0.0/16",
                "127.0.0.0/8",
                "169.254.0.0/16"
            )

            # Basic check - this is simplified
            if ($ipAddress -match '^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.|^192\.168\.|^127\.|^169\.254\.') {
                return $false
            }

            return $true
        }
        catch {
            return $false
        }
    }

    # Get module information
    [hashtable] GetModuleInfo() {
        return @{
            Name = $this.ModuleName
            Type = "Inventory"
            Enabled = $this.IsEnabled
            LastScan = $this.LastScan
            Configuration = $this.Configuration
        }
    }
}

# Export the Windows inventory class
Export-ModuleMember -Type 'Inventory_Windows'
Export-ModuleMember -Function 'Write-InventoryLog'
