#!/bin/bash
#
# Create custom Ubuntu Server 24.04 autoinstall ISO
# Run this on a Linux machine with the required tools
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
UBUNTU_ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso"
UBUNTU_ISO="ubuntu-24.04.1-live-server-amd64.iso"
OUTPUT_ISO="ubuntu-24.04-p16-autoinstall.iso"
WORK_DIR="/tmp/p16-iso-build"

echo -e "${GREEN}P16 GPU Server - Custom ISO Builder${NC}"
echo ""

# Check dependencies
echo "Checking dependencies..."
for cmd in xorriso 7z mkpasswd; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Missing: $cmd${NC}"
        echo "Install with: sudo apt install xorriso p7zip-full whois"
        exit 1
    fi
done
echo -e "${GREEN}✓ Dependencies OK${NC}"
echo ""

# Get user credentials
echo -e "${YELLOW}Configure default user account:${NC}"
read -p "Hostname [gpu-server]: " HOSTNAME
HOSTNAME=${HOSTNAME:-gpu-server}

read -p "Username [admin]: " USERNAME
USERNAME=${USERNAME:-admin}

while true; do
    read -s -p "Password: " PASSWORD
    echo
    read -s -p "Confirm password: " PASSWORD2
    echo
    if [ "$PASSWORD" = "$PASSWORD2" ]; then
        break
    fi
    echo -e "${RED}Passwords don't match. Try again.${NC}"
done

# Hash password
echo "Hashing password..."
HASHED_PASSWORD=$(mkpasswd -m sha-512 "$PASSWORD")

echo ""
echo -e "${GREEN}Building ISO with:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  Username: $USERNAME"
echo ""

# Create work directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download Ubuntu ISO if needed
if [ ! -f "$UBUNTU_ISO" ]; then
    echo "Downloading Ubuntu Server 24.04..."
    wget -O "$UBUNTU_ISO" "$UBUNTU_ISO_URL"
fi

# Extract ISO
echo "Extracting ISO..."
7z x -o"$WORK_DIR/iso" "$UBUNTU_ISO"

# Download autoinstall.yaml template
echo "Downloading autoinstall configuration..."
curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/autoinstall.yaml \
    -o "$WORK_DIR/autoinstall.yaml"

# Customize autoinstall.yaml
echo "Customizing configuration..."
sed -i "s/hostname: gpu-server/hostname: $HOSTNAME/" "$WORK_DIR/autoinstall.yaml"
sed -i "s/username: admin/username: $USERNAME/" "$WORK_DIR/autoinstall.yaml"
sed -i "s|password: .*|password: \"$HASHED_PASSWORD\"|" "$WORK_DIR/autoinstall.yaml"

# Create directory structure for autoinstall
mkdir -p "$WORK_DIR/iso/nocloud"
cp "$WORK_DIR/autoinstall.yaml" "$WORK_DIR/iso/nocloud/user-data"
touch "$WORK_DIR/iso/nocloud/meta-data"

# Modify grub to autoinstall
echo "Configuring boot menu..."
cat > "$WORK_DIR/iso/boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0

menuentry "P16 GPU Server - Autoinstall" {
    set gfxpayload=keep
    linux   /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/nocloud/ ---
    initrd  /casper/initrd
}

menuentry "Ubuntu Server - Manual Install" {
    set gfxpayload=keep
    linux   /casper/vmlinuz ---
    initrd  /casper/initrd
}
EOF

# Rebuild ISO
echo "Building custom ISO..."
cd "$WORK_DIR/iso"
xorriso -as mkisofs \
    -r -V "P16_GPU_SERVER" \
    -o "$WORK_DIR/$OUTPUT_ISO" \
    -J -joliet-long \
    -b boot/grub/i386-pc/eltorito.img \
    -c boot/grub/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --grub2-boot-info --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot \
    -e EFI/boot/bootx64.efi \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    .

# Copy to current directory
echo ""
echo -e "${GREEN}✓ ISO created: $WORK_DIR/$OUTPUT_ISO${NC}"
echo ""
echo "To write to USB:"
echo "  sudo dd if=$WORK_DIR/$OUTPUT_ISO of=/dev/sdX bs=4M status=progress"
echo ""
echo "Or use Ventoy/Rufus to create a bootable USB."
