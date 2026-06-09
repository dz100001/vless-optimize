#!/bin/bash
# ==============================================================================
# Script Cài đặt tự động Nginx Reverse Proxy (Bản tương tác - Nâng cao)
# Tùy chọn: Có thể bỏ qua tính năng chặn User-Agent bằng cách ấn Enter
# ==============================================================================

echo -e "\n========== BẮT ĐẦU THIẾT LẬP HỆ THỐNG PROXY NGINX ==========\n"

# ==============================================================================
# BƯỚC A: LẤY THÔNG TIN TỪ NGƯỜI DÙNG
# ==============================================================================
read -p "1. Nhập IP của VPS V2board gốc (VD: 152.53.169.197): " TARGET_IP
read -p "2. Nhập Port đang mở trên VPS gốc (VD: 6666): " TARGET_PORT
read -p "3. Nhập User-Agent (VD: YouyiApp) - [ẤN ENTER ĐỂ BỎ QUA NẾU KHÔNG CẦN]: " ALLOWED_UA

# Xử lý logic cấu hình User-Agent
if [ -z "$ALLOWED_UA" ]; then
    UA_MSG="KHÔNG SỬ DỤNG (Cho phép mọi kết nối)"
    # Nếu người dùng để trống, gán biến này bằng rỗng (không ghi gì vào Nginx)
    NGINX_UA_RULE=""
else
    UA_MSG="Chỉ cho phép '$ALLOWED_UA'"
    # Nếu có nhập liệu, tạo khối lệnh Nginx chặn UA
    NGINX_UA_RULE="
        # KHÓA CHẶT USER-AGENT ĐỘC QUYỀN
        if (\$http_user_agent !~ \"$ALLOWED_UA\") {
            return 404;
        }"
fi

echo -e "\n---------------------------------------------------------"
echo "ĐANG CÀI ĐẶT VỚI CÁC THÔNG SỐ:"
echo "=> Trỏ về đích: http://$TARGET_IP:$TARGET_PORT"
echo "=> Trạng thái User-Agent: $UA_MSG"
echo "---------------------------------------------------------\n"

# ==============================================================================
# BƯỚC B: CHẠY LỆNH TỰ ĐỘNG
# ==============================================================================

# 1. Cập nhật hệ thống và cài đặt Nginx
echo "=> [1/4] Đang cập nhật hệ thống và cài đặt Nginx..."
sudo apt update -y
sudo apt --fix-broken install -y
sudo apt install nginx -y

# 2. Xóa cấu hình mặc định gây xung đột
echo "=> [2/4] Đang dọn dẹp cấu hình Nginx mặc định..."
sudo rm -f /etc/nginx/sites-enabled/default

# 3. Tạo file cấu hình Proxy mới
echo "=> [3/4] Đang khởi tạo file cấu hình ip-sub.conf..."
sudo cat << EOF > /etc/nginx/conf.d/ip-sub.conf
server {
    listen 80 default_server;
    server_name _;

    location / {
$NGINX_UA_RULE

        # Định tuyến về IP và Port đích
        proxy_pass http://$TARGET_IP:$TARGET_PORT; 
        
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

# 4. Kiểm tra và Khởi động lại hệ thống
echo "=> [4/4] Đang kiểm tra cú pháp và kích hoạt dịch vụ..."
sudo nginx -t

# Chỉ khởi động lại nếu Nginx báo test thành công ($? -eq 0)
if [ $? -eq 0 ]; then
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    echo -e "\n========== CÀI ĐẶT HOÀN TẤT THÀNH CÔNG! =========="
    echo "VPS này đã sẵn sàng trung chuyển lưu lượng."
else
    echo -e "\n[LỖI] Cú pháp Nginx có vấn đề. Vui lòng kiểm tra lại!"
fi
