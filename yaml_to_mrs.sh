#!/bin/bash

# 询问用户选择规则集类型，设置默认值为 1
echo "请选择规则集类型（输入 1 选择 domain，输入 2 选择 ipcidr，默认为 1）："
read choice

# 如果用户没有输入，使用默认值 1
if [[ -z "$choice" ]]; then
    choice="1"
fi

# 根据选择的规则集类型设置备注
if [[ "$choice" == "1" ]]; then
    RULESET_DESC="domain"
elif [[ "$choice" == "2" ]]; then
    RULESET_DESC="ipcidr"
else
    echo "无效选择，请输入 1 或 2。"
    exit 1
fi

# 询问用户输入文件名称，设置默认值
echo "请输入输入文件的名称（直接按回车将使用 proxy.yaml）："
read INPUT_FILE

# 如果用户没有输入，使用默认文件名
if [[ -z "$INPUT_FILE" ]]; then
    INPUT_FILE="proxy.yaml"
fi

# 检查输入文件是否存在
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "输入文件不存在，请检查文件名。"
    exit 1
fi

# 自定义输出文件名，根据输入文件名称生成
OUTPUT_FILE="${INPUT_FILE%.*}.mrs"

# 执行转换（替换为你的具体命令）
mihomo convert-ruleset "$RULESET_DESC" yaml "$INPUT_FILE" "$OUTPUT_FILE"

echo "转换完成：$OUTPUT_FILE"

