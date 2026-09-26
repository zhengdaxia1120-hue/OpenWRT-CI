#!/bin/bash
# 私有自定义补丁：禁用 procd 对 crontab 文件的监视重启，避免 OpenClash 重启时连带重启 crond、吞掉定时任务

CRON_INIT="./package/utils/busybox/files/cron"

if [ -f "$CRON_INIT" ]; then
  # 删掉"文件变更即重启 crond"的那一行（新版 OpenWrt 用 procd_set_param file 监视 crontab）
  sed '/procd_set_param file "\$crontab"/d' "$CRON_INIT" > "$CRON_INIT.tmp" && mv "$CRON_INIT.tmp" "$CRON_INIT"
  echo "cron 脚本修补完成：已移除 crontab 文件监视"
else
  echo "警告: 未找到 $CRON_INIT，请确认 OpenWrt 版本与源码路径"
fi
