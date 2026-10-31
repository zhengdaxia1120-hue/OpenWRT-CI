#!/bin/sh
# WAN 拨号成功后，等 IPv6 就绪，再启动 DDNS（服务本身保持禁用）
[ "$ACTION" = "ifup" ] || exit 0
case "$INTERFACE" in
    wan|wan6) ;;
    *) exit 0 ;;
esac

(
    # 最多等待 5 分钟，直到 pppoe-wan 拿到全局 IPv6 地址
    for i in $(seq 1 60); do
        ip -6 addr show dev pppoe-wan scope global | grep -q inet6 && break
        sleep 5
    done
    sleep 10
    /etc/init.d/ddns restart
) &
