#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本"
  exit 1
fi

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

# 主菜单
while true; do
  echo "请选择操作："
  echo "1) 申请单域名证书"
  echo "2) 申请泛域名证书"
  echo "3) 退出"
  read -p "输入选项 (1-3): " choice

  case $choice in
    1)
      apply_single_domain
      break
      ;;
    2)
      apply_wildcard_domain
      break
      ;;
    3)
      echo "脚本终止。"
      exit 0
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