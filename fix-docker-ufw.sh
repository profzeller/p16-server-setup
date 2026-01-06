#!/bin/bash
#
# Fix Docker UFW Integration
# Run on servers where Docker is bypassing UFW firewall rules
#
# Usage: curl -sSL https://raw.githubusercontent.com/profzeller/p16-server-setup/main/fix-docker-ufw.sh | sudo bash
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[FIX]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Must be root
[[ $EUID -ne 0 ]] && error "Run with sudo: curl -sSL ... | sudo bash"

AFTER_RULES="/etc/ufw/after.rules"
MARKER="# BEGIN DOCKER-USER UFW INTEGRATION"

log "Checking Docker UFW integration..."

# Check if already configured
if grep -q "$MARKER" "$AFTER_RULES" 2>/dev/null; then
    log "Docker UFW integration already in after.rules"
else
    log "Adding Docker UFW integration to $AFTER_RULES..."

    # Backup
    cp "$AFTER_RULES" "${AFTER_RULES}.backup.$(date +%Y%m%d%H%M%S)"

    # Add the integration
    cat >> "$AFTER_RULES" << 'EOFBLOCK'

# BEGIN DOCKER-USER UFW INTEGRATION
# Route Docker container traffic through UFW
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j RETURN
COMMIT
# END DOCKER-USER UFW INTEGRATION
EOFBLOCK

    log "Added Docker UFW integration"
fi

# Reload UFW
log "Reloading UFW..."
ufw reload

# Verify DOCKER-USER chain
log "Verifying DOCKER-USER chain..."
echo ""
iptables -L DOCKER-USER -n -v
echo ""

# Check if rules are present
if iptables -L DOCKER-USER -n | grep -q "ufw-user-forward"; then
    log "SUCCESS: Docker traffic now routes through UFW"
    echo ""
    echo -e "${GREEN}Firewall is now properly restricting Docker container access.${NC}"
    echo "Only IPs in /etc/gpu-server/allowed-ips.conf can access services."
else
    warn "DOCKER-USER chain may not be active. Try restarting Docker:"
    echo "  sudo systemctl restart docker"
    echo "  sudo ufw reload"
fi
