#!/bin/bash
# ==============================================================================
# Youyi Reverse Proxy Installer (Interactive Version)
# Script sẽ hỏi bạn các thông tin cần thiết để cài đặt
# ==============================================================================

set -euo pipefail

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   YOUYI REVERSE PROXY INSTALLER${NC}"
echo -e "${GREEN}========================================${NC}\n"

# ================== HỎI THÔNG TIN ==================

# Hỏi Backend IP
read -p "Nhập IP Backend (VPS gốc): " BACKEND_IP
while [[ -z "$BACKEND_IP" ]]; do
    echo -e "${RED}IP không được để trống!${NC}"
    read -p "Nhập IP Backend (VPS gốc): " BACKEND_IP
done

# Hỏi Backend Port
read -p "Nhập Port Backend (mặc định: 6666): " BACKEND_PORT
BACKEND_PORT="${BACKEND_PORT:-6666}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}   THÔNG TIN BẠN ĐÃ NHẬP:${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "Backend IP   : ${YELLOW}${BACKEND_IP}${NC}"
echo -e "Backend Port : ${YELLOW}${BACKEND_PORT}${NC}"
echo -e "${CYAN}========================================${NC}\n"

# Xác nhận trước khi cài
read -p "Bạn có muốn tiếp tục cài đặt với thông tin trên? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${RED}Đã hủy cài đặt.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}=> Bắt đầu cài đặt...${NC}"

# 1. Cập nhật hệ thống
echo "   [1/5] Cập nhật hệ thống và cài Nginx..."
sudo apt update -y > /dev/null 2>&1
sudo apt install -y nginx curl > /dev/null 2>&1

# 2. Dọn dẹp config cũ
echo "   [2/5] Dọn dẹp cấu hình mặc định..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/conf.d/youyi-proxy.conf 2>/dev/null || true

# 3. Tạo file cấu hình
echo "   [3/5] Tạo file cấu hình Nginx..."
sudo tee /etc/nginx/conf.d/youyi-proxy.conf > /dev/null << EOF
server {
    listen 80 default_server;
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
echo "   [4/5] Kiểm tra cú pháp Nginx..."
if ! sudo nginx -t; then
    echo -e "${RED}❌ Lỗi cấu hình Nginx!${NC}"
    exit 1
fi

# 5. Khởi động Nginx
echo "   [5/5] Khởi động lại Nginx..."
sudo systemctl enable nginx > /dev/null 2>&1
sudo systemctl restart nginx

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CÀI ĐẶT THÀNH CÔNG!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Backend hiện tại : ${YELLOW}http://${BACKEND_IP}:${BACKEND_PORT}${NC}"
echo -e "Config file      : /etc/nginx/conf.d/youyi-proxy.conf"
echo -e "\nBạn có thể kiểm tra bằng cách truy cập VPS với User-Agent YouyiApp."
