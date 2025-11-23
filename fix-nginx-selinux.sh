#!/bin/bash
# -----------------------------------------------------------------------------
# fix-nginx-selinux.sh - Diagnose and Fix nginx.conf SELinux Issues
#
# This script helps diagnose and fix SELinux context and permission issues
# with nginx/nginx.conf when running Podman in rootless mode on systems with
# SELinux enabled (e.g., openSUSE Leap, openSUSE MicroOS, Fedora, RHEL).
#
# USAGE:
#   chmod +x fix-nginx-selinux.sh
#   ./fix-nginx-selinux.sh          # Diagnose issues
#   ./fix-nginx-selinux.sh --fix    # Attempt to fix issues automatically
# -----------------------------------------------------------------------------

NGINX_CONF="./nginx/nginx.conf"
NEEDS_SUDO=false

echo "============================================================"
echo "  nginx.conf SELinux and Permission Diagnostic Tool"
echo "============================================================"
echo ""

# --- Check if nginx.conf exists ---
if [ ! -f "${NGINX_CONF}" ]; then
    echo "[X] ERROR: nginx.conf not found at ${NGINX_CONF}"
    echo ""
    echo "   The nginx configuration file doesn't exist yet."
    echo "   Run './startup.sh' first to generate it."
    echo ""
    exit 1
fi

echo "[ok] Found nginx.conf at ${NGINX_CONF}"
echo ""

# --- Check file permissions ---
echo "Checking file permissions..."
FILE_PERMS=$(stat -c "%a" "${NGINX_CONF}" 2>/dev/null || stat -f "%OLp" "${NGINX_CONF}" 2>/dev/null)
FILE_OWNER=$(stat -c "%u" "${NGINX_CONF}" 2>/dev/null || stat -f "%u" "${NGINX_CONF}" 2>/dev/null)
CURRENT_UID=$(id -u)

echo "  Current permissions: ${FILE_PERMS}"
echo "  File owner UID: ${FILE_OWNER}"
echo "  Current user UID: ${CURRENT_UID}"
echo ""

PERMS_OK=true

# Check if permissions are readable (at least 4 in the owner position)
if [ "${FILE_PERMS}" != "644" ] && [ "${FILE_PERMS}" != "444" ] && [ "${FILE_PERMS}" != "600" ] && [ "${FILE_PERMS}" != "400" ]; then
    echo "[WARNING]  WARNING: Unusual file permissions detected"
    echo "   Recommended: 644 (readable by all, writable by owner)"
    echo "   Current: ${FILE_PERMS}"
    PERMS_OK=false
else
    echo "[ok] File permissions are acceptable"
fi

# Check ownership
if [ "${FILE_OWNER}" != "${CURRENT_UID}" ]; then
    echo "[WARNING]  WARNING: File is not owned by current user"
    echo "   File owner: UID ${FILE_OWNER}"
    echo "   Current user: UID ${CURRENT_UID}"
    echo "   This might cause issues with Podman rootless"
    PERMS_OK=false
    NEEDS_SUDO=true
else
    echo "[ok] File ownership is correct"
fi

echo ""

# --- Check SELinux status ---
echo "Checking SELinux status..."

SELINUX_AVAILABLE=true
if ! command -v getenforce &> /dev/null; then
    echo "[INFO]  SELinux tools not installed (getenforce not found)"
    echo "   If you're on openSUSE/SUSE, install with:"
    echo "     sudo transactional-update pkg install setools-console"
    echo "     sudo reboot"
    echo ""
    echo "   If SELinux is not in use on your system, you can ignore this."
    echo ""
    SELINUX_AVAILABLE=false
    SELINUX_OK=true  # No SELinux, so no SELinux issues
else
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
    echo "  SELinux status: ${SELINUX_STATUS}"
    echo ""

    if [ "${SELINUX_STATUS}" = "Disabled" ]; then
        echo "[ok] SELinux is disabled - no context issues expected"
        echo ""
        SELINUX_OK=true
    else
        # SELinux is enabled - check context
        echo "Checking SELinux context..."
        
        if command -v ls &> /dev/null && ls -Z "${NGINX_CONF}" &> /dev/null; then
            CURRENT_CONTEXT=$(ls -Z "${NGINX_CONF}" 2>/dev/null | awk '{print $1}')
            echo "  Current context: ${CURRENT_CONTEXT}"
            echo ""
            
            # Check if context is suitable for containers
            if echo "${CURRENT_CONTEXT}" | grep -q "container_file_t\|svirt_sandbox_file_t"; then
                echo "[ok] SELinux context is suitable for Podman containers"
                SELINUX_OK=true
            else
                echo "[X] SELinux context may prevent Podman from accessing this file"
                echo ""
                echo "   Current context: ${CURRENT_CONTEXT}"
                echo "   Expected context: *:container_file_t:* or *:svirt_sandbox_file_t:*"
                echo ""
                echo "   This is the likely cause of 'Permission denied' errors"
                echo "   when nginx tries to read /etc/nginx/nginx.conf"
                SELINUX_OK=false
            fi
        else
            echo "[WARNING]  Could not determine SELinux context"
            SELINUX_OK=false
        fi
        
        echo ""
    fi
fi

# --- Show summary and recommendations ---
if [ "${PERMS_OK}" = true ] && [ "${SELINUX_OK}" = true ]; then
    echo "============================================================"
    echo "  [ok] All checks passed - no issues detected"
    echo "============================================================"
    exit 0
fi

echo "  Issues detected - Recommendations:"
echo "============================================================"
echo ""

if [ "${PERMS_OK}" = false ]; then
    echo "Permission fixes:"
    if [ "${FILE_OWNER}" != "${CURRENT_UID}" ]; then
        echo "  sudo chown ${CURRENT_UID} ${NGINX_CONF}"
    fi
    if [ "${FILE_PERMS}" != "644" ]; then
        echo "  chmod 644 ${NGINX_CONF}"
    fi
    echo ""
fi

if [ "${SELINUX_OK}" = false ]; then
    echo "SELinux context fix:"
    if [ "${NEEDS_SUDO}" = true ]; then
        echo "  sudo chcon -t container_file_t ${NGINX_CONF}"
    else
        echo "  chcon -t container_file_t ${NGINX_CONF}"
    fi
    echo ""
    echo "Alternative: The startup.sh script now uses the :Z mount flag"
    echo "which should automatically relabel the file when the container starts."
    echo ""
fi

# --- Auto-fix mode ---
if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo "============================================================"
    echo "  Attempting automatic fixes..."
    echo "============================================================"
    echo ""
    
    FIXED_SOMETHING=false
    
    # Fix permissions
    if [ "${FILE_PERMS}" != "644" ]; then
        echo "Setting file permissions to 644..."
        if chmod 644 "${NGINX_CONF}"; then
            echo "[ok] Permissions updated"
            FIXED_SOMETHING=true
        else
            echo "[X] Failed to update permissions"
        fi
    fi
    
    # Fix ownership (requires sudo if owned by different user)
    if [ "${FILE_OWNER}" != "${CURRENT_UID}" ]; then
        echo "Attempting to fix file ownership..."
        if [ "${NEEDS_SUDO}" = true ]; then
            echo "  (requires sudo access)"
            if sudo chown "${CURRENT_UID}" "${NGINX_CONF}"; then
                echo "[ok] Ownership updated"
                FIXED_SOMETHING=true
            else
                echo "[X] Failed to update ownership"
            fi
        fi
    fi
    
    # Fix SELinux context
    if [ "${SELINUX_OK}" = false ] && [ "${SELINUX_STATUS}" != "Disabled" ]; then
        echo "Attempting to fix SELinux context..."
        
        if command -v chcon &> /dev/null; then
            # Try without sudo first
            if chcon -t container_file_t "${NGINX_CONF}" 2>/dev/null; then
                echo "[ok] SELinux context updated"
                NEW_CONTEXT=$(ls -Z "${NGINX_CONF}" 2>/dev/null | awk '{print $1}')
                echo "  New context: ${NEW_CONTEXT}"
                FIXED_SOMETHING=true
            else
                # Try with sudo
                echo "  (requires sudo access)"
                if sudo chcon -t container_file_t "${NGINX_CONF}"; then
                    echo "[ok] SELinux context updated with sudo"
                    NEW_CONTEXT=$(ls -Z "${NGINX_CONF}" 2>/dev/null | awk '{print $1}')
                    echo "  New context: ${NEW_CONTEXT}"
                    FIXED_SOMETHING=true
                else
                    echo "[X] Failed to update SELinux context"
                    echo "   You may need to run this with appropriate permissions"
                fi
            fi
        else
            echo "[X] chcon command not found - cannot fix SELinux context"
        fi
    fi
    
    echo ""
    if [ "${FIXED_SOMETHING}" = true ]; then
        echo "============================================================"
        echo "  [ok] Fixes applied - you can now run ./startup.sh"
        echo "============================================================"
    else
        echo "============================================================"
        echo "  No automatic fixes could be applied"
        echo "  Please manually apply the recommendations above"
        echo "============================================================"
    fi
else
    echo "Run with --fix to attempt automatic repairs:"
    echo "  ./fix-nginx-selinux.sh --fix"
fi

echo ""
