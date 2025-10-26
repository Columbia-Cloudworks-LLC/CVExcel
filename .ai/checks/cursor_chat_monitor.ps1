# Cursor Chat Monitor - AI Foreman Check Script
# Monitors for Cursor chat requests and prepares them for AI Foreman processing

param(
    [string]$OutputPath = ".ai/state/cursor-request.json"
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Test-CursorChatRequest {
    # Check if there's a pending Cursor chat request
    $cursorRequestFile = ".ai/state/cursor-request.json"

    if (-not (Test-Path $cursorRequestFile)) {
        Write-Log "No Cursor chat request found"
        return $null
    }

    try {
        $request = Get-Content $cursorRequestFile | ConvertFrom-Json
        $age = (Get-Date) - [DateTime]::Parse($request.timestamp)

        # Only process requests less than 1 hour old
        if ($age.TotalHours -gt 1) {
            Write-Log "Cursor chat request is too old ($($age.TotalMinutes) minutes), ignoring"
            Remove-Item $cursorRequestFile -Force
            return $null
        }

        Write-Log "Found Cursor chat request: $($request.type) - $($request.description)"
        return $request
    } catch {
        Write-Log "Error reading Cursor chat request: $($_.Exception.Message)"
        return $null
    }
}

function New-CursorChatRequest {
    param(
        [string]$Type,
        [string]$Description,
        [string]$Files = @(),
        [string]$Priority = "normal"
    )

    $request = @{
        timestamp   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        type        = $Type
        description = $Description
        files       = $Files
        priority    = $Priority
        status      = "pending"
        processed   = $false
    }

    $request | ConvertTo-Json -Depth 3 | Set-Content $OutputPath
    Write-Log "Created Cursor chat request: $Type - $Description"
}

# Main execution
Write-Log "Starting Cursor chat monitor check"

# Check for existing requests
$existingRequest = Test-CursorChatRequest

if ($existingRequest) {
    # Output the request for AI Foreman to process
    $existingRequest | ConvertTo-Json -Depth 3 | Set-Content $OutputPath
    Write-Log "Cursor chat request ready for processing"
    exit 0
}

# No request found
Write-Log "No Cursor chat request to process"
exit 0
