<#
.SYNOPSIS
    About Tab - Information and documentation tab component for CVExcel GUI

.DESCRIPTION
    Modular component containing initialization logic for the About/Info tab.
    Handles hyperlink navigation and displays project information.

.NOTES
    This module is loaded by CVExcel-GUI.ps1 and operates on GUI controls
    passed as parameters to Initialize-AboutTab.

.AUTHOR
    Columbia Cloudworks LLC
    https://github.com/Columbia-Cloudworks-LLC/CVExcel
#>

function Initialize-AboutTab {
    <#
    .SYNOPSIS
        Initializes the About/Info tab with event handlers.

    .PARAMETER Window
        The main WPF window object

    .PARAMETER Controls
        Hashtable containing About tab control references
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [Parameter(Mandatory)]
        [hashtable]$Controls
    )

    Write-Host "Initializing About tab..." -ForegroundColor Cyan

    # -------------------- Hyperlink Handler for GitHub Link --------------------

    if ($Controls.GitHubLink) {
        $Controls.GitHubLink.Add_RequestNavigate({
                param($s, $e)
                Start-Process $e.Uri.AbsoluteUri
                $e.Handled = $true
            })
        Write-Host "  GitHub link handler configured" -ForegroundColor Green
    }

    Write-Host "  About tab initialized successfully" -ForegroundColor Green
}

# Function is available for direct calling in script mode
