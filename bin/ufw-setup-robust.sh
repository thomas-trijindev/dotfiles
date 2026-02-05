#!/bin/bash
# UFW Configuration Script for CachyOS + Docker + Tailscale
# Dynamic network detection with comprehensive error handling
# Version: 2.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/ufw-setup-$(date +%Y%m%d-%H%M%S).log"
PRIMARY_IF=""
LOCAL_IP=""
LOCAL_NETWORK=""
TAILSCALE_IP=""
DOCKER_BRIDGE=""
DOCKER_NETWORK=""
DOCKER_NETWORKS=()

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    log "INFO: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    log "WARN: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
    log "HEADER: $1"
}

print_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
        log "DEBUG: $1"
    fi
}

# Error handling function
handle_error() {
    print_error "An error occurred on line $1. Check log: $LOG_FILE"
    print_error "Attempting to restore UFW to previous state..."
    
    # Attempt to restore from most recent backup
    LATEST_BACKUP=$(find /etc/ufw/backup-* -maxdepth 0 -type d 2>/dev/null | sort | tail -1)
    if [ -n "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
        print_warning "Restoring from backup: $LATEST_BACKUP"
        sudo cp -r "$LATEST_BACKUP"/* /etc/ufw/ 2>/dev/null || true
        sudo ufw reload 2>/dev/null || true
    fi
    
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if running as root (for sudo commands)
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        print_status "Please run: sudo -v"
        exit 1
    fi
    
    # Check if UFW is installed
    if ! command -v ufw >/dev/null 2>&1; then
        print_error "UFW is not installed"
        print_status "Install with: sudo pacman -S ufw"
        exit 1
    fi
    
    # Check for required tools
    local missing_tools=()
    for tool in ip awk sed grep; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    print_status "All prerequisites satisfied"
    echo
}

# Function to detect network configuration with validation
detect_networks() {
    print_header "Detecting Network Configuration"
    
    # Detect primary interface and LAN network
    print_debug "Detecting primary network interface..."
    PRIMARY_IF=$(ip route get 8.8.8.8 2>/dev/null | head -1 | awk '{print $5}' | head -1 || echo "")
    
    if [ -z "$PRIMARY_IF" ]; then
        # Fallback method
        PRIMARY_IF=$(ip route | grep default | awk '{print $5}' | head -1 || echo "")
    fi
    
    if [ -n "$PRIMARY_IF" ]; then
        print_debug "Primary interface detected: $PRIMARY_IF"
        
        # Get IP address with better parsing
        LOCAL_IP=$(ip addr show "$PRIMARY_IF" 2>/dev/null | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | head -1 || echo "")
        
        if [ -n "$LOCAL_IP" ]; then
            # Validate IP format
            if [[ "$LOCAL_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                # Extract network from IP/CIDR (smarter network calculation)
                IFS='/' read -r ip_part cidr_part <<< "$LOCAL_IP"
                IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$ip_part"
                
                # Calculate network based on CIDR
                case "$cidr_part" in
                    24) LOCAL_NETWORK="${ip1}.${ip2}.${ip3}.0/24" ;;
                    16) LOCAL_NETWORK="${ip1}.${ip2}.0.0/16" ;;
                    8) LOCAL_NETWORK="${ip1}.0.0.0/8" ;;
                    *) 
                        # For other CIDR values, use a more conservative /24
                        LOCAL_NETWORK="${ip1}.${ip2}.${ip3}.0/24"
                        print_warning "Unusual CIDR /$cidr_part detected, using /24 network"
                        ;;
                esac
                
                print_status "Primary interface: $PRIMARY_IF"
                print_status "Local IP: $LOCAL_IP"
                print_status "Calculated network: $LOCAL_NETWORK"
            else
                print_error "Invalid IP format detected: $LOCAL_IP"
                exit 1
            fi
        else
            print_error "Could not detect local IP address on interface $PRIMARY_IF"
            print_debug "Available interfaces:"
            ip addr show | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/:$//' >> "$LOG_FILE"
            exit 1
        fi
    else
        print_error "Could not detect primary network interface"
        print_debug "Available routes:"
        ip route >> "$LOG_FILE" 2>&1
        exit 1
    fi
    
    # Detect Tailscale configuration with better error handling
    print_debug "Detecting Tailscale configuration..."
    TAILSCALE_IP=""
    if command -v tailscale >/dev/null 2>&1; then
        if systemctl is-active tailscaled >/dev/null 2>&1; then
            TAILSCALE_IP=$(timeout 5 tailscale ip -4 2>/dev/null || echo "")
            if [ -n "$TAILSCALE_IP" ]; then
                # Validate Tailscale IP is in correct range
                if [[ "$TAILSCALE_IP" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-2][0-9])\. ]]; then
                    print_status "Tailscale IP: $TAILSCALE_IP (bypasses UFW)"
                else
                    print_warning "Unusual Tailscale IP range: $TAILSCALE_IP"
                fi
            else
                print_warning "Tailscale installed but not connected or authenticated"
            fi
        else
            print_warning "Tailscale installed but service not running"
        fi
    else
        print_debug "Tailscale not installed"
    fi
    
    # Detect Docker configuration with comprehensive network detection
    print_debug "Detecting Docker configuration..."
    DOCKER_BRIDGE=""
    DOCKER_NETWORKS=()
    
    if command -v docker >/dev/null 2>&1; then
        if systemctl is-active docker >/dev/null 2>&1 || pgrep dockerd >/dev/null 2>&1; then
            print_debug "Docker service is active"
            
            # Check default bridge
            DOCKER_BRIDGE=$(ip addr show docker0 2>/dev/null | grep -E 'inet [0-9]' | awk '{print $2}' | head -1 || echo "")
            if [ -n "$DOCKER_BRIDGE" ]; then
                # Convert bridge IP to network
                DOCKER_NETWORK=$(echo "$DOCKER_BRIDGE" | sed 's/\.[0-9]*\//.0\//')
                print_status "Docker bridge: $DOCKER_BRIDGE"
                print_status "Docker network: $DOCKER_NETWORK"
            else
                print_debug "Docker bridge not found or not configured"
            fi
            
            # Check for custom Docker networks (with timeout)
            if timeout 10 docker network ls >/dev/null 2>&1; then
                print_debug "Checking custom Docker networks..."
                
                # Get custom networks without jq dependency
                CUSTOM_NETWORKS=$(docker network ls --format "table {{.Name}}" | tail -n +2 | grep -v -E '^(bridge|host|none)$' | head -10 || echo "")
                
                for net in $CUSTOM_NETWORKS; do
                    if [ -n "$net" ]; then
                        # Get subnet without jq
                        NET_SUBNET=$(docker network inspect "$net" 2>/dev/null | grep '"Subnet"' | head -1 | sed 's/.*"Subnet": *"\([^"]*\)".*/\1/' || echo "")
                        if [ -n "$NET_SUBNET" ] && [[ "$NET_SUBNET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                            DOCKER_NETWORKS+=("$NET_SUBNET")
                            print_status "Custom Docker network '$net': $NET_SUBNET"
                        fi
                    fi
                done
            else
                print_debug "Could not query Docker networks (timeout or permission issue)"
            fi
        else
            print_debug "Docker service not running"
        fi
    else
        print_debug "Docker not installed"
    fi
    
    echo
}

# Function to validate detected networks
validate_networks() {
    print_header "Validating Network Configuration"
    
    # Validate local network is private (RFC1918) or common ranges
    local is_private=false
    if [[ "$LOCAL_NETWORK" =~ ^192\.168\. ]] || \
       [[ "$LOCAL_NETWORK" =~ ^10\. ]] || \
       [[ "$LOCAL_NETWORK" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || \
       [[ "$LOCAL_NETWORK" =~ ^169\.254\. ]]; then
        is_private=true
        print_status "Local network is private/local: $LOCAL_NETWORK"
    fi
    
    if [ "$is_private" = false ]; then
        print_warning "Local network appears to be public: $LOCAL_NETWORK"
        print_warning "This may not be suitable for UFW local network rules"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Configuration cancelled by user"
            exit 0
        fi
    fi
    
    # Check for network conflicts
    if [ -n "$DOCKER_NETWORK" ] && [ "$LOCAL_NETWORK" = "$DOCKER_NETWORK" ]; then
        print_error "Network conflict detected!"
        print_error "Local network and Docker network overlap: $LOCAL_NETWORK"
        print_error "This can cause routing issues. Please reconfigure Docker networks."
        exit 1
    fi
    
    # Check Docker custom network conflicts
    for docker_net in "${DOCKER_NETWORKS[@]}"; do
        if [ "$LOCAL_NETWORK" = "$docker_net" ]; then
            print_error "Network conflict: Local network overlaps with Docker network $docker_net"
            exit 1
        fi
    done
    
    print_status "Network validation completed"
    echo
}

# Function to create comprehensive backup
create_backup() {
    print_header "Creating Configuration Backup"
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="/etc/ufw/backup-$timestamp"
    
    print_status "Creating backup directory: $backup_dir"
    sudo mkdir -p "$backup_dir"
    
    # Backup UFW configuration files
    local files_to_backup=("user.rules" "user6.rules" "before.rules" "after.rules" "ufw.conf")
    
    for file in "${files_to_backup[@]}"; do
        if [ -f "/etc/ufw/$file" ]; then
            sudo cp "/etc/ufw/$file" "$backup_dir/" || print_warning "Failed to backup $file"
        fi
    done
    
    # Save current UFW status
    sudo ufw status verbose > "$backup_dir/status.txt" 2>&1 || true
    sudo iptables-save > "$backup_dir/iptables.txt" 2>&1 || true
    
    print_status "Backup created successfully: $backup_dir"
    echo "$backup_dir" > /tmp/ufw-backup-location.txt
    echo
}

# Enhanced UFW configuration function
configure_ufw() {
    print_header "Configuring UFW Rules"
    
    # Reset UFW with confirmation
    print_status "Resetting UFW to clean state..."
    sudo ufw --force reset
    
    # Set secure defaults
    print_status "Setting secure default policies..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing  
    sudo ufw default deny forward
    
    # Essential SSH access with enhanced rate limiting
    print_status "Configuring SSH access with rate limiting..."
    sudo ufw allow ssh comment 'SSH access'
    sudo ufw limit ssh comment 'SSH rate limiting'
    
    # Local network access with validation
    if [ -n "$LOCAL_NETWORK" ]; then
        print_status "Allowing local network access: $LOCAL_NETWORK"
        sudo ufw allow from "$LOCAL_NETWORK" comment "Local network: $LOCAL_NETWORK"
    fi
    
    # Docker network access
    if [ -n "$DOCKER_NETWORK" ]; then
        print_status "Allowing Docker bridge network: $DOCKER_NETWORK"
        sudo ufw allow from "$DOCKER_NETWORK" comment "Docker bridge: $DOCKER_NETWORK"
    fi
    
    # Custom Docker networks
    for docker_net in "${DOCKER_NETWORKS[@]}"; do
        print_status "Allowing custom Docker network: $docker_net"
        sudo ufw allow from "$docker_net" comment "Docker custom: $docker_net"
    done
    
    # Development server ports with proper scoping
    print_status "Configuring development server access..."
    
    if [ -n "$LOCAL_NETWORK" ]; then
        sudo ufw allow from "$LOCAL_NETWORK" to any port 3000:8999 proto tcp comment 'Dev servers: LAN'
        # Common specific dev ports
        sudo ufw allow from "$LOCAL_NETWORK" to any port 5173 proto tcp comment 'Vite dev server'
        sudo ufw allow from "$LOCAL_NETWORK" to any port 8080 proto tcp comment 'Alt dev server'
    fi
    
    if [ -n "$DOCKER_NETWORK" ]; then
        sudo ufw allow from "$DOCKER_NETWORK" to any port 3000:8999 proto tcp comment 'Dev servers: Docker'
    fi
    
    for docker_net in "${DOCKER_NETWORKS[@]}"; do
        sudo ufw allow from "$docker_net" to any port 3000:8999 proto tcp comment "Dev servers: ${docker_net}"
    done
    
    # Enable logging with appropriate level
    print_status "Configuring logging..."
    sudo ufw logging medium
    
    # Enable UFW with final confirmation
    print_status "Enabling UFW firewall..."
    sudo ufw --force enable
    
    print_status "UFW configuration completed successfully"
}

# Comprehensive testing function
test_configuration() {
    print_header "Testing Configuration"
    
    # Test UFW status
    print_status "UFW Status Check:"
    if sudo ufw status | grep -q "Status: active"; then
        print_status "✓ UFW is active"
    else
        print_error "✗ UFW is not active"
        return 1
    fi
    
    # Count configured rules
    local rule_count=$(sudo ufw status numbered | grep -c "^\[" || echo "0")
    print_status "✓ $rule_count UFW rules configured"
    
    # Test network connectivity (basic)
    if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
        print_status "✓ Internet connectivity working"
    else
        print_warning "⚠ Internet connectivity test failed"
    fi
    
    # Check for conflicts
    if sudo iptables -L | grep -q "REJECT\|DROP"; then
        print_status "✓ Firewall rules are active in iptables"
    else
        print_warning "⚠ No blocking rules visible in iptables"
    fi
    
    print_status "Configuration testing completed"
}

# Generate comprehensive report
generate_report() {
    print_header "Generating Configuration Report"
    
    local report_file="/tmp/ufw-config-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "UFW Configuration Report"
        echo "Generated: $(date)"
        echo "Script Version: 2.0"
        echo "Host: $(hostname)"
        echo "User: $USER"
        echo ""
        echo "Network Configuration:"
        echo "Primary Interface: $PRIMARY_IF"
        echo "Local IP: $LOCAL_IP"
        echo "Local Network: $LOCAL_NETWORK"
        [ -n "$TAILSCALE_IP" ] && echo "Tailscale IP: $TAILSCALE_IP"
        [ -n "$DOCKER_NETWORK" ] && echo "Docker Network: $DOCKER_NETWORK"
        for docker_net in "${DOCKER_NETWORKS[@]}"; do
            echo "Custom Docker Network: $docker_net"
        done
        echo ""
        echo "UFW Configuration:"
        sudo ufw status verbose
        echo ""
        echo "UFW Rules (numbered):"
        sudo ufw status numbered
        echo ""
        echo "Active Network Interfaces:"
        ip addr show | grep -E "^[0-9]+:|inet "
    } > "$report_file"
    
    print_status "Detailed report saved to: $report_file"
    return 0
}

# Main configuration flow
main() {
    print_header "UFW Dynamic Configuration Script v2.0"
    print_status "Starting comprehensive UFW configuration..."
    print_status "Log file: $LOG_FILE"
    echo
    
    # Run all checks and configurations
    check_prerequisites
    detect_networks
    validate_networks
    
    # Show configuration summary
    print_header "Configuration Summary"
    echo "The following UFW rules will be configured:"
    echo "• Local network access: ${LOCAL_NETWORK:-"Not detected"}"
    [ -n "$DOCKER_NETWORK" ] && echo "• Docker bridge access: $DOCKER_NETWORK"
    for docker_net in "${DOCKER_NETWORKS[@]}"; do
        echo "• Custom Docker network: $docker_net"
    done
    echo "• SSH access with rate limiting"
    echo "• Development ports (3000-8999, 5173, 8080) from allowed networks"
    [ -n "$TAILSCALE_IP" ] && echo "• Tailscale traffic ($TAILSCALE_IP) will bypass UFW"
    echo
    
    # Confirmation with timeout
    read -t 30 -p "Proceed with UFW configuration? (Y/n): " -r || REPLY="Y"
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_status "Configuration cancelled by user"
        exit 0
    fi
    
    # Execute configuration
    create_backup
    configure_ufw
    test_configuration
    
    # Show final status
    print_header "Configuration Complete"
    sudo ufw status numbered
    
    echo
    print_header "Security Summary"
    print_status "✓ Default deny incoming policy active"
    print_status "✓ SSH access allowed with rate limiting"
    print_status "✓ Local network (${LOCAL_NETWORK}) access configured"
    [ -n "$DOCKER_NETWORK" ] && print_status "✓ Docker bridge (${DOCKER_NETWORK}) access configured"
    local custom_count=${#DOCKER_NETWORKS[@]}
    [ $custom_count -gt 0 ] && print_status "✓ $custom_count custom Docker networks configured"
    print_status "✓ Development ports accessible from allowed networks"
    [ -n "$TAILSCALE_IP" ] && print_status "✓ Tailscale traffic ($TAILSCALE_IP) bypasses UFW (handled by ts-input)"
    print_status "✓ Comprehensive logging enabled"
    
    echo
    print_header "Testing & Monitoring"
    echo "Test SSH access:"
    echo "  Local: ssh $USER@$(echo "$LOCAL_IP" | cut -d'/' -f1)"
    [ -n "$TAILSCALE_IP" ] && echo "  Tailscale: ssh $USER@$TAILSCALE_IP"
    echo ""
    echo "Monitor UFW activity:"
    echo "  sudo tail -f /var/log/ufw.log"
    echo "  sudo ufw status numbered"
    echo ""
    echo "View configuration:"
    echo "  sudo iptables -L -n -v"
    
    generate_report
    
    print_status "UFW configuration completed successfully!"
    print_status "Backup location: $(cat /tmp/ufw-backup-location.txt 2>/dev/null || echo "Not available")"
    print_status "Log file: $LOG_FILE"
}

# Handle script interruption
cleanup() {
    print_warning "Script interrupted. Check log: $LOG_FILE"
    exit 130
}

trap cleanup INT TERM

# Run main function
main "$@"
