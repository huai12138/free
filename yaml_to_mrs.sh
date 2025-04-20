#!/bin/bash

mihomo convert-ruleset "domain" yaml "proxy.yaml" "proxy.mrs"
mihomo convert-ruleset "domain" yaml "direct.yaml" "direct.mrs"



mihomo convert-ruleset "ipcidr" yaml "pass-ip.yaml" "pass-ip.mrs"
mihomo convert-ruleset "ipcidr" yaml "direct-ip.yaml" "direct-ip.mrs"

echo "所有YAML文件转换完成"

