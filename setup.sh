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

# Version - update this with each release
SCRIPT_VERSION="1.9.0"

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
    # Skip in batch mode (first-run setup)
    [[ "$BATCH_MODE" == "1" ]] && return
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

get_current_ip() {
    # Get the actual current IP address (not from config)
    hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "unknown"
}

get_network_status() {
    if [ -f /etc/netplan/00-static-config.yaml ]; then
        local ip=$(get_current_ip)
        if [ -n "$ip" ] && [ "$ip" != "unknown" ]; then
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


# Open a port in firewall for Docker containers
open_docker_port() {
    local port=$1

    if [ -f "$CONFIG_DIR/allowed-ips.conf" ]; then
        log "Opening port $port for allowed IPs..."
        while IFS= read -r ip; do
            [[ "$ip" =~ ^#.*$ ]] && continue
            [[ -z "$ip" ]] && continue
            ufw allow from $ip to any port $port proto tcp 2>/dev/null
            ufw route allow from $ip to any port $port proto tcp 2>/dev/null
        done < "$CONFIG_DIR/allowed-ips.conf"
        log "Firewall updated for port $port"
    else
        warn "No allowed IPs configured. Opening port $port for all..."
        ufw allow $port/tcp 2>/dev/null
        ufw route allow proto tcp to any port $port 2>/dev/null
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
    local current_ip=$(get_current_ip)
    local host=$(hostname)
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}         ${BOLD}P16 GPU Server Setup${NC}  ${DIM}v${SCRIPT_VERSION}${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}         ${host} - ${current_ip}                      ${CYAN}║${NC}"
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
        echo -e "  ${CYAN}6)${NC} P16 Agent            $(get_service_status p16-agent 9100)"
        echo -e "     ${DIM}Metrics collection agent for remote monitoring${NC}"
        echo ""
        echo -e "  ${YELLOW}7)${NC} Update server-setup  ${DIM}[v${SCRIPT_VERSION}]${NC}"
        echo -e "     ${DIM}Check for and install updates${NC}"
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
            6) install_agent ;;
            7) update_server_setup ;;
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

    # Offer to remove old user if a different username was specified
    if [[ "$new_username" != "$current_user" ]] && [[ "$current_user" != "root" ]]; then
        echo ""
        if confirm "Remove old user '$current_user'?"; then
            # Kill any processes owned by the old user
            pkill -u "$current_user" 2>/dev/null || true
            sleep 1
            # Remove the user and their home directory
            if userdel -r "$current_user" 2>/dev/null; then
                log "Removed user '$current_user' and home directory"
            else
                warn "Could not fully remove user '$current_user' - you may need to remove manually"
            fi
        fi
    fi

    log "System identity configured"
    press_enter
}

# ============================================
# Section: Network & Firewall
# ============================================
run_network() {
    require_root || return

    header "Network & Firewall Configuration"

    local edit_firewall=true
    local edit_network=true

    # Show current status and submenu if already configured
    if [ -f "$MARKER_FILE" ]; then
        echo "Current network: $(get_network_status)"
        if [ -f "$CONFIG_DIR/allowed-ips.conf" ]; then
            echo "Allowed IPs:"
            grep -v "^#" "$CONFIG_DIR/allowed-ips.conf" 2>/dev/null | while read ip; do
                [ -n "$ip" ] && echo "  - $ip"
            done
        fi
        echo ""
        echo "What would you like to modify?"
        echo "  1) Firewall (allowed IPs)"
        echo "  2) Network (DHCP/Static IP)"
        echo "  3) Both"
        echo "  0) Cancel"
        echo ""
        read -p "Select option [3]: " edit_choice
        edit_choice=${edit_choice:-3}

        case $edit_choice in
            1) edit_firewall=true; edit_network=false ;;
            2) edit_firewall=false; edit_network=true ;;
            3) edit_firewall=true; edit_network=true ;;
            0|"") return ;;
            *) echo -e "${RED}Invalid option${NC}"; press_enter; return ;;
        esac
        echo ""
    fi

    local allowed_ips=()

    # Collect allowed IPs (firewall section)
    if [ "$edit_firewall" = true ]; then
        echo -e "${YELLOW}Firewall Configuration${NC}"
        echo ""
        echo "Enter the IP addresses or networks that should be allowed to connect."
        echo "Examples: 192.168.1.0/24, 10.0.0.5, 203.0.113.0/24"
        echo ""

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
    fi

    local use_static=false
    local net_iface static_ip subnet_cidr gateway dns1 dns2

    # Network mode section
    if [ "$edit_network" = true ]; then
        echo ""
        echo -e "${YELLOW}Network Configuration${NC}"
        echo ""
        echo "  1) DHCP (automatic IP from router)"
        echo "  2) Static IP (manual configuration)"
        echo ""
        read -p "Select network mode [1]: " net_mode
        net_mode=${net_mode:-1}

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
    fi

    # Apply firewall rules
    if [ "$edit_firewall" = true ]; then
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
    fi

    # Apply static IP if selected
    if [ "$edit_network" = true ] && [ "$use_static" = true ]; then
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
        log "Applying network configuration..."
        netplan apply 2>/dev/null || warn "Netplan apply failed - may need reboot"
    elif [ "$edit_network" = true ] && [ "$use_static" = false ]; then
        # DHCP mode - remove static config if it exists
        if [ -f /etc/netplan/00-static-config.yaml ]; then
            log "Removing static IP configuration (switching to DHCP)..."
            rm -f /etc/netplan/00-static-config.yaml
            log "Applying network configuration..."
            netplan apply 2>/dev/null || warn "Netplan apply failed - may need reboot"
        fi
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

    # Configure UFW to control Docker traffic
    configure_docker_ufw

    log "Docker installed successfully"
    press_enter
}

# Configure UFW to properly control Docker container traffic
# By default, Docker bypasses UFW by manipulating iptables directly
# This creates a FILTERS chain that only allows configured IPs
configure_docker_ufw() {
    log "Configuring UFW to control Docker traffic..."

    local after_rules="/etc/ufw/after.rules"
    local marker="# BEGIN DOCKER-USER UFW INTEGRATION"
    local allowed_ips_file="$CONFIG_DIR/allowed-ips.conf"

    # Remove any broken previous attempts
    if grep -q "$marker" "$after_rules" 2>/dev/null; then
        log "Removing previous Docker UFW integration..."
        sed -i '/# BEGIN DOCKER-USER/,/# END DOCKER-USER/d' "$after_rules"
    fi

    # Ensure UFW forward policy is set
    if grep -q 'DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
        log "Enabling UFW forward policy..."
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    fi

    # Backup the file
    cp "$after_rules" "${after_rules}.backup.$(date +%Y%m%d)" 2>/dev/null || true

    # Build allowed IPs rules from config
    local allowed_rules=""
    if [[ -f "$allowed_ips_file" ]]; then
        log "Reading allowed IPs from $allowed_ips_file..."
        while IFS= read -r ip || [[ -n "$ip" ]]; do
            [[ -z "$ip" || "$ip" =~ ^# ]] && continue
            ip=$(echo "$ip" | xargs)
            [[ -n "$ip" ]] && allowed_rules="${allowed_rules}-A FILTERS -s ${ip} -j RETURN
"
            log "  Allowing: $ip"
        done < "$allowed_ips_file"
    fi

    # Add Docker-USER chain rules with FILTERS chain
    cat >> "$after_rules" << EOFBLOCK

# BEGIN DOCKER-USER UFW INTEGRATION
# Block Docker container access except from allowed IPs
# This runs BEFORE Docker's permissive rules
*filter
:DOCKER-USER - [0:0]
:FILTERS - [0:0]

# Jump to our filters
-A DOCKER-USER -j FILTERS

# Allow established connections
-A FILTERS -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# Allow from localhost and private networks
-A FILTERS -s 127.0.0.0/8 -j RETURN
-A FILTERS -s 172.16.0.0/12 -j RETURN
-A FILTERS -s 10.0.0.0/8 -j RETURN
-A FILTERS -s 192.168.0.0/16 -j RETURN

# Allow from configured IPs (from $allowed_ips_file)
${allowed_rules}
# Allow Docker internal networks
-A FILTERS -i docker0 -j RETURN
-A FILTERS -i br- -j RETURN

# Default: drop everything else to containers
-A FILTERS -j DROP

-A DOCKER-USER -j RETURN
COMMIT
# END DOCKER-USER UFW INTEGRATION
EOFBLOCK

    log "Docker UFW integration added to $after_rules"

    # Ensure UFW is enabled
    if ! ufw status | grep -q "Status: active"; then
        log "Enabling UFW..."
        echo "y" | ufw enable
    fi

    # Reload UFW to apply changes
    ufw reload
    log "UFW reloaded"

    # Restart Docker to pick up new iptables rules
    if systemctl is-active --quiet docker; then
        log "Restarting Docker..."
        systemctl restart docker
    fi
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

# Show service status with details
show_service_status() {
    local name="$1"
    local container="$2"
    local port="$3"

    # Check container status
    local status=$(docker ps --filter "name=$container" --format "{{.Status}}" 2>/dev/null)
    local health=$(docker ps --filter "name=$container" --format "{{.Status}}" 2>/dev/null | grep -o "(healthy)\|(unhealthy)" || echo "")

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $name Status${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ -n "$status" ]; then
        echo -e "  Container:  ${GREEN}Running${NC} $health"
        echo -e "  Uptime:     $(echo "$status" | sed 's/ (healthy)//' | sed 's/ (unhealthy)//')"
    else
        echo -e "  Container:  ${RED}Stopped${NC}"
    fi

    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "  Endpoint:   http://${ip}:${port}"
    echo ""
}

# Ollama-specific status
show_ollama_status() {
    local container="ollama"
    local port="11434"

    show_service_status "Ollama" "$container" "$port"

    # Get config from environment
    local ctx=$(docker exec $container printenv OLLAMA_NUM_CTX 2>/dev/null || echo "default")
    local parallel=$(docker exec $container printenv OLLAMA_NUM_PARALLEL 2>/dev/null || echo "default")
    local flash=$(docker exec $container printenv OLLAMA_FLASH_ATTENTION 2>/dev/null || echo "0")

    echo -e "  ${YELLOW}Configuration:${NC}"
    echo -e "  Context Window:    $ctx tokens"
    echo -e "  Parallel Requests: $parallel"
    echo -e "  Flash Attention:   $([ "$flash" = "1" ] && echo "Enabled" || echo "Disabled")"
    echo ""

    # Get loaded models
    echo -e "  ${YELLOW}Loaded Models:${NC}"
    local loaded=$(curl -s http://localhost:$port/api/ps 2>/dev/null)
    if [ -n "$loaded" ] && echo "$loaded" | grep -q "models"; then
        echo "$loaded" | grep -oP '"name":"[^"]+"|"size":\d+|"parameter_size":"[^"]+"' | \
            sed 's/"name":"/ ► /g' | sed 's/"size":/  Size: /g' | sed 's/"parameter_size":"/  Params: /g' | \
            sed 's/"//g' || echo "  (none loaded)"
    else
        echo "  (none currently loaded)"
    fi
    echo ""

    # Get installed models
    echo -e "  ${YELLOW}Installed Models:${NC}"
    docker exec $container ollama list 2>/dev/null | tail -n +2 | awk '{printf "  ► %-25s %s\n", $1, $2}' || echo "  (none)"
    echo ""
}

# Chatterbox-specific status
show_chatterbox_status() {
    local container="chatterbox"
    local port="8100"

    show_service_status "Chatterbox TTS" "$container" "$port"

    # Get health info from API
    local health=$(curl -s http://localhost:$port/health 2>/dev/null)
    if [ -n "$health" ]; then
        local model_loaded=$(echo "$health" | grep -oP '"model_loaded":\s*(true|false)' | cut -d: -f2)
        local cuda=$(echo "$health" | grep -oP '"cuda_available":\s*(true|false)' | cut -d: -f2)
        local device=$(echo "$health" | grep -oP '"device":\s*"[^"]+"' | cut -d'"' -f4)

        echo -e "  ${YELLOW}Model Status:${NC}"
        echo -e "  Model Loaded:  $([ "$model_loaded" = "true" ] && echo "${GREEN}Yes${NC}" || echo "${YELLOW}No (loads on first request)${NC}")"
        echo -e "  CUDA:          $([ "$cuda" = "true" ] && echo "${GREEN}Available${NC}" || echo "${RED}Not Available${NC}")"
        echo -e "  Device:        $device"
    else
        echo -e "  ${RED}API not responding${NC}"
    fi
    echo ""

    echo -e "  ${YELLOW}API Parameters:${NC}"
    echo "  temperature:   0.7 (default)"
    echo "  exaggeration:  1.0 (default, try 0.4-0.6 for smoother)"
    echo "  cfg_weight:    0.5 (default)"
    echo "  speed:         1.0 (default)"
    echo ""
}

# Video Server-specific status
show_video_status() {
    local container="wan-video"
    local port="8200"

    show_service_status "Video Server" "$container" "$port"

    # Get health info from API
    local health=$(curl -s http://localhost:$port/health 2>/dev/null)
    if [ -n "$health" ]; then
        local model=$(echo "$health" | grep -oP '"model":\s*"[^"]+"' | cut -d'"' -f4)
        local model_loaded=$(echo "$health" | grep -oP '"model_loaded":\s*(true|false)' | cut -d: -f2)
        local cuda=$(echo "$health" | grep -oP '"cuda_available":\s*(true|false)' | cut -d: -f2)
        local vram_used=$(echo "$health" | grep -oP '"vram_used_gb":\s*[0-9.]+' | cut -d: -f2)
        local vram_total=$(echo "$health" | grep -oP '"vram_total_gb":\s*[0-9.]+' | cut -d: -f2)
        local cpu_offload=$(echo "$health" | grep -oP '"cpu_offload":\s*(true|false)' | cut -d: -f2)

        echo -e "  ${YELLOW}Model Status:${NC}"
        echo -e "  Model:         $model"
        echo -e "  Loaded:        $([ "$model_loaded" = "true" ] && echo "${GREEN}Yes${NC}" || echo "${YELLOW}No (loads on first request)${NC}")"
        echo -e "  CUDA:          $([ "$cuda" = "true" ] && echo "${GREEN}Available${NC}" || echo "${RED}Not Available${NC}")"
        echo -e "  VRAM:          ${vram_used}GB / ${vram_total}GB"
        echo -e "  CPU Offload:   $([ "$cpu_offload" = "true" ] && echo "Enabled" || echo "Disabled")"
    else
        echo -e "  ${RED}API not responding${NC}"
    fi
    echo ""

    echo -e "  ${YELLOW}Available Models:${NC}"
    echo "  Wan-AI/Wan2.2-T2V-A14B  (Text-to-Video)"
    echo "  Wan-AI/Wan2.2-I2V-A14B  (Image-to-Video) - default"
    echo "  Wan-AI/Wan2.2-TI2V-5B   (Both, smaller)"
    echo ""
}

# vLLM-specific status
show_vllm_status() {
    local container="vllm"
    local port="8000"

    show_service_status "vLLM" "$container" "$port"

    # Get model from .env
    local dir="$INSTALL_DIR/local-vllm-server"
    if [ -f "$dir/.env" ]; then
        local model=$(grep "^MODEL=" "$dir/.env" 2>/dev/null | cut -d= -f2)
        local gpu_mem=$(grep "^GPU_MEMORY_UTILIZATION=" "$dir/.env" 2>/dev/null | cut -d= -f2)

        echo -e "  ${YELLOW}Configuration:${NC}"
        echo -e "  Model:            ${model:-not set}"
        echo -e "  GPU Memory Util:  ${gpu_mem:-0.9}"
    fi
    echo ""
}

# ComfyUI-specific status
show_comfyui_status() {
    local container="comfyui"
    local port="8188"

    show_service_status "ComfyUI" "$container" "$port"

    # List models
    local dir="$INSTALL_DIR/local-comfyui-server"
    if [ -d "$dir/models/checkpoints" ]; then
        echo -e "  ${YELLOW}Installed Checkpoints:${NC}"
        ls "$dir/models/checkpoints"/*.safetensors "$dir/models/checkpoints"/*.ckpt 2>/dev/null | \
            xargs -I{} basename {} | head -5 | sed 's/^/  ► /' || echo "  (none)"
    fi
    echo ""
}

# View docker logs for a service
view_service_logs() {
    local container="$1"
    local name="$2"

    header "$name Logs"

    echo "How would you like to view logs?"
    echo ""
    echo "  1) Last 50 lines (static)"
    echo "  2) Last 100 lines (static)"
    echo "  3) Follow live (Ctrl+C to stop)"
    echo "  0) Cancel"
    echo ""
    read -p "Select option: " log_choice

    case $log_choice in
        1)
            docker logs --tail 50 "$container" 2>&1 | less
            ;;
        2)
            docker logs --tail 100 "$container" 2>&1 | less
            ;;
        3)
            echo ""
            echo "Following logs... Press Ctrl+C to stop"
            echo ""
            # Trap SIGINT to prevent script exit
            trap 'echo ""; echo "Stopped following logs."; trap - INT; return 0' INT
            docker logs --tail 20 -f "$container" 2>&1
            trap - INT
            ;;
        0|"") return ;;
    esac
}

# Configure vLLM model
configure_vllm() {
    local dir="$INSTALL_DIR/local-vllm-server"
    local env_file="$dir/.env"

    header "Configure vLLM Model"

    if [ ! -d "$dir" ]; then
        warn "vLLM not installed. Install it first."
        press_enter
        return
    fi

    # Create .env if doesn't exist
    if [ ! -f "$env_file" ]; then
        cp "$dir/.env.example" "$env_file" 2>/dev/null || touch "$env_file"
    fi

    # Current model
    local current_model=$(grep "^VLLM_MODEL=" "$env_file" 2>/dev/null | cut -d= -f2)
    current_model=${current_model:-"mistralai/Mistral-7B-Instruct-v0.3"}

    echo "Current model: $current_model"
    echo ""
    echo -e "${YELLOW}Recommended models for 16GB VRAM:${NC}"
    echo ""
    echo "  1) mistralai/Mistral-7B-Instruct-v0.3 (7B, fast)"
    echo "  2) Qwen/Qwen2.5-7B-Instruct (7B, multilingual)"
    echo "  3) meta-llama/Llama-3.2-3B-Instruct (3B, very fast)"
    echo "  4) microsoft/Phi-3-mini-4k-instruct (3.8B, efficient)"
    echo ""
    echo -e "${YELLOW}For 24GB+ VRAM:${NC}"
    echo ""
    echo "  5) Qwen/Qwen2.5-14B-Instruct (14B, best quality)"
    echo "  6) meta-llama/Llama-3.1-8B-Instruct (8B)"
    echo ""
    echo "  7) Custom model (enter HuggingFace ID)"
    echo "  0) Cancel"
    echo ""
    read -p "Select model: " model_choice

    local new_model=""
    local served_name=""
    local max_len="8192"

    case $model_choice in
        1) new_model="mistralai/Mistral-7B-Instruct-v0.3"; served_name="mistral-7b" ;;
        2) new_model="Qwen/Qwen2.5-7B-Instruct"; served_name="qwen2.5-7b"; max_len="32768" ;;
        3) new_model="meta-llama/Llama-3.2-3B-Instruct"; served_name="llama-3b" ;;
        4) new_model="microsoft/Phi-3-mini-4k-instruct"; served_name="phi3-mini"; max_len="4096" ;;
        5) new_model="Qwen/Qwen2.5-14B-Instruct"; served_name="qwen2.5-14b"; max_len="4096" ;;
        6) new_model="meta-llama/Llama-3.1-8B-Instruct"; served_name="llama-8b" ;;
        7)
            read -p "Enter HuggingFace model ID: " new_model
            read -p "API model name (e.g., my-model): " served_name
            read -p "Max context length [8192]: " max_len
            max_len=${max_len:-8192}
            ;;
        0|"") return ;;
        *) echo -e "${RED}Invalid option${NC}"; press_enter; return ;;
    esac

    if [ -n "$new_model" ]; then
        log "Updating vLLM configuration..."

        # Update .env file
        cat > "$env_file" << EOF
# vLLM Configuration
VLLM_MODEL=$new_model
VLLM_SERVED_NAME=$served_name
VLLM_MAX_MODEL_LEN=$max_len
VLLM_GPU_MEMORY_UTIL=0.90
VLLM_DTYPE=auto
HF_TOKEN=
EOF

        log "Configuration saved to $env_file"

        if confirm "Restart vLLM now to apply changes?" "y"; then
            cd "$dir"
            docker compose down
            docker compose up -d
            log "vLLM restarting with $new_model"
            echo ""
            echo "Note: Model download may take a few minutes."
            echo "Check logs with: docker logs -f vllm"
        fi
    fi

    press_enter
}

# Configure Ollama model
configure_ollama() {
    local dir="$INSTALL_DIR/local-ollama-server"

    header "Configure Ollama Model"

    if [ ! -d "$dir" ]; then
        warn "Ollama not installed. Install it first."
        press_enter
        return
    fi

    # List current models
    echo "Installed models:"
    docker exec ollama ollama list 2>/dev/null || echo "  (none or container not running)"
    echo ""
    echo -e "${YELLOW}Available actions:${NC}"
    echo ""
    echo "  1) Pull a new model"
    echo "  2) Remove a model"
    echo "  3) Show recommended models"
    echo "  0) Cancel"
    echo ""
    read -p "Select option: " ollama_choice

    case $ollama_choice in
        1)
            echo ""
            echo -e "${YELLOW}Popular models for 16GB VRAM:${NC}"
            echo "  mistral:7b, qwen2.5:7b, llama3.2:3b, phi3:mini, gemma2:9b"
            echo ""
            read -p "Model to pull (e.g., mistral:7b): " model_name
            if [ -n "$model_name" ]; then
                log "Pulling $model_name..."
                docker exec ollama ollama pull "$model_name"
            fi
            ;;
        2)
            echo ""
            read -p "Model to remove: " model_name
            if [ -n "$model_name" ]; then
                docker exec ollama ollama rm "$model_name"
                log "Removed $model_name"
            fi
            ;;
        3)
            echo ""
            echo -e "${CYAN}Recommended models for 16GB VRAM:${NC}"
            echo ""
            echo "  mistral:7b     - 7B, fast, great all-around"
            echo "  qwen2.5:7b     - 7B, multilingual"
            echo "  llama3.2:3b    - 3B, very fast"
            echo "  phi3:mini      - 3.8B, efficient"
            echo "  gemma2:9b      - 9B, good quality"
            echo ""
            echo -e "${CYAN}For 24GB+ VRAM:${NC}"
            echo ""
            echo "  qwen2.5:14b    - 14B, excellent quality"
            echo "  llama3.1:8b    - 8B, good balance"
            echo "  deepseek-r1:14b - 14B, great reasoning"
            echo ""
            ;;
        0|"") return ;;
    esac

    press_enter
}

# Configure ComfyUI models
configure_comfyui() {
    local dir="$INSTALL_DIR/local-comfyui-server"

    header "Configure ComfyUI Models"

    if [ ! -d "$dir" ]; then
        warn "ComfyUI not installed. Install it first."
        press_enter
        return
    fi

    # List current models
    echo "Installed checkpoint models:"
    if ls "$dir/models/checkpoints"/*.safetensors "$dir/models/checkpoints"/*.ckpt 2>/dev/null; then
        ls -lh "$dir/models/checkpoints"/*.safetensors "$dir/models/checkpoints"/*.ckpt 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
    else
        echo "  (none)"
    fi
    echo ""

    echo -e "${YELLOW}Available actions:${NC}"
    echo ""
    echo -e "  ${CYAN}P) Install Preset (recommended models + settings)${NC}"
    echo ""
    echo "  1) Download a checkpoint model"
    echo "  2) Download a VAE model"
    echo "  3) Download a LoRA model"
    echo "  4) Download an upscaler model"
    echo "  5) Show model directory paths"
    echo "  6) View/Edit settings"
    echo "  0) Cancel"
    echo ""
    read -p "Select option: " comfy_choice

    case $comfy_choice in
        1)
            echo ""
            echo -e "${CYAN}Popular Checkpoint Models:${NC}"
            echo ""
            echo "  1) SDXL Base 1.0 (6.9GB) - Best quality, requires 8GB+ VRAM"
            echo "  2) SDXL Turbo (6.9GB) - Fast SDXL, 1-4 steps"
            echo "  3) SD 1.5 (4.3GB) - Classic, works on 4GB+ VRAM"
            echo "  4) Realistic Vision v5.1 (2GB) - Photorealistic SD 1.5"
            echo "  5) DreamShaper XL (6.5GB) - Artistic SDXL"
            echo "  6) Juggernaut XL (6.5GB) - High quality SDXL"
            echo "  7) Custom URL"
            echo "  0) Cancel"
            echo ""
            read -p "Select model: " model_choice

            local model_url=""
            local model_name=""

            case $model_choice in
                1)
                    model_url="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
                    model_name="sd_xl_base_1.0.safetensors"
                    ;;
                2)
                    model_url="https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors"
                    model_name="sd_xl_turbo_1.0_fp16.safetensors"
                    ;;
                3)
                    model_url="https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"
                    model_name="v1-5-pruned-emaonly.safetensors"
                    ;;
                4)
                    model_url="https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1_fp16-no-ema.safetensors"
                    model_name="Realistic_Vision_V5.1.safetensors"
                    ;;
                5)
                    model_url="https://huggingface.co/Lykon/dreamshaper-xl-v2-turbo/resolve/main/DreamShaperXL_Turbo_v2_1.safetensors"
                    model_name="DreamShaperXL_Turbo_v2_1.safetensors"
                    ;;
                6)
                    model_url="https://huggingface.co/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"
                    model_name="Juggernaut-XL_v9.safetensors"
                    ;;
                7)
                    read -p "Enter model URL: " model_url
                    read -p "Save as filename: " model_name
                    ;;
                0|"") return ;;
                *) warn "Invalid option"; return ;;
            esac

            if [ -n "$model_url" ] && [ -n "$model_name" ]; then
                # Ensure directory exists
                mkdir -p "$dir/models/checkpoints"
                log "Downloading $model_name..."
                echo "This may take several minutes depending on your connection."
                echo ""
                wget -c --progress=bar:force -O "$dir/models/checkpoints/$model_name" "$model_url"
                if [ $? -eq 0 ]; then
                    log "Model downloaded successfully!"
                    log "Location: $dir/models/checkpoints/$model_name"
                else
                    error "Download failed"
                fi
            fi
            ;;
        2)
            echo ""
            echo -e "${CYAN}Popular VAE Models:${NC}"
            echo ""
            echo "  1) SDXL VAE (335MB) - For SDXL models"
            echo "  2) SD 1.5 VAE (335MB) - For SD 1.5 models"
            echo "  3) Custom URL"
            echo "  0) Cancel"
            echo ""
            read -p "Select VAE: " vae_choice

            local vae_url=""
            local vae_name=""

            case $vae_choice in
                1)
                    vae_url="https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
                    vae_name="sdxl_vae.safetensors"
                    ;;
                2)
                    vae_url="https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors"
                    vae_name="vae-ft-mse-840000-ema-pruned.safetensors"
                    ;;
                3)
                    read -p "Enter VAE URL: " vae_url
                    read -p "Save as filename: " vae_name
                    ;;
                0|"") return ;;
                *) warn "Invalid option"; return ;;
            esac

            if [ -n "$vae_url" ] && [ -n "$vae_name" ]; then
                mkdir -p "$dir/models/vae"
                log "Downloading $vae_name..."
                wget -c --progress=bar:force -O "$dir/models/vae/$vae_name" "$vae_url"
                if [ $? -eq 0 ]; then
                    log "VAE downloaded: $dir/models/vae/$vae_name"
                fi
            fi
            ;;
        3)
            echo ""
            echo -e "${CYAN}Popular LoRA Models:${NC}"
            echo ""
            echo "  LoRAs are smaller models that modify checkpoint behavior."
            echo "  Browse: https://civitai.com/models?types=LORA"
            echo ""
            read -p "Enter LoRA URL: " lora_url
            if [ -n "$lora_url" ]; then
                read -p "Save as filename: " lora_name
                if [ -n "$lora_name" ]; then
                    mkdir -p "$dir/models/loras"
                    log "Downloading $lora_name..."
                    wget -c --progress=bar:force -O "$dir/models/loras/$lora_name" "$lora_url"
                    if [ $? -eq 0 ]; then
                        log "LoRA downloaded: $dir/models/loras/$lora_name"
                    fi
                fi
            fi
            ;;
        4)
            echo ""
            echo -e "${CYAN}Upscaler Models:${NC}"
            echo ""
            echo "  1) 4x-UltraSharp (67MB) - Best quality upscaler"
            echo "  2) 4x-AnimeSharp (67MB) - For anime/illustration"
            echo "  3) ESRGAN 4x (67MB) - General purpose"
            echo "  4) Custom URL"
            echo "  0) Cancel"
            echo ""
            read -p "Select upscaler: " upscale_choice

            local upscale_url=""
            local upscale_name=""

            case $upscale_choice in
                1)
                    upscale_url="https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth"
                    upscale_name="4x-UltraSharp.pth"
                    ;;
                2)
                    upscale_url="https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-AnimeSharp.pth"
                    upscale_name="4x-AnimeSharp.pth"
                    ;;
                3)
                    upscale_url="https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x_NMKD-Superscale-SP_178000_G.pth"
                    upscale_name="4x_ESRGAN.pth"
                    ;;
                4)
                    read -p "Enter upscaler URL: " upscale_url
                    read -p "Save as filename: " upscale_name
                    ;;
                0|"") ;;
            esac

            if [ -n "$upscale_url" ] && [ -n "$upscale_name" ]; then
                mkdir -p "$dir/models/upscale_models"
                log "Downloading $upscale_name..."
                wget -c --progress=bar:force -O "$dir/models/upscale_models/$upscale_name" "$upscale_url"
                if [ $? -eq 0 ]; then
                    log "Upscaler downloaded: $dir/models/upscale_models/$upscale_name"
                fi
            fi
            ;;
        5)
            echo ""
            echo -e "${CYAN}Model Directory Paths:${NC}"
            echo ""
            echo "  Checkpoints: $dir/models/checkpoints/"
            echo "  VAE:         $dir/models/vae/"
            echo "  LoRA:        $dir/models/loras/"
            echo "  ControlNet:  $dir/models/controlnet/"
            echo "  Upscale:     $dir/models/upscale_models/"
            echo "  Embeddings:  $dir/models/embeddings/"
            echo "  CLIP:        $dir/models/clip/"
            echo ""
            echo "Download models manually and place in these directories."
            echo ""
            ;;
        6)
            view_comfyui_settings "$dir"
            ;;
        [Pp])
            install_comfyui_preset "$dir"
            ;;
        0|"") return ;;
    esac

    press_enter
}

# View/edit ComfyUI settings
view_comfyui_settings() {
    local dir="$1"
    local settings_file="$dir/settings.json"

    echo ""
    echo -e "${CYAN}Current ComfyUI Settings:${NC}"
    echo ""

    if [ -f "$settings_file" ]; then
        cat "$settings_file"
    else
        echo "No custom settings file found."
        echo "Settings are configured per-workflow in ComfyUI."
    fi

    echo ""
    echo -e "${YELLOW}Recommended settings for photorealistic output:${NC}"
    echo ""
    echo "  Sampler:    dpmpp_2m or euler_ancestral"
    echo "  Scheduler:  karras"
    echo "  Steps:      25-35"
    echo "  CFG Scale:  4-6 (SDXL) or 7-9 (SD 1.5)"
    echo "  Resolution: 1024x1024 (SDXL) or 512x512 (SD 1.5)"
    echo ""
}

# Install ComfyUI preset
install_comfyui_preset() {
    local dir="$1"

    echo ""
    echo -e "${CYAN}ComfyUI Presets:${NC}"
    echo ""
    echo "  1) Photorealistic (Gemini Flash-like)"
    echo "     - Juggernaut XL v9 (6.5GB)"
    echo "     - SDXL VAE + 4x-UltraSharp upscaler"
    echo ""
    echo "  2) Versatile (Multi-style)"
    echo "     - SDXL Base + DreamShaper XL (~13GB)"
    echo "     - Good for photos, art, illustrations, abstracts"
    echo ""
    echo "  3) Fast & Good (SDXL Turbo)"
    echo "     - SDXL Turbo (6.9GB)"
    echo "     - 1-4 step generation"
    echo ""
    echo "  4) Lightweight (SD 1.5)"
    echo "     - Realistic Vision v5.1 (2GB)"
    echo "     - Works on 4GB VRAM"
    echo ""
    echo "  0) Cancel"
    echo ""
    read -p "Select preset: " preset_choice

    case $preset_choice in
        1)
            install_photorealistic_preset "$dir"
            ;;
        2)
            install_versatile_preset "$dir"
            ;;
        3)
            install_fast_preset "$dir"
            ;;
        4)
            install_lightweight_preset "$dir"
            ;;
        0|"") return ;;
    esac
}

configure_video() {
    local dir="$INSTALL_DIR/local-video-server"
    local compose_file="$dir/docker-compose.yml"

    header "Configure Video Server Model"

    if [ ! -d "$dir" ]; then
        warn "Video server not installed. Install it first."
        press_enter
        return
    fi

    # Get current model
    local current_model=$(grep "MODEL_ID=" "$compose_file" 2>/dev/null | grep -v "^#" | cut -d= -f2 | tr -d '"' | head -1)
    echo "Current model: ${current_model:-Not set}"
    echo ""

    echo -e "${YELLOW}Available Wan2.2 Models:${NC}"
    echo ""
    echo "  1) Wan2.2-T2V-A14B (Text-to-Video, 14B params)"
    echo "     Best quality, needs CPU offload for 16GB VRAM"
    echo ""
    echo "  2) Wan2.2-I2V-A14B (Image-to-Video, 14B params)"
    echo "     Animate images, needs CPU offload for 16GB VRAM"
    echo ""
    echo "  3) Wan2.2-TI2V-5B (Text/Image-to-Video, 5B params)"
    echo "     Smaller model, easier on VRAM"
    echo ""
    echo "  4) Wan2.1-T2V-14B (Legacy Text-to-Video)"
    echo "     Older version"
    echo ""
    echo "  0) Cancel"
    echo ""
    read -p "Select model: " model_choice

    local new_model=""
    case $model_choice in
        1) new_model="Wan-AI/Wan2.2-T2V-A14B" ;;
        2) new_model="Wan-AI/Wan2.2-I2V-A14B" ;;
        3) new_model="Wan-AI/Wan2.2-TI2V-5B" ;;
        4) new_model="Wan-AI/Wan2.1-T2V-14B" ;;
        0|"") return ;;
        *) warn "Invalid option"; press_enter; return ;;
    esac

    log "Setting model to: $new_model"

    # Update docker-compose.yml
    if grep -q "MODEL_ID=" "$compose_file"; then
        sed -i "s|MODEL_ID=.*|MODEL_ID=$new_model|" "$compose_file"
    else
        # Add MODEL_ID if not present
        sed -i "/ENABLE_CPU_OFFLOAD/a\\      - MODEL_ID=$new_model" "$compose_file"
    fi

    log "Model updated in docker-compose.yml"
    echo ""

    if confirm "Restart video server to apply changes?" "y"; then
        cd "$dir"
        docker compose down 2>/dev/null || true
        docker compose up -d
        log "Video server restarted with new model"
        echo ""
        warn "Note: First request will download the new model (~20GB)"
    fi

    press_enter
}

# Download helper function
download_model() {
    local url="$1"
    local dest="$2"
    local name="$3"

    if [ -f "$dest" ]; then
        log "$name already exists, skipping..."
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    log "Downloading $name..."
    wget -c --progress=bar:force -O "$dest" "$url"
    return $?
}

# Photorealistic preset (Gemini Flash-like)
install_photorealistic_preset() {
    local dir="$1"

    header "Installing Photorealistic Preset"
    echo "This will download ~7GB of models for best photorealistic quality."
    echo ""
    if ! confirm "Continue with download?" "y"; then
        return
    fi

    echo ""
    log "Installing Photorealistic (Gemini Flash-like) preset..."
    echo ""

    # Download Juggernaut XL
    download_model \
        "https://huggingface.co/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors" \
        "$dir/models/checkpoints/Juggernaut-XL_v9.safetensors" \
        "Juggernaut XL v9"

    # Download SDXL VAE
    download_model \
        "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
        "$dir/models/vae/sdxl_vae.safetensors" \
        "SDXL VAE"

    # Download 4x-UltraSharp upscaler
    download_model \
        "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth" \
        "$dir/models/upscale_models/4x-UltraSharp.pth" \
        "4x-UltraSharp Upscaler"

    # Save recommended settings
    mkdir -p "$dir/presets"
    cat > "$dir/presets/photorealistic.json" << 'PRESET'
{
    "name": "Photorealistic (Gemini Flash-like)",
    "checkpoint": "Juggernaut-XL_v9.safetensors",
    "vae": "sdxl_vae.safetensors",
    "upscaler": "4x-UltraSharp.pth",
    "settings": {
        "sampler": "dpmpp_2m",
        "scheduler": "karras",
        "steps": 30,
        "cfg_scale": 5,
        "width": 1024,
        "height": 1024,
        "clip_skip": 2
    },
    "recommended_prompt_prefix": "masterpiece, best quality, highly detailed, photorealistic, 8k uhd, professional photography, natural lighting",
    "recommended_negative": "cartoon, anime, illustration, painting, drawing, art, sketch, low quality, blurry, deformed, ugly, bad anatomy, disfigured, mutation, extra limbs"
}
PRESET

    log "Photorealistic preset installed!"
    echo ""
    echo -e "${GREEN}Models downloaded:${NC}"
    echo "  ✓ Juggernaut XL v9 (checkpoint)"
    echo "  ✓ SDXL VAE"
    echo "  ✓ 4x-UltraSharp (upscaler)"
    echo ""
    echo -e "${YELLOW}Recommended workflow settings:${NC}"
    echo "  Sampler:    dpmpp_2m"
    echo "  Scheduler:  karras"
    echo "  Steps:      30"
    echo "  CFG Scale:  5"
    echo "  Resolution: 1024x1024"
    echo ""
    echo -e "${YELLOW}Prompt tips:${NC}"
    echo "  Add to prompt: masterpiece, best quality, photorealistic, 8k uhd"
    echo "  Negative:      cartoon, anime, low quality, blurry, deformed"
    echo ""
    echo "Settings saved to: $dir/presets/photorealistic.json"
}

# Versatile preset (Multi-style)
install_versatile_preset() {
    local dir="$1"

    header "Installing Versatile (Multi-style) Preset"
    echo "This will download ~14GB of models for maximum flexibility."
    echo ""
    echo "Includes:"
    echo "  - SDXL Base 1.0 (best for general use)"
    echo "  - DreamShaper XL (artistic/creative)"
    echo "  - SDXL VAE (better colors)"
    echo "  - 4x-UltraSharp (upscaler)"
    echo ""
    if ! confirm "Continue with download?" "y"; then
        return
    fi

    echo ""
    log "Installing Versatile (Multi-style) preset..."
    echo ""

    # Download SDXL Base
    download_model \
        "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
        "$dir/models/checkpoints/sd_xl_base_1.0.safetensors" \
        "SDXL Base 1.0"

    # Download DreamShaper XL
    download_model \
        "https://huggingface.co/Lykon/dreamshaper-xl-v2-turbo/resolve/main/DreamShaperXL_Turbo_v2_1.safetensors" \
        "$dir/models/checkpoints/DreamShaperXL_Turbo_v2_1.safetensors" \
        "DreamShaper XL"

    # Download SDXL VAE
    download_model \
        "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
        "$dir/models/vae/sdxl_vae.safetensors" \
        "SDXL VAE"

    # Download 4x-UltraSharp upscaler
    download_model \
        "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/4x-UltraSharp.pth" \
        "$dir/models/upscale_models/4x-UltraSharp.pth" \
        "4x-UltraSharp Upscaler"

    # Save preset config
    mkdir -p "$dir/presets"
    cat > "$dir/presets/versatile.json" << 'PRESET'
{
    "name": "Versatile (Multi-style)",
    "checkpoints": {
        "sdxl_base": {
            "file": "sd_xl_base_1.0.safetensors",
            "best_for": ["photorealistic", "general", "portraits", "landscapes"]
        },
        "dreamshaper": {
            "file": "DreamShaperXL_Turbo_v2_1.safetensors",
            "best_for": ["artistic", "illustration", "fantasy", "abstract", "creative"]
        }
    },
    "vae": "sdxl_vae.safetensors",
    "upscaler": "4x-UltraSharp.pth",
    "style_guides": {
        "photorealistic": {
            "checkpoint": "sd_xl_base_1.0.safetensors",
            "cfg_scale": 5,
            "steps": 30,
            "prompt_add": "photorealistic, 8k uhd, professional photography, natural lighting",
            "negative": "cartoon, anime, illustration, painting, drawing"
        },
        "artistic": {
            "checkpoint": "DreamShaperXL_Turbo_v2_1.safetensors",
            "cfg_scale": 4,
            "steps": 25,
            "prompt_add": "artistic, creative, beautiful composition",
            "negative": "ugly, deformed, low quality"
        },
        "illustration": {
            "checkpoint": "DreamShaperXL_Turbo_v2_1.safetensors",
            "cfg_scale": 5,
            "steps": 25,
            "prompt_add": "digital illustration, clean lines, professional artwork",
            "negative": "photo, realistic, blurry, low quality"
        },
        "abstract": {
            "checkpoint": "DreamShaperXL_Turbo_v2_1.safetensors",
            "cfg_scale": 3,
            "steps": 20,
            "prompt_add": "abstract art, geometric, modern art, vibrant colors",
            "negative": "realistic, photo, ugly"
        },
        "infographic": {
            "checkpoint": "sd_xl_base_1.0.safetensors",
            "cfg_scale": 6,
            "steps": 30,
            "prompt_add": "infographic style, flat design, clean, professional, icons",
            "negative": "photo, realistic, 3d, complex"
        },
        "3d_render": {
            "checkpoint": "sd_xl_base_1.0.safetensors",
            "cfg_scale": 5,
            "steps": 35,
            "prompt_add": "3D render, octane render, blender, smooth lighting, high detail",
            "negative": "flat, 2d, sketch, drawing"
        }
    },
    "base_settings": {
        "sampler": "dpmpp_2m",
        "scheduler": "karras",
        "width": 1024,
        "height": 1024
    }
}
PRESET

    log "Versatile preset installed!"
    echo ""
    echo -e "${GREEN}Models downloaded:${NC}"
    echo "  ✓ SDXL Base 1.0 (general purpose)"
    echo "  ✓ DreamShaper XL (artistic/creative)"
    echo "  ✓ SDXL VAE"
    echo "  ✓ 4x-UltraSharp (upscaler)"
    echo ""
    echo -e "${YELLOW}Which model to use:${NC}"
    echo ""
    echo "  SDXL Base 1.0 - Best for:"
    echo "    • Photorealistic images"
    echo "    • Infographics & diagrams"
    echo "    • 3D renders"
    echo "    • General purpose"
    echo ""
    echo "  DreamShaper XL - Best for:"
    echo "    • Artistic/creative styles"
    echo "    • Illustrations"
    echo "    • Abstract art"
    echo "    • Fantasy scenes"
    echo ""
    echo -e "${YELLOW}Style prompt examples:${NC}"
    echo ""
    echo "  Photorealistic: 'professional photography, natural lighting, 8k'"
    echo "  Illustration:   'digital illustration, clean lines, vector style'"
    echo "  Abstract:       'abstract art, geometric shapes, vibrant colors'"
    echo "  Infographic:    'infographic style, flat design, icons, diagram'"
    echo "  3D Render:      '3D render, octane render, smooth lighting'"
    echo ""
    echo "Settings saved to: $dir/presets/versatile.json"
}

# Fast preset (SDXL Turbo)
install_fast_preset() {
    local dir="$1"

    header "Installing Fast Preset"
    echo "This will download ~7GB of models for fast 1-4 step generation."
    echo ""
    if ! confirm "Continue with download?" "y"; then
        return
    fi

    echo ""
    log "Installing Fast & Good (SDXL Turbo) preset..."
    echo ""

    download_model \
        "https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors" \
        "$dir/models/checkpoints/sd_xl_turbo_1.0_fp16.safetensors" \
        "SDXL Turbo"

    download_model \
        "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
        "$dir/models/vae/sdxl_vae.safetensors" \
        "SDXL VAE"

    mkdir -p "$dir/presets"
    cat > "$dir/presets/fast.json" << 'PRESET'
{
    "name": "Fast & Good (SDXL Turbo)",
    "checkpoint": "sd_xl_turbo_1.0_fp16.safetensors",
    "vae": "sdxl_vae.safetensors",
    "settings": {
        "sampler": "euler_ancestral",
        "scheduler": "normal",
        "steps": 4,
        "cfg_scale": 1,
        "width": 1024,
        "height": 1024
    },
    "notes": "SDXL Turbo uses very low steps (1-4) and CFG (1-2)"
}
PRESET

    log "Fast preset installed!"
    echo ""
    echo -e "${YELLOW}SDXL Turbo settings:${NC}"
    echo "  Steps:     1-4 (yes, really!)"
    echo "  CFG Scale: 1-2"
    echo "  Sampler:   euler_ancestral"
}

# Lightweight preset (SD 1.5)
install_lightweight_preset() {
    local dir="$1"

    header "Installing Lightweight Preset"
    echo "This will download ~2.5GB of models that work on 4GB+ VRAM."
    echo ""
    if ! confirm "Continue with download?" "y"; then
        return
    fi

    echo ""
    log "Installing Lightweight (SD 1.5) preset..."
    echo ""

    download_model \
        "https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1_fp16-no-ema.safetensors" \
        "$dir/models/checkpoints/Realistic_Vision_V5.1.safetensors" \
        "Realistic Vision v5.1"

    download_model \
        "https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors" \
        "$dir/models/vae/vae-ft-mse-840000-ema-pruned.safetensors" \
        "SD 1.5 VAE"

    mkdir -p "$dir/presets"
    cat > "$dir/presets/lightweight.json" << 'PRESET'
{
    "name": "Lightweight (SD 1.5)",
    "checkpoint": "Realistic_Vision_V5.1.safetensors",
    "vae": "vae-ft-mse-840000-ema-pruned.safetensors",
    "settings": {
        "sampler": "dpmpp_2m",
        "scheduler": "karras",
        "steps": 25,
        "cfg_scale": 7,
        "width": 512,
        "height": 512
    },
    "notes": "SD 1.5 works on 4GB VRAM. Use 512x512 or 768x768 resolution."
}
PRESET

    log "Lightweight preset installed!"
    echo ""
    echo -e "${YELLOW}SD 1.5 settings:${NC}"
    echo "  Resolution: 512x512 or 768x768"
    echo "  Steps:      20-30"
    echo "  CFG Scale:  7-9"
}

install_service() {
    require_root || return

    local name="$1"
    local repo="$2"
    local port="$3"
    local dir="local-${name}-server"

    # Map service name to container name
    local container="$name"
    case $name in
        video) container="wan-video" ;;
    esac

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    if [ -d "$dir" ]; then
        # Show service-specific status
        case $name in
            ollama) show_ollama_status ;;
            chatterbox) show_chatterbox_status ;;
            video) show_video_status ;;
            vllm) show_vllm_status ;;
            comfyui) show_comfyui_status ;;
            *) show_service_status "$name" "$container" "$port" ;;
        esac

        echo -e "${YELLOW}Management Options:${NC}"
        echo ""
        echo "  1) Start service"
        echo "  2) Stop service"
        echo "  3) Restart service"
        echo ""
        echo -e "${YELLOW}Configuration:${NC}"
        echo ""
        echo "  4) Configure model/settings"
        echo "  5) View logs"
        echo "  6) Open firewall port"
        echo ""
        echo -e "${YELLOW}Maintenance:${NC}"
        echo ""
        echo "  7) Update (git pull + rebuild)"
        echo "  8) Reinstall (fresh clone)"
        echo -e "  9) ${RED}Uninstall (remove completely)${NC}"
        echo ""
        echo "  0) Back"
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
                docker compose restart
                log "$name restarted"
                ;;
            4)
                case $name in
                    vllm) configure_vllm ;;
                    ollama) configure_ollama ;;
                    comfyui) configure_comfyui ;;
                    video) configure_video ;;
                    chatterbox)
                        echo ""
                        echo "Chatterbox parameters are set per-request via API:"
                        echo "  temperature:  0.7 (default)"
                        echo "  exaggeration: 0.4-0.6 for smoother audio"
                        echo "  cfg_weight:   0.5 (default)"
                        echo "  speed:        1.0 (default)"
                        echo ""
                        echo "Use reference_audio_base64 for voice cloning."
                        press_enter
                        ;;
                    *) warn "Model configuration not available for $name" ;;
                esac
                return
                ;;
            5)
                view_service_logs "$container" "$name"
                ;;
            6)
                open_docker_port "$port"
                log "Port $port opened"
                ;;
            7)
                cd "$dir"
                git pull
                docker compose down 2>/dev/null || true
                # Rebuild if Dockerfile exists (picks up code changes)
                if [ -f Dockerfile ] || [ -f */Dockerfile ]; then
                    log "Rebuilding container..."
                    docker compose build --no-cache
                else
                    # Pull latest image for image-based services
                    log "Pulling latest image..."
                    docker compose pull
                fi
                docker compose up -d
                log "$name updated"
                ;;
            8)
                cd "$dir"
                docker compose down 2>/dev/null || true
                # Remove old images to force fresh build
                docker compose rm -f 2>/dev/null || true
                cd ..
                rm -rf "$dir"
                git clone "$repo"
                cd "$dir"
                # Copy .env.example if exists
                [ -f .env.example ] && cp .env.example .env
                # Build from scratch or pull latest image
                if [ -f Dockerfile ] || [ -f */Dockerfile ]; then
                    log "Building container..."
                    docker compose build --no-cache
                else
                    log "Pulling latest image..."
                    docker compose pull
                fi
                docker compose up -d
                log "$name reinstalled"
                ;;
            9)
                echo ""
                echo -e "${RED}WARNING: This will completely remove $name${NC}"
                echo ""
                echo "This will:"
                echo "  • Stop and remove the container"
                echo "  • Delete the installation directory ($INSTALL_DIR/$dir)"
                echo "  • Optionally remove Docker images and volumes"
                echo ""
                if ! confirm "Are you sure you want to uninstall $name?" "n"; then
                    return
                fi

                cd "$dir"

                # Stop and remove containers
                log "Stopping $name..."
                docker compose down 2>/dev/null || true
                docker compose rm -f 2>/dev/null || true

                # Ask about removing images
                echo ""
                if confirm "Remove Docker images? (frees disk space)" "y"; then
                    log "Removing Docker images..."
                    docker compose down --rmi all 2>/dev/null || true
                fi

                # Ask about removing volumes
                if confirm "Remove Docker volumes? (deletes downloaded models)" "n"; then
                    log "Removing Docker volumes..."
                    docker compose down -v 2>/dev/null || true
                fi

                # Remove directory
                cd "$INSTALL_DIR"
                rm -rf "$dir"
                log "Removed $dir"

                # Ask about closing firewall port
                echo ""
                if confirm "Close firewall port $port?" "y"; then
                    ufw delete allow "$port/tcp" 2>/dev/null || true
                    # Remove from DOCKER-USER chain if exists
                    iptables -D DOCKER-USER -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
                    log "Closed port $port"
                fi

                log "$name has been completely uninstalled"
                ;;
            0|"")
                return
                ;;
        esac

        press_enter
        return
    fi

    # New installation
    header "Installing $name"
    log "Cloning repository..."
    git clone "$repo"
    cd "$dir"

    # Special handling for ComfyUI
    if [ "$name" = "comfyui" ]; then
        mkdir -p models/checkpoints output input custom_nodes
        warn "Download SDXL model to $INSTALL_DIR/$dir/models/checkpoints/"
    fi

    # Copy .env.example if exists
    [ -f .env.example ] && cp .env.example .env

    log "Starting $name..."
    docker compose up -d
    log "$name installed and started"

    # Firewall prompt for Docker container port (new installs only)
    echo ""
    echo -e "${YELLOW}Firewall Configuration${NC}"
    echo "This service runs on port $port"
    echo ""

    if confirm "Open port $port in firewall?" "y"; then
        open_docker_port "$port"
    fi

    echo ""
    echo -e "Access at: ${CYAN}http://$(hostname -I | awk '{print $1}'):$port${NC}"

    press_enter
}

list_services() {
    clear

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}GPU Services Dashboard${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Service definitions: name, container, port
    local services=(
        "Ollama LLM:ollama:11434"
        "Chatterbox TTS:chatterbox:8100"
        "Video Server:wan-video:8200"
        "vLLM:vllm:8000"
        "ComfyUI:comfyui:8188"
        "P16 Agent:p16-agent:9100"
    )

    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    printf "  ${BOLD}%-18s %-12s %-10s %s${NC}\n" "SERVICE" "STATUS" "PORT" "ENDPOINT"
    echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"

    for svc_info in "${services[@]}"; do
        IFS=':' read -r name container port <<< "$svc_info"
        local status=$(docker ps --filter "name=^${container}$" --format "{{.Status}}" 2>/dev/null)

        if [ -n "$status" ]; then
            local indicator="${GREEN}●${NC}"
            local status_text="Running"
            if echo "$status" | grep -q "(healthy)"; then
                indicator="${GREEN}●${NC}"
                status_text="${GREEN}Healthy${NC}"
            elif echo "$status" | grep -q "(unhealthy)"; then
                indicator="${RED}●${NC}"
                status_text="${RED}Unhealthy${NC}"
            else
                indicator="${YELLOW}●${NC}"
                status_text="${YELLOW}Starting${NC}"
            fi
            printf "  $indicator %-16s %-18b %-10s %s\n" "$name" "$status_text" "$port" "http://${ip}:${port}"
        else
            # Check if installed but not running
            local dir_name="local-$(echo "$container" | sed 's/wan-//')-server"
            if [ "$container" = "p16-agent" ]; then
                dir_name="p16-agent"
            fi
            if [ -d "$INSTALL_DIR/$dir_name" ]; then
                printf "  ${RED}○${NC} %-16s ${DIM}%-18s${NC} %-10s %s\n" "$name" "Stopped" "$port" "-"
            else
                printf "  ${DIM}○ %-16s %-18s %-10s %s${NC}\n" "$name" "Not installed" "$port" "-"
            fi
        fi
    done

    echo ""

    # GPU Quick Status
    echo -e "  ${BOLD}${CYAN}GPU Quick Status${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
    local gpu_info=$(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$gpu_info" ]; then
        IFS=',' read -r gpu_name temp util mem_used mem_total <<< "$gpu_info"
        temp=$(echo "$temp" | xargs)
        util=$(echo "$util" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        local mem_percent=$((mem_used * 100 / mem_total))

        local t_color=$(temp_color "$temp")
        echo -e "  $(echo "$gpu_name" | xargs)"
        echo -e "  Temp: ${t_color}${temp}°C${NC} | VRAM: $(usage_color "$mem_percent")${mem_percent}%${NC} (${mem_used}/${mem_total} MB) | Util: $(usage_color "$util")${util}%${NC}"
    else
        echo -e "  ${RED}GPU not available${NC}"
    fi
    echo ""

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
# P16 Agent Functions
# ============================================
install_agent() {
    require_root || return

    local name="p16-agent"
    local repo="https://github.com/profzeller/p16-agent.git"
    local port="9100"
    local dir="$INSTALL_DIR/$name"

    header "P16 Monitoring Agent"

    if [ -d "$dir" ]; then
        echo "P16 Agent is installed."
        echo ""
        echo "Options:"
        echo "  1) Start agent"
        echo "  2) Stop agent"
        echo "  3) View logs"
        echo "  4) Update (git pull)"
        echo "  5) Reinstall"
        echo "  6) Remove"
        echo "  0) Cancel"
        echo ""
        read -p "Select option: " agent_choice

        case $agent_choice in
            1)
                cd "$dir"
                docker compose up -d
                log "P16 Agent started"
                echo ""
                echo -e "${GREEN}Agent running at http://$(hostname -I | awk '{print $1}'):$port${NC}"
                ;;
            2)
                cd "$dir"
                docker compose down
                log "P16 Agent stopped"
                ;;
            3)
                cd "$dir"
                docker compose logs -f --tail=100
                ;;
            4)
                cd "$dir"
                git pull
                docker compose down 2>/dev/null || true
                docker compose build --no-cache
                docker compose up -d
                log "P16 Agent updated"
                ;;
            5)
                rm -rf "$dir"
                git clone "$repo" "$dir"
                cd "$dir"
                docker compose up -d
                log "P16 Agent reinstalled"
                ;;
            6)
                cd "$dir"
                docker compose down 2>/dev/null || true
                rm -rf "$dir"
                log "P16 Agent removed"
                press_enter
                return
                ;;
            0|"")
                return
                ;;
        esac
    else
        echo "P16 Agent collects system metrics (CPU, RAM, GPU, services)"
        echo "and exposes them via HTTP API for remote monitoring."
        echo ""
        echo "Port: $port"
        echo ""

        if ! confirm "Install P16 Agent?" "y"; then
            return
        fi

        log "Cloning repository..."
        git clone "$repo" "$dir"
        cd "$dir"

        log "Building and starting agent..."
        docker compose up -d
        log "P16 Agent installed and started"
    fi

    # Firewall prompt
    echo ""
    echo -e "${YELLOW}Firewall Configuration${NC}"
    echo "The agent runs on port $port"
    echo ""

    if confirm "Open port $port in firewall?" "y"; then
        open_docker_port "$port"
    fi

    echo ""
    echo -e "Test endpoint: ${CYAN}curl http://$(hostname -I | awk '{print $1}'):$port/health${NC}"
    echo -e "Metrics:       ${CYAN}curl http://$(hostname -I | awk '{print $1}'):$port/metrics${NC}"

    press_enter
}

# ============================================
# Tools Functions
# ============================================
run_server_status() {
    clear

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}Server Status Dashboard${NC}                       ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # GPU Status
    echo -e "  ${BOLD}${CYAN}GPU${NC}"
    echo -e "  ${DIM}───────────────────────────────────────────────────────${NC}"
    local gpu_info=$(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$gpu_info" ]; then
        IFS=',' read -r gpu_name temp util mem_used mem_total <<< "$gpu_info"
        gpu_name=$(echo "$gpu_name" | xargs)
        temp=$(echo "$temp" | xargs)
        util=$(echo "$util" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        local mem_percent=$((mem_used * 100 / mem_total))

        echo -e "  $gpu_name"
        echo -n "  Temp: "
        if [ "$temp" -lt 50 ]; then
            echo -e "${GREEN}${temp}°C${NC}"
        elif [ "$temp" -lt 70 ]; then
            echo -e "${YELLOW}${temp}°C${NC}"
        else
            echo -e "${RED}${temp}°C${NC}"
        fi
        echo -n "  VRAM: "
        draw_bar "$mem_percent" 25 "$(usage_color "$mem_percent")"
        echo -e " ${DIM}(${mem_used}/${mem_total} MB)${NC}"
        echo -n "  Util: "
        draw_bar "$util" 25 "$(usage_color "$util")"
        echo ""
    else
        echo -e "  ${RED}GPU not available${NC}"
    fi
    echo ""

    # Services
    echo -e "  ${BOLD}${CYAN}GPU Services${NC}"
    echo -e "  ${DIM}───────────────────────────────────────────────────────${NC}"
    local has_services=false
    for svc in ollama chatterbox wan-video vllm comfyui; do
        local status=$(docker ps --filter "name=$svc" --format "{{.Status}}" 2>/dev/null)
        if [ -n "$status" ]; then
            has_services=true
            local health=""
            if echo "$status" | grep -q "(healthy)"; then
                health="${GREEN}●${NC}"
            elif echo "$status" | grep -q "(unhealthy)"; then
                health="${RED}●${NC}"
            else
                health="${YELLOW}●${NC}"
            fi
            printf "  $health %-15s %s\n" "$svc" "$(echo "$status" | sed 's/(healthy)//' | sed 's/(unhealthy)//')"
        fi
    done
    if [ "$has_services" = false ]; then
        echo -e "  ${DIM}(no GPU services running)${NC}"
    fi
    echo ""

    # System Resources
    echo -e "  ${BOLD}${CYAN}System Resources${NC}"
    echo -e "  ${DIM}───────────────────────────────────────────────────────${NC}"

    # RAM
    local ram_info=$(free -m | grep Mem)
    local ram_total=$(echo "$ram_info" | awk '{print $2}')
    local ram_used=$(echo "$ram_info" | awk '{print $3}')
    local ram_percent=$((ram_used * 100 / ram_total))
    echo -n "  RAM:  "
    draw_bar "$ram_percent" 25 "$(usage_color "$ram_percent")"
    echo -e " ${DIM}(${ram_used}/${ram_total} MB)${NC}"

    # Disk
    local disk_info=$(df -m / | tail -1)
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    local disk_percent=$((disk_used * 100 / disk_total))
    echo -n "  Disk: "
    draw_bar "$disk_percent" 25 "$(usage_color "$disk_percent")"
    echo -e " ${DIM}($(numfmt --to=iec $((disk_used * 1024 * 1024)))/$(numfmt --to=iec $((disk_total * 1024 * 1024))))${NC}"

    # CPU Load
    local load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
    local cores=$(nproc 2>/dev/null || echo 1)
    local load_percent=$(echo "$load $cores" | awk '{printf "%.0f", ($1 / $2) * 100}')
    echo -n "  CPU:  "
    draw_bar "$load_percent" 25 "$(usage_color "$load_percent")"
    echo -e " ${DIM}(load: $load)${NC}"

    echo ""

    # Network
    echo -e "  ${BOLD}${CYAN}Network${NC}"
    echo -e "  ${DIM}───────────────────────────────────────────────────────${NC}"
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "  IP: ${GREEN}$ip${NC}"
    echo -e "  Hostname: $(hostname)"
    echo ""

    press_enter
}

run_gpu_monitor() {
    clear
    echo ""
    echo "Select GPU monitor mode:"
    echo ""
    echo "  1) Dashboard (colorful, refreshes every 2s)"
    echo "  2) Classic nvidia-smi (refreshes every 1s)"
    echo "  3) GPU Processes (what's using the GPU)"
    echo "  0) Cancel"
    echo ""
    read -p "Select option [1]: " monitor_choice
    monitor_choice=${monitor_choice:-1}

    case $monitor_choice in
        1) gpu_dashboard ;;
        2) watch -n 1 nvidia-smi 2>/dev/null || nvidia-smi ;;
        3) gpu_processes ;;
        0|"") return ;;
    esac
    press_enter
}

# Colorful progress bar
draw_bar() {
    local percent=$1
    local width=${2:-30}
    local color=$3

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "${color}"
    printf "["
    for ((i=0; i<filled; i++)); do printf "█"; done
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "]${NC} %3d%%" "$percent"
}

# Get color based on temperature
temp_color() {
    local temp=$1
    if [ "$temp" -lt 50 ]; then
        echo "$GREEN"
    elif [ "$temp" -lt 70 ]; then
        echo "$YELLOW"
    else
        echo "$RED"
    fi
}

# Get color based on usage percentage
usage_color() {
    local usage=$1
    if [ "$usage" -lt 50 ]; then
        echo "$GREEN"
    elif [ "$usage" -lt 80 ]; then
        echo "$YELLOW"
    else
        echo "$RED"
    fi
}

gpu_dashboard() {
    trap 'return 0' INT

    while true; do
        clear

        # Get GPU info
        local gpu_info=$(nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,power.limit --format=csv,noheader,nounits 2>/dev/null)

        if [ -z "$gpu_info" ]; then
            echo -e "${RED}GPU not available${NC}"
            sleep 2
            continue
        fi

        IFS=',' read -r gpu_name driver_ver temp util mem_used mem_total power power_limit <<< "$gpu_info"

        # Trim whitespace
        gpu_name=$(echo "$gpu_name" | xargs)
        driver_ver=$(echo "$driver_ver" | xargs)
        temp=$(echo "$temp" | xargs)
        util=$(echo "$util" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        power=$(echo "$power" | xargs | cut -d'.' -f1)
        power_limit=$(echo "$power_limit" | xargs | cut -d'.' -f1)

        # Calculate percentages
        local mem_percent=$((mem_used * 100 / mem_total))
        local power_percent=$((power * 100 / power_limit))

        # Header
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}              ${BOLD}GPU Dashboard${NC}                                ${CYAN}║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo ""

        # GPU Info
        echo -e "  ${BOLD}GPU:${NC}     $gpu_name"
        echo -e "  ${BOLD}Driver:${NC}  $driver_ver"
        echo ""

        # Temperature
        local t_color=$(temp_color "$temp")
        echo -e "  ${BOLD}Temperature:${NC}"
        echo -e "    ${t_color}${temp}°C${NC}"
        if [ "$temp" -lt 50 ]; then
            echo -e "    ${GREEN}◉ Cool${NC}"
        elif [ "$temp" -lt 70 ]; then
            echo -e "    ${YELLOW}◉ Warm${NC}"
        else
            echo -e "    ${RED}◉ Hot!${NC}"
        fi
        echo ""

        # GPU Utilization
        echo -e "  ${BOLD}GPU Utilization:${NC}"
        echo -n "    "
        draw_bar "$util" 35 "$(usage_color "$util")"
        echo ""
        echo ""

        # VRAM Usage
        echo -e "  ${BOLD}VRAM Usage:${NC}"
        echo -n "    "
        draw_bar "$mem_percent" 35 "$(usage_color "$mem_percent")"
        echo ""
        echo -e "    ${DIM}${mem_used} MB / ${mem_total} MB${NC}"
        echo ""

        # Power
        echo -e "  ${BOLD}Power:${NC}"
        echo -n "    "
        draw_bar "$power_percent" 35 "$(usage_color "$power_percent")"
        echo ""
        echo -e "    ${DIM}${power}W / ${power_limit}W${NC}"
        echo ""

        # Running Services
        echo -e "  ${BOLD}GPU Services:${NC}"
        local services=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "ollama|chatterbox|video|vllm|comfyui" || echo "")
        if [ -n "$services" ]; then
            while IFS= read -r svc; do
                echo -e "    ${GREEN}●${NC} $svc"
            done <<< "$services"
        else
            echo -e "    ${DIM}(none running)${NC}"
        fi
        echo ""

        echo -e "${DIM}Press Ctrl+C to exit | Refreshing every 2s${NC}"

        sleep 2
    done

    trap - INT
}

gpu_processes() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}GPU Processes${NC}                                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv,noheader 2>/dev/null | \
        awk -F',' '{printf "  PID: %-8s Memory: %-10s %s\n", $1, $3, $2}' || echo "  No GPU processes running"

    echo ""
    echo -e "${BOLD}Docker containers using GPU:${NC}"
    echo ""
    docker ps --filter "label=com.docker.compose.service" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | \
        head -10 || echo "  None"
    echo ""
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
        echo "Log view options:"
        echo "  1) Last 50 lines (static)"
        echo "  2) Last 100 lines (static)"
        echo "  3) Follow logs (Ctrl+C to stop)"
        echo ""
        read -p "Select option [1]: " log_option
        log_option=${log_option:-1}

        echo ""
        case $log_option in
            1)
                docker logs --tail 50 "$selected" 2>&1 | less +G
                ;;
            2)
                docker logs --tail 100 "$selected" 2>&1 | less +G
                ;;
            3)
                echo "Following logs for $selected (Ctrl+C to stop):"
                echo ""
                # Trap SIGINT to return to menu instead of exiting script
                trap 'echo ""; echo "Stopped following logs."; trap - INT; return 0' INT
                docker logs --tail 50 -f "$selected" 2>&1
                trap - INT
                ;;
            *)
                docker logs --tail 50 "$selected" 2>&1 | less +G
                ;;
        esac
    fi
    press_enter
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

update_server_setup() {
    require_root || return

    header "Update server-setup"

    local current_script="/usr/local/bin/server-setup"
    local repo_url="https://raw.githubusercontent.com/profzeller/p16-server-setup/main/setup.sh"
    local version_url="https://api.github.com/repos/profzeller/p16-server-setup/releases/latest"
    local tmp_script="/tmp/server-setup-new.sh"

    echo -e "Current version: ${CYAN}v${SCRIPT_VERSION}${NC}"
    echo ""

    # Check for latest version
    log "Checking for updates..."
    local latest_version=$(curl -fsSL "$version_url" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')

    if [ -n "$latest_version" ]; then
        echo -e "Latest version:  ${GREEN}v${latest_version}${NC}"
        echo ""

        if [ "$SCRIPT_VERSION" = "$latest_version" ]; then
            log "You are running the latest version!"
            press_enter
            return
        fi

        echo -e "${YELLOW}Update available: v${SCRIPT_VERSION} → v${latest_version}${NC}"
        echo ""
    else
        warn "Could not check latest version (GitHub API)"
        echo ""
    fi

    if ! confirm "Download and install update?"; then
        return
    fi

    log "Downloading latest version..."
    if curl -fsSL "$repo_url" -o "$tmp_script"; then
        if head -1 "$tmp_script" | grep -q "^#!/bin/bash"; then
            # Extract version from downloaded script
            local new_version=$(grep -oP '^SCRIPT_VERSION="\K[^"]+' "$tmp_script" | head -1)

            chmod +x "$tmp_script"
            mv "$tmp_script" "$current_script"
            log "server-setup updated successfully!"
            if [ -n "$new_version" ]; then
                echo -e "Updated to: ${GREEN}v${new_version}${NC}"
            fi
            echo ""
            echo -e "${YELLOW}Restart server-setup to use the new version.${NC}"
            echo ""
            if confirm "Restart now?" "y"; then
                exec "$current_script"
            fi
        else
            rm -f "$tmp_script"
            warn "Downloaded file doesn't appear to be valid. Update aborted."
        fi
    else
        warn "Failed to download update. Check internet connection."
    fi

    press_enter
}

# ============================================
# Full Setup
# ============================================
run_full_setup() {
    require_root || return

    # Enable batch mode for first run (skips press_enter prompts)
    local first_run=0
    if [ ! -f "$MARKER_FILE" ]; then
        first_run=1
        export BATCH_MODE=1
    fi

    header "Full P16 GPU Server Setup"

    echo "This will run all configuration sections:"
    echo "  1. Display & Console (run first for 4K screens)"
    echo "  2. System Identity"
    echo "  3. Network & Firewall"
    echo "  4. System Updates"
    echo "  5. SSH Configuration"
    echo "  6. Lid Close Handling"
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

    # Run display first so 4K screens are readable
    run_display
    run_identity
    run_network
    run_updates
    run_ssh
    run_lid
    run_suspend
    run_nvidia
    run_docker
    run_performance
    run_management_tools

    # Disable batch mode
    export BATCH_MODE=0

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
    # Check if first run - auto-elevate to root
    if is_first_run; then
        if [[ $EUID -ne 0 ]]; then
            echo -e "${YELLOW}First-time setup requires root privileges. Elevating...${NC}"
            exec sudo "$0" "$@"
        fi
        run_full_setup
        exit 0
    fi

    # For normal operation, also auto-elevate if not root
    if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
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
