#!/bin/sh

# 检查参数数量
if [ $# -ne 2 ]; then
    echo "用法: $0 <订阅名称> <密码>"
    exit 1
fi

SUBSCRIPTION=$1
PASSWORD=$2

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# 下载并解压 clash.zip
if ! curl -s -o clash.zip http://nas/clash.zip; then
    echo "错误: 下载 clash.zip 失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 使用提供的密码解压 clash.zip
if ! unzip -P "$PASSWORD" clash.zip; then
    echo "错误: 解压 clash.zip 失败，可能是密码错误"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 根据参数获取对应的 URL
url_part=$(grep "^$SUBSCRIPTION:" clash.txt | cut -d' ' -f2)

# 检查 URL 内容是否为空
if [ -z "$url_part" ]; then
    echo "错误: 无效的订阅选项 '$SUBSCRIPTION'"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "选择的订阅: $SUBSCRIPTION"
echo "使用的 URL: $url_part"

# 使用 curl 下载 config.yaml 文件，并处理错误
if ! curl -o /etc/mihomo/config.yaml "$url_part"; then
    echo "错误: 下载 config.yaml 文件失败"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 清理临时文件和目录
cd - > /dev/null
rm -rf "$TEMP_DIR"

# 删除 ui 目录（如果存在），并忽略错误
rm -rf /etc/mihomo/ui && rm -rf /etc/mihomo/cache.db && rm -rf /etc/mihomo/rules

(/etc/init.d/mihomo stop && /etc/init.d/mihomo start) > /dev/null 2>&1 

echo "mihomo 配置已更新 (订阅: $SUBSCRIPTION)"

