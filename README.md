# VPS Office Security Deployment

Complete setup for secure office infrastructure with VPN, email, Git hosting, and employee lockdown.

## What's Included

| Service | Domain | Description |
|---------|--------|-------------|
| Mailcow | mail.yourdomain.com | Self-hosted email server |
| Gitea | git.yourdomain.com | Self-hosted Git (like GitHub) |
| WireGuard | VPS_IP:51820 | VPN for employees |
| Pi-hole | 10.10.0.1:8080 | DNS-level site blocking |
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
    |-- Pi-hole (DNS filtering: blocks gmail, outlook, etc.)
    |-- Mailcow (company email: mail.yourdomain.com)
    |-- Gitea (company git: git.yourdomain.com)
    |-- Nginx (reverse proxy, SSL termination)
    |-- WireGuard (VPN server)
    |-- Fail2Ban + UFW (security)
```

## Setup Order

### On VPS:
1. `bash 01-vps-setup.sh` - WireGuard, Pi-hole, SSH hardening
2. `bash 02-docker-services.sh` - Docker, Mailcow, Gitea, Nginx
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
| MX | @ | mail.yourdomain.com | 3600 (Priority: 10) |
| TXT | @ | v=spf1 mx -all | 3600 |

## Quick Reference

### URLs
- Email Admin: https://mail.yourdomain.com
- Git: https://git.yourdomain.com
- Pi-hole: http://10.10.0.1:8080/admin (VPN required)

### Manage Sites
```bash
# Allow a website
pihole -w domain.com

# Block a website
pihole -b domain.com

# List blocked/allowed
pihole -b -l
pihole -w -l
```

### Add New Employee
```bash
bash 03-add-employee.sh
```

### Check All Services
```bash
bash 05-manage.sh status
```

## Key Files on VPS

| File | Purpose |
|------|---------|
| `/etc/wireguard/wg0.conf` | WireGuard VPN config |
| `/opt/mailcow-dockerized/` | Mailcow installation |
| `/opt/mailcow-dockerized/data/conf/nginx/gitea.conf` | Nginx proxy for Gitea |
| `/opt/gitea/docker-compose.yml` | Gitea config |
| `/etc/pihole/pihole.toml` | Pi-hole config |
| `/root/employee*_vpn.conf` | Employee VPN configs |

## Troubleshooting

### Gitea shows Mailcow content
The Nginx config for Gitea must be:
- Located at: `/opt/mailcow-dockerized/data/conf/nginx/gitea.conf`
- NOT in `site.d/` subdirectory
- NOT named `.conf.active` - must be `.conf`
- Use `proxy_pass http://gitea:3000` (Docker DNS, not IP)
- Gitea must be on Mailcow's Docker network

Fix:
```bash
cd /opt/mailcow-dockerized
docker compose exec nginx-mailcow nginx -s reload
```

### Employee can't connect to VPN
1. Check WireGuard is running: `wg show`
2. Check employee peer is added: `grep -A3 "Peer" /etc/wireguard/wg0.conf`
3. Check firewall allows WireGuard: `ufw status | grep 51820`

### Services won't start after reboot
```bash
systemctl enable wg-quick@wg0
systemctl enable docker
cd /opt/mailcow-dockerized && docker compose up -d
cd /opt/gitea && docker compose up -d
```
