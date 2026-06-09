#!/bin/bash

# Thiết lập màu sắc cho thông báo
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    BẮT ĐẦU CÀI ĐẶT CLOUDREVE NHANH     ${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. Cập nhật hệ thống và cài đặt wget nếu chưa có
echo -e "${YELLOW}[1/4] Đang chuẩn bị môi trường...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install wget -y > /dev/null 2>&1

# 2. Tạo thư mục, tải và giải nén Cloudreve
echo -e "${YELLOW}[2/4] Đang tải mã nguồn Cloudreve (Bản 3.8.3)...${NC}"
mkdir -p /opt/cloudreve
cd /opt/cloudreve || exit
wget -qO cloudreve.tar.gz https://github.com/cloudreve/Cloudreve/releases/download/3.8.3/cloudreve_3.8.3_linux_amd64.tar.gz

echo -e "${YELLOW}[3/4] Đang giải nén và cấp quyền...${NC}"
tar -zxvf cloudreve.tar.gz > /dev/null 2>&1
chmod +x ./cloudreve
rm cloudreve.tar.gz # Xóa file nén cho sạch rác

# 3. Tạo cấu hình Systemd để chạy ngầm
echo -e "${YELLOW}[4/4] Đang cấu hình Systemd và khởi động...${NC}"
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

# 4. Kích hoạt dịch vụ
systemctl daemon-reload
systemctl enable cloudreve > /dev/null 2>&1
systemctl start cloudreve

echo -e "${GREEN}========================================================================${NC}"
echo -e "${GREEN} THÀNH CÔNG! Cloudreve đã được cài đặt và đang chạy ngầm trên VPS.      ${NC}"
echo -e "${GREEN}========================================================================${NC}"
echo -e "Truy cập web tại địa chỉ: ${YELLOW}http://$(curl -s ifconfig.me):5212${NC}"
echo -e ""
echo -e "Để lấy ${YELLOW}Tài khoản${NC} và ${YELLOW}Mật khẩu${NC} mặc định do hệ thống tạo, hãy copy và chạy lệnh sau:"
echo -e "------------------------------------------------------------"
echo -e "  journalctl -u cloudreve -n 50 --no-pager | grep -E 'Admin user name:|Admin password:'"
echo -e "------------------------------------------------------------"
