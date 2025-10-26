# CVExcel Core Engine - Getting Started Guide

## Quick Start

Welcome to CVExcel Core Engine! This guide will help you get up and running with the modular vulnerability scanner in just a few minutes.

### Prerequisites

- **Windows Server 2016+** or **Windows 10+**
- **PowerShell 5.1+** (PowerShell Core 6+ recommended)
- **Administrative privileges** (for local scanning)
- **Internet connectivity** (for vulnerability data feeds)

### Installation

1. **Clone or download** the CVExcel repository
2. **Navigate** to the CVExcel directory
3. **Verify** the core engine structure exists:
   ```
   CVExcel/
   ├── core-engine/
   │   ├── feeds/
   │   ├── inventory/
   │   ├── scanners/
   │   ├── assessments/
   │   ├── output/
   │   ├── common/
   │   └── cli/
   ├── config.json
   └── CVExcel-CoreEngine.ps1
   ```

### First Run

1. **Open PowerShell** as Administrator
2. **Navigate** to the CVExcel directory
3. **Run** the core engine:
   ```powershell
   .\CVExcel-CoreEngine.ps1
   ```

You should see output similar to:
```
CVExcel Core Engine - Modular Vulnerability Scanner
==================================================
Version: 1.0.0

Configuration loaded from: config.json
Module loader initialized successfully
Loaded modules: 8 total

System Status:
==============

Configuration:
  Version: 1.0.0
  Database: SQLite
  API Enabled: True
  Logging Level: INFO

Module Statistics:
  Total Modules: 8
  Successful Loads: 8
  Failed Loads: 0

Module Breakdown:
  Feeds: 2 modules
  Inventory: 2 modules
  Scanners: 1 modules
  Assessments: 1 modules
  Output: 2 modules
```

## Basic Operations

### 1. Asset Discovery

Discover Windows servers and Active Directory assets:

```powershell
.\CVExcel-CoreEngine.ps1 -Action inventory
```

This will:
- Scan the local machine for Windows roles and features
- Discover Active Directory domain controllers and computers
- Create asset records in the database

### 2. Vulnerability Scanning

Scan discovered assets for vulnerabilities:

```powershell
.\CVExcel-CoreEngine.ps1 -Action scan
```

Or scan specific targets:

```powershell
.\CVExcel-CoreEngine.ps1 -Action scan -Targets @("192.168.1.1", "server1.domain.com")
```

This will:
- Perform network port scans
- Check for missing security patches
- Analyze configuration security
- Generate vulnerability findings

### 3. Risk Assessment

Calculate risk scores and priorities:

```powershell
.\CVExcel-CoreEngine.ps1 -Action assess
```

This will:
- Analyze vulnerability findings
- Calculate risk scores based on multiple factors
- Prioritize findings by risk level
- Generate risk assessment results

### 4. Report Generation

Generate comprehensive reports:

```powershell
.\CVExcel-CoreEngine.ps1 -Action report
```

This will:
- Create executive summary reports
- Generate technical vulnerability reports
- Export data to CSV/Excel formats
- Save reports to the output directory

### 5. Graphical Interface

Launch the GUI for interactive use:

```powershell
.\CVExcel-CoreEngine.ps1 -Action gui
```

## Configuration

### Basic Configuration

Edit `config.json` to customize the engine:

```json
{
  "version": "1.0.0",
  "name": "CVExcel Core Engine",

  "modules": {
    "feeds": [
      "Feed_Microsoft",
      "Feed_GitHub"
    ],
    "inventory": [
      "Inventory_Windows",
      "Inventory_AD"
    ],
    "scanners": [
      "Scanner_Network",
      "Scanner_Windows_Patches"
    ]
  },

  "scanning": {
    "defaultTimeout": 300,
    "maxConcurrentScans": 10,
    "retryAttempts": 3
  }
}
```

### Advanced Configuration

#### Database Settings
```json
{
  "database": {
    "type": "SQLite",
    "connectionString": "Data Source=core-engine/data/vulnscan.db;Version=3;",
    "backupEnabled": true,
    "backupRetentionDays": 30
  }
}
```

#### Risk Scoring
```json
{
  "riskScoring": {
    "enabled": true,
    "algorithm": "weighted",
    "weights": {
      "exploitability": 0.4,
      "exposure": 0.3,
      "assetCriticality": 0.2,
      "patchAvailability": 0.1
    }
  }
}
```

#### API Settings
```json
{
  "api": {
    "enabled": true,
    "port": 8080,
    "authentication": {
      "enabled": true,
      "type": "bearer"
    }
  }
}
```

## Common Use Cases

### 1. Local Machine Assessment

Assess the security posture of the local machine:

```powershell
# Discover local assets
.\CVExcel-CoreEngine.ps1 -Action inventory

# Scan for vulnerabilities
.\CVExcel-CoreEngine.ps1 -Action scan

# Calculate risk scores
.\CVExcel-CoreEngine.ps1 -Action assess

# Generate report
.\CVExcel-CoreEngine.ps1 -Action report
```

### 2. Network Segment Scanning

Scan a specific network segment:

```powershell
# Define target range
$targets = @("192.168.1.1", "192.168.1.2", "192.168.1.3")

# Scan targets
.\CVExcel-CoreEngine.ps1 -Action scan -Targets $targets

# Assess risks
.\CVExcel-CoreEngine.ps1 -Action assess

# Generate report
.\CVExcel-CoreEngine.ps1 -Action report
```

### 3. Active Directory Assessment

Comprehensive AD environment assessment:

```powershell
# Discover AD assets
.\CVExcel-CoreEngine.ps1 -Action inventory

# Scan domain controllers
.\CVExcel-CoreEngine.ps1 -Action scan -Targets @("dc1.domain.com", "dc2.domain.com")

# Assess domain-wide risks
.\CVExcel-CoreEngine.ps1 -Action assess

# Generate executive report
.\CVExcel-CoreEngine.ps1 -Action report
```

### 4. Continuous Monitoring

Set up automated scanning:

```powershell
# Create scheduled task for daily scans
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\CVExcel\CVExcel-CoreEngine.ps1 -Action scan"
$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName "CVExcel Daily Scan"
```

## Troubleshooting

### Common Issues

#### 1. Module Loading Errors
**Problem**: Modules fail to load
**Solution**:
- Check PowerShell execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- Verify module files exist in correct directories
- Check configuration file syntax

#### 2. Permission Errors
**Problem**: Access denied errors during scanning
**Solution**:
- Run PowerShell as Administrator
- Check Windows Firewall settings
- Verify network connectivity

#### 3. Database Errors
**Problem**: Database connection failures
**Solution**:
- Check database file permissions
- Verify connection string in config.json
- Ensure SQLite is available

#### 4. Network Scanning Issues
**Problem**: Network scans fail or timeout
**Solution**:
- Check network connectivity
- Verify target hosts are reachable
- Adjust timeout settings in configuration

### Debug Mode

Enable verbose logging for troubleshooting:

```powershell
.\CVExcel-CoreEngine.ps1 -Action scan -Verbose
```

### Log Files

Check log files for detailed error information:
- **Location**: `core-engine/logs/vulnscan.log`
- **Rotation**: Automatic log rotation (100MB max, 10 files)
- **Levels**: DEBUG, INFO, WARNING, ERROR

## Next Steps

### 1. Explore Advanced Features
- Custom vulnerability feeds
- Advanced risk scoring algorithms
- Integration with SIEM systems
- Automated remediation workflows

### 2. Extend the Platform
- Develop custom modules
- Integrate with existing tools
- Create custom reports
- Build API integrations

### 3. Production Deployment
- Set up centralized scanning
- Configure automated reporting
- Implement monitoring and alerting
- Establish maintenance procedures

### 4. Security Hardening
- Review and customize security settings
- Implement proper authentication
- Configure network segmentation
- Set up audit logging

## Support and Resources

### Documentation
- **Architecture Guide**: `docs/Architecture.md`
- **Module Development**: `docs/ModuleDevelopment.md`
- **API Reference**: `docs/API_REFERENCE.md`

### Community
- **GitHub Issues**: Report bugs and request features
- **Discussions**: Community support and discussions
- **Contributing**: Guidelines for contributing to the project

### Professional Support
For enterprise deployments and professional support:
- **Consulting Services**: Custom implementation and integration
- **Training Programs**: Team training and certification
- **Support Contracts**: Priority support and maintenance

## Conclusion

You're now ready to start using CVExcel Core Engine! The modular architecture makes it easy to customize and extend the platform for your specific needs. Start with basic operations and gradually explore more advanced features as you become familiar with the system.

For additional help, refer to the comprehensive documentation or reach out to the community for support.
