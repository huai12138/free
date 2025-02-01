#!/bin/bash

# URL编码函数
encode_url() {
    cat "$1" | tr -d '\r' | python -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()), end='')"
}

# 检查参数
[ $# -ne 1 ] && { echo "用法: ./encode.sh <mitce|bajie>"; exit 1; }

# 选择源文件
case "$1" in
    "mitce") SOURCE_FILE="mitce.txt" ;;
    "bajie") SOURCE_FILE="bajie.txt" ;;
    *) echo "参数错误: 请使用 mitce 或 bajie"; exit 1; ;;
esac

[ ! -f "$SOURCE_FILE" ] && { echo "错误: 找不到 $SOURCE_FILE"; exit 1; }

# 生成 URLs
printf "http://nas:5000/" > singbox.txt
encode_url "$SOURCE_FILE" >> singbox.txt
printf "\n" >> singbox.txt

printf "http://nas:5002/" > clash.txt
encode_url "$SOURCE_FILE" >> clash.txt
printf "\n" >> clash.txt

# 显示结果
printf "\n=== Singbox URL ===\n"
cat singbox.txt
printf "\n=== Clash URL ===\n"
cat clash.txt

