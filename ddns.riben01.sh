#!/bin/bash
# =================================================================
# VPS 初始化脚本、系统更新 & 安装 CLOUDFLARE DDNS
# (Phiên bản an toàn sử dụng Biến môi trường - Environment Variables)
# =================================================================

# -----------------------------------------------------------------
# 0. Kiểm tra Biến môi trường bảo mật
# -----------------------------------------------------------------
# Script 
if [ -z "$MY_ROOT_PASSWORD" ] || [ -z "$MY_CF_API_KEY" ] || [ -z "$MY_NYANPASS_TOKEN" ]; then
    echo "error:  ( API, Token)!"
    echo "Script ."
    exit 1
fi

# -----------------------------------------------------------------
# 1. 配置信息 (Nhận dữ liệu từ dòng lệnh, KHÔNG hardcode)
# -----------------------------------------------------------------
ROOT_PASSWORD="$MY_ROOT_PASSWORD"
CF_EMAIL="${MY_CF_EMAIL:-qtwq8y6frc@privaterelay.appleid.com}"
CF_API_KEY="$MY_CF_API_KEY"
CF_ZONE="${MY_CF_ZONE:-c3c3.top}"
CF_RECORD="${MY_CF_RECORD:-ddns.aliyun.hk.c3c3.top}"
NYANPASS_TOKEN="$MY_NYANPASS_TOKEN"

# -----------------------------------------------------------------
# 2. 重装系统为 DEBIAN 13 (TANTI / TRIXY)
# -----------------------------------------------------------------
echo "==> 正在执行一键重装系统为 Debian 13..."
bash <(curl -sSL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh) debian -v 13 --password "$ROOT_PASSWORD"

# -----------------------------------------------------------------
# 3. 安装基础工具 (CURL, WGET) & 更新系统
# -----------------------------------------------------------------
echo "==> 正在安装 curl、wget 并更新 VPS 软件..."
sudo apt update && sudo apt install -y curl wget
sudo apt dist-upgrade -y
sudo apt install -y cron jq
sudo systemctl enable --now cron

# -----------------------------------------------------------------
# 4. 配置 ROOT 密码 & SSH
# -----------------------------------------------------------------
if [ -n "$ROOT_PASSWORD" ]; then
    echo "==> 正在修改 root 密码..."
    echo root:"$ROOT_PASSWORD" | sudo chpasswd root
fi

echo "==> 正在配置 SSH (PermitRootLogin & PasswordAuthentication)..."
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo rm -rf /etc/ssh/sshd_config.d
sudo systemctl restart sshd

# -----------------------------------------------------------------
# 5. 运行 CLOUDFLARE DDNS 脚本 & 创建定时任务 (CRONJOB)
# -----------------------------------------------------------------
echo "==> 正在安装 Cloudflare DDNS..."
bash <(curl -sSL https://ddns.8245454.xyz/aws.sh) --install-cron "$CF_EMAIL" "$CF_API_KEY" "$CF_ZONE" "$CF_RECORD"

# -----------------------------------------------------------------
# 6. 安装 NYANPASS NODECLIENT
# -----------------------------------------------------------------
echo "==> 正在安装 Nyanpass Nodeclient..."
yes "" | bash <(curl -fLSs https://dispatch.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-t $NYANPASS_TOKEN -u https://fw.fzpn.net"

# -----------------------------------------------------------------
# 7. 启用 BBR (网络优化)
# -----------------------------------------------------------------
echo "==> 正在启用 BBR..."
bash <(curl -L -s www.hlspeed.cc/bbr/123.sh)

echo "==> 安装完成！"
