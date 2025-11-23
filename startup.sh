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
    "nginx_cache"
    "doubletake_data"
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
BASE_DOMAIN=$(read_var BASE_DOMAIN)
GRAFANA_HOSTNAME=$(read_var GRAFANA_HOSTNAME)
FRIGATE_HOSTNAME=$(read_var FRIGATE_HOSTNAME)
NODERED_HOSTNAME=$(read_var NODERED_HOSTNAME)
ZIGBEE2MQTT_HOSTNAME=$(read_var ZIGBEE2MQTT_HOSTNAME)
COCKPIT_HOSTNAME=$(read_var COCKPIT_HOSTNAME)
DOUBLETAKE_HOSTNAME=$(read_var DOUBLETAKE_HOSTNAME)


# ----------------------------------------------------------------------
# --- NGINX CONFIGURATION GENERATION ---
# ----------------------------------------------------------------------

# --- Function to generate nginx configuration based on stack type ---
generate_nginx_config() {
    local stack_type=$1
    local nginx_conf_file="./nginx/nginx.conf"
    
    echo "Generating nginx configuration for stack type: ${stack_type}..."
    
    cat > "${nginx_conf_file}" << 'NGINX_EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    keepalive_timeout 65;
    
    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # Default server - redirect to available services
    server {
        listen 80 default_server;
        server_name _;
        
        location / {
            return 200 '<html><head><title>Home IoT/SCADA Stack</title></head><body><h1>Home IoT/SCADA Stack</h1><ul>SERVICES_LIST</ul></body></html>';
            add_header Content-Type text/html;
        }
    }
NGINX_EOF

    # Add service configurations based on stack type
    if [ "$stack_type" == "iot_only" ] || [ "$stack_type" == "iot_nvr" ]; then
        cat >> "${nginx_conf_file}" << NGINX_EOF
    
    # Grafana
    server {
        listen 80;
        server_name ${GRAFANA_HOSTNAME}.${BASE_DOMAIN};
        
        location / {
            proxy_pass http://grafana:3000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
    
    # Node-RED
    server {
        listen 80;
        server_name ${NODERED_HOSTNAME}.${BASE_DOMAIN};
        
        location / {
            proxy_pass http://nodered:1880;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
    
    # Zigbee2MQTT
    server {
        listen 80;
        server_name ${ZIGBEE2MQTT_HOSTNAME}.${BASE_DOMAIN};
        
        location / {
            proxy_pass http://zigbee2mqtt:8080;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
NGINX_EOF
    fi
    
    if [ "$stack_type" == "nvr_only" ] || [ "$stack_type" == "iot_nvr" ]; then
        cat >> "${nginx_conf_file}" << NGINX_EOF
    
    # Frigate NVR
    server {
        listen 80;
        server_name ${FRIGATE_HOSTNAME}.${BASE_DOMAIN};
        
        location / {
            proxy_pass http://frigate:5000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
    
    # Double-Take (Facial Recognition for Frigate)
    server {
        listen 80;
        server_name ${DOUBLETAKE_HOSTNAME}.${BASE_DOMAIN};
        
        location / {
            proxy_pass http://doubletake:3000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
NGINX_EOF
    fi
    
    # Add Cockpit (openSUSE web console) proxy - assuming it runs on host
    cat >> "${nginx_conf_file}" << NGINX_EOF
    
    # openSUSE Cockpit Web Console
    server {
        listen 80;
        server_name ${COCKPIT_HOSTNAME}.${BASE_DOMAIN};
        
        location / {
            proxy_pass https://host.containers.internal:9090;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_ssl_verify off;
        }
    }
}
NGINX_EOF

    # Update the services list in the default page
    local services_html=""
    if [ "$stack_type" == "iot_only" ] || [ "$stack_type" == "iot_nvr" ]; then
        services_html+="<li><a href=\"http://${GRAFANA_HOSTNAME}.${BASE_DOMAIN}\">Grafana</a></li>"
        services_html+="<li><a href=\"http://${NODERED_HOSTNAME}.${BASE_DOMAIN}\">Node-RED</a></li>"
        services_html+="<li><a href=\"http://${ZIGBEE2MQTT_HOSTNAME}.${BASE_DOMAIN}\">Zigbee2MQTT</a></li>"
    fi
    if [ "$stack_type" == "nvr_only" ] || [ "$stack_type" == "iot_nvr" ]; then
        services_html+="<li><a href=\"http://${FRIGATE_HOSTNAME}.${BASE_DOMAIN}\">Frigate NVR</a></li>"
        services_html+="<li><a href=\"http://${DOUBLETAKE_HOSTNAME}.${BASE_DOMAIN}\">Double-Take</a></li>"
    fi
    services_html+="<li><a href=\"http://${COCKPIT_HOSTNAME}.${BASE_DOMAIN}\">openSUSE Cockpit</a></li>"
    
    sed -i "s|SERVICES_LIST|${services_html}|g" "${nginx_conf_file}"
    
    echo "Nginx configuration generated at ${nginx_conf_file}"
}

# --- Function to check and fix SELinux context and permissions for nginx.conf ---
check_and_fix_nginx_permissions() {
    local nginx_conf_file="./nginx/nginx.conf"
    
    if [ ! -f "${nginx_conf_file}" ]; then
        echo "WARNING: nginx.conf not found at ${nginx_conf_file}. It will be generated."
        return 0
    fi
    
    echo ""
    echo "Checking nginx.conf permissions and SELinux context..."
    
    # Check file permissions
    local file_perms=$(stat -c "%a" "${nginx_conf_file}" 2>/dev/null || stat -f "%OLp" "${nginx_conf_file}" 2>/dev/null)
    local file_owner=$(stat -c "%u" "${nginx_conf_file}" 2>/dev/null || stat -f "%u" "${nginx_conf_file}" 2>/dev/null)
    local current_uid=$(id -u)
    
    echo "  File permissions: ${file_perms}"
    echo "  File owner UID: ${file_owner}"
    echo "  Current user UID: ${current_uid}"
    
    # Warn if permissions are not 644 or more restrictive
    if [ "${file_perms}" != "644" ] && [ "${file_perms}" != "444" ] && [ "${file_perms}" != "400" ] && [ "${file_perms}" != "600" ]; then
        echo "  [WARNING]  WARNING: File permissions are ${file_perms}. Recommended: 644"
        echo "      To fix: chmod 644 ${nginx_conf_file}"
    else
        echo "  [ok] File permissions are acceptable"
    fi
    
    # Warn if file is not owned by current user
    if [ "${file_owner}" != "${current_uid}" ]; then
        echo "  [WARNING]  WARNING: File is owned by UID ${file_owner}, but current user is UID ${current_uid}"
        echo "      To fix: chown ${current_uid} ${nginx_conf_file}"
    else
        echo "  [ok] File ownership is correct"
    fi
    
    # Check if SELinux is enabled
    if command -v getenforce &> /dev/null; then
        local selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
        echo "  SELinux status: ${selinux_status}"
        
        if [ "${selinux_status}" != "Disabled" ]; then
            # Check current SELinux context
            if command -v ls &> /dev/null && ls -Z "${nginx_conf_file}" &> /dev/null; then
                local current_context=$(ls -Z "${nginx_conf_file}" 2>/dev/null | awk '{print $1}')
                echo "  Current SELinux context: ${current_context}"
                
                # Check if context contains container_file_t or svirt_sandbox_file_t
                if echo "${current_context}" | grep -q "container_file_t\|svirt_sandbox_file_t"; then
                    echo "  [ok] SELinux context is already suitable for containers"
                else
                    echo "  [WARNING]  SELinux context may prevent Podman from reading this file"
                    echo "      Current context: ${current_context}"
                    echo "      Expected: *:container_file_t:* or similar"
                    echo ""
                    echo "  Attempting to fix SELinux context..."
                    
                    # Try to fix with chcon if available
                    if command -v chcon &> /dev/null; then
                        if chcon -t container_file_t "${nginx_conf_file}" 2>/dev/null; then
                            echo "  [ok] SELinux context updated successfully with chcon"
                            local new_context=$(ls -Z "${nginx_conf_file}" 2>/dev/null | awk '{print $1}')
                            echo "    New context: ${new_context}"
                        else
                            echo "  [WARNING]  Could not update SELinux context with chcon (permission denied)"
                            echo "      Manual fix required: sudo chcon -t container_file_t ${nginx_conf_file}"
                        fi
                    else
                        echo "  [WARNING]  chcon command not found. Cannot auto-fix SELinux context."
                        echo "      Manual fix required: sudo chcon -t container_file_t ${nginx_conf_file}"
                    fi
                fi
            fi
            
            echo ""
            echo "  [INFO]  For Podman rootless with SELinux, the volume mount will use :Z flag"
            echo "     to automatically relabel the file. If issues persist, run:"
            echo "       sudo chcon -t container_file_t ${nginx_conf_file}"
            echo "     Or use the provided helper script: ./fix-nginx-selinux.sh"
        else
            echo "  [ok] SELinux is disabled, no context issues expected"
        fi
    else
        echo "  [INFO]  SELinux tools not detected (getenforce not found)"
        echo "     If you're on a system with SELinux, ensure it's installed"
    fi
    
    echo ""
}


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
    echo "  2) NVR only (Frigate for camera recording)"
    echo "  3) Both IoT/SCADA Stack + NVR (All services)"
    echo ""
    echo -n "Enter your choice (1, 2, or 3): "
    read -r choice
    
    case "$choice" in
        1)
            echo ""
            echo "Selected: IoT/SCADA Stack only"
            save_stack_config "iot_only"
            ;;
        2)
            echo ""
            echo "Selected: NVR only"
            show_nvr_memory_warning
            save_stack_config "nvr_only"
            ;;
        3)
            echo ""
            echo "Selected: Both IoT/SCADA Stack + NVR"
            show_nvr_memory_warning
            save_stack_config "iot_nvr"
            ;;
        *)
            echo ""
            echo "Invalid choice. Please run the setup again and select 1, 2, or 3."
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
            BASE_DOMAIN=$(read_var BASE_DOMAIN)
            GRAFANA_HOSTNAME=$(read_var GRAFANA_HOSTNAME)
            FRIGATE_HOSTNAME=$(read_var FRIGATE_HOSTNAME)
            NODERED_HOSTNAME=$(read_var NODERED_HOSTNAME)
            ZIGBEE2MQTT_HOSTNAME=$(read_var ZIGBEE2MQTT_HOSTNAME)
            COCKPIT_HOSTNAME=$(read_var COCKPIT_HOSTNAME)
            DOUBLETAKE_HOSTNAME=$(read_var DOUBLETAKE_HOSTNAME)
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
    CONTAINER_NAMES=("mosquitto" "zigbee2mqtt" "frigate" "influxdb" "grafana" "nodered" "nginx" "doubletake")
    
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
SERVICE_CMDS[nginx]="podman run -d --name nginx --restart unless-stopped --network ${NETWORK_NAME} --add-host=host.containers.internal:host-gateway -p 80:80 -v ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro,Z -v nginx_cache:/var/cache/nginx docker.io/library/nginx:alpine"
SERVICE_CMDS[doubletake]="podman run -d --name doubletake --restart unless-stopped --network ${NETWORK_NAME} -p 3001:3000 -v doubletake_data:/.storage -e TZ=${TZ} docker.io/jakowenko/double-take:latest"
SERVICE_NAMES=(mosquitto influxdb zigbee2mqtt frigate grafana nodered nginx doubletake)

# --- Manual Start Function ---
start_manual_service() {
    local SERVICE_NAME=$1
    if [[ " ${SERVICE_NAMES[@]} " =~ " ${SERVICE_NAME} " ]]; then
        echo "--- Manual Start: ${SERVICE_NAME} ---"
        
        # Check configuration and service compatibility
        local stack_type=$(read_stack_config)
        if [ "$SERVICE_NAME" == "frigate" ] && [ "$stack_type" == "iot_only" ]; then
            echo "ERROR: Frigate is not enabled in your configuration (IoT/SCADA only mode)."
            echo "To enable Frigate, delete ${CONFIG_FILE} and run ./startup.sh to reconfigure."
            exit 1
        fi
        
        if [ "$SERVICE_NAME" == "doubletake" ] && [ "$stack_type" == "iot_only" ]; then
            echo "ERROR: Double-Take is not enabled in your configuration (IoT/SCADA only mode)."
            echo "To enable Double-Take, delete ${CONFIG_FILE} and run ./startup.sh to reconfigure."
            exit 1
        fi
        
        if [ "$SERVICE_NAME" != "frigate" ] && [ "$SERVICE_NAME" != "doubletake" ] && [ "$stack_type" == "nvr_only" ]; then
            echo "ERROR: ${SERVICE_NAME} is not enabled in your configuration (NVR only mode)."
            echo "To enable IoT/SCADA services, delete ${CONFIG_FILE} and run ./startup.sh to reconfigure."
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
    if [ "$stack_type" == "iot_nvr" ] || [ "$stack_type" == "nvr_only" ]; then
        mount_smb_share
    fi
    
    # 3. Generate nginx configuration based on stack type
    generate_nginx_config "$stack_type"
    
    # 4. Check and fix nginx.conf permissions and SELinux context
    check_and_fix_nginx_permissions
    
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
        # Skip nginx for now - it will be started last after all upstream services
        if [ "$SERVICE" == "nginx" ]; then
            continue
        fi
        
        # Skip Frigate if stack type is iot_only
        if [ "$SERVICE" == "frigate" ] && [ "$stack_type" == "iot_only" ]; then
            echo "Skipping Frigate (NVR not enabled in configuration)"
            SERVICE_STATUS["${SERVICE}"]="SKIPPED (Not configured)"
            continue
        fi
        # Skip Double-Take if stack type is iot_only
        if [ "$SERVICE" == "doubletake" ] && [ "$stack_type" == "iot_only" ]; then
            echo "Skipping Double-Take (NVR not enabled in configuration)"
            SERVICE_STATUS["${SERVICE}"]="SKIPPED (Not configured)"
            continue
        fi
        # Skip IoT services if stack type is nvr_only (but keep frigate and doubletake)
        if [ "$SERVICE" != "frigate" ] && [ "$SERVICE" != "doubletake" ] && [ "$stack_type" == "nvr_only" ]; then
            echo "Skipping $SERVICE (IoT/SCADA not enabled in configuration)"
            SERVICE_STATUS["${SERVICE}"]="SKIPPED (Not configured)"
            continue
        fi
        run_service "$SERVICE" "${SERVICE_CMDS[$SERVICE]}"
    done
    
    # Start nginx last, after all upstream services are running
    # This prevents "host not found in upstream" errors
    echo ""
    echo "Starting nginx (reverse proxy) after all upstream services..."
    run_service "nginx" "${SERVICE_CMDS[nginx]}"

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
    echo ""
    echo "Via Nginx Reverse Proxy (hostname-based):"
    echo " - Service Index:  http://<host_ip> or http://${BASE_DOMAIN}"
    if [ "$stack_type" == "nvr_only" ]; then
        echo " - Frigate NVR:    http://${FRIGATE_HOSTNAME}.${BASE_DOMAIN}"
    elif [ "$stack_type" == "iot_only" ]; then
        echo " - Grafana:        http://${GRAFANA_HOSTNAME}.${BASE_DOMAIN}"
        echo " - Node-RED:       http://${NODERED_HOSTNAME}.${BASE_DOMAIN}"
        echo " - Zigbee2MQTT:    http://${ZIGBEE2MQTT_HOSTNAME}.${BASE_DOMAIN}"
    else
        echo " - Grafana:        http://${GRAFANA_HOSTNAME}.${BASE_DOMAIN}"
        echo " - Frigate NVR:    http://${FRIGATE_HOSTNAME}.${BASE_DOMAIN}"
        echo " - Node-RED:       http://${NODERED_HOSTNAME}.${BASE_DOMAIN}"
        echo " - Zigbee2MQTT:    http://${ZIGBEE2MQTT_HOSTNAME}.${BASE_DOMAIN}"
    fi
    echo " - Cockpit:        http://${COCKPIT_HOSTNAME}.${BASE_DOMAIN}"
    echo ""
    echo "Direct Access (port-based):"
    if [ "$stack_type" == "nvr_only" ]; then
        echo " - Frigate Web UI: http://<host_ip>:${FRIGATE_PORT}"
    elif [ "$stack_type" == "iot_only" ]; then
        echo " - Grafana Web UI: http://<host_ip>:3000"
        echo " - Node-RED UI:    http://<host_ip>:${NODERED_PORT}"
    else
        echo " - Grafana Web UI: http://<host_ip>:3000"
        echo " - Frigate Web UI: http://<host_ip>:${FRIGATE_PORT}"
        echo " - Node-RED UI:    http://<host_ip>:${NODERED_PORT}"
    fi
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
