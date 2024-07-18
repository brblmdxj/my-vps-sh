#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 默认值设置
DEFAULT_AUTH_EMAIL="guoabar@outlook.com"
DEFAULT_AUTH_KEY="944c6bb800c6ef07711597a3c4059b1a141ee"
ZONE_ID_1="3f6005568bd77a13e56970fc4539b00d"
ZONE_ID_2="105f2a8d8d354aeef39cb1e83eadb85c"
DEFAULT_ZONE_ID=$ZONE_ID_1

# 检查是否以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请以root权限运行此脚本${NC}"
        exit 1
    fi
}

# 安装和配置
install_and_configure() {
    check_root

    # 提示用户输入Cloudflare信息
    read -p "请输入您的Cloudflare账户邮箱 [默认: $DEFAULT_AUTH_EMAIL]: " AUTH_EMAIL
    AUTH_EMAIL=${AUTH_EMAIL:-$DEFAULT_AUTH_EMAIL}

    read -p "请输入您的Cloudflare Global API Key [默认: $DEFAULT_AUTH_KEY]: " AUTH_KEY
    AUTH_KEY=${AUTH_KEY:-$DEFAULT_AUTH_KEY}

    echo "请选择您的Zone ID:"
    echo "1. $ZONE_ID_1 (默认)"
    echo "2. $ZONE_ID_2"
    read -p "请输入选项 (1 或 2) [默认: 1]: " ZONE_ID_CHOICE
    ZONE_ID_CHOICE=${ZONE_ID_CHOICE:-1}

    case $ZONE_ID_CHOICE in
        1)
            ZONE_ID=$ZONE_ID_1
            ;;
        2)
            ZONE_ID=$ZONE_ID_2
            ;;
        *)
            echo "无效的选择，使用默认值 1"
            ZONE_ID=$ZONE_ID_1
            ;;
    esac

    read -p "请输入您要更新的域名 [默认: example.com]: " RECORD_NAME
    RECORD_NAME=${RECORD_NAME:-example.com}

    # 安装必要的工具
    echo "正在安装必要的工具..."
    apt-get update
    apt-get install -y jq curl

    # 创建更新DNS的脚本
    cat > /usr/local/bin/update_cf_dns.sh << EOL
#!/bin/bash

# Cloudflare 配置
AUTH_EMAIL="$AUTH_EMAIL"
AUTH_KEY="$AUTH_KEY"
ZONE_ID="$ZONE_ID"
RECORD_NAME="$RECORD_NAME"
RECORD_TYPE="A"

# 获取当前公网 IP
CURRENT_IP=\$(curl -s http://ipv4.icanhazip.com)

# 获取 Cloudflare 上当前的 DNS 记录
RECORD_ID=\$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records?type=\$RECORD_TYPE&name=\$RECORD_NAME" \
     -H "X-Auth-Email: \$AUTH_EMAIL" \
     -H "X-Auth-Key: \$AUTH_KEY" \
     -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -z "\$RECORD_ID" ]; then
    echo "DNS 记录不存在，创建新记录"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records" \
         -H "X-Auth-Email: \$AUTH_EMAIL" \
         -H "X-Auth-Key: \$AUTH_KEY" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"\$RECORD_TYPE\",\"name\":\"\$RECORD_NAME\",\"content\":\"\$CURRENT_IP\",\"ttl\":1,\"proxied\":false}"
else
    echo "更新已存在的 DNS 记录"
    curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \
         -H "X-Auth-Email: \$AUTH_EMAIL" \
         -H "X-Auth-Key: \$AUTH_KEY" \
         -H "Content-Type: application/json" \
         --data "{\"type\":\"\$RECORD_TYPE\",\"name\":\"\$RECORD_NAME\",\"content\":\"\$CURRENT_IP\",\"ttl\":1,\"proxied\":false}"
fi

echo "DNS 记录已更新为 \$CURRENT_IP"
EOL

    # 给脚本添加执行权限
    chmod +x /usr/local/bin/update_cf_dns.sh

    # 创建系统服务
    cat > /etc/systemd/system/update-cf-dns.service << EOL
[Unit]
Description=Update Cloudflare DNS
After=network.target

[Service]
ExecStart=/usr/local/bin/update_cf_dns.sh

[Install]
WantedBy=multi-user.target
EOL

    # 启用并启动服务
    systemctl enable update-cf-dns.service
    systemctl start update-cf-dns.service

    echo -e "${GREEN}安装完成！DNS更新服务已设置并启动。${NC}"
}

# 检查服务状态
check_service_status() {
    STATUS=$(systemctl is-active update-cf-dns.service)

    if [ "$STATUS" = "active" ]; then
        echo -e "${GREEN}Cloudflare DNS 更新服务正在运行。${NC}"
    else
        echo -e "${RED}Cloudflare DNS 更新服务未运行。${NC}"
        echo "您可以使用以下命令启动服务："
        echo "sudo systemctl start update-cf-dns.service"
    fi

    echo -e "\n${YELLOW}最后一次运行的日志：${NC}"
    journalctl -u update-cf-dns.service -n 20 --no-pager
}

# 立即更新DNS
update_dns_now() {
    echo "正在手动运行 Cloudflare DNS 更新脚本..."
    /usr/local/bin/update_cf_dns.sh

    echo -e "\n${YELLOW}更新完成。以下是最新的日志：${NC}"
    journalctl -u update-cf-dns.service -n 20 --no-pager
}

# 卸载功能
uninstall() {
    check_root

    echo -e "${YELLOW}正在卸载 Cloudflare DNS 更新服务...${NC}"

    # 停止并禁用服务
    systemctl stop update-cf-dns.service
    systemctl disable update-cf-dns.service

    # 删除服务文件
    rm -f /etc/systemd/system/update-cf-dns.service

    # 删除更新脚本
    rm -f /usr/local/bin/update_cf_dns.sh

    # 重新加载 systemd 管理器配置
    systemctl daemon-reload

    echo -e "${GREEN}卸载完成。所有相关的组件、文件和服务已被删除。${NC}"
}

# 主菜单
show_menu() {
    echo -e "${YELLOW}==== Cloudflare DNS 管理器 ====${NC}"
    echo "1. 安装和配置"
    echo "2. 检查服务状态"
    echo "3. 立即更新DNS"
    echo "4. 卸载"
    echo "0. 退出"
    echo -e "${YELLOW}==============================${NC}"
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项 (0-4): " choice

    case $choice in
        1)
            install_and_configure
            ;;
        2)
            check_service_status
            ;;
        3)
            update_dns_now
            ;;
        4)
            uninstall
            ;;
        0)
            echo "谢谢使用，再见！"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选项，请重新选择。${NC}"
            ;;
    esac

    echo
    read -p "按回车键继续..."
    clear
done