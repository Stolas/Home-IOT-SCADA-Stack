# Home IoT SCADA Stack for openSUSE MicroOS

A comprehensive, containerized Home IoT SCADA (Supervisory Control and Data Acquisition) Stack built with Podman for resiliency and security on an openSUSE MicroOS host.

## Credits

This project was 99% developed by AI assistants (Gemini and GitHub Copilot). The remaining 1% was me being lazy and asking them to do all the work.

## Features

* **Host OS:** Optimized for **openSUSE MicroOS** (or other transactional OS) for enhanced stability and rollback capability.
* **Container Runtime:** Uses **Podman** for managing containers, networks, and persistent volumes.
* **Core Components:** Integrates **MQTT Broker** (Mosquitto), **Time Series Database** (InfluxDB), **Visualization** (Grafana), **Automation** (Node-RED), **NVR** (Frigate), and **Zigbee Gateway** (Zigbee2MQTT).
* **Reverse Proxy:** Nginx-based reverse proxy with hostname-based routing for all services, including openSUSE Cockpit web console.
* **Security:** Uses `create_secrets.sh` to generate unique, random, 64-character passwords/tokens for sensitive environment variables.
* **External Storage:** Includes logic to mount an **SMB/CIFS** share for Frigate recordings on the host machine.
* **Resilience:** The `startup.sh` script continues running even if individual service starts fail, providing a complete status report.

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

* **Operating System:** openSUSE MicroOS (or compatible transactional Linux distribution)
* **Container Runtime:** Podman (installed by default on MicroOS)
* **Package Dependencies:**
  * `cifs-utils` - Required for SMB/CIFS share mounting (only if using NVR/Frigate)
  * `sudo` - Required for mounting shares and system operations

### Optional Hardware

* **Zigbee Coordinator:** USB Zigbee adapter (e.g., CC2531, CC2652, ConBee II) for Zigbee2MQTT
* **Coral TPU:** Google Coral Edge TPU for accelerated object detection in Frigate (USB or M.2 versions) - only needed if using NVR

### Network Requirements

* **Local Network Access:** All services communicate on the local network
* **Port Availability:** Ensure the following ports are available:
  * 1883 (Mosquitto MQTT)
  * 3000 (Grafana)
  * 5000 (Frigate, configurable) - only if NVR is enabled
  * 8080 (Zigbee2MQTT Web UI)
  * 8086 (InfluxDB)
  * 1880 (Node-RED, configurable)

## Getting Started

Follow these steps to set up and run the entire stack.

### 1. Prerequisites (openSUSE MicroOS)

You must have the following installed on your host machine:

* **Podman:** Installed by default on MicroOS.
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

1. **IoT/SCADA Stack only** - Includes: Mosquitto (MQTT Broker), InfluxDB (Time Series Database), Grafana (Visualization), Node-RED (Automation), and Zigbee2MQTT (Zigbee Gateway)

2. **NVR only** - Includes: Frigate (Network Video Recorder for camera management and object detection)

3. **Both IoT/SCADA Stack + NVR** - Includes all services from both options above

**Memory Warning:** If you select option 2 (NVR only) or option 3 (Both) and your system has less than 8GB of RAM, the script will display a warning. You can still proceed, but Frigate may not perform optimally with insufficient memory.

**Automatic Secret Generation:** The script will automatically generate secure random passwords and tokens for all services. No manual secret generation is required.

**Manual Configuration Required:**

After the automatic setup, you must manually edit the `secrets.env` file to configure:

* `ZIGBEE_DEVICE_PATH` - Update with the path to your Zigbee adapter (e.g., `/dev/ttyACM0` or `/dev/serial/by-id/...`)
* `PODMAN_SOCKET_PATH` - Update for Node-RED integration. On modern Podman/MicroOS systems, this is typically:

```bash
PODMAN_SOCKET_PATH=/run/user/$(id -u)/podman/podman.sock
```

* Other site-specific variables like `TZ` (timezone), `SMB_SERVER`, `SMB_SHARE`, `SMB_USER` (if using NVR), etc.
* Nginx reverse proxy hostnames: `BASE_DOMAIN`, `GRAFANA_HOSTNAME`, `FRIGATE_HOSTNAME`, `NODERED_HOSTNAME`, `ZIGBEE2MQTT_HOSTNAME`, `COCKPIT_HOSTNAME`

### 3. Configure DNS/Hostnames (Optional but Recommended)

The stack includes an Nginx reverse proxy that allows you to access services via hostname instead of ports. This provides a cleaner, more professional access method (e.g., `http://grafana.home.local` instead of `http://192.168.1.100:3000`).

**Why hostname-based access?**
- Easier to remember (grafana.home.local vs 192.168.1.100:3000)
- More professional and organized
- Allows for potential future HTTPS/SSL certificate integration
- Simplifies bookmarking and sharing links

**Important:** DNS configuration and firewall/network setup are **out-of-scope** for this project. You are responsible for configuring your own network, DNS, and firewall rules. The options below are provided as guidance only.

**Option 1: Local DNS/Hosts File**

Add entries to your `/etc/hosts` file:

```
<host_ip> grafana.home.local
<host_ip> frigate.home.local
<host_ip> nodered.home.local
<host_ip> zigbee.home.local
<host_ip> cockpit.home.local
```

**Option 2: Local DNS Server**

Configure your router or DNS server to resolve these hostnames to your server's IP address. You can use wildcard DNS: `*.home.local -> <host_ip>`

**Option 3: Direct Port Access**

If you prefer not to configure hostnames, you can access services directly via their ports (see Access Points section below). This works immediately without any DNS configuration.

### 4. Configure Frigate (NVR Only)

If you selected the NVR option, you need to configure Frigate:

* Edit the `frigate_config.yml` file to define your cameras and settings.

### 5. Run the Stack

After completing the manual configuration in `secrets.env`, run the setup again:

```bash
./startup.sh
```

This will start all configured services based on your first-run choices.

### 5. Additional Operations

**Breakdown (Stop and Remove Containers)**

This stops and removes all active containers and unmounts the SMB share. Persistent volumes and the Podman network are kept intact.

```bash
./startup.sh breakdown
```

**Start a Single Service**

To troubleshoot or manually start a specific service:

```bash
./startup.sh start <service_name>
# Example: ./startup.sh start zigbee2mqtt
```

Available service names: `mosquitto`, `influxdb`, `zigbee2mqtt`, `frigate`, `grafana`, `nodered`.

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

To extend the stack with a new service, such as the **CODESYS Gateway**, you need to update two sections in the `startup.sh` script.

### Step 1: Update Service Definitions

Edit `startup.sh` and add the new service name to the arrays.

**Add to Service Status/Commands:** Define the `codesysgateway` container command in the `SERVICE_CMDS` map.

**CODESYS Gateway Example:** Assumes the standard port 12110 for the gateway.

```bash
# (Inside startup.sh, near line 240)
# Add the CODESYS Gateway command to the map:
SERVICE_CMDS[codesysgateway]="podman run -d --name codesysgateway --restart unless-stopped --network ${NETWORK_NAME} -p 12110:12110/udp -p 12111:12111/tcp docker.io/codesys/codesyscontrol-gateway-x64:latest"
```


**Add to Service List:** Add the name to the list of all services to ensure it is managed by the script.

```bash
# (Inside startup.sh, near line 250)
# Add 'codesysgateway' to the SERVICE_NAMES array:
SERVICE_NAMES=(mosquitto influxdb zigbee2mqtt frigate grafana nodered codesysgateway)
```


### Step 2: Run the Setup

After saving startup.sh, run the full setup script again. It will automatically stop existing containers, check volumes, and start the new codesysgateway container along with the others.

```bash
./startup.sh setup
```


The CODESYS Gateway container will now be started and managed by the startup.sh script, listening on the specified ports.

## Components and Access Points

| Component | Purpose | Access URL (Default Ports) | Notes |
|-----------|---------|----------------------------|-------|
| **Nginx** | Reverse Proxy | http://&lt;host_ip&gt; | Always included, provides hostname-based routing |
| **Grafana** | Data Visualization (SCADA UI) | http://grafana.&lt;BASE_DOMAIN&gt; or :3000 | IoT/SCADA modes only |
| **Frigate** | NVR and Object Detection | http://frigate.&lt;BASE_DOMAIN&gt; or :5000 | NVR modes only |
| **Node-RED** | Flow-Based Automation | http://nodered.&lt;BASE_DOMAIN&gt; or :1880 | IoT/SCADA modes only |
| **Zigbee2MQTT** | Zigbee Device Control | http://zigbee.&lt;BASE_DOMAIN&gt; or :8080 | IoT/SCADA modes only |
| **Cockpit** | openSUSE Web Console | http://cockpit.&lt;BASE_DOMAIN&gt; | Requires Cockpit enabled on host |
| **Mosquitto** | MQTT Broker | Port 1883 (Internal/External) | IoT/SCADA modes only |
| **InfluxDB** | Time-Series Database | Port 8086 (Internal/External) | IoT/SCADA modes only |

**Note:** Cockpit access via nginx requires Cockpit to be installed and running on the host. Install with:
```bash
sudo transactional-update pkg install cockpit
sudo systemctl enable --now cockpit.socket
```

## Project Structure

| File/Directory | Description |
|----------------|-------------|
| **startup.sh** | Main script for managing setup, breakdown, and service start. (Executable) |
| **create_secrets.sh** | Script to generate a secure secrets.env file from the example. (Executable) |
| **.stack_config** | Stores your stack configuration choice (IoT only, NVR only, or both). Auto-generated on first run. |
| **secrets.env-example** | Template file listing all necessary environment variables. |
| **secrets.env** | Your configuration file. Created by create_secrets.sh. (Keep this secret!) |
| **frigate_config.yml** | Configuration file for the Frigate NVR container. |
| **mosquitto/** | Directory for Mosquitto configuration files (e.g., mosquitto.conf). |
| **nginx/** | Directory for Nginx configuration files. nginx.conf is auto-generated based on stack type. |
| **.gitignore** | Ensures secrets.env and .stack_config are never committed to Git. |

## Troubleshooting

* **openSUSE MicroOS Updates:** Use `sudo transactional-update` for package management and system upgrades, followed by a reboot.

* **Container Logs:** If a container starts with a FAILURE status, check the logs for detailed errors:

```bash
podman logs <service_name>
```

* **Zigbee Adapter:** If zigbee2mqtt fails, ensure the `ZIGBEE_DEVICE_PATH` is correct and that the host user has the necessary permissions.
