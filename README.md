# VPS Office Security Deployment

Complete setup for secure office infrastructure with VPN, email, Git hosting, team chat, and employee lockdown.

## What's Included

| Service | Domain | Description |
|---------|--------|-------------|
| Mailcow | mail.yourdomain.com | Self-hosted email server |
| Gitea | git.yourdomain.com | Self-hosted Git (like GitHub) |
| Rocket.Chat | chat.yourdomain.com | Self-hosted team chat (VPN only) |
| WireGuard | VPS_IP:51820 | VPN for employees |
| Pi-hole | 10.10.0.1:8080 | DNS-level site blocking (whitelist-only) |
| Fail2Ban | - | Brute force protection |
| UFW | - | Firewall |

## Architecture

```
Employee PC (Ubuntu)
    |
    | WireGuard VPN (encrypted tunnel)
    |
    v
VPS Server
    |-- Pi-hole (DNS filtering: whitelist-only mode)
    |-- Mailcow (company email: mail.yourdomain.com)
    |-- Gitea (company git: git.yourdomain.com)
    |-- Rocket.Chat (team chat: chat.yourdomain.com)
    |-- Nginx (reverse proxy, SSL termination)
    |-- WireGuard (VPN server)
    |-- Fail2Ban + UFW (security)
```

## Pi-hole Whitelist-Only Mode

All websites are blocked by default. Only the following categories are allowed:

| Category | Domains |
|----------|---------|
| Company | malspy.com, mail/git/chat subdomains |
| NPM/Node.js | npmjs.org, npmjs.com, nodejs.org, yarnpkg.com |
| Python/PyPI | pypi.org, python.org, pythonhosted.org |
| GitHub | github.com, githubusercontent.com |
| Next.js/Vercel | nextjs.org, vercel.com |
| React | reactjs.org, react.dev |
| Expo | expo.dev, expo.io |
| Django | djangoproject.com, django-rest-framework.org |
| CDNs | cloudflare.com, jsdelivr.net, fastly.net |
| Docs | stackoverflow.com, developer.mozilla.org |
| TypeScript | typescriptlang.org |
| Tailwind | tailwindcss.com |
| Docker | docker.com, docker.io |
| Databases | postgresql.org, redis.io |
| Cloud | amazonaws.com, sentry.io |
| OS Packages | ubuntu.com, debian.org |
| SSL | letsencrypt.org |
| Mobile Dev | apple.com, android.com, gradle.org |
| Google (dev) | fonts.googleapis.com, googleapis.com |

Everything else (Gmail, YouTube, Facebook, WhatsApp, ChatGPT, etc.) is **blocked**.

## Setup Order

### On VPS:
1. `bash 01-vps-setup.sh` - WireGuard, Pi-hole, SSH hardening
2. `bash 02-docker-services.sh` - Docker, Mailcow, Gitea, Rocket.Chat, Nginx
3. `bash 03-add-employee.sh` - Generate employee VPN configs

### On Employee PC:
1. Copy `employee1_vpn.conf` to `/etc/wireguard/wg0.conf`
2. Copy `employee1_pc_setup.sh` to employee PC
3. Run: `sudo bash employee1_pc_setup.sh`

## DNS Records Required

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | mail | VPS_IP | 3600 |
| A | git | VPS_IP | 3600 |
| A | chat | VPS_IP | 3600 |
| MX | @ | mail.yourdomain.com | 3600 (Priority: 10) |
| TXT | @ | v=spf1 mx -all | 3600 |

## Quick Reference

### URLs
- Email Admin: https://mail.yourdomain.com
- Git: https://git.yourdomain.com
- Team Chat: https://chat.yourdomain.com
- Pi-hole: http://10.10.0.1:8080/admin (VPN required)

### Manage Sites (Pi-hole)
```bash
# Allow a website
pihole --allow-regex '(^|\.)(domain\.com)$'

# Check if a domain is blocked
pihole query domain.com

# View all whitelist entries
sqlite3 /etc/pihole/gravity.db "SELECT domain, comment FROM domainlist WHERE type=2;"

# Reload after changes
pihole reloadlists
```

### Add New Employee
```bash
bash 03-add-employee.sh
```

### Check All Services
```bash
bash 05-manage.sh status
```

### Restart Services
```bash
bash 05-manage.sh restart-mail
bash 05-manage.sh restart-git
bash 05-manage.sh restart-chat
bash 05-manage.sh restart-vpn
bash 05-manage.sh restart-nginx
```

## Key Files on VPS

| File | Purpose |
|------|---------|
| `/etc/wireguard/wg0.conf` | WireGuard VPN config |
| `/opt/mailcow-dockerized/` | Mailcow installation |
| `/opt/mailcow-dockerized/data/conf/nginx/gitea.conf` | Nginx proxy for Gitea |
| `/opt/mailcow-dockerized/data/conf/nginx/rocketchat.conf` | Nginx proxy for Rocket.Chat |
| `/opt/gitea/docker-compose.yml` | Gitea config |
| `/opt/rocketchat/docker-compose.yml` | Rocket.Chat config |
| `/etc/pihole/gravity.db` | Pi-hole whitelist database |
| `/etc/pihole/pihole.toml` | Pi-hole config |
| `/root/employee*_vpn.conf` | Employee VPN configs |

## Troubleshooting

### Gitea/Chat shows Mailcow content
The Nginx config must be:
- Located at: `/opt/mailcow-dockerized/data/conf/nginx/<service>.conf`
- NOT in `site.d/` subdirectory
- NOT named `.conf.active` - must be `.conf`
- Use `proxy_pass http://<container_name>:<port>` (Docker DNS, not IP)
- Service must be on Mailcow's Docker network

Fix:
```bash
cd /opt/mailcow-dockerized
docker compose exec nginx-mailcow nginx -s reload
```

### Employee can't connect to VPN
1. Check WireGuard is running: `wg show`
2. Check employee peer is added: `grep -A3 "Peer" /etc/wireguard/wg0.conf`
3. Check firewall allows WireGuard: `ufw status | grep 51820`

### Rocket.Chat won't start
1. Check MongoDB replica set: `docker exec rocketchat-mongo mongosh --eval "rs.status()"`
2. Check logs: `bash 05-manage.sh logs-chat`
3. Restart: `bash 05-manage.sh restart-chat`

### Services won't start after reboot
```bash
systemctl enable wg-quick@wg0
systemctl enable docker
cd /opt/mailcow-dockerized && docker compose up -d
cd /opt/gitea && docker compose up -d
cd /opt/rocketchat && docker compose up -d
```

### Pi-hole: Allow a new website
```bash
sqlite3 /etc/pihole/gravity.db "INSERT INTO domainlist (type, domain, comment) VALUES (2, '(^|\\.)(newsite\\.com)\$', 'Description');"
pihole reloadlists
```
