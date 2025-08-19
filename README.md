# Universal NUT UPS Shutdown Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust, universal, and configurable Bash script that safely shuts down a Linux-based system by monitoring a remote NUT (Network UPS Tools) server. It's designed to be a reliable replacement for inflexible or buggy built-in UPS clients.

---

## 📜 The Problem

Many appliance-like operating systems, such as Synology DSM, Proxmox VE, or TrueNAS, offer built-in UPS support. However, this support can be surprisingly brittle, especially in custom setups (like using a non-Synology device as a NUT server for a Synology client).

This project was born out of frustration with a common failure mode: upon receiving a "Low Battery" signal, the system would start a shutdown procedure but hang indefinitely, becoming unresponsive. This is often caused by a flawed "Standby Mode" or "Safe Mode" implementation that fails to complete. A system in this hung state requires a hard power cycle to recover, which is a critical issue for remote or unattended servers.

## ✨ The Solution

This script bypasses the native, problematic shutdown logic entirely. Instead of relying on the host OS's UPS integration, it uses a simple and direct approach:

1.  It runs periodically via **cron**.
2.  It directly queries the NUT server using the standard `upsc` command.
3.  If a critical `On Battery, Low Battery` state is detected, it initiates a **configurable countdown**.
4.  If power is restored during the countdown, the shutdown is **cleanly cancelled**.
5.  If the countdown completes, it executes the universally reliable `/sbin/shutdown -h now` command.

This method provides predictable, robust, and platform-agnostic protection against data loss during a power failure.

---

## 🚀 Features

* **Reliable Shutdown:** Uses the low-level `shutdown` command, avoiding complex and fragile "standby" modes.
* **Configurable Delay:** Set a grace period (in minutes) before shutdown, giving short power outages a chance to resolve.
* **Smart Cancellation:** Automatically cancels the pending shutdown if mains power is restored.
* **Universal Compatibility:** Works on virtually any Linux-based system with Bash and NUT client tools (Synology DSM, Proxmox, Debian, Ubuntu, etc.).
* **Lightweight & Stateless:** Has minimal dependencies and uses a simple flag file for state management, requiring no complex daemons.
* **Easy to Configure:** All settings are managed in a simple, external `ups.env` file.
* **Centralized Updates:** Includes an optional update script to pull the latest version from your repository.

This project is the perfect companion to the **[PowerManager](https://github.com/MarekWo/PowerManager)** server script, which simulates a NUT (Network UPS Tools) server's status based on network conditions.

---

## 🔧 How It Works

The script's logic is managed by a state machine that runs every minute:

1.  **Check Status:** The script calls `upsc` to get the `ups.status` variable from the NUT server.
2.  **Detect Low Battery:** If the status is `OB LB` (On Battery, Low Battery), the script checks for the existence of a flag file (`/tmp/ups_shutdown_pending.flag`).
    * If the flag **doesn't exist**, it's the first sign of trouble. The script writes the current timestamp into the flag file and logs that the countdown has begun.
    * If the flag **exists**, the script calculates the time elapsed since the timestamp in the file. If the elapsed time exceeds the configured delay, it executes `shutdown -h now`.
3.  **Detect Power Restoration:** If the status is `OL` (On Line) and the flag file **exists**, the script knows a shutdown was pending. It logs the cancellation and simply deletes the flag file, effectively resetting the state.

---

## ⚙️ Installation & Configuration

Follow these steps to set up the monitor on a new system.

### Prerequisites

Ensure the following packages are installed on your system:
* `bash` (usually installed by default)
* `cron` or another task scheduler
* `curl` (for the update script)
* `nut-client` (or equivalent package that provides the `upsc` command)
* `git` for cloning the project from GitHub

### Step 1: Clone or Download the Repository

First, place the script files in a persistent location on your server.

**For most Linux systems (Proxmox, Debian, etc.), a good choice is `/opt/ups-monitor`:**
```bash
# Example using git
git clone https://github.com/MarekWo/UPS_monitor.git /opt/ups-monitor
cd /opt/ups-monitor
```

**For Synology DSM Users:**
The Synology operating system does not have an `/opt` directory. The best practice is to place scripts on a data volume to ensure they survive system updates. The recommended location is a dedicated `scripts` folder on `volume1`.

```bash
# Create the directory on your data volume
sudo mkdir -p /volume1/scripts/ups-monitor

# Clone the repository into the new directory
git clone https://github.com/MarekWo/UPS_monitor.git /volume1/scripts/ups-monitor
cd /volume1/scripts/ups-monitor
```

### Step 2: Create and Customize the Configuration

Create your local configuration file by copying the provided example. This file will be ignored by git, so your settings are safe.

```bash
cp ups.env.example ups.env
```

Now, edit the newly created `ups.env` with your specific settings:

```ini
# ups.env

# The identifier for the UPS on your NUT server (<upsname>@<hostname>).
UPS_NAME="ups@192.168.1.50"

# The delay in minutes before shutdown after a low battery is detected.
SHUTDOWN_DELAY_MINUTES=5
```

### Step 3: Set Permissions

Make the main script and the update script executable.

```bash
chmod +x ups_monitor.sh
chmod +x update.sh
```

### Step 4: Schedule the Cron Job

The script needs to run every minute to be effective. You must schedule it to run as the **`root`** user, as the `shutdown` command requires root privileges.

**For most Linux systems:**
Open the root user's crontab for editing:

```bash
sudo crontab -e
```

Add the following line, making sure the path is correct for your installation, then save and exit:

```crontab
# Run the UPS monitor script every minute
* * * * * /opt/ups-monitor/ups_monitor.sh
```

**For Synology DSM Users:**

1.  Go to `Control Panel` \> `Task Scheduler`.
2.  Click `Create` \> `Scheduled Task` \> `User-defined script`.
3.  In the **General** tab:
      * Task: `UPS Monitor`
      * User: `root`
4.  In the **Schedule** tab:
      * Run on the following days: `Daily`
      * Frequency: `Every 1 minute`
5.  In the **Task Settings** tab, enter the full path to the script in the `Run command` box:
    ```
    bash /volume1/scripts/ups-monitor/ups_monitor.sh
    ```
6.  Click `OK` to save the task.

-----

## 🔄 Updating

To update the script to the latest version from your repository, simply run the `update.sh` script.

```bash
# Navigate to your script directory and run the updater
# (e.g., /opt/ups-monitor or /volume1/scripts/ups-monitor)
cd /path/to/your/script/directory
./update.sh
```

You can also automate this by adding a second cron job (or another Task Scheduler entry on Synology) to run the updater daily, for example, at 3:00 AM.

-----

## ✅ Testing

After setup, you can test the script's functionality:

1.  **Run it manually:** Execute `/path/to/your/script/ups_monitor.sh` and check for any errors.
2.  **Check the logs:**
      * **For systemd-based systems (Debian, Proxmox):** `journalctl -f | grep UPS_Shutdown_Script`
      * **For Synology DSM:** Open the `Log Center` application or check the log file directly with `tail -f /var/log/messages | grep UPS_Shutdown_Script`
3.  **Simulate a power failure:** Change the state of your (dummy) NUT server to `OB LB` and watch the logs. The script should log that the countdown has started.
4.  **Simulate power restoration:** Before the delay is over, change the NUT server state back to `OL`. The script should log that the shutdown has been cancelled.

-----

## 🤝 Contributing

This is a community-driven project. If you have an idea for an improvement or find a bug, please feel free to fork the repository, make your changes, and submit a pull request. You can also open an issue to start a discussion.

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.

```
