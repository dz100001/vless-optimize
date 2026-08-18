#!/bin/bash
# =================================================================
# VPS 初始化脚本、系统更新 & 安装 CLOUDFLARE DDNS
# =================================================================

# -----------------------------------------------------------------
# 0. 重装系统为 DEBIAN 13 (TANTI / TRIXY)
# -----------------------------------------------------------------
echo "==> 正在执行一键重装系统为 Debian 13..."
bash <(curl -sSL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh) debian -v 13 --password "$ROOT_PASSWORD"

# -----------------------------------------------------------------
# 1. 配置信息
# -----------------------------------------------------------------
ROOT_PASSWORD="048297ac-908f-4edb-9601-55901c00e29e"
CF_EMAIL="qtwq8y6frc@privaterelay.appleid.com"
CF_API_KEY="cfut_j5zl4dGpivg59DdsKTs0h3Q72ggQTNJYEy5LmERFdbecee2d"
CF_ZONE="c3c3.top"
CF_RECORD="aliyun.riben01.c3c3.top"

# -----------------------------------------------------------------
# 2. 安装基础工具 (CURL, WGET) & 更新系统
# -----------------------------------------------------------------
echo "==> 正在安装 curl、wget 并更新 VPS 软件..."
sudo apt update && sudo apt install -y curl wget
sudo apt dist-upgrade -y
sudo apt install -y cron jq
sudo systemctl enable --now cron

# -----------------------------------------------------------------
# 3. 配置 ROOT 密码 & SSH
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
# 4. 运行 CLOUDFLARE DDNS 脚本 & 创建定时任务 (CRONJOB)
# -----------------------------------------------------------------
echo "==> 正在安装 Cloudflare DDNS..."
bash <(curl -sSL https://ddns.8245454.xyz/aws.sh) --install-cron "$CF_EMAIL" "$CF_API_KEY" "$CF_ZONE" "$CF_RECORD"

# -----------------------------------------------------------------
# 5. 安装 NYANPASS NODECLIENT
# -----------------------------------------------------------------
echo "==> 正在安装 Nyanpass Nodeclient..."
bash <(curl -L https://gcode.hostcentral.cc/https://github.com/Sagit-chu/flvx/releases/download/3.0.0/install.sh -o ./install.sh && chmod +x ./install.sh && PROXY_ENABLED=true PROXY_URL=https://gcode.hostcentral.cc VERSION=3.0.0 ./install.sh -a 160.30.160.90:6366 -s 249d464e98a77737cfea559d0fab8485)
# -----------------------------------------------------------------
# 6. 启用 BBR (网络优化)
# -----------------------------------------------------------------
echo "==> 正在启用 BBR..."
bash <(curl -L -s www.hlspeed.cc/bbr/123.sh)

echo "==> 安装完成！"
