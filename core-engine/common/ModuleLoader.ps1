# ModuleLoader.ps1 - Dynamic module discovery and loading system
# This module provides a unified interface for loading all core engine modules

[CmdletBinding()]
param(
    [string]$ConfigPath = "config.json",
    [switch]$Verbose
)

# Global module registry
$Global:ModuleRegistry = @{
    Feeds       = @{}
    Inventory   = @{}
    Scanners    = @{}
    Assessments = @{}
    Output      = @{}
    Common      = @{}
}

# Configuration cache
$Global:EngineConfig = $null

# Common logging function
function Write-EngineLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Module = "ModuleLoader"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$Module] $Message"

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

# Load configuration
function Get-EngineConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = "config.json"
    )

    if ($Global:EngineConfig) {
        return $Global:EngineConfig
    }

    try {
        if (-not (Test-Path $ConfigPath)) {
            Write-EngineLog "Configuration file not found: $ConfigPath" -Level "ERROR"
            throw "Configuration file not found: $ConfigPath"
        }

        $configContent = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $Global:EngineConfig = $configContent | ConvertFrom-Json

        Write-EngineLog "Configuration loaded successfully from $ConfigPath" -Level "SUCCESS"
        return $Global:EngineConfig
    } catch {
        Write-EngineLog "Failed to load configuration: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Discover modules in a directory
function Find-Modules {
    [CmdletBinding()]
    param(
        [string]$Directory,
        [string]$Pattern = "*.ps1"
    )

    if (-not (Test-Path $Directory)) {
        Write-EngineLog "Directory not found: $Directory" -Level "WARNING"
        return @()
    }

    $modules = Get-ChildItem -Path $Directory -Filter $Pattern -File |
    Where-Object { $_.Name -notlike "*Test*" -and $_.Name -notlike "*Example*" }

    Write-EngineLog "Found $($modules.Count) modules in $Directory" -Level "DEBUG"
    return $modules
}

# Load a single module
function Import-ModuleFile {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string]$ModuleType
    )

    try {
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        Write-EngineLog "Loading module: $moduleName ($ModuleType)" -Level "DEBUG"

        # Dot-source the module
        . $FilePath

        # Register the module
        if (-not $Global:ModuleRegistry[$ModuleType].ContainsKey($moduleName)) {
            $Global:ModuleRegistry[$ModuleType][$moduleName] = @{
                FilePath = $FilePath
                LoadedAt = Get-Date
                Status   = "Loaded"
            }
            Write-EngineLog "Module registered: $moduleName" -Level "SUCCESS"
        }

        return $true
    } catch {
        Write-EngineLog "Failed to load module $FilePath`: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Load all modules of a specific type
function Load-ModuleType {
    [CmdletBinding()]
    param(
        [string]$ModuleType,
        [string]$Directory,
        [string[]]$EnabledModules
    )

    Write-EngineLog "Loading $ModuleType modules from $Directory" -Level "INFO"

    $modules = Find-Modules -Directory $Directory
    $loadedCount = 0

    foreach ($module in $modules) {
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($module.Name)

        # Check if module is enabled in configuration
        if ($EnabledModules -and $EnabledModules.Count -gt 0) {
            if ($EnabledModules -notcontains $moduleName) {
                Write-EngineLog "Skipping disabled module: $moduleName" -Level "DEBUG"
                continue
            }
        }

        if (Import-ModuleFile -FilePath $module.FullName -ModuleType $ModuleType) {
            $loadedCount++
        }
    }

    Write-EngineLog "Loaded $loadedCount of $($modules.Count) $ModuleType modules" -Level "SUCCESS"
    return $loadedCount
}

# Initialize the module loader
function Initialize-ModuleLoader {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = "config.json"
    )

    Write-EngineLog "Initializing CVExcel Core Engine Module Loader" -Level "INFO"

    try {
        # Load configuration
        $config = Get-EngineConfig -ConfigPath $ConfigPath

        # Initialize module registry
        $Global:ModuleRegistry = @{
            Feeds       = @{}
            Inventory   = @{}
            Scanners    = @{}
            Assessments = @{}
            Output      = @{}
            Common      = @{}
        }

        # Load common modules first (dependencies)
        $commonDir = "core-engine/common"
        if (Test-Path $commonDir) {
            Load-ModuleType -ModuleType "Common" -Directory $commonDir
        }

        # Load feed modules
        $feedsDir = "core-engine/feeds"
        if (Test-Path $feedsDir) {
            Load-ModuleType -ModuleType "Feeds" -Directory $feedsDir -EnabledModules $config.modules.feeds
        }

        # Load inventory modules
        $inventoryDir = "core-engine/inventory"
        if (Test-Path $inventoryDir) {
            Load-ModuleType -ModuleType "Inventory" -Directory $inventoryDir -EnabledModules $config.modules.inventory
        }

        # Load scanner modules
        $scannersDir = "core-engine/scanners"
        if (Test-Path $scannersDir) {
            Load-ModuleType -ModuleType "Scanners" -Directory $scannersDir -EnabledModules $config.modules.scanners
        }

        # Load assessment modules
        $assessmentsDir = "core-engine/assessments"
        if (Test-Path $assessmentsDir) {
            Load-ModuleType -ModuleType "Assessments" -Directory $assessmentsDir -EnabledModules $config.modules.assessments
        }

        # Load output modules
        $outputDir = "core-engine/output"
        if (Test-Path $outputDir) {
            Load-ModuleType -ModuleType "Output" -Directory $outputDir -EnabledModules $config.modules.output
        }

        Write-EngineLog "Module loader initialization completed" -Level "SUCCESS"
        return $true
    } catch {
        Write-EngineLog "Module loader initialization failed: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Get loaded modules by type
function Get-LoadedModules {
    [CmdletBinding()]
    param(
        [string]$ModuleType = "*"
    )

    if ($ModuleType -eq "*") {
        return $Global:ModuleRegistry
    }

    if ($Global:ModuleRegistry.ContainsKey($ModuleType)) {
        return $Global:ModuleRegistry[$ModuleType]
    }

    return @{}
}

# Get module statistics
function Get-ModuleStats {
    [CmdletBinding()]
    param()

    $stats = @{
        TotalModules = 0
        ModuleTypes  = @{}
        LoadStatus   = @{
            Success = 0
            Failed  = 0
        }
    }

    foreach ($moduleType in $Global:ModuleRegistry.Keys) {
        $moduleCount = $Global:ModuleRegistry[$moduleType].Count
        $stats.ModuleTypes[$moduleType] = $moduleCount
        $stats.TotalModules += $moduleCount

        foreach ($module in $Global:ModuleRegistry[$moduleType].Values) {
            if ($module.Status -eq "Loaded") {
                $stats.LoadStatus.Success++
            } else {
                $stats.LoadStatus.Failed++
            }
        }
    }

    return $stats
}

# Reload a specific module
function Reload-Module {
    [CmdletBinding()]
    param(
        [string]$ModuleName,
        [string]$ModuleType
    )

    if (-not $Global:ModuleRegistry.ContainsKey($ModuleType)) {
        Write-EngineLog "Unknown module type: $ModuleType" -Level "ERROR"
        return $false
    }

    if (-not $Global:ModuleRegistry[$ModuleType].ContainsKey($ModuleName)) {
        Write-EngineLog "Module not found: $ModuleName ($ModuleType)" -Level "ERROR"
        return $false
    }

    $moduleInfo = $Global:ModuleRegistry[$ModuleType][$ModuleName]

    try {
        Write-EngineLog "Reloading module: $ModuleName" -Level "INFO"
        . $moduleInfo.FilePath

        $Global:ModuleRegistry[$ModuleType][$ModuleName].LoadedAt = Get-Date
        $Global:ModuleRegistry[$ModuleType][$ModuleName].Status = "Loaded"

        Write-EngineLog "Module reloaded successfully: $ModuleName" -Level "SUCCESS"
        return $true
    } catch {
        Write-EngineLog "Failed to reload module $ModuleName`: $($_.Exception.Message)" -Level "ERROR"
        $Global:ModuleRegistry[$ModuleType][$ModuleName].Status = "Failed"
        return $false
    }
}

# Export functions for use by other modules
Export-ModuleMember -Function @(
    'Initialize-ModuleLoader',
    'Get-LoadedModules',
    'Get-ModuleStats',
    'Reload-Module',
    'Get-EngineConfig',
    'Write-EngineLog'
)

Write-EngineLog "ModuleLoader.ps1 loaded successfully" -Level "SUCCESS"
