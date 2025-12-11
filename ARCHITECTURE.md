# Home IOT SCADA Stack Architecture

A comprehensive guide to the architecture, components, and deployment of the Home IOT SCADA Stack.

## 1. 🚀 Project Overview: The SCADA Stack

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

The entire stack is deployed using **Podman containers** managed by a single `compose.yml` file. This approach:

- **Simplifies Setup**: Define all services, networks, and volumes in one declarative file
- **Ensures Reproducibility**: Identical deployments across different hosts
- **Facilitates Updates**: Manage all container versions centrally
- **Supports Rootless Mode**: Enhanced security with rootless Podman execution
- **SELinux Friendly**: Properly configured volume mounts with `:Z` labels for SELinux contexts

Use `podman-compose up -d` to start the entire stack with a single command.

## 2. 🌐 System Architecture & Component Roles

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

## 3. ➕ New Component Setup Instructions (Telegraf)

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

Mount the `telegraf.conf` file into the container at the expected path. In your `compose.yml`:

```yaml
services:
  telegraf:
    image: docker.io/telegraf:latest
    container_name: telegraf
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "514:514/udp"  # Syslog listener
    environment:
      - INFLUX_TOKEN=${INFLUXDB_ADMIN_TOKEN}
      - INFLUX_ORG=${INFLUXDB_ORG}
      - INFLUX_BUCKET=${INFLUXDB_BUCKET}
    volumes:
      # Mount telegraf.conf with SELinux label :Z for Podman/SELinux compatibility
      - ./docker/telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:Z
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

## 4. 🗂️ Podman Compose File Update (Instructions)

The `compose.yml` file defines all services, networks, and volumes for the SCADA stack. This section provides guidance on ensuring your compose file includes all necessary components.

### Required Services

Confirm your `compose.yml` includes the following services:

1. **mosquitto** - MQTT broker
2. **influxdb** - Time-series database
3. **grafana** - Visualization dashboards
4. **fuxa** - HMI/SCADA interface
5. **node-red** - Automation logic
6. **frigate** - Video surveillance (NVR)
7. **compreface** - Face recognition API
8. **telegraf** - Metrics collection agent

### Essential Configuration Elements

#### Networks

Create a custom bridge network for service communication:

```yaml
networks:
  iot_stack_net:
    driver: bridge
```

All services should connect to this network. Services can reference each other by container name as hostname (e.g., `http://influxdb:8086`).

#### Volumes

Named volumes for persistent data:

```yaml
volumes:
  mosquitto_data:
  influxdb_data:
  grafana_data:
  fuxa_data:
  node-red_data:
  frigate_data:
  compreface_data:
  telegraf_data:
```

#### Port Mappings

Essential ports to expose:

- Mosquitto: `1883` (MQTT)
- InfluxDB: `8086` (HTTP API)
- Grafana: `3000` (Web UI)
- FUXA: `1881` (Web UI)
- Node-RED: `1880` (Web UI), `514` (Syslog UDP/TCP)
- Frigate: `5000` (Web UI), `8554` (RTSP)
- CompreFace: `8000` (API)
- Telegraf: `514/udp` (Syslog listener)

### Example compose.yml Snippet

Below is a complete example `compose.yml` suitable for Podman Compose. This includes all primary services with minimal necessary configuration:

```yaml
version: '3.8'

services:
  # MQTT Broker
  mosquitto:
    image: docker.io/eclipse-mosquitto:latest
    container_name: mosquitto
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - mosquitto_data:/mosquitto/data
      - ./mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro

  # Time-Series Database
  influxdb:
    image: docker.io/influxdb:2.7
    container_name: influxdb
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "8086:8086"
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=${INFLUXDB_ADMIN_USER}
      - DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUXDB_ADMIN_PASSWORD}
      - DOCKER_INFLUXDB_INIT_ORG=${INFLUXDB_ORG}
      - DOCKER_INFLUXDB_INIT_BUCKET=${INFLUXDB_BUCKET}
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUXDB_ADMIN_TOKEN}
      - TZ=${TZ}
    volumes:
      - influxdb_data:/var/lib/influxdb2

  # Visualization Dashboards
  grafana:
    image: docker.io/grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_SECURITY_SECRET_KEY=${GRAFANA_SECRET_KEY}
      - GF_AUTH_ANONYMOUS_ENABLED=${GRAFANA_ANONYMOUS_ENABLED:-false}
      - GF_AUTH_ANONYMOUS_ORG_NAME=${GRAFANA_ANONYMOUS_ORG_NAME:-Main Org.}
      - GF_AUTH_ANONYMOUS_ORG_ROLE=${GRAFANA_ANONYMOUS_ORG_ROLE:-Viewer}
      - TZ=${TZ}
    volumes:
      - grafana_data:/var/lib/grafana

  # HMI/SCADA Interface
  fuxa:
    image: docker.io/frangoteam/fuxa:latest
    container_name: fuxa
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "1881:1881"
    environment:
      - TZ=${TZ}
    volumes:
      - fuxa_data:/usr/src/app/FUXA/server/_appdata

  # Automation Logic
  node-red:
    image: docker.io/nodered/node-red:latest
    container_name: node-red
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "1880:1880"
      - "514:514/udp"
      - "514:514/tcp"
    environment:
      - TZ=${TZ}
    volumes:
      - node-red_data:/data
    # For Podman socket access (optional, for Docker nodes in Node-RED)
    # Uncomment if using Node-RED with Docker/Podman integration
    # - ${PODMAN_SOCKET_PATH}:/var/run/docker.sock:ro

  # Video Surveillance (NVR)
  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable
    container_name: frigate
    restart: unless-stopped
    networks:
      - iot_stack_net
    privileged: true
    ports:
      - "5000:5000"
      - "8554:8554"  # RTSP
      - "1935:1935"  # RTMP
    environment:
      - TZ=${TZ}
    volumes:
      - frigate_data:/media/frigate
      - ./frigate_config.yml:/config/config.yml:ro
      - /etc/localtime:/etc/localtime:ro
    shm_size: '256m'

  # Face Recognition API
  compreface:
    image: docker.io/exadel/compreface:latest
    container_name: compreface
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "8000:8000"
    environment:
      - API_KEY=${COMPREFACE_API_KEY}
      - TZ=${TZ}
    volumes:
      - compreface_data:/root/.cache

  # Metrics Collection Agent
  telegraf:
    image: docker.io/telegraf:latest
    container_name: telegraf
    restart: unless-stopped
    networks:
      - iot_stack_net
    ports:
      - "514:514/udp"  # Syslog listener
    environment:
      - INFLUX_TOKEN=${INFLUXDB_ADMIN_TOKEN}
      - INFLUX_ORG=${INFLUXDB_ORG}
      - INFLUX_BUCKET=${INFLUXDB_BUCKET}
    volumes:
      - ./docker/telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:Z

networks:
  iot_stack_net:
    driver: bridge

volumes:
  mosquitto_data:
  influxdb_data:
  grafana_data:
  fuxa_data:
  node-red_data:
  frigate_data:
  compreface_data:
  telegraf_data:
```

### Environment Variables and Secrets

**Do NOT hardcode credentials in compose.yml.** Use environment variable substitution with a `secrets.env` file:

```bash
# Load secrets.env before running podman-compose
export $(cat secrets.env | xargs)
podman-compose up -d
```

Or use `podman-compose --env-file secrets.env up -d` if supported.

### Podman Compose Commands

**Start the stack:**
```bash
podman-compose up -d
```

**Stop the stack:**
```bash
podman-compose down
```

**View logs:**
```bash
podman-compose logs -f
podman-compose logs -f telegraf  # Specific service
```

**Rebuild after config changes:**
```bash
podman-compose down
podman-compose up -d
```

### Creating the Network (Optional)

If you prefer to create the network manually before starting the stack:

```bash
podman network create iot_stack_net
```

Podman Compose will use the existing network if it already exists.

### SELinux Considerations

When running on SELinux-enabled systems (like openSUSE Leap Micro):

1. **Volume Mounts**: Use `:Z` or `:z` labels on volume mounts to set appropriate SELinux contexts.
   - `:Z`: Private mount (single container)
   - `:z`: Shared mount (multiple containers)

2. **Example**:
   ```yaml
   volumes:
     - ./docker/telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:Z
     - ./mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:z
   ```

3. **Privileged Containers**: Some containers (like Frigate) require `privileged: true` for hardware access. Use sparingly and only when necessary.

### Verifying Service Communication

After starting the stack, verify services can communicate:

```bash
# Check that Telegraf can reach InfluxDB
podman exec telegraf ping -c 3 influxdb

# Check that Node-RED can reach Mosquitto
podman exec node-red ping -c 3 mosquitto

# Check network connectivity
podman network inspect iot_stack_net
```

All services on the `iot_stack_net` network can reference each other by container name.

---

## Next Steps

1. **Review and Update** your existing `compose.yml` to include all services listed above.
2. **Create** the `docker/telegraf/telegraf.conf` file with the configuration provided in Section 3.
3. **Update** your `secrets.env` file to include any new environment variables (Telegraf-related variables should already exist if you have InfluxDB configured).
4. **Test** the stack:
   ```bash
   podman-compose up -d
   podman-compose logs -f
   ```
5. **Configure** each service via its web UI:
   - FUXA: http://localhost:1881
   - Grafana: http://localhost:3000
   - Node-RED: http://localhost:1880
   - Frigate: http://localhost:5000
   - CompreFace: http://localhost:8000

For troubleshooting and additional configuration details, refer to the official documentation for each component.
