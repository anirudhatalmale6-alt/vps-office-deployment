#!/bin/bash
#############################################
# PART 2: DOCKER + MAILCOW + GITEA
# Run as root: bash 02-docker-services.sh
#
# This script sets up:
# - Docker
# - Mailcow (email server)
# - Gitea (self-hosted Git)
# - Nginx reverse proxy (Gitea through Mailcow's Nginx)
#
# BEFORE RUNNING: Update the variables below
# BEFORE RUNNING: DNS records must point to this VPS:
#   A record: mail.yourdomain.com -> VPS_IP
#   A record: git.yourdomain.com  -> VPS_IP
#   MX record: @ -> mail.yourdomain.com (priority 10)
#   TXT record: @ -> v=spf1 mx -all
#############################################

set -e

# ======== CONFIGURATION ========
MAIL_DOMAIN="mail.malspy.com"
GIT_DOMAIN="git.malspy.com"
CHAT_DOMAIN="chat.malspy.com"
# ================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=============================================="
echo "   Docker + Mailcow + Gitea Setup"
echo "=============================================="
echo -e "${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Run as root (sudo -i)${NC}"
    exit 1
fi

# ============================================
# 2.1 Install Docker
# ============================================
echo -e "${GREEN}[1/5] Installing Docker...${NC}"
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
apt install -y docker-compose-plugin

docker --version
docker compose version

# Docker security settings
cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["1.1.1.1", "8.8.8.8"],
  "no-new-privileges": true,
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker

# ============================================
# 2.2 Install Mailcow
# ============================================
echo -e "${GREEN}[2/5] Installing Mailcow...${NC}"
cd /opt
git clone https://github.com/mailcow/mailcow-dockerized
cd mailcow-dockerized

echo -e "${YELLOW}Mailcow config generator will start.${NC}"
echo -e "${YELLOW}Enter your mail hostname: $MAIL_DOMAIN${NC}"
read -p "Press Enter to continue..."
./generate_config.sh

# Add Gitea and Chat domains for SSL
sed -i "s/^ADDITIONAL_SAN=.*/ADDITIONAL_SAN=$GIT_DOMAIN,$CHAT_DOMAIN/" mailcow.conf

echo -e "${GREEN}Pulling Mailcow containers (this takes a while)...${NC}"
docker compose pull
docker compose up -d

echo "Waiting for Mailcow to start (2 minutes)..."
sleep 120

docker compose ps

# ============================================
# 2.3 Install Gitea
# ============================================
echo -e "${GREEN}[3/5] Installing Gitea...${NC}"
mkdir -p /opt/gitea
cd /opt/gitea

# IMPORTANT: Gitea must be on Mailcow's Docker network for Nginx proxy to work
# Find Mailcow's network name
MAILCOW_NETWORK=$(docker network ls --format '{{.Name}}' | grep mailcow.*network)
echo "Mailcow network: $MAILCOW_NETWORK"

cat > docker-compose.yml << EOF

services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: always
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__server__DOMAIN=$GIT_DOMAIN
      - GITEA__server__ROOT_URL=https://$GIT_DOMAIN/
      - GITEA__server__SSH_DOMAIN=$GIT_DOMAIN
      - GITEA__server__SSH_PORT=2222
      - GITEA__service__DISABLE_REGISTRATION=true
      - GITEA__service__REQUIRE_SIGNIN_VIEW=true
    volumes:
      - ./data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "127.0.0.1:3000:3000"
      - "2222:22"
    networks:
      - default
      - mailcow-network

networks:
  mailcow-network:
    external: true
    name: $MAILCOW_NETWORK
EOF

docker compose up -d
sleep 10
docker compose ps

# ============================================
# 2.4 Install Rocket.Chat
# ============================================
echo -e "${GREEN}[4/7] Installing Rocket.Chat...${NC}"
mkdir -p /opt/rocketchat
cd /opt/rocketchat

cat > docker-compose.yml << EOF

services:
  rocketchat:
    image: registry.rocket.chat/rocketchat/rocket.chat:latest
    container_name: rocketchat
    restart: always
    environment:
      - ROOT_URL=https://$CHAT_DOMAIN
      - PORT=3100
      - MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0
      - MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0
      - DEPLOY_METHOD=docker
    depends_on:
      - mongodb
    ports:
      - "127.0.0.1:3100:3100"
    networks:
      - default
      - mailcow-network

  mongodb:
    image: mongo:7.0
    container_name: rocketchat-mongo
    restart: always
    command: mongod --replSet rs0 --oplogSize 128
    volumes:
      - mongodb_data:/data/db

volumes:
  mongodb_data:

networks:
  mailcow-network:
    external: true
    name: $MAILCOW_NETWORK
EOF

docker compose up -d
sleep 10

# Initialize MongoDB replica set
docker exec rocketchat-mongo mongosh --eval "rs.initiate()" 2>/dev/null || true

echo "Waiting for Rocket.Chat to start (2 minutes)..."
sleep 120
docker compose ps

# ============================================
# 2.5 Nginx Reverse Proxy for Gitea
# ============================================
echo -e "${GREEN}[5/7] Configuring Nginx reverse proxy for Gitea...${NC}"

cd /opt/mailcow-dockerized

# IMPORTANT: Config file MUST be placed directly in data/conf/nginx/ (NOT site.d/)
# IMPORTANT: File MUST end in .conf (NOT .conf.active or anything else)
# IMPORTANT: proxy_pass must use container name 'gitea' (NOT 172.17.0.1)
#            because Gitea is on the Mailcow Docker network

cat > data/conf/nginx/gitea.conf << EOF
server {
    listen 80;
    server_name $GIT_DOMAIN;
    root /web;

    location ^~ /.well-known/acme-challenge/ {
        allow all;
        default_type "text/plain";
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;

    server_name $GIT_DOMAIN;

    ssl_certificate /etc/ssl/mail/cert.pem;
    ssl_certificate_key /etc/ssl/mail/key.pem;

    client_max_body_size 512M;

    location / {
        proxy_pass http://gitea:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

# ============================================
# 2.6 Nginx Reverse Proxy for Rocket.Chat
# ============================================
echo -e "${GREEN}[6/7] Configuring Nginx reverse proxy for Rocket.Chat...${NC}"

cat > data/conf/nginx/rocketchat.conf << EOF
server {
    listen 80;
    server_name $CHAT_DOMAIN;
    root /web;

    location ^~ /.well-known/acme-challenge/ {
        allow all;
        default_type "text/plain";
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;

    server_name $CHAT_DOMAIN;

    ssl_certificate /etc/ssl/mail/cert.pem;
    ssl_certificate_key /etc/ssl/mail/key.pem;

    client_max_body_size 200M;

    location / {
        proxy_pass http://rocketchat:3100;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

# Test and reload Nginx
docker compose exec -T nginx-mailcow nginx -t
docker compose exec -T nginx-mailcow nginx -s reload

echo ""
echo "Verifying..."
sleep 3
GITEA_TITLE=$(curl -sk https://$GIT_DOMAIN 2>&1 | grep -o '<title>[^<]*</title>')
MAIL_TITLE=$(curl -sk https://$MAIL_DOMAIN 2>&1 | grep -o '<title>[^<]*</title>')
CHAT_TITLE=$(curl -sk --resolve $CHAT_DOMAIN:443:127.0.0.1 https://$CHAT_DOMAIN 2>&1 | grep -o '<title>[^<]*</title>')
echo "Mailcow page: $MAIL_TITLE"
echo "Gitea page: $GITEA_TITLE"
echo "Rocket.Chat page: $CHAT_TITLE"

# ============================================
# 2.7 Firewall Rules
# ============================================
echo -e "${GREEN}[7/7] Configuring firewall...${NC}"
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

# HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Gitea SSH
ufw allow 2222/tcp

ufw --force enable
ufw status numbered

echo ""
echo -e "${BLUE}=============================================="
echo "   Docker Services Setup Complete!"
echo "=============================================="
echo -e "${NC}"
echo ""
echo "Services:"
echo "  Mailcow:      https://$MAIL_DOMAIN (admin/moohoo - CHANGE THIS!)"
echo "  Gitea:        https://$GIT_DOMAIN (complete setup in browser)"
echo "  Rocket.Chat:  https://$CHAT_DOMAIN (complete setup in browser)"
echo "  Pi-hole:      http://10.10.0.1:8080/admin (VPN required)"
echo ""
echo -e "${YELLOW}IMPORTANT: Complete Gitea setup by visiting https://$GIT_DOMAIN${NC}"
echo -e "${YELLOW}IMPORTANT: Complete Rocket.Chat setup by visiting https://$CHAT_DOMAIN${NC}"
echo -e "${YELLOW}IMPORTANT: Change Mailcow admin password!${NC}"
echo ""
echo -e "${YELLOW}Next: Run 03-add-employee.sh to add VPN employees${NC}"
