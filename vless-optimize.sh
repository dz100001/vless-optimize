#!/bin/bash

# ============================================================
# VLESS VPS 优化脚本 - 版本 2.8 (极致优化)
# 专为 1核1G 内存、面向中国用户的 VPS 设计
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=========================================="
echo -e "   VLESS VPS 优化脚本 v2.8 (极致优化)"
echo -e "==========================================${NC}"

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}需要使用 root 权限运行！${NC}"
    exit 1
fi

# ==================== 1. 选择后端 (CHỌN BACKEND) ====================
echo -e "\n${YELLOW}您使用的是哪个后端？${NC}"
echo "1) V2bX"
echo "2) v2node"
read -p "请选择 (1 或 2): " BACKEND_CHOICE

if [ "$BACKEND_CHOICE" = "1" ]; then
    BACKEND="V2bX"
    CONFIG_FILE="/etc/V2bX/config.json"
    SERVICE_NAME="V2bX"
    RESTART_CMD="systemctl restart V2bX"
elif [ "$BACKEND_CHOICE" = "2" ]; then
    BACKEND="v2node"
    CONFIG_FILE="/etc/v2node/config.json"
    SERVICE_NAME="v2node"
    RESTART_CMD="v2node restart"
else
    echo -e "${RED}无效的选择！${NC}"; exit 1
fi
echo -e "${GREEN}✓ 后端：$BACKEND${NC}"

# ==================== 2. 选择 VLESS 协议 ====================
echo -e "\n${YELLOW}您想为哪种 VLESS 协议进行优化？${NC}"
echo "1) VLESS + Reality + Vision (强烈推荐)"
echo "2) VLESS + WebSocket"
read -p "请选择 (1 或 2): " VLESS_CHOICE

if [ "$VLESS_CHOICE" = "1" ]; then
    VLESS_TYPE="Reality"
    echo -e "${GREEN}✓ 已选择 Reality + Vision (最适合中国用户的配置)${NC}"
elif [ "$VLESS_CHOICE" = "2" ]; then
    VLESS_TYPE="WebSocket"
    echo -e "${RED}⚠️ 警告：WebSocket 比 Reality 占用更多的 RAM 和 CPU。${NC}"
    echo -e "${RED}   对于 1GB RAM + 200 用户的 VPS，Reality 会稳定得多。${NC}"
else
    echo -e "${RED}无效的选择！${NC}"; exit 1
fi

# ==================== 3. 创建 ZRAM 或 SWAP ====================
echo -e "\n${YELLOW}您想使用 Zram 还是普通 Swap？${NC}"
echo "1) Zram (推荐低内存使用)"
echo "2) 普通 Swap"
echo "3) 不创建"
read -p "请选择 (1-3): " SWAP_TYPE

if [ "$SWAP_TYPE" = "1" ]; then
    echo -e "${YELLOW}正在安装 zram...${NC}"
    apt install -y zram-tools >/dev/null 2>&1
    systemctl enable --now zramswap.service 2>/dev/null || true
    echo -e "${GREEN}✓ 已启用 Zram${NC}"
elif [ "$SWAP_TYPE" = "2" ]; then
    echo -e "\n${YELLOW}请选择 Swap 容量：${NC}"
    echo "1) 1GB   2) 2GB (推荐)   3) 4GB   4) 8GB"
    read -p "请选择 (1-4): " SWAP_SIZE_CHOICE
    case $SWAP_SIZE_CHOICE in 1) SIZE=1 ;; 2) SIZE=2 ;; 3) SIZE=4 ;; 4) SIZE=8 ;; *) SIZE=2 ;; esac

    SWAPFILE="/swapfile"
    [ -f "$SWAPFILE" ] && swapoff $SWAPFILE 2>/dev/null && rm -f $SWAPFILE
    fallocate -l ${SIZE}G $SWAPFILE 2>/dev/null || dd if=/dev/zero of=$SWAPFILE bs=1M count=$((SIZE*1024)) status=progress
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon $SWAPFILE
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab 2>/dev/null
    sysctl -w vm.swappiness=10 >/dev/null 2>&1
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo -e "${GREEN}✓ 已创建 ${SIZE}GB Swap${NC}"
fi

# ==================== 4. 修改 SSH 端口 ====================
echo -e "\n${YELLOW}您想将 SSH 端口更改为 2901 吗？${NC}"
echo "1) 是 (推荐)"
echo "2) 否"
read -p "请选择 (1 或 2): " SSH_CHOICE

if [ "$SSH_CHOICE" = "1" ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
    sed -i 's/^#*Port .*/Port 2901/' /etc/ssh/sshd_config
    if command -v ufw &> /dev/null; then
        ufw allow 2901/tcp >/dev/null 2>&1
        ufw reload >/dev/null 2>&1
    fi
    echo -e "${GREEN}✓ 已将 SSH 端口更改为 2901${NC}"
fi

# ==================== 5. 系统优化 ====================
echo -e "\n${YELLOW}[1/5] 正在优化系统...${NC}"

# 禁用 IPv6
cat > /etc/sysctl.d/99-disable-ipv6.conf << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1

# 极致 Sysctl 优化
cat > /etc/sysctl.d/99-vless-optimize.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.somaxconn = 32768
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 300
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608
net.netfilter.nf_conntrack_max = 131072
vm.swappiness = 10
EOF
sysctl -p /etc/sysctl.d/99-vless-optimize.conf >/dev/null 2>&1

cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
ulimit -n 65535

# 限制 journald 日志
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-vless.conf << 'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=50M
EOF
systemctl restart systemd-journald 2>/dev/null || true

echo -e "${GREEN}✓ 已优化 sysctl + 禁用 IPv6 + 开启 TCP Fast Open${NC}"

# ==================== 6. 配置优化 ====================
echo -e "${YELLOW}[2/5] 正在优化 $BACKEND 配置 ($VLESS_TYPE)...${NC}"
BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"

jq '
  if has("SniffEnabled") then .SniffEnabled = false else . end |
  if .Log then .Log.Level = "error" else . end |
  if .Nodes then .Nodes |= map(if has("SniffEnabled") then .SniffEnabled = false else . end) else . end
' "$CONFIG_FILE" > /tmp/vless_config_temp.json && mv /tmp/vless_config_temp.json "$CONFIG_FILE"

echo -e "${GREEN}✓ 已设置日志级别 (Log Level) 为 error 并关闭流量探测 (Sniffing)${NC}"

# ==================== 7. LOGROTATE + CRON ====================
echo -e "${YELLOW}[3/5] 正在配置 logrotate 和定时重启服务 (cron)...${NC}"
cat > /etc/logrotate.d/vless-node << 'EOF'
/var/log/v2node/*.log /var/log/V2bX/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    create 0640 root adm
}
EOF

CRON_JOB="0 4 * * * $RESTART_CMD >/dev/null 2>&1"
if ! crontab -l 2>/dev/null | grep -q "$RESTART_CMD"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
fi

# ==================== 8. RESTART ====================
echo -e "${YELLOW}[4/5] 正在重启服务...${NC}"
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
systemctl restart "$SERVICE_NAME" 2>/dev/null || $RESTART_CMD 2>/dev/null

echo -e "\n${GREEN}=========================================="
echo -e "           优化完成 (v2.8)"
echo -e "==========================================${NC}"

echo -e "${GREEN}后端            : $BACKEND${NC}"
echo -e "${GREEN}VLESS 协议      : $VLESS_TYPE${NC}"
echo -e "${GREEN}日志级别        : error${NC}"
echo -e "${GREEN}IPv6            : 已禁用${NC}"
echo -e "${GREEN}TCP Fast Open   : 已开启${NC}"

if [ "$SWAP_TYPE" = "1" ]; then echo -e "${GREEN}内存优化        : Zram 已启用${NC}"; fi
if [ "$SWAP_TYPE" = "2" ]; then echo -e "${GREEN}Swap 虚拟内存   : ${SIZE}GB${NC}"; fi
if [ "$SSH_CHOICE" = "1" ]; then echo -e "${GREEN}新 SSH 端口     : 2901${NC}"; fi

echo -e "${YELLOW}配置文件备份    : $BACKUP_FILE${NC}"

echo -e "\n${BLUE}最终建议：${NC}"
if [ "$VLESS_TYPE" = "Reality" ]; then
    echo "→ Reality + Vision 是目前面向中国用户的最佳选择。"
else
    echo "→ WebSocket 占用较多资源。建议考虑切换到 Reality。"
fi

echo -e "\n${RED}重要提示：${NC}"
echo "- 对于 1GB RAM + 200 用户，Reality 会比 WebSocket 稳定且流畅得多。"
echo "- 请在投入实际生产环境前进行充分测试。"
