# Basic Internet Monitoring and Modem Power Cycle System

This project monitors internet connectivity by pinging multiple targets, logs the status in an SQLite database, and automatically triggers a modem power cycle if consecutive failures are detected. It also provides a dashboard to visualize the network status over time using a Dash web app.

## Features

- **Monitor Internet Connectivity**: Pings a list of IPs (e.g., `8.8.8.8`, `1.1.1.1`) and logs success/failure in SQLite.
- **Automatic Power Cycle**: If the internet is down for 5 consecutive checks, it triggers a power cycle of a TP-Link Tapo smart plug (controlling the modem).
- **Dash Dashboard**: A web interface to visualize internet status logs using Dash, showing connectivity success rate, latency, and packet loss over time.
- **Redis Caching**: Used in the Dash app for performance optimization.
- **Cooldown Logic**: Ensures the power cycle isn’t retriggered within a specified cooldown period (10 minutes).

---

## Project Structure

```
internet-monitoring/
│
├── scripts/
│   ├── check_net.sh                     # Script that checks the internet and triggers the power cycle
│   ├── power_cycle_p100.py              # Python script for power cycling the modem via Tapo smart plug
│   ├── requirements.txt                 # Python dependencies for the power cycle script (pytapo)
│
├── dash_app/
│   ├── app.py                           # Dash web app to visualize network logs
│   └── requirements.txt                 # Python dependencies for the Dash app
│
├── logs/                                # Directory for logs, status, and database files
│   ├── check_internet.log               # Log file for internet check script
│   ├── p100-smart-plug-logfile.log      # Log file for the power cycle script
│   ├── internet_status.db               # SQLite database to store internet check results
│   ├── failure_count.txt                # Tracks the number of consecutive internet failures
│   └── cooldown.txt                     # Tracks the cooldown period after power cycling
│
├── venv/                                # Virtual environment for Python packages
└── README.md                            # Setup instructions
```

---

## Setup

### 1. Install Dependencies

First, clone this repository and navigate to the directory:

```bash
git clone https://github.com/famesjranko/internet-monitoring.git
cd internet-monitoring
```

#### a. Python Virtual Environment

1. Create a virtual environment to manage Python dependencies:

   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

2. Install dependencies for both the **power cycle script** and the **Dash app**:

   ```bash
   pip install -r scripts/requirements.txt
   pip install -r dash_app/requirements.txt
   ```

#### b. Redis Setup

1. **Install Redis** on your system (if not already installed):

   ```bash
   sudo apt-get install redis-server
   ```

2. **Start Redis**:

   ```bash
   sudo systemctl start redis-server
   sudo systemctl enable redis-server
   ```

---

## 2. Script and App Configuration

### a. Bash Script (`check_net.sh`)

This script pings predefined targets (e.g., `8.8.8.8`) and logs internet status in the SQLite database (`internet_status.db`). If internet is down for 5 consecutive checks, it triggers the power cycle of the modem via the Python script.

1. **Edit Target IPs**: You can edit the target IPs in the `TARGETS` array in `check_net.sh` if needed.

2. **Database and Log Paths**: The logs are stored in the `logs/` directory. The SQLite database (`internet_status.db`) stores the ping results.

### b. Python Power Cycle Script (`power_cycle_p100.py`)

This script communicates with a TP-Link Tapo smart plug to power cycle the modem. 

1. **Tapo Credentials**: Update the `email`, `password`, and `device_ip` in the script with your Tapo credentials and device IP address.
   
2. **Cooldown Period**: The script includes a cooldown period (default: 10 minutes) to avoid repeated power cycling. The cooldown is tracked via the `logs/cooldown.txt` file.

---

## 3. Dash Web App Setup

The **Dash app** provides a web interface to monitor network connectivity and manually trigger power cycling.

1. **Run the Dash App**:
   ```bash
   cd dash_app
   python3 app.py
   ```

2. **Access the App**: Navigate to `http://<your-server-ip>:8050` in a browser to access the dashboard.

---

## 4. Systemd Services

### a. Internet Check Script Service

Create a systemd service to run the internet check script at regular intervals:

1. **Create a Timer**: `/etc/systemd/system/internet-check.timer`

   ```ini
   [Unit]
   Description=Run internet check every minute

   [Timer]
   OnBootSec=1min
   OnUnitActiveSec=1min
   Unit=internet-check.service

   [Install]
   WantedBy=timers.target
   ```

2. **Create the Service**: `/etc/systemd/system/internet-check.service`

   ```ini
   [Unit]
   Description=Internet Check Service

   [Service]
   ExecStart=/bin/bash /path-to-repo/scripts/check_net.sh
   ```

3. **Enable the Timer**:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now internet-check.timer
   ```

### b. Dash Web App Service

You can set up the Dash app as a service so it starts automatically.

1. **Create the Service**: `/etc/systemd/system/dash-app.service`

   ```ini
   [Unit]
   Description=Dash Network Monitoring App
   After=network.target

   [Service]
   User=<your-username>
   WorkingDirectory=/path-to-repo/dash_app
   ExecStart=/path-to-repo/venv/bin/python3 /path-to-repo/dash_app/app.py
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```

2. **Enable the Dash App**:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable dash-app.service
   sudo systemctl start dash-app.service
   ```

---

## How It Works

1. **The Internet Check**:
   - The `check_net.sh` script runs every minute via the systemd timer.
   - It pings 3 target IPs. If all fail for 5 consecutive attempts, it triggers the modem power cycle via the Tapo smart plug.
   - Each result is logged in an SQLite database, and details like packet loss, latency, and success rate are recorded.

2. **The Power Cycle**:
   - The `power_cycle_p100.py` script communicates with a Tapo smart plug to power cycle the modem.
   - A cooldown period of 10 minutes ensures that consecutive power cycles do not happen too soon.

3. **The Dashboard**:
   - The Dash web app provides a graphical view of the network history. It shows metrics like success rates, latency, and packet loss.
   - You can manually trigger a power cycle from the dashboard by clicking the **Power Cycle NBN Plug** button.

---

## Additional Notes

- **Logs**: All logs are stored in the `logs/` directory, and can be useful for debugging.
- **Database**: The SQLite database (`internet_status.db`) stores all the ping data for the dashboard and logs.

---

## Future Enhancements

- Add more detailed metrics to the dashboard (e.g., real-time alerts).
- Support for additional smart plug brands or other power cycle devices.
- Incorporate email or SMS alerts for downtime notifications.

---

This setup should give you a complete monitoring and automation system for handling internet connectivity issues. Let me know if you need any additional details!
