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

log "Fixing Docker UFW integration..."

# Step 1: Remove any broken previous attempts
if grep -q "$MARKER" "$AFTER_RULES" 2>/dev/null; then
    log "Removing previous Docker UFW integration..."
    sed -i '/# BEGIN DOCKER-USER/,/# END DOCKER-USER/d' "$AFTER_RULES"
fi

# Step 2: Ensure UFW forward policy allows us to create forward rules
log "Checking UFW forward policy..."
if grep -q 'DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
    log "Enabling UFW forward policy..."
    sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi

# Step 3: Backup after.rules
cp "$AFTER_RULES" "${AFTER_RULES}.backup.$(date +%Y%m%d%H%M%S)"

# Step 4: Build the allowed IPs list
ALLOWED_IPS_FILE="/etc/gpu-server/allowed-ips.conf"
ALLOWED_RULES=""

if [[ -f "$ALLOWED_IPS_FILE" ]]; then
    log "Reading allowed IPs from $ALLOWED_IPS_FILE..."
    while IFS= read -r ip || [[ -n "$ip" ]]; do
        # Skip comments and empty lines
        [[ -z "$ip" || "$ip" =~ ^# ]] && continue
        ip=$(echo "$ip" | xargs)  # trim whitespace
        [[ -n "$ip" ]] && ALLOWED_RULES="${ALLOWED_RULES}-A FILTERS -s ${ip} -j RETURN
"
        log "  Allowing: $ip"
    done < "$ALLOWED_IPS_FILE"
else
    warn "No $ALLOWED_IPS_FILE found - only private networks will be allowed"
fi

# Step 5: Add Docker integration that creates its own chain
log "Adding Docker UFW integration..."
cat >> "$AFTER_RULES" << EOFBLOCK

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

# Allow from configured IPs (from /etc/gpu-server/allowed-ips.conf)
${ALLOWED_RULES}
# Allow if coming from docker networks (internal container communication)
-A FILTERS -i docker0 -j RETURN
-A FILTERS -i br- -j RETURN

# Default: drop everything else to containers
-A FILTERS -j DROP

-A DOCKER-USER -j RETURN
COMMIT
# END DOCKER-USER UFW INTEGRATION
EOFBLOCK

log "Docker UFW integration added"

# Step 6: Reload UFW
log "Reloading UFW..."
if ! ufw reload 2>&1; then
    error "UFW reload failed. Check /etc/ufw/after.rules for syntax errors"
fi

# Step 7: Restart Docker to pick up new iptables rules
log "Restarting Docker..."
systemctl restart docker

# Step 8: Verify
log "Verifying DOCKER-USER chain..."
echo ""
iptables -L DOCKER-USER -n -v 2>/dev/null || true
echo ""
iptables -L FILTERS -n -v 2>/dev/null || true
echo ""

if iptables -L DOCKER-USER -n 2>/dev/null | grep -q "FILTERS"; then
    log "SUCCESS: Docker traffic is now filtered"
    echo ""
    echo -e "${GREEN}Container access is now restricted to:${NC}"
    echo "  - Private networks (192.168.x.x, 10.x.x.x, 172.16.x.x)"
    if [[ -f "$ALLOWED_IPS_FILE" ]]; then
        echo "  - IPs from $ALLOWED_IPS_FILE"
    fi
    echo "  - Docker internal networks"
    echo ""
else
    warn "Verification incomplete. Check iptables -L DOCKER-USER -n -v"
fi
