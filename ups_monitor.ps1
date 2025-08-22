<#
.SYNOPSIS
    Universal UPS Status Monitor for Windows (v4.0.1 - Caching Hub Edition)
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
    Version: 4.0.1
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

# PowerShell equivalent of 'source ups.env'
if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        if ($_ -match '^([^#].*?)=["'']?(.*?)["'']?$') {
            Set-Variable -Name $Matches[1] -Value $Matches[2]
        }
    }
}
else {
    Write-EventLog -LogName Application -Source "UPS_Monitor_Core" -EventId 1001 -EntryType Error -Message "CRITICAL ERROR: Local config file not found at $ConfigFile. Exiting."
    Exit 1
}

# --- Set Default Values ---
$UPS_NAME = if ([string]::IsNullOrEmpty($UPS_NAME)) { "ups@localhost" } else { $UPS_NAME }
$SHUTDOWN_DELAY_MINUTES = if ([string]::IsNullOrEmpty($SHUTDOWN_DELAY_MINUTES)) { 15 } else { $SHUTDOWN_DELAY_MINUTES }
$FLAG_FILE = if ([string]::IsNullOrEmpty($FLAG_FILE)) { "$env:TEMP\ups_shutdown_pending.flag" } else { $FLAG_FILE }
$LOG_TAG = if ([string]::IsNullOrEmpty($LOG_TAG)) { "UPS_Shutdown_Script" } else { $LOG_TAG }

# --- Universal Logging Function (using Windows Event Log) ---
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level,

        [Parameter(Mandatory=$true)]
        [string]$Message
    )

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

# --- Function to get the primary IP of this machine ---
function Get-PrimaryIp {
    try {
        $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1).IPv4Address.IPAddress
        return $ip
    } catch {
        return $null
    }
}

# --- Configuration Fetching Logic (Hub Mode) ---
if (-not ([string]::IsNullOrEmpty($API_SERVER_URI)) -and -not ([string]::IsNullOrEmpty($API_TOKEN))) {
    Write-Log -Level "Information" -Message "API server is configured. Attempting to fetch remote configuration."

    $ClientIp = Get-PrimaryIp
    $ApiUrl = "$API_SERVER_URI/config?ip=$ClientIp"
    $headers = @{ "Authorization" = "Bearer $API_TOKEN" }

    try {
        $ApiResponse = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 10 -ConnectTimeout 5
        
        $RemoteUpsName = $ApiResponse.PSObject.Properties['UPS_NAME'].Value
        $RemoteShutdownDelay = $ApiResponse.PSObject.Properties['SHUTDOWN_DELAY_MINUTES'].Value

        if (-not ([string]::IsNullOrEmpty($RemoteUpsName)) -and -not ([string]::IsNullOrEmpty($RemoteShutdownDelay))) {
            Write-Log -Level "Information" -Message "Successfully fetched remote config. Using UPS: '$RemoteUpsName', Delay: '$RemoteShutdownDelay' minutes."
            
            # Update local variables for the current run
            $UPS_NAME = $RemoteUpsName
            $SHUTDOWN_DELAY_MINUTES = $RemoteShutdownDelay

            # Update the local ups.env file to cache the new values
            Write-Log -Level "Information" -Message "Updating local fallback configuration at $ConfigFile."
            $newConfig = (Get-Content $ConfigFile) | ForEach-Object {
                if ($_ -like 'UPS_NAME=*') {
                    "UPS_NAME=`"$UPS_NAME`""
                } elseif ($_ -like 'SHUTDOWN_DELAY_MINUTES=*') {
                    "SHUTDOWN_DELAY_MINUTES=$SHUTDOWN_DELAY_MINUTES"
                } else {
                    $_
                }
            }
            $newConfig | Set-Content $ConfigFile
        }
        else {
            Write-Log -Level "Warning" -Message "API response was invalid (check key names: UPS_NAME, SHUTDOWN_DELAY_MINUTES). Falling back to local configuration."
        }
    }
    catch {
        Write-Log -Level "Warning" -Message "Failed to connect to API Hub at $API_SERVER_URI. Error: $($_.Exception.Message). Falling back to local configuration."
    }
}
else {
    Write-Log -Level "Information" -Message "API server not configured. Using local configuration."
}


# --- MAIN SCRIPT LOGIC ---
$ShutdownDelaySeconds = [int]$SHUTDOWN_DELAY_MINUTES * 60
$CurrentStatus = $null
$UpsStatusUrl = "$API_SERVER_URI/upsc" # Use the base URI for the upsc endpoint

try {
    # Per your instructions, get status from the REST API
    $headers = @{ "Authorization" = "Bearer $API_TOKEN" }
    $CurrentStatus = (Invoke-RestMethod -Uri $UpsStatusUrl -Headers $headers -TimeoutSec 10).ups.status
}
catch {
    Write-Log -Level "Error" -Message "ERROR: Could not get status from UPS server API ($UpsStatusUrl). Check connection. Error: $($_.Exception.Message)"
    Exit 1
}

if ($CurrentStatus -eq "OB LB") {
    if (-not (Test-Path $FLAG_FILE)) {
        Write-Log -Level "Warning" -Message "Low battery detected! Starting $SHUTDOWN_DELAY_MINUTES minute countdown to system shutdown."
        $startTime = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $startTime | Set-Content $FLAG_FILE
    }
    else {
        $startTime = Get-Content $FLAG_FILE
        $currentTime = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $elapsedTime = $currentTime - [int64]$startTime
        
        if ($elapsedTime -ge $ShutdownDelaySeconds) {
            Write-Log -Level "Error" -Message "Shutdown delay of $SHUTDOWN_DELAY_MINUTES minutes has passed. Shutting down NOW."
            Remove-Item $FLAG_FILE -ErrorAction SilentlyContinue
            Stop-Computer -Force
            Exit 0
        }
    }
}
elseif ($CurrentStatus -eq "OL") {
    if (Test-Path $FLAG_FILE) {
        Write-Log -Level "Information" -Message "Main power has been restored. Cancelling shutdown countdown."
        Remove-Item $FLAG_FILE -ErrorAction SilentlyContinue
    }
}

Exit 0