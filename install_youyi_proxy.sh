#!/bin/bash
# ==============================================================================
# Youyi Reverse Proxy Installer (Fixed Version)
# Đã sửa lỗi: duplicate default server
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   YOUYI REVERSE PROXY INSTALLER${NC}"
echo -e "${GREEN}========================================${NC}\n"

# ================== HỎI THÔNG TIN ==================
read -p "Nhập IP Backend (VPS gốc): " BACKEND_IP
while [[ -z "$BACKEND_IP" ]]; do
    echo -e "${RED}IP không được để trống!${NC}"
    read -p "Nhập IP Backend (VPS gốc): " BACKEND_IP
done

read -p "Nhập Port Backend (mặc định: 6666): " BACKEND_PORT
BACKEND_PORT="${BACKEND_PORT:-6666}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "Backend IP   : ${YELLOW}${BACKEND_IP}${NC}"
echo -e "Backend Port : ${YELLOW}${BACKEND_PORT}${NC}"
echo -e "${CYAN}========================================${NC}\n"

read -p "Tiếp tục cài đặt? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Đã hủy."
    exit 0
fi

echo -e "\n${YELLOW}=> Đang cài đặt...${NC}"

# 1. Cài Nginx
echo "   [1/6] Cập nhật và cài Nginx..."
sudo apt update -y > /dev/null 2>&1
sudo apt install -y nginx curl > /dev/null 2>&1

# 2. Dọn dẹp triệt để (QUAN TRỌNG - sửa lỗi duplicate)
echo "   [2/6] Dọn dẹp cấu hình xung đột..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-enabled/youyi-proxy.conf 2>/dev/null || true
sudo rm -f /etc/nginx/conf.d/youyi-proxy.conf 2>/dev/null || true

# Xóa tất cả các file có default_server trong sites-enabled (nếu có)
sudo find /etc/nginx/sites-enabled -type f -exec grep -l "default_server" {} + 2>/dev/null | xargs sudo rm -f || true

# 3. Tạo config mới (ghi vào conf.d - đúng chuẩn)
echo "   [3/6] Tạo cấu hình Nginx..."
sudo tee /etc/nginx/conf.d/youyi-proxy.conf > /dev/null << EOF
server {
    listen 80;
    server_name _;

    location / {
        if (\$http_user_agent !~ "YouyiApp") {
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
        proxy_redirect off;
    }
}
EOF

# 4. Kiểm tra cấu hình
echo "   [4/6] Kiểm tra cấu hình Nginx..."
if ! sudo nginx -t; then
    echo -e "${RED}❌ Lỗi cấu hình Nginx!${NC}"
    exit 1
fi

# 5. Restart Nginx
echo "   [5/6] Khởi động lại Nginx..."
sudo systemctl enable nginx > /dev/null 2>&1
sudo systemctl restart nginx

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CÀI ĐẶT THÀNH CÔNG!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Backend : ${YELLOW}http://${BACKEND_IP}:${BACKEND_PORT}${NC}"
echo -e "Config  : /etc/nginx/conf.d/youyi-proxy.conf"
