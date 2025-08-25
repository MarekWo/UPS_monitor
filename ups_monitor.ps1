<#
.SYNOPSIS
    Universal UPS Status Monitor for Windows (v4.0.2 - Caching Hub Edition)
    Monitors a remote NUT UPS server via a REST API and safely shuts down the local machine.
.DESCRIPTION
    A robust, universal, and configurable PowerShell script that safely shuts down a Windows-based
    system by monitoring a remote NUT (Network UPS Tools) server via a REST API. It is designed
    as a feature-equivalent replacement for the Linux UPS_Monitor script.

    Features:
    - Configurable shutdown delay.
    - Shutdown cancellation if power is restored.
    - Stateful operation using a flag file.
    - External configuration via an ups.env file.
    - Hub functionality: Fetches configuration from a central REST API.
    - Resilient Fallback: Uses a local ups.env file if the API is unreachable.
    - Caching: Updates the local ups.env file with the last successful config from the hub.
.NOTES
    Author: MarekWo
    Version: 4.0.2
    Requires: Windows PowerShell 5.1 or later.
    Execution Policy: Must be run with an execution policy that allows scripts (e.g., RemoteSigned).
    Permissions: Must be run as an Administrator to write to the Event Log and to initiate shutdown.
#>

# --- Verify Administrator Privileges ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an Administrator."
    Exit 1
}

# --- Initial Setup & Configuration Loading ---
$ScriptDir = $PSScriptRoot
$ConfigFile = Join-Path $ScriptDir "ups.env"

# Initialize variables with defaults
$UPS_NAME = "ups@localhost"
$SHUTDOWN_DELAY_MINUTES = 15
$FLAG_FILE = "$env:TEMP\ups_shutdown_pending.flag"
$LOG_TAG = "UPS_Shutdown_Script"
$API_SERVER_URI = $null
$API_TOKEN = $null

# PowerShell equivalent of 'source ups.env'
if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        # Skip comments and empty lines
        if ($_ -match '^\s*#' -or $_ -match '^\s*$') {
            return
        }
        # Parse KEY=VALUE pairs, handling quoted values
        if ($_ -match '^([^#].*?)=["'']?(.*?)["'']?\s*$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            # Remove quotes if present
            $value = $value -replace '^["'']|["'']$', ''
            Set-Variable -Name $key -Value $value -ErrorAction SilentlyContinue
        }
    }
}
else {
    Write-EventLog -LogName Application -Source "UPS_Monitor_Core" -EventId 1001 -EntryType Error -Message "CRITICAL ERROR: Local config file not found at $ConfigFile. Exiting." -ErrorAction SilentlyContinue
    Write-Error "CRITICAL ERROR: Local config file not found at $ConfigFile. Exiting."
    Exit 1
}

# --- Universal Logging Function (using Windows Event Log) ---
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level,

        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    try {
        # Create the Event Log source if it doesn't exist
        if (-not ([System.Diagnostics.EventLog]::SourceExists($LOG_TAG))) {
            New-EventLog -LogName Application -Source $LOG_TAG
        }

        $EventId = switch ($Level) {
            "Information" { 1000 }
            "Warning"     { 2000 }
            "Error"       { 3000 }
        }

        Write-EventLog -LogName Application -Source $LOG_TAG -EventId $EventId -EntryType $Level -Message $Message
    }
    catch {
        # Fallback to Write-Host if EventLog fails
        Write-Host "[$Level] $Message" -ForegroundColor $(switch($Level) {"Error"{"Red"} "Warning"{"Yellow"} default{"White"}})
    }
}

# --- Function to get the primary IP of this machine ---
function Get-PrimaryIp {
    try {
        $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1).IPv4Address.IPAddress
        if (-not $ip) {
            # Fallback method
            $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -eq 'Dhcp' } | Select-Object -First 1).IPAddress
        }
        return $ip
    } catch {
        Write-Log -Level "Warning" -Message "Could not determine primary IP address: $($_.Exception.Message)"
        return $null
    }
}

# --- Function to update local config file ---
function Update-LocalConfig {
    param(
        [string]$UpsName,
        [int]$ShutdownDelay
    )
    
    try {
        Write-Log -Level "Information" -Message "Updating local fallback configuration at $ConfigFile."
        
        $configContent = Get-Content $ConfigFile
        $updatedContent = $configContent | ForEach-Object {
            if ($_ -match '^UPS_NAME=') {
                "UPS_NAME=`"$UpsName`""
            } elseif ($_ -match '^SHUTDOWN_DELAY_MINUTES=') {
                "SHUTDOWN_DELAY_MINUTES=$ShutdownDelay"
            } else {
                $_
            }
        }
        
        $updatedContent | Set-Content $ConfigFile
    }
    catch {
        Write-Log -Level "Warning" -Message "Failed to update local config file: $($_.Exception.Message)"
    }
}

# --- Configuration Fetching Logic (Hub Mode) ---
if (-not ([string]::IsNullOrWhiteSpace($API_SERVER_URI)) -and -not ([string]::IsNullOrWhiteSpace($API_TOKEN))) {
    Write-Log -Level "Information" -Message "API server is configured. Attempting to fetch remote configuration."

    $ClientIp = Get-PrimaryIp
    if ($ClientIp) {
        $ApiUrl = "$API_SERVER_URI/config?ip=$ClientIp"
        $headers = @{ "Authorization" = "Bearer $API_TOKEN" }

        try {
            $ApiResponse = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 10 -ErrorAction Stop
            
            # Check for required properties in response
            $RemoteUpsName = $null
            $RemoteShutdownDelay = $null
            
            if ($ApiResponse.PSObject.Properties['UPS_NAME']) {
                $RemoteUpsName = $ApiResponse.UPS_NAME
            }
            if ($ApiResponse.PSObject.Properties['SHUTDOWN_DELAY_MINUTES']) {
                $RemoteShutdownDelay = $ApiResponse.SHUTDOWN_DELAY_MINUTES
            }

            if (-not ([string]::IsNullOrWhiteSpace($RemoteUpsName)) -and $RemoteShutdownDelay -ne $null) {
                Write-Log -Level "Information" -Message "Successfully fetched remote config. Using UPS: '$RemoteUpsName', Delay: '$RemoteShutdownDelay' minutes."
                
                # Update local variables for the current run
                $UPS_NAME = $RemoteUpsName
                $SHUTDOWN_DELAY_MINUTES = [int]$RemoteShutdownDelay

                # Update the local ups.env file to cache the new values
                Update-LocalConfig -UpsName $UPS_NAME -ShutdownDelay $SHUTDOWN_DELAY_MINUTES
            }
            else {
                Write-Log -Level "Warning" -Message "API response was invalid (missing UPS_NAME or SHUTDOWN_DELAY_MINUTES). Falling back to local configuration."
            }
        }
        catch {
            Write-Log -Level "Warning" -Message "Failed to connect to API Hub at $API_SERVER_URI. Error: $($_.Exception.Message). Falling back to local configuration."
        }
    }
    else {
        Write-Log -Level "Warning" -Message "Could not determine client IP address. Falling back to local configuration."
    }
}
else {
    Write-Log -Level "Information" -Message "API server not configured. Using local configuration."
}

# --- MAIN SCRIPT LOGIC ---
$ShutdownDelaySeconds = [int]$SHUTDOWN_DELAY_MINUTES * 60
$CurrentStatus = $null

# Get UPS status - try API first, then fall back to direct UPS query if available
if (-not ([string]::IsNullOrWhiteSpace($API_SERVER_URI)) -and -not ([string]::IsNullOrWhiteSpace($API_TOKEN))) {
    try {
        $UpsStatusUrl = "$API_SERVER_URI/upsc"
        $headers = @{ "Authorization" = "Bearer $API_TOKEN" }
        $UpsResponse = Invoke-RestMethod -Uri $UpsStatusUrl -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        
        # Extract status from API response - adjust path as needed based on your API structure
        if ($UpsResponse.PSObject.Properties['ups'] -and $UpsResponse.ups.PSObject.Properties['status']) {
            $CurrentStatus = $UpsResponse.ups.status
        } elseif ($UpsResponse.PSObject.Properties['status']) {
            $CurrentStatus = $UpsResponse.status
        }
    }
    catch {
        Write-Log -Level "Error" -Message "ERROR: Could not get status from UPS server API ($UpsStatusUrl). Error: $($_.Exception.Message)"
        Exit 1
    }
}

if (-not $CurrentStatus) {
    Write-Log -Level "Error" -Message "ERROR: Could not determine UPS status from any source."
    Exit 1
}

Write-Log -Level "Information" -Message "Current UPS status: $CurrentStatus"

# Handle low battery condition
if ($CurrentStatus -eq "OB LB") {
    if (-not (Test-Path $FLAG_FILE)) {
        Write-Log -Level "Warning" -Message "Low battery detected! Starting $SHUTDOWN_DELAY_MINUTES minute countdown to system shutdown."
        $startTime = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $startTime | Set-Content $FLAG_FILE
    }
    else {
        try {
            $startTime = [int64](Get-Content $FLAG_FILE -ErrorAction Stop)
            $currentTime = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $elapsedTime = $currentTime - $startTime
            $remainingTime = $ShutdownDelaySeconds - $elapsedTime
            
            if ($elapsedTime -ge $ShutdownDelaySeconds) {
                Write-Log -Level "Error" -Message "Shutdown delay of $SHUTDOWN_DELAY_MINUTES minutes has passed. Shutting down NOW."
                Remove-Item $FLAG_FILE -ErrorAction SilentlyContinue
                Stop-Computer -Force
                Exit 0
            }
            else {
                Write-Log -Level "Warning" -Message "Shutdown countdown in progress. $([math]::Ceiling($remainingTime / 60)) minutes remaining."
            }
        }
        catch {
            Write-Log -Level "Warning" -Message "Error reading flag file. Recreating with current timestamp."
            $startTime = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $startTime | Set-Content $FLAG_FILE
        }
    }
}
# Handle power restoration
elseif ($CurrentStatus -eq "OL") {
    if (Test-Path $FLAG_FILE) {
        Write-Log -Level "Information" -Message "Main power has been restored. Cancelling shutdown countdown."
        Remove-Item $FLAG_FILE -ErrorAction SilentlyContinue
    }
}
else {
    # Handle other statuses (OB without LB, etc.)
    if (Test-Path $FLAG_FILE) {
        Write-Log -Level "Information" -Message "UPS status changed to '$CurrentStatus'. Cancelling any pending shutdown."
        Remove-Item $FLAG_FILE -ErrorAction SilentlyContinue
    }
}

Exit 0