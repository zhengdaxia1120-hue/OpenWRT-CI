#!/bin/sh
# 首次开机时禁用 DDNS，由 hotplug 在 WAN 就绪后启动
[ -f /etc/init.d/ddns ] && /etc/init.d/ddns disable
exit 0
