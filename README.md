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

### Step 1: Clone or Download the Repository

First, place the script files in a persistent location on your server. A good choice is `/opt/ups-monitor` or `/usr/local/bin/ups-monitor`.

```bash
# Example using git
git clone [https://github.com/MaWojt/UPS-monitor.git](https://github.com/MaWoj/UPS-monitor.git) /opt/ups-monitor
cd /opt/ups-monitor
```

### Step 2: Create and Customize the Configuration

Create your configuration file by copying the provided example.

```bash
cp ups.env.example ups.env
```

Now, edit `ups.env` with your specific settings:

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

Open the root user's crontab for editing:

```bash
sudo crontab -e
```

Add the following line at the bottom, then save and exit:

```crontab
# Run the UPS monitor script every minute
* * * * * /opt/ups-monitor/ups_monitor.sh
```

**Note for Synology Users:** Use the `Control Panel > Task Scheduler`. Create a new "Scheduled Task" -\> "User-defined script". Set the user to `root` and configure it to run every 1 minute on the "Schedule" tab.

-----

## 🔄 Updating

To update the script to the latest version from your repository, simply run the `update.sh` script.

```bash
# Navigate to the script directory and run the updater
cd /opt/ups-monitor
./update.sh
```

You can also automate this by adding a second cron job to run the updater daily, for example, at 3:00 AM.

```crontab
# Check for script updates once a day at 3:00 AM
0 3 * * * /opt/ups-monitor/update.sh
```

-----

## ✅ Testing

After setup, you can test the script's functionality:

1.  **Run it manually:** Execute `/opt/ups-monitor/ups_monitor.sh` and check for any errors.
2.  **Check the logs:** On most systems, you can view the script's output in the system log.
    ```bash
    # For systemd-based systems (Debian, Proxmox, modern Ubuntu)
    journalctl -f | grep UPS_Shutdown_Script

    # For older systems or Synology
    tail -f /var/log/messages | grep UPS_Shutdown_Script
    ```
3.  **Simulate a power failure:** Change the state of your (dummy) NUT server to `OB LB` and watch the logs. The script should log that the countdown has started.
4.  **Simulate power restoration:** Before the delay is over, change the NUT server state back to `OL`. The script should log that the shutdown has been cancelled.

-----

## 🤝 Contributing

This is a community-driven project. If you have an idea for an improvement or find a bug, please feel free to fork the repository, make your changes, and submit a pull request. You can also open an issue to start a discussion.

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.

