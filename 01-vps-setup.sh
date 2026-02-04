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
CHAT_DOMAIN="chat.malspy.com"
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

# Configure Pi-hole: WHITELIST-ONLY mode
# Block ALL sites by default, only allow developer-needed sites
echo -e "${GREEN}Setting up Pi-hole whitelist-only mode...${NC}"

apt install -y sqlite3

DB=/etc/pihole/gravity.db

# Clear existing rules
sqlite3 $DB "DELETE FROM domainlist;"

# Pi-hole types: 0=exact allow, 1=exact deny, 2=regex allow, 3=regex deny

# Company services
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(malspy\\.com)\$', 'Company domains');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (0, 'malspy.com', 'Company main');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (0, 'mail.malspy.com', 'Company mail');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (0, 'git.malspy.com', 'Company git');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (0, 'chat.malspy.com', 'Company chat');"

# NPM / Node.js (Next.js + Expo)
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(npmjs\\.org|npmjs\\.com)\$', 'NPM');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(nodejs\\.org)\$', 'Node.js');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(yarnpkg\\.com)\$', 'Yarn');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(unpkg\\.com)\$', 'NPM CDN');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(pnpm\\.io)\$', 'PNPM');"

# Python / PyPI (Django)
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(pypi\\.org|pythonhosted\\.org)\$', 'PyPI');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(python\\.org)\$', 'Python');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(pypa\\.io)\$', 'PyPA');"

# GitHub
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(github\\.com|githubusercontent\\.com|github\\.io|githubassets\\.com)\$', 'GitHub');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(ghcr\\.io)\$', 'GitHub Container Registry');"

# Stack Overflow
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(stackoverflow\\.com|stackexchange\\.com|sstatic\\.net)\$', 'Stack Overflow');"

# Next.js / Vercel
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(nextjs\\.org|vercel\\.com|vercel\\.app)\$', 'Next.js/Vercel');"

# React
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(reactjs\\.org|react\\.dev)\$', 'React');"

# Expo
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(expo\\.dev|expo\\.io|exp\\.host)\$', 'Expo');"

# Django
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(djangoproject\\.com)\$', 'Django');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(django-rest-framework\\.org)\$', 'Django REST');"

# CDNs
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(cloudflare\\.com|cdnjs\\.cloudflare\\.com)\$', 'Cloudflare CDN');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(jsdelivr\\.net)\$', 'jsDelivr CDN');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(fastly\\.net|fastlylb\\.net)\$', 'Fastly CDN');"

# Docker
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(docker\\.com|docker\\.io)\$', 'Docker');"

# MDN Docs
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(developer\\.mozilla\\.org|mozilla\\.net)\$', 'MDN Docs');"

# Google Fonts & APIs (for web dev)
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(fonts\\.googleapis\\.com|fonts\\.gstatic\\.com)\$', 'Google Fonts');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(googleapis\\.com)\$', 'Google APIs');"

# TypeScript, Tailwind, ESLint
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(typescriptlang\\.org)\$', 'TypeScript');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(tailwindcss\\.com)\$', 'Tailwind CSS');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(eslint\\.org)\$', 'ESLint');"

# Let's Encrypt
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(letsencrypt\\.org)\$', 'Lets Encrypt');"

# Mobile dev (Expo)
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(apple\\.com)\$', 'Apple Dev');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(android\\.com|dl\\.google\\.com)\$', 'Android Dev');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(gradle\\.org)\$', 'Gradle');"

# Databases
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(postgresql\\.org)\$', 'PostgreSQL');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(redis\\.io)\$', 'Redis');"

# AWS / Cloud
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(amazonaws\\.com)\$', 'AWS');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(sentry\\.io)\$', 'Sentry');"

# OS packages
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(ubuntu\\.com|canonical\\.com|launchpad\\.net)\$', 'Ubuntu packages');"
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(debian\\.org)\$', 'Debian packages');"

# BLOCK ALL (regex deny-all - everything not whitelisted above is blocked)
sqlite3 $DB "INSERT INTO domainlist (type, domain, comment) VALUES (3, '.*', 'Block all - whitelist only mode');"

pihole reloadlists
echo -e "${GREEN}Pi-hole whitelist-only mode configured${NC}"

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
