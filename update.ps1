<#
.SYNOPSIS
    Update script for UPS Monitor PowerShell version
.DESCRIPTION
    A simple script to download the latest version of ups_monitor.ps1 from GitHub.
    This is the PowerShell equivalent of the update.sh script.
.NOTES
    Author: MarekWo
    Version: 1.0.0
    Requires: PowerShell 5.1 or later with internet access
#>

# --- CONFIGURATION ---
$SCRIPT_URL = "https://raw.githubusercontent.com/MarekWo/UPS_monitor/main/ups_monitor.ps1"
$INSTALL_DIR = $PSScriptRoot
$TARGET_SCRIPT = "ups_monitor.ps1"
$TEMP_SCRIPT = "ups_monitor.ps1.tmp"

# Full paths
$TargetPath = Join-Path $INSTALL_DIR $TARGET_SCRIPT
$TempPath = Join-Path $INSTALL_DIR $TEMP_SCRIPT

# --- SCRIPT LOGIC ---
try {
    Write-Host "Downloading latest version of the UPS monitor PowerShell script..." -ForegroundColor Green
    
    # Configure TLS settings for better compatibility
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # Download to a temporary file first
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "UPS-Monitor-Update-Script/1.0")
    
    try {
        $webClient.DownloadFile($SCRIPT_URL, $TempPath)
        Write-Host "Download completed successfully." -ForegroundColor Green
    }
    finally {
        $webClient.Dispose()
    }
    
    # Check if download was successful and the file is not empty
    if ((Test-Path $TempPath) -and ((Get-Item $TempPath).Length -gt 0)) {
        
        # Basic validation - check if it looks like a PowerShell script
        $firstLine = Get-Content $TempPath -First 1
        if ($firstLine -match "^<#|^#.*PowerShell|^param|^\s*\$") {
            
            # Create backup of existing script if it exists
            if (Test-Path $TargetPath) {
                $BackupPath = Join-Path $INSTALL_DIR "ups_monitor.ps1.backup"
                Copy-Item $TargetPath $BackupPath -Force
                Write-Host "Created backup: $BackupPath" -ForegroundColor Yellow
            }
            
            # Overwrite the old script only if the new one appears valid
            Move-Item $TempPath $TargetPath -Force
            Write-Host "Update successful! The script has been updated." -ForegroundColor Green
            
            # Display version info if available
            $versionLine = Get-Content $TargetPath | Where-Object { $_ -match "Version:\s*(\d+\.\d+\.\d+)" } | Select-Object -First 1
            if ($versionLine) {
                $version = ($versionLine | Select-String "Version:\s*(\d+\.\d+\.\d+)").Matches[0].Groups[1].Value
                Write-Host "Updated to version: $version" -ForegroundColor Cyan
            }
            
        } else {
            throw "Downloaded file does not appear to be a valid PowerShell script."
        }
        
    } else {
        throw "Downloaded file is empty or does not exist."
    }
    
} catch {
    Write-Host "ERROR: Failed to download or update the script." -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    
    # Clean up the failed download
    if (Test-Path $TempPath) {
        Remove-Item $TempPath -Force -ErrorAction SilentlyContinue
    }
    
    # Restore backup if update failed and backup exists
    $BackupPath = Join-Path $INSTALL_DIR "ups_monitor.ps1.backup"
    if ((Test-Path $BackupPath) -and (-not (Test-Path $TargetPath))) {
        Move-Item $BackupPath $TargetPath -Force
        Write-Host "Restored previous version from backup." -ForegroundColor Yellow
    }
    
    Write-Host "No changes were made to the existing script." -ForegroundColor Yellow
    Exit 1
}

# --- OPTIONAL: Test the updated script syntax ---
try {
    Write-Host "Validating script syntax..." -ForegroundColor Yellow
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $TargetPath -Raw), [ref]$null)
    Write-Host "Script syntax validation passed!" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Script syntax validation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "The script may have issues. Consider restoring from backup." -ForegroundColor Red
}

Write-Host "Update process completed." -ForegroundColor Green
Exit 0