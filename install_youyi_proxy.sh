#!/bin/bash
# ==============================================================================
# Youyi Reverse Proxy Installer v2.3
# - Reverse Proxy thuần (cho phép tất cả đường dẫn)
# - Hỗ trợ port 36868 (hoặc port tùy chỉnh)
# - Tự động mở firewall (UFW/Firewalld)
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} YOUYI REVERSE PROXY INSTALLER v2.3${NC}"
echo -e "${GREEN}========================================${NC}\n"

# ================== HỎI THÔNG TIN ==================
read -p "Nhập IP Backend (VPS gốc): " BACKEND_IP
while [[ -z "$BACKEND_IP" ]]; do
    echo -e "${RED}IP không được để trống!${NC}"
    read -p "Nhập IP Backend (VPS gốc): " BACKEND_IP
done

read -p "Nhập Port Backend (mặc định: 6666): " BACKEND_PORT
BACKEND_PORT="${BACKEND_PORT:-6666}"

read -p "Nhập Port CDN/Proxy (mặc định: 36868): " PROXY_PORT
PROXY_PORT="${PROXY_PORT:-36868}"

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

# 2. Dọn dẹp cấu hình
echo " [2/7] Dọn dẹp cấu hình xung đột..."
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
sudo rm -f /etc/nginx/sites-enabled/youyi* 2>/dev/null || true
sudo rm -f /etc/nginx/conf.d/youyi* 2>/dev/null || true

# 3. Mở port Firewall
echo " [3/7] Cấu hình Firewall cho port ${PROXY_PORT}..."
if command -v ufw >/dev/null 2>&1; then
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow ${PROXY_PORT}/tcp comment 'Youyi Reverse Proxy' > /dev/null 2>&1 || true
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

# 4. Tạo cấu hình Nginx (Reverse Proxy thuần - cho phép tất cả)
echo " [4/7] Tạo cấu hình Nginx..."
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
        proxy_redirect off;
    }
}
EOF
)

echo "$PROXY_CONFIG" | sudo tee /etc/nginx/conf.d/youyi-proxy.conf > /dev/null

# 5. Kiểm tra cấu hình
echo " [5/7] Kiểm tra cấu hình Nginx..."
if ! sudo nginx -t; then
    echo -e "${RED}❌ Lỗi cấu hình Nginx!${NC}"
    exit 1
fi

# 6. Restart Nginx
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
echo -e "Chế độ      : ${GREEN}Reverse Proxy thuần (cho phép tất cả đường dẫn)${NC}"

echo -e "\n${YELLOW}=== HƯỚNG DẪN TEST ===${NC}"
echo -e "Test:"
echo -e " ${CYAN}curl http://127.0.0.1:${PROXY_PORT}/${NC}"

echo -e "\n${RED}⚠️ LƯU Ý QUAN TRỌNG:${NC}"
echo "Nếu không truy cập được từ ngoài internet:"
echo " → Vào dashboard nhà cung cấp VPS mở port ${PROXY_PORT} (Security Group / Firewall)"
echo " Ví dụ: DigitalOcean, Hetzner, AWS, Linode, Vultr..."
echo ""
echo -e "${GREEN}Script đã tự động mở port trong UFW/Firewalld (nếu đang bật).${NC}"
