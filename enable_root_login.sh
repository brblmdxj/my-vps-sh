#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本"
  exit 1
fi

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
            exit 1
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