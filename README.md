oh lol fully replaced this with Ansible.



# Home IoT SCADA Stack for openSUSE Leap Micro

A comprehensive, containerized Home IoT SCADA (Supervisory Control and Data Acquisition) Stack built with Podman for resiliency and security on an openSUSE Leap Micro host.

## Credits

This project was 99% developed by AI assistants (Gemini and GitHub Copilot). The remaining 1% was me being lazy and asking them to do all the work.

## Features

* **Host OS:** Optimized for **openSUSE Leap Micro** (or other transactional OS) for enhanced stability and rollback capability.
* **Container Runtime:** Uses **Podman** for managing containers, networks, and persistent volumes.
* **Core Components:** Integrates **MQTT Broker** (Mosquitto), **Time Series Database** (InfluxDB), **Visualization** (Grafana), **HMI/SCADA** (FUXA), **Automation** (Node-RED), **Metrics Collection** (Telegraf), **NVR** (Frigate with Double-Take facial recognition), and **Zigbee Gateway** (Zigbee2MQTT).
* **Reverse Proxy:** Nginx-based reverse proxy with hostname-based routing for all services, including openSUSE Cockpit web console. Nginx configuration is dynamically generated based on running services to prevent startup failures.
* **Security:** Uses `create_secrets.sh` to generate unique, random, 64-character passwords/tokens for sensitive environment variables.
* **External Storage:** Includes logic to mount an **SMB/CIFS** share for Frigate recordings on the host machine.
* **Resilience:** The `startup.sh` script continues running even if individual service starts fail, providing a complete status report. Nginx automatically adapts to only proxy running services.
* **Automatic Podman Socket Detection:** Node-RED automatically detects and uses the podman socket for docker/container integration. If the socket is unavailable, Node-RED starts in standalone mode without crashing.

## Stack Components

### Core Services

* **FUXA** - Web-based HMI/SCADA interface providing visual, floorplan-based control panels for IoT devices. Accessible on port 1881.
* **Telegraf** - Metrics collection agent that aggregates system metrics and syslog data from network devices (port 514/udp), forwarding to InfluxDB for storage and analysis.
* **Mosquitto** - Lightweight MQTT broker for publish/subscribe messaging between IoT devices.
* **InfluxDB** - High-performance time-series database optimized for sensor data and metrics.
* **Grafana** - Advanced data visualization and monitoring dashboards with alerting capabilities.
* **Node-RED** - Visual flow-based programming tool for automation logic and event processing.
* **Zigbee2MQTT** - Bridge for Zigbee devices to communicate via MQTT (requires USB Zigbee adapter).

### NVR Services (Optional)

* **Frigate** - Network Video Recorder with real-time AI object detection for camera feeds.
* **CompreFace** - AI-powered facial recognition API for identifying people in video frames.
* **Double-Take** - Facial recognition integration that analyzes Frigate events using CompreFace.
* **go2rtc** - RTSP stream converter for low-latency camera viewing in Grafana and browsers.

### Infrastructure Services

* **Nginx** - Reverse proxy with dynamic hostname-based routing for all web services.

## System Requirements

### Hardware Requirements

* **CPU:** Multi-core processor (4+ cores recommended for optimal performance)
* **RAM:** 
  * IoT/SCADA Stack only: Minimum 4GB RAM
  * NVR (Frigate) only: Minimum 8GB RAM required
  * Both IoT/SCADA Stack + NVR: Minimum 8GB RAM required
  * Note: The system will display a warning if you select NVR mode with less than 8GB RAM, but will allow you to proceed
* **Storage:** 
  * Minimum 32GB for OS and containers
  * Additional storage for Frigate recordings (external NAS/SMB share recommended) if NVR is enabled
* **Network:** Ethernet connection recommended for stability
* **USB Ports:** At least one available USB port for Zigbee coordinator device

### Software Requirements

* **Operating System:** openSUSE Leap Micro (or compatible transactional Linux distribution)
* **Container Runtime:** Podman (installed by default on Leap Micro)
* **Package Dependencies:**
  * `cifs-utils` - Required for SMB/CIFS share mounting (only if using NVR/Frigate)
  * `sudo` - Required for mounting shares and system operations

### Optional Hardware

* **Zigbee Coordinator:** USB Zigbee adapter (e.g., CC2531, CC2652, ConBee II) for Zigbee2MQTT
* **Coral TPU:** Google Coral Edge TPU for accelerated object detection in Frigate (USB or M.2 versions) - only needed if using NVR

### Network Requirements

* **Local Network Access:** All services communicate on the local network
* **Port Availability:** Ensure the following ports are available:
  * 514 (Syslog UDP for Telegraf) - for log ingestion from network devices
  * 1880 (Node-RED, configurable)
  * 1881 (FUXA HMI/SCADA)
  * 1883 (Mosquitto MQTT)
  * 1984 (go2rtc Web UI) - for RTSP stream conversion (Fixes #15)
  * 3000 (Grafana)
  * 3001 (Double-Take) - only if NVR is enabled
  * 5000 (Frigate, configurable) - only if NVR is enabled
  * 8000 (CompreFace) - only if NVR is enabled (Fixes #5)
  * 8080 (Zigbee2MQTT Web UI)
  * 8086 (InfluxDB)
  * 8554 (go2rtc RTSP server) - for re-streaming camera feeds (Fixes #15)
  * 8555 (go2rtc WebRTC server) - for low-latency browser playback (Fixes #15)

## Getting Started

Follow these steps to set up and run the entire stack.

### 1. Prerequisites (openSUSE Leap Micro)

You must have the following installed on your host machine:

* **Podman:** Installed by default on Leap Micro.
* **cifs-utils:** Required only if you plan to use the NVR (Frigate) with SMB share mounting. Use `transactional-update` to install this package permanently:

```bash
sudo transactional-update pkg install cifs-utils
sudo reboot
```

* **sudo privileges:** Required for mounting the SMB share (if using NVR).

### 2. First-Run Setup

On your first run, the startup script will guide you through an interactive configuration:

**Run the startup script:**

```bash
chmod +x startup.sh
./startup.sh
```

**Configuration Options:**

The script will ask you to choose between:

1. **IoT/SCADA Stack only** - Includes: Mosquitto (MQTT Broker), InfluxDB (Time Series Database), Grafana (Visualization), FUXA (HMI/SCADA), Node-RED (Automation), Telegraf (Metrics Collection), and Zigbee2MQTT (Zigbee Gateway)

2. **NVR only** - Includes: Frigate (Network Video Recorder for camera management and object detection) and Double-Take (facial recognition)

3. **Both IoT/SCADA Stack + NVR** - Includes all services from both options above

**Memory Warning:** If you select option 2 (NVR only) or option 3 (Both) and your system has less than 8GB of RAM, the script will display a warning. You can still proceed, but Frigate may not perform optimally with insufficient memory.

**Automatic Secret Generation:** The script will automatically generate secure random passwords and tokens for all services. No manual secret generation is required.

**Manual Configuration Required:**

After the automatic setup, you must manually edit the `secrets.env` file to configure:

* `ZIGBEE_DEVICE_PATH` - Update with the path to your Zigbee adapter (e.g., `/dev/ttyACM0` or `/dev/serial/by-id/...`)
* `PODMAN_SOCKET_PATH` - **OPTIONAL** for Node-RED integration. The startup script automatically detects the podman socket for the current user. If you need to specify a custom path, uncomment and update this variable. Common paths:
  * Rootless (recommended): `/run/user/$(id -u)/podman/podman.sock`
  * Rootful: `/run/podman/podman.sock`
  * **Note**: If the socket is not found, Node-RED will still start successfully but without podman/docker integration capabilities.
* Other site-specific variables like `TZ` (timezone), `SMB_SERVER`, `SMB_SHARE`, `SMB_USER` (if using NVR), etc.
* Nginx reverse proxy hostnames: `BASE_DOMAIN`, `GRAFANA_HOSTNAME`, `FRIGATE_HOSTNAME`, `NODERED_HOSTNAME`, `ZIGBEE2MQTT_HOSTNAME`, `COCKPIT_HOSTNAME`, `DOUBLETAKE_HOSTNAME`

### 3. Configure Frigate (NVR Only)

If you selected the NVR option, you need to configure Frigate:

* Edit the `frigate_config.yml` file to define your cameras and settings.

### 3a. Configure CompreFace and Double-Take (NVR Only - Fixes #5)

CompreFace provides face recognition capabilities for Double-Take, enabling facial detection in your NVR setup.

**Automatic Configuration:**

The `COMPREFACE_API_KEY` is automatically generated by `create_secrets.sh`. This key is used for secure communication between Double-Take and CompreFace.

**Double-Take Configuration:**

After the stack is running, configure Double-Take to use CompreFace:

1. Access Double-Take at `http://doubletake.<BASE_DOMAIN>` or `http://<host_ip>:3001`
2. Navigate to Settings → Detectors
3. Add CompreFace as a detector with:
   - **URL:** `http://compreface:8000`
   - **API Key:** Use the `COMPREFACE_API_KEY` from your `secrets.env` file
4. Configure face recognition settings as needed

**CompreFace Face Training:**

To train CompreFace to recognize faces:

1. Access CompreFace at `http://compreface.<BASE_DOMAIN>` or `http://<host_ip>:8000`
2. Create a new application or use the existing one
3. Upload reference images for face recognition
4. Double-Take will automatically use these trained faces for detection

### 4. Run the Stack

After completing the manual configuration in `secrets.env`, run the setup again:

```bash
./startup.sh
```

This will start all configured services based on your first-run choices.

**Container Auto-Restart on Reboot:**

All containers are configured with the `--restart unless-stopped` policy. This means:
* Containers will automatically restart if they crash or exit unexpectedly
* Containers will automatically start when the system reboots (as long as the Podman service/socket is enabled)
* Containers will NOT restart if you manually stop them with `podman stop` or `./startup.sh breakdown`

To enable Podman to start containers at boot, ensure the Podman service is enabled. On most systems, this is automatic, but you can verify with:

```bash
systemctl --user status podman.socket
```

If it's not enabled, you can enable it with:

```bash
systemctl --user enable podman.socket
systemctl --user start podman.socket
```

**Running as a Systemd Service (Recommended for Persistent Operation):**

For production deployments where you want the stack to automatically start on boot and persist even after SSH disconnection, you can install the stack as a systemd user service:

```bash
chmod +x install-service.sh
./install-service.sh install
```

This will:
* Install the stack as a systemd user service
* Enable automatic startup on system boot
* Enable user lingering so the service persists after SSH logout
* Ensure containers continue running even when you disconnect

**Service Management Commands:**

```bash
# Check service status
./install-service.sh status
# or
systemctl --user status iot-scada-stack.service

# View live logs
./install-service.sh logs
# or
journalctl --user -u iot-scada-stack.service -f

# Restart the service
systemctl --user restart iot-scada-stack.service

# Stop the service
systemctl --user stop iot-scada-stack.service

# Uninstall the service (containers remain manageable via startup.sh)
./install-service.sh uninstall
```

**Note:** The systemd service approach is the **recommended method** for ensuring containers persist across SSH sessions and system reboots. Without it, containers started in an SSH session may be terminated when the session ends, depending on your system configuration.

### 5. Additional Operations

**Breakdown (Stop and Remove Containers)**

This stops and removes all active containers and unmounts the SMB share. Persistent volumes and the Podman network are kept intact.

```bash
./startup.sh breakdown
```

**Nuke (Complete Data Removal) - DESTRUCTIVE**

**WARNING: This is a destructive operation that CANNOT be undone!**

The `nuke` option completely removes all containers AND all persistent volumes, effectively resetting the stack to a clean state. This will permanently delete:

* All container data
* All volumes (mosquitto_data, frigate_data, nodered_data, z2m_data, grafana_data, influxdb_data, nginx_cache, doubletake_data)
* All stored configurations
* All recordings (Frigate)
* All time-series data (InfluxDB)
* All Grafana dashboards and settings
* All Node-RED flows

The script will prompt for confirmation (you must type `YES` in all caps) before proceeding.

```bash
./startup.sh nuke
```

Use this option when you want to:
* Start completely fresh with new data
* Remove all data before decommissioning the system
* Troubleshoot issues by resetting to factory defaults

After running `nuke`, you can start fresh by running `./startup.sh` again.

**Start a Single Service**

To troubleshoot or manually start a specific service:

```bash
./startup.sh start <service_name>
# Example: ./startup.sh start zigbee2mqtt
```

Available service names: `mosquitto`, `influxdb`, `zigbee2mqtt`, `frigate`, `grafana`, `nodered`, `nginx`, `doubletake`.

**Changing Stack Configuration**

If you want to change between IoT/SCADA only and IoT/SCADA + NVR modes:

1. Stop all running containers:
   ```bash
   ./startup.sh breakdown
   ```

2. Delete the configuration file:
   ```bash
   rm .stack_config
   ```

3. Run the setup again to go through the configuration wizard:
   ```bash
   ./startup.sh
   ```

## Adding New Services (Example: CODESYS Gateway)

To extend the stack with a new service, such as the **CODESYS Gateway**, you need to update the `startup.sh` script. This example shows how to add any additional service to the stack.

### Step 1: Update Service Definitions in startup.sh

Open `startup.sh` and locate the service definitions section (around line 492-500).

**Add the Service Command:**

Add your service to the `SERVICE_CMDS` associative array. Each service needs a unique name and a complete podman run command.

```bash
# Add after line 499, before SERVICE_NAMES
SERVICE_CMDS[codesysgateway]="podman run -d --name codesysgateway --restart unless-stopped --network ${NETWORK_NAME} -p 12110:12110/udp -p 12111:12111/tcp docker.io/codesys/codesyscontrol-gateway-x64:latest"
```

**Add to Service List:**

Add the service name to the `SERVICE_NAMES` array (line 500):

```bash
# Update this line:
SERVICE_NAMES=(mosquitto influxdb zigbee2mqtt frigate grafana nodered nginx doubletake codesysgateway)
```

**Important Notes:**
- Custom services like CODESYS Gateway will always start regardless of stack configuration (IoT/SCADA/NVR mode)
- If you want the service to be conditional based on stack type, you'll need to modify the service startup logic in the `setup_system()` function
- Make sure to use `${NETWORK_NAME}` to connect the service to the same Podman network as other services

### Step 2: (Optional) Add to Breakdown Function

If you want the service to be properly cleaned up when running `./startup.sh breakdown`, add it to the `CONTAINER_NAMES` array in the `breakdown_containers_only()` function (around line 445):

```bash
CONTAINER_NAMES=("mosquitto" "zigbee2mqtt" "frigate" "influxdb" "grafana" "nodered" "nginx" "doubletake" "codesysgateway")
```

### Step 3: (Optional) Configure Nginx Proxy

If you want hostname-based access to your service via the nginx reverse proxy, you'll need to:

1. Add a hostname variable to `secrets.env`:
   ```bash
   CODESYS_HOSTNAME=codesys
   ```

2. Read the variable in startup.sh (around line 69):
   ```bash
   CODESYS_HOSTNAME=$(read_var CODESYS_HOSTNAME)
   ```

3. Add a server block to the `generate_nginx_config()` function (around line 203) to proxy requests to your service.

### Step 4: Run the Setup

After saving your changes to `startup.sh`, run the setup script:

```bash
./startup.sh
```

The script will automatically stop existing containers and start all services including your new CODESYS Gateway container.

**Verify the Service:**

Check that the service is running:

```bash
podman ps | grep codesysgateway
podman logs codesysgateway
```

## Grafana Configuration

### Public Dashboard Access

By default, Grafana requires authentication to view dashboards. If you want to enable public (anonymous) access to dashboards without requiring login credentials, you can configure this in the `secrets.env` file.

**Enable Public Access:**

Edit the `secrets.env` file and set the following variables:

```bash
# Enable anonymous (public) access to dashboards
GRAFANA_ANONYMOUS_ENABLED=true

# Organization name for anonymous users (default: Main Org.)
GRAFANA_ANONYMOUS_ORG_NAME=Main Org.

# Role for anonymous users: Viewer, Editor, or Admin (default: Viewer)
# RECOMMENDED: Keep as 'Viewer' to prevent unauthorized modifications
GRAFANA_ANONYMOUS_ORG_ROLE=Viewer
```

After updating these settings, restart the Grafana container or the entire stack:

```bash
./startup.sh start grafana
# or restart the entire stack
./startup.sh
```

**Security Considerations:**

**Important:** Enabling public access means anyone who can reach your Grafana instance can view your dashboards without authentication.

* **Recommended for:** Home networks, isolated networks, or trusted environments
* **Not recommended for:** Internet-facing deployments or untrusted networks
* **Best practices:**
  * Keep `GRAFANA_ANONYMOUS_ORG_ROLE` set to `Viewer` (read-only)
  * Use network-level security (firewall, VPN) to restrict access
  * Regularly review what data is exposed in your dashboards
  * Consider using Grafana's built-in folder permissions for sensitive dashboards
  * Monitor access logs for unexpected activity

**Dashboard Sharing Options:**

Even without enabling anonymous access, Grafana offers several sharing options:

* **Snapshot sharing:** Create a static snapshot of a dashboard that can be shared via a link
* **Dashboard export:** Export dashboards as JSON for sharing or backup
* **Role-based access:** Create users with different permission levels (Viewer, Editor, Admin)
* **Organization isolation:** Use multiple organizations within Grafana for different user groups

For more information on Grafana security and sharing options, refer to the [official Grafana documentation](https://grafana.com/docs/grafana/latest/administration/security/).

**Step-by-Step Example:**

1. **Edit your secrets.env file:**
   ```bash
   nano secrets.env
   ```

2. **Find the Grafana public access section and modify it:**
   ```bash
   # Change from:
   GRAFANA_ANONYMOUS_ENABLED=false
   
   # To:
   GRAFANA_ANONYMOUS_ENABLED=true
   ```

3. **Save the file and restart Grafana:**
   ```bash
   ./startup.sh start grafana
   ```

4. **Test public access:**
   - Open an incognito/private browser window
   - Navigate to your Grafana URL (e.g., `http://grafana.home.local` or `http://<host_ip>:3000`)
   - You should now be able to view dashboards without logging in
   - To access admin features, click "Sign in" and use your admin credentials

5. **Verify it's working:**
   - Anonymous users will see dashboards but won't have edit permissions (if using Viewer role)
   - The Grafana UI will show a "Sign in" button in the top right for anonymous users
   - Admin users can still log in to create/edit dashboards

## Node-RED Configuration (Fixes #14)

Node-RED provides flow-based automation for the IoT/SCADA stack. It includes support for MQTT and syslog ingestion.

### MQTT Integration

Node-RED can communicate with the Mosquitto MQTT broker on the internal network. To configure MQTT in your flows:

1. Add an **mqtt in** or **mqtt out** node to your flow
2. Configure the broker connection:
   - **Server:** `mosquitto` (internal container hostname)
   - **Port:** `1883`
   - **Username:** Your `MQTT_USER` from `secrets.env`
   - **Password:** Your `MQTT_PASSWORD` from `secrets.env`

**Example MQTT Flow:**
```json
[{"id":"mqtt-broker","type":"mqtt-broker","name":"Mosquitto","broker":"mosquitto","port":"1883","clientid":"","autoConnect":true,"usetls":false,"protocolVersion":"4","keepalive":"60","cleansession":true}]
```

### Syslog Log Ingestion

The stack exposes port 514 (UDP and TCP) for syslog log ingestion. This allows network devices (routers, switches, servers, etc.) to send logs to Node-RED for processing, aggregation, and visualization.

**Installing node-red-contrib-syslog-input:**

1. Access Node-RED at `http://nodered.<BASE_DOMAIN>` or `http://<host_ip>:1880`
2. Go to **Menu → Manage palette → Install**
3. Search for `node-red-contrib-syslog-input`
4. Click **Install**

**Setting up Syslog Input Flow:**

1. Add a **syslog input** node to your flow
2. Configure the node:
   - **Port:** `514`
   - **Protocol:** `UDP` or `TCP` (depending on your device configuration)
3. Connect to processing nodes (function, debug, dashboard, etc.)

**Example Syslog Flow:**
```json
[{"id":"syslog-in","type":"syslog-input","name":"Syslog Input","port":"514","protocol":"udp","wires":[["debug-node"]]},{"id":"debug-node","type":"debug","name":"Debug","active":true,"tosidebar":true,"console":false,"tostatus":false,"complete":"payload","targetType":"msg","statusVal":"","statusType":"auto"}]
```

**Configuring Network Devices:**

Configure your network devices to send syslog messages to the Home-IOT-SCADA-Stack host IP address on port 514. Refer to your device's documentation for specific syslog configuration instructions.

## go2rtc and Camera Streams in Grafana (Fixes #15)

go2rtc is included in all stack profiles (IoT/SCADA, NVR, and combined) to enable displaying camera RTSP streams in Grafana dashboards.

### go2rtc Configuration

1. Access go2rtc at `http://go2rtc.<BASE_DOMAIN>` or `http://<host_ip>:1984`
2. Configure your camera streams in the go2rtc web interface or by creating a config file

**Example go2rtc configuration (create in the go2rtc_data volume):**
```yaml
streams:
  camera1:
    - rtsp://user:password@192.168.1.100:554/stream1
  camera2:
    - rtsp://user:password@192.168.1.101:554/stream1
```

### Available go2rtc Ports

* **Port 1984:** go2rtc Web UI and API
* **Port 8554:** RTSP server (re-streams converted streams)
* **Port 8555:** WebRTC server (for browser playback)

### Embedding Camera Streams in Grafana

To display camera streams in Grafana dashboards:

1. **Install the HTML panel plugin:**
   - Go to Grafana → Configuration → Plugins
   - Search for "HTML" or "Text" panel
   - Install a suitable HTML panel plugin (e.g., "marcusolsson-dynamictext-panel")

2. **Create a dashboard panel with embedded stream:**
   ```html
   <iframe 
     src="http://go2rtc.<BASE_DOMAIN>/stream.html?src=camera1" 
     width="100%" 
     height="400" 
     frameborder="0">
   </iframe>
   ```

3. **Alternative: Use WebRTC stream URL:**
   ```
   http://go2rtc.<BASE_DOMAIN>/api/ws?src=camera1
   ```

**Example Grafana Dashboard JSON:**
```json
{
  "panels": [
    {
      "title": "Camera 1",
      "type": "marcusolsson-dynamictext-panel",
      "options": {
        "content": "<iframe src='http://go2rtc.home.local/stream.html?src=camera1' width='100%' height='400' frameborder='0'></iframe>"
      }
    }
  ]
}
```

### Stream URLs Reference

| Format | URL Pattern | Use Case |
|--------|-------------|----------|
| WebRTC | `http://go2rtc:1984/stream.html?src=<stream_name>` | Low latency browser playback |
| HLS | `http://go2rtc:1984/api/stream.m3u8?src=<stream_name>` | Wide compatibility |
| RTSP | `rtsp://go2rtc:8554/<stream_name>` | Re-stream to other applications |

## Components and Access Points

| Component | Purpose | Access URL (Default Ports) | Notes |
|-----------|---------|----------------------------|-------|
| **Nginx** | Reverse Proxy | http://&lt;host_ip&gt; | Always included, provides hostname-based routing |
| **Grafana** | Data Visualization (SCADA UI) | http://grafana.&lt;BASE_DOMAIN&gt; or :3000 | IoT/SCADA modes only |
| **go2rtc** | RTSP to WebRTC/HLS Converter | http://go2rtc.&lt;BASE_DOMAIN&gt; or :1984 | All modes, for camera streams in Grafana (Fixes #15) |
| **Frigate** | NVR and Object Detection | http://frigate.&lt;BASE_DOMAIN&gt; or :5000 | NVR modes only |
| **Double-Take** | Facial Recognition for Frigate | http://doubletake.&lt;BASE_DOMAIN&gt; or :3001 | NVR modes only |
| **CompreFace** | Face Recognition API | http://compreface.&lt;BASE_DOMAIN&gt; or :8000 | NVR modes only, backend for Double-Take (Fixes #5) |
| **Node-RED** | Flow-Based Automation | http://nodered.&lt;BASE_DOMAIN&gt; or :1880 | IoT/SCADA modes only |
| **Zigbee2MQTT** | Zigbee Device Control | http://zigbee.&lt;BASE_DOMAIN&gt; or :8080 | IoT/SCADA modes only |
| **Cockpit** | openSUSE Web Console | http://cockpit.&lt;BASE_DOMAIN&gt; | Requires Cockpit enabled on host |
| **Mosquitto** | MQTT Broker | Port 1883 (Internal/External) | IoT/SCADA modes only |
| **InfluxDB** | Time-Series Database | Port 8086 (Internal/External) | IoT/SCADA modes only |

**Note:** Cockpit is installed by default on openSUSE Leap Micro. If for any reason it is not installed or running, you can install and enable it with:
```bash
sudo transactional-update pkg install cockpit
sudo reboot
sudo systemctl enable --now cockpit.socket
```

## Project Structure

| File/Directory | Description |
|----------------|-------------|
| **startup.sh** | Main script for managing setup, breakdown, and service start. (Executable) |
| **install-service.sh** | Helper script to install/uninstall the stack as a systemd user service for persistent operation. (Executable) |
| **iot-scada-stack.service.template** | Systemd service template file used by install-service.sh. |
| **create_secrets.sh** | Script to generate a secure secrets.env file from the example. (Executable) |
| **.stack_config** | Stores your stack configuration choice (IoT only, NVR only, or both). Auto-generated on first run. |
| **secrets.env-example** | Template file listing all necessary environment variables including Grafana public access settings. |
| **secrets.env** | Your configuration file. Created by create_secrets.sh. (Keep this secret!) |
| **frigate_config.yml** | Configuration file for the Frigate NVR container. |
| **mosquitto/** | Directory for Mosquitto configuration files (e.g., mosquitto.conf). |
| **nginx/** | Directory for Nginx configuration files. nginx.conf is auto-generated based on stack type. |
| **.gitignore** | Ensures secrets.env and .stack_config are never committed to Git. |

## Security

This stack implements multiple security layers to protect your home IoT infrastructure:

### Credential Management
* **Automatic Secret Generation:** The `create_secrets.sh` script generates unique, random, 64-character passwords/tokens for all sensitive environment variables (MQTT, InfluxDB, Grafana, SMB).
* **Secrets File Protection:** The `secrets.env` file is excluded from version control via `.gitignore` to prevent accidental credential exposure.

### Network Security
* **Container Isolation:** All services run in isolated Podman containers on a dedicated internal network (`iot_net`).
* **Hostname-Based Routing:** Nginx reverse proxy provides hostname-based access to services, reducing direct port exposure.
* **Rootless Containers:** The stack is designed to run with rootless Podman for enhanced security isolation.

### Access Control
* **Grafana Authentication:** By default, Grafana requires authentication. Anonymous access can be optionally enabled for trusted networks only.
* **MQTT Authentication:** Mosquitto broker supports username/password authentication for MQTT clients.
* **Service Segmentation:** Services are organized by stack type (IoT/SCADA, NVR) allowing deployment of only necessary components.

### Best Practices
* Keep your `secrets.env` file secure and never commit it to version control.
* Regularly update container images for security patches.
* Use network-level security (firewall, VPN) to restrict external access.
* Review Grafana dashboard permissions when enabling public access.
* Monitor container logs for suspicious activity.

For more information on specific service security configurations, see the [Grafana Configuration](#grafana-configuration) section.

## Troubleshooting

* **openSUSE Leap Micro Updates:** Use `sudo transactional-update` for package management and system upgrades, followed by a reboot.

* **Container Logs:** If a container starts with a FAILURE status, check the logs for detailed errors:

```bash
podman logs <service_name>
```

* **Zigbee Adapter:** If zigbee2mqtt fails, ensure the `ZIGBEE_DEVICE_PATH` is correct and that the host user has the necessary permissions.

* **Nginx Dynamic Configuration:** The nginx reverse proxy is configured dynamically based on which services are actually running. This prevents nginx startup failures when some services are not configured or fail to start. During startup:
  1. All backend services are started first
  2. The system waits 3 seconds for services to stabilize
  3. Running services are detected using `podman ps`
  4. Nginx configuration is generated with only the running services
  5. Nginx starts last as the reverse proxy

This means if a service like zigbee2mqtt is not configured or fails to start, nginx will automatically exclude it from the configuration and start successfully. You'll see output like:

```
Waiting 3 seconds for services to stabilize...
Checking which services are running and generating nginx configuration...
  [ok] Grafana is running - adding to nginx config
  [ok] Node-RED is running - adding to nginx config
  [INFO] Zigbee2MQTT is not running - skipping from nginx config
Starting nginx (reverse proxy) after all upstream services...
```

* **Grafana Public Access Not Working:** If you've enabled anonymous access (`GRAFANA_ANONYMOUS_ENABLED=true`) but visitors are still prompted to log in:
  1. Verify the variables are correctly set in `secrets.env`
  2. Restart the Grafana container: `./startup.sh start grafana`
  3. Check Grafana logs for errors: `podman logs grafana`
  4. Ensure you're using the correct Grafana URL (via nginx proxy or direct port 3000)
  5. Clear your browser cache and cookies for the Grafana site

* **Systemd Service Issues:** If the systemd service isn't starting or containers stop after SSH logout:
  1. Check service status: `./install-service.sh status`
  2. View service logs: `./install-service.sh logs`
  3. Verify user lingering is enabled: `loginctl show-user $USER | grep Linger=`
  4. If lingering shows "Linger=no", enable it: `sudo loginctl enable-linger $USER`
  5. Check podman socket is running: `systemctl --user status podman.socket`
  6. Reload systemd if you manually edited the service file: `systemctl --user daemon-reload`

* **Containers Stop When SSH Session Ends:** This happens when containers are started without proper persistence:
  1. **Recommended solution:** Use the systemd service: `./install-service.sh install`
  2. **Alternative:** Enable user lingering manually: `sudo loginctl enable-linger $USER`
  3. **Verify:** Check lingering status: `loginctl show-user $USER | grep Linger=`
  4. After enabling lingering, containers started with `--restart unless-stopped` will persist

* **Port 80 Permission Error (Rootless Podman):** If you encounter a permission error when starting the nginx container (attempting to bind to port 80), this is because ports below 1024 are considered "privileged ports" and normally require root access. When running Podman in rootless mode (as a non-root user), you may see an error like:

```
Error: rootlessport cannot expose privileged port 80, you can add 'net.ipv4.ip_unprivileged_port_start=80' to /etc/sysctl.conf (currently 1024), or choose a larger port number (>= 1024)
```

**Workaround Steps:**

1. Edit the sysctl configuration file to allow unprivileged users to bind to port 80:
   ```bash
   sudo nano /etc/sysctl.conf
   ```

2. Add the following line at the end of the file:
   ```
   net.ipv4.ip_unprivileged_port_start=80
   ```

3. Apply the changes:
   ```bash
   sudo sysctl -p
   ```

4. Retry starting the container:
   ```bash
   ./startup.sh
   ```

**Security Implications:**

Allowing unprivileged users to bind to privileged ports (ports < 1024) reduces a traditional security boundary in Unix-like systems. Historically, only root could bind to these ports, which prevented non-root processes from impersonating system services.

**When to use this workaround:**
* [OK] **Recommended for:** Single-user systems, home lab environments, personal IoT setups
* [OK] **Safe when:** You trust all users on the system and understand the security tradeoff
* [WARNING] **Use with caution in:** Multi-user environments or systems where additional security isolation is needed
* [X] **Not recommended for:** Production servers with untrusted users or strict security requirements

**Alternative approaches:**
* Run nginx on a higher port (e.g., 8080) and use port forwarding at the router/firewall level
* Use a reverse proxy running as root that forwards to your rootless containers
* Run containers with `podman` in rootful mode (requires root privileges)
