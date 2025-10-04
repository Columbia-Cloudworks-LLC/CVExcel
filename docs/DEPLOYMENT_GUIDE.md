# CVExcel Deployment Guide

## Production Deployment

### System Requirements

#### Minimum Requirements
- **OS**: Windows 10 (version 1903+) or Windows Server 2016+
- **PowerShell**: 5.1 or later (PowerShell 7+ recommended)
- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 2GB free space
- **Network**: Internet connectivity with HTTPS access

#### Recommended Requirements
- **OS**: Windows 11 or Windows Server 2019+
- **PowerShell**: PowerShell 7.4+
- **RAM**: 16GB
- **Storage**: 10GB free space (SSD recommended)
- **Network**: High-speed internet connection

### Pre-Deployment Checklist

- [ ] Verify PowerShell version compatibility
- [ ] Confirm internet connectivity
- [ ] Check antivirus exclusions
- [ ] Plan for log storage
- [ ] Set up monitoring
- [ ] Configure backup strategy

## Installation Methods

### Method 1: Direct Deployment

1. **Download Project**:
   ```powershell
   # Clone from repository
   git clone <repository-url> CVExcel
   cd CVExcel
   ```

2. **Set Execution Policy**:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

3. **Install Dependencies**:
   ```powershell
   # Install required modules
   Install-Module -Name PSScriptAnalyzer -Scope AllUsers -Force
   Install-Module -Name Selenium -Scope AllUsers -Force
   ```

4. **Verify Installation**:
   ```powershell
   .\tests\run-all-tests.ps1 -TestFilter "quick"
   ```

### Method 2: Automated Installation

1. **Run Installation Script**:
   ```powershell
   .\scripts\install.ps1 -Scope AllUsers
   ```

2. **Verify Installation**:
   ```powershell
   .\scripts\verify-installation.ps1
   ```

### Method 3: MSI Package (Future)

*Note: MSI package deployment will be available in future versions*

## Configuration

### Basic Configuration

1. **Create Configuration File**:
   ```powershell
   # Copy example configuration
   Copy-Item "config\config.example.json" "config\config.json"
   ```

2. **Edit Configuration**:
   ```json
   {
     "scraping": {
       "timeout": 30,
       "retryCount": 3,
       "maxConcurrent": 5
     },
     "logging": {
       "level": "INFO",
       "maxLogSize": "10MB",
       "maxLogFiles": 10
     },
     "output": {
       "directory": "out",
       "backupEnabled": true
     }
   }
   ```

### Advanced Configuration

#### Network Configuration
```json
{
  "network": {
    "proxy": {
      "enabled": false,
      "server": "",
      "port": 0,
      "credentials": null
    },
    "timeout": 30,
    "userAgent": "CVExcel/1.0"
  }
}
```

#### Vendor-Specific Configuration
```json
{
  "vendors": {
    "microsoft": {
      "apiKey": "",
      "rateLimit": 100
    },
    "github": {
      "apiKey": "",
      "rateLimit": 5000
    }
  }
}
```

## Security Configuration

### Execution Policy
```powershell
# For production environments
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# For high-security environments
Set-ExecutionPolicy -ExecutionPolicy AllSigned -Scope LocalMachine
```

### Firewall Configuration
```powershell
# Allow PowerShell through firewall
New-NetFirewallRule -DisplayName "CVExcel PowerShell" -Direction Inbound -Program "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Action Allow
```

### Antivirus Exclusions
Add the following paths to antivirus exclusions:
- Project installation directory
- PowerShell execution paths
- Temporary directories used by the application

## Service Deployment

### Windows Service Installation

1. **Create Service Script**:
   ```powershell
   # Create service wrapper
   .\scripts\create-service.ps1 -ServiceName "CVExcel" -DisplayName "CVExcel CVE Scraper"
   ```

2. **Configure Service**:
   ```powershell
   # Set service to auto-start
   Set-Service -Name "CVExcel" -StartupType Automatic
   ```

3. **Start Service**:
   ```powershell
   Start-Service -Name "CVExcel"
   ```

### Task Scheduler Deployment

1. **Create Scheduled Task**:
   ```powershell
   .\scripts\create-scheduled-task.ps1 -TaskName "CVExcel Daily Scrape" -Schedule "Daily" -Time "02:00"
   ```

2. **Configure Task**:
   - Set appropriate user credentials
   - Configure retry options
   - Set up notifications

## Monitoring and Logging

### Log Configuration

1. **Configure Log Rotation**:
   ```json
   {
     "logging": {
       "rotation": {
         "enabled": true,
         "maxSize": "10MB",
         "maxFiles": 10,
         "compressOldFiles": true
       }
     }
   }
   ```

2. **Set Log Levels**:
   ```json
   {
     "logging": {
       "levels": {
         "console": "INFO",
         "file": "DEBUG",
         "eventLog": "WARNING"
       }
     }
   }
   ```

### Performance Monitoring

1. **Enable Performance Counters**:
   ```powershell
   # Install performance monitoring
   .\scripts\install-monitoring.ps1
   ```

2. **Configure Alerts**:
   - Set up alerts for failed scrapes
   - Monitor execution time
   - Track error rates

### Health Checks

1. **Create Health Check Script**:
   ```powershell
   .\scripts\health-check.ps1
   ```

2. **Schedule Health Checks**:
   ```powershell
   # Run health check every hour
   Register-ScheduledTask -TaskName "CVExcel Health Check" -Action (New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File .\scripts\health-check.ps1") -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1))
   ```

## Backup and Recovery

### Backup Strategy

1. **Configuration Backup**:
   ```powershell
   # Backup configuration
   .\scripts\backup-config.ps1 -Destination "\\backup-server\cvexcel\config"
   ```

2. **Data Backup**:
   ```powershell
   # Backup output data
   .\scripts\backup-data.ps1 -Destination "\\backup-server\cvexcel\data"
   ```

3. **Log Backup**:
   ```powershell
   # Backup logs
   .\scripts\backup-logs.ps1 -Destination "\\backup-server\cvexcel\logs"
   ```

### Recovery Procedures

1. **Configuration Recovery**:
   ```powershell
   # Restore configuration
   .\scripts\restore-config.ps1 -Source "\\backup-server\cvexcel\config"
   ```

2. **Data Recovery**:
   ```powershell
   # Restore data
   .\scripts\restore-data.ps1 -Source "\\backup-server\cvexcel\data"
   ```

## Scaling and Performance

### Horizontal Scaling

1. **Load Balancer Configuration**:
   - Distribute scraping load across multiple instances
   - Use session affinity for consistent results

2. **Database Integration**:
   - Store results in database for better performance
   - Implement caching mechanisms

### Vertical Scaling

1. **Resource Optimization**:
   ```json
   {
     "performance": {
       "maxConcurrentScrapes": 10,
       "memoryLimit": "2GB",
       "cpuLimit": "80%"
     }
   }
   ```

2. **Caching Configuration**:
   ```json
   {
     "caching": {
       "enabled": true,
       "ttl": 3600,
       "maxSize": "1GB"
     }
   }
   ```

## Troubleshooting

### Common Deployment Issues

1. **Execution Policy Errors**:
   ```powershell
   # Check current policy
   Get-ExecutionPolicy -List

   # Set appropriate policy
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

2. **Module Installation Issues**:
   ```powershell
   # Check module installation
   Get-Module -ListAvailable

   # Reinstall modules
   Install-Module -Name <ModuleName> -Force -AllowClobber
   ```

3. **Permission Issues**:
   ```powershell
   # Check file permissions
   Get-Acl .\CVScrape.ps1

   # Fix permissions
   icacls .\CVScrape.ps1 /grant Everyone:F
   ```

### Log Analysis

1. **Check Application Logs**:
   ```powershell
   # View recent logs
   Get-Content .\out\*.log | Select-Object -Last 100
   ```

2. **Check Event Logs**:
   ```powershell
   # Check Windows Event Log
   Get-WinEvent -LogName Application -FilterHashtable @{ID=1000} | Where-Object {$_.Message -like "*CVExcel*"}
   ```

## Maintenance

### Regular Maintenance Tasks

1. **Weekly**:
   - Review logs for errors
   - Check disk space
   - Verify backup integrity

2. **Monthly**:
   - Update dependencies
   - Review performance metrics
   - Test disaster recovery procedures

3. **Quarterly**:
   - Security updates
   - Performance optimization
   - Capacity planning review

### Update Procedures

1. **Prepare for Update**:
   ```powershell
   # Backup current installation
   .\scripts\backup-full.ps1
   ```

2. **Apply Update**:
   ```powershell
   # Stop services
   Stop-Service -Name "CVExcel" -Force

   # Apply update
   .\scripts\apply-update.ps1 -UpdatePackage "cvexcel-update.zip"

   # Restart services
   Start-Service -Name "CVExcel"
   ```

3. **Verify Update**:
   ```powershell
   # Run verification tests
   .\tests\run-all-tests.ps1
   ```

## Support and Documentation

### Support Channels
- GitHub Issues for bug reports
- Documentation in the `docs` directory
- Community forums for questions

### Documentation Updates
- Keep deployment documentation current
- Update configuration examples
- Maintain troubleshooting guides
