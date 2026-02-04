#!/bin/bash
#############################################
# PART 3: ADD NEW EMPLOYEE VPN PEER
# Run on VPS as root: bash 03-add-employee.sh
#
# This script:
# - Generates WireGuard keys for new employee
# - Adds peer to VPS WireGuard config
# - Creates employee VPN config file
# - Creates employee PC setup script
#############################################

set -e

# ======== CONFIGURATION ========
VPS_IP="145.239.93.41"
# ================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=============================================="
echo "   Add New Employee VPN Peer"
echo "=============================================="
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Run as root (sudo -i)${NC}"
    exit 1
fi

# Get employee number
read -p "Employee number (e.g., 1, 2, 3): " EMP_NUM
read -p "Employee name (for reference only): " EMP_NAME

# Calculate IP (10.10.0.2 for emp1, 10.10.0.3 for emp2, etc.)
EMP_IP="10.10.0.$((EMP_NUM + 1))"

# Generate keys
cd /etc/wireguard
wg genkey | tee "emp${EMP_NUM}_private.key" | wg pubkey > "emp${EMP_NUM}_public.key"
chmod 600 "emp${EMP_NUM}_private.key"

EMP_PRIVKEY=$(cat "emp${EMP_NUM}_private.key")
EMP_PUBKEY=$(cat "emp${EMP_NUM}_public.key")
VPS_PUBKEY=$(wg show wg0 public-key)

# Add peer to WireGuard config
cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
# Employee $EMP_NUM - $EMP_NAME
PublicKey = $EMP_PUBKEY
AllowedIPs = $EMP_IP/32
EOF

# Apply without restart
wg syncconf wg0 <(wg-quick strip wg0)

# Create employee VPN config
cat > "/root/employee${EMP_NUM}_vpn.conf" << EOF
[Interface]
PrivateKey = $EMP_PRIVKEY
Address = $EMP_IP/32
DNS = 10.10.0.1

[Peer]
PublicKey = $VPS_PUBKEY
Endpoint = $VPS_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Create employee PC setup script
cat > "/root/employee${EMP_NUM}_pc_setup.sh" << 'PCSCRIPT'
#!/bin/bash
#############################################
# EMPLOYEE PC SETUP - Run on employee's Ubuntu PC
# Run as root: sudo -i && bash employee_pc_setup.sh
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Setting up employee PC...${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Run as root (sudo -i)${NC}"
    exit 1
fi

# 1. Install packages
echo -e "${GREEN}[1/6] Installing packages...${NC}"
apt update
apt install -y wireguard ufw resolvconf

# 2. Copy VPN config (must be placed before running this script)
echo -e "${GREEN}[2/6] Setting up WireGuard VPN...${NC}"
if [ ! -f /etc/wireguard/wg0.conf ]; then
    echo -e "${RED}ERROR: /etc/wireguard/wg0.conf not found!${NC}"
    echo "Copy the employee VPN config to /etc/wireguard/wg0.conf first"
    exit 1
fi

chmod 600 /etc/wireguard/wg0.conf
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Verify VPN
echo "Testing VPN connection..."
sleep 3
wg show
ping -c 3 10.10.0.1 || echo -e "${YELLOW}Warning: Cannot ping VPS via VPN${NC}"

# 3. Mandatory VPN enforcement
echo -e "${GREEN}[3/6] Enforcing mandatory VPN...${NC}"
PCSCRIPT

# Inject VPS_IP into the employee script
cat >> "/root/employee${EMP_NUM}_pc_setup.sh" << EOF
ufw --force reset
ufw default deny outgoing
ufw default deny incoming
ufw allow out to $VPS_IP port 51820 proto udp comment 'WireGuard to VPS'
ufw allow out on wg0 comment 'VPN outbound'
ufw allow in on wg0 comment 'VPN inbound'
ufw --force enable
EOF

cat >> "/root/employee${EMP_NUM}_pc_setup.sh" << 'PCSCRIPT'
ufw status verbose

# 4. Block personal email (extra layer via /etc/hosts)
echo -e "${GREEN}[4/6] Blocking personal email services...${NC}"
cat >> /etc/hosts << 'HOSTSEOF'

# Blocked by company policy
127.0.0.1 gmail.com www.gmail.com mail.google.com
127.0.0.1 accounts.google.com
127.0.0.1 outlook.com outlook.live.com
127.0.0.1 login.live.com login.microsoftonline.com
127.0.0.1 yahoo.com mail.yahoo.com
127.0.0.1 protonmail.com proton.me
127.0.0.1 chatgpt.com chat.openai.com
HOSTSEOF

# Lock hosts file
chattr +i /etc/hosts

# 5. Lock config files
echo -e "${GREEN}[5/6] Locking config files...${NC}"
chattr +i /etc/wireguard/wg0.conf

# 6. Block USB storage
echo -e "${GREEN}[6/6] Blocking USB storage...${NC}"
echo 'blacklist usb-storage' > /etc/modprobe.d/block-usb.conf
update-initramfs -u

echo ""
echo -e "${GREEN}=============================================="
echo "   Employee PC Setup Complete!"
echo "=============================================="
echo -e "${NC}"
echo ""
echo "VPN: Connected (mandatory - no internet without VPN)"
echo "Email: Personal email services blocked"
echo "USB: Storage devices blocked"
echo "Config files: Locked (cannot be modified by employee)"
echo ""
echo "Testing..."
echo ""

echo "=== VPN Status ==="
wg show

echo ""
echo "=== Internet Test ==="
curl -s --max-time 5 ifconfig.me && echo " (via VPN)" || echo "No internet"

echo ""
echo "=== Blocked Sites Test ==="
curl -s --max-time 5 https://gmail.com > /dev/null 2>&1 && echo "gmail.com: ACCESSIBLE (problem!)" || echo "gmail.com: BLOCKED (good)"

echo ""
echo "=== Allowed Sites Test ==="
curl -s --max-time 5 -o /dev/null -w "%{http_code}" https://github.com 2>/dev/null && echo " github.com: WORKS" || echo " github.com: FAILED"
PCSCRIPT

chmod +x "/root/employee${EMP_NUM}_pc_setup.sh"

echo ""
echo -e "${BLUE}=============================================="
echo "   Employee $EMP_NUM ($EMP_NAME) Added!"
echo "=============================================="
echo -e "${NC}"
echo ""
echo "Employee VPN IP: $EMP_IP"
echo ""
echo -e "${GREEN}Files created:${NC}"
echo "  /root/employee${EMP_NUM}_vpn.conf      - VPN config (copy to employee PC)"
echo "  /root/employee${EMP_NUM}_pc_setup.sh   - PC setup script (run on employee PC)"
echo ""
echo -e "${YELLOW}To set up employee PC:${NC}"
echo "  1. Copy employee${EMP_NUM}_vpn.conf to employee PC as /etc/wireguard/wg0.conf"
echo "  2. Copy employee${EMP_NUM}_pc_setup.sh to employee PC"
echo "  3. Run: sudo bash employee${EMP_NUM}_pc_setup.sh"
echo ""
echo -e "${GREEN}WireGuard Status:${NC}"
wg show
