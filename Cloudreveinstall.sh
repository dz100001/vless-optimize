#!/bin/bash
# ==============================================
#   CÀI ĐẶT CLOUDREVE 3.8.3 - PHIÊN BẢN CẢI TIẾN
#   Tự động hiển thị tài khoản + mật khẩu chính xác
# ==============================================

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   BẮT ĐẦU CÀI ĐẶT CLOUDREVE NHANH    ${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. Chuẩn bị môi trường
echo -e "${YELLOW}[1/5] Đang chuẩn bị môi trường...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y wget curl awk > /dev/null 2>&1

# 2. Tải Cloudreve
echo -e "${YELLOW}[2/5] Đang tải Cloudreve 3.8.3...${NC}"
mkdir -p /opt/cloudreve
cd /opt/cloudreve || exit 1

wget -qO cloudreve.tar.gz https://github.com/cloudreve/Cloudreve/releases/download/3.8.3/cloudreve_3.8.3_linux_amd64.tar.gz
if [ $? -ne 0 ]; then
    echo -e "${RED}Lỗi tải file Cloudreve!${NC}"
    exit 1
fi

# 3. Giải nén
echo -e "${YELLOW}[3/5] Đang giải nén và cấp quyền...${NC}"
tar -zxvf cloudreve.tar.gz > /dev/null 2>&1
chmod +x ./cloudreve
rm -f cloudreve.tar.gz

# --- ĐIỂM QUAN TRỌNG: XÓA ĐÚNG THƯ MỤC DATA (Cloudreve 3.x dùng data/) ---
echo -e "${YELLOW}[4/5] Đang xóa dữ liệu cũ để tạo mật khẩu mới...${NC}"
systemctl stop cloudreve > /dev/null 2>&1 || true
rm -rf /opt/cloudreve/data 2>/dev/null || true
mkdir -p /opt/cloudreve/data

# 4. Chạy tạm để lấy mật khẩu (có chờ thông minh)
echo -e "${YELLOW}[5/5] Đang khởi tạo và trích xuất thông tin đăng nhập...${NC}"

./cloudreve > temp_init.log 2>&1 &
CLOUD_PID=$!

# Chờ tối đa 60 giây cho đến khi xuất hiện dòng mật khẩu
echo -e "${CYAN}    Đang chờ Cloudreve khởi tạo (tối đa 60 giây)...${NC}"
for i in {1..60}; do
    if grep -q "Admin password" temp_init.log 2>/dev/null; then
        echo -e "${GREEN}    ✓ Đã lấy được thông tin đăng nhập!${NC}"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo -e "${RED}    ⚠️ Hết thời gian chờ!${NC}"
    fi
done

kill -9 $CLOUD_PID >/dev/null 2>&1 || true
sleep 2

# === TRÍCH XUẤT TÀI KHOẢN & MẬT KHẨU (ĐÃ SỬA LỖI) ===
ADMIN_USER=$(grep -i "admin user name" temp_init.log | tail -1 | sed -E 's/.*name[[:space:]]*:[[:space:]]*([a-zA-Z0-9@._-]+).*/\1/')
ADMIN_PASS=$(grep -i "admin password" temp_init.log | tail -1 | sed -E 's/.*password[[:space:]]*:[[:space:]]*([a-zA-Z0-9@._-]+).*/\1/')

rm -f temp_init.log

# 5. Tạo systemd service
echo -e "${YELLOW}Đang cấu hình systemd...${NC}"
cat > /etc/systemd/system/cloudreve.service <<EOF
[Unit]
Description=Cloudreve
Documentation=https://docs.cloudreve.org
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/cloudreve
ExecStart=/opt/cloudreve/cloudreve
Restart=on-abnormal
RestartSec=5s
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudreve > /dev/null 2>&1
systemctl start cloudreve

sleep 3

# 6. Hiển thị kết quả
echo -e ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   CÀI ĐẶT THÀNH CÔNG!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e ""
echo -e "Truy cập: ${CYAN}http://$(curl -s ifconfig.me):5212${NC}"
echo -e ""
echo -e "${YELLOW}LƯU Ý:${NC} Hãy mở port ${CYAN}5212${NC} trên Security Group / Firewall của VPS!"

if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; then
    echo -e ""
    echo -e "${GREEN}=== THÔNG TIN ĐĂNG NHẬP ===${NC}"
    echo -e "Tài khoản : ${CYAN}${ADMIN_USER}${NC}"
    echo -e "Mật khẩu : ${CYAN}${ADMIN_PASS}${NC}"
    echo -e "${GREEN}===========================${NC}"
    echo -e ""
    echo -e "${YELLOW}⚠️  Hãy đổi mật khẩu ngay sau khi đăng nhập!${NC}"
else
    echo -e ""
    echo -e "${RED}Không lấy được thông tin đăng nhập tự động.${NC}"
    echo -e "Bạn có thể chạy lại script hoặc xóa thư mục ${CYAN}/opt/cloudreve/data${NC} rồi chạy lại."
fi

echo -e ""
