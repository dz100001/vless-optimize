#!/bin/bash
# ==============================================
#   安装 CLOUDREVE 3.8.3 - 改进版
#   自动显示准确的账号 + 密码
# ==============================================

# 颜色配置
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   开始快速安装 CLOUDREVE    ${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. 准备环境
echo -e "${YELLOW}[1/5] 正在准备环境...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y wget curl awk > /dev/null 2>&1

# 2. 下载 Cloudreve
echo -e "${YELLOW}[2/5] 正在下载 Cloudreve 3.8.3...${NC}"
mkdir -p /opt/cloudreve
cd /opt/cloudreve || exit 1

wget -qO cloudreve.tar.gz https://github.com/cloudreve/Cloudreve/releases/download/3.8.3/cloudreve_3.8.3_linux_amd64.tar.gz
if [ $? -ne 0 ]; then
    echo -e "${RED}Cloudreve 文件下载失败！${NC}"
    exit 1
fi

# 3. 解压并授权
echo -e "${YELLOW}[3/5] 正在解压并赋予权限...${NC}"
tar -zxvf cloudreve.tar.gz > /dev/null 2>&1
chmod +x ./cloudreve
rm -f cloudreve.tar.gz

# --- 关键点：正确删除 DATA 文件夹（Cloudreve 3.x 使用 data/） ---
echo -e "${YELLOW}[4/5] 正在删除旧数据以生成新密码...${NC}"
systemctl stop cloudreve > /dev/null 2>&1 || true
rm -rf /opt/cloudreve/data 2>/dev/null || true
mkdir -p /opt/cloudreve/data

# 4. 临时运行以获取密码（智能等待）
echo -e "${YELLOW}[5/5] 正在初始化并提取登录信息...${NC}"

./cloudreve > temp_init.log 2>&1 &
CLOUD_PID=$!

# 最多等待 60 秒直到出现密码行
echo -e "${CYAN}    正在等待 Cloudreve 初始化（最多 60 秒）...${NC}"
for i in {1..60}; do
    if grep -q "Admin password" temp_init.log 2>/dev/null; then
        echo -e "${GREEN}    ✓ 已成功获取登录信息！${NC}"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        echo -e "${RED}    ⚠️ 等待超时！${NC}"
    fi
done

kill -9 $CLOUD_PID >/dev/null 2>&1 || true
sleep 2

# === 提取账号和密码（已修复错误） ===
ADMIN_USER=$(grep -i "admin user name" temp_init.log | tail -1 | sed -E 's/.*name[[:space:]]*:[[:space:]]*([a-zA-Z0-9@._-]+).*/\1/')
ADMIN_PASS=$(grep -i "admin password" temp_init.log | tail -1 | sed -E 's/.*password[[:space:]]*:[[:space:]]*([a-zA-Z0-9@._-]+).*/\1/')

rm -f temp_init.log

# 5. 创建 systemd 服务
echo -e "${YELLOW}正在配置 systemd...${NC}"
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

# 6. 显示结果
echo -e ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   安装成功！${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e ""
echo -e "访问地址: ${CYAN}http://$(curl -s ifconfig.me):5212${NC}"
echo -e ""
echo -e "${YELLOW}注意:${NC} 请在 VPS 的安全组 / 防火墙中开放 ${CYAN}5212${NC} 端口！"

if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; then
    echo -e ""
    echo -e "${GREEN}=== 登录信息 ===${NC}"
    echo -e "账号 : ${CYAN}${ADMIN_USER}${NC}"
    echo -e "密码 : ${CYAN}${ADMIN_PASS}${NC}"
    echo -e "${GREEN}===========================${NC}"
    echo -e ""
    echo -e "${YELLOW}⚠️  请在登录后立即修改密码！${NC}"
else
    echo -e ""
    echo -e "${RED}无法自动获取登录信息。${NC}"
    echo -e "您可以重新运行脚本，或者删除 ${CYAN}/opt/cloudreve/data${NC} 文件夹后再重试。"
fi

echo -e ""
