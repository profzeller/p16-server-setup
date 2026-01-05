#!/bin/bash
#
# GPU Service Installer
# Installs AI services from GitHub repos with a simple menu
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Service definitions
declare -A SERVICES
SERVICES=(
    ["1,name"]="Ollama"
    ["1,desc"]="Local LLM inference (simpler, good for dev)"
    ["1,repo"]="https://github.com/profzeller/local-ollama-server.git"
    ["1,port"]="11434"
    ["1,dir"]="local-ollama-server"

    ["2,name"]="vLLM"
    ["2,desc"]="High-throughput LLM inference (2-4x faster for batch)"
    ["2,repo"]="https://github.com/profzeller/local-vllm-server.git"
    ["2,port"]="8000"
    ["2,dir"]="local-vllm-server"

    ["3,name"]="Chatterbox TTS"
    ["3,desc"]="Text-to-speech voice generation"
    ["3,repo"]="https://github.com/profzeller/local-chatterbox-server.git"
    ["3,port"]="8100"
    ["3,dir"]="local-chatterbox-server"

    ["4,name"]="ComfyUI"
    ["4,desc"]="Image generation with SDXL"
    ["4,repo"]="https://github.com/profzeller/local-comfyui-server.git"
    ["4,port"]="8188"
    ["4,dir"]="local-comfyui-server"

    ["5,name"]="Video Server"
    ["5,desc"]="Wan2.2 text-to-video and image-to-video"
    ["5,repo"]="https://github.com/profzeller/local-video-server.git"
    ["5,port"]="8200"
    ["5,dir"]="local-video-server"
)

INSTALL_DIR="/opt/gpu-services"

show_header() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}            ${CYAN}GPU Service Installer${NC}                          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}            Lenovo P16 GPU Server                          ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_menu() {
    echo -e "${YELLOW}Available Services:${NC}"
    echo ""
    for i in 1 2 3 4 5; do
        local name="${SERVICES[$i,name]}"
        local desc="${SERVICES[$i,desc]}"
        local port="${SERVICES[$i,port]}"
        local dir="${SERVICES[$i,dir]}"

        # Check if already installed
        local status=""
        if [ -d "$INSTALL_DIR/$dir" ]; then
            # Check if running
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${dir%%-server}"; then
                status="${GREEN}[Running]${NC}"
            else
                status="${YELLOW}[Installed]${NC}"
            fi
        fi

        printf "  ${CYAN}%d)${NC} %-20s ${status}\n" "$i" "$name"
        printf "     ${NC}%s\n" "$desc"
        printf "     Port: %s\n\n" "$port"
    done

    echo -e "  ${CYAN}6)${NC} List running services"
    echo -e "  ${CYAN}7)${NC} Stop all services"
    echo -e "  ${CYAN}0)${NC} Exit"
    echo ""
}

install_service() {
    local choice=$1
    local name="${SERVICES[$choice,name]}"
    local repo="${SERVICES[$choice,repo]}"
    local dir="${SERVICES[$choice,dir]}"
    local port="${SERVICES[$choice,port]}"

    echo ""
    echo -e "${BLUE}Installing $name...${NC}"
    echo ""

    # Create install directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Check if already cloned
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}Directory exists. Updating...${NC}"
        cd "$dir"
        git pull
    else
        echo -e "${GREEN}Cloning repository...${NC}"
        git clone "$repo"
        cd "$dir"
    fi

    # Special handling for ComfyUI (needs model directories)
    if [ "$choice" = "4" ]; then
        echo -e "${YELLOW}Creating ComfyUI directories...${NC}"
        mkdir -p models/checkpoints output input custom_nodes
        echo ""
        echo -e "${YELLOW}NOTE: Download SDXL model to $INSTALL_DIR/$dir/models/checkpoints/${NC}"
    fi

    # Start the service
    echo ""
    echo -e "${GREEN}Starting $name...${NC}"
    docker compose up -d

    echo ""
    echo -e "${GREEN}✓ $name installed and started!${NC}"
    echo -e "  Access at: ${CYAN}http://$(hostname -I | awk '{print $1}'):$port${NC}"
    echo ""

    read -p "Press Enter to continue..."
}

stop_service() {
    local choice=$1
    local name="${SERVICES[$choice,name]}"
    local dir="${SERVICES[$choice,dir]}"

    if [ -d "$INSTALL_DIR/$dir" ]; then
        echo -e "${YELLOW}Stopping $name...${NC}"
        cd "$INSTALL_DIR/$dir"
        docker compose down
        echo -e "${GREEN}✓ $name stopped${NC}"
    else
        echo -e "${RED}$name is not installed${NC}"
    fi

    read -p "Press Enter to continue..."
}

list_services() {
    echo ""
    echo -e "${BLUE}Running GPU Services:${NC}"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAME|ollama|vllm|chatterbox|comfyui|video)" || echo "No GPU services running"
    echo ""
    echo -e "${BLUE}GPU Status:${NC}"
    nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | \
        awk -F',' '{printf "  %s | Temp: %s°C | Util: %s%% | VRAM: %s/%s MB\n", $1, $2, $3, $4, $5}' || echo "  GPU not available"
    echo ""
    read -p "Press Enter to continue..."
}

stop_all() {
    echo ""
    echo -e "${YELLOW}Stopping all GPU services...${NC}"

    for i in 1 2 3 4 5; do
        local dir="${SERVICES[$i,dir]}"
        if [ -d "$INSTALL_DIR/$dir" ]; then
            echo "  Stopping ${SERVICES[$i,name]}..."
            cd "$INSTALL_DIR/$dir"
            docker compose down 2>/dev/null
        fi
    done

    echo ""
    echo -e "${GREEN}✓ All services stopped${NC}"
    read -p "Press Enter to continue..."
}

# Main loop
while true; do
    show_header
    show_menu

    read -p "Select an option: " choice

    case $choice in
        1|2|3|4|5)
            install_service "$choice"
            ;;
        6)
            list_services
            ;;
        7)
            stop_all
            ;;
        0)
            echo ""
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            ;;
    esac
done
