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

## Requirements

- Lenovo P16 with NVIDIA RTX 4090 Laptop GPU (16GB VRAM)
- Fresh Ubuntu Server 24.04 LTS minimal installation
- Internet connection
- Root/sudo access

## Quick Start

### 1. Install Ubuntu Server 24.04

Download Ubuntu Server 24.04 LTS from [ubuntu.com](https://ubuntu.com/download/server) and perform a minimal installation.

During installation:
- Choose "Ubuntu Server (minimized)"
- Set your hostname (e.g., `gpu-server-01`)
- Create your user account
- Enable OpenSSH server (optional - script will install it)

### 2. Run the Setup Script

After first boot, run:

```bash
# Option 1: Direct download and run
curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/setup.sh | sudo bash

# Option 2: Clone and run
git clone https://github.com/profzeller/p16-server-setup.git
cd p16-server-setup
sudo bash setup.sh
```

### 3. Reboot

The script will prompt you to reboot. After reboot, verify the setup:

```bash
test-gpu-setup
```

## Firewall Configuration

The script will prompt you to enter the IP addresses or networks that should be allowed to connect. You can enter multiple IPs/CIDRs:

```
Enter IP or network (or press Enter when done): 192.168.1.0/24
Added: 192.168.1.0/24
Enter IP or network (or press Enter when done): 10.0.0.5
Added: 10.0.0.5
Enter IP or network (or press Enter when done): [Enter]
```

**Allowed Ports:**

| Port | Service |
|------|---------|
| 22 | SSH |
| 8000 | vLLM (high-throughput LLM) |
| 11434 | Ollama (LLM) |
| 8100 | Chatterbox TTS |
| 8188 | ComfyUI Web UI |
| 8189 | ComfyUI API |
| 8200 | Video Server |

### Modifying Firewall Rules

To add additional IPs:

```bash
# Add another IP
sudo ufw allow from 1.2.3.4 to any port 22 proto tcp

# Add another subnet
sudo ufw allow from 10.0.0.0/8 to any port 22 proto tcp

# View current rules
sudo ufw status numbered

# Delete a rule
sudo ufw delete [rule_number]
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
# Quick system status
server-status

# Live GPU monitoring
gpu-monitor

# Verify setup configuration
test-gpu-setup
```

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

## Deploying AI Services

After setup, deploy any of these services:

### Text Generation (vLLM) - Recommended for batch content
```bash
git clone https://github.com/profzeller/local-vllm-server.git
cd local-vllm-server
docker compose up -d  # Uses Qwen 2.5 14B by default
```

### Text Generation (Ollama) - Simpler, good for dev
```bash
git clone https://github.com/profzeller/local-ollama-server.git
cd local-ollama-server
docker compose up -d
docker exec ollama ollama pull qwen2.5:14b
```

### Text-to-Speech (Chatterbox)
```bash
git clone https://github.com/profzeller/local-chatterbox-server.git
cd local-chatterbox-server
docker compose up -d
```

### Image Generation (ComfyUI)
```bash
git clone https://github.com/profzeller/local-comfyui-server.git
cd local-comfyui-server
mkdir -p models/checkpoints output input custom_nodes
# Download SDXL to models/checkpoints/
docker compose up -d
```

### Video Generation (Wan2.2)
```bash
git clone https://github.com/profzeller/local-video-server.git
cd local-video-server
docker compose up -d
```

## Static IP Configuration

After setup, configure a static IP by editing netplan:

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Example configuration:

```yaml
network:
  version: 2
  ethernets:
    enp0s31f6:  # Your interface name
      dhcp4: no
      addresses:
        - 203.0.113.10/24  # Your static IP
      routes:
        - to: default
          via: 203.0.113.1  # Your gateway
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Apply changes:

```bash
sudo netplan apply
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
- All service ports are firewall-restricted
- Root login is disabled (use sudo)
- Consider setting up SSH keys:

```bash
# On your local machine
ssh-copy-id user@gpu-server-ip

# Then disable password auth
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

## License

MIT License - Use freely for personal and commercial projects.
