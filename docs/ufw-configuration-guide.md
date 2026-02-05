# UFW Firewall Configuration Guide for CachyOS
## Industrial Best Practices with Tailscale and Docker Integration

*Configuration Guide for Thomas's Development Environment*  
*Last Updated: February 2026*

---

## Executive Summary

This document outlines the industrial-grade UFW (Uncomplicated Firewall) configuration for a CachyOS system running Tailscale mesh networking and Docker containers. The setup implements defense-in-depth security with three distinct firewall layers handling different traffic types.

## Network Architecture Overview

### System Configuration
- **OS**: CachyOS (Arch-based)
- **Primary Interface**: wlan0 (192.168.1.41/24)
- **Tailscale Interface**: tailscale0 (100.125.91.45/32)
- **Docker Bridge**: docker0 (172.17.0.1/16)

### Traffic Flow Architecture
```
Internet/LAN Traffic  → UFW Rules      → Application
Tailscale Traffic    → ts-input Rules  → Application (bypasses UFW)
Docker Traffic       → UFW Rules      → Host Services
```

---

## Key Discoveries and Analysis

### 1. UFW State Analysis
**Initial Finding**: UFW was active but had zero user-defined rules
- Service: Active and enabled since system boot
- Rules: Empty user.rules file (only logging and rate-limiting chains configured)
- Status: `ufw status numbered` returned empty despite active service

### 2. Tailscale Network Behavior
**Critical Discovery**: Tailscale completely bypasses UFW

**Tailscale iptables Rules**:
```bash
Chain ts-input (1 references)
 pkts bytes target     prot opt in     out     source               destination
 5831  800K ACCEPT     all  --  tailscale0 *   0.0.0.0/0            0.0.0.0/0
    0     0 DROP       all  --  !tailscale0 *  100.64.0.0/10        0.0.0.0/0
```

**Security Implications**:
- ✅ All Tailscale traffic (100.125.91.45) is automatically accepted
- ✅ Prevents IP spoofing (blocks 100.64.0.0/10 from non-Tailscale interfaces)
- ⚠️ UFW rules do not apply to Tailscale mesh traffic

### 3. Docker Network Integration
**Docker Bridge Network**: 172.17.0.0/16
- Docker creates its own iptables rules
- Container-to-host communication requires explicit UFW allowance
- State: Interface UP but no containers currently running

---

## Industrial Best Practice Configuration

### Core Security Principles Applied
1. **Default Deny Policy**: All incoming traffic blocked by default
2. **Principle of Least Privilege**: Only specific networks allowed
3. **Defense in Depth**: Multiple firewall layers
4. **Network Segmentation**: Different rules for different network types
5. **Comprehensive Logging**: Full audit trail for security monitoring

### Final UFW Rule Set

```bash
# Default Policies
default deny incoming
default allow outgoing
default deny forward

# SSH Access with Rate Limiting
allow 22/tcp comment 'SSH access'
limit 22/tcp comment 'SSH rate limiting (max 6 attempts/min)'

# Network-Specific Access
allow from 192.168.1.0/24 comment 'Home/Office LAN'
allow from 172.17.0.0/16 comment 'Docker bridge network'

# Development Server Access
allow from 192.168.1.0/24 to any port 3000:8999/tcp comment 'Dev servers from LAN'
allow from 172.17.0.0/16 to any port 3000:8999/tcp comment 'Dev servers from containers'
allow from 192.168.1.0/24 to any port 5173/tcp comment 'Vite dev server'
allow from 192.168.1.0/24 to any port 8080/tcp comment 'Alt dev server'

# Logging
logging medium
```

---

## Network Security Matrix

| Traffic Source | IP Range | Firewall Handler | Access Level |
|----------------|----------|------------------|--------------|
| Internet | Any | UFW | Deny (default) |
| Local LAN | 192.168.1.0/24 | UFW | SSH + Dev ports |
| Tailscale Mesh | 100.64.0.0/10 | ts-input | Full access |
| Docker Containers | 172.17.0.0/16 | UFW | Host services |
| Loopback | 127.0.0.1 | N/A | Full access |

---

## Implementation Guide

### Prerequisites
```bash
# Verify UFW installation
sudo pacman -S ufw

# Check current status
sudo ufw status verbose
sudo systemctl status ufw
```

### Configuration Script
```bash
#!/bin/bash
# UFW Configuration for CachyOS + Docker + Tailscale

# Reset and set secure defaults
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny forward

# SSH with rate limiting
sudo ufw allow ssh comment 'SSH access'
sudo ufw limit ssh comment 'SSH rate limiting'

# Network access
sudo ufw allow from 192.168.1.0/24 comment 'Home/Office LAN'
sudo ufw allow from 172.17.0.0/16 comment 'Docker bridge network'

# Development ports
sudo ufw allow from 192.168.1.0/24 to any port 3000:8999 proto tcp comment 'Dev servers from LAN'
sudo ufw allow from 172.17.0.0/16 to any port 3000:8999 proto tcp comment 'Dev servers from containers'

# Enable logging and activate
sudo ufw logging medium
sudo ufw --force enable
```

---

## Monitoring and Maintenance

### Daily Operations
```bash
# Check firewall status
sudo ufw status numbered

# Monitor UFW logs (excludes Tailscale traffic)
sudo tail -f /var/log/ufw.log

# Check all firewall systems
sudo iptables -L ts-input -n -v    # Tailscale rules
sudo iptables -L ufw-user-input -n -v   # UFW rules
```

### Key Log Locations
- **UFW Logs**: `/var/log/ufw.log`
- **UFW Configuration**: `/etc/ufw/user.rules`
- **Backup Location**: `/etc/ufw/backup-YYYYMMDD/`

### Testing Procedures
```bash
# Test LAN access (should work)
ssh tjunkie@192.168.1.41

# Test Tailscale access (should work, bypasses UFW)
ssh tjunkie@100.125.91.45

# Test Docker container to host (should work if containers running)
docker run --rm alpine/curl curl http://172.17.0.1:22
```

---

## RFC1918 Private Networks Analysis

### Why Specific Networks vs. Broad Ranges

**Avoided Broad Ranges**:
```bash
# These were considered but rejected for security
sudo ufw allow from 10.0.0.0/8 comment 'RFC1918 Class A'        # 16M addresses
sudo ufw allow from 172.16.0.0/12 comment 'RFC1918 Class B'     # 1M addresses
sudo ufw allow from 192.168.0.0/16 comment 'RFC1918 Class C'    # 65K addresses
```

**Implemented Specific Networks**:
```bash
# Only actual networks in use
sudo ufw allow from 192.168.1.0/24 comment 'Actual LAN'         # 254 addresses
sudo ufw allow from 172.17.0.0/16 comment 'Docker bridge'       # Docker specific
```

**Security Rationale**: Follows principle of least privilege by allowing only known, required networks rather than entire RFC1918 address space.

---

## Advanced Configuration Options

### Tailscale Netfilter Control
```bash
# Disable Tailscale's iptables management (advanced)
tailscale up --netfilter-mode=off

# Then add Tailscale to UFW manually
sudo ufw allow from 100.64.0.0/10 comment 'Tailscale network'
```

### Docker UFW Integration
```bash
# Make Docker respect UFW (advanced)
# Edit /etc/docker/daemon.json:
{
  "iptables": false
}

# Requires manual Docker network rule management
```

### Application Profiles
```bash
# Create custom application profiles
sudo tee /etc/ufw/applications.d/development << EOF
[Development]
title=Development Environment
description=Common development server ports
ports=3000:3999/tcp|8000:8999/tcp|5173/tcp
EOF

# Apply profile
sudo ufw allow Development
```

---

## Automation Integration

### Ansible Playbook Integration
```yaml
- name: Configure UFW firewall
  block:
    - name: Install UFW
      pacman:
        name: ufw
        state: present

    - name: Configure UFW rules
      ufw:
        rule: "{{ item.rule }}"
        port: "{{ item.port | default(omit) }}"
        proto: "{{ item.proto | default(omit) }}"
        src: "{{ item.src | default(omit) }}"
        comment: "{{ item.comment | default(omit) }}"
      loop:
        - { rule: 'allow', port: 'ssh', comment: 'SSH access' }
        - { rule: 'allow', src: '192.168.1.0/24', comment: 'LAN' }
        - { rule: 'allow', src: '172.17.0.0/16', comment: 'Docker' }

    - name: Enable UFW
      ufw:
        state: enabled
        logging: medium
```

### Integration with Configuration Management
- **chezmoi**: Include UFW rules in dotfiles repository
- **mise**: No direct integration needed
- **Ansible**: Full automation capability as shown above

---

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. "UFW status numbered returns empty"
**Cause**: UFW active but no user-defined rules  
**Solution**: Add rules using `sudo ufw allow` commands

#### 2. "Tailscale connections work despite UFW blocks"
**Cause**: Tailscale bypasses UFW via ts-input chain  
**Solution**: This is normal behavior, use Tailscale ACLs for mesh network control

#### 3. "Docker containers can't reach host services"
**Cause**: Missing UFW rule for Docker bridge network  
**Solution**: `sudo ufw allow from 172.17.0.0/16`

#### 4. "SSH works from some devices but not others"
**Cause**: Device not on allowed networks  
**Solution**: Check device IP and add appropriate network rule

### Diagnostic Commands
```bash
# Check all network interfaces
ip addr show

# Verify iptables rule order
sudo iptables -L INPUT -n -v --line-numbers

# Check UFW rule processing
sudo iptables -L ufw-user-input -n -v

# Monitor real-time logs
sudo tail -f /var/log/ufw.log
```

---

## Security Considerations

### Threat Model Coverage
- ✅ **Internet-based attacks**: Blocked by UFW default deny
- ✅ **Local network lateral movement**: Limited to specific services
- ✅ **Container escapes**: Docker bridge network restrictions
- ✅ **Tailscale mesh security**: Handled by Tailscale authentication
- ✅ **SSH brute force**: Rate limiting implemented

### Regular Security Tasks
1. **Weekly**: Review UFW logs for unusual activity
2. **Monthly**: Audit active rules vs. actual requirements
3. **Quarterly**: Review Tailscale ACL policies
4. **Annual**: Full security architecture review

### Backup and Recovery
```bash
# Backup UFW configuration
sudo cp -r /etc/ufw /etc/ufw.backup.$(date +%Y%m%d)

# Restore from backup
sudo cp -r /etc/ufw.backup.YYYYMMDD/* /etc/ufw/
sudo ufw reload
```

---

## Conclusion

This configuration provides industrial-grade network security for a development environment while maintaining the flexibility needed for modern containerized and mesh-networked applications. The three-layer approach (UFW for perimeter defense, Tailscale for zero-trust mesh networking, and Docker for container isolation) creates a robust security posture suitable for both personal development and professional environments.

The configuration follows established security principles while accommodating the specific requirements of a CachyOS-based development environment with infrastructure automation tools.

---

## References and Further Reading

- [UFW Community Help](https://help.ubuntu.com/community/UFW)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Docker Network Security](https://docs.docker.com/network/iptables/)
- [RFC1918 Private Address Allocation](https://tools.ietf.org/html/rfc1918)
- [iptables Tutorial](https://www.netfilter.org/documentation/HOWTO/packet-filtering-HOWTO.html)

---

*This document serves as the authoritative reference for the UFW firewall configuration implemented on Thomas's CachyOS development environment.*
