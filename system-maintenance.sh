#!/bin/bash
# ============================================================
# System Maintenance Script for Ubuntu 26.04 LTS
# Dell Laptop - Intel i7-10610U
# Generated: 2026-09-06
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()    { echo -e "${GREEN}[✔]${RESET} $1"; }
warn()   { echo -e "${YELLOW}[⚠]${RESET} $1"; }
info()   { echo -e "${CYAN}[→]${RESET} $1"; }
header() { echo -e "\n${BOLD}${BLUE}━━━ $1 ━━━${RESET}"; }

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[✘]${RESET} Must run as root (use sudo)."
  exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="/home/$REAL_USER"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║       Ubuntu System Maintenance & Optimization       ║"
echo "║              Dell Laptop  $(date '+%Y-%m-%d %H:%M:%S')           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# 1. SYSTEM UPDATES
header "1. SYSTEM UPDATES"
info "Updating package lists..."
apt-get update -qq
info "Upgrading all packages..."
apt-get upgrade -y
info "Performing dist-upgrade..."
apt-get dist-upgrade -y
log "All packages up-to-date"

# 2. OLD KERNEL REMOVAL
header "2. REMOVING OLD LINUX KERNELS"
CURRENT_KERNEL=$(uname -r)
info "Current kernel: $CURRENT_KERNEL"
OLD_KERNELS=$(dpkg --list | grep 'linux-image-[0-9]' | grep '^rc\|^ii' \
  | awk '{print $2}' | grep -v "$CURRENT_KERNEL" | grep -v "linux-image-generic")
if [[ -n "$OLD_KERNELS" ]]; then
  warn "Removing old kernels: $OLD_KERNELS"
  apt-get remove --purge -y $OLD_KERNELS 2>/dev/null || true
  OLD_HEADERS=$(dpkg --list | grep 'linux-headers-[0-9]' | grep '^rc\|^ii' \
    | awk '{print $2}' | grep -v "$CURRENT_KERNEL")
  [[ -n "$OLD_HEADERS" ]] && apt-get remove --purge -y $OLD_HEADERS 2>/dev/null || true
  OLD_MODULES=$(dpkg --list | grep 'linux-modules-[0-9]' | grep '^rc\|^ii' \
    | awk '{print $2}' | grep -v "$CURRENT_KERNEL")
  [[ -n "$OLD_MODULES" ]] && apt-get remove --purge -y $OLD_MODULES 2>/dev/null || true
  log "Old kernels and associated packages removed"
else
  log "No old kernels to remove"
fi

# 3. AUTOREMOVE
header "3. REMOVING UNUSED PACKAGES"
apt-get autoremove --purge -y
log "Unused dependencies removed"

# 4. APT CACHE
header "4. APT CACHE CLEANUP"
BEFORE=$(du -sh /var/cache/apt | cut -f1)
apt-get clean && apt-get autoclean
AFTER=$(du -sh /var/cache/apt | cut -f1)
log "APT cache: $BEFORE → $AFTER"

# 5. JOURNAL CLEANUP
header "5. JOURNAL LOG CLEANUP"
JBEFORE=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+\s*[GMKB]+(?= in)' || echo "?")
info "Journal size before: $JBEFORE"
journalctl --vacuum-time=7d --vacuum-size=500M
JAFTER=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+\s*[GMKB]+(?= in)' || echo "?")
log "Journal size after: $JAFTER"

# 6. OLD LOG FILES
header "6. OLD LOG FILES CLEANUP"
LBEFORE=$(du -sh /var/log | cut -f1)
find /var/log -name "*.gz" -mtime +14 -delete 2>/dev/null || true
find /var/log -name "*.1" -mtime +14 -delete 2>/dev/null || true
find /var/log -name "*.old" -mtime +14 -delete 2>/dev/null || true
LAFTER=$(du -sh /var/log | cut -f1)
log "Log directory: $LBEFORE → $LAFTER"

# 7. USER CACHE CLEANUP
header "7. USER CACHE CLEANUP"
# Chrome cache
CHROME_CACHE="$HOME_DIR/.cache/google-chrome"
if [[ -d "$CHROME_CACHE" ]]; then
  CSIZE=$(du -sh "$CHROME_CACHE" | cut -f1)
  info "Chrome cache before: $CSIZE"
  find "$CHROME_CACHE" -type d -name "Cache" -exec sh -c 'rm -rf "$1"/*' _ {} \; 2>/dev/null || true
  find "$CHROME_CACHE" -type d -name "Code Cache" -exec sh -c 'rm -rf "$1"/*' _ {} \; 2>/dev/null || true
  find "$CHROME_CACHE" -type d -name "GPUCache" -exec sh -c 'rm -rf "$1"/*' _ {} \; 2>/dev/null || true
  log "Chrome cache cleared (profile/sessions preserved)"
fi

# node-gyp cache
if [[ -d "$HOME_DIR/.cache/node-gyp" ]]; then
  SZ=$(du -sh "$HOME_DIR/.cache/node-gyp" | cut -f1)
  rm -rf "$HOME_DIR/.cache/node-gyp"
  log "node-gyp cache removed ($SZ)"
fi

# pip cache
if [[ -d "$HOME_DIR/.cache/pip" ]]; then
  SZ=$(du -sh "$HOME_DIR/.cache/pip" | cut -f1)
  rm -rf "$HOME_DIR/.cache/pip"
  log "pip cache removed ($SZ)"
fi

# Old thumbnails
find "$HOME_DIR/.cache/thumbnails" -type f -atime +30 -delete 2>/dev/null || true
log "Old thumbnails cleaned"

# Fix permissions
chown -R "$REAL_USER:$REAL_USER" "$HOME_DIR/.cache" 2>/dev/null || true

# 8. TRASH
header "8. EMPTY TRASH"
TRASH="$HOME_DIR/.local/share/Trash"
if [[ -d "$TRASH" ]]; then
  TSIZE=$(du -sh "$TRASH" | cut -f1)
  rm -rf "$TRASH/files/"* "$TRASH/info/"* 2>/dev/null || true
  log "Trash emptied ($TSIZE freed)"
fi

# 9. TEMP FILES
header "9. TEMP FILES CLEANUP"
find /tmp -type f -atime +7 -delete 2>/dev/null || true
find /tmp -mindepth 1 -type d -empty -delete 2>/dev/null || true
log "/tmp cleaned (files older than 7 days removed)"

# 10. DOWNLOADS REPORT
header "10. LARGE FILES IN DOWNLOADS"
DOWNLOADS="$HOME_DIR/Downloads"
if [[ -d "$DOWNLOADS" ]]; then
  LARGE=$(find "$DOWNLOADS" -size +50M -type f 2>/dev/null)
  if [[ -n "$LARGE" ]]; then
    warn "Large files in ~/Downloads (review manually if no longer needed):"
    echo "$LARGE" | while read -r f; do
      echo "  $(du -sh "$f" | cut -f1)  $f"
    done
  else
    log "No large files in Downloads"
  fi
fi

# 11. KERNEL OPTIMIZATION
header "11. KERNEL PARAMETER OPTIMIZATION"
SYSCTL_CONF="/etc/sysctl.d/99-laptop-optimize.conf"
cat > "$SYSCTL_CONF" << 'SYSCTL'
# Performance tuning - Dell i7-10610U, 16GB RAM, NVMe SSD
# Generated by system-maintenance.sh

# Prefer RAM over swap (great for 16GB systems)
vm.swappiness=10

# Cache more filesystem metadata
vm.vfs_cache_pressure=50

# SSD-optimized dirty page ratios
vm.dirty_ratio=10
vm.dirty_background_ratio=5

# Network performance
net.core.netdev_max_backlog=16384
net.ipv4.tcp_fastopen=3
SYSCTL
sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1 || true
log "Kernel parameters optimized (swappiness=10, vfs_cache=50, dirty tuning)"

# 12. SSD TRIM
header "12. NVMe SSD TRIM"
fstrim -av 2>/dev/null && log "TRIM completed" || warn "TRIM failed or not supported"
if ! systemctl is-enabled fstrim.timer &>/dev/null; then
  systemctl enable --now fstrim.timer 2>/dev/null && log "Weekly TRIM timer enabled" || true
else
  log "Weekly TRIM timer already active"
fi

# 13. FAILED UNITS
header "13. SYSTEMD FAILED UNITS"
FAILED=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
if [[ $FAILED -gt 0 ]]; then
  warn "$FAILED failed unit(s) found:"
  systemctl --failed 2>/dev/null
  systemctl reset-failed 2>/dev/null || true
  log "Failed units reset"
else
  log "All systemd units healthy"
fi

# 14. FIREWALL
header "14. FIREWALL (UFW)"
if command -v ufw &>/dev/null; then
  # Always ensure SSH is allowed FIRST to prevent remote lockout
  info "Ensuring SSH access is allowed before any firewall changes..."
  ufw allow ssh > /dev/null 2>&1
  ufw allow OpenSSH > /dev/null 2>&1
  log "SSH rule confirmed (port 22 allowed)"

  UFW_STATUS=$(ufw status | head -1)
  log "UFW current status: $UFW_STATUS"
  if echo "$UFW_STATUS" | grep -q "inactive"; then
    ufw --force enable
    log "UFW enabled (SSH allowed, deny other incoming / allow outgoing)"
  else
    log "UFW already active — SSH rule added/confirmed"
  fi

  # Show current rules for transparency
  info "Active UFW rules:"
  ufw status numbered 2>/dev/null || true
fi

# 15. FONT CACHE
header "15. FONT CACHE"
fc-cache -f 2>/dev/null && log "Font cache rebuilt" || warn "fc-cache failed"

# 16. LOCATE DB
header "16. LOCATE DATABASE"
if command -v updatedb &>/dev/null; then
  updatedb 2>/dev/null && log "locate database updated" || warn "updatedb failed"
fi

# 17. SUMMARY
header "17. FINAL SUMMARY"
echo ""
DISK=$(df -h / | tail -1 | awk '{print $3 " used / " $2 " (" $5 ")"}')
RAM=$(free -h | grep Mem | awk '{print $3 " used / " $2}')
SWAP=$(free -h | grep Swap | awk '{print $3 " used / " $2}')
KERN=$(uname -r)
LOAD=$(cat /proc/loadavg | cut -d' ' -f1-3)

echo -e "  ${BOLD}Post-Maintenance System Status:${RESET}"
echo -e "  Disk  : $DISK"
echo -e "  RAM   : $RAM"
echo -e "  Swap  : $SWAP"
echo -e "  Kernel: $KERN"
echo -e "  Load  : $LOAD"
echo ""
echo -e "${BOLD}${GREEN}  ✔  Maintenance Complete!${RESET}"
echo ""
warn "Recommend a reboot to complete kernel updates."
echo ""
