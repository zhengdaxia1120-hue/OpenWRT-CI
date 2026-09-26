#!/bin/bash
# 私有自定义补丁：禁用 procd 对 crontab 文件的监视重启,避免 OpenClash 重启时连带重启 crond、吞掉定时任务

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
  echo "cron 脚本修补完成：已移除 crontab 文件监视"
else
  echo "警告: 未找到 $CRON_INIT，请确认 OpenWrt 版本与源码路径"
fi
