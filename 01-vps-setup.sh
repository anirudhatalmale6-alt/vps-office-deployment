#!/bin/bash
#############################################
# PART 1: VPS INITIAL SETUP
# Run as root: sudo -i && bash 01-vps-setup.sh
#
# This script sets up:
# - System packages
# - WireGuard VPN
# - DNS configuration
# - Pi-hole (DNS-level ad/site blocking)
#
# BEFORE RUNNING: Update the variables below
#############################################

set -e

# ======== CONFIGURATION ========
# Change these to match your setup
VPS_IP="145.239.93.41"
MAIL_DOMAIN="mail.malspy.com"
GIT_DOMAIN="git.malspy.com"
PIHOLE_PORT="8080"            # Pi-hole admin port (avoid conflict with Mailcow)
# ================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=============================================="
echo "   VPS Initial Setup"
echo "=============================================="
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Run as root (sudo -i)${NC}"
    exit 1
fi

# ============================================
# 1.1 System Update & Packages
# ============================================
echo -e "${GREEN}[1/6] Updating system and installing packages...${NC}"
apt update && apt upgrade -y
apt install -y curl wget nano git htop unzip zip ufw fail2ban wireguard

# ============================================
# 1.2 Enable IP Forwarding
# ============================================
echo -e "${GREEN}[2/6] Enabling IP forwarding...${NC}"
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# ============================================
# 1.3 WireGuard VPN Setup
# ============================================
echo -e "${GREEN}[3/6] Setting up WireGuard VPN...${NC}"
wg genkey | tee /etc/wireguard/vps_private.key | wg pubkey > /etc/wireguard/vps_public.key
chmod 600 /etc/wireguard/vps_private.key

VPS_PRIVATE_KEY=$(cat /etc/wireguard/vps_private.key)
VPS_PUBLIC_KEY=$(cat /etc/wireguard/vps_public.key)

# Detect network interface
NET_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "Detected network interface: $NET_INTERFACE"

# Create WireGuard config
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = $VPS_PRIVATE_KEY
PostUp = iptables -I FORWARD 1 -i wg0 -j ACCEPT; iptables -I FORWARD 1 -o wg0 -j ACCEPT; iptables -t nat -I POSTROUTING 1 -o $NET_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $NET_INTERFACE -j MASQUERADE

# Employees will be added below
EOF

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
wg show

apt install -y iptables-persistent
netfilter-persistent save

# ============================================
# 1.4 Fix DNS
# ============================================
echo -e "${GREEN}[4/6] Configuring DNS...${NC}"
cat > /etc/systemd/resolved.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=8.8.4.4
EOF

systemctl enable systemd-resolved
systemctl restart systemd-resolved

# ============================================
# 1.5 Pi-hole Installation
# ============================================
echo -e "${GREEN}[5/6] Installing Pi-hole...${NC}"
echo ""
echo -e "${YELLOW}Pi-hole installer will start. Select these options:${NC}"
echo "  Interface: $NET_INTERFACE"
echo "  Upstream DNS: 1.1.1.1 (Cloudflare)"
echo "  Install web interface: Yes"
echo "  Install lighttpd: Yes"
echo "  Log queries: Yes"
echo ""
read -p "Press Enter to start Pi-hole installation..."

curl -sSL https://install.pi-hole.net | bash

# Change Pi-hole port to avoid Mailcow conflict
echo -e "${GREEN}Changing Pi-hole port to $PIHOLE_PORT...${NC}"
# Update pihole.toml - find the port line and replace it
if [ -f /etc/pihole/pihole.toml ]; then
    sed -i "s|port = \"80o,443os,\[::\]:80o,\[::\]:443os\"|port = \"127.0.0.1:${PIHOLE_PORT},\[::1\]:${PIHOLE_PORT}\"|" /etc/pihole/pihole.toml
fi

systemctl restart pihole-FTL

# Block personal email services via Pi-hole
echo -e "${GREEN}Blocking email services...${NC}"
pihole deny gmail.com
pihole deny mail.google.com
pihole deny accounts.google.com
pihole deny outlook.com
pihole deny outlook.live.com
pihole deny login.microsoftonline.com
pihole deny login.live.com
pihole deny yahoo.com
pihole deny mail.yahoo.com
pihole deny protonmail.com
pihole deny proton.me

# ============================================
# 1.6 SSH Hardening
# ============================================
echo -e "${GREEN}[6/6] Hardening SSH...${NC}"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

cat > /etc/ssh/sshd_config.d/hardening.conf << 'EOF'
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
EOF

sshd -t && systemctl restart ssh

# Fail2Ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 10.10.0.0/24

[sshd]
enabled = true
port = 22
maxretry = 3
bantime = 24h

[postfix]
enabled = true

[dovecot]
enabled = true
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo ""
echo -e "${BLUE}=============================================="
echo "   VPS Initial Setup Complete!"
echo "=============================================="
echo -e "${NC}"
echo ""
echo "VPS Public Key: $VPS_PUBLIC_KEY"
echo "Save this key - you need it for employee configs!"
echo ""
echo -e "${YELLOW}Next: Run 02-docker-services.sh${NC}"
