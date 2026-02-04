#!/bin/bash
#############################################
# PART 4: FIREWALL SETUP (run separately if needed)
# Run as root on VPS
#############################################

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run as root"
    exit 1
fi

apt install -y ufw
ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow 22/tcp

# WireGuard
ufw allow 51820/udp

# Mailcow mail ports
ufw allow 25/tcp
ufw allow 465/tcp
ufw allow 587/tcp
ufw allow 993/tcp

# HTTP/HTTPS (Mailcow + Gitea)
ufw allow 80/tcp
ufw allow 443/tcp

# Gitea SSH
ufw allow 2222/tcp

ufw --force enable
ufw status numbered
