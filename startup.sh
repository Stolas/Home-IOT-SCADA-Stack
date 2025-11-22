#!/bin/bash
# -----------------------------------------------------------------------------
# startup.sh - IoT SCADA Stack Startup and Breakdown Script (Raw Podman)
#
# This script manages the full life-cycle of the SCADA stack using raw 'podman'
# commands instead of 'podman-compose'. It includes functions for setup (which
# includes a breakdown for freshness) and a full system breakdown.
#
# USAGE: 
#   chmod +x startup.sh
#   ./startup.sh setup   # To stop existing, and start all systems
#   ./startup.sh breakdown # To stop and remove all systems and unmount SMB
# -----------------------------------------------------------------------------
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
ENV_FILE="secrets.env"
NETWORK_NAME="iot_net"
VOLUME_LIST=(
    "mosquitto_data"
    "frigate_data"
    "nodered_data"
    "z2m_data"
    "grafana_data"
    "influxdb_data"
)

echo "--- IoT SCADA Stack Management Script (Raw Podman) ---"
echo "Using environment file: ${ENV_FILE}"

# --- Check for required files ---
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Missing required file. Ensure '${ENV_FILE}' is in the same directory."
    exit 1
fi

# --- Helper function to read variables from the secrets file ---
read_var() {
    # The grep command handles the reading, removing potential leading/trailing spaces
    grep "^${1}=" "${ENV_FILE}" | cut -d'=' -f2- | tr -d '[:space:]'
}

# --- Read variables for services and SMB mount ---
FRIGATE_PORT=$(read_var FRIGATE_PORT)
NODERED_PORT=$(read_var NODERED_PORT)
FRIGATE_RECORDINGS_HOST_PATH=$(read_var FRIGATE_RECORDINGS_HOST_PATH)
SMB_SERVER=$(read_var SMB_SERVER)
SMB_SHARE=$(read_var SMB_SHARE)
SMB_USER=$(read_var SMB_USER)
SMB_PASS=$(read_var SMB_PASS)
ZIGBEE_DEVICE_PATH=$(read_var ZIGBEE_DEVICE_PATH)
PODMAN_SOCKET_PATH=$(read_var PODMAN_SOCKET_PATH)
CURRENT_UID=$(id -u) 
# Variables for InfluxDB and Grafana
INFLUXDB_ADMIN_USER=$(read_var INFLUXDB_ADMIN_USER)
INFLUXDB_ADMIN_PASSWORD=$(read_var INFLUXDB_ADMIN_PASSWORD)
INFLUXDB_ORG=$(read_var INFLUXDB_ORG)
INFLUXDB_BUCKET=$(read_var INFLUXDB_BUCKET)
INFLUXDB_ADMIN_TOKEN=$(read_var INFLUXDB_ADMIN_TOKEN)
GRAFANA_ADMIN_USER=$(read_var GRAFANA_ADMIN_USER)
GRAFANA_ADMIN_PASSWORD=$(read_var GRAFANA_ADMIN_PASSWORD)
GRAFANA_SECRET_KEY=$(read_var GRAFANA_SECRET_KEY)
MQTT_USER=$(read_var MQTT_USER)
MQTT_PASSWORD=$(read_var MQTT_PASSWORD)
TZ=$(read_var TZ)


# --- CORE FUNCTIONS ---

# --- Unmount SMB Share ---
unmount_smb_share() {
    echo ""
    echo "Checking and unmounting SMB share..."
    if mountpoint -q "${FRIGATE_RECORDINGS_HOST_PATH}"; then
        echo "Unmounting ${FRIGATE_RECORDINGS_HOST_PATH}..."
        sudo umount "${FRIGATE_RECORDINGS_HOST_PATH}" || { echo "WARNING: Could not unmount SMB share. May be in use."; }
        echo "SMB share unmounted."
    else
        echo "SMB share is not mounted at ${FRIGATE_RECORDINGS_HOST_PATH}. Skipping unmount."
    fi
}

# --- Mount SMB Share for Frigate Recordings ---
mount_smb_share() {
    echo ""
    echo "Checking and ensuring SMB share is mounted..."

    if [ ! -d "${FRIGATE_RECORDINGS_HOST_PATH}" ]; then
        echo "Creating mount point directory: ${FRIGATE_RECORDINGS_HOST_PATH}"
        mkdir -p "${FRIGATE_RECORDINGS_HOST_PATH}" || { echo "ERROR: Could not create mount point. Check user permissions."; exit 1; }
    fi

    if mountpoint -q "${FRIGATE_RECORDINGS_HOST_PATH}"; then
        echo "SMB share already mounted at ${FRIGATE_RECORDINGS_HOST_PATH}. Skipping mount."
    else
        echo "Attempting to mount //${SMB_SERVER}/${SMB_SHARE} to ${FRIGATE_RECORDINGS_HOST_PATH}"
        
        # NOTE: Requires 'sudo' and 'cifs-utils' to be installed.
        sudo mount -t cifs \
            "//${SMB_SERVER}/${SMB_SHARE}" \
            "${FRIGATE_RECORDINGS_HOST_PATH}" \
            -o username=${SMB_USER},password=${SMB_PASS},vers=3.0,iocharset=utf8,rw,uid=${CURRENT_UID}

        if [ $? -eq 0 ]; then
            echo "Successfully mounted SMB share."
        else
            echo "ERROR: SMB mount failed. Check credentials, host path, and network connectivity."
            exit 1
        fi
    fi
}

# --- Breakdown function: Stop and Remove all containers (KEEP volumes) ---
breakdown_containers_only() {
    echo "Stopping and removing containers..."
    # List of all container names from the podman-compose.yml
    CONTAINER_NAMES=("mosquitto" "zigbee2mqtt" "frigate" "influxdb" "grafana" "nodered")
    
    for name in "${CONTAINER_NAMES[@]}"; do
        if podman ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
            echo "Stopping and removing container: ${name}"
            # Use '|| true' to ignore errors if container doesn't stop gracefully but is still removed
            podman stop -t 5 "${name}" || true 
            podman rm "${name}"
        else
            echo "Container ${name} is not running or doesn't exist. Skipping."
        fi
    done
}


# --- Setup Function: Create network, volumes, and start containers ---
setup_system() {
    
    # 1. Always break down containers first for a fresh start (as requested)
    echo "--- Initiating System Breakdown for Fresh Start (Containers Only) ---"
    breakdown_containers_only
    echo "--- Breakdown Complete. Starting Setup ---"

    # 2. Mount SMB Share 
    mount_smb_share
    
    echo ""
    echo "[1/3] Setting up Podman Network and Volumes..."

    # Create network if it doesn't exist
    podman network exists "${NETWORK_NAME}" || podman network create "${NETWORK_NAME}"
    echo "Network '${NETWORK_NAME}' ensured."

    # Create volumes if they don't exist
    for vol in "${VOLUME_LIST[@]}"; do
        podman volume exists "${vol}" || podman volume create "${vol}"
        echo "Volume '${vol}' ensured."
    done
    
    echo ""
    echo "[2/3] Starting containers..."

    # 2.1 Mosquitto
    echo "Starting mosquitto..."
    podman run -d \
        --name mosquitto \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        -p 1883:1883 \
        -p 9001:9001 \
        -v mosquitto_data:/mosquitto/data \
        -v ./mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro \
        eclipse-mosquitto:latest

    # 2.2 InfluxDB (Start before Grafana and Node-RED)
    echo "Starting influxdb..."
    podman run -d \
        --name influxdb \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        -p 8086:8086 \
        -v influxdb_data:/var/lib/influxdb2 \
        -e DOCKER_INFLUXDB_INIT_MODE=setup \
        -e DOCKER_INFLUXDB_INIT_USERNAME="${INFLUXDB_ADMIN_USER}" \
        -e DOCKER_INFLUXDB_INIT_PASSWORD="${INFLUXDB_ADMIN_PASSWORD}" \
        -e DOCKER_INFLUXDB_INIT_ORG="${INFLUXDB_ORG}" \
        -e DOCKER_INFLUXDB_INIT_BUCKET="${INFLUXDB_BUCKET}" \
        -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN="${INFLUXDB_ADMIN_TOKEN}" \
        -e TZ="${TZ}" \
        influxdb:2.7
        
    # 2.3 Zigbee2MQTT
    echo "Starting zigbee2mqtt..."
    podman run -d \
        --name zigbee2mqtt \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        -p 8080:8080 \
        -e MQTT_SERVER="mqtt://mosquitto" \
        -e MQTT_USER="${MQTT_USER}" \
        -e MQTT_PASSWORD="${MQTT_PASSWORD}" \
        -e TZ="${TZ}" \
        -v z2m_data:/app/data \
        --device "${ZIGBEE_DEVICE_PATH}:/dev/zigbee" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        koenkk/zigbee2mqtt:latest

    # 2.4 Frigate
    echo "Starting frigate..."
    podman run -d \
        --name frigate \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        --privileged \
        -e TZ="${TZ}" \
        -p "${FRIGATE_PORT}:5000/tcp" \
        -p "${FRIGATE_RTSP_PORT}:8554/tcp" \
        -p 1935:1935 \
        -v "${FRIGATE_RECORDINGS_HOST_PATH}:/media/frigate:rw" \
        -v ./frigate_config.yml:/config/config.yml:ro \
        -v /etc/localtime:/etc/localtime:ro \
        --shm-size "256m" \
        ghcr.io/blakeblackshear/frigate:stable
        
    # 2.5 Grafana
    echo "Starting grafana..."
    podman run -d \
        --name grafana \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        -p 3000:3000 \
        -v grafana_data:/var/lib/grafana \
        -e GF_SECURITY_ADMIN_USER="${GRAFANA_ADMIN_USER}" \
        -e GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}" \
        -e GF_SECURITY_SECRET_KEY="${GRAFANA_SECRET_KEY}" \
        grafana/grafana:latest
    
    # 2.6 Node-RED
    echo "Starting nodered..."
    podman run -d \
        --name nodered \
        --restart unless-stopped \
        --network "${NETWORK_NAME}" \
        -p "${NODERED_PORT}:1880" \
        -e TZ="${TZ}" \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        -v nodered_data:/data \
        -v "${PODMAN_SOCKET_PATH}:/var/run/docker.sock:ro" \
        --security-opt label=disable \
        --user root \
        nodered/node-red:latest

    echo ""
    echo "[3/3] System Setup Complete!"
    echo "All containers have been refreshed and restarted using existing data volumes."
    echo ""
    echo "Access Points:"
    echo " - Grafana Web UI: http://<host_ip>:3000"
    echo " - Frigate Web UI: http://<host_ip>:${FRIGATE_PORT} (Default: 5000)"
    echo " - Node-RED UI:    http://<host_ip>:${NODERED_PORT} (Default: 1880)"
}

# --- Full Breakdown function: Containers and SMB share ---
breakdown_system() {
    breakdown_containers_only
    unmount_smb_share
    echo "System Breakdown Complete (Persistent volumes and network were kept)."
}


# --- Main Execution ---
case "$1" in
    setup)
        setup_system
        ;;
    breakdown)
        breakdown_system
        ;;
    *)
        echo "Usage: $0 {setup|breakdown}"
        exit 1
        ;;
esac
