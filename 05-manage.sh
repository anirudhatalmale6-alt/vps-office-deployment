#!/bin/bash
#############################################
# MANAGEMENT COMMANDS - Quick Reference
# Run as root on VPS
#############################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    echo -e "${BLUE}=============================================="
    echo "   VPS Management Commands"
    echo "=============================================="
    echo -e "${NC}"
    echo ""
    echo "Usage: bash 05-manage.sh <command>"
    echo ""
    echo "Commands:"
    echo "  status        - Show status of all services"
    echo "  allow <site>  - Allow a website (Pi-hole whitelist)"
    echo "  block <site>  - Block a website (Pi-hole blacklist)"
    echo "  list-blocked  - List blocked domains"
    echo "  list-allowed  - List allowed domains"
    echo "  restart-mail  - Restart Mailcow"
    echo "  restart-git   - Restart Gitea"
    echo "  restart-chat  - Restart Rocket.Chat"
    echo "  restart-vpn   - Restart WireGuard"
    echo "  restart-nginx - Restart Nginx (fix routing issues)"
    echo "  logs-mail     - View Mailcow logs"
    echo "  logs-git      - View Gitea logs"
    echo "  logs-chat     - View Rocket.Chat logs"
    echo "  add-employee  - Run employee setup script"
    echo ""
}

case "$1" in
    status)
        echo -e "${GREEN}=== WireGuard ===${NC}"
        wg show
        echo ""
        echo -e "${GREEN}=== Pi-hole ===${NC}"
        systemctl status pihole-FTL --no-pager | head -5
        echo ""
        echo -e "${GREEN}=== Mailcow ===${NC}"
        cd /opt/mailcow-dockerized && docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | head -20
        echo ""
        echo -e "${GREEN}=== Gitea ===${NC}"
        cd /opt/gitea && docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null
        echo ""
        echo -e "${GREEN}=== Rocket.Chat ===${NC}"
        cd /opt/rocketchat && docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null
        echo ""
        echo -e "${GREEN}=== Firewall ===${NC}"
        ufw status
        echo ""
        echo -e "${GREEN}=== Fail2Ban ===${NC}"
        fail2ban-client status
        echo ""
        echo -e "${GREEN}=== Disk Space ===${NC}"
        df -h / | tail -1
        echo ""
        echo -e "${GREEN}=== Memory ===${NC}"
        free -h | head -2
        ;;

    allow)
        if [ -z "$2" ]; then echo "Usage: bash 05-manage.sh allow <domain>"; exit 1; fi
        pihole -w "$2"
        echo -e "${GREEN}Allowed: $2${NC}"
        ;;

    block)
        if [ -z "$2" ]; then echo "Usage: bash 05-manage.sh block <domain>"; exit 1; fi
        pihole -b "$2"
        echo -e "${RED}Blocked: $2${NC}"
        ;;

    list-blocked)
        pihole -b -l
        ;;

    list-allowed)
        pihole -w -l
        ;;

    restart-mail)
        cd /opt/mailcow-dockerized && docker compose restart
        echo -e "${GREEN}Mailcow restarted${NC}"
        ;;

    restart-git)
        cd /opt/gitea && docker compose restart
        echo -e "${GREEN}Gitea restarted${NC}"
        ;;

    restart-chat)
        cd /opt/rocketchat && docker compose restart
        echo -e "${GREEN}Rocket.Chat restarted${NC}"
        ;;

    restart-vpn)
        systemctl restart wg-quick@wg0
        wg show
        echo -e "${GREEN}WireGuard restarted${NC}"
        ;;

    restart-nginx)
        cd /opt/mailcow-dockerized && docker compose restart nginx-mailcow
        echo -e "${GREEN}Nginx restarted${NC}"
        ;;

    logs-mail)
        cd /opt/mailcow-dockerized && docker compose logs --tail 50
        ;;

    logs-git)
        cd /opt/gitea && docker compose logs --tail 50
        ;;

    logs-chat)
        cd /opt/rocketchat && docker compose logs --tail 50
        ;;

    add-employee)
        bash "$(dirname "$0")/03-add-employee.sh"
        ;;

    *)
        show_help
        ;;
esac
