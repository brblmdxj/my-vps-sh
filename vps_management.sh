#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请以root权限运行此脚本${NC}"
        exit 1
    fi
}

# 设置SSL证书
setup_ssl() {
    check_root

    # 安装必要的软件包
    apt update
    apt install -y certbot python3-certbot-dns-cloudflare

    # 函数：申请单域名证书
    apply_single_domain() {
        read -p "请输入您的域名: " domain
        certbot certonly --standalone -d $domain --agree-tos --email admin@$domain --rsa-key-size 4096
        copy_certs $domain
    }

    # 函数：申请泛域名证书
    apply_wildcard_domain() {
        read -p "请输入您的主域名（例如：example.com）: " domain
        read -p "请输入您的Cloudflare Global API Key: " cf_api_key
        read -p "请输入您的Cloudflare邮箱: " cf_email

        # 创建Cloudflare凭证文件
        mkdir -p /root/.secrets/certbot
        echo "dns_cloudflare_email = $cf_email" > /root/.secrets/certbot/cloudflare.ini
        echo "dns_cloudflare_api_key = $cf_api_key" >> /root/.secrets/certbot/cloudflare.ini
        chmod 600 /root/.secrets/certbot/cloudflare.ini

        certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
            -d $domain -d *.$domain --agree-tos --email admin@$domain --rsa-key-size 4096

        copy_certs $domain
    }

    # 函数：复制并重命名证书文件
    copy_certs() {
        local domain=$1
        cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/cert.crt
        cp /etc/letsencrypt/live/$domain/privkey.pem /etc/private.key
    }

    # SSL证书设置菜单
    while true; do
        echo "请选择操作："
        echo "1) 申请单域名证书"
        echo "2) 申请泛域名证书"
        echo "3) 返回主菜单"
        read -p "输入选项 (1-3): " ssl_choice

        case $ssl_choice in
            1)
                apply_single_domain
                break
                ;;
            2)
                apply_wildcard_domain
                break
                ;;
            3)
                return
                ;;
            *)
                echo "无效选项，请重新选择。"
                ;;
        esac
    done

    # 设置证书自动续期
    (crontab -l 2>/dev/null; echo "0 0 1 * * /usr/bin/certbot renew --quiet && cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/cert.crt && cp /etc/letsencrypt/live/$domain/privkey.pem /etc/private.key") | crontab -

    echo "证书已成功申请并设置自动续期。证书文件位于:"
    echo "/etc/cert.crt"
    echo "/etc/private.key"
}

# 启用root登录
enable_root_login() {
    check_root

    # 设置root密码
    echo "设置root密码"
    passwd root

    # 修改SSH配置
    echo "修改SSH配置"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

    # 重启SSH服务
    echo "重启SSH服务"
    if systemctl is-active --quiet ssh; then
        systemctl restart ssh
    elif systemctl is-active --quiet sshd; then
        systemctl restart sshd
    else
        echo "无法找到SSH服务，请手动重启SSH服务"
    fi

    # 检查AWS CLI是否已安装
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI未安装，正在尝试安装..."
        
        # 下载AWS CLI安装脚本
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        
        # 安装unzip（如果尚未安装）
        if ! command -v unzip &> /dev/null; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y unzip
            elif command -v yum &> /dev/null; then
                sudo yum install -y unzip
            else
                echo "无法安装unzip。请手动安装unzip后重试。"
                return
            fi
        fi
        
        # 解压并安装AWS CLI
        unzip awscliv2.zip
        sudo ./aws/install
        
        # 清理下载的文件
        rm -rf awscliv2.zip aws
    fi

    # 再次检查AWS CLI是否已安装
    if command -v aws &> /dev/null; then
        echo "AWS CLI已安装"
        
        # 检查AWS凭证
        if ! aws sts get-caller-identity &> /dev/null; then
            echo "AWS凭证未配置或无效"
            read -p "是否要配置AWS凭证？(y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                aws configure
            fi
        fi
        
        # 尝试修改实例元数据选项
        echo "尝试修改实例元数据选项..."
        TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
        INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/instance-id)
        if aws ec2 modify-instance-metadata-options --instance-id $INSTANCE_ID --http-tokens required --http-endpoint enabled; then
            echo "成功修改实例元数据选项"
        else
            echo "修改实例元数据选项失败，可能是由于权限不足或其他原因"
        fi
    else
        echo "AWS CLI安装失败或未找到，跳过修改实例元数据选项"
    fi

    echo "完成！现在您可以使用root用户和密码登录了。"
    echo "请记住，这种配置不太安全，建议仅在测试环境中使用。"
}

# 设置Cloudflare DNS更新器
setup_cf_dns_updater() {
    check_root

    # 提示用户输入Cloudflare信息
    read -p "请输入您的Cloudflare账户邮箱: " AUTH_EMAIL
    read -p "请输入您的Cloudflare Global API Key: " AUTH_KEY
    read -p "请输入您的Zone ID: " ZONE_ID
    read -p "请输入您要更新的域名: " RECORD_NAME

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

# 主菜单
show_menu() {
    echo -e "${YELLOW}==== 多功能VPS管理脚本 ====${NC}"
    echo "1. 设置SSL证书"
    echo "2. 启用root登录"
    echo "3. 设置Cloudflare DNS更新器"
    echo "4. 退出"
    echo -e "${YELLOW}==============================${NC}"
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项 (1-4): " choice

    case $choice in
        1)
            setup_ssl
            ;;
        2)
            enable_root_login
            ;;
        3)
            setup_cf_dns_updater
            ;;
        4)
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