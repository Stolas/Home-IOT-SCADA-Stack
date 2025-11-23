# Home IoT SCADA Stack for openSUSE MicroOS

A comprehensive, containerized Home IoT SCADA (Supervisory Control and Data Acquisition) Stack built with Podman for resiliency and security on an openSUSE MicroOS host.

## Credits

This project was 99% developed by AI assistants (Gemini and GitHub Copilot). The remaining 1% was me being lazy and asking them to do all the work.

## Features

* **Host OS:** Optimized for **openSUSE MicroOS** (or other transactional OS) for enhanced stability and rollback capability.
* **Container Runtime:** Uses **Podman** for managing containers, networks, and persistent volumes.
* **Core Components:** Integrates **MQTT Broker** (Mosquitto), **Time Series Database** (InfluxDB), **Visualization** (Grafana), **Automation** (Node-RED), **NVR** (Frigate with Double-Take facial recognition), and **Zigbee Gateway** (Zigbee2MQTT).
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
  * 3001 (Double-Take) - only if NVR is enabled
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

2. **NVR only** - Includes: Frigate (Network Video Recorder for camera management and object detection) and Double-Take (facial recognition)

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
* Nginx reverse proxy hostnames: `BASE_DOMAIN`, `GRAFANA_HOSTNAME`, `FRIGATE_HOSTNAME`, `NODERED_HOSTNAME`, `ZIGBEE2MQTT_HOSTNAME`, `COCKPIT_HOSTNAME`, `DOUBLETAKE_HOSTNAME`

### 3. Configure Frigate (NVR Only)

If you selected the NVR option, you need to configure Frigate:

* Edit the `frigate_config.yml` file to define your cameras and settings.

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

## Components and Access Points

| Component | Purpose | Access URL (Default Ports) | Notes |
|-----------|---------|----------------------------|-------|
| **Nginx** | Reverse Proxy | http://&lt;host_ip&gt; | Always included, provides hostname-based routing |
| **Grafana** | Data Visualization (SCADA UI) | http://grafana.&lt;BASE_DOMAIN&gt; or :3000 | IoT/SCADA modes only |
| **Frigate** | NVR and Object Detection | http://frigate.&lt;BASE_DOMAIN&gt; or :5000 | NVR modes only |
| **Double-Take** | Facial Recognition for Frigate | http://doubletake.&lt;BASE_DOMAIN&gt; or :3001 | NVR modes only |
| **Node-RED** | Flow-Based Automation | http://nodered.&lt;BASE_DOMAIN&gt; or :1880 | IoT/SCADA modes only |
| **Zigbee2MQTT** | Zigbee Device Control | http://zigbee.&lt;BASE_DOMAIN&gt; or :8080 | IoT/SCADA modes only |
| **Cockpit** | openSUSE Web Console | http://cockpit.&lt;BASE_DOMAIN&gt; | Requires Cockpit enabled on host |
| **Mosquitto** | MQTT Broker | Port 1883 (Internal/External) | IoT/SCADA modes only |
| **InfluxDB** | Time-Series Database | Port 8086 (Internal/External) | IoT/SCADA modes only |

**Note:** Cockpit is installed by default on openSUSE MicroOS. If for any reason it is not installed or running, you can install and enable it with:
```bash
sudo transactional-update pkg install cockpit
sudo reboot
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

* **nginx Permission Denied with SELinux (Podman Rootless):** On systems with SELinux enabled (e.g., openSUSE MicroOS, openSUSE Leap, Fedora, RHEL), you may encounter an error when the nginx container tries to read its configuration file:

```
nginx: [emerg] open() "/etc/nginx/nginx.conf" failed (13: Permission denied)
```

This occurs because SELinux prevents Podman from accessing files with incorrect security contexts. The nginx.conf file may have a context like `unconfined_u:object_r:user_home_t:s0` instead of the required `container_file_t` context.

**Automatic Fix (Recommended):**

The startup script now automatically checks and attempts to fix SELinux context issues. It also uses the `:Z` mount flag for automatic relabeling. Simply run:

```bash
./startup.sh
```

**Manual Diagnosis and Fix:**

Use the included diagnostic helper script:

```bash
./fix-nginx-selinux.sh          # Diagnose issues
./fix-nginx-selinux.sh --fix    # Attempt automatic fixes
```

**Manual SELinux Context Fix:**

If automatic fixes don't work, manually set the correct SELinux context:

```bash
sudo chcon -t container_file_t ./nginx/nginx.conf
```

**Verify the fix:**

```bash
ls -Z ./nginx/nginx.conf
```

The context should show `container_file_t` instead of `user_home_t`.

**File Permissions:**

Ensure the nginx.conf file has correct permissions (644) and is owned by your user:

```bash
chmod 644 ./nginx/nginx.conf
chown $(id -u) ./nginx/nginx.conf
```

**Understanding the :Z Mount Flag:**

The startup script mounts nginx.conf with the `:Z` flag:
```bash
-v ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro,Z
```

This flag tells Podman to automatically relabel the file with the appropriate SELinux context for exclusive use by this container. This should handle most SELinux issues automatically.

**Why This Happens:**

SELinux enforces mandatory access control. Files in your home directory typically have the `user_home_t` context, which containers cannot access. The `container_file_t` context (or automatic relabeling with `:Z`) allows Podman containers to read the file while maintaining security.

**Installing SELinux Tools (if needed):**

If SELinux tools are not available on openSUSE/SUSE systems:

```bash
sudo transactional-update pkg install setools-console
sudo reboot
```

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
