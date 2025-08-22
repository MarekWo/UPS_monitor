## 🪟 Installation & Configuration for Windows (PowerShell)

Follow these steps to set up the monitor on a Windows system using the PowerShell script (`ups_monitor.ps1`). The logic is identical to the Linux version but adapted for the Windows environment.

### Prerequisites

Ensure the following are available on your system:

  * **Windows PowerShell 5.1** or later (installed by default on Windows 10/11 and Server 2016/2019/2022).
  * **Git for Windows** for cloning the project.
  * The script must be run as an **Administrator** to schedule tasks, write to the Event Log, and initiate system shutdown.

The PowerShell script is self-contained and does **not** require external tools like `curl` or `jq`.

### Step 1: Clone or Download the Repository

First, place the script files in a persistent, system-wide location. A good choice for system scripts on Windows is `C:\ProgramData`, which is a hidden folder by default.

```powershell
# Open PowerShell as an Administrator
# Create the directory and clone the repository
New-Item -Path "C:\ProgramData\ups-monitor" -ItemType Directory
git clone https://github.com/MarekWo/UPS_monitor.git C:\ProgramData\ups-monitor
cd C:\ProgramData\ups-monitor
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

[cite\_start]The settings are the same as the Linux version and are documented in the `ups.env` file itself[cite: 1, 2, 3, 4, 5, 6].

### Step 3: Set PowerShell Execution Policy

By default, Windows restricts running scripts for security. You must set an execution policy that allows the script to run. Running the following command from an **Administrator PowerShell** prompt is a common and safe choice:

```powershell
Set-ExecutionPolicy RemoteSigned
```

This allows locally created scripts to run but requires scripts downloaded from the internet to be signed.

### Step 4: Schedule the Task

The script needs to run every minute to be effective. This is done using **Task Scheduler**, and it must be configured to run as a high-privilege user.

1.  Open **Task Scheduler** from the Start Menu.

2.  In the right-hand "Actions" pane, click **Create Task...**.

3.  On the **General** tab:

      * **Name:** `UPS Monitor`
      * Select **Run whether user is logged on or not**.
      * Check the box for **Run with highest privileges**.
      * Click **Change User or Group...** and type `SYSTEM`, then click OK. The task will now run as the local `SYSTEM` account.

4.  On the **Triggers** tab:

      * Click **New...**.
      * Set "Begin the task:" to **On a schedule**.
      * Under "Settings", select **Daily**.
      * Under "Advanced settings", check **Repeat task every:** and choose **1 minute** from the dropdown.
      * For "for a duration of:", choose **Indefinitely**.
      * Ensure the **Enabled** box at the bottom is checked. Click **OK**.

5.  On the **Actions** tab:

      * Click **New...**.
      * **Action:** `Start a program`.
      * **Program/script:** `powershell.exe`
      * **Add arguments (optional):** `-NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\ups-monitor\ups_monitor.ps1"`

6.  Click **OK** to save the task. It will now run every minute.

-----

## 🔄 Updating (Windows)

To update the script to the latest version, you can manually run `git pull` from the script directory or use the provided `update.ps1` script.

```powershell
# Navigate to your script directory and run the updater
cd C:\ProgramData\ups-monitor
.\update.ps1
```

You can automate this by adding a second, less frequent Scheduled Task (e.g., daily) that runs the `update.ps1` script.

-----

## ✅ Testing (Windows)

After setup, you can test the script's functionality:

1.  **Run it manually:** Open an **Administrator PowerShell** prompt, navigate to the script directory, and execute it:
    ```powershell
    cd C:\ProgramData\ups-monitor
    .\ups_monitor.ps1
    ```
2.  **Check the logs:**
      * Open the **Event Viewer** app.
      * Navigate to **Windows Logs** -\> **Application**.
      * Look for events with the **Source** set to `UPS_Shutdown_Script` (or your custom `$LOG_TAG`). [cite\_start]The script will log its status here, including countdown initiation and cancellation[cite: 3].
3.  **Simulate a power failure:** Change the state of your NUT server to `OB LB` and watch the Event Viewer logs. The script should log that the countdown has started.
4.  **Simulate power restoration:** Before the delay is over, change the NUT server state back to `OL`. [cite\_start]The script should log that the shutdown has been cancelled[cite: 3].