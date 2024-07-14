#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始一键安装和执行VPS管理脚本...${NC}"

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请以root权限运行此脚本"
    exit 1
fi

# 安装git（如果尚未安装）
if ! command -v git &> /dev/null; then
    echo "正在安装git..."
    apt-get update && apt-get install -y git
fi

# 克隆或更新仓库
if [ -d "my-vps-sh" ]; then
    echo "更新现有仓库..."
    cd my-vps-sh
    git pull
else
    echo "克隆仓库..."
    git clone https://github.com/brblmdxj/my-vps-sh.git
    cd my-vps-sh
fi

# 给脚本添加执行权限
chmod +x vps_management.sh

# 执行脚本
echo -e "${GREEN}开始执行VPS管理脚本...${NC}"
./vps_management.sh

echo -e "${GREEN}脚本执行完毕${NC}"