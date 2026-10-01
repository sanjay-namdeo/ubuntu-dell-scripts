#!/usr/bin/env bash
# ==============================================================================
# Script: setup-dell-dock.sh
# Description: Installs and configures DisplayLink drivers and EVDI kernel
#              module for Dell Universal Dock D6000 (and other DisplayLink docks)
#              on Ubuntu to fix external monitor display issues.
# Reference: dell-docking-station.md
# ==============================================================================

set -euo pipefail

# ANSI formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log()    { echo -e "${GREEN}[✔]${RESET} $1"; }
warn()   { echo -e "${YELLOW}[⚠]${RESET} $1"; }
info()   { echo -e "${CYAN}[→]${RESET} $1"; }
err()    { echo -e "${RED}[✘]${RESET} $1"; }
header() { echo -e "\n${BOLD}${BLUE}=== $1 ===${RESET}"; }

SCRIPT_PATH="$(readlink -f "$0")"
KEYRING_URL="https://www.synaptics.com/sites/default/files/Ubuntu/pool/stable/main/all/synaptics-repository-keyring.deb"
SYNAPTICS_LIST="/etc/apt/sources.list.d/synaptics.list"
SYNAPTICS_KEYRING="/usr/share/keyrings/synaptics-repository-keyring.gpg"
GDM_CONF="/etc/gdm3/custom.conf"

FORCE_XORG=false
CHECK_ONLY=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --force-xorg)
            FORCE_XORG=true
            ;;
        --check)
            CHECK_ONLY=true
            ;;
        -h|--help)
            echo "Usage: sudo $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force-xorg   Set GDM to default to Xorg session in /etc/gdm3/custom.conf"
            echo "  --check        Check current DisplayLink, EVDI, and dock status without making changes"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            warn "Unknown option '$arg', ignoring."
            ;;
    esac
done

# Ensure standard PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Resolve real user and session
ORIG_USER="${SUDO_USER:-${PKEXEC_UID:+$(id -nu "$PKEXEC_UID" 2>/dev/null || true)}}"
ORIG_USER="${ORIG_USER:-$USER}"

# Check status helper
check_status() {
    header "DisplayLink & Dock Hardware Diagnostics"
    echo -e "${BOLD}1. Hardware Detection:${RESET}"
    if lsusb | grep -i "17e9:" >/dev/null; then
        local dock_info
        dock_info="$(lsusb | grep -i "17e9:")"
        log "Found DisplayLink device: ${dock_info}"
    else
        warn "No DisplayLink (17e9:*) device detected via lsusb. Is dock plugged in?"
    fi

    echo -e "\n${BOLD}2. EVDI Kernel Module:${RESET}"
    if lsmod | grep -E "^evdi[[:space:]]" >/dev/null; then
        log "Kernel module 'evdi' is currently loaded."
        local evdi_ver
        evdi_ver="$(modinfo -F version evdi 2>/dev/null || true)"
        [ -z "$evdi_ver" ] && evdi_ver="$(dpkg-query -W -f='${Version}' libevdi1 2>/dev/null || dpkg-query -W -f='${Version}' "linux-main-modules-evdi-$(uname -r)" 2>/dev/null || echo "active")"
        info "EVDI version: ${evdi_ver}"
    else
        warn "Kernel module 'evdi' is NOT loaded."
    fi

    echo -e "\n${BOLD}3. DisplayLink Service:${RESET}"
    if systemctl is-active --quiet displaylink-driver 2>/dev/null; then
        log "displaylink-driver.service is active (running)."
        local dl_ver
        dl_ver="$(dpkg-query -W -f='${Version}' displaylink-driver 2>/dev/null || echo "unknown")"
        info "DisplayLink driver package version: ${dl_ver}"
    else
        warn "displaylink-driver.service is not active."
    fi

    echo -e "\n${BOLD}4. Display Server Session:${RESET}"
    local sess_type="${XDG_SESSION_TYPE:-unknown}"
    if [ -n "$ORIG_USER" ] && command -v loginctl >/dev/null 2>&1; then
        local user_sess
        user_sess="$(loginctl list-sessions --no-legend 2>/dev/null | grep "$ORIG_USER" | awk '{print $1}' | head -n1 || true)"
        if [ -n "$user_sess" ]; then
            sess_type="$(loginctl show-session "$user_sess" -p Type --value 2>/dev/null || echo "$sess_type")"
        fi
    fi
    info "Current Desktop Session Type: ${sess_type}"
    if [ "$sess_type" = "wayland" ]; then
        warn "Session is Wayland. DisplayLink is most reliable under Xorg (X11)."
    fi

    echo -e "\n${BOLD}5. DRM Card Devices:${RESET}"
    ls -l /dev/dri/card* 2>/dev/null || warn "No DRM card devices found in /dev/dri/."
}

if [ "$CHECK_ONLY" = true ]; then
    check_status
    exit 0
fi

# Privilege elevation
if [ "$(id -u)" -ne 0 ]; then
    info "Elevated privileges required. Escalating to root..."
    if sudo -n true 2>/dev/null; then
        exec sudo "$SCRIPT_PATH" "$@"
    elif [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if command -v pkexec >/dev/null 2>&1; then
            exec pkexec "$SCRIPT_PATH" "$@"
        else
            exec sudo "$SCRIPT_PATH" "$@"
        fi
    else
        exec sudo "$SCRIPT_PATH" "$@"
    fi
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║      Dell D6000 Dock DisplayLink & EVDI Auto-Fix        ║"
echo "║        Ubuntu 26.04 LTS / Dell Latitude Systems         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Step 1: Hardware Check
header "1. Checking Dock Hardware"
if lsusb | grep -i "17e9:6006" >/dev/null; then
    log "Dell Universal Dock D6000 detected (ID 17e9:6006)."
elif lsusb | grep -i "17e9:" >/dev/null; then
    log "DisplayLink dock device detected:"
    lsusb | grep -i "17e9:"
else
    warn "Dell D6000 / DisplayLink dock not detected on USB."
    warn "Please ensure the dock is securely connected to the laptop's USB-C port."
    warn "Continuing with driver installation..."
fi

# Step 2: Install EVDI and Prerequisites
header "2. Installing EVDI Module & Prerequisites"
info "Updating package lists..."
apt-get update -qq

CURRENT_KERNEL="$(uname -r)"
PACKAGES_TO_INSTALL=("dkms" "libdrm-dev" "libevdi1" "linux-modules-evdi-generic" "wget" "curl")

# If Ubuntu provides a pre-signed EVDI module for the running kernel, include it
if apt-cache show "linux-main-modules-evdi-${CURRENT_KERNEL}" >/dev/null 2>&1; then
    info "Found matching signed EVDI kernel module: linux-main-modules-evdi-${CURRENT_KERNEL}"
    PACKAGES_TO_INSTALL+=("linux-main-modules-evdi-${CURRENT_KERNEL}")
fi

info "Installing prerequisite packages: ${PACKAGES_TO_INSTALL[*]}"
apt-get install -y "${PACKAGES_TO_INSTALL[@]}"
log "Prerequisites and EVDI packages installed successfully."

# Step 3: Install Synaptics Official Repository Keyring
header "3. Configuring Synaptics DisplayLink Repository"
if [ -f "$SYNAPTICS_LIST" ] && [ -f "$SYNAPTICS_KEYRING" ]; then
    log "Synaptics repository is already configured."
else
    info "Downloading Synaptics repository keyring package..."
    TMP_KEYRING_DEB="$(mktemp /tmp/synaptics-keyring-XXXXXX.deb)"
    if wget -q --show-progress "$KEYRING_URL" -O "$TMP_KEYRING_DEB"; then
        info "Installing Synaptics keyring package..."
        apt-get install -y "$TMP_KEYRING_DEB"
        rm -f "$TMP_KEYRING_DEB"
        log "Synaptics repository keyring installed."
    else
        rm -f "$TMP_KEYRING_DEB"
        err "Failed to download Synaptics repository keyring from $KEYRING_URL."
        exit 1
    fi
fi

# Step 4: Install DisplayLink Driver
header "4. Installing Synaptics DisplayLink Driver"
info "Updating repository indexes..."
apt-get update -qq

info "Installing displaylink-driver package..."
apt-get install -y displaylink-driver
log "DisplayLink driver package installed successfully."

# Step 5: Configure and Load Kernel Module
header "5. Configuring and Loading EVDI Kernel Module"
mkdir -p /etc/modules-load.d /etc/modprobe.d

# Ensure evdi is loaded on boot
echo "evdi" > /etc/modules-load.d/evdi.conf

# Ensure options evdi initial_device_count=4
if [ -f /etc/modprobe.d/evdi.conf ]; then
    if grep -q '^options evdi initial_device_count' /etc/modprobe.d/evdi.conf; then
        sed -i 's/^options evdi initial_device_count=.*/options evdi initial_device_count=4/' /etc/modprobe.d/evdi.conf
    else
        echo "options evdi initial_device_count=4" >> /etc/modprobe.d/evdi.conf
    fi
else
    echo "options evdi initial_device_count=4" > /etc/modprobe.d/evdi.conf
fi

info "Loading evdi kernel module..."
if modprobe evdi; then
    log "evdi kernel module loaded into running kernel."
else
    warn "modprobe evdi returned non-zero. Check dmesg for details."
fi

# Step 6: Secure Boot Verification
header "6. Checking Secure Boot Status"
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -i "enabled" >/dev/null; then
    info "Secure Boot is enabled on this system."
    if lsmod | grep -E "^evdi[[:space:]]" >/dev/null; then
        log "EVDI module is signed and active under Secure Boot."
    else
        warn "EVDI module is not currently loaded under Secure Boot."
        warn "If prompted during installation or on next reboot, complete the MOK enrollment screen:"
        warn "  1. Select 'Enroll MOK' -> Continue"
        warn "  2. Confirm 'Yes'"
        warn "  3. Enter password set during install -> Reboot"
    fi
else
    info "Secure Boot is disabled or not active; no MOK enrollment necessary."
fi

# Step 7: Service Activation & Udev Triggers
header "7. Activating DisplayLink Systemd Service"
systemctl daemon-reload
systemctl enable displaylink-driver.service
systemctl restart displaylink-driver.service

if systemctl is-active --quiet displaylink-driver.service; then
    log "displaylink-driver.service is active and running!"
else
    warn "displaylink-driver.service is not currently active. Status:"
    systemctl status displaylink-driver.service --no-pager || true
fi

info "Reloading udev rules and triggering USB devices..."
udevadm control --reload-rules || true
udevadm trigger --subsystem-match=usb || true

# Step 8: Desktop Session (Wayland vs Xorg)
header "8. Desktop Display Server Configuration"
CURR_SESSION="${XDG_SESSION_TYPE:-wayland}"
if [ -n "$ORIG_USER" ] && command -v loginctl >/dev/null 2>&1; then
    user_sess="$(loginctl list-sessions --no-legend 2>/dev/null | grep "$ORIG_USER" | awk '{print $1}' | head -n1 || true)"
    if [ -n "$user_sess" ]; then
        CURR_SESSION="$(loginctl show-session "$user_sess" -p Type --value 2>/dev/null || echo "$CURR_SESSION")"
    fi
fi

info "Current desktop session type: ${CURR_SESSION}"

if [ "$FORCE_XORG" = true ]; then
    if [ -f "$GDM_CONF" ]; then
        info "Applying WaylandEnable=false in $GDM_CONF as requested..."
        cp "$GDM_CONF" "${GDM_CONF}.bak.$(date +%s)"
        if grep -q "^#WaylandEnable=false" "$GDM_CONF"; then
            sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' "$GDM_CONF"
        elif grep -q "^WaylandEnable=" "$GDM_CONF"; then
            sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' "$GDM_CONF"
        else
            sed -i '/\[daemon\]/a WaylandEnable=false' "$GDM_CONF"
        fi
        log "GDM configured to default to Xorg session upon next login/reboot."
    else
        warn "$GDM_CONF not found; cannot force Xorg globally."
    fi
else
    if [ "$CURR_SESSION" = "wayland" ]; then
        warn "Wayland frequently causes blank screens or monitor detection failures with DisplayLink."
        echo ""
        echo -e "${BOLD}Recommended Action to Activate External Monitors:${RESET}"
        echo "  1. Save your open work and Log Out of Ubuntu."
        echo "  2. At the login screen, click your username (${ORIG_USER})."
        echo "  3. Click the gear icon (⚙️) in the bottom-right corner of the screen."
        echo "  4. Select 'Ubuntu on Xorg' (instead of standard Ubuntu / Wayland)."
        echo "  5. Enter your password to log in."
        echo ""
        echo "  Tip: You can run '$0 --force-xorg' to make Xorg the permanent default in GDM."
    fi
fi

# Step 9: Final Verification & Instructions
header "9. Summary and Next Steps"
echo -e "${GREEN}${BOLD}✔ DisplayLink driver and EVDI setup completed successfully!${RESET}\n"
echo -e "${BOLD}To get external displays working right now:${RESET}"
echo "  1. Unplug the USB-C dock connector from the laptop, wait 5 seconds, and plug it back in."
echo "  2. If using Wayland and monitors do not appear, switch to 'Ubuntu on Xorg' as described above."
echo "  3. Open Settings -> Displays to arrange and position your external screens."
echo "  4. Verify cable setup: both monitors must connect directly to the dock ports (HDMI / DP);"
echo "     the D6000 dock does not support DisplayPort daisy chaining (MST)."
echo ""
