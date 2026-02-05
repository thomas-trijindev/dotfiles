#!/bin/bash
# UFW Configuration Script for CachyOS + Docker + Tailscale
# Dynamic network detection - no hardcoded IP addresses

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Function to detect network configuration
detect_networks() {
    print_header "Detecting Network Configuration"
    
    # Detect primary interface and LAN network
    PRIMARY_IF=$(ip route get 8.8.8.8 2>/dev/null | head -1 | awk '{print $5}' || echo "")
    if [ -n "$PRIMARY_IF" ]; then
        LOCAL_IP=$(ip addr show "$PRIMARY_IF" | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
        if [ -n "$LOCAL_IP" ]; then
            # Extract network from IP/CIDR
            LOCAL_NETWORK=$(echo "$LOCAL_IP" | sed 's/\.[0-9]*\//.0\//')
            print_status "Primary interface: $PRIMARY_IF"
            print_status "Local IP: $LOCAL_IP"
            print_status "Local network: $LOCAL_NETWORK"
        else
            print_error "Could not detect local IP address"
            exit 1
        fi
    else
        print_error "Could not detect primary network interface"
        exit 1
    fi
    
    # Detect Tailscale configuration
    TAILSCALE_IP=""
    if command -v tailscale >/dev/null 2>&1; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
        if [ -n "$TAILSCALE_IP" ]; then
            print_status "Tailscale IP: $TAILSCALE_IP (bypasses UFW)"
        else
            print_warning "Tailscale installed but not connected"
        fi
    else
        print_warning "Tailscale not installed"
    fi
    
    # Detect Docker configuration
    DOCKER_BRIDGE=""
    DOCKER_NETWORKS=()
    if command -v docker >/dev/null 2>&1 && systemctl is-active docker >/dev/null 2>&1; then
        # Default Docker bridge
        DOCKER_BRIDGE=$(ip addr show docker0 2>/dev/null | grep -E 'inet [0-9]' | awk '{print $2}' | head -1 || echo "")
        if [ -n "$DOCKER_BRIDGE" ]; then
            # Convert bridge IP to network (e.g., 172.17.0.1/16 -> 172.17.0.0/16)
            DOCKER_NETWORK=$(echo "$DOCKER_BRIDGE" | sed 's/\.[0-9]*\//.0\//')
            print_status "Docker bridge: $DOCKER_BRIDGE"
            print_status "Docker network: $DOCKER_NETWORK"
        fi
        
        # Check for custom Docker networks
        if command -v jq >/dev/null 2>&1; then
            CUSTOM_NETWORKS=$(docker network ls --format json 2>/dev/null | jq -r 'select(.Name != "bridge" and .Name != "host" and .Name != "none") | .Name' | head -5)
            for net in $CUSTOM_NETWORKS; do
                NET_SUBNET=$(docker network inspect "$net" 2>/dev/null | jq -r '.[0].IPAM.Config[]?.Subnet // empty' | head -1)
                if [ -n "$NET_SUBNET" ]; then
                    DOCKER_NETWORKS+=("$NET_SUBNET")
                    print_status "Custom Docker network '$net': $NET_SUBNET"
                fi
            done
        fi
    else
        print_warning "Docker not installed or not running"
    fi
    
    echo
}

# Function to validate detected networks
validate_networks() {
    print_header "Validating Network Configuration"
    
    # Validate local network is private (RFC1918)
    if [[ "$LOCAL_NETWORK" =~ ^192\.168\. ]] || [[ "$LOCAL_NETWORK" =~ ^10\. ]] || [[ "$LOCAL_NETWORK" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
        print_status "Local network is RFC1918 private: $LOCAL_NETWORK"
    else
        print_warning "Local network appears to be public: $LOCAL_NETWORK"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check for network conflicts
    if [ -n "$DOCKER_NETWORK" ] && [ "$LOCAL_NETWORK" = "$DOCKER_NETWORK" ]; then
        print_error "Network conflict: Local and Docker networks overlap ($LOCAL_NETWORK)"
        exit 1
    fi
    
    echo
}

print_header "UFW Configuration Script - Dynamic Network Detection"
print_status "Detecting your network configuration automatically..."
echo

# Run network detection
detect_networks
validate_networks

# Confirmation prompt
print_header "Configuration Summary"
echo "The following UFW rules will be configured:"
echo "• Local network access: $LOCAL_NETWORK"
[ -n "$DOCKER_NETWORK" ] && echo "• Docker network access: $DOCKER_NETWORK"
for docker_net in "${DOCKER_NETWORKS[@]}"; do
    echo "• Custom Docker network: $docker_net"
done
echo "• SSH access with rate limiting"
echo "• Development ports (3000-8999) from local networks"
[ -n "$TAILSCALE_IP" ] && echo "• Tailscale traffic ($TAILSCALE_IP) will bypass UFW"
echo

read -p "Proceed with UFW configuration? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    print_status "Configuration cancelled by user"
    exit 0
fi

# Check current status
print_header "Current UFW Status"
sudo ufw status verbose
echo

# Backup current configuration
print_status "Creating backup of current UFW configuration..."
BACKUP_DIR="/etc/ufw/backup-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo cp -r /etc/ufw/*.rules "$BACKUP_DIR/" 2>/dev/null || true
print_status "Backup created in $BACKUP_DIR"
echo

# Reset UFW to clean state
print_status "Resetting UFW to clean state..."
sudo ufw --force reset

# Set secure defaults
print_status "Setting secure default policies..."
sudo ufw default deny incoming
sudo ufw default allow outgoing  
sudo ufw default deny forward

# Essential SSH access with rate limiting
print_status "Configuring SSH access with rate limiting..."
sudo ufw allow ssh comment 'SSH access'
sudo ufw limit ssh comment 'SSH rate limiting (max 6 attempts/min)'

# Local network access
print_status "Allowing local network access ($LOCAL_NETWORK)..."
sudo ufw allow from "$LOCAL_NETWORK" comment 'Local LAN'

# Docker network access
if [ -n "$DOCKER_NETWORK" ]; then
    print_status "Allowing Docker bridge network ($DOCKER_NETWORK)..."
    sudo ufw allow from "$DOCKER_NETWORK" comment 'Docker bridge network'
fi

# Custom Docker networks
for docker_net in "${DOCKER_NETWORKS[@]}"; do
    print_status "Allowing custom Docker network ($docker_net)..."
    sudo ufw allow from "$docker_net" comment "Docker network: $docker_net"
done

# Development servers - accessible from local networks
print_status "Configuring development server ports..."
sudo ufw allow from "$LOCAL_NETWORK" to any port 3000:8999 proto tcp comment 'Dev servers from LAN'

if [ -n "$DOCKER_NETWORK" ]; then
    sudo ufw allow from "$DOCKER_NETWORK" to any port 3000:8999 proto tcp comment 'Dev servers from Docker'
fi

# Additional Docker networks for dev servers
for docker_net in "${DOCKER_NETWORKS[@]}"; do
    sudo ufw allow from "$docker_net" to any port 3000:8999 proto tcp comment "Dev servers from: $docker_net"
done

# Common development ports
print_status "Adding common development ports..."
sudo ufw allow from "$LOCAL_NETWORK" to any port 5173 proto tcp comment 'Vite dev server'
sudo ufw allow from "$LOCAL_NETWORK" to any port 8080 proto tcp comment 'Alt dev server'

# Enable comprehensive logging
print_status "Enabling UFW logging..."
sudo ufw logging medium

# Enable UFW
print_status "Enabling UFW firewall..."
sudo ufw --force enable


print_header "UFW Configuration Complete"
print_status "Final UFW status:"
sudo ufw status numbered

echo
print_header "Security Summary"
print_status "✓ Default deny incoming (secure)"
print_status "✓ SSH allowed with rate limiting"
print_status "✓ Local network ($LOCAL_NETWORK) allowed"
[ -n "$DOCKER_NETWORK" ] && print_status "✓ Docker bridge ($DOCKER_NETWORK) can reach host"
for docker_net in "${DOCKER_NETWORKS[@]}"; do
    print_status "✓ Custom Docker network ($docker_net) allowed"
done
print_status "✓ Development ports accessible from allowed networks"
[ -n "$TAILSCALE_IP" ] && print_status "✓ Tailscale traffic ($TAILSCALE_IP) bypasses UFW (handled by ts-input)"
print_status "✓ All other traffic blocked by default"

echo
print_header "Testing Commands"
echo "Monitor UFW logs: sudo tail -f /var/log/ufw.log"
echo "Check UFW status: sudo ufw status numbered"
echo "Test from LAN: ssh $USER@$(echo "$LOCAL_IP" | cut -d'/' -f1)"
[ -n "$TAILSCALE_IP" ] && echo "Test from Tailscale: ssh $USER@$TAILSCALE_IP"
echo

print_header "Next Steps"
print_status "1. Test SSH access from another device on your network"
print_status "2. Monitor UFW logs for any blocked traffic you need to allow"
print_status "3. Add specific rules for any additional services as needed"

# Show network interface summary
echo
print_header "Network Interface Summary"
echo "Primary Interface: $PRIMARY_IF ($LOCAL_IP)"
[ -n "$TAILSCALE_IP" ] && echo "Tailscale Interface: tailscale0 ($TAILSCALE_IP)"
[ -n "$DOCKER_BRIDGE" ] && echo "Docker Interface: docker0 ($DOCKER_BRIDGE)"

print_status "Configuration completed successfully!"

# Optional: Generate a summary report
REPORT_FILE="/tmp/ufw-config-report-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "UFW Configuration Report"
    echo "Generated: $(date)"
    echo "Primary Interface: $PRIMARY_IF"
    echo "Local Network: $LOCAL_NETWORK"
    [ -n "$TAILSCALE_IP" ] && echo "Tailscale IP: $TAILSCALE_IP"
    [ -n "$DOCKER_NETWORK" ] && echo "Docker Network: $DOCKER_NETWORK"
    echo ""
    echo "UFW Rules:"
    sudo ufw status numbered
} > "$REPORT_FILE"

print_status "Configuration report saved to: $REPORT_FILE"
