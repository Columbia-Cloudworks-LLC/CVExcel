# Inventory_AD.ps1 - Active Directory inventory and domain enumeration module
# Discovers domain controllers, trusts, and domain-wide assets

# Import common modules
. "$PSScriptRoot/../common/ModuleLoader.ps1"
. "$PSScriptRoot/../common/DataSchemas.ps1"

# Common logging function for AD inventory
function Write-ADLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$ModuleName = "Inventory_AD"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [AD-Inventory:$ModuleName] $Message"

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

class Inventory_AD {
    [string]$ModuleName
    [hashtable]$Configuration
    [datetime]$LastScan
    [bool]$IsEnabled
    [string]$DomainName

    Inventory_AD() {
        $this.ModuleName = "Inventory_AD"
        $this.IsEnabled = $true
        $this.LastScan = Get-Date
        $this.DomainName = $this.GetCurrentDomain()
        $this.Configuration = @{
            ScanDomainControllers = $true
            ScanDomainComputers = $true
            ScanTrusts = $true
            ScanSites = $true
            ScanOUs = $true
            ScanTimeout = 600
            MaxConcurrentScans = 10
            IncludeComputerDetails = $true
            IncludeUserAccounts = $false
            IncludeGroups = $false
        }
    }

    # Main AD discovery method
    [Asset[]] DiscoverDomainAssets() {
        Write-ADLog "Starting Active Directory asset discovery for domain: $($this.DomainName)" -Level "INFO"

        $assets = @()

        try {
            # Discover domain controllers
            if ($this.Configuration.ScanDomainControllers) {
                Write-ADLog "Discovering domain controllers" -Level "INFO"
                $dcAssets = $this.DiscoverDomainControllers()
                $assets += $dcAssets
            }

            # Discover domain computers
            if ($this.Configuration.ScanDomainComputers) {
                Write-ADLog "Discovering domain computers" -Level "INFO"
                $computerAssets = $this.DiscoverDomainComputers()
                $assets += $computerAssets
            }

            Write-ADLog "AD asset discovery completed. Found $($assets.Count) assets" -Level "SUCCESS"
            return $assets
        }
        catch {
            Write-ADLog "AD asset discovery failed: $($_.Exception.Message)" -Level "ERROR"
            return $assets
        }
    }

    # Discover domain controllers
    [Asset[]] DiscoverDomainControllers() {
        $dcAssets = @()

        try {
            # Get domain controllers using AD module
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue

                $domainControllers = Get-ADDomainController -Filter * -Properties *

                foreach ($dc in $domainControllers) {
                    $asset = [Asset]::new()
                    $asset.Hostname = $dc.HostName
                    $asset.IPAddress = $dc.IPv4Address
                    $asset.Domain = $this.DomainName
                    $asset.DomainRole = "Domain Controller"
                    $asset.Roles = @("Domain Controller")
                    $asset.BusinessCriticality = "Critical"
                    $asset.Environment = "Production"
                    $asset.LastScanTime = Get-Date
                    $asset.Notes = "DC Site: $($dc.Site), FSMO Roles: $($dc.OperationMasterRoles -join ', ')"

                    # Get additional DC information
                    $asset.CustomAttributes = @{
                        Site = $dc.Site
                        FSMO = $dc.OperationMasterRoles
                        IsGlobalCatalog = $dc.IsGlobalCatalog
                        IsReadOnly = $dc.IsReadOnly
                    }

                    $dcAssets += $asset
                    Write-ADLog "Discovered DC: $($asset.Hostname)" -Level "SUCCESS"
                }
            }
            else {
                Write-ADLog "Active Directory module not available, using alternative method" -Level "WARNING"

                # Alternative method using nltest or net commands
                $dcs = $this.GetDomainControllersAlternative()
                foreach ($dc in $dcs) {
                    $asset = [Asset]::new()
                    $asset.Hostname = $dc.Hostname
                    $asset.IPAddress = $dc.IPAddress
                    $asset.Domain = $this.DomainName
                    $asset.DomainRole = "Domain Controller"
                    $asset.Roles = @("Domain Controller")
                    $asset.BusinessCriticality = "Critical"
                    $asset.Environment = "Production"
                    $asset.LastScanTime = Get-Date

                    $dcAssets += $asset
                    Write-ADLog "Discovered DC (alternative): $($asset.Hostname)" -Level "SUCCESS"
                }
            }
        }
        catch {
            Write-ADLog "Domain controller discovery failed: $($_.Exception.Message)" -Level "ERROR"
        }

        return $dcAssets
    }

    # Discover domain computers
    [Asset[]] DiscoverDomainComputers() {
        $computerAssets = @()

        try {
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue

                # Get computer accounts
                $computers = Get-ADComputer -Filter * -Properties *

                foreach ($computer in $computers) {
                    $asset = [Asset]::new()
                    $asset.Hostname = $computer.Name
                    $asset.Domain = $this.DomainName
                    $asset.DomainRole = "Member Server"
                    $asset.BusinessCriticality = "Medium"
                    $asset.Environment = "Production"
                    $asset.LastScanTime = Get-Date
                    $asset.Notes = "OU: $($computer.CanonicalName)"

                    # Get additional computer information
                    if ($this.Configuration.IncludeComputerDetails) {
                        $asset.CustomAttributes = @{
                            DistinguishedName = $computer.DistinguishedName
                            OU = $computer.CanonicalName
                            LastLogon = $computer.LastLogonDate
                            Created = $computer.Created
                            Enabled = $computer.Enabled
                            OperatingSystem = $computer.OperatingSystem
                            OperatingSystemVersion = $computer.OperatingSystemVersion
                        }
                    }

                    $computerAssets += $asset
                }

                Write-ADLog "Discovered $($computerAssets.Count) domain computers" -Level "SUCCESS"
            }
            else {
                Write-ADLog "Active Directory module not available for computer discovery" -Level "WARNING"
            }
        }
        catch {
            Write-ADLog "Domain computer discovery failed: $($_.Exception.Message)" -Level "ERROR"
        }

        return $computerAssets
    }

    # Get current domain name
    [string] GetCurrentDomain() {
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem
            return $computerSystem.Domain
        }
        catch {
            return "Unknown"
        }
    }

    # Alternative method to get domain controllers
    [hashtable[]] GetDomainControllersAlternative() {
        $dcs = @()

        try {
            # Use nltest command if available
            $nltestResult = & nltest /dclist:$($this.DomainName) 2>$null

            if ($nltestResult) {
                foreach ($line in $nltestResult) {
                    if ($line -match '\\\\\\([^\\s]+)') {
                        $dcName = $matches[1]

                        # Try to resolve IP
                        $ipAddress = $null
                        try {
                            $ipAddress = [System.Net.Dns]::GetHostAddresses($dcName)[0].IPAddressToString
                        }
                        catch {
                            $ipAddress = "Unknown"
                        }

                        $dcs += @{
                            Hostname = $dcName
                            IPAddress = $ipAddress
                        }
                    }
                }
            }
        }
        catch {
            Write-ADLog "Alternative DC discovery failed: $($_.Exception.Message)" -Level "WARNING"
        }

        return $dcs
    }

    # Get domain trust information
    [hashtable[]] GetDomainTrusts() {
        $trusts = @()

        try {
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue

                $domainTrusts = Get-ADTrust -Filter *

                foreach ($trust in $domainTrusts) {
                    $trusts += @{
                        Name = $trust.Name
                        Type = $trust.TrustType
                        Direction = $trust.TrustDirection
                        Transitive = $trust.Transitive
                    }
                }
            }
        }
        catch {
            Write-ADLog "Trust discovery failed: $($_.Exception.Message)" -Level "WARNING"
        }

        return $trusts
    }

    # Get AD sites information
    [hashtable[]] GetADSites() {
        $sites = @()

        try {
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue

                $adSites = Get-ADReplicationSite -Filter *

                foreach ($site in $adSites) {
                    $sites += @{
                        Name = $site.Name
                        DistinguishedName = $site.DistinguishedName
                        Description = $site.Description
                    }
                }
            }
        }
        catch {
            Write-ADLog "Site discovery failed: $($_.Exception.Message)" -Level "WARNING"
        }

        return $sites
    }

    # Get organizational units
    [hashtable[]] GetOrganizationalUnits() {
        $ous = @()

        try {
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue

                $adOUs = Get-ADOrganizationalUnit -Filter *

                foreach ($ou in $adOUs) {
                    $ous += @{
                        Name = $ou.Name
                        DistinguishedName = $ou.DistinguishedName
                        Description = $ou.Description
                        ProtectedFromAccidentalDeletion = $ou.ProtectedFromAccidentalDeletion
                    }
                }
            }
        }
        catch {
            Write-ADLog "OU discovery failed: $($_.Exception.Message)" -Level "WARNING"
        }

        return $ous
    }

    # Get domain information summary
    [hashtable] GetDomainSummary() {
        $summary = @{
            DomainName = $this.DomainName
            DomainControllers = @()
            Trusts = @()
            Sites = @()
            OrganizationalUnits = @()
            ComputerCount = 0
            UserCount = 0
            GroupCount = 0
        }

        try {
            # Get domain controllers
            $summary.DomainControllers = $this.DiscoverDomainControllers()

            # Get trusts
            if ($this.Configuration.ScanTrusts) {
                $summary.Trusts = $this.GetDomainTrusts()
            }

            # Get sites
            if ($this.Configuration.ScanSites) {
                $summary.Sites = $this.GetADSites()
            }

            # Get OUs
            if ($this.Configuration.ScanOUs) {
                $summary.OrganizationalUnits = $this.GetOrganizationalUnits()
            }

            # Get counts
            if (Get-Module -ListAvailable -Name ActiveDirectory) {
                Import-Module ActiveDirectory -ErrorAction SilentlyContinue

                $summary.ComputerCount = (Get-ADComputer -Filter *).Count

                if ($this.Configuration.IncludeUserAccounts) {
                    $summary.UserCount = (Get-ADUser -Filter *).Count
                }

                if ($this.Configuration.IncludeGroups) {
                    $summary.GroupCount = (Get-ADGroup -Filter *).Count
                }
            }
        }
        catch {
            Write-ADLog "Domain summary generation failed: $($_.Exception.Message)" -Level "ERROR"
        }

        return $summary
    }

    # Get module information
    [hashtable] GetModuleInfo() {
        return @{
            Name = $this.ModuleName
            Type = "Inventory"
            Enabled = $this.IsEnabled
            LastScan = $this.LastScan
            DomainName = $this.DomainName
            Configuration = $this.Configuration
        }
    }
}

# Export the AD inventory class
Export-ModuleMember -Type 'Inventory_AD'
Export-ModuleMember -Function 'Write-ADLog'
