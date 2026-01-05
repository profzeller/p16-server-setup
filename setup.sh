#!/bin/bash
#
# Lenovo P16 (RTX 4090) GPU Server Setup Utility
# Interactive menu for configuring and managing headless GPU servers
#
# First run: Runs full setup automatically
# Subsequent runs: Shows interactive menu
#
# Usage: server-setup (after installation)
#    or: sudo bash setup.sh (first time)
#

set -e

# ============================================
# Colors and Formatting
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================
# Configuration
# ============================================
MARKER_FILE="/etc/gpu-server/.setup-complete"
CONFIG_DIR="/etc/gpu-server"
INSTALL_DIR="/opt/gpu-services"

# ============================================
# Helper Functions
# ============================================
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
}

press_enter() {
    echo ""
    read -p "Press Enter to continue..."
}

confirm() {
    local msg="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        read -p "$msg (Y/n): " response
        [[ -z "$response" || "$response" =~ ^[Yy] ]]
    else
        read -p "$msg (y/N): " response
        [[ "$response" =~ ^[Yy] ]]
    fi
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This operation requires root privileges"
        echo "Run with: sudo server-setup"
        return 1
    fi
}

# ============================================
# Status Detection Functions
# ============================================
get_hostname() {
    hostname
}

get_username() {
    who | head -1 | awk '{print $1}' 2>/dev/null || echo "unknown"
}

get_nvidia_version() {
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "Error"
    else
        echo "Not installed"
    fi
}

get_docker_version() {
    if command -v docker &>/dev/null; then
        docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "Installed"
    else
        echo "Not installed"
    fi
}

get_network_status() {
    if [ -f /etc/netplan/00-static-config.yaml ]; then
        local ip=$(grep -oP 'addresses:.*\[.\K[0-9.]+' /etc/netplan/00-static-config.yaml 2>/dev/null | head -1)
        if [ -n "$ip" ]; then
            echo "Static: $ip"
        else
            echo "Static"
        fi
    else
        local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo "DHCP: ${ip:-unknown}"
    fi
}

get_ssh_status() {
    if systemctl is-active --quiet ssh 2>/dev/null; then
        echo "${GREEN}Running${NC}"
    else
        echo "${RED}Stopped${NC}"
    fi
}

get_lid_status() {
    if grep -q "HandleLidSwitch=ignore" /etc/systemd/logind.conf.d/lid.conf 2>/dev/null; then
        echo "${GREEN}Configured${NC}"
    else
        echo "${YELLOW}Not configured${NC}"
    fi
}

get_suspend_status() {
    local status=$(systemctl is-enabled suspend.target 2>/dev/null || echo "unknown")
    if [[ "$status" == "masked" || "$status" == "disabled" ]]; then
        echo "${GREEN}Disabled${NC}"
    else
        echo "${YELLOW}Enabled${NC}"
    fi
}

get_service_status() {
    local service_name="$1"
    local port="$2"

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$service_name"; then
        echo "${GREEN}Running :$port${NC}"
    elif [ -d "$INSTALL_DIR/local-${service_name}-server" ]; then
        echo "${YELLOW}Installed${NC}"
    else
        echo "${DIM}Not installed${NC}"
    fi
}

is_first_run() {
    [ ! -f "$MARKER_FILE" ]
}

# ============================================
# Main Menu
# ============================================
show_main_menu() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}         ${BOLD}P16 GPU Server Setup${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}         $(hostname) - $(hostname -I 2>/dev/null | awk '{print $1}')                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Status indicators
    local nvidia_ver=$(get_nvidia_version)
    local docker_ver=$(get_docker_version)
    local net_status=$(get_network_status)

    echo -e "  ${CYAN}1)${NC} System Identity      ${DIM}[$(get_hostname) / $(get_username)]${NC}"
    echo -e "     ${DIM}Change hostname, username, or password${NC}"
    echo ""
    echo -e "  ${CYAN}2)${NC} Network & Firewall   ${DIM}[$net_status]${NC}"
    echo -e "     ${DIM}Configure allowed IPs, DHCP/static IP${NC}"
    echo ""
    echo -e "  ${CYAN}3)${NC} NVIDIA Stack         ${DIM}[Driver: $nvidia_ver]${NC}"
    echo -e "     ${DIM}Install/upgrade drivers and container toolkit${NC}"
    echo ""
    echo -e "  ${CYAN}4)${NC} Docker               ${DIM}[Version: $docker_ver]${NC}"
    echo -e "     ${DIM}Install or reinstall Docker with GPU support${NC}"
    echo ""
    echo -e "  ${CYAN}5)${NC} System Settings  ${MAGENTA}→${NC}"
    echo -e "     ${DIM}SSH, lid close, display blanking, suspend${NC}"
    echo ""
    echo -e "  ${CYAN}6)${NC} Performance Tuning"
    echo -e "     ${DIM}GPU persistence, swap, kernel params${NC}"
    echo ""
    echo -e "  ${CYAN}7)${NC} Management Tools"
    echo -e "     ${DIM}Install/update helper scripts${NC}"
    echo ""
    echo -e "  ${CYAN}8)${NC} AI Services      ${MAGENTA}→${NC}"
    echo -e "     ${DIM}Ollama, vLLM, Chatterbox, ComfyUI, Video${NC}"
    echo ""
    echo -e "  ${CYAN}9)${NC} Tools & Monitoring ${MAGENTA}→${NC}"
    echo -e "     ${DIM}Server status, GPU monitor, diagnostics${NC}"
    echo ""
    echo -e "  ${YELLOW}F)${NC} Run Full Setup"
    echo -e "     ${DIM}Run all configuration sections${NC}"
    echo ""
    echo -e "  ${GREEN}S)${NC} Drop to Shell"
    echo -e "     ${DIM}Exit to command line${NC}"
    echo ""
    echo -e "  ${RED}0)${NC} Exit / Logout"
    echo ""
}

# ============================================
# System Settings Sub-menu
# ============================================
show_system_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}         ${BOLD}System Settings${NC}                                    ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} System Updates"
        echo -e "     ${DIM}Update and upgrade packages${NC}"
        echo ""
        echo -e "  ${CYAN}2)${NC} OpenSSH Server       $(get_ssh_status)"
        echo -e "     ${DIM}Configure SSH security${NC}"
        echo ""
        echo -e "  ${CYAN}3)${NC} Lid Close Handling   $(get_lid_status)"
        echo -e "     ${DIM}Set lid close behavior${NC}"
        echo ""
        echo -e "  ${CYAN}4)${NC} Display & OLED"
        echo -e "     ${DIM}Console font and blanking${NC}"
        echo ""
        echo -e "  ${CYAN}5)${NC} Suspend/Hibernate    $(get_suspend_status)"
        echo -e "     ${DIM}Disable sleep modes${NC}"
        echo ""
        echo -e "  ${YELLOW}6)${NC} Run All System Settings"
        echo ""
        echo -e "  ${RED}0)${NC} Back to main menu"
        echo ""

        read -p "Select option: " choice

        case $choice in
            1) run_updates ;;
            2) run_ssh ;;
            3) run_lid ;;
            4) run_display ;;
            5) run_suspend ;;
            6) run_all_system ;;
            0|"") return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================
# AI Services Sub-menu
# ============================================
show_services_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}         ${BOLD}AI Services${NC}                                        ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} Ollama               $(get_service_status ollama 11434)"
        echo -e "     ${DIM}Local LLM inference (simpler, good for dev)${NC}"
        echo ""
        echo -e "  ${CYAN}2)${NC} vLLM                 $(get_service_status vllm 8000)"
        echo -e "     ${DIM}High-throughput LLM inference${NC}"
        echo ""
        echo -e "  ${CYAN}3)${NC} Chatterbox TTS       $(get_service_status chatterbox 8100)"
        echo -e "     ${DIM}Text-to-speech voice generation${NC}"
        echo ""
        echo -e "  ${CYAN}4)${NC} ComfyUI              $(get_service_status comfyui 8188)"
        echo -e "     ${DIM}Image generation with SDXL${NC}"
        echo ""
        echo -e "  ${CYAN}5)${NC} Video Server         $(get_service_status video 8200)"
        echo -e "     ${DIM}Wan2.2 text-to-video and image-to-video${NC}"
        echo ""
        echo -e "  ${YELLOW}6)${NC} List running services"
        echo -e "  ${YELLOW}7)${NC} Stop all services"
        echo ""
        echo -e "  ${RED}0)${NC} Back to main menu"
        echo ""

        read -p "Select option: " choice

        case $choice in
            1) install_service "ollama" "https://github.com/profzeller/local-ollama-server.git" "11434" ;;
            2) install_service "vllm" "https://github.com/profzeller/local-vllm-server.git" "8000" ;;
            3) install_service "chatterbox" "https://github.com/profzeller/local-chatterbox-server.git" "8100" ;;
            4) install_service "comfyui" "https://github.com/profzeller/local-comfyui-server.git" "8188" ;;
            5) install_service "video" "https://github.com/profzeller/local-video-server.git" "8200" ;;
            6) list_services ;;
            7) stop_all_services ;;
            0|"") return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================
# Tools & Monitoring Sub-menu
# ============================================
show_tools_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}         ${BOLD}Tools & Monitoring${NC}                                 ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${CYAN}1)${NC} Server Status"
        echo -e "     ${DIM}Quick system overview (GPU, containers, resources)${NC}"
        echo ""
        echo -e "  ${CYAN}2)${NC} GPU Monitor"
        echo -e "     ${DIM}Live GPU monitoring (press q to exit)${NC}"
        echo ""
        echo -e "  ${CYAN}3)${NC} Test Setup"
        echo -e "     ${DIM}Verify server configuration${NC}"
        echo ""
        echo -e "  ${CYAN}4)${NC} View Container Logs"
        echo -e "     ${DIM}Select a container to view logs${NC}"
        echo ""
        echo -e "  ${CYAN}5)${NC} System Info"
        echo -e "     ${DIM}Detailed hardware and OS info${NC}"
        echo ""
        echo -e "  ${RED}0)${NC} Back to main menu"
        echo ""

        read -p "Select option: " choice

        case $choice in
            1) run_server_status ;;
            2) run_gpu_monitor ;;
            3) run_test_setup ;;
            4) view_container_logs ;;
            5) run_system_info ;;
            0|"") return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# ============================================
# Section: System Identity
# ============================================
run_identity() {
    require_root || return

    header "System Identity Configuration"

    if [ -f "$MARKER_FILE" ]; then
        echo "Current hostname: $(hostname)"
        echo "Current user: $(get_username)"
        echo ""
        if ! confirm "This will modify system identity. Continue?"; then
            return
        fi
        echo ""
    fi

    # Hostname
    local current_hostname=$(hostname)
    read -p "Hostname [$current_hostname]: " new_hostname
    new_hostname=${new_hostname:-$current_hostname}

    # Username
    echo ""
    echo "Create or update a user account for this server."
    local current_user=${SUDO_USER:-$(whoami)}
    read -p "Username [$current_user]: " new_username
    new_username=${new_username:-$current_user}

    # Password
    echo ""
    while true; do
        read -s -p "Password for $new_username: " new_password
        echo
        if [[ -z "$new_password" ]]; then
            echo -e "${RED}Password cannot be empty${NC}"
            continue
        fi
        read -s -p "Confirm password: " new_password2
        echo
        if [[ "$new_password" != "$new_password2" ]]; then
            echo -e "${RED}Passwords don't match. Try again.${NC}"
            continue
        fi
        break
    done

    # Apply changes
    echo ""
    log "Applying system identity..."

    if [[ "$new_hostname" != "$current_hostname" ]]; then
        log "Setting hostname to $new_hostname..."
        hostnamectl set-hostname "$new_hostname"
        sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
        echo "$new_hostname" > /etc/hostname
    fi

    if id "$new_username" &>/dev/null; then
        log "Updating password for existing user $new_username..."
        echo "$new_username:$new_password" | chpasswd
    else
        log "Creating new user $new_username..."
        useradd -m -s /bin/bash -G sudo "$new_username"
        echo "$new_username:$new_password" | chpasswd
    fi

    usermod -aG sudo "$new_username"
    unset new_password new_password2

    log "System identity configured"
    press_enter
}

# ============================================
# Section: Network & Firewall
# ============================================
run_network() {
    require_root || return

    header "Network & Firewall Configuration"

    if [ -f "$MARKER_FILE" ]; then
        echo "Current network: $(get_network_status)"
        if [ -f "$CONFIG_DIR/allowed-ips.conf" ]; then
            echo "Allowed IPs:"
            grep -v "^#" "$CONFIG_DIR/allowed-ips.conf" 2>/dev/null | while read ip; do
                [ -n "$ip" ] && echo "  - $ip"
            done
        fi
        echo ""
        if ! confirm "This will modify network settings. Continue?"; then
            return
        fi
        echo ""
    fi

    # Collect allowed IPs
    echo -e "${YELLOW}Firewall Configuration${NC}"
    echo ""
    echo "Enter the IP addresses or networks that should be allowed to connect."
    echo "Examples: 192.168.1.0/24, 10.0.0.5, 203.0.113.0/24"
    echo ""

    local allowed_ips=()
    while true; do
        read -p "Enter IP or network (or press Enter when done): " ip_input

        if [[ -z "$ip_input" ]]; then
            if [[ ${#allowed_ips[@]} -eq 0 ]]; then
                echo -e "${RED}Error: You must enter at least one IP address or network.${NC}"
                continue
            fi
            break
        fi

        if [[ "$ip_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
            allowed_ips+=("$ip_input")
            echo -e "${GREEN}Added: $ip_input${NC}"
        else
            echo -e "${RED}Invalid format. Use IP (e.g., 10.0.0.1) or CIDR (e.g., 10.0.0.0/24)${NC}"
        fi
    done

    # Network mode
    echo ""
    echo -e "${YELLOW}Network Configuration${NC}"
    echo ""
    echo "  1) DHCP (automatic IP from router)"
    echo "  2) Static IP (manual configuration)"
    echo ""
    read -p "Select network mode [1]: " net_mode
    net_mode=${net_mode:-1}

    local use_static=false
    local net_iface static_ip subnet_cidr gateway dns1 dns2

    if [[ "$net_mode" == "2" ]]; then
        use_static=true
        echo ""

        local default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
        read -p "Network interface [$default_iface]: " net_iface
        net_iface=${net_iface:-$default_iface}

        read -p "Static IP address (e.g., 192.168.1.100): " static_ip
        while [[ ! "$static_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
            echo -e "${RED}Invalid IP format${NC}"
            read -p "Static IP address: " static_ip
        done

        read -p "Subnet mask in CIDR (e.g., 24) [24]: " subnet_cidr
        subnet_cidr=${subnet_cidr:-24}

        read -p "Gateway (e.g., 192.168.1.1): " gateway
        while [[ ! "$gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
            echo -e "${RED}Invalid IP format${NC}"
            read -p "Gateway: " gateway
        done

        read -p "DNS server 1 [8.8.8.8]: " dns1
        dns1=${dns1:-8.8.8.8}

        read -p "DNS server 2 [8.8.4.4]: " dns2
        dns2=${dns2:-8.8.4.4}
    fi

    # Apply firewall rules
    echo ""
    log "Configuring firewall..."

    apt-get install -y ufw >/dev/null 2>&1
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    for ip in "${allowed_ips[@]}"; do
        log "  Allowing SSH from $ip..."
        ufw allow from $ip to any port 22 proto tcp >/dev/null 2>&1
    done

    echo "y" | ufw enable >/dev/null 2>&1

    # Save allowed IPs
    mkdir -p "$CONFIG_DIR"
    echo "# Allowed IPs for firewall rules" > "$CONFIG_DIR/allowed-ips.conf"
    for ip in "${allowed_ips[@]}"; do
        echo "$ip" >> "$CONFIG_DIR/allowed-ips.conf"
    done

    # Apply static IP if selected
    if [ "$use_static" = true ]; then
        log "Configuring static IP..."

        cat > /etc/netplan/00-static-config.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $net_iface:
      dhcp4: no
      addresses:
        - $static_ip/$subnet_cidr
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses:
          - $dns1
          - $dns2
EOF
        chmod 600 /etc/netplan/00-static-config.yaml
        log "Static IP configured: $static_ip/$subnet_cidr"
        log "Note: New IP will take effect after reboot"
    fi

    log "Network configuration complete"
    press_enter
}

# ============================================
# Section: NVIDIA Stack
# ============================================
run_nvidia() {
    require_root || return

    header "NVIDIA Stack"

    local current_version=$(get_nvidia_version)
    echo "Current NVIDIA driver: $current_version"
    echo ""

    if [[ "$current_version" != "Not installed" && "$current_version" != "Error" ]]; then
        echo "Options:"
        echo "  1) Keep current ($current_version)"
        echo "  2) Reinstall driver 550"
        echo "  3) Upgrade to driver 560"
        echo "  4) Upgrade to driver 570 (latest)"
        echo "  5) Custom version"
        echo "  0) Cancel"
        echo ""
        echo -e "${DIM}Note: vLLM recommends driver 550+ for best compatibility${NC}"
        echo ""
        read -p "Select option [1]: " nvidia_choice
        nvidia_choice=${nvidia_choice:-1}

        case $nvidia_choice in
            1) log "Keeping current driver"; press_enter; return ;;
            2) driver_version="550" ;;
            3) driver_version="560" ;;
            4) driver_version="570" ;;
            5) read -p "Enter driver version: " driver_version ;;
            0|"") return ;;
            *) echo -e "${RED}Invalid option${NC}"; press_enter; return ;;
        esac
    else
        echo "Options:"
        echo "  1) Install driver 550 (recommended for vLLM)"
        echo "  2) Install driver 560"
        echo "  3) Install driver 570 (latest)"
        echo "  4) Custom version"
        echo "  0) Cancel"
        echo ""
        read -p "Select option [1]: " nvidia_choice
        nvidia_choice=${nvidia_choice:-1}

        case $nvidia_choice in
            1) driver_version="550" ;;
            2) driver_version="560" ;;
            3) driver_version="570" ;;
            4) read -p "Enter driver version: " driver_version ;;
            0|"") return ;;
            *) echo -e "${RED}Invalid option${NC}"; press_enter; return ;;
        esac
    fi

    echo ""
    log "Installing NVIDIA driver $driver_version..."

    add-apt-repository -y ppa:graphics-drivers/ppa >/dev/null 2>&1
    apt-get update >/dev/null 2>&1
    apt-get install -y nvidia-driver-$driver_version nvidia-utils-$driver_version

    log "Installing NVIDIA Container Toolkit..."

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

    apt-get update >/dev/null 2>&1
    apt-get install -y nvidia-container-toolkit

    # Configure Docker if installed
    if command -v docker &>/dev/null; then
        nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1
        systemctl restart docker 2>/dev/null || true
    fi

    log "NVIDIA stack installed"
    warn "A reboot is required to load the new driver"
    press_enter
}

# ============================================
# Section: Docker
# ============================================
run_docker() {
    require_root || return

    header "Docker Installation"

    local current_version=$(get_docker_version)
    echo "Current Docker: $current_version"
    echo ""

    if [[ "$current_version" != "Not installed" ]]; then
        echo "Options:"
        echo "  1) Keep current installation"
        echo "  2) Reinstall Docker"
        echo "  0) Cancel"
        echo ""
        read -p "Select option [1]: " docker_choice
        docker_choice=${docker_choice:-1}

        case $docker_choice in
            1) log "Keeping current Docker"; press_enter; return ;;
            2) log "Reinstalling Docker..." ;;
            0|"") return ;;
            *) echo -e "${RED}Invalid option${NC}"; press_enter; return ;;
        esac
    fi

    log "Removing old Docker versions..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    log "Adding Docker repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update >/dev/null 2>&1

    log "Installing Docker..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log "Configuring Docker for NVIDIA..."
    if command -v nvidia-ctk &>/dev/null; then
        nvidia-ctk runtime configure --runtime=docker
    fi

    systemctl enable docker
    systemctl start docker

    # Add user to docker group
    if [ -n "$SUDO_USER" ]; then
        log "Adding $SUDO_USER to docker group..."
        usermod -aG docker "$SUDO_USER"
    fi

    log "Docker installed successfully"
    press_enter
}

# ============================================
# System Settings Functions
# ============================================
run_updates() {
    require_root || return

    header "System Updates"

    log "Updating package lists..."
    apt-get update

    log "Upgrading installed packages..."
    apt-get upgrade -y

    log "Installing essential packages..."
    apt-get install -y \
        curl wget git htop nvtop vim nano net-tools \
        ca-certificates gnupg lsb-release \
        software-properties-common build-essential \
        linux-headers-$(uname -r)

    log "System updated"
    press_enter
}

run_ssh() {
    require_root || return

    header "OpenSSH Server Configuration"

    log "Installing OpenSSH server..."
    apt-get install -y openssh-server

    systemctl enable ssh
    systemctl start ssh

    log "Configuring SSH security settings..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup 2>/dev/null || true

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

    systemctl restart ssh

    log "SSH configured"
    press_enter
}

run_lid() {
    require_root || return

    header "Lid Close & Power Management"

    log "Configuring lid close behavior..."
    mkdir -p /etc/systemd/logind.conf.d

    cat > /etc/systemd/logind.conf.d/lid.conf << 'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
LidSwitchIgnoreInhibited=no
EOF

    systemctl restart systemd-logind

    log "Lid close configured to ignore"
    press_enter
}

run_display() {
    require_root || return

    header "Display & OLED Burn-in Prevention"

    log "Installing console font packages..."
    apt-get install -y console-setup kbd

    log "Configuring large console font..."
    cat > /etc/default/console-setup << 'EOF'
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Terminus"
FONTSIZE="32x16"
EOF

    setupcon --force 2>/dev/null || true

    # Console font service
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

    # Console blank service
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

    systemctl set-default multi-user.target 2>/dev/null || true

    log "Display configured"
    press_enter
}

run_suspend() {
    require_root || return

    header "Suspend/Hibernate Configuration"

    log "Disabling suspend and hibernate..."
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

    log "Suspend/hibernate disabled"
    press_enter
}

run_all_system() {
    run_updates
    run_ssh
    run_lid
    run_display
    run_suspend
}

# ============================================
# Section: Performance Tuning
# ============================================
run_performance() {
    require_root || return

    header "Performance Tuning"

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
    systemctl enable nvidia-persistenced 2>/dev/null || true

    log "Setting up swap (8GB)..."
    if [ ! -f /swapfile ]; then
        fallocate -l 8G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    else
        log "Swap already configured"
    fi

    log "Optimizing kernel parameters..."
    cat > /etc/sysctl.d/99-gpu-server.conf << 'EOF'
vm.swappiness=10
fs.inotify.max_user_watches=524288
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF

    sysctl -p /etc/sysctl.d/99-gpu-server.conf 2>/dev/null || true

    log "Performance tuning complete"
    press_enter
}

# ============================================
# Section: Management Tools
# ============================================
run_management_tools() {
    require_root || return

    header "Installing Management Tools"

    log "Installing test-gpu-setup..."
    cat > /usr/local/bin/test-gpu-setup << 'SCRIPT'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "======================================"
echo " GPU Server Setup Verification"
echo "======================================"
echo ""

echo "1. NVIDIA Driver..."
if nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    pass "NVIDIA driver loaded - $GPU_NAME"
else
    fail "NVIDIA driver not working"
fi

echo "2. Docker..."
if docker --version &>/dev/null; then
    pass "Docker installed - $(docker --version)"
else
    fail "Docker not installed"
fi

echo "3. Docker GPU Access..."
if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
    pass "Docker can access GPU"
else
    fail "Docker cannot access GPU"
fi

echo "4. UFW Firewall..."
if ufw status | grep -q "Status: active"; then
    pass "UFW is active"
else
    fail "UFW is not active"
fi

echo "5. SSH Service..."
if systemctl is-active --quiet ssh; then
    pass "SSH is running"
else
    fail "SSH is not running"
fi

echo "6. Lid Close Config..."
if grep -q "HandleLidSwitch=ignore" /etc/systemd/logind.conf.d/lid.conf 2>/dev/null; then
    pass "Lid close set to ignore"
else
    fail "Lid close not configured"
fi

echo "7. Suspend Disabled..."
SUSPEND_STATUS=$(systemctl is-enabled suspend.target 2>/dev/null || echo "unknown")
if [[ "$SUSPEND_STATUS" == "masked" || "$SUSPEND_STATUS" == "disabled" ]]; then
    pass "Suspend is disabled"
else
    fail "Suspend may still be enabled"
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
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv 2>/dev/null || echo "GPU info unavailable"
echo ""
SCRIPT
    chmod +x /usr/local/bin/test-gpu-setup

    log "Installing gpu-monitor..."
    cat > /usr/local/bin/gpu-monitor << 'SCRIPT'
#!/bin/bash
watch -n 1 nvidia-smi
SCRIPT
    chmod +x /usr/local/bin/gpu-monitor

    log "Installing server-status..."
    cat > /usr/local/bin/server-status << 'SCRIPT'
#!/bin/bash
echo "=== GPU Status ==="
nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | \
    awk -F',' '{printf "GPU: %s | Temp: %s°C | Util: %s%% | VRAM: %s/%s MB\n", $1, $2, $3, $4, $5}' || echo "GPU not available"
echo ""
echo "=== Docker Containers ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running"
echo ""
echo "=== System Resources ==="
free -h | grep Mem | awk '{printf "RAM: %s used / %s total\n", $3, $2}'
df -h / | tail -1 | awk '{printf "Disk: %s used / %s total (%s)\n", $3, $2, $5}'
echo ""
echo "=== Network ==="
echo "IP: $(hostname -I | awk '{print $1}')"
echo "Firewall: $(ufw status 2>/dev/null | head -1 || echo 'Unknown')"
SCRIPT
    chmod +x /usr/local/bin/server-status

    log "Installing server-commands..."
    cat > /usr/local/bin/server-commands << 'SCRIPT'
#!/bin/bash
echo ""
echo "Lenovo P16 GPU Server Commands"
echo "==============================="
echo ""
echo "Main utility:"
echo "  server-setup       Interactive setup and management menu"
echo ""
echo "Quick commands:"
echo "  server-status      System overview"
echo "  gpu-monitor        Live GPU monitoring"
echo "  test-gpu-setup     Verify configuration"
echo ""
SCRIPT
    chmod +x /usr/local/bin/server-commands

    # Install this script as server-setup
    log "Installing server-setup command..."
    cp "$0" /usr/local/bin/server-setup 2>/dev/null || true
    chmod +x /usr/local/bin/server-setup

    log "Management tools installed"
    press_enter
}

# ============================================
# AI Services Functions
# ============================================
install_service() {
    require_root || return

    local name="$1"
    local repo="$2"
    local port="$3"
    local dir="local-${name}-server"

    header "Installing $name"

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    if [ -d "$dir" ]; then
        echo "Service already installed."
        echo ""
        echo "Options:"
        echo "  1) Start service"
        echo "  2) Stop service"
        echo "  3) Update (git pull)"
        echo "  4) Reinstall"
        echo "  0) Cancel"
        echo ""
        read -p "Select option: " svc_choice

        case $svc_choice in
            1)
                cd "$dir"
                docker compose up -d
                log "$name started"
                ;;
            2)
                cd "$dir"
                docker compose down
                log "$name stopped"
                ;;
            3)
                cd "$dir"
                git pull
                docker compose down 2>/dev/null || true
                docker compose up -d
                log "$name updated"
                ;;
            4)
                rm -rf "$dir"
                git clone "$repo"
                cd "$dir"
                docker compose up -d
                log "$name reinstalled"
                ;;
            0|"")
                return
                ;;
        esac
    else
        log "Cloning repository..."
        git clone "$repo"
        cd "$dir"

        # Special handling for ComfyUI
        if [ "$name" = "comfyui" ]; then
            mkdir -p models/checkpoints output input custom_nodes
            warn "Download SDXL model to $INSTALL_DIR/$dir/models/checkpoints/"
        fi

        log "Starting $name..."
        docker compose up -d
        log "$name installed and started"
    fi

    # Firewall prompt
    echo ""
    echo -e "${YELLOW}Firewall Configuration${NC}"
    echo "This service runs on port $port"
    echo ""

    if confirm "Open port $port in firewall?" "y"; then
        if [ -f "$CONFIG_DIR/allowed-ips.conf" ]; then
            log "Opening port $port for allowed IPs..."
            while IFS= read -r ip; do
                [[ "$ip" =~ ^#.*$ ]] && continue
                [[ -z "$ip" ]] && continue
                ufw allow from $ip to any port $port proto tcp 2>/dev/null
            done < "$CONFIG_DIR/allowed-ips.conf"
            log "Firewall updated"
        else
            warn "No allowed IPs configured. Run Network & Firewall setup first."
        fi
    fi

    echo ""
    echo -e "Access at: ${CYAN}http://$(hostname -I | awk '{print $1}'):$port${NC}"

    press_enter
}

list_services() {
    header "Running GPU Services"

    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | \
        grep -E "(NAME|ollama|vllm|chatterbox|comfyui|video)" || echo "No GPU services running"

    echo ""
    echo "GPU Status:"
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | \
        awk -F',' '{printf "  %s | Temp: %s°C | Util: %s%% | VRAM: %s/%s MB\n", $1, $2, $3, $4, $5}' || echo "  GPU not available"

    press_enter
}

stop_all_services() {
    require_root || return

    header "Stopping All GPU Services"

    for service in ollama vllm chatterbox comfyui video; do
        local dir="$INSTALL_DIR/local-${service}-server"
        if [ -d "$dir" ]; then
            echo "Stopping $service..."
            cd "$dir"
            docker compose down 2>/dev/null || true
        fi
    done

    log "All services stopped"
    press_enter
}

# ============================================
# Tools Functions
# ============================================
run_server_status() {
    clear
    echo ""
    if command -v server-status &>/dev/null; then
        server-status
    else
        echo "=== GPU Status ==="
        nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | \
            awk -F',' '{printf "GPU: %s | Temp: %s°C | Util: %s%% | VRAM: %s/%s MB\n", $1, $2, $3, $4, $5}' || echo "GPU not available"
        echo ""
        echo "=== Docker Containers ==="
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not running"
        echo ""
        echo "=== System Resources ==="
        free -h | grep Mem | awk '{printf "RAM: %s used / %s total\n", $3, $2}'
        df -h / | tail -1 | awk '{printf "Disk: %s used / %s total (%s)\n", $3, $2, $5}'
    fi
    press_enter
}

run_gpu_monitor() {
    clear
    echo "GPU Monitor (press Ctrl+C to exit)"
    echo ""
    watch -n 1 nvidia-smi 2>/dev/null || nvidia-smi
    press_enter
}

run_test_setup() {
    clear
    if command -v test-gpu-setup &>/dev/null; then
        test-gpu-setup
    else
        echo "test-gpu-setup not installed. Install Management Tools first."
    fi
    press_enter
}

view_container_logs() {
    clear
    echo "Running containers:"
    echo ""

    local containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
    if [ -z "$containers" ]; then
        echo "No containers running"
        press_enter
        return
    fi

    local i=1
    local container_list=()
    while IFS= read -r container; do
        echo "  $i) $container"
        container_list+=("$container")
        ((i++))
    done <<< "$containers"

    echo ""
    echo "  0) Cancel"
    echo ""
    read -p "Select container: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ] && [ "$choice" -le "${#container_list[@]}" ]; then
        local selected="${container_list[$((choice-1))]}"
        echo ""
        echo "Showing last 50 lines of $selected (press Ctrl+C to exit):"
        echo ""
        docker logs --tail 50 -f "$selected"
    fi
}

run_system_info() {
    clear
    header "System Information"

    echo "Hostname: $(hostname)"
    echo "IP Address: $(hostname -I | awk '{print $1}')"
    echo "Kernel: $(uname -r)"
    echo "Ubuntu: $(lsb_release -d 2>/dev/null | cut -f2)"
    echo ""

    echo "=== CPU ==="
    lscpu | grep -E "Model name|Socket|Core|Thread" | head -4
    echo ""

    echo "=== Memory ==="
    free -h
    echo ""

    echo "=== GPU ==="
    nvidia-smi 2>/dev/null || echo "NVIDIA driver not loaded"
    echo ""

    echo "=== Storage ==="
    df -h /

    press_enter
}

# ============================================
# Full Setup
# ============================================
run_full_setup() {
    require_root || return

    header "Full P16 GPU Server Setup"

    echo "This will run all configuration sections:"
    echo "  1. System Identity"
    echo "  2. Network & Firewall"
    echo "  3. System Updates"
    echo "  4. SSH Configuration"
    echo "  5. Lid Close Handling"
    echo "  6. Display & OLED"
    echo "  7. Suspend Disable"
    echo "  8. NVIDIA Stack"
    echo "  9. Docker"
    echo "  10. Performance Tuning"
    echo "  11. Management Tools"
    echo ""

    if [ -f "$MARKER_FILE" ]; then
        if ! confirm "This will re-run all setup. Continue?"; then
            return
        fi
    fi

    run_identity
    run_network
    run_updates
    run_ssh
    run_lid
    run_display
    run_suspend
    run_nvidia
    run_docker
    run_performance
    run_management_tools

    # Create marker file
    mkdir -p "$CONFIG_DIR"
    date > "$MARKER_FILE"

    # Create auto-boot config
    create_autoboot

    # Final message
    header "Setup Complete!"

    echo -e "${GREEN}The P16 GPU server has been configured successfully!${NC}"
    echo ""
    echo "Summary:"
    echo "  ✓ System identity configured"
    echo "  ✓ Network and firewall configured"
    echo "  ✓ System packages updated"
    echo "  ✓ SSH server configured"
    echo "  ✓ Lid close set to ignore"
    echo "  ✓ Display blanking enabled"
    echo "  ✓ Suspend/hibernate disabled"
    echo "  ✓ NVIDIA drivers installed"
    echo "  ✓ Docker with GPU support installed"
    echo "  ✓ Performance tuning applied"
    echo "  ✓ Management tools installed"
    echo ""
    echo -e "${YELLOW}IMPORTANT: A reboot is required to complete the setup.${NC}"
    echo ""
    echo "After reboot, this menu will appear automatically on login."
    echo "Use 'AI Services' menu to install Ollama, vLLM, etc."
    echo ""

    if confirm "Reboot now?" "y"; then
        log "Rebooting..."
        reboot
    fi
}

# ============================================
# Auto-boot Configuration
# ============================================
create_autoboot() {
    require_root || return

    log "Configuring auto-boot to menu..."

    cat > /etc/profile.d/server-setup.sh << 'EOF'
# Auto-launch server-setup menu on interactive login
if [[ $- == *i* ]] && [[ -z "$SERVER_SETUP_RUNNING" ]] && [[ -z "$SSH_TTY" || "$TERM" != "dumb" ]]; then
    if [ -f /usr/local/bin/server-setup ]; then
        export SERVER_SETUP_RUNNING=1
        exec /usr/local/bin/server-setup
    fi
fi
EOF

    chmod +x /etc/profile.d/server-setup.sh

    # Create MOTD
    cat > /etc/update-motd.d/99-gpu-server << 'EOF'
#!/bin/bash
echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║     Lenovo P16 GPU Server (RTX 4090)      ║"
echo "  ╠═══════════════════════════════════════════╣"
echo "  ║  Type 'server-setup' for management menu  ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""
EOF
    chmod +x /etc/update-motd.d/99-gpu-server
}

drop_to_shell() {
    clear
    echo ""
    echo -e "${GREEN}Dropping to shell...${NC}"
    echo ""
    echo "Type 'server-setup' to return to the menu."
    echo "Type 'exit' to logout."
    echo ""

    # Unset the flag so shell is normal
    unset SERVER_SETUP_RUNNING

    # Start a new shell
    exec bash --login
}

# ============================================
# Main Entry Point
# ============================================
main() {
    # Check if first run
    if is_first_run; then
        if [[ $EUID -ne 0 ]]; then
            echo -e "${RED}First-time setup requires root privileges${NC}"
            echo "Run with: sudo bash setup.sh"
            exit 1
        fi
        run_full_setup
        exit 0
    fi

    # Interactive menu loop
    while true; do
        show_main_menu
        read -p "Select option: " choice

        case $choice in
            1) run_identity ;;
            2) run_network ;;
            3) run_nvidia ;;
            4) run_docker ;;
            5) show_system_menu ;;
            6) run_performance ;;
            7) run_management_tools ;;
            8) show_services_menu ;;
            9) show_tools_menu ;;
            [Ff]) run_full_setup ;;
            [Ss]) drop_to_shell ;;
            0|"")
                clear
                echo ""
                echo "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# Run main
main "$@"
