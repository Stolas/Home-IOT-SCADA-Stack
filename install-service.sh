#!/bin/bash
# -----------------------------------------------------------------------------
# install-service.sh - Install Home IoT SCADA Stack as systemd user service
#
# This script sets up the stack to run as a systemd user service, ensuring
# that containers persist across SSH sessions and automatically start on boot.
#
# USAGE: 
#   chmod +x install-service.sh
#   ./install-service.sh install   # Install and enable the service
#   ./install-service.sh uninstall # Stop and remove the service
#   ./install-service.sh status    # Check service status
#   ./install-service.sh logs      # View service logs
# -----------------------------------------------------------------------------

set -e

# --- Configuration ---
SERVICE_NAME="iot-scada-stack"
SERVICE_TEMPLATE="iot-scada-stack.service.template"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_USER_DIR}/${SERVICE_NAME}.service"
WORKING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helper Functions ---
print_header() {
    echo ""
    echo "================================================================"
    echo "  $1"
    echo "================================================================"
    echo ""
}

print_success() {
    echo "[✓] $1"
}

print_info() {
    echo "[i] $1"
}

print_error() {
    echo "[✗] ERROR: $1" >&2
}

# --- Check Prerequisites ---
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if systemd is available
    if ! command -v systemctl &> /dev/null; then
        print_error "systemd is not available on this system"
        exit 1
    fi
    
    # Check if service template exists
    if [ ! -f "${WORKING_DIR}/${SERVICE_TEMPLATE}" ]; then
        print_error "Service template not found: ${SERVICE_TEMPLATE}"
        exit 1
    fi
    
    # Check if startup.sh exists
    if [ ! -f "${WORKING_DIR}/startup.sh" ]; then
        print_error "startup.sh not found in ${WORKING_DIR}"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# --- Install Service ---
install_service() {
    print_header "Installing Home IoT SCADA Stack as systemd user service"
    
    check_prerequisites
    
    # Create systemd user directory if it doesn't exist
    print_info "Creating systemd user directory..."
    mkdir -p "${SYSTEMD_USER_DIR}"
    print_success "Directory created: ${SYSTEMD_USER_DIR}"
    
    # Generate service file from template
    print_info "Generating service file from template..."
    sed "s|WORKING_DIRECTORY_PLACEHOLDER|${WORKING_DIR}|g" \
        "${WORKING_DIR}/${SERVICE_TEMPLATE}" > "${SERVICE_FILE}"
    print_success "Service file created: ${SERVICE_FILE}"
    
    # Reload systemd daemon
    print_info "Reloading systemd daemon..."
    systemctl --user daemon-reload
    print_success "Systemd daemon reloaded"
    
    # Enable the service to start on boot
    print_info "Enabling service to start on boot..."
    systemctl --user enable "${SERVICE_NAME}.service"
    print_success "Service enabled"
    
    # Enable lingering so service runs without active session
    print_info "Enabling user lingering to keep service running after logout..."
    if loginctl enable-linger "${USER}" 2>/dev/null; then
        print_success "User lingering enabled for ${USER}"
    else
        print_info "Note: Lingering might require elevated privileges. Trying with sudo..."
        if sudo loginctl enable-linger "${USER}"; then
            print_success "User lingering enabled for ${USER} (with sudo)"
        else
            print_error "Failed to enable lingering. Service may stop when SSH session ends."
            echo "         To fix this manually, run: sudo loginctl enable-linger ${USER}"
        fi
    fi
    
    # Start the service
    print_info "Starting service..."
    systemctl --user start "${SERVICE_NAME}.service"
    print_success "Service started"
    
    print_header "Installation Complete"
    
    echo "The Home IoT SCADA Stack is now installed as a systemd user service."
    echo ""
    echo "Service management commands:"
    echo "  - Check status:   systemctl --user status ${SERVICE_NAME}.service"
    echo "  - View logs:      journalctl --user -u ${SERVICE_NAME}.service -f"
    echo "  - Stop service:   systemctl --user stop ${SERVICE_NAME}.service"
    echo "  - Restart:        systemctl --user restart ${SERVICE_NAME}.service"
    echo "  - Disable:        systemctl --user disable ${SERVICE_NAME}.service"
    echo ""
    echo "Or use this script:"
    echo "  - ./install-service.sh status"
    echo "  - ./install-service.sh logs"
    echo ""
}

# --- Uninstall Service ---
uninstall_service() {
    print_header "Uninstalling Home IoT SCADA Stack systemd service"
    
    # Stop the service
    print_info "Stopping service..."
    if systemctl --user is-active --quiet "${SERVICE_NAME}.service"; then
        systemctl --user stop "${SERVICE_NAME}.service"
        print_success "Service stopped"
    else
        print_info "Service is not running"
    fi
    
    # Disable the service
    print_info "Disabling service..."
    if systemctl --user is-enabled --quiet "${SERVICE_NAME}.service"; then
        systemctl --user disable "${SERVICE_NAME}.service"
        print_success "Service disabled"
    else
        print_info "Service is not enabled"
    fi
    
    # Remove service file
    print_info "Removing service file..."
    if [ -f "${SERVICE_FILE}" ]; then
        rm -f "${SERVICE_FILE}"
        print_success "Service file removed"
    else
        print_info "Service file does not exist"
    fi
    
    # Reload systemd daemon
    print_info "Reloading systemd daemon..."
    systemctl --user daemon-reload
    print_success "Systemd daemon reloaded"
    
    print_header "Uninstallation Complete"
    
    echo "The systemd service has been removed."
    echo ""
    echo "Note: User lingering is still enabled. To disable it, run:"
    echo "  sudo loginctl disable-linger ${USER}"
    echo ""
    echo "The containers can still be managed manually with:"
    echo "  ./startup.sh"
    echo ""
}

# --- Show Service Status ---
show_status() {
    print_header "Home IoT SCADA Stack Service Status"
    
    if [ ! -f "${SERVICE_FILE}" ]; then
        print_error "Service is not installed"
        echo "Run './install-service.sh install' to install the service"
        exit 1
    fi
    
    systemctl --user status "${SERVICE_NAME}.service"
    
    echo ""
    print_info "Lingering status for user ${USER}:"
    loginctl show-user "${USER}" | grep "Linger="
    echo ""
    
    print_info "Running containers:"
    podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

# --- Show Service Logs ---
show_logs() {
    print_header "Home IoT SCADA Stack Service Logs"
    
    if [ ! -f "${SERVICE_FILE}" ]; then
        print_error "Service is not installed"
        echo "Run './install-service.sh install' to install the service"
        exit 1
    fi
    
    print_info "Showing last 50 lines and following new logs (Ctrl+C to exit)..."
    echo ""
    journalctl --user -u "${SERVICE_NAME}.service" -n 50 -f
}

# --- Main Execution ---
case "$1" in
    install)
        install_service
        ;;
    uninstall)
        uninstall_service
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    *)
        echo "Home IoT SCADA Stack - Systemd Service Manager"
        echo ""
        echo "Usage: $0 {install|uninstall|status|logs}"
        echo ""
        echo "Commands:"
        echo "  install    - Install and start the service (persists after SSH logout)"
        echo "  uninstall  - Stop and remove the service"
        echo "  status     - Check service and container status"
        echo "  logs       - View service logs (follow mode)"
        echo ""
        echo "Examples:"
        echo "  $0 install     # Set up automatic service management"
        echo "  $0 status      # Check if service is running"
        echo "  $0 logs        # Monitor service activity"
        echo ""
        exit 1
        ;;
esac
