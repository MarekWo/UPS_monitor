## 🚀 Features

* **Reliable Shutdown:** Uses the low-level `shutdown` command, avoiding complex and fragile "standby" modes.
* **Centralized Configuration (Hub Mode):** Optionally, the script can fetch its configuration (`UPS_NAME`, `SHUTDOWN_DELAY_MINUTES`) from a central REST API endpoint. This is perfect for managing multiple client machines from a single location.
* **Configurable Delay:** Set a grace period (in minutes) before shutdown, giving short power outages a chance to resolve.
* **Smart Cancellation:** Automatically cancels the pending shutdown if mains power is restored.
* **Resilient Fallback:** If the central API hub is unreachable, the script automatically falls back to using its last known good configuration from the local `ups.env` file, ensuring uninterrupted protection.
* **Compatibility:** Works on any Windows machines with Powershell 5.1 or later.
* **Lightweight & Stateless:** Has minimal dependencies and uses a simple flag file for state management, requiring no complex daemons.
* **Easy to Configure:** All settings are managed in a simple, external `ups.env` file for standalone mode, with an override for hub mode.
* **Automated Updates:** Includes an optional update script to pull the latest version from the official repository.
* **Active Status Reporting:** In Hub Mode, the script reports its status (`online`, `shutdown_pending`) back to the `UPS_Server_Docker` API on every run. This provides a live, accurate view of the client's health in the central dashboard.

---



## 🪟 Installation & Configuration for Windows (PowerShell)

Follow these steps to set up the monitor on a Windows system using the PowerShell script (`ups_monitor.ps1`). The logic is identical to the Linux version but adapted for the Windows environment.

### Prerequisites

Ensure the following are available on your system:

* **Windows PowerShell 5.1** or later (installed by default on Windows 10/11 and Server 2016/2019/2022).
* **Git for Windows** for cloning the project (or download ZIP from GitHub).
* **Internet access** for the script to communicate with the UPS API server.
* The script must be run as an **Administrator** to schedule tasks, write to the Event Log, and initiate system shutdown.

**Important:** The PowerShell script communicates with the UPS server via REST API (unlike the Linux version which uses the `upsc` command directly). Ensure your UPS server provides the appropriate API endpoints.

### Step 1: Clone or Download the Repository

First, place the script files in a persistent, system-wide location. A good choice for system scripts on Windows is `C:\ProgramData`, which is a hidden folder by default.

```powershell
# Open PowerShell as an Administrator
# Create the directory and clone the repository
New-Item -Path "C:\ProgramData\ups-monitor" -ItemType Directory -Force
Set-Location "C:\ProgramData\ups-monitor"

# Method 1: Using Git
git clone https://github.com/MarekWo/UPS_monitor.git .

# Method 2: If Git is not available, download and extract manually
# Download the ZIP file from GitHub and extract to C:\ProgramData\ups-monitor
```

### Step 2: Create and Customize the Configuration

Create your local configuration file by copying the provided example. This file will be ignored by git, so your settings are safe.

```powershell
# In the script directory (C:\ProgramData\ups-monitor)
Copy-Item ups.env.example ups.env
```

Now, edit the newly created `ups.env` file with your specific settings using a text editor like Notepad:

```powershell
notepad C:\ProgramData\ups-monitor\ups.env
```

**Example configuration for Windows (API mode):**
```bash
# ups.env

# --- API Hub Configuration (Required for Windows) ---
# The address of your central UPS Hub API server.
API_SERVER_URI="http://192.168.1.50:5000"

# The secret token to authenticate with the API Hub.
API_TOKEN="your_super_secret_api_token"

# --- Fallback Configuration ---
# Used if the API Hub is unreachable.
UPS_NAME="ups@192.168.1.50"
SHUTDOWN_DELAY_MINUTES=10

# --- Optional Windows-specific settings ---
# FLAG_FILE="C:\Temp\ups_shutdown_pending.flag"
# LOG_TAG="UPS_Monitor_Windows"
```

**Note:** The Windows version requires the API server configuration (`API_SERVER_URI` and `API_TOKEN`) to function properly, as it cannot use the native `upsc` command like the Linux version.

### Step 3: Set PowerShell Execution Policy and Unblock Scripts

By default, Windows restricts running scripts for security. First, ensure your system's execution policy allows local scripts to run. The following command, run from an **Administrator PowerShell** prompt, is a common and safe choice:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

Next, because the script files were downloaded from the internet, you must "unblock" them to allow them to run under the `RemoteSigned` policy. This removes the "Mark of the Web" that Windows automatically adds to downloaded files.

Run these commands from the script's directory:

```powershell
# In C:\ProgramData\ups-monitor
Unblock-File .\ups_monitor.ps1
Unblock-File .\update.ps1
```

This approach maintains a high level of security on your system without preventing the monitor scripts from running.


### Step 4: Schedule the Task

The script needs to run every minute to be effective. This is done using **Task Scheduler**, and it must be configured to run as a high-privilege user.

#### Method 1: Using Task Scheduler GUI

1. Open **Task Scheduler** from the Start Menu or run `taskschd.msc`.

2. In the right-hand "Actions" pane, click **Create Task...**.

3. On the **General** tab:
   * **Name:** `UPS Monitor`
   * **Description:** `Monitors UPS status and initiates safe shutdown on low battery`
   * Select **Run whether user is logged on or not**.
   * Check the box for **Run with highest privileges**.
   * **Configure for:** Choose your Windows version (e.g., "Windows 10")

4. On the **Triggers** tab:
   * Click **New...**.
   * Set "Begin the task:" to **At startup**.
   * Under "Advanced settings", check **Repeat task every:** and choose **1 minute** from the dropdown.
   * For "for a duration of:", choose **Indefinitely**.
   * Ensure the **Enabled** box at the bottom is checked. Click **OK**.

5. On the **Actions** tab:
   * Click **New...**.
   * **Action:** `Start a program`.
   * **Program/script:** `powershell.exe`
   * **Add arguments (optional):** `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ups-monitor\ups_monitor.ps1"`
   * **Start in (optional):** `C:\ProgramData\ups-monitor`

6. On the **Conditions** tab:
   * **Uncheck** "Start the task only if the computer is on AC power" (important for UPS monitoring!)
   * **Uncheck** "Stop if the computer switches to battery power"

7. On the **Settings** tab:
   * Check "Allow task to be run on demand"
   * Check "Run task as soon as possible after a scheduled start is missed"
   * If task fails, restart every: **1 minute**
   * Attempt to restart up to: **3 times**

8. Click **OK** to save the task.

#### Method 2: Using PowerShell (Alternative)

```powershell
# Create scheduled task using PowerShell (run as Administrator)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\ProgramData\ups-monitor\ups_monitor.ps1`"" -WorkingDirectory "C:\ProgramData\ups-monitor"

$Trigger = New-ScheduledTaskTrigger -AtStartup
$Trigger.RepetitionInterval = "PT1M"  # Every 1 minute
$Trigger.RepetitionDuration = "P1D"   # For 1 day, then repeat

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3

$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "UPS Monitor" -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Description "Monitors UPS status and initiates safe shutdown on low battery"
```

---

## 🔄 Updating (Windows)

To update the script to the latest version, you can use the provided `update.ps1` script:

```powershell
# Navigate to your script directory and run the updater
Set-Location C:\ProgramData\ups-monitor
.\update.ps1
```

**Automating Updates:**
You can automate this by adding a second, less frequent Scheduled Task (e.g., daily at 3:00 AM):

```powershell
# Create update task using PowerShell (run as Administrator)
$UpdateAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\ProgramData\ups-monitor\update.ps1`"" -WorkingDirectory "C:\ProgramData\ups-monitor"

$UpdateTrigger = New-ScheduledTaskTrigger -Daily -At "3:00AM"

$UpdateSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

$UpdatePrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "UPS Monitor Update" -Action $UpdateAction -Trigger $UpdateTrigger -Settings $UpdateSettings -Principal $UpdatePrincipal -Description "Updates UPS Monitor script from GitHub"
```

---

## ✅ Testing (Windows)

After setup, you can test the script's functionality:

### 1. Manual Test Run
Open an **Administrator PowerShell** prompt and run the script manually:
```powershell
Set-Location C:\ProgramData\ups-monitor
.\ups_monitor.ps1
```

Watch for any error messages or warnings during execution.

### 2. Check the Event Logs
The script logs all activities to the Windows Event Log:

**Using Event Viewer GUI:**
* Open the **Event Viewer** app (`eventvwr.msc`).
* Navigate to **Windows Logs** → **Application**.
* Look for events with the **Source** set to `UPS_Shutdown_Script` (or your custom `LOG_TAG`).

**Using PowerShell:**
```powershell
# View recent UPS monitor events
Get-EventLog -LogName Application -Source "UPS_Shutdown_Script" -Newest 10

# Monitor events in real-time
Get-EventLog -LogName Application -Source "UPS_Shutdown_Script" -After (Get-Date).AddMinutes(-1) | Format-Table TimeGenerated, EntryType, Message -Wrap
```

### 3. Verify Scheduled Task
Check that the scheduled task is running properly:
```powershell
# Check if task exists and is enabled
Get-ScheduledTask -TaskName "UPS Monitor"

# View task history
Get-ScheduledTask -TaskName "UPS Monitor" | Get-ScheduledTaskInfo
```

### 4. Simulate Power Events
**Testing Low Battery Detection:**
1. Configure your UPS server to return `OB LB` status.
2. Wait for the next script execution (up to 1 minute).
3. Check Event Viewer for countdown initiation messages.
4. The script should log: `"Low battery detected! Starting X minute countdown to system shutdown."`

**Testing Power Restoration:**
1. Before the countdown completes, configure your UPS server to return `OL` status.
2. Check Event Viewer for cancellation messages.
3. The script should log: `"Main power has been restored. Cancelling shutdown countdown."`

### 5. API Connectivity Test
Verify the script can communicate with your UPS API server:
```powershell
# Test API connectivity manually
$headers = @{ "Authorization" = "Bearer YOUR_API_TOKEN" }
Invoke-RestMethod -Uri "http://YOUR_UPS_SERVER:5000/upsc" -Headers $headers
```

---

## 🔧 Troubleshooting (Windows)

### Common Issues:

**Script won't run - Execution Policy:**
```powershell
# Check current policy
Get-ExecutionPolicy -List

# Fix with appropriate policy
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

**Event Log access denied:**
- Ensure the script runs as Administrator or SYSTEM account
- The scheduled task must have "Run with highest privileges" enabled

**API connection failures:**
- Verify `API_SERVER_URI` and `API_TOKEN` in `ups.env`
- Check Windows Firewall settings
- Test network connectivity to UPS server

**Task doesn't run on battery power:**
- In Task Scheduler, uncheck "Start the task only if the computer is on AC power"
- Uncheck "Stop if the computer switches to battery power"

### Debug Mode:
Add debug logging to see detailed execution:
```powershell
# Edit the script to add more verbose logging
# Or temporarily add Write-Host statements for console output
```

---

## 🔒 Security Considerations (Windows)

* Store the `ups.env` file in a secure location with appropriate NTFS permissions
* Consider encrypting the `API_TOKEN` using Windows DPAPI if storing sensitive credentials
* Regularly review Event Logs for unauthorized access attempts
* Keep the script updated to the latest version for security patches