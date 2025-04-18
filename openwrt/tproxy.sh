#!/bin/sh

# 设置默认模式,转换为大写以便统一比较
MODE=$(echo "${1:-clean}" | tr '[a-z]' '[A-Z]')  # 使用确定的字符范围进行转换

# 验证输入的模式是否有效
case "$MODE" in
    "SINGBOX"|"CLEAN")
        echo "当前运行模式: ${1:-clean}"  # 显示原始输入
        ;;
    *)
        echo "错误: 无效的模式 '${1:-clean}'"
        echo "用法: $0 [singbox|clean]"
        exit 1
        ;;
esac

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 此脚本需要 root 权限运行"
    exit 1
fi

# 配置参数
SINGBOX_PORT=7893  # 与 sing-box 中定义的一致
ROUTING_MARK=666   # 与 sing-box 中定义的一致
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100

# 获取默认接口，增加错误处理
INTERFACE=$(ip route show default | awk '/default/ {print $5}')
if [ -z "$INTERFACE" ]; then
    echo "错误: 无法获取默认网络接口"
    exit 1
fi

# 保留 IP 地址集合
ReservedIP4='{ 127.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 198.51.100.0/24, 192.88.99.0/24, 192.168.0.0/16, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 }'


# 检查必要工具是否存在
check_requirements() {
    for cmd in ip nft sysctl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "错误: 未找到必需的命令: $cmd"
            exit 1
        fi
    done
}

# 检查指定路由表是否存在
check_route_exists() {
    ip route show table "$1" >/dev/null 2>&1
    return $?
}

# 创建路由表，如果不存在的话
create_route_table_if_not_exists() {
    if ! check_route_exists "$PROXY_ROUTE_TABLE"; then
        echo "路由表不存在，正在创建..."
        ip route add local default dev "$INTERFACE" table "$PROXY_ROUTE_TABLE" || { echo "创建路由表失败"; exit 1; }
    fi
}

# 等待 FIB 表加载完成
wait_for_fib_table() {
    i=1
    while [ $i -le 10 ]; do
        if ip route show table "$PROXY_ROUTE_TABLE" >/dev/null 2>&1; then
            return 0
        fi
        echo "等待 FIB 表加载中，等待 $i 秒..."
        sleep 1
        i=$((i + 1))
    done
    echo "FIB 表加载失败，超出最大重试次数"
    return 1
}

# 清理现有 sing-box 防火墙规则
clearSingboxRules() {
    if nft list table inet sing-box >/dev/null 2>&1; then
        nft delete table inet sing-box
    fi
    
    ip rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null || true
    ip route del local default dev "${INTERFACE}" table $PROXY_ROUTE_TABLE 2>/dev/null || true
    echo "清理 sing-box 相关的防火墙规则"
}

# 主程序开始
main() {
    # 检查必要工具
    check_requirements
    
    clearSingboxRules

    # 如果是 clean 模式,到此结束
    if [ "$MODE" = "CLEAN" ]; then
        echo "已清理所有 sing-box 相关的防火墙规则"
        exit 0
    fi

    # 仅在 SingBox 模式下应用新的防火墙规则
    if [ "$MODE" = "SINGBOX" ]; then
        echo "应用 SingBox 模式下的防火墙规则..."

        # 创建并确保路由表存在
        create_route_table_if_not_exists

        # 等待 FIB 表加载完成
        if ! wait_for_fib_table; then
            echo "FIB 表准备失败，退出脚本。"
            exit 1
        fi

        # 设置 IP 规则和路由
        ip rule add fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE || { echo "添加 IP 规则失败"; exit 1; }
        ip route add local default dev "$INTERFACE" table $PROXY_ROUTE_TABLE || { echo "添加路由失败"; exit 1; }
        sysctl -w net.ipv4.ip_forward=1 > /dev/null || { echo "启用 IP 转发失败"; exit 1; }

        # 确保目录存在
        mkdir -p /etc/sing-box/nft

        # 手动创建 inet 表
        nft add table inet sing-box

        # 设置 SingBox 模式下的 nftables 规则
        cat > /etc/sing-box/nft/nftables.conf <<EOF
table inet sing-box {
    set RESERVED_IPSET {
        type ipv4_addr
        flags interval
        auto-merge
        elements = $ReservedIP4
    }

    chain prerouting_singbox {
        type filter hook prerouting priority mangle; policy accept;

        # 确保 DHCP 数据包不被拦截 UDP 67/68
        udp dport { 67, 68 } accept comment "Allow DHCP traffic"
        
        # DNS 请求重定向到本地 SingBox 端口
        meta l4proto { tcp, udp } th dport 53 tproxy to :$SINGBOX_PORT accept

        # 拒绝访问本地 TProxy 端口
        fib daddr type local meta l4proto { tcp, udp } th dport $SINGBOX_PORT reject with icmpx type host-unreachable

        # 本地地址绕过
        fib daddr type local accept

        # 保留地址绕过
        ip daddr @RESERVED_IPSET accept

        #放行所有经过 DNAT 的流量
        ct status dnat accept comment "Allow forwarded traffic"

        # 重定向剩余流量到 SingBox 端口并设置标记
        meta l4proto { tcp, udp } tproxy to :$SINGBOX_PORT meta mark set $PROXY_FWMARK
    }

    chain output_singbox {
        type route hook output priority mangle; policy accept;

        # 放行本地回环接口流量
        meta oifname "lo" accept

        # 本地 sing-box 发出的流量绕过
        meta mark $ROUTING_MARK accept

        # DNS 请求标记
        meta l4proto { tcp, udp } th dport 53 meta mark set $PROXY_FWMARK

        # 绕过 NBNS 流量
        udp dport { netbios-ns, netbios-dgm, netbios-ssn } accept

        # 本地地址绕过
        fib daddr type local accept

        # 保留地址绕过
        ip daddr @RESERVED_IPSET accept

        # 标记并重定向剩余流量
        meta l4proto { tcp, udp } meta mark set $PROXY_FWMARK
    }
}
EOF

        # 应用防火墙规则和 IP 路由
        echo "正在应用 nftables 规则..."
        if ! nft -f /etc/sing-box/nft/nftables.conf; then
            echo "错误: 应用 nftables 规则失败"
            exit 1
        fi
        # 持久化防火墙规则
        # nft list ruleset > /etc/nftables.conf

        echo "SingBox 模式的防火墙规则已成功应用。"
    fi
}

# 执行主程序
main