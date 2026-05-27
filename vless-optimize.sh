#!/bin/bash

# ============================================================
# Script Tối Ưu VPS VLESS - Phiên bản 2.6
# Thêm tính năng tạo Swap (1GB / 2GB / 4GB / 8GB)
# Tối ưu cho VPS 1CPU 1GB RAM (~200 user Trung Quốc)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo -e "   SCRIPT TỐI ƯU VPS VLESS v2.6"
echo -e "==========================================${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Cần chạy với quyền root!${NC}"
    exit 1
fi

# ==================== CHỌN BACKEND ====================
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

# ==================== CHỌN LOẠI VLESS ====================
echo -e "\n${YELLOW}Bạn muốn tối ưu cho loại VLESS nào?${NC}"
echo "1) VLESS + Reality + Vision (Khuyến nghị)"
echo "2) VLESS + WebSocket"
read -p "Chọn (1 hoặc 2): " VLESS_CHOICE

if [ "$VLESS_CHOICE" = "1" ]; then
    VLESS_TYPE="Reality"
elif [ "$VLESS_CHOICE" = "2" ]; then
    VLESS_TYPE="WebSocket"
else
    echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; exit 1
fi
echo -e "${GREEN}✓ Loại VLESS: $VLESS_TYPE${NC}"

# ==================== TẠO SWAP (MỚI) ====================
echo -e "\n${YELLOW}Bạn có muốn tạo Swap không? (Khuyến nghị cho VPS 1GB RAM)${NC}"
echo "1) Có"
echo "2) Không"
read -p "Chọn (1 hoặc 2): " SWAP_CHOICE

if [ "$SWAP_CHOICE" = "1" ]; then
    echo -e "\n${YELLOW}Chọn dung lượng Swap:${NC}"
    echo "1) 1GB"
    echo "2) 2GB (Khuyến nghị)"
    echo "3) 4GB"
    echo "4) 8GB"
    read -p "Chọn (1-4): " SWAP_SIZE_CHOICE

    case $SWAP_SIZE_CHOICE in
        1) SWAP_SIZE=1 ;;
        2) SWAP_SIZE=2 ;;
        3) SWAP_SIZE=4 ;;
        4) SWAP_SIZE=8 ;;
        *) SWAP_SIZE=2; echo -e "${YELLOW}Mặc định chọn 2GB${NC}" ;;
    esac

    SWAPFILE="/swapfile"
    if [ -f "$SWAPFILE" ]; then
        echo -e "${YELLOW}Swapfile đã tồn tại. Đang xóa cái cũ...${NC}"
        swapoff $SWAPFILE 2>/dev/null
        rm -f $SWAPFILE
    fi

    echo -e "${YELLOW}Đang tạo Swap ${SWAP_SIZE}GB...${NC}"
    fallocate -l ${SWAP_SIZE}G $SWAPFILE 2>/dev/null || dd if=/dev/zero of=$SWAPFILE bs=1M count=$((SWAP_SIZE*1024)) status=progress
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon $SWAPFILE

    # Thêm vào fstab
    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
    fi

    # Tối ưu swappiness cho proxy
    sysctl -w vm.swappiness=10 >/dev/null 2>&1
    echo "vm.swappiness=10" >> /etc/sysctl.conf

    echo -e "${GREEN}✓ Đã tạo Swap ${SWAP_SIZE}GB thành công${NC}"
else
    echo -e "${YELLOW}→ Bỏ qua tạo Swap${NC}"
fi

# ==================== TỐI ƯU HỆ THỐNG ====================
echo -e "\n${YELLOW}[1/7] Đang tối ưu hệ thống...${NC}"

# Tắt IPv6
cat > /etc/sysctl.d/99-disable-ipv6.conf << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1

# Sysctl tối ưu
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

# Tăng file descriptor
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
ulimit -n 65535

echo -e "${GREEN}✓ Đã tối ưu sysctl + IPv6 + TCP Fast Open${NC}"

# ==================== TỐI ƯU CONFIG ====================
echo -e "${YELLOW}[2/7] Đang tối ưu cấu hình $BACKEND...${NC}"
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

jq '
  if has("SniffEnabled") then .SniffEnabled = false else . end |
  if .Log then .Log.Level = "error" else . end |
  if .Nodes then .Nodes |= map(if has("SniffEnabled") then .SniffEnabled = false else . end) else . end
' "$CONFIG_FILE" > /tmp/vless_config_temp.json && mv /tmp/vless_config_temp.json "$CONFIG_FILE"

echo -e "${GREEN}✓ Đã đặt Log Level = error + tắt Sniffing${NC}"

# ==================== LOGROTATE + CRON ====================
echo -e "${YELLOW}[3/7] Đang thiết lập logrotate + cron restart...${NC}"
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

# Tắt journald
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-vless.conf << 'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=50M
EOF
systemctl restart systemd-journald

# ==================== RESTART ====================
echo -e "${YELLOW}[4/7] Đang khởi động lại dịch vụ...${NC}"
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
systemctl restart "$SERVICE_NAME" 2>/dev/null || $RESTART_CMD 2>/dev/null

echo -e "\n${GREEN}=========================================="
echo -e "           TỐI ƯU HOÀN TẤT (v2.6)"
echo -e "==========================================${NC}"
echo -e "${GREEN}Backend       : $BACKEND${NC}"
echo -e "${GREEN}Loại VLESS    : $VLESS_TYPE${NC}"
echo -e "${GREEN}Log Level     : error${NC}"
echo -e "${GREEN}IPv6          : Disabled${NC}"
echo -e "${GREEN}TCP Fast Open : Enabled${NC}"
if [ "$SWAP_CHOICE" = "1" ]; then
    echo -e "${GREEN}Swap          : ${SWAP_SIZE}GB${NC}"
fi
echo -e "${YELLOW}Backup config : $BACKUP_FILE${NC}"

echo -e "\n${BLUE}Khuyến nghị:${NC}"
if [ "$VLESS_TYPE" = "Reality" ]; then
    echo "→ Reality + Vision là lựa chọn tốt nhất cho khách Trung Quốc."
else
    echo "→ WebSocket đang tiêu tốn nhiều tài nguyên hơn. Nên cân nhắc chuyển sang Reality."
fi
