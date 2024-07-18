#!/bin/bash

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要以root权限运行" 1>&2
   exit 1
fi

# 获取当前登录的用户名
CURRENT_USER=$(logname)

# 将用户添加到docker组
usermod -aG docker $CURRENT_USER

# 创建sudoers文件
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/dockerd" > /etc/sudoers.d/docker-admin

# 设置正确的权限
chmod 0440 /etc/sudoers.d/docker-admin

echo "已将用户 $CURRENT_USER 添加到docker组并授予Docker管理员权限"
echo "请注销并重新登录以使更改生效"