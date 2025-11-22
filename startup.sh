#!/bin/bash
# -----------------------------------------------------------------------------
# startup.sh - IoT SCADA Stack Reload and Startup Script
#
# This script is designed to safely stop, update, and restart the entire
# Podman stack while preserving all persistent data volumes.
# It now includes automatic mounting of the external SMB share for Frigate.
#
# USAGE: chmod +x startup.sh && ./startup.sh
# -----------------------------------------------------------------------------
set -e # Exit immediately if a command exits with a non-zero status.

COMPOSE_FILE="podman-compose.yml"
ENV_FILE="secrets.env"

echo "--- IoT SCADA Stack Maintenance and Reload Script ---"
echo "Targeting compose file: ${COMPOSE_FILE}"
echo "Using environment file: ${ENV_FILE}"

# --- Check for required files ---
if [ ! -f "$COMPOSE_FILE" ] || [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Missing required files. Ensure '${COMPOSE_FILE}' and '${ENV_FILE}' are in the same directory."
    exit 1
fi

# --- Helper function to read variables from the secrets file ---
read_var() {
    # The grep command handles the reading, removing potential leading/trailing spaces
    grep "^${1}=" "${ENV_FILE}" | cut -d'=' -f2- | tr -d '[:space:]'
}

# --- 1/5: Read variables for services and SMB mount ---
FRIGATE_PORT=$(read_var FRIGATE_PORT)
NODERED_PORT=$(read_var NODERED_PORT)
FRIGATE_RECORDINGS_HOST_PATH=$(read_var FRIGATE_RECORDINGS_HOST_PATH)
SMB_SERVER=$(read_var SMB_SERVER)
SMB_SHARE=$(read_var SMB_SHARE)
SMB_USER=$(read_var SMB_USER)
SMB_PASS=$(read_var SMB_PASS)

# --- 2/5: Mount SMB Share for Frigate Recordings ---
echo ""
echo "[1/4] Checking and ensuring SMB share is mounted..."

# Check if the mount point directory exists, and create it if necessary
if [ ! -d "${FRIGATE_RECORDINGS_HOST_PATH}" ]; then
    echo "Creating mount point directory: ${FRIGATE_RECORDINGS_HOST_PATH}"
    # NOTE: This will prompt for sudo password if not configured for NOPASSWD
    sudo mkdir -p "${FRIGATE_RECORDINGS_HOST_PATH}"
fi

# Check if the SMB share is already mounted at the target path
if mountpoint -q "${FRIGATE_RECORDINGS_HOST_PATH}"; then
    echo "SMB share already mounted at ${FRIGATE_RECORDINGS_HOST_PATH}. Skipping mount."
else
    echo "Attempting to mount //${SMB_SERVER}/${SMB_SHARE} to ${FRIGATE_RECORDINGS_HOST_PATH}"
    
    # Execute the mount command using credentials from secrets.yml
    sudo mount -t cifs \
        "//${SMB_SERVER}/${SMB_SHARE}" \
        "${FRIGATE_RECORDINGS_HOST_PATH}" \
        -o username=${SMB_USER},password=${SMB_PASS},vers=3.0,iocharset=utf8
    
    # Check the exit status of the mount command
    if [ $? -eq 0 ]; then
        echo "Successfully mounted SMB share."
    else
        echo "ERROR: SMB mount failed. Check credentials, host path, and network connectivity."
        exit 1
    fi
fi

# --- 3/5: Stop and Remove existing containers (Preserve volumes) ---
echo ""
echo "[2/4] Stopping and removing old containers (Data volumes will be KEPT)..."
podman-compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" down || true # '|| true' prevents exit if no containers are running

# --- 4/5: Pull the latest images ---
echo ""
echo "[3/4] Pulling the latest images for all services..."
podman-compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" pull

# --- 5/5: Recreate and Start the stack ---
echo ""
echo "[4/4] Starting the entire stack in detached mode..."
# 'up -d' recreates containers using the latest config and re-attaches existing data volumes.
# '--remove-orphans' ensures any forgotten containers are cleaned up.
podman-compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d --remove-orphans

echo ""
echo "--- Stack Reload Complete ---"
echo "All containers have been refreshed and restarted using existing data volumes."
echo ""
echo "Access Points:"
echo " - Grafana Web UI: http://<host_ip>:3000"
echo " - Frigate Web UI: http://<host_ip>:${FRIGATE_PORT} (Default: 5000)"
echo " - Node-RED UI:    http://<host_ip>:${NODERED_PORT} (Default: 1880)"
echo ""
