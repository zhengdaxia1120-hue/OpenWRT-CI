#!/bin/bash
# 私有自定义补丁

# =========================
# 修复 OpenClash 重启触发 crond 被 procd 连带重启、导致定时任务被吞的问题
# =========================
echo " "
echo "修补 cron 初始化脚本,禁用 procd 对 crontab 文件的监视重启..."

CRON_INIT="./package/base-files/files/etc/init.d/cron"

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
  echo "cron 初始化脚本修补完成"
else
  echo "警告: 未找到 $CRON_INIT，路径可能不对，请检查"
fi
