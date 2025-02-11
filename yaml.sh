#!/bin/sh

# 检查是否提供了密码参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <password>"
    exit 1
fi

PASSWORD=$1

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# 下载并解压 clash.zip
if ! curl -s -o clash.zip http://nas/clash.zip; then
    echo "Error: 下载 clash.zip 失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 使用提供的密码解压 clash.zip
if ! unzip -P "$PASSWORD" clash.zip; then
    echo "Error: 解压 clash.zip 失败，可能是密码错误"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 读取解压后的 clash.txt 内容
url_part=$(cat clash.txt)

# 检查 URL 内容是否为空
if [ -z "$url_part" ]; then
    echo "Error: clash.txt 文件内容为空"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "最终 URL: $url_part"

# 使用 curl 下载 config.yaml 文件，并处理错误
if ! curl -o /etc/mihomo/config.yaml "$url_part"; then
    echo "Error: 下载 config.yaml 文件失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 清理临时文件和目录
cd - > /dev/null
rm -rf "$TEMP_DIR"

# 删除 ui 目录（如果存在），并忽略错误
rm -rf /etc/mihomo/ui && rm -rf /etc/mihomo/cache.db && rm -rf /etc/mihomo/rules

/etc/init.d/mihomo stop && /etc/init.d/mihomo start

echo "mihomo 配置已更新"

