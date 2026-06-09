#!/bin/bash

# Thiết lập màu sắc cho thông báo
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    BẮT ĐẦU CÀI ĐẶT CLOUDREVE NHANH     ${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. Cập nhật hệ thống và cài đặt wget
echo -e "${YELLOW}[1/5] Đang chuẩn bị môi trường...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install wget curl awk -y > /dev/null 2>&1

# 2. Tải và giải nén Cloudreve
echo -e "${YELLOW}[2/5] Đang tải mã nguồn Cloudreve (Bản 3.8.3)...${NC}"
mkdir -p /opt/cloudreve
cd /opt/cloudreve || exit
wget -qO cloudreve.tar.gz https://github.com/cloudreve/Cloudreve/releases/download/3.8.3/cloudreve_3.8.3_linux_amd64.tar.gz

echo -e "${YELLOW}[3/5] Đang giải nén và cấp quyền...${NC}"
tar -zxvf cloudreve.tar.gz > /dev/null 2>&1
chmod +x ./cloudreve
rm cloudreve.tar.gz # Xóa file nén cho sạch rác

# 3. Chạy thử để lấy mật khẩu
echo -e "${YELLOW}[4/5] Đang khởi tạo dữ liệu để trích xuất mật khẩu...${NC}"
# Chạy Cloudreve và lưu log tạm ra file
./cloudreve > temp_init.log 2>&1 &
PID=$!
# Đợi 5 giây để Cloudreve tạo xong Database và sinh mật khẩu
sleep 5
# Tắt tiến trình chạy nháp
kill $PID

# Dùng awk để lọc và lấy chính xác tài khoản, mật khẩu
ADMIN_USER=$(grep "Admin user name:" temp_init.log | awk '{print $NF}')
ADMIN_PASS=$(grep "Admin password:" temp_init.log | awk '{print $NF}')
rm temp_init.log # Dọn dẹp file log tạm

# 4. Tạo cấu hình Systemd để chạy ngầm
echo -e "${YELLOW}[5/5] Đang cấu hình Systemd và khởi chạy dịch vụ...${NC}"
cat <<EOF > /etc/systemd/system/cloudreve.service
[Unit]
Description=Cloudreve
Documentation=https://docs.cloudreve.org
After=network.target
After=mysqld.service
Wants=network.target

[Service]
WorkingDirectory=/opt/cloudreve
ExecStart=/opt/cloudreve/cloudreve
Restart=on-abnormal
RestartSec=5s
KillMode=mixed

StandardOutput=null
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

# 5. Kích hoạt dịch vụ
systemctl daemon-reload
systemctl enable cloudreve > /dev/null 2>&1
systemctl start cloudreve

# 6. In kết quả cuối cùng
echo -e "${GREEN}========================================================================${NC}"
echo -e "${GREEN} THÀNH CÔNG! Cloudreve đã được cài đặt và đang chạy ngầm trên VPS.      ${NC}"
echo -e "${GREEN}========================================================================${NC}"
echo -e "Truy cập web tại : ${CYAN}http://$(curl -s ifconfig.me):5212${NC}"
echo -e ""
echo -e "Hãy lưu lại thông tin đăng nhập tự động tạo dưới đây:"
echo -e "------------------------------------------------------------"
echo -e "Tài khoản : ${CYAN}${ADMIN_USER}${NC}"
echo -e "Mật khẩu  : ${CYAN}${ADMIN_PASS}${NC}"
echo -e "------------------------------------------------------------"
echo -e "(Sau khi đăng nhập, hãy vào Admin Panel -> Users để đổi lại theo ý muốn)"
