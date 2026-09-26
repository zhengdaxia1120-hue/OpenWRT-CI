# =========================
# 修复 OpenClash 重启触发 crond 被 procd 连带重启、导致定时任务被吞的问题
# =========================
CRON_INIT="./package/utils/busybox/files/cron"

if [ -f "$CRON_INIT" ]; then
  sed '/procd_set_param file "\$crontab"/d' "$CRON_INIT" > "$CRON_INIT.tmp" && mv "$CRON_INIT.tmp" "$CRON_INIT"
  echo "cron 脚本修补完成：已移除 crontab 文件监视"
else
  echo "警告: 未找到 $CRON_INIT，请确认源码路径"
fi
