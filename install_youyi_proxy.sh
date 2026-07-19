#!/bin/bash
# ==============================================================================
# Youyi Reverse Proxy for V2Board v2.4
# - Hỗ trợ 2 chế độ: Chỉ mở Subscribe hoặc Full Proxy
# - Tối ưu cho V2Board / Xboard
# - Tự động mở firewall
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} YOUYI REVERSE PROXY FOR V2BOARD v2.4${NC}"
echo -e "${GREEN}========================================${NC}\n"

# ================== HỎI THÔNG TIN ==================
read -p "Nhập IP Backend (VPS gốc chạy V2Board): " BACKEND_IP
while [[ -z "$BACKEND_IP" ]]; do
    echo -e "${RED}IP không được để trống!${NC}"
    read -p "Nhập IP Backend (VPS gốc chạy V2Board): " BACKEND_IP
done

read -p "Nhập Port Backend (mặc định: 6666): " BACKEND_PORT
BACKEND_PORT="${BACKEND_PORT:-6666}"

read -p "Nhập Port Proxy (mặc định: 36868): " PROXY_PORT
PROXY_PORT="${PROXY_PORT:-36868}"

# ================== CHỌN CHẾ ĐỘ ==================
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} CHỌN CHẾ ĐỘ PROXY${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${GREEN}1.${NC} Chỉ cho phép /api/v1/client/subscribe?token=...  ${YELLOW}(Khuyến nghị - Ẩn panel)${NC}"
echo -e "${GREEN}2.${NC} Cho phép tất cả đường dẫn                     ${YELLOW}(Full Reverse Proxy)${NC}"
echo ""

while true; do
    read -p "Chọn chế độ [1/2]: " mode
    case "$mode" in
        1)
            PROXY_MODE="subscribe"
            echo -e "${GREEN}→ Đã chọn: Chỉ mở Subscription${NC}"
            break
            ;;
        2)
            PROXY_MODE="full"
            echo -e "${YELLOW}→ Đã chọn: Full Reverse Proxy${NC}"
            break
            ;;
        *)
            echo "Vui lòng chọn 1 hoặc 2."
            ;;
    esac
done

echo ""
read -p "Tiếp tục cài đặt? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Đã hủy."
    exit 0
fi

echo -e "\n${YELLOW}=> Đang cài đặt...${NC}"

# 1. Cài Nginx
echo " [1/7] Cập nhật và cài Nginx..."
sudo apt update -y > /dev/null 2>&1
sudo apt install -y nginx curl > /dev/null 2>&1

# 2. Dọn dẹp cấu hình cũ
echo " [2/7] Dọn dẹp cấu hình xung đột..."
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
sudo rm -f /etc/nginx/sites-enabled/youyi* 2>/dev/null || true
sudo rm -f /etc/nginx/conf.d/youyi* 2>/dev/null || true

# 3. Mở Firewall
echo " [3/7] Cấu hình Firewall cho port ${PROXY_PORT}..."
if command -v ufw >/dev/null 2>&1; then
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow ${PROXY_PORT}/tcp comment 'Youyi V2Board Proxy' > /dev/null 2>&1 || true
        sudo ufw reload > /dev/null 2>&1 || true
        echo " ✓ Đã mở port ${PROXY_PORT} trong UFW"
    else
        echo " ℹ UFW đang tắt"
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
        sudo firewall-cmd --permanent --add-port=${PROXY_PORT}/tcp > /dev/null 2>&1 || true
        sudo firewall-cmd --reload > /dev/null 2>&1 || true
        echo " ✓ Đã mở port ${PROXY_PORT} trong Firewalld"
    fi
else
    echo " ℹ Không phát hiện UFW/Firewalld"
fi

# 4. Tạo cấu hình Nginx
echo " [4/7] Tạo cấu hình Nginx..."

if [[ "$PROXY_MODE" == "subscribe" ]]; then
    # Chế độ chỉ cho phép Subscription
    PROXY_CONFIG=$(cat << EOF
server {
    listen ${PROXY_PORT};
    server_name _;

    location / {
        # Chỉ cho phép đúng đường dẫn subscription của V2Board
        if (\$request_uri !~ "^/api/v1/client/subscribe\?token=") {
            return 404;
        }

        proxy_pass http://${BACKEND_IP}:${BACKEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        proxy_send_timeout 300s;
        proxy_redirect off;
    }
}
EOF
)
else
    # Chế độ Full Proxy
    PROXY_CONFIG=$(cat << EOF
server {
    listen ${PROXY_PORT};
    server_name _;

    location / {
        proxy_pass http://${BACKEND_IP}:${BACKEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        proxy_send_timeout 300s;
        proxy_redirect off;
    }
}
EOF
)
fi

echo "$PROXY_CONFIG" | sudo tee /etc/nginx/conf.d/youyi-proxy.conf > /dev/null

# 5. Kiểm tra cấu hình
echo " [5/7] Kiểm tra cấu hình Nginx..."
if ! sudo nginx -t; then
    echo -e "${RED}❌ Lỗi cấu hình Nginx!${NC}"
    exit 1
fi

# 6. Khởi động lại Nginx
echo " [6/7] Khởi động lại Nginx..."
sudo systemctl enable nginx > /dev/null 2>&1
sudo systemctl restart nginx

# 7. Hoàn tất
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CÀI ĐẶT THÀNH CÔNG!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Backend     : ${YELLOW}http://${BACKEND_IP}:${BACKEND_PORT}${NC}"
echo -e "Proxy Port  : ${YELLOW}${PROXY_PORT}${NC}"
echo -e "Config      : /etc/nginx/conf.d/youyi-proxy.conf"

if [[ "$PROXY_MODE" == "subscribe" ]]; then
    echo -e "Chế độ      : ${GREEN}Chỉ mở Subscription (Khuyến nghị)${NC}"
    echo -e "             Chỉ cho phép: /api/v1/client/subscribe?token=..."
else
    echo -e "Chế độ      : ${YELLOW}Full Reverse Proxy${NC}"
    echo -e "             Cho phép tất cả đường dẫn"
fi

echo -e "\n${YELLOW}=== HƯỚNG DẪN TEST ===${NC}"
if [[ "$PROXY_MODE" == "subscribe" ]]; then
    echo -e "Test thành công:"
    echo -e " ${CYAN}curl \"http://127.0.0.1:${PROXY_PORT}/api/v1/client/subscribe?token=your_token\"${NC}"
    echo -e "Test bị chặn:"
    echo -e " ${CYAN}curl http://127.0.0.1:${PROXY_PORT}/${NC}"
else
    echo -e "Test:"
    echo -e " ${CYAN}curl http://127.0.0.1:${PROXY_PORT}/${NC}"
fi

echo -e "\n${RED}⚠️ LƯU Ý:${NC}"
echo "1. Nhớ mở port ${PROXY_PORT} trên Security Group / Firewall của nhà cung cấp VPS"
echo "2. Nếu dùng chế độ 1, link subscription sẽ là:"
echo "   http://IP_PROXY:${PROXY_PORT}/api/v1/client/subscribe?token=xxxxx"
echo ""
echo -e "${GREEN}Script đã tự động mở port trong UFW/Firewalld (nếu đang bật).${NC}"
