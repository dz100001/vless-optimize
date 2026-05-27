#!/bin/bash

# ============================================================
# Script Tối Ưu VPS VLESS (Hỗ trợ v2node + V2bX)
# Phiên bản: 2.1
# GitHub: https://github.com/dz100001/vless-optimize
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_LINK="https://github.com/dz100001/vless-optimize"

echo -e "${GREEN}=========================================="
echo -e "   SCRIPT TỐI ƯU VPS VLESS (v2node / V2bX)"
echo -e "   Phiên bản 2.1"
echo -e "==========================================${NC}"
echo -e "${BLUE}GitHub: $GITHUB_LINK${NC}\n"

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Vui lòng chạy script với quyền root (sudo)!${NC}"
    exit 1
fi

# Tự động phát hiện backend
if [ -f /etc/v2node/config.json ]; then
    BACKEND="v2node"
    CONFIG_FILE="/etc/v2node/config.json"
    SERVICE_NAME="v2node"
    RESTART_CMD="v2node restart"
elif [ -f /etc/V2bX/config.json ]; then
    BACKEND="V2bX"
    CONFIG_FILE="/etc/V2bX/config.json"
    SERVICE_NAME="V2bX"
    RESTART_CMD="systemctl restart V2bX"
else
    echo -e "${RED}Không tìm thấy config của v2node hoặc V2bX!${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/8] Đang phát hiện backend...${NC}"
echo -e "${GREEN}✓ Phát hiện: $BACKEND${NC}"

# Cài đặt công cụ
apt update -y >/dev/null 2>&1
apt install -y jq htop btop curl wget logrotate >/dev/null 2>&1

# Tối ưu sysctl
cat > /etc/sysctl.d/99-vless-optimize.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.somaxconn = 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
sysctl -p /etc/sysctl.d/99-vless-optimize.conf >/dev/null 2>&1

# Tăng file descriptor
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
ulimit -n 65535

# Tối ưu config
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

jq '
  if has("SniffEnabled") then .SniffEnabled = false else . end |
  if .Log then .Log.Level = "warning" else . end |
  if .Nodes then .Nodes |= map(if has("SniffEnabled") then .SniffEnabled = false else . end) else . end
' "$CONFIG_FILE" > /tmp/vless_config_temp.json && mv /tmp/vless_config_temp.json "$CONFIG_FILE"

# Logrotate
cat > /etc/logrotate.d/vless-node << 'EOF'
/var/log/v2node/*.log /var/log/V2bX/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0640 root adm
}
EOF

# Thêm cron restart
CRON_JOB="0 4 * * * $RESTART_CMD >/dev/null 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$RESTART_CMD"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
fi

# Restart
systemctl restart "$SERVICE_NAME" 2>/dev/null || $RESTART_CMD 2>/dev/null

echo -e "${GREEN}=========================================="
echo -e "           TỐI ƯU HOÀN TẤT"
echo -e "==========================================${NC}"
echo -e "${GREEN}Backend: $BACKEND${NC}"
echo -e "${YELLOW}Backup config: $BACKUP_FILE${NC}"
