#!/bin/bash

# URL编码函数
encode_url() {
    echo "$1" | python -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()), end='')"
}

# 检查参数
[ $# -ne 3 ] && { echo "用法: ./encode.sh <mitce|bajie|milkcloud|aifun> <input_password> <output_password>"; exit 1; }

# 保存当前工作目录
CURRENT_DIR=$(pwd)

# 检查0.zip是否存在
[ ! -f "0.zip" ] && { echo "错误: 找不到 0.zip"; exit 1; }

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# 使用7z解压0.zip到临时目录，使用第二个参数作为密码
7z x -p"$2" 0.zip -o"$TEMP_DIR" >/dev/null 2>&1 || { echo "错误: 解压失败，请检查密码是否正确"; exit 1; }

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

# 生成 Singbox URL
printf "http://nas:5000/" > "$TEMP_DIR/singbox.txt"
encode_url "$URL" >> "$TEMP_DIR/singbox.txt"
printf "\n" >> "$TEMP_DIR/singbox.txt"

# 生成 Clash URL
printf "http://nas:5002/" > "$TEMP_DIR/clash.txt"
encode_url "$URL" >> "$TEMP_DIR/clash.txt"
printf "\n" >> "$TEMP_DIR/clash.txt"

# 显示结果
printf "\n=== Singbox URL ===\n"
cat "$TEMP_DIR/singbox.txt"
printf "\n=== Clash URL ===\n"
cat "$TEMP_DIR/clash.txt"

# 定义压缩函数
compress_file() {
    local input="$1"
    local output="$2"
    local password="$3"
    
    # 确保输入文件存在
    [ ! -f "$input" ] && { echo "错误: 输入文件 $input 不存在"; return 1; }
    
    # 删除已存在的输出文件（使用完整路径）
    [ -f "$CURRENT_DIR/$output" ] && rm -f "$CURRENT_DIR/$output"
    
    # 在临时目录中压缩文件
    cd "$TEMP_DIR" || return 1
    
    # 使用绝对路径创建压缩文件
    if ! 7z a -p"$password" -tzip "$TEMP_DIR/$output" "$(basename $input)" >/dev/null 2>&1; then
        echo "错误: 压缩 $output 失败"
        echo "详细错误信息:"
        7z a -p"$password" -tzip "$TEMP_DIR/$output" "$(basename $input)" 2>&1
        return 1
    fi
    
    # 将压缩文件移动到当前目录
    mv "$TEMP_DIR/$output" "$CURRENT_DIR/$output" || { echo "错误: 移动文件失败"; return 1; }
    
    return 0
}

# 压缩 Singbox 文件
if ! compress_file "$TEMP_DIR/singbox.txt" "singbox.zip" "$3"; then
    exit 1
fi

# 压缩 Clash 文件
if ! compress_file "$TEMP_DIR/clash.txt" "clash.zip" "$3"; then
    exit 1
fi

# 显示结果
echo "文件已加密保存为 singbox.zip 和 clash.zip"
echo "使用密码 '$3' 可以解压文件"