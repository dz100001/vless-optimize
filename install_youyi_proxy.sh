#!/bin/bash
# ==============================================================================
# Youyi Reverse Proxy for V2Board v2.4
# - 支持两种模式：仅开放订阅 (Subscribe) 或 全局代理 (Full Proxy)
# - 专为 V2Board / Xboard 优化
# - 自动开放防火墙端口
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} YOUYI REVERSE PROXY FOR V2BOARD v2.4${NC}"
echo -e "${GREEN}========================================${NC}\n"

# ================== 填写信息 ==================
read -p "请输入后端 IP (运行 V2Board 的源 VPS): " BACKEND_IP
while [[ -z "$BACKEND_IP" ]]; do
    echo -e "${RED}IP 不能为空！${NC}"
    read -p "请输入后端 IP (运行 V2Board 的源 VPS): " BACKEND_IP
done

read -p "请输入后端端口 (默认: 6666): " BACKEND_PORT
BACKEND_PORT="${BACKEND_PORT:-6666}"

read -p "请输入代理端口 (默认: 36868): " PROXY_PORT
PROXY_PORT="${PROXY_PORT:-36868}"

# ================== 选择模式 ==================
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} 选择代理模式${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${GREEN}1.${NC} 仅允许 /api/v1/client/subscribe?token=...  ${YELLOW}(推荐 - 隐藏面板)${NC}"
echo -e "${GREEN}2.${NC} 允许所有路径                      ${YELLOW}(全局反向代理)${NC}"
echo ""

while true; do
    read -p "请选择模式 [1/2]: " mode
    case "$mode" in
        1)
            PROXY_MODE="subscribe"
            echo -e "${GREEN}→ 已选择：仅开放订阅${NC}"
            break
            ;;
        2)
            PROXY_MODE="full"
            echo -e "${YELLOW}→ 已选择：全局反向代理${NC}"
            break
            ;;
        *)
            echo "请选择 1 或 2。"
            ;;
    esac
done

echo ""
read -p "是否继续安装？[Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "已取消。"
    exit 0
fi

echo -e "\n${YELLOW}=> 正在安装...${NC}"

# 1. 安装 Nginx
echo " [1/7] 更新并安装 Nginx..."
sudo apt update -y > /dev/null 2>&1
sudo apt install -y nginx curl > /dev/null 2>&1

# 2. 清理旧配置
echo " [2/7] 清理冲突的配置文件..."
sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
sudo rm -f /etc/nginx/sites-enabled/youyi* 2>/dev/null || true
sudo rm -f /etc/nginx/conf.d/youyi* 2>/dev/null || true

# 3. 开放防火墙
echo " [3/7] 为端口 ${PROXY_PORT} 配置防火墙..."
if command -v ufw >/dev/null 2>&1; then
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow ${PROXY_PORT}/tcp comment 'Youyi V2Board Proxy' > /dev/null 2>&1 || true
        sudo ufw reload > /dev/null 2>&1 || true
        echo " ✓ 已在 UFW 中开放端口 ${PROXY_PORT}"
    else
        echo " ℹ UFW 未开启"
    fi
elif command -v firewall-cmd >/dev/null 2>&1; then
    if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
        sudo firewall-cmd --permanent --add-port=${PROXY_PORT}/tcp > /dev/null 2>&1 || true
        sudo firewall-cmd --reload > /dev/null 2>&1 || true
        echo " ✓ 已在 Firewalld 中开放端口 ${PROXY_PORT}"
    fi
else
    echo " ℹ 未检测到 UFW/Firewalld"
fi

# 4. 创建 Nginx 配置文件
echo " [4/7] 生成 Nginx 配置文件..."

if [[ "$PROXY_MODE" == "subscribe" ]]; then
    # 仅允许订阅模式
    PROXY_CONFIG=$(cat << EOF
server {
    listen ${PROXY_PORT};
    server_name _;

    location / {
        # 仅允许 V2Board 订阅路径
        if (\$request_uri !~ "^/api/v1/client/subscribe\?token=") {
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
        proxy_send_timeout 300s;
        proxy_redirect off;
    }
}
EOF
)
else
    # 全局反向代理模式
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
        proxy_send_timeout 300s;
        proxy_redirect off;
    }
}
EOF
)
fi

echo "$PROXY_CONFIG" | sudo tee /etc/nginx/conf.d/youyi-proxy.conf > /dev/null

# 5. 检查配置
echo " [5/7] 检查 Nginx 配置..."
if ! sudo nginx -t; then
    echo -e "${RED}❌ Nginx 配置错误！${NC}"
    exit 1
fi

# 6. 重启 Nginx
echo " [6/7] 重启 Nginx..."
sudo systemctl enable nginx > /dev/null 2>&1
sudo systemctl restart nginx

# 7. 完成
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ 安装成功！${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "后端 (Backend) : ${YELLOW}http://${BACKEND_IP}:${BACKEND_PORT}${NC}"
echo -e "代理端口       : ${YELLOW}${PROXY_PORT}${NC}"
echo -e "配置文件       : /etc/nginx/conf.d/youyi-proxy.conf"

if [[ "$PROXY_MODE" == "subscribe" ]]; then
    echo -e "模式           : ${GREEN}仅开放订阅 (推荐)${NC}"
    echo -e "             仅允许: /api/v1/client/subscribe?token=..."
else
    echo -e "模式           : ${YELLOW}全局反向代理${NC}"
    echo -e "             允许所有路径"
fi

echo -e "\n${YELLOW}=== 测试指南 ===${NC}"
if [[ "$PROXY_MODE" == "subscribe" ]]; then
    echo -e "测试成功示例:"
    echo -e " ${CYAN}curl \"http://127.0.0.1:${PROXY_PORT}/api/v1/client/subscribe?token=your_token\"${NC}"
    echo -e "测试被拦截示例:"
    echo -e " ${CYAN}curl http://127.0.0.1:${PROXY_PORT}/${NC}"
else
    echo -e "测试示例:"
    echo -e " ${CYAN}curl http://127.0.0.1:${PROXY_PORT}/${NC}"
fi

echo -e "\n${RED}⚠️ 注意事项:${NC}"
echo "1. 请务必在 VPS 提供商的安全组/防火墙中开放端口 ${PROXY_PORT}"
echo "2. 如果使用模式 1，订阅链接将是:"
echo "   http://IP_PROXY:${PROXY_PORT}/api/v1/client/subscribe?token=xxxxx"
echo ""
echo -e "${GREEN}脚本已自动在 UFW/Firewalld 中开放端口 (如果已开启)。${NC}"
