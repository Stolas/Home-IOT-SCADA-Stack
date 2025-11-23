#!/bin/bash
# -----------------------------------------------------------------------------
# startup.sh - IoT SCADA Stack Startup and Breakdown Script (Resilient Raw Podman)
#
# This script manages the full life-cycle of the SCADA stack. It is resilient,
# attempts to start all containers, and reports a summary of failures at the end.
# Container startup output (pulls, errors) is now displayed directly.
#
# USAGE: 
#   chmod +x startup.sh
#   ./startup.sh         # DEFAULT: Stops existing, and starts all systems
#   ./startup.sh start <service_name> # Start a specific service manually
#   ./startup.sh breakdown # To stop and remove all systems and unmount SMB
# -----------------------------------------------------------------------------
# Removed set -e: The script will now continue execution after failed commands.

# --- Configuration ---
ENV_FILE="secrets.env"
CONFIG_FILE=".stack_config"
NETWORK_NAME="iot_net"
VOLUME_LIST=(
    "mosquitto_data"
    "frigate_data"
    "nodered_data"
    "z2m_data"
    "grafana_data"
    "influxdb_data"
)
# Array to track the startup status of each service
declare -A SERVICE_STATUS

echo "--- IoT SCADA Stack Management Script (Resilient Raw Podman) ---"
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


# ----------------------------------------------------------------------
# --- FIRST-RUN CONFIGURATION ---
# ----------------------------------------------------------------------

# --- Function to check available memory ---
check_memory() {
    # Get total memory in GiB
    local total_mem_gib=$(free -g | awk '/^Mem:/{print $2}')
    echo "$total_mem_gib"
}

# --- Function to display memory warning for NVR ---
show_nvr_memory_warning() {
    local mem_gib=$(check_memory)
    if [ "$mem_gib" -lt 8 ]; then
        echo ""
        echo "================================================================"
        echo "                    MEMORY WARNING                              "
        echo "================================================================"
        echo "WARNING: Your system has ${mem_gib}GiB of total RAM."
        echo "Frigate NVR requires a minimum of 8GiB RAM for optimal operation."
        echo "Running with insufficient memory may lead to performance issues."
        echo "================================================================"
        echo ""
        sleep 3  # Give user time to read the warning
    fi
}

# --- Function to save stack configuration ---
save_stack_config() {
    local config_choice=$1
    echo "STACK_TYPE=${config_choice}" > "${CONFIG_FILE}"
    echo "Configuration saved to ${CONFIG_FILE}"
}

# --- Function to read stack configuration ---
read_stack_config() {
    if [ -f "${CONFIG_FILE}" ]; then
        grep "^STACK_TYPE=" "${CONFIG_FILE}" | cut -d'=' -f2
    else
        echo ""
    fi
}

# --- First-run configuration menu ---
first_run_configuration() {
    echo ""
    echo "================================================================"
    echo "           FIRST-RUN CONFIGURATION                              "
    echo "================================================================"
    echo ""
    echo "Welcome to the Home IoT SCADA Stack setup!"
    echo ""
    echo "Please choose your stack configuration:"
    echo ""
    echo "  1) IoT/SCADA Stack only (Mosquitto, InfluxDB, Grafana, Node-RED, Zigbee2MQTT)"
    echo "  2) IoT/SCADA Stack + NVR (includes Frigate for camera recording)"
    echo ""
    echo -n "Enter your choice (1 or 2): "
    read -r choice
    
    case "$choice" in
        1)
            echo ""
            echo "Selected: IoT/SCADA Stack only"
            save_stack_config "iot_only"
            ;;
        2)
            echo ""
            echo "Selected: IoT/SCADA Stack + NVR"
            show_nvr_memory_warning
            save_stack_config "iot_nvr"
            ;;
        *)
            echo ""
            echo "Invalid choice. Please run the setup again and select 1 or 2."
            exit 1
            ;;
    esac
    
    echo ""
    echo "Generating secrets automatically..."
    if [ -x "./create_secrets.sh" ]; then
        ./create_secrets.sh
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to generate secrets. Please check create_secrets.sh"
            exit 1
        fi
    else
        echo "ERROR: create_secrets.sh not found or not executable"
        exit 1
    fi
    
    echo ""
    echo "First-run configuration complete!"
    echo ""
}

# --- Check if this is first run ---
check_first_run() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        # First run - do configuration
        first_run_configuration
        
        # Re-read variables after secrets are generated
        if [ -f "$ENV_FILE" ]; then
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
        fi
    fi
}


# ----------------------------------------------------------------------
# --- CORE FUNCTIONS ---
# ----------------------------------------------------------------------

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
        # Exit if directory creation fails (this is a host-level prerequisite)
        mkdir -p "${FRIGATE_RECORDINGS_HOST_PATH}" || { echo "FATAL ERROR: Could not create mount point. Check user permissions."; exit 1; }
    fi

    if mountpoint -q "${FRIGATE_RECORDINGS_HOST_PATH}"; then
        echo "SMB share already mounted at ${FRIGATE_RECORDINGS_HOST_PATH}. Skipping mount."
        SERVICE_STATUS["SMB Mount"]="SUCCESS (Already Mounted)"
    else
        echo "Attempting to mount //${SMB_SERVER}/${SMB_SHARE} to ${FRIGATE_RECORDINGS_HOST_PATH}"
        
        sudo mount -t cifs \
            "//${SMB_SERVER}/${SMB_SHARE}" \
            "${FRIGATE_RECORDINGS_HOST_PATH}" \
            -o username=${SMB_USER},password=${SMB_PASS},vers=3.0,iocharset=utf8,rw,uid=${CURRENT_UID}
        
        if [ $? -eq 0 ]; then
            echo "Successfully mounted SMB share."
            SERVICE_STATUS["SMB Mount"]="SUCCESS"
        else
            echo "WARNING: SMB mount failed. Check credentials, host path, and network connectivity."
            SERVICE_STATUS["SMB Mount"]="FAILURE (Mount Failed)"
            # Do NOT exit, continue with other services
        fi
    fi
}

# --- Breakdown function: Stop and Remove all containers (KEEP volumes) ---
breakdown_containers_only() {
    echo "Stopping and removing containers..."
    CONTAINER_NAMES=("mosquitto" "zigbee2mqtt" "frigate" "influxdb" "grafana" "nodered")
    
    for name in "${CONTAINER_NAMES[@]}"; do
        if podman ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
            echo "Stopping and removing container: ${name}"
            # Use '|| true' to ensure the script doesn't exit if stop/rm fails
            podman stop -t 5 "${name}" || true 
            podman rm "${name}" || true
        else
            echo "Container ${name} is not running or doesn't exist. Skipping."
        fi
    done
}


# --- Function to handle service execution and status tracking ---
run_service() {
    local SERVICE_NAME=$1
    local CMD=$2
    local IS_MANUAL=$3 # "manual" if called by start, empty otherwise
    
    # If manual start, first remove the container to allow a clean run
    if [ "$IS_MANUAL" == "manual" ]; then
        echo "Attempting to remove existing container: ${SERVICE_NAME}..."
        podman stop -t 5 "${SERVICE_NAME}" 2>/dev/null || true
        podman rm "${SERVICE_NAME}" 2>/dev/null || true
    fi

    echo "Starting ${SERVICE_NAME}..."
    
    # Execute the command directly, allowing stdout/stderr to pass through
    $CMD
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "${SERVICE_NAME} started successfully."
        SERVICE_STATUS["${SERVICE_NAME}"]="SUCCESS"
    else
        echo "WARNING: ${SERVICE_NAME} failed to start (Exit Code: $exit_code). Check 'podman logs ${SERVICE_NAME}' for details."
        SERVICE_STATUS["${SERVICE_NAME}"]="FAILURE"
    fi
}

# --- Service Definitions (For run_service and manual starts) ---
declare -A SERVICE_CMDS
SERVICE_CMDS[mosquitto]="podman run -d --name mosquitto --restart unless-stopped --network ${NETWORK_NAME} -p 1883:1883 -p 9001:9001 -v mosquitto_data:/mosquitto/data -v ./mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro docker.io/eclipse-mosquitto:latest"
SERVICE_CMDS[influxdb]="podman run -d --name influxdb --restart unless-stopped --network ${NETWORK_NAME} -p 8086:8086 -v influxdb_data:/var/lib/influxdb2 -e DOCKER_INFLUXDB_INIT_MODE=setup -e DOCKER_INFLUXDB_INIT_USERNAME=${INFLUXDB_ADMIN_USER} -e DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUXDB_ADMIN_PASSWORD} -e DOCKER_INFLUXDB_INIT_ORG=${INFLUXDB_ORG} -e DOCKER_INFLUXDB_INIT_BUCKET=${INFLUXDB_BUCKET} -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUXDB_ADMIN_TOKEN} -e TZ=${TZ} docker.io/influxdb:2.7"
SERVICE_CMDS[zigbee2mqtt]="podman run -d --name zigbee2mqtt --restart unless-stopped --network ${NETWORK_NAME} -p 8080:8080 -e MQTT_SERVER=mqtt://mosquitto -e MQTT_USER=${MQTT_USER} -e MQTT_PASSWORD=${MQTT_PASSWORD} -e TZ=${TZ} -v z2m_data:/app/data --device ${ZIGBEE_DEVICE_PATH}:/dev/zigbee --cap-add NET_ADMIN --cap-add SYS_ADMIN docker.io/koenkk/zigbee2mqtt:latest"
SERVICE_CMDS[frigate]="podman run -d --name frigate --restart unless-stopped --network ${NETWORK_NAME} --privileged -e TZ=${TZ} -p ${FRIGATE_PORT}:5000/tcp -p 1935:1935 -v ${FRIGATE_RECORDINGS_HOST_PATH}:/media/frigate:rw -v ./frigate_config.yml:/config/config.yml:ro -v /etc/localtime:/etc/localtime:ro --shm-size 256m ghcr.io/blakeblackshear/frigate:stable"
SERVICE_CMDS[grafana]="podman run -d --name grafana --restart unless-stopped --network ${NETWORK_NAME} -p 3000:3000 -v grafana_data:/var/lib/grafana -e GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER} -e GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD} -e GF_SECURITY_SECRET_KEY=${GRAFANA_SECRET_KEY} docker.io/grafana/grafana:latest"
SERVICE_CMDS[nodered]="podman run -d --name nodered --restart unless-stopped --network ${NETWORK_NAME} -p ${NODERED_PORT}:1880 -e TZ=${TZ} -e DOCKER_HOST=unix:///var/run/docker.sock -v nodered_data:/data -v ${PODMAN_SOCKET_PATH}:/var/run/docker.sock:ro --security-opt label=disable --user root docker.io/nodered/node-red:latest"
SERVICE_NAMES=(mosquitto influxdb zigbee2mqtt frigate grafana nodered)

# --- Manual Start Function ---
start_manual_service() {
    local SERVICE_NAME=$1
    if [[ " ${SERVICE_NAMES[@]} " =~ " ${SERVICE_NAME} " ]]; then
        echo "--- Manual Start: ${SERVICE_NAME} ---"
        
        # Check if trying to start Frigate when not configured
        local stack_type=$(read_stack_config)
        if [ "$SERVICE_NAME" == "frigate" ] && [ "$stack_type" == "iot_only" ]; then
            echo "ERROR: Frigate is not enabled in your configuration (IoT/SCADA only mode)."
            echo "To enable Frigate, delete ${CONFIG_FILE} and run ./startup.sh to reconfigure."
            exit 1
        fi
        
        # Ensure the network is up (critical prerequisite)
        podman network exists "${NETWORK_NAME}" || podman network create "${NETWORK_NAME}"
        # Only mount SMB if the service needs it (i.e., frigate)
        if [ "$SERVICE_NAME" == "frigate" ]; then
            mount_smb_share
        fi
        
        run_service "$SERVICE_NAME" "${SERVICE_CMDS[$SERVICE_NAME]}" "manual"
        
        if [ "${SERVICE_STATUS[$SERVICE_NAME]}" == "SUCCESS" ]; then
            echo "Successfully started ${SERVICE_NAME}."
        else
            echo "Manual start failed for ${SERVICE_NAME}. Review output above."
        fi
    else
        echo "ERROR: Unknown service name '${SERVICE_NAME}'. Available services: ${SERVICE_NAMES[@]}"
        exit 1
    fi
}

# --- Setup Function: Create network, volumes, and start containers ---
setup_system() {
    
    # Check for first run and handle configuration
    check_first_run
    
    # Get the stack configuration
    local stack_type=$(read_stack_config)
    
    # 1. Always break down containers first for a fresh start
    echo "--- Initiating System Breakdown for Fresh Start (Containers Only) ---"
    breakdown_containers_only
    echo "--- Breakdown Complete. Starting Setup ---"

    # 2. Mount SMB Share only if NVR is enabled
    if [ "$stack_type" == "iot_nvr" ]; then
        mount_smb_share
    fi
    
    echo ""
    echo "[1/3] Setting up Podman Network and Volumes..."

    # Create network if it doesn't exist (Exiting on failure here is acceptable for a critical prerequisite)
    podman network exists "${NETWORK_NAME}" || podman network create "${NETWORK_NAME}"
    echo "Network '${NETWORK_NAME}' ensured."

    # Create volumes if they don't exist
    for vol in "${VOLUME_LIST[@]}"; do
        podman volume exists "${vol}" || podman volume create "${vol}"
        echo "Volume '${vol}' ensured."
    done
    
    echo ""
    echo "[2/3] Starting containers (Output displayed below)..."
    echo "Stack Type: ${stack_type}"

    # --------------------------------------------------
    # --- Start Services (Using run_service function) ---
    # --------------------------------------------------
    for SERVICE in "${SERVICE_NAMES[@]}"; do
        # Skip Frigate if stack type is iot_only
        if [ "$SERVICE" == "frigate" ] && [ "$stack_type" == "iot_only" ]; then
            echo "Skipping Frigate (NVR not enabled in configuration)"
            SERVICE_STATUS["${SERVICE}"]="SKIPPED (Not configured)"
            continue
        fi
        run_service "$SERVICE" "${SERVICE_CMDS[$SERVICE]}"
    done

    echo ""
    echo "[3/3] Finalizing Setup..."
    echo ""
    echo "--- Stack Startup Report ---"
    
    # Print the status summary
    TOTAL_FAILURES=0
    FAILED_SERVICES=""
    for SERVICE in "${!SERVICE_STATUS[@]}"; do
        STATUS=${SERVICE_STATUS[${SERVICE}]}
        printf "  %-20s: %s\n" "${SERVICE}" "${STATUS}"
        if [[ "${STATUS}" == *"FAILURE"* ]]; then
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
            if [ "$SERVICE" != "SMB Mount" ]; then
                FAILED_SERVICES+="${SERVICE} "
            fi
        fi
    done
    
    echo ""
    if [ ${TOTAL_FAILURES} -gt 0 ]; then
        echo "WARNING: ${TOTAL_FAILURES} component(s) failed to start."
        echo "Action items:"
        echo "  - Check logs: podman logs <service_name>"
        if [ -n "$FAILED_SERVICES" ]; then
            echo "  - Retry failed services manually: ./startup.sh start ${FAILED_SERVICES}"
        fi
    else
        echo "SUCCESS: All configured services were started."
    fi

    echo ""
    echo "Access Points:"
    echo " - Grafana Web UI: http://<host_ip>:3000"
    if [ "$stack_type" == "iot_nvr" ]; then
        echo " - Frigate Web UI: http://<host_ip>:${FRIGATE_PORT} (Default: 5000)"
    fi
    echo " - Node-RED UI:    http://<host_ip>:${NODERED_PORT} (Default: 1880)"
    echo ""
    echo "To change your stack configuration, delete ${CONFIG_FILE} and run ./startup.sh again"
}

# --- Full Breakdown function: Containers and SMB share ---
breakdown_system() {
    breakdown_containers_only
    unmount_smb_share
    echo "System Breakdown Complete (Persistent volumes and network were kept)."
}


# --- Main Execution ---
case "$1" in
    setup|"")
        setup_system
        ;;
    breakdown)
        breakdown_system
        ;;
    start)
        if [ -z "$2" ]; then
            echo "ERROR: 'start' command requires a service name (e.g., ./startup.sh start mosquitto)."
            exit 1
        fi
        start_manual_service "$2"
        ;;
    *)
        echo "Usage: $0 {setup|breakdown|start <service_name>}"
        echo "       (Running without arguments defaults to setup)"
        exit 1
        ;;
esac
