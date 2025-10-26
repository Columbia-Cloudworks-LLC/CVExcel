# Cursor Chat Integration Script
# Allows Cursor chat to submit requests to AI Foreman for idempotent development

param(
    [Parameter(Mandatory=$true)]
    [string]$Type,

    [Parameter(Mandatory=$true)]
    [string]$Description,

    [string[]]$Files = @(),
    [string]$Priority = "normal",
    [switch]$VerboseLog
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if ($VerboseLog) {
        Write-Host "[$timestamp] $Message" -ForegroundColor Cyan
    }
}

function Submit-CursorChatRequest {
    param(
        [string]$Type,
        [string]$Description,
        [string[]]$Files,
        [string]$Priority
    )

    $request = @{
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        type = $Type
        description = $Description
        files = $Files
        priority = $Priority
        status = "pending"
        processed = $false
        source = "cursor_chat"
    }

    $requestPath = ".ai/state/cursor-request.json"
    $request | ConvertTo-Json -Depth 3 | Set-Content $requestPath

    Write-Log "Cursor chat request submitted: $Type - $Description"
    Write-Log "Request saved to: $requestPath"

    return $requestPath
}

function Invoke-AIForeman {
    param([string]$RequestPath)

    Write-Log "Running AI Foreman to process Cursor chat request..."

    try {
        # Run AI Foreman
        $result = & ".\ai-foreman.ps1" -VerboseLog:$VerboseLog

        if ($LASTEXITCODE -eq 0) {
            Write-Log "AI Foreman completed successfully"
            return $true
        } else {
            Write-Log "AI Foreman completed with issues (exit code: $LASTEXITCODE)"
            return $false
        }
    }
    catch {
        Write-Log "Error running AI Foreman: $($_.Exception.Message)"
        return $false
    }
}

function Get-AIForemanStatus {
    $fingerprintPath = ".ai/state/fp.json"
    $logPath = "docs/AI_FOREMAN_LOG.md"

    $status = @{
        fingerprint_exists = Test-Path $fingerprintPath
        log_exists = Test-Path $logPath
        last_run = $null
        fingerprint = $null
    }

    if ($status.fingerprint_exists) {
        try {
            $fingerprint = Get-Content $fingerprintPath | ConvertFrom-Json
            $status.last_run = $fingerprint.when
            $status.fingerprint = $fingerprint.fingerprint
        }
        catch {
            Write-Log "Error reading fingerprint: $($_.Exception.Message)"
        }
    }

    return $status
}

function Show-Usage {
    Write-Host @"
Cursor Chat Integration for AI Foreman

USAGE:
    .\cursor-chat-integration.ps1 -Type <type> -Description <description> [options]

PARAMETERS:
    -Type          Request type: add_feature, fix_bug, improve_scraping, security_fix, documentation, vendor_module
    -Description   Detailed description of the requested change
    -Files         Optional array of specific files to modify
    -Priority      Priority level: low, normal, high, critical (default: normal)
    -VerboseLog       Show detailed logging

EXAMPLES:
    # Add a new feature
    .\cursor-chat-integration.ps1 -Type "add_feature" -Description "Add support for Oracle security advisories"

    # Fix a bug
    .\cursor-chat-integration.ps1 -Type "fix_bug" -Description "Fix Microsoft vendor scraping for new MSRC page layout"

    # Improve scraping
    .\cursor-chat-integration.ps1 -Type "improve_scraping" -Description "Enhance Playwright integration for JavaScript-heavy pages"

    # Security fix
    .\cursor-chat-integration.ps1 -Type "security_fix" -Description "Implement NIST security guidelines compliance"

    # Documentation update
    .\cursor-chat-integration.ps1 -Type "documentation" -Description "Update API documentation for new vendor modules"

    # Vendor module improvements
    .\cursor-chat-integration.ps1 -Type "vendor_module" -Description "Improve error handling in all vendor modules"

REQUEST TYPES:
    add_feature    - Add new functionality or features
    fix_bug        - Fix existing bugs or issues
    improve_scraping - Enhance web scraping capabilities
    security_fix   - Implement security improvements
    documentation  - Update documentation
    vendor_module  - Improve vendor-specific modules

"@
}

# Main execution
Write-Log "Starting Cursor chat integration"

# Validate parameters
$validTypes = @("add_feature", "fix_bug", "improve_scraping", "security_fix", "documentation", "vendor_module")
if ($Type -notin $validTypes) {
    Write-Host "Error: Invalid type '$Type'. Valid types are: $($validTypes -join ', ')" -ForegroundColor Red
    Show-Usage
    exit 1
}

$validPriorities = @("low", "normal", "high", "critical")
if ($Priority -notin $validPriorities) {
    Write-Host "Error: Invalid priority '$Priority'. Valid priorities are: $($validPriorities -join ', ')" -ForegroundColor Red
    Show-Usage
    exit 1
}

# Check AI Foreman status
$status = Get-AIForemanStatus
Write-Log "AI Foreman status: Fingerprint exists: $($status.fingerprint_exists), Last run: $($status.last_run)"

# Submit request
$requestPath = Submit-CursorChatRequest -Type $Type -Description $Description -Files $Files -Priority $Priority

# Run AI Foreman
$success = Invoke-AIForeman -RequestPath $requestPath

if ($success) {
    Write-Host "✅ Cursor chat request processed successfully by AI Foreman" -ForegroundColor Green
    Write-Host "📋 Check the AI Foreman log: docs/AI_FOREMAN_LOG.md" -ForegroundColor Yellow
    Write-Host "🔍 Review changes in the generated branch" -ForegroundColor Yellow
} else {
    Write-Host "❌ AI Foreman encountered issues processing the request" -ForegroundColor Red
    Write-Host "📋 Check the AI Foreman log: docs/AI_FOREMAN_LOG.md" -ForegroundColor Yellow
}

Write-Log "Cursor chat integration completed"
