#!/bin/sh

# 检查是否提供了密码参数
if [ -z "$1" ]; then
    echo "Error: 请提供解压密码作为参数"
    echo "用法: $0 <密码>"
    exit 1
fi

/etc/init.d/sing-box stop

# 创建临时目录
temp_dir=$(mktemp -d)

# 从远程下载zip文件
if ! curl -s -o "$temp_dir/singbox.zip" "http://nas/singbox.zip"; then
    echo "Error: 下载 singbox.zip 失败"
    rm -rf "$temp_dir"
    exit 1
fi

# 解压zip文件以获取txt文件
if ! unzip -P "$1" "$temp_dir/singbox.zip" -d "$temp_dir"; then
    echo "Error: 解压 zip 文件失败"
    rm -rf "$temp_dir"
    exit 1
fi

# 读取解压后的txt文件内容获取URL
url_part=$(cat "$temp_dir/singbox.txt")

# 检查URL内容是否为空
if [ -z "$url_part" ]; then
    echo "Error: singbox.txt 文件内容为空"
    rm -rf "$temp_dir"
    exit 1
fi

echo "最终 URL: $url_part"

# 下载配置文件
if ! curl -o /etc/sing-box/config.json "$url_part"; then
    echo "Error: 下载 config.json 文件失败"
    rm -rf "$temp_dir"
    exit 1
fi

# 清理临时目录
rm -rf "$temp_dir"

# 删除 ui 目录（如果存在），并忽略错误
rm -rf /usr/share/sing-box/ui && rm -rf /usr/share/sing-box/cache.db

/etc/init.d/sing-box start

echo "sing-box 配置已更新。"

