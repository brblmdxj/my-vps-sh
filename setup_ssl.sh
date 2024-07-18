#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请以 root 权限运行此脚本${NC}"
  exit 1
fi

# 安装必要的软件包
install_packages() {
  echo -e "${YELLOW}正在安装必要的软件包...${NC}"
  apt update
  apt install -y certbot python3-certbot-dns-cloudflare
}

# 函数：申请单域名证书
apply_single_domain() {
  read -p "请输入您的域名: " domain
  echo -e "${YELLOW}正在申请单域名证书...${NC}"
  certbot certonly --standalone -d $domain --agree-tos --email admin@$domain --rsa-key-size 4096
  if [ $? -eq 0 ]; then
    copy_certs $domain
    echo -e "${GREEN}单域名证书申请成功！${NC}"
  else
    echo -e "${RED}单域名证书申请失败，请检查错误信息并重试。${NC}"
  fi
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

  echo -e "${YELLOW}正在申请泛域名证书...${NC}"
  certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
    -d $domain -d *.$domain --agree-tos --email admin@$domain --rsa-key-size 4096

  if [ $? -eq 0 ]; then
    copy_certs $domain
    echo -e "${GREEN}泛域名证书申请成功！${NC}"
  else
    echo -e "${RED}泛域名证书申请失败，请检查错误信息并重试。${NC}"
  fi
}

# 函数：复制并重命名证书文件
copy_certs() {
  local domain=$1
  cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/cert.crt
  cp /etc/letsencrypt/live/$domain/privkey.pem /etc/private.key
  echo -e "${GREEN}证书文件已复制到 /etc/cert.crt 和 /etc/private.key${NC}"
}

# 设置证书自动续期
setup_auto_renewal() {
  local domain=$1
  (crontab -l 2>/dev/null; echo "0 0 1 * * /usr/bin/certbot renew --quiet && cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/cert.crt && cp /etc/letsencrypt/live/$domain/privkey.pem /etc/private.key") | crontab -
  echo -e "${GREEN}证书自动续期已设置${NC}"
}

# 主菜单
main_menu() {
  while true; do
    echo -e "${YELLOW}请选择操作：${NC}"
    echo "1) 申请单域名证书"
    echo "2) 申请泛域名证书"
    echo "3) 退出"
    read -p "输入选项 (1-3): " choice

    case $choice in
      1)
        apply_single_domain
        setup_auto_renewal $domain
        break
        ;;
      2)
        apply_wildcard_domain
        setup_auto_renewal $domain
        break
        ;;
      3)
        echo -e "${GREEN}脚本终止。${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}无效选项，请重新选择。${NC}"
        ;;
    esac
  done
}

# 主程序
install_packages
main_menu

echo -e "${GREEN}证书已成功申请并设置自动续期。证书文件位于:${NC}"
echo "/etc/cert.crt"
echo "/etc/private.key"