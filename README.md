#!/bin/bash

# ============================================================
# Script Tối Ưu VPS VLESS (Hỗ trợ v2node + V2bX)
# Phiên bản: 2.1
# GitHub: https://github.com/YOUR_USERNAME/vless-optimize
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_LINK="https://github.com/YOUR_USERNAME/vless-optimize"

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

# ============================================================
# TỰ ĐỘNG PHÁT HIỆN v2node HOẶC V2bX
# ============================================================
echo -e "${YELLOW}[1/8] Đang phát hiện backend...${NC}"

if [ -f /etc/v2node/config.json ]; then
    BACKEND="v2node"
    CONFIG_FILE="/etc/v2node/config.json"
    SERVICE_NAME="v2node"
    RESTART_CMD="v2node restart"
    echo -e "${GREEN}✓ Phát hiện: v2node${NC}"
elif [ -f /etc/V2bX/config.json ]; then
    BACKEND="V2bX"
    CONFIG_FILE="/etc/V2bX/config.json"
    SERVICE_NAME="V2bX"
    RESTART_CMD="systemctl restart V2bX"
    echo -e "${GREEN}✓ Phát hiện: V2bX${NC}"
else
    echo -e "${RED}Không tìm thấy config của v2node hoặc V2bX!${NC}"
    exit 1
fi

echo -e "${BLUE}→ Sử dụng config: $CONFIG_FILE${NC}"

# Cài đặt công cụ
echo -e "${YELLOW}[2/8] Đang cài đặt các công cụ cần thiết...${NC}"
apt update -y >/dev/null 2>&1
apt install -y jq htop btop curl wget logrotate >/dev/null 2>&1
echo -e "${GREEN}✓ Đã cài đặt jq, htop, btop, logrotate${NC}"

# 1. Tối ưu sysctl
echo -e "${YELLOW}[3/8] Đang tối ưu sysctl (BBR + Network)...${NC}"
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

# 2. Tăng giới hạn file descriptor
echo -e "${YELLOW}[4/8] Đang tăng giới hạn file descriptor...${NC}"
if ! grep -q "65535" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf << 'EOF'

# VLESS Optimization
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
fi
ulimit -n 65535
echo -e "${GREEN}✓ Đã tăng giới hạn file descriptor${NC}"

# 3. Tối ưu config v2node / V2bX
echo -e "${YELLOW}[5/8] Đang tối ưu cấu hình $BACKEND...${NC}"
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo -e "${GREEN}✓ Đã backup config tại: $BACKUP_FILE${NC}"

jq '
  if has("SniffEnabled") then .SniffEnabled = false else . end |
  if .Log then .Log.Level = "warning" else . end |
  if .Nodes then .Nodes |= map(if has("SniffEnabled") then .SniffEnabled = false else . end) else . end
' "$CONFIG_FILE" > /tmp/vless_config_temp.json && mv /tmp/vless_config_temp.json "$CONFIG_FILE"

echo -e "${GREEN}✓ Đã tắt SniffEnabled và đặt Log Level = warning${NC}"

# 4. Thiết lập Logrotate
echo -e "${YELLOW}[6/8] Đang thiết lập logrotate...${NC}"
cat > /etc/logrotate.d/vless-node << 'EOF'
/var/log/v2node/*.log /var/log/V2bX/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0640 root adm
    sharedscripts
    postrotate
        systemctl reload v2node V2bX > /dev/null 2>&1 || true
    endscript
}
EOF
echo -e "${GREEN}✓ Đã thiết lập logrotate${NC}"

# 5. Thêm Cron Restart hàng ngày
echo -e "${YELLOW}[7/8] Đang thêm cron restart hàng ngày...${NC}"
CRON_JOB="0 4 * * * $RESTART_CMD >/dev/null 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$RESTART_CMD"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}✓ Đã thêm cron restart lúc 4:00 sáng hàng ngày${NC}"
else
    echo -e "${YELLOW}→ Cron restart đã tồn tại.${NC}"
fi

# 6. Restart service
echo -e "${YELLOW}[8/8] Đang khởi động lại $BACKEND...${NC}"
systemctl restart "$SERVICE_NAME" 2>/dev/null || $RESTART_CMD 2>/dev/null || echo -e "${YELLOW}Vui lòng chạy thủ công: $RESTART_CMD${NC}"
echo -e "${GREEN}✓ Đã restart $BACKEND${NC}"

# Kết quả
echo -e "\n${GREEN}=========================================="
echo -e "           TỐI ƯU HOÀN TẤT"
echo -e "==========================================${NC}"
echo -e "${GREEN}Backend:${NC} $BACKEND"
echo -e "${GREEN}GitHub:${NC} $GITHUB_LINK"
echo -e "\n${YELLOW}Các tối ưu đã thực hiện:${NC}"
echo "  • Bật TCP BBR + Network tuning"
echo "  • Tăng giới hạn file descriptor"
echo "  • Tắt SniffEnabled"
echo "  • Log Level = warning"
echo "  • Logrotate + Cron restart hàng ngày"
echo -e "\n${BLUE}File backup:${NC} $BACKUP_FILE"
echo -e "${BLUE}Kiểm tra cron:${NC} crontab -l"
echo -e "${BLUE}Xem tài nguyên:${NC} btop"
