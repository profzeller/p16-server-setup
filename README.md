# Lenovo P16 GPU Server Setup

Automated setup script for configuring Lenovo P16 laptops (RTX 4090) as headless GPU servers running Ubuntu Server 24.04.

Perfect for creating a rack of AI inference servers for local development.

## What This Script Does

- **NVIDIA Drivers** - Installs driver 550 for RTX 4090 support
- **NVIDIA Container Toolkit** - Enables Docker GPU passthrough
- **Docker & Docker Compose** - Container runtime with GPU support
- **OpenSSH Server** - Remote access with security hardening
- **UFW Firewall** - Restricts access to specific IPs/subnets
- **Lid Close Handling** - Ignores lid close (safe to stack laptops)
- **OLED Burn-in Prevention** - Blanks console after 60 seconds
- **Large Console Font** - Terminus 32x16 for maximum visibility
- **Suspend/Hibernate Disabled** - Keeps server running 24/7
- **Performance Tuning** - GPU persistence, swap, kernel optimizations
- **Static IP Support** - Optional static IP configuration during setup

## Requirements

- Lenovo P16 with NVIDIA RTX 4090 Laptop GPU (16GB VRAM)
- Fresh Ubuntu Server 24.04 LTS minimal installation
- Internet connection
- Root/sudo access

## Installation Options

### Option A: Autoinstall ISO (Recommended for Multiple Machines)

Create a custom ISO that automatically installs Ubuntu and runs the setup script on first boot. Perfect for deploying multiple servers.

#### 1. Build the Custom ISO

On any Linux machine with the required tools:

```bash
# Install dependencies
sudo apt install xorriso p7zip-full whois

# Download and run the ISO builder
curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/create-iso.sh -o create-iso.sh
chmod +x create-iso.sh
./create-iso.sh
```

The script will prompt for:
- **Hostname** (e.g., `gpu-server-01`)
- **Username** (e.g., `admin`)
- **Password**

#### 2. Write to USB

```bash
# Find your USB device
lsblk

# Write ISO (replace sdX with your USB device)
sudo dd if=ubuntu-24.04-p16-autoinstall.iso of=/dev/sdX bs=4M status=progress
```

Or use [Ventoy](https://www.ventoy.net/) / [Rufus](https://rufus.ie/) to create a bootable USB.

#### 3. Boot and Install

1. Insert USB into P16 laptop
2. Boot from USB (F12 for boot menu on Lenovo)
3. Select "P16 GPU Server - Autoinstall"
4. Installation runs automatically (~10-15 minutes)
5. System reboots and runs setup script on first boot

#### 4. First Boot Configuration

On first boot, the setup script runs automatically and prompts for:

```
Firewall Configuration
Enter IP or network (or press Enter when done): 192.168.1.0/24
Added: 192.168.1.0/24
Enter IP or network (or press Enter when done): [Enter]

Network Configuration
  1) DHCP (automatic IP from router)
  2) Static IP (manual configuration)
Select network mode [1]: 2

Static IP address: 192.168.1.100
Subnet mask in CIDR [24]: 24
Gateway: 192.168.1.1
DNS server 1 [8.8.8.8]:
DNS server 2 [8.8.4.4]:
```

After setup completes, the system reboots and is ready to use.

---

### Option B: Manual Installation

For single machines or when you already have Ubuntu installed.

#### 1. Install Ubuntu Server 24.04

Download Ubuntu Server 24.04 LTS from [ubuntu.com](https://ubuntu.com/download/server) and perform a minimal installation.

During installation:
- Choose "Ubuntu Server (minimized)"
- Set your hostname (e.g., `gpu-server-01`)
- Create your user account
- Enable OpenSSH server

#### 2. Run the Setup Script

After first boot, run:

```bash
# Direct download and run
curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/setup.sh | sudo bash

# Or clone and run
git clone https://github.com/profzeller/p16-server-setup.git
cd p16-server-setup
sudo bash setup.sh
```

#### 3. Reboot

The script will prompt you to reboot. After reboot, verify the setup:

```bash
test-gpu-setup
```

## Firewall Configuration

The setup script prompts for allowed IP addresses/networks. Only **SSH (port 22)** is opened by default.

**Service ports are opened individually** when you install services via `install-service`. This keeps your firewall secure by only opening ports you actually need.

### Firewall Prompts During Setup

```
Firewall Configuration

Enter the IP addresses or networks that should be allowed to connect.
Examples: 192.168.1.0/24, 10.0.0.5, 203.0.113.0/24

Enter IP or network (or press Enter when done): 192.168.1.0/24
Added: 192.168.1.0/24
Enter IP or network (or press Enter when done): 10.0.0.5
Added: 10.0.0.5
Enter IP or network (or press Enter when done): [Enter]
```

### Firewall Prompts When Installing Services

When you run `install-service` and select a service:

```
✓ vLLM installed and started!

Firewall Configuration
This service runs on port 8000

Open port 8000 in firewall? (y/n) [y]: y
Opening port 8000 for allowed IPs...
  Adding rule for 192.168.1.0/24...
  Adding rule for 10.0.0.5...
✓ Firewall updated
```

### Available Service Ports

| Port | Service |
|------|---------|
| 22 | SSH (opened by default) |
| 8000 | vLLM |
| 11434 | Ollama |
| 8100 | Chatterbox TTS |
| 8188 | ComfyUI Web UI |
| 8189 | ComfyUI API |
| 8200 | Video Server |

### Modifying Firewall Rules

```bash
# View current rules
sudo ufw status numbered

# Add another IP for a port
sudo ufw allow from 1.2.3.4 to any port 8000 proto tcp

# Delete a rule
sudo ufw delete [rule_number]
```

## Network Configuration

The setup script prompts for DHCP or Static IP:

```
Network Configuration

  1) DHCP (automatic IP from router)
  2) Static IP (manual configuration)

Select network mode [1]:
```

If you choose Static IP, you'll be prompted for:
- Network interface (auto-detected)
- Static IP address
- Subnet mask (CIDR notation)
- Gateway
- DNS servers

The static IP is configured via netplan and takes effect after reboot.

### Changing Network Settings Later

```bash
# Edit netplan configuration
sudo nano /etc/netplan/00-static-config.yaml

# Apply changes
sudo netplan apply
```

## Lid Close & Stacking

The script configures the laptop to:

- **Ignore lid close** - Closing the lid won't suspend the system
- **Disable suspend/hibernate** - System stays running 24/7
- **Blank console** - Screen turns off after 60 seconds (OLED protection)

You can safely:
- Close the laptop lid
- Stack multiple laptops in a rack
- Run them headless indefinitely

## Management Commands

After setup, these commands are available:

```bash
# Show all available commands
server-commands

# Install AI services (interactive menu)
install-service

# Quick system status
server-status

# Live GPU monitoring
gpu-monitor

# Verify setup configuration
test-gpu-setup
```

### Installing AI Services

Run `install-service` to get an interactive menu:

```
╔═══════════════════════════════════════════════════════════╗
║            GPU Service Installer                          ║
║            Lenovo P16 GPU Server                          ║
╚═══════════════════════════════════════════════════════════╝

Available Services:

  1) Ollama               [Running]
     Local LLM inference (simpler, good for dev)
     Port: 11434

  2) vLLM
     High-throughput LLM inference (2-4x faster for batch)
     Port: 8000

  3) Chatterbox TTS
     Text-to-speech voice generation
     Port: 8100

  4) ComfyUI
     Image generation with SDXL
     Port: 8188

  5) Video Server
     Wan2.2 text-to-video and image-to-video
     Port: 8200

  6) List running services
  7) Stop all services
  0) Exit

Select an option:
```

Services are installed to `/opt/gpu-services/` and started automatically. Firewall ports are opened per-service when you install them.

### Example Output: `server-status`

```
=== GPU Status ===
GPU: NVIDIA RTX 4090 Laptop GPU | Temp: 45°C | Util: 0% | VRAM: 512/16384 MB

=== Docker Containers ===
NAMES        STATUS         PORTS
ollama       Up 2 hours     0.0.0.0:11434->11434/tcp
chatterbox   Up 2 hours     0.0.0.0:8100->8100/tcp

=== System Resources ===
RAM: 8.2G used / 64G total
Disk: 45G used / 500G total (10%)

=== Network ===
IP: 192.168.1.100
Firewall: Status: active
```

## Troubleshooting

### GPU not detected after reboot

```bash
# Check NVIDIA driver status
nvidia-smi

# If not working, reinstall driver
sudo apt install --reinstall nvidia-driver-550

# Reboot
sudo reboot
```

### Docker can't access GPU

```bash
# Reconfigure NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Test
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

### Can't connect via SSH

```bash
# Check if SSH is running
sudo systemctl status ssh

# Check firewall rules
sudo ufw status verbose

# Temporarily allow all SSH (for debugging)
sudo ufw allow 22/tcp
```

### System suspends when lid closed

```bash
# Verify logind config
cat /etc/systemd/logind.conf.d/lid.conf

# Should show:
# HandleLidSwitch=ignore
# HandleLidSwitchExternalPower=ignore
# HandleLidSwitchDocked=ignore

# Restart logind
sudo systemctl restart systemd-logind
```

### OLED screen still on

```bash
# Check console blank setting
cat /sys/module/kernel/parameters/consoleblank

# Manually blank now
sudo setterm --blank 1 --powerdown 2

# Force blank
sudo sh -c 'echo 1 > /sys/module/kernel/parameters/consoleblank'
```

## Hardware Notes

### Lenovo P16 Specs (typical)

- **GPU**: NVIDIA RTX 4090 Laptop (16GB GDDR6)
- **CPU**: Intel Core i9-13980HX or similar
- **RAM**: 32-64GB DDR5
- **Storage**: 1-2TB NVMe SSD

### Thermal Considerations

When stacking laptops:
- Ensure adequate ventilation between units
- Consider a rack with spacing or fans
- Monitor GPU temperatures: `nvidia-smi -l 1`
- Target: Keep GPU below 80°C under load

### Power Consumption

- Idle: ~30-50W
- GPU Load: ~150-200W
- Use appropriate power strips/UPS

## Security Notes

- SSH is restricted to specific IPs only
- Service ports are only opened when you install the service
- Root login is disabled (use sudo)
- Consider setting up SSH keys:

```bash
# On your local machine
ssh-copy-id user@gpu-server-ip

# Then disable password auth
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

## File Structure

```
p16-server-setup/
├── setup.sh              # Main setup script
├── install-service.sh    # Service installer (downloaded during setup)
├── autoinstall.yaml      # Cloud-init autoinstall config
├── create-iso.sh         # Custom ISO builder script
├── README.md
└── LICENSE
```

## License

MIT License - Use freely for personal and commercial projects.
