#!/bin/bash

# URL编码函数
encode_url() {
    echo "$1" | python -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()), end='')"
}

# 检查参数
[ $# -ne 1 ] && { echo "用法: ./encode.sh <mitce|bajie|milkcloud|aifun>"; exit 1; }

# 检查0.zip是否存在
[ ! -f "0.zip" ] && { echo "错误: 找不到 0.zip"; exit 1; }

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# 使用7z解压0.zip到临时目录
7z x -p1107530255 0.zip -o"$TEMP_DIR" >/dev/null 2>&1 || { echo "错误: 解压失败"; exit 1; }

# 根据参数获取对应的URL
case "$1" in
    "mitce") 
        URL=$(grep "mitce:" "$TEMP_DIR/0.txt" | cut -d' ' -f2) ;;
    "bajie") 
        URL=$(grep "bajie:" "$TEMP_DIR/0.txt" | cut -d' ' -f2) ;;
    "milkcloud") 
        URL=$(grep "milkcloud:" "$TEMP_DIR/0.txt" | cut -d' ' -f2) ;;   
    "aifun") 
        URL=$(grep "aifun:" "$TEMP_DIR/0.txt" | cut -d' ' -f2) ;;
    *) 
        echo "参数错误: 请使用 mitce、bajie、milkcloud 或 aifun"
        exit 1
        ;;
esac

[ -z "$URL" ] && { echo "错误: 在解压的文件中找不到对应的URL"; exit 1; }

# 生成 URLs
printf "http://nas:5000/" > singbox.txt
encode_url "$URL" >> singbox.txt
printf "\n" >> singbox.txt

printf "http://nas:5002/" > clash.txt
encode_url "$URL" >> clash.txt
printf "\n" >> clash.txt

# 显示结果
printf "\n=== Singbox URL ===\n"
cat singbox.txt
printf "\n=== Clash URL ===\n"
cat clash.txt

