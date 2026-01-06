# Lenovo P16 GPU Server Setup

Interactive terminal utility for configuring and managing Lenovo P16 laptops (RTX 4090) as headless GPU servers running Ubuntu Server 24.04.

Perfect for creating a rack of AI inference servers for local development.

## Related Repositories

This project is part of the P16 GPU Server ecosystem:

| Repository | Description | Port |
|------------|-------------|------|
| [p16-server-setup](https://github.com/profzeller/p16-server-setup) | Main setup utility (this repo) | - |
| [p16-iso-builder](https://github.com/profzeller/p16-iso-builder) | Create custom Ubuntu ISOs for automated deployment | - |
| [p16-agent](https://github.com/profzeller/p16-agent) | Metrics collection agent for remote monitoring | 9100 |
| [p16-monitor](https://github.com/profzeller/p16-monitor) | Web dashboard for monitoring all GPU servers | 7000 |
| [local-ollama-server](https://github.com/profzeller/local-ollama-server) | LLM inference with Ollama (simple, good for dev) | 11434 |
| [local-vllm-server](https://github.com/profzeller/local-vllm-server) | High-throughput LLM inference with vLLM | 8000 |
| [local-chatterbox-server](https://github.com/profzeller/local-chatterbox-server) | Text-to-speech with voice cloning | 8100 |
| [local-comfyui-server](https://github.com/profzeller/local-comfyui-server) | Image generation with SDXL/ComfyUI | 8188 |
| [local-video-server](https://github.com/profzeller/local-video-server) | Video generation with Wan2.1 | 8200 |

All AI services are installable directly from the server-setup menu (option 8).
P16 Agent is installable from Tools & Monitoring menu (option 6).

## Features

- **Interactive Menu System** - Full TUI for setup and management
- **First-Run Detection** - Automatic full setup on fresh install
- **Re-runnable Sections** - Modify any configuration anytime
- **Auto-boot to Menu** - Server boots directly into management interface
- **AI Service Management** - Install/manage Ollama, vLLM, ComfyUI, etc.
- **NVIDIA Version Selection** - Choose driver version (550/560/570)
- **Status Indicators** - See current configuration at a glance

## What Gets Configured

- **System Identity** - Hostname, username, password
- **NVIDIA Drivers** - Driver 550/560/570 with version selection
- **NVIDIA Container Toolkit** - Docker GPU passthrough
- **Docker & Compose** - Container runtime with GPU support
- **OpenSSH Server** - Remote access with security hardening
- **UFW Firewall** - IP-restricted access, per-service ports
- **Lid Close Handling** - Ignores lid close (safe to stack)
- **OLED Burn-in Prevention** - Console blanking after 60 seconds
- **Large Console Font** - Terminus 32x16 for visibility
- **Suspend/Hibernate Disabled** - 24/7 operation
- **Performance Tuning** - GPU persistence, swap, kernel optimizations
- **Static IP Support** - Optional static IP configuration

## Requirements

- Lenovo P16 with NVIDIA RTX 4090 Laptop GPU (16GB VRAM)
- Fresh Ubuntu Server 24.04 LTS minimal installation
- Internet connection
- Root/sudo access

## Quick Start

### First-Time Setup

```bash
# Download and run
curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/setup.sh | sudo bash
```

The script will:
1. Prompt for system identity (hostname, username, password)
2. Prompt for allowed firewall IPs
3. Prompt for DHCP or static IP
4. Install and configure everything automatically
5. Reboot into the management menu

### After Setup

The server automatically boots into the management menu:

```
╔═══════════════════════════════════════════════════════════╗
║         P16 GPU Server Setup                              ║
║         gpu-server-01 - 192.168.1.100                     ║
╚═══════════════════════════════════════════════════════════╝

  1) System Identity      [gpu-server-01 / admin]
  2) Network & Firewall   [Static: 192.168.1.100]
  3) NVIDIA Stack         [Driver: 550.54.14]
  4) Docker               [Version: 24.0.7]
  5) System Settings  →
  6) Performance Tuning
  7) Management Tools
  8) AI Services      →
  9) Tools & Monitoring →

  F) Run Full Setup
  S) Drop to Shell
  0) Exit / Logout
```

## Menu Structure

### Main Menu

| Option | Description |
|--------|-------------|
| 1 | Change hostname, username, or password |
| 2 | Configure firewall IPs and DHCP/static IP |
| 3 | Install/upgrade NVIDIA drivers (550/560/570) |
| 4 | Install or reinstall Docker |
| 5 | System Settings sub-menu |
| 6 | Configure GPU persistence, swap, kernel params |
| 7 | Install helper scripts |
| 8 | AI Services sub-menu |
| 9 | Tools & Monitoring sub-menu |
| F | Run complete setup (all sections) |
| S | Drop to command line shell |
| 0 | Exit / Logout |

### System Settings Sub-menu

```
  1) System Updates       - Update/upgrade packages
  2) OpenSSH Server       - Configure SSH security
  3) Lid Close Handling   - Set lid close behavior
  4) Display & OLED       - Console font and blanking
  5) Suspend/Hibernate    - Disable sleep modes
  6) Run All System Settings
```

### AI Services Sub-menu

```
  1) Ollama               [Running :11434]
  2) vLLM                 [Not installed]
  3) Chatterbox TTS       [Not installed]
  4) ComfyUI              [Not installed]
  5) Video Server         [Not installed]

  6) List running services
  7) Stop all services
```

Each service shows options to start/stop/update/reinstall when selected.

**Service Management Options:**
```
Service already installed.

Options:
  1) Start service
  2) Stop service
  3) Configure model
  4) Update (git pull)
  5) Reinstall
  0) Cancel
```

### ComfyUI Model Presets

ComfyUI includes a preset system for quick model setup:

```
ComfyUI Presets:

  1) Photorealistic (Gemini Flash-like)
     - Juggernaut XL v9 (6.5GB)
     - SDXL VAE + 4x-UltraSharp upscaler

  2) Versatile (Multi-style)
     - SDXL Base + DreamShaper XL (~14GB)
     - Good for photos, art, illustrations, abstracts

  3) Fast & Good (SDXL Turbo)
     - SDXL Turbo (6.9GB)
     - 1-4 step generation

  4) Lightweight (SD 1.5)
     - Realistic Vision v5.1 (2GB)
     - Works on 4GB VRAM
```

**Versatile Preset Style Guides:**

| Style | Model | CFG | Prompt Tips |
|-------|-------|-----|-------------|
| Photorealistic | SDXL Base | 5 | photography, natural lighting, 8k |
| Artistic | DreamShaper | 4 | artistic, creative, beautiful |
| Illustration | DreamShaper | 5 | digital illustration, clean lines |
| Abstract | DreamShaper | 3 | abstract art, geometric, vibrant |
| Infographic | SDXL Base | 6 | flat design, icons, diagram |
| 3D Render | SDXL Base | 5 | octane render, smooth lighting |

### vLLM Model Configuration

Select from optimized models for your VRAM:

```
Recommended models for 16GB VRAM:
  1) mistralai/Mistral-7B-Instruct-v0.3 (7B, fast)
  2) Qwen/Qwen2.5-7B-Instruct (7B, multilingual)
  3) meta-llama/Llama-3.2-3B-Instruct (3B, very fast)
  4) microsoft/Phi-3-mini-4k-instruct (3.8B, efficient)

For 24GB+ VRAM:
  5) Qwen/Qwen2.5-14B-Instruct (14B, best quality)
  6) meta-llama/Llama-3.1-8B-Instruct (8B)
```

### Tools & Monitoring Sub-menu

```
  1) Server Status        - GPU, containers, resources overview
  2) GPU Monitor          - Live nvidia-smi (Ctrl+C to exit)
  3) Test Setup           - Verify configuration
  4) View Container Logs  - Select container to tail logs
  5) System Info          - Detailed hardware info
  6) P16 Agent            - Install metrics agent for remote monitoring
  7) Update server-setup  - Download latest version from GitHub
```

### Self-Update Feature

Update to the latest version directly from the menu:

```
Tools & Monitoring → 7) Update server-setup

Downloading latest version...
server-setup updated successfully!

Restart server-setup to use the new version.
Restart now? (Y/n):
```

## NVIDIA Driver Selection

When configuring NVIDIA, you can choose your driver version:

```
Current NVIDIA driver: 550.54.14

Options:
  1) Keep current (550.54.14)
  2) Reinstall driver 550
  3) Upgrade to driver 560
  4) Upgrade to driver 570 (latest)
  5) Custom version
  0) Cancel

Note: vLLM recommends driver 550+ for best compatibility
```

## Confirmation Prompts

Sections that modify existing configuration show a confirmation:

```
Current hostname: gpu-server-01
Current user: admin

This will modify system identity. Continue? (y/N):
```

## Service Ports

| Port | Service |
|------|---------|
| 22 | SSH (opened by default) |
| 8000 | vLLM |
| 8100 | Chatterbox TTS |
| 8188 | ComfyUI Web UI |
| 8200 | Video Server |
| 9100 | P16 Agent (monitoring) |
| 11434 | Ollama |

Firewall ports are opened per-service when you install them.

## Drop to Shell

Press `S` from the main menu to drop to a command line:

```
Dropping to shell...

Type 'server-setup' to return to the menu.
Type 'exit' to logout.
```

## Installation Options

### Option A: Autoinstall ISO (Multiple Machines)

Create a custom ISO for automated deployment:

```bash
# On a Linux machine
sudo apt install xorriso p7zip-full whois

curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/create-iso.sh -o create-iso.sh
chmod +x create-iso.sh
./create-iso.sh
```

The ISO prompts for hostname/username/password during creation, then boots into automatic installation.

### Option B: Manual Installation

```bash
# After installing Ubuntu Server 24.04
curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/setup.sh | sudo bash
```

## File Locations

| Path | Description |
|------|-------------|
| `/usr/local/bin/server-setup` | Main utility command |
| `/etc/gpu-server/` | Configuration directory |
| `/etc/gpu-server/.setup-complete` | First-run marker file |
| `/etc/gpu-server/allowed-ips.conf` | Firewall allowed IPs |
| `/opt/gpu-services/` | Installed AI services |
| `/etc/profile.d/server-setup.sh` | Auto-boot configuration |

## Commands

After setup, these commands are available:

```bash
server-setup       # Main interactive menu
server-status      # Quick system overview
gpu-monitor        # Live GPU monitoring
test-gpu-setup     # Verify configuration
server-commands    # List available commands
```

## Troubleshooting

### Menu doesn't appear on login

```bash
# Check auto-boot config
cat /etc/profile.d/server-setup.sh

# Manually run
server-setup
```

### GPU not detected after reboot

```bash
# From shell (press S in menu)
nvidia-smi

# If not working, use menu option 3 (NVIDIA Stack) to reinstall
sudo server-setup
```

### Can't connect via SSH

```bash
# Check firewall
sudo ufw status verbose

# Add your IP via menu option 2 (Network & Firewall)
```

### Service won't start

```bash
# Check Docker
docker ps -a

# View logs via menu option 9 → 4 (View Container Logs)
```

## Hardware Notes

### Lenovo P16 Specs

- **GPU**: NVIDIA RTX 4090 Laptop (16GB GDDR6)
- **CPU**: Intel Core i9-13980HX or similar
- **RAM**: 32-64GB DDR5
- **Storage**: 1-2TB NVMe SSD

### Thermal Considerations

- Ensure adequate ventilation between stacked units
- Monitor GPU temps: use menu option 9 → 2 (GPU Monitor)
- Target: Keep GPU below 80°C under load

### Power

- Idle: ~30-50W
- GPU Load: ~150-200W

## Security

- SSH restricted to configured IPs only
- Service ports opened only when installing services
- Root login disabled (use sudo)
- Passwords required with confirmation
- **Docker UFW Integration** - Container traffic routed through firewall

### Docker UFW Integration

By default, Docker bypasses UFW by manipulating iptables directly. This setup configures the `DOCKER-USER` chain to route container traffic through UFW rules, ensuring your firewall configuration is respected.

```bash
# Configured in /etc/ufw/after.rules:
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j RETURN
COMMIT
```

This means AI service ports (8000, 11434, 8188, etc.) are properly restricted to your allowed IPs.

## License

MIT License - Use freely for personal and commercial projects.
