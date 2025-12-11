# Home IOT SCADA Stack Architecture

A comprehensive guide to the architecture, components, and deployment of the Home IOT SCADA Stack.

## 1. Project Overview: The SCADA Stack

### Goal

This project aims to build a modern, open-source, event-driven SCADA (Supervisory Control and Data Acquisition) system for smart home control. The stack prioritizes a visual, non-coding, floorplan-based Human-Machine Interface (HMI) that empowers users to monitor and control their home automation systems through an intuitive graphical interface.

### Architecture Principle: Best-of-Breed Approach

The stack follows a **"Best-of-Breed"** architecture philosophy, selecting specialized components that excel in their specific domains:

- **Real-Time Control**: FUXA provides visual HMI and SCADA capabilities with floorplan-based controls
- **Analytics**: Grafana delivers powerful data visualization and monitoring dashboards
- **AI & Computer Vision**: Frigate and CompreFace handle video surveillance, object detection, and facial recognition
- **Logic & Automation**: Node-RED enables visual flow-based programming for automation logic
- **Data Collection**: Telegraf aggregates system metrics and syslog data from network devices
- **Time-Series Storage**: InfluxDB stores metrics and sensor data efficiently
- **Messaging**: Mosquitto MQTT broker provides reliable event-driven communication

By combining best-in-class tools, the stack achieves flexibility, maintainability, and powerful functionality without vendor lock-in.

### Deployment

The entire stack is deployed using **Podman containers** managed by the `startup.sh` shell script. This approach:

- **Automated Management**: Single script handles container lifecycle, network creation, and volume management
- **Resilient Operation**: Script continues even if individual services fail, providing complete status reporting
- **Flexibility**: Easy to enable/disable services based on your needs (IoT/SCADA only, NVR only, or both)
- **Supports Rootless Mode**: Enhanced security with rootless Podman execution
- **SELinux Friendly**: Properly configured volume mounts and security contexts

Use `./startup.sh` to start the entire stack. The script will guide you through initial configuration on first run.

## 2. System Architecture & Component Roles

The SCADA stack is organized into functional layers. Each component serves a specific role and communicates with others through well-defined interfaces.

| Layer | Component | Container Name (Suggested) | Primary Role & Function | Key Data Connection |
|-------|-----------|---------------------------|------------------------|---------------------|
| **HMI/SCADA** | FUXA | `fuxa` | Web-based HMI/SCADA editor and runtime. Provides visual, floorplan-based interface for monitoring and controlling IoT devices. Non-coding approach to building dashboards and control panels. | MQTT topics (via Mosquitto), OPC UA, Modbus, HTTP APIs |
| **Visualization** | Grafana | `grafana` | Advanced data visualization and monitoring dashboards. Display time-series data, create alerts, and visualize metrics from InfluxDB. Supports camera feeds via go2rtc integration. | InfluxDB API (http://influxdb:8086), MQTT data sources, go2rtc streams |
| **Time-Series Database** | InfluxDB | `influxdb` | High-performance time-series database for storing sensor data, metrics, and telemetry. Optimized for write-heavy IoT workloads with efficient compression. | InfluxDB Line Protocol API (port 8086), Telegraf writes, Grafana queries |
| **Automation Logic** | Node-RED | `node-red` | Visual flow-based programming for automation logic and event processing. Connect IoT devices, APIs, and services with drag-and-drop nodes. Includes syslog listener on UDP/514. | MQTT broker (mosquitto:1883), InfluxDB API, HTTP APIs, Syslog UDP/514 |
| **Video Surveillance (NVR)** | Frigate | `frigate` | Network Video Recorder with real-time object detection using AI. Monitors camera feeds, detects objects (people, vehicles, animals), and triggers events. Supports hardware acceleration. | RTSP camera streams, MQTT events to mosquitto, recordings to local storage |
| **Face Recognition** | CompreFace | `compreface` | AI-powered facial recognition service. Trains on uploaded face images and provides recognition API for identifying people in video frames from Frigate/Double-Take. | REST API on port 8000, used by Double-Take and potentially Frigate |
| **Metrics Collection** | Telegraf | `telegraf` | Metrics collection agent and data aggregator. Collects system metrics, network device syslog data, and IoT telemetry. Forwards data to InfluxDB for storage and analysis. | Syslog UDP/514 input, SNMP, system metrics → InfluxDB API output |
| **Message Broker** | Mosquitto | `mosquitto` | Lightweight MQTT broker for publish/subscribe messaging. Central message bus for IoT device communication, events, and commands. | MQTT protocol on port 1883, connects all MQTT-enabled services |

### Additional Components (from existing stack)

| Layer | Component | Container Name | Role | Connection |
|-------|-----------|---------------|------|------------|
| **Reverse Proxy** | Nginx | `nginx` | HTTP reverse proxy with hostname-based routing for all web services. Dynamically configured based on running services. | Proxies to all web UIs on port 80 |
| **Zigbee Gateway** | Zigbee2MQTT | `zigbee2mqtt` | Bridges Zigbee devices to MQTT. Allows Zigbee sensors and actuators to communicate via MQTT broker. | USB Zigbee adapter, MQTT to mosquitto |
| **Face Detection** | Double-Take | `doubletake` | Analyzes Frigate events for facial recognition using CompreFace. Identifies known faces in camera feeds. | Frigate MQTT events, CompreFace API |
| **RTSP Converter** | go2rtc | `go2rtc` | Converts RTSP camera streams to WebRTC/HLS for low-latency browser playback in Grafana and other dashboards. | RTSP streams, WebRTC/HLS output on ports 1984, 8554, 8555 |

## 3. New Component Setup Instructions (Telegraf)

Telegraf is a powerful metrics collection agent that aggregates data from various sources and forwards it to InfluxDB. This section covers setting up Telegraf for syslog collection from network devices (routers, switches, firewalls, etc.).

### Telegraf Configuration Overview

Telegraf uses a configuration file (`telegraf.conf`) that defines:
- **Input plugins**: Where to collect data from (syslog, SNMP, system metrics, etc.)
- **Output plugins**: Where to send data (InfluxDB, MQTT, etc.)
- **Processors**: Optional data transformation and filtering

### Example telegraf.conf Configuration

Create the configuration file at `docker/telegraf/telegraf.conf`:

```toml
# Telegraf Configuration for Home IOT SCADA Stack
# This configuration collects syslog data from network devices and sends it to InfluxDB

[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = "0s"
  hostname = ""
  omit_hostname = false

###############################################################################
#                            OUTPUT PLUGINS                                   #
###############################################################################

# Output to InfluxDB v2.x
[[outputs.influxdb_v2]]
  ## The URLs of the InfluxDB cluster nodes.
  ## Use the service name from compose.yml for internal DNS resolution
  urls = ["http://influxdb:8086"]
  
  ## Token for authentication.
  ## REQUIRED: Replace with your actual InfluxDB admin token from secrets.env
  token = "${INFLUX_TOKEN}"
  
  ## Organization is the name of the organization you want to write to.
  organization = "${INFLUX_ORG}"
  
  ## Destination bucket to write into.
  bucket = "${INFLUX_BUCKET}"
  
  ## Timeout for HTTP messages.
  timeout = "5s"

###############################################################################
#                            INPUT PLUGINS                                    #
###############################################################################

# Syslog listener for network device logs
[[inputs.syslog]]
  ## Protocol: tcp, udp, or unix
  ## For network devices, UDP is most common
  server = "udp://:514"
  
  ## Maximum number of concurrent connections (for TCP)
  # max_connections = 1024
  
  ## Read timeout (for TCP)
  # read_timeout = "5s"
  
  ## Whether to parse in best effort mode or not
  ## If true, will attempt to parse any syslog message format
  best_effort = true
  
  ## Syslog parser configuration
  ## Supported formats: RFC3164, RFC5424, RFC6587, automatic
  # syslog_standard = "RFC5424"

# Uncomment below to collect system metrics from the Telegraf container itself
# [[inputs.cpu]]
#   percpu = true
#   totalcpu = true
#   collect_cpu_time = false
#   report_active = false
#
# [[inputs.disk]]
#   ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]
#
# [[inputs.mem]]
#
# [[inputs.net]]
#
# [[inputs.system]]
```

### Environment Variables for Telegraf

Telegraf configuration uses environment variable substitution for sensitive values. You need to set these in your `secrets.env` file or in the compose.yml environment section:

- `INFLUX_TOKEN`: Your InfluxDB admin token (same as `INFLUXDB_ADMIN_TOKEN`)
- `INFLUX_ORG`: Your InfluxDB organization name (same as `INFLUXDB_ORG`)
- `INFLUX_BUCKET`: The InfluxDB bucket to write to (same as `INFLUXDB_BUCKET`)

**Example in secrets.env:**
```bash
# These should already exist in your secrets.env
INFLUXDB_ADMIN_TOKEN=your_secure_influxdb_admin_token_here
INFLUXDB_ORG=beelzebub_org
INFLUXDB_BUCKET=iot_scada_data
```

### Volume Mount Configuration

Mount the `telegraf.conf` file into the container at the expected path using the `-v` flag in the `podman run` command:

```bash
podman run -d \
  --name telegraf \
  --restart unless-stopped \
  --network iot_net \
  -p 514:514/udp \
  -e INFLUX_TOKEN=${INFLUXDB_ADMIN_TOKEN} \
  -e INFLUX_ORG=${INFLUXDB_ORG} \
  -e INFLUX_BUCKET=${INFLUXDB_BUCKET} \
  -v ./docker/telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:Z \
  docker.io/telegraf:latest
```

**Important Notes on SELinux and Volume Mounts:**

- **`:Z` Label**: Use `:Z` for private volume mounts that only one container will access. This sets the SELinux context to allow Podman to read the file.
- **`:z` Label**: Use `:z` for shared volumes accessed by multiple containers.
- **Rootless Podman**: Ensure the `docker/telegraf/telegraf.conf` file is readable by the user running Podman.

### Network Security Recommendations

Telegraf's syslog listener on UDP/514 receives logs from network devices. Consider these security practices:

1. **Dedicated Network Segment**: Run Telegraf on a separate network (e.g., `syslog_net`) isolated from the main IoT network if possible.
2. **Firewall Rules**: Configure your firewall to only allow syslog traffic (UDP/514) from trusted network device IP addresses.
3. **Bind Address**: The configuration above binds to `0.0.0.0:514` (all interfaces) for simplicity. For enhanced security, bind to a specific interface IP if your network topology allows:
   ```toml
   server = "udp://192.168.1.100:514"  # Replace with your server's IP
   ```
4. **Authentication**: Syslog over UDP does not provide authentication. Consider using syslog over TLS (RFC5425) for sensitive environments, though this requires additional Telegraf configuration and device support.

### Testing Telegraf Configuration

After starting the stack:

1. **View Telegraf logs**:
   ```bash
   podman logs -f telegraf
   ```

2. **Send a test syslog message**:
   ```bash
   logger -n <telegraf-host-ip> -P 514 "Test syslog message from logger"
   ```

3. **Query InfluxDB** to verify data is being written:
   ```bash
   # Using InfluxDB CLI (inside the influxdb container or via API)
   influx query 'from(bucket:"iot_scada_data") |> range(start: -1h) |> filter(fn: (r) => r._measurement == "syslog")'
   ```

## 4. Deployment with startup.sh

The SCADA stack is deployed using the `startup.sh` shell script, which provides automated management of all Podman containers, networks, and volumes.

### Using startup.sh

The startup script provides several commands for managing the stack:

**Start the stack (default):**
```bash
./startup.sh
# or
./startup.sh setup
```

**Start a specific service:**
```bash
./startup.sh start <service_name>
```

**Stop and remove all containers (keeps volumes):**
```bash
./startup.sh breakdown
```

**Complete cleanup (removes volumes - DESTRUCTIVE):**
```bash
./startup.sh nuke
```

### First-Run Configuration

On first run, the startup script will:

1. Prompt you to select deployment mode:
   - IoT/SCADA Stack only
   - NVR only
   - Both IoT/SCADA Stack + NVR

2. Automatically generate secure passwords/tokens in `secrets.env`

3. Guide you through required manual configuration:
   - `ZIGBEE_DEVICE_PATH` - Path to your Zigbee adapter
   - `PODMAN_SOCKET_PATH` - Optional, for Node-RED Docker integration
   - `TZ` - Timezone setting
   - Network and hostname configuration for Nginx reverse proxy

### Adding Telegraf to the Stack

To add Telegraf to your existing deployment, you'll need to integrate it into the `startup.sh` script. Here's how to add the Telegraf service:

1. **Create the Telegraf configuration directory:**
   ```bash
   mkdir -p docker/telegraf
   ```

2. **Add the telegraf.conf file** using the configuration from Section 3.

3. **Add Telegraf service definition** to `startup.sh`:

   Find the section where services are defined (around line 1087) and add:
   
   ```bash
   SERVICE_CMDS[telegraf]="podman run -d --name telegraf --restart unless-stopped --network ${NETWORK_NAME} -p 514:514/udp -e INFLUX_TOKEN=${INFLUXDB_ADMIN_TOKEN} -e INFLUX_ORG=${INFLUXDB_ORG} -e INFLUX_BUCKET=${INFLUXDB_BUCKET} -e TZ=${TZ} -v ./docker/telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:Z docker.io/telegraf:latest"
   ```

4. **Add Telegraf to the service list** in the appropriate deployment mode.

### Port Mappings

The following ports are exposed by default:

- **Mosquitto**: `1883` (MQTT), `9001` (WebSocket)
- **InfluxDB**: `8086` (HTTP API)
- **Grafana**: `3000` (Web UI)
- **FUXA**: `1881` (Web UI) - *if added to stack*
- **Node-RED**: `1880` (Web UI), `514` (Syslog UDP/TCP)
- **Frigate**: `5000` (Web UI), `8554` (RTSP), `1935` (RTMP)
- **CompreFace**: `8000` (API)
- **Telegraf**: `514/udp` (Syslog listener) - *Note: conflicts with Node-RED if both enabled*

### Network Configuration

The startup script creates a custom Podman network (`iot_net` by default) for service-to-service communication. All containers join this network and can reference each other by container name:

- `http://influxdb:8086` - InfluxDB API
- `mqtt://mosquitto:1883` - MQTT broker
- `http://grafana:3000` - Grafana
- `http://fuxa:1881` - FUXA

### Volume Management

Persistent data is stored in named Podman volumes:

- `mosquitto_data` - MQTT broker data
- `influxdb_data` - Time-series database
- `grafana_data` - Grafana dashboards and config
- `nodered_data` - Node-RED flows
- `z2m_data` - Zigbee2MQTT data
- `frigate_data` - NVR recordings
- `compreface_data` - Face recognition models
- `doubletake_data` - Face detection data
- `go2rtc_data` - RTSP converter config

The `breakdown` command preserves these volumes. Only the `nuke` command removes them.

### SELinux Considerations

When running on SELinux-enabled systems (like openSUSE Leap Micro):

1. **Volume Mounts**: Use `:Z` or `:z` labels on volume mounts:
   - `:Z` - Private mount (single container)
   - `:z` - Shared mount (multiple containers)

2. **Security Options**: Some services use `--security-opt label=disable` for compatibility

3. **Privileged Mode**: Frigate requires `--privileged` for hardware access (GPU, Coral TPU)

### Verifying Service Communication

After starting the stack, verify services can communicate:

```bash
# Check that Telegraf can reach InfluxDB
podman exec telegraf ping -c 3 influxdb

# Check that Node-RED can reach Mosquitto
podman exec node-red ping -c 3 mosquitto

# Check network connectivity
podman network inspect iot_net
```

### Systemd Service Integration

For production deployments, install the stack as a systemd user service:

```bash
./install-service.sh install
```

This ensures:
- Automatic startup on system boot
- Service persistence after SSH logout
- User lingering enabled

Manage the service with:
```bash
systemctl --user status iot-scada-stack.service
systemctl --user restart iot-scada-stack.service
journalctl --user -u iot-scada-stack.service -f
```

---

## Next Steps

1. **Configure** the `docker/telegraf/telegraf.conf` file with the configuration from Section 3
2. **Update** your `secrets.env` file to include Telegraf-related environment variables (if not already present)
3. **Run** the startup script to deploy the stack:
   ```bash
   ./startup.sh
   ```
4. **Access** each service via its web UI:
   - FUXA: http://localhost:1881
   - Grafana: http://localhost:3000
   - Node-RED: http://localhost:1880
   - Frigate: http://localhost:5000
   - CompreFace: http://localhost:8000

For troubleshooting and additional configuration details, refer to the official documentation for each component and the README.md file in this repository.
