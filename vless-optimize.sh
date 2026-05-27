#!/bin/bash

# ============================================================
# Script Tối Ưu VPS VLESS (Hỗ trợ v2node + V2bX)
# Phiên bản: 2.3 - Thêm đổi cổng SSH sang 2901
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
echo -e "   Phiên bản 2.3 - Đổi cổng SSH sang 2901"
echo -e "==========================================${NC}"
echo -e "${BLUE}GitHub: $GITHUB_LINK${NC}\n"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Vui lòng chạy script với quyền root (sudo)!${NC}"
    exit 1
fi

# ============================================================
# PHÁT HIỆN BACKEND
# ============================================================
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

echo -e "${YELLOW}[1/9] Đang phát hiện backend...${NC}"
echo -e "${GREEN}✓ Phát hiện: $BACKEND${NC}"

# ============================================================
# CÀI ĐẶT CÔNG CỤ
# ============================================================
echo -e "${YELLOW}[2/9] Đang cài đặt các công cụ cần thiết...${NC}"

apt-get update -y >/dev/null 2>&1 || apt update -y >/dev/null 2>&1

if ! command -v jq &> /dev/null; then
    apt-get install -y jq 2>/dev/null || apt install -y jq 2>/dev/null
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Lỗi: Không thể cài jq. Vui lòng chạy: apt install jq${NC}"
    exit 1
fi

apt install -y htop btop curl wget logrotate ufw -y >/dev/null 2>&1
echo -e "${GREEN}✓ Đã cài đặt đầy đủ công cụ${NC}"

# ============================================================
# TỐI ƯU HỆ THỐNG
# ============================================================
echo -e "${YELLOW}[3/9] Đang tối ưu sysctl (BBR + Network)...${NC}"
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
echo -e "${GREEN}✓ Đã áp dụng sysctl tối ưu${NC}"

echo -e "${YELLOW}[4/9] Đang tăng giới hạn file descriptor...${NC}"
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
ulimit -n 65535
echo -e "${GREEN}✓ Đã tăng giới hạn file descriptor${NC}"

# ============================================================
# TỐI ƯU CONFIG V2bX / v2node
# ============================================================
echo -e "${YELLOW}[5/9] Đang tối ưu cấu hình $BACKEND...${NC}"
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

jq '
  if has("SniffEnabled") then .SniffEnabled = false else . end |
  if .Log then .Log.Level = "warning" else . end |
  if .Nodes then .Nodes |= map(if has("SniffEnabled") then .SniffEnabled = false else . end) else . end
' "$CONFIG_FILE" > /tmp/vless_config_temp.json && mv /tmp/vless_config_temp.json "$CONFIG_FILE"

echo -e "${GREEN}✓ Đã tắt SniffEnabled và đặt Log Level = warning${NC}"

# ============================================================
# ĐỔI CỔNG SSH SANG 2901 (MỚI)
# ============================================================
echo -e "${YELLOW}[6/9] Đang đổi cổng SSH sang 2901...${NC}"

# Backup sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)

# Đổi cổng SSH
sed -i 's/^#*Port .*/Port 2901/' /etc/ssh/sshd_config

# Cho phép cổng 2901 qua UFW
if command -v ufw &> /dev/null; then
    ufw allow 2901/tcp >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
    echo -e "${GREEN}✓ Đã cho phép cổng 2901 qua UFW${NC}"
fi

echo -e "${GREEN}✓ Đã đổi cổng SSH sang 2901${NC}"

# ============================================================
# LOGROTATE + CRON RESTART
# ============================================================
echo -e "${YELLOW}[7/9] Đang thiết lập logrotate...${NC}"
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
echo -e "${GREEN}✓ Đã thiết lập logrotate${NC}"

echo -e "${YELLOW}[8/9] Đang thêm cron restart hàng ngày (4h sáng)...${NC}"
CRON_JOB="0 4 * * * $RESTART_CMD >/dev/null 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$RESTART_CMD"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}✓ Đã thêm cron restart${NC}"
else
    echo -e "${YELLOW}→ Cron restart đã tồn tại${NC}"
fi

# ============================================================
# RESTART DỊCH VỤ
# ============================================================
echo -e "${YELLOW}[9/9] Đang khởi động lại dịch vụ...${NC}"
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
systemctl restart "$SERVICE_NAME" 2>/dev/null || $RESTART_CMD 2>/dev/null

echo -e "\n${GREEN}=========================================="
echo -e "           TỐI ƯU HOÀN TẤT"
echo -e "==========================================${NC}"
echo -e "${GREEN}Backend: $BACKEND${NC}"
echo -e "${GREEN}Cổng SSH mới: 2901${NC}"
echo -e "${YELLOW}Backup SSH config: /etc/ssh/sshd_config.bak.*${NC}"
echo -e "${BLUE}GitHub: $GITHUB_LINK${NC}"
echo -e "\n${YELLOW}Lưu ý: Hãy test kết nối SSH bằng cổng 2901 trước khi thoát phiên hiện tại!${NC}"
