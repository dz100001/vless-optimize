#!/bin/bash

# ============================================================
# Script Tối Ưu VPS VLESS - Phiên bản 2.8 (Max Optimization)
# Dành cho VPS 1CPU 1GB RAM chạy cho khách Trung Quốc
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo -e "   SCRIPT TỐI ƯU VPS VLESS v2.8 (Max)"
echo -e "==========================================${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Cần chạy với quyền root!${NC}"
    exit 1
fi

# ==================== 1. CHỌN BACKEND ====================
echo -e "\n${YELLOW}Bạn đang dùng backend nào?${NC}"
echo "1) V2bX"
echo "2) v2node"
read -p "Chọn (1 hoặc 2): " BACKEND_CHOICE

if [ "$BACKEND_CHOICE" = "1" ]; then
    BACKEND="V2bX"
    CONFIG_FILE="/etc/V2bX/config.json"
    SERVICE_NAME="V2bX"
    RESTART_CMD="systemctl restart V2bX"
elif [ "$BACKEND_CHOICE" = "2" ]; then
    BACKEND="v2node"
    CONFIG_FILE="/etc/v2node/config.json"
    SERVICE_NAME="v2node"
    RESTART_CMD="v2node restart"
else
    echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; exit 1
fi
echo -e "${GREEN}✓ Backend: $BACKEND${NC}"

# ==================== 2. CHỌN LOẠI VLESS ====================
echo -e "\n${YELLOW}Bạn muốn tối ưu cho loại VLESS nào?${NC}"
echo "1) VLESS + Reality + Vision (Khuyến nghị mạnh)"
echo "2) VLESS + WebSocket"
read -p "Chọn (1 hoặc 2): " VLESS_CHOICE

if [ "$VLESS_CHOICE" = "1" ]; then
    VLESS_TYPE="Reality"
    echo -e "${GREEN}✓ Đã chọn Reality + Vision (Tốt nhất cho Trung Quốc)${NC}"
elif [ "$VLESS_CHOICE" = "2" ]; then
    VLESS_TYPE="WebSocket"
    echo -e "${RED}⚠️ CẢNH BÁO: WebSocket tốn RAM + CPU nhiều hơn Reality khá nhiều.${NC}"
    echo -e "${RED}   Với VPS 1GB RAM + 200 user, Reality sẽ ổn định hơn rất nhiều.${NC}"
else
    echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; exit 1
fi

# ==================== 3. TẠO ZRAM hoặc SWAP ====================
echo -e "\n${YELLOW}Bạn muốn dùng Zram hay Swap thông thường?${NC}"
echo "1) Zram (Khuyến nghị cho RAM thấp)"
echo "2) Swap thông thường"
echo "3) Không tạo"
read -p "Chọn (1-3): " SWAP_TYPE

if [ "$SWAP_TYPE" = "1" ]; then
    echo -e "${YELLOW}Đang cài zram...${NC}"
    apt install -y zram-tools >/dev/null 2>&1
    systemctl enable --now zramswap.service 2>/dev/null || true
    echo -e "${GREEN}✓ Đã bật Zram${NC}"
elif [ "$SWAP_TYPE" = "2" ]; then
    echo -e "\n${YELLOW}Chọn dung lượng Swap:${NC}"
    echo "1) 1GB   2) 2GB (Khuyến nghị)   3) 4GB   4) 8GB"
    read -p "Chọn (1-4): " SWAP_SIZE_CHOICE
    case $SWAP_SIZE_CHOICE in 1) SIZE=1 ;; 2) SIZE=2 ;; 3) SIZE=4 ;; 4) SIZE=8 ;; *) SIZE=2 ;; esac

    SWAPFILE="/swapfile"
    [ -f "$SWAPFILE" ] && swapoff $SWAPFILE 2>/dev/null && rm -f $SWAPFILE
    fallocate -l ${SIZE}G $SWAPFILE 2>/dev/null || dd if=/dev/zero of=$SWAPFILE bs=1M count=$((SIZE*1024)) status=progress
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon $SWAPFILE
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab 2>/dev/null
    sysctl -w vm.swappiness=10 >/dev/null 2>&1
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo -e "${GREEN}✓ Đã tạo Swap ${SIZE}GB${NC}"
fi

# ==================== 4. ĐỔI CỔNG SSH ====================
echo -e "\n${YELLOW}Bạn có muốn đổi cổng SSH sang 2901 không?${NC}"
echo "1) Có (Khuyến nghị)"
echo "2) Không"
read -p "Chọn (1 hoặc 2): " SSH_CHOICE

if [ "$SSH_CHOICE" = "1" ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
    sed -i 's/^#*Port .*/Port 2901/' /etc/ssh/sshd_config
    if command -v ufw &> /dev/null; then
        ufw allow 2901/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    fi
    echo -e "${GREEN}✓ Đã đổi cổng SSH sang 2901${NC}"
fi

# ==================== 5. TỐI ƯU HỆ THỐNG ====================
echo -e "\n${YELLOW}[1/5] Đang tối ưu hệ thống...${NC}"

# Tắt IPv6
cat > /etc/sysctl.d/99-disable-ipv6.conf << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1

# Sysctl mạnh
cat > /etc/sysctl.d/99-vless-optimize.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 32768
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 300
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608
net.netfilter.nf_conntrack_max = 131072
vm.swappiness = 10
EOF
sysctl -p /etc/sysctl.d/99-vless-optimize.conf >/dev/null 2>&1

cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
ulimit -n 65535

# Tắt journald
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-vless.conf << 'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=50M
EOF
systemctl restart systemd-journald 2>/dev/null || true

echo -e "${GREEN}✓ Đã tối ưu sysctl + IPv6 + TCP Fast Open${NC}"

# ==================== 6. TỐI ƯU CONFIG ====================
echo -e "${YELLOW}[2/5] Đang tối ưu cấu hình $BACKEND ($VLESS_TYPE)...${NC}"
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

jq '
  if has("SniffEnabled") then .SniffEnabled = false else . end |
  if .Log then .Log.Level = "error" else . end |
  if .Nodes then .Nodes |= map(if has("SniffEnabled") then .SniffEnabled = false else . end) else . end
' "$CONFIG_FILE" > /tmp/vless_config_temp.json && mv /tmp/vless_config_temp.json "$CONFIG_FILE"

echo -e "${GREEN}✓ Đã đặt Log Level = error + tắt Sniffing${NC}"

# ==================== 7. LOGROTATE + CRON ====================
echo -e "${YELLOW}[3/5] Đang thiết lập logrotate + cron restart...${NC}"
cat > /etc/logrotate.d/vless-node << 'EOF'
/var/log/v2node/*.log /var/log/V2bX/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    create 0640 root adm
}
EOF

CRON_JOB="0 4 * * * $RESTART_CMD >/dev/null 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$RESTART_CMD"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
fi

# ==================== 8. RESTART ====================
echo -e "${YELLOW}[4/5] Đang khởi động lại dịch vụ...${NC}"
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
systemctl restart "$SERVICE_NAME" 2>/dev/null || $RESTART_CMD 2>/dev/null

echo -e "\n${GREEN}=========================================="
echo -e "           TỐI ƯU HOÀN TẤT (v2.8)"
echo -e "==========================================${NC}"

echo -e "${GREEN}Backend       : $BACKEND${NC}"
echo -e "${GREEN}Loại VLESS    : $VLESS_TYPE${NC}"
echo -e "${GREEN}Log Level     : error${NC}"
echo -e "${GREEN}IPv6          : Disabled${NC}"
echo -e "${GREEN}TCP Fast Open : Enabled${NC}"

if [ "$SWAP_TYPE" = "1" ]; then echo -e "${GREEN}Memory        : Zram enabled${NC}"; fi
if [ "$SWAP_TYPE" = "2" ]; then echo -e "${GREEN}Swap          : ${SIZE}GB${NC}"; fi
if [ "$SSH_CHOICE" = "1" ]; then echo -e "${GREEN}Cổng SSH mới  : 2901${NC}"; fi

echo -e "${YELLOW}Backup config : $BACKUP_FILE${NC}"

echo -e "\n${BLUE}Khuyến nghị cuối cùng:${NC}"
if [ "$VLESS_TYPE" = "Reality" ]; then
    echo "→ Reality + Vision là lựa chọn tối ưu nhất cho khách Trung Quốc hiện nay."
else
    echo "→ WebSocket đang dùng nhiều tài nguyên hơn. Nên cân nhắc chuyển sang Reality."
fi

echo -e "\n${RED}Lưu ý quan trọng:${NC}"
echo "- Với 1GB RAM + 200 user, Reality sẽ ổn định và mượt hơn WebSocket rất nhiều."
echo "- Hãy test kỹ trước khi đưa vào sử dụng thực tế."
