#!/bin/bash
#
# Lenovo P16 (RTX 4090) Ubuntu Server 24.04 Setup Script
# Configures laptop as a headless GPU server for AI workloads
#
# Usage: curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/setup.sh | sudo bash
#    or: sudo bash setup.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

header "Lenovo P16 GPU Server Setup"

# ============================================
# Collect Firewall Configuration
# ============================================
echo -e "${YELLOW}Firewall Configuration${NC}"
echo ""
echo "Enter the IP addresses or networks that should be allowed to connect."
echo "Examples: 192.168.1.0/24, 10.0.0.5, 203.0.113.0/24"
echo ""

ALLOWED_IPS=()

while true; do
    read -p "Enter IP or network (or press Enter when done): " ip_input

    if [[ -z "$ip_input" ]]; then
        if [[ ${#ALLOWED_IPS[@]} -eq 0 ]]; then
            echo -e "${RED}Error: You must enter at least one IP address or network.${NC}"
            continue
        fi
        break
    fi

    # Basic validation - check if it looks like an IP or CIDR
    if [[ "$ip_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        ALLOWED_IPS+=("$ip_input")
        echo -e "${GREEN}Added: $ip_input${NC}"
    else
        echo -e "${RED}Invalid format. Please enter a valid IP (e.g., 10.0.0.1) or CIDR (e.g., 10.0.0.0/24)${NC}"
    fi
done

echo ""
echo -e "${BLUE}Allowed IPs/Networks:${NC}"
for ip in "${ALLOWED_IPS[@]}"; do
    echo "  - $ip"
done
echo ""
read -p "Is this correct? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled. Please run the script again."
    exit 1
fi

# ============================================
# Collect Network Configuration
# ============================================
echo ""
echo -e "${YELLOW}Network Configuration${NC}"
echo ""
echo "  1) DHCP (automatic IP from router)"
echo "  2) Static IP (manual configuration)"
echo ""
read -p "Select network mode [1]: " NET_MODE
NET_MODE=${NET_MODE:-1}

USE_STATIC=false
if [[ "$NET_MODE" == "2" ]]; then
    USE_STATIC=true
    echo ""

    # Detect current interface
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    read -p "Network interface [$DEFAULT_IFACE]: " NET_IFACE
    NET_IFACE=${NET_IFACE:-$DEFAULT_IFACE}

    read -p "Static IP address (e.g., 192.168.1.100): " STATIC_IP
    while [[ ! "$STATIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        echo -e "${RED}Invalid IP format${NC}"
        read -p "Static IP address: " STATIC_IP
    done

    read -p "Subnet mask in CIDR (e.g., 24 for 255.255.255.0) [24]: " SUBNET_CIDR
    SUBNET_CIDR=${SUBNET_CIDR:-24}

    read -p "Gateway (e.g., 192.168.1.1): " GATEWAY
    while [[ ! "$GATEWAY" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        echo -e "${RED}Invalid IP format${NC}"
        read -p "Gateway: " GATEWAY
    done

    read -p "DNS server 1 [8.8.8.8]: " DNS1
    DNS1=${DNS1:-8.8.8.8}

    read -p "DNS server 2 [8.8.4.4]: " DNS2
    DNS2=${DNS2:-8.8.4.4}

    echo ""
    echo -e "${BLUE}Static IP Configuration:${NC}"
    echo "  Interface: $NET_IFACE"
    echo "  IP: $STATIC_IP/$SUBNET_CIDR"
    echo "  Gateway: $GATEWAY"
    echo "  DNS: $DNS1, $DNS2"
    echo ""
    read -p "Is this correct? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Please run the script again."
        exit 1
    fi
fi

echo ""
log "Starting configuration for Ubuntu Server 24.04..."

# ============================================
# SECTION 1: System Updates
# ============================================
header "1. System Updates"

log "Updating package lists..."
apt-get update

log "Upgrading installed packages..."
apt-get upgrade -y

log "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    htop \
    nvtop \
    vim \
    nano \
    net-tools \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    build-essential \
    linux-headers-$(uname -r)

# ============================================
# SECTION 2: OpenSSH Server
# ============================================
header "2. OpenSSH Server Configuration"

log "Installing OpenSSH server..."
apt-get install -y openssh-server

log "Enabling SSH service..."
systemctl enable ssh
systemctl start ssh

log "Configuring SSH security settings..."
# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Create secure SSH config
cat > /etc/ssh/sshd_config.d/99-security.conf << 'EOF'
# Security hardening
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 5
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

log "Restarting SSH service..."
systemctl restart ssh

# ============================================
# SECTION 3: Lid Close & Power Management
# ============================================
header "3. Lid Close & Power Management"

log "Configuring lid close behavior (ignore lid close)..."
# Create directory first, then configure logind to ignore lid close
mkdir -p /etc/systemd/logind.conf.d

cat > /etc/systemd/logind.conf.d/lid.conf << 'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
LidSwitchIgnoreInhibited=no
EOF

log "Disabling suspend and hibernate..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

log "Restarting logind..."
systemctl restart systemd-logind

# ============================================
# SECTION 4: Display / OLED Burn-in Prevention
# ============================================
header "4. Display & OLED Burn-in Prevention"

log "Installing console font packages..."
apt-get install -y console-setup kbd

log "Configuring largest console font..."
# Set the largest available console font for better visibility
cat > /etc/default/console-setup << 'EOF'
# Console configuration for large font display
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Terminus"
FONTSIZE="32x16"
EOF

# Apply font immediately
setupcon --force 2>/dev/null || true

# Create systemd service to ensure font persists
cat > /etc/systemd/system/console-font.service << 'EOF'
[Unit]
Description=Set large console font
After=systemd-vconsole-setup.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/setupcon --force
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable console-font.service

log "Configuring console blanking..."
# Set console to blank after 1 minute
cat >> /etc/default/grub << 'EOF'

# Blank console after 60 seconds to prevent OLED burn-in
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX consoleblank=60"
EOF

log "Updating GRUB..."
update-grub

log "Setting up kernel console blanking..."
# Set immediate blanking
setterm --blank 1 --powerdown 2 2>/dev/null || true

# Create systemd service for console blanking
cat > /etc/systemd/system/console-blank.service << 'EOF'
[Unit]
Description=Blank console to prevent OLED burn-in
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/setterm --blank 1 --powerdown 2
ExecStart=/bin/sh -c 'echo 1 > /sys/module/kernel/parameters/consoleblank'
StandardOutput=tty
TTYPath=/dev/console
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable console-blank.service

# Disable graphical target if installed
log "Ensuring text-mode boot..."
systemctl set-default multi-user.target 2>/dev/null || true

# ============================================
# SECTION 5: NVIDIA Drivers
# ============================================
header "5. NVIDIA Driver Installation"

log "Adding NVIDIA driver repository..."
# Add NVIDIA PPA for latest drivers
add-apt-repository -y ppa:graphics-drivers/ppa
apt-get update

log "Installing NVIDIA drivers..."
# Install the recommended driver (usually 535+ for RTX 4090)
apt-get install -y nvidia-driver-550 nvidia-utils-550

log "Installing nvidia-smi and related tools..."
apt-get install -y nvidia-settings 2>/dev/null || true

# ============================================
# SECTION 6: NVIDIA Container Toolkit
# ============================================
header "6. NVIDIA Container Toolkit"

log "Adding NVIDIA Container Toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update

log "Installing NVIDIA Container Toolkit..."
apt-get install -y nvidia-container-toolkit

# ============================================
# SECTION 7: Docker Installation
# ============================================
header "7. Docker Installation"

log "Removing old Docker versions..."
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

log "Adding Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update

log "Installing Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Configuring Docker to use NVIDIA runtime..."
nvidia-ctk runtime configure --runtime=docker

log "Enabling Docker service..."
systemctl enable docker
systemctl start docker

# Add current user to docker group (if not root)
if [ -n "$SUDO_USER" ]; then
    log "Adding $SUDO_USER to docker group..."
    usermod -aG docker "$SUDO_USER"
fi

# ============================================
# SECTION 8: UFW Firewall Configuration
# ============================================
header "8. Firewall Configuration"

log "Installing UFW..."
apt-get install -y ufw

log "Resetting UFW to defaults..."
ufw --force reset

log "Setting default policies (deny all incoming)..."
ufw default deny incoming
ufw default allow outgoing

log "Configuring SSH access..."

# Only open SSH by default - service ports are opened by install-service
for ip in "${ALLOWED_IPS[@]}"; do
    log "  Allowing SSH from $ip..."
    ufw allow from $ip to any port 22 proto tcp
done

log "Note: Additional ports will be opened when you install services via 'install-service'"

log "Enabling UFW..."
echo "y" | ufw enable

log "UFW status:"
ufw status verbose

# Save allowed IPs for install-service to use later
mkdir -p /etc/gpu-server
echo "# Allowed IPs for firewall rules" > /etc/gpu-server/allowed-ips.conf
for ip in "${ALLOWED_IPS[@]}"; do
    echo "$ip" >> /etc/gpu-server/allowed-ips.conf
done

# ============================================
# SECTION 9: Network Configuration (Static IP)
# ============================================
if [ "$USE_STATIC" = true ]; then
    header "9. Static IP Configuration"

    log "Configuring static IP via netplan..."

    # Backup existing netplan config
    cp /etc/netplan/*.yaml /etc/netplan/backup.yaml 2>/dev/null || true

    # Create new netplan config
    cat > /etc/netplan/00-static-config.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $NET_IFACE:
      dhcp4: no
      addresses:
        - $STATIC_IP/$SUBNET_CIDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - $DNS1
          - $DNS2
EOF

    chmod 600 /etc/netplan/00-static-config.yaml

    log "Static IP configured: $STATIC_IP/$SUBNET_CIDR"
    log "Note: New IP will take effect after reboot"
else
    header "9. Network Configuration"
    log "Using DHCP (no changes needed)"
fi

# ============================================
# SECTION 10: Performance Tuning
# ============================================
header "10. Performance Tuning"

log "Configuring GPU persistence mode..."
cat > /etc/systemd/system/nvidia-persistenced.service << 'EOF'
[Unit]
Description=NVIDIA Persistence Daemon
Wants=syslog.target

[Service]
Type=forking
ExecStart=/usr/bin/nvidia-persistenced --verbose
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nvidia-persistenced

log "Setting up swap (8GB)..."
if [ ! -f /swapfile ]; then
    fallocate -l 8G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

log "Optimizing kernel parameters..."
cat > /etc/sysctl.d/99-gpu-server.conf << 'EOF'
# Reduce swappiness for GPU workloads
vm.swappiness=10

# Increase inotify watches for file-heavy workloads
fs.inotify.max_user_watches=524288

# Network optimizations
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF

sysctl -p /etc/sysctl.d/99-gpu-server.conf

# ============================================
# SECTION 11: Create Test Script
# ============================================
header "11. Creating Test Script"

cat > /usr/local/bin/test-gpu-setup << 'EOF'
#!/bin/bash
# Test script to verify GPU server setup

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "======================================"
echo " GPU Server Setup Verification"
echo "======================================"
echo ""

# Test 1: NVIDIA Driver
echo "1. NVIDIA Driver..."
if nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    pass "NVIDIA driver loaded - $GPU_NAME"
else
    fail "NVIDIA driver not working"
fi

# Test 2: Docker
echo "2. Docker..."
if docker --version &>/dev/null; then
    pass "Docker installed - $(docker --version)"
else
    fail "Docker not installed"
fi

# Test 3: Docker GPU Access
echo "3. Docker GPU Access..."
if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
    pass "Docker can access GPU"
else
    fail "Docker cannot access GPU"
fi

# Test 4: UFW Firewall
echo "4. UFW Firewall..."
if ufw status | grep -q "Status: active"; then
    pass "UFW is active"
else
    fail "UFW is not active"
fi

# Test 5: SSH
echo "5. SSH Service..."
if systemctl is-active --quiet ssh; then
    pass "SSH is running"
else
    fail "SSH is not running"
fi

# Test 6: Lid Close Handling
echo "6. Lid Close Config..."
if grep -q "HandleLidSwitch=ignore" /etc/systemd/logind.conf.d/lid.conf 2>/dev/null; then
    pass "Lid close set to ignore"
else
    fail "Lid close not configured"
fi

# Test 7: Display Blanking
echo "7. Console Blanking..."
if grep -q "consoleblank=60" /proc/cmdline 2>/dev/null || systemctl is-enabled console-blank.service &>/dev/null; then
    pass "Console blanking configured"
else
    fail "Console blanking not configured (will work after reboot)"
fi

# Test 8: Large Console Font
echo "8. Console Font..."
if grep -q "FONTSIZE=\"32x16\"" /etc/default/console-setup 2>/dev/null; then
    pass "Large console font configured (Terminus 32x16)"
else
    fail "Console font not configured"
fi

# Test 9: Suspend Disabled
echo "9. Suspend/Hibernate..."
SUSPEND_STATUS=$(systemctl is-enabled suspend.target 2>/dev/null || echo "unknown")
if [[ "$SUSPEND_STATUS" == "masked" ]]; then
    pass "Suspend is disabled (masked)"
elif [[ "$SUSPEND_STATUS" == "disabled" ]]; then
    pass "Suspend is disabled"
else
    fail "Suspend may still be enabled ($SUSPEND_STATUS)"
fi

echo ""
echo "======================================"
echo " System Information"
echo "======================================"
echo ""
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "Kernel: $(uname -r)"
echo ""
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
echo ""
echo "======================================"
EOF

chmod +x /usr/local/bin/test-gpu-setup

# ============================================
# SECTION 12: Create Management Scripts
# ============================================
header "12. Creating Management Scripts"

# GPU monitoring script
cat > /usr/local/bin/gpu-monitor << 'EOF'
#!/bin/bash
watch -n 1 nvidia-smi
EOF
chmod +x /usr/local/bin/gpu-monitor

# Quick status script
cat > /usr/local/bin/server-status << 'EOF'
#!/bin/bash
echo "=== GPU Status ==="
nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | \
    awk -F',' '{printf "GPU: %s | Temp: %s°C | Util: %s%% | VRAM: %s/%s MB\n", $1, $2, $3, $4, $5}'
echo ""
echo "=== Docker Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "=== System Resources ==="
free -h | grep Mem | awk '{printf "RAM: %s used / %s total\n", $3, $2}'
df -h / | tail -1 | awk '{printf "Disk: %s used / %s total (%s)\n", $3, $2, $5}'
echo ""
echo "=== Network ==="
echo "IP: $(hostname -I | awk '{print $1}')"
echo "Firewall: $(ufw status | head -1)"
EOF
chmod +x /usr/local/bin/server-status

# Service installer script
log "Downloading GPU service installer..."
curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/install-service.sh \
    -o /usr/local/bin/install-service
chmod +x /usr/local/bin/install-service

# Help command (server-commands to avoid conflict with bash built-in 'help')
cat > /usr/local/bin/server-commands << 'EOF'
#!/bin/bash

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}          ${YELLOW}Lenovo P16 GPU Server Commands${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Service Management:${NC}"
echo "  install-service    Install/manage AI services (interactive menu)"
echo ""
echo -e "${GREEN}Monitoring:${NC}"
echo "  server-status      Quick system status (GPU, containers, resources)"
echo "  gpu-monitor        Live GPU monitoring (nvidia-smi watch)"
echo ""
echo -e "${GREEN}Diagnostics:${NC}"
echo "  test-gpu-setup     Verify server configuration"
echo ""
echo -e "${GREEN}Docker:${NC}"
echo "  docker ps          List running containers"
echo "  docker logs <name> View container logs"
echo ""
echo -e "${GREEN}GPU:${NC}"
echo "  nvidia-smi         NVIDIA GPU status"
echo "  nvtop              Interactive GPU monitor"
echo ""
EOF
chmod +x /usr/local/bin/server-commands

# ============================================
# SECTION 13: Final Steps
# ============================================
header "13. Final Configuration"

log "Creating MOTD banner..."
cat > /etc/update-motd.d/99-gpu-server << 'EOF'
#!/bin/bash
echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║     Lenovo P16 GPU Server (RTX 4090)      ║"
echo "  ╠═══════════════════════════════════════════╣"
echo "  ║  Type 'server-commands' for help          ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""
EOF
chmod +x /etc/update-motd.d/99-gpu-server

log "Cleaning up..."
apt-get autoremove -y
apt-get autoclean

# ============================================
# Complete!
# ============================================
header "Setup Complete!"

echo -e "${GREEN}The Lenovo P16 GPU server has been configured successfully!${NC}"
echo ""
echo "Summary of changes:"
echo "  ✓ System packages updated"
echo "  ✓ OpenSSH server installed and secured"
echo "  ✓ Lid close behavior set to ignore (safe to close lid)"
echo "  ✓ Console blanking enabled (OLED protection)"
echo "  ✓ Large console font configured (Terminus 32x16)"
echo "  ✓ Suspend/hibernate disabled"
echo "  ✓ NVIDIA drivers installed (driver 550)"
echo "  ✓ NVIDIA Container Toolkit installed"
echo "  ✓ Docker installed with GPU support"
echo "  ✓ UFW firewall configured (SSH only)"
echo "  ✓ Performance tuning applied"
if [ "$USE_STATIC" = true ]; then
    echo "  ✓ Static IP configured: $STATIC_IP/$SUBNET_CIDR"
fi
echo ""
echo "Firewall allows SSH from:"
for ip in "${ALLOWED_IPS[@]}"; do
    echo "  - $ip"
done
echo ""
echo "To install AI services and open their ports, run: install-service"
echo ""
echo -e "${YELLOW}IMPORTANT: A reboot is required to complete the setup.${NC}"
if [ "$USE_STATIC" = true ]; then
    echo -e "${YELLOW}After reboot, connect via: ssh $(whoami)@$STATIC_IP${NC}"
fi
echo ""
echo "After reboot, run: test-gpu-setup"
echo ""
read -p "Reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Rebooting..."
    reboot
fi
