#!/bin/bash
# SPDX-License-Identifier: MIT
# 私有自定义补丁

# =========================
# 修复 OpenClash 重启触发 crond 被 procd 连带重启、导致定时任务被吞的问题
# 原理：busybox 的 cron 初始化脚本里用 procd_set_param file 监视 crontab 文件，
#       文件内容一变化（哪怕是 OpenClash 自己重写一次）就会触发 crond 整体重启，
#       重启的空档期会漏掉本该触发的定时任务。这里去掉这个监视逻辑。
# =========================
echo " "
echo "开始修补 cron 初始化脚本..."

CRON_INIT="./package/utils/busybox/files/cron"

if [ -f "$CRON_INIT" ]; then
  cat > "$CRON_INIT" << 'EOF'
#!/bin/sh /etc/rc.common
# Copyright (C) 2006-2011 OpenWrt.org

START=50

USE_PROCD=1
PROG=/usr/sbin/crond

validate_cron_section() {
	uci_validate_section system system "${1}" \
		'cronloglevel:uinteger'
}

start_service() {
	[ -z "$(ls /etc/crontabs/)" ] && return 1

	loglevel="$(uci_get "system.@system[0].cronloglevel")"

	[ -z "${loglevel}" ] || {
		/sbin/validate_data uinteger "${loglevel}" 2>/dev/null
		[ "$?" -eq 0 ] || {
			echo "validation failed"
			return 1
		}
	}

	mkdir -p /var/spool/cron
	ln -s /etc/crontabs /var/spool/cron/ 2>/dev/null

	procd_open_instance
	procd_set_param command "$PROG" -f -c /etc/crontabs -l "${loglevel:-7}"
	procd_set_param respawn
	procd_close_instance
}

service_triggers() {
	procd_add_validation validate_cron_section
}
EOF
  chmod 755 "$CRON_INIT"
  echo "cron 脚本修补完成：已移除 crontab 文件监视"
else
  echo "警告: 未找到 $CRON_INIT，请确认 OpenWrt 版本与源码路径"
fi
