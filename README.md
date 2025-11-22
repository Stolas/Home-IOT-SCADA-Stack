Home IoT SCADA Stack for openSUSE MicroOS

A comprehensive, containerized Home IoT SCADA (Supervisory Control and Data Acquisition) Stack built with Podman for resiliency and security on an openSUSE MicroOS host.

Features

Host OS: Optimized for openSUSE MicroOS (or other transactional OS) for enhanced stability and rollback capability.

Container Runtime: Uses Podman for managing containers, networks, and persistent volumes.

Core Components: Integrates MQTT Broker (Mosquitto), Time Series Database (InfluxDB), Visualization (Grafana), Automation (Node-RED), NVR (Frigate), and Zigbee Gateway (Zigbee2MQTT).

Security: Uses create_secrets.sh to generate unique, random, 64-character passwords/tokens for sensitive environment variables.

External Storage: Includes logic to mount an SMB/CIFS share for Frigate recordings on the host machine.

Resilience: The startup.sh script continues running even if individual service starts fail, providing a complete status report.

Getting Started

Follow these steps to set up and run the entire stack.

1. Prerequisites (openSUSE MicroOS)

You must have the following installed on your host machine:

Podman: Installed by default on MicroOS.

cifs-utils: Required for mounting the SMB share. Use transactional-update to install this package permanently:

sudo transactional-update pkg install cifs-utils
sudo reboot


sudo privileges: Required for mounting the SMB share.

2. Configure Environment Variables

The stack uses a single .env file for all configurations.

Review the Example: Examine secrets.env-example to understand the required variables.

Generate Secrets: Run the create_secrets.sh script. This will create your secure secrets.env file.

chmod +x create_secrets.sh
./create_secrets.sh


Manual Configuration (CRITICAL):

Edit the newly created secrets.env file.

Crucially, update ZIGBEE_DEVICE_PATH with the path to your Zigbee adapter (e.g., /dev/ttyACM0 or /dev/ttyUSB0).

Update the PODMAN_SOCKET_PATH variable for Node-RED integration. On modern Podman/MicroOS systems, this is typically:

PODMAN_SOCKET_PATH=/run/user/$(id -u)/podman/podman.sock


Update all other non-secret, site-specific variables (e.g., FRIGATE_PORT, SMB_SERVER, TZ).

3. Configure Frigate

The Frigate container uses a separate configuration file.

Edit the frigate_config.yml file to define your cameras and settings.

4. Run the Stack

The startup.sh script manages the entire lifecycle.

Default Start / Setup

This stops any existing containers, unmounts the SMB share, sets up the Podman network and volumes, mounts the SMB share, and starts all services.

chmod +x startup.sh
./startup.sh setup  # or simply ./startup.sh


Breakdown (Stop and Remove Containers)

This stops and removes all active containers and unmounts the SMB share. Persistent volumes and the Podman network are kept intact.

./startup.sh breakdown


Start a Single Service

To troubleshoot or manually start a specific service:

./startup.sh start <service_name>
# Example: ./startup.sh start zigbee2mqtt


Available service names: mosquitto, influxdb, zigbee2mqtt, frigate, grafana, nodered.

Adding New Services (Example: CODESYS Gateway)

To extend the stack with a new service, such as the CODESYS Gateway, you need to update two sections in the startup.sh script.

Step 1: Update Service Definitions

Edit startup.sh and add the new service name to the arrays.

Add to Service Status/Commands: Define the codesysgateway container command in the SERVICE_CMDS map.

CODESYS Gateway Example: Assumes the standard port 12110 for the gateway.

# (Inside startup.sh, near line 240)
# Add the CODESYS Gateway command to the map:
SERVICE_CMDS[codesysgateway]="podman run -d --name codesysgateway --restart unless-stopped --network ${NETWORK_NAME} -p 12110:12110/udp -p 12111:12111/tcp docker.io/codesys/codesyscontrol-gateway-x64:latest"


Add to Service List: Add the name to the list of all services to ensure it is managed by the script.

# (Inside startup.sh, near line 250)
# Add 'codesysgateway' to the SERVICE_NAMES array:
SERVICE_NAMES=(mosquitto influxdb zigbee2mqtt frigate grafana nodered codesysgateway)


Step 2: Run the Setup

After saving startup.sh, run the full setup script again. It will automatically stop existing containers, check volumes, and start the new codesysgateway container along with the others.

./startup.sh setup


The CODESYS Gateway container will now be started and managed by the startup.sh script, listening on the specified ports.

Components and Access Points

Component

Purpose

Access URL (Default Ports)

Grafana

Data Visualization (SCADA UI)

http://<host_ip>:3000

Frigate

NVR and Object Detection

http://<host_ip>:<FRIGATE_PORT> (default: 5000)

Node-RED

Flow-Based Automation

http://<host_ip>:<NODERED_PORT> (default: 1880)

Zigbee2MQTT

Zigbee Device Control

http://<host_ip>:8080 (Web UI)

CODESYS Gateway

PLC Runtime Communication

udp/tcp <host_ip>:12110/12111

Mosquitto

MQTT Broker

Port 1883 (Internal/External)

InfluxDB

Time-Series Database

Port 8086 (Internal/External)

Project Structure

File/Directory

Description

startup.sh

Main script for managing setup, breakdown, and service start. (Executable)

create_secrets.sh

Script to generate a secure secrets.env file from the example. (Executable)

secrets.env-example

Template file listing all necessary environment variables.

secrets.env

Your configuration file. Created by create_secrets.sh. (Keep this secret!)

frigate_config.yml

Configuration file for the Frigate NVR container.

mosquitto/

Directory for Mosquitto configuration files (e.g., mosquitto.conf).

.gitignore

Ensures secrets.env is never committed to Git.

Troubleshooting

openSUSE MicroOS Updates: Use sudo transactional-update for package management and system upgrades, followed by a reboot.

Container Logs: If a container starts with a FAILURE status, check the logs for detailed errors:

podman logs <service_name>


Zigbee Adapter: If zigbee2mqtt fails, ensure the ZIGBEE_DEVICE_PATH is correct and that the host user has the necessary permissions.
