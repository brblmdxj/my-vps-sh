#!/bin/bash

# 检查是否在 Git 仓库中
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "错误: 当前目录不是 Git 仓库。"
    exit 1
fi

# 获取当前分支名
current_branch=$(git rev-parse --abbrev-ref HEAD)

# 添加所有更改
echo "添加所有更改..."
git add .

# 自动生成提交信息
commit_message="自动更新 $(date '+%Y-%m-%d %H:%M:%S')"

# 提交更改
echo "提交更改..."
git commit -m "$commit_message"

# 推送到 GitHub
echo "推送到 GitHub..."
if git push origin $current_branch; then
    echo "成功推送所有更改到 GitHub！"
else
    echo "推送失败。请检查您的网络连接和 GitHub 凭证。"
    exit 1
fi