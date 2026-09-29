#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 移除 luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec \
	sed -i "/attendedsysupgrade/d" {} +

# 修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec \
	sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +

# 修改 immortalwrt.lan 关联 IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec \
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +

# 添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec \
	sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +


# WIFI 配置
WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ \
	-type f -name "*set-wireless.sh" 2>/dev/null)

WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -n "$WIFI_SH" ]; then
	# 修改 WIFI 名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"

	# 修改 WIFI 密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"

elif [ -f "$WIFI_UC" ]; then
	# 修改 WIFI 名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" "$WIFI_UC"

	# 修改 WIFI 密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" "$WIFI_UC"
fi


# 默认配置文件
CFG_FILE="./package/base-files/files/bin/config_generate"

# 修改默认 IP 地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"

# 修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"


# 配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config


# 引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat "$GITHUB_WORKSPACE/Config/PRIVATE.txt" >> ./.config
fi


# 手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi


# 无 WIFI 配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> "$GITHUB_ENV"
fi


# 高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"

if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then

	# 无 WIFI 配置调整 Q6 大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find "$DTS_PATH" -type f ! -iname '*nowifi*' -exec \
			sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +

		echo "qualcommax set up nowifi successfully!"
	fi

fi

#
# ===== 内置 0 点openclash自动更新 =====
mkdir -p files/etc/init.d files/etc/uci-defaults

cat > files/etc/data-update.sh <<'EOF'
#!/bin/sh
TARGET="00:00"
DIR=/usr/share/openclash
LOG=/tmp/dataupdate.log

log() { echo "$(date '+%F %T') $*" >> $LOG; }

run() {
  [ -f "$DIR/$1" ] || { log "skip $1 (not found)"; return; }
  log "run $*"
  sh "$DIR/$@" >/dev/null 2>&1
  sleep 5
}

do_update() {
  log "=== update start ==="
  run openclash_geo.sh ipdb
  run openclash_geo.sh geosite
  run openclash_geo.sh geoip
  run openclash_geo.sh geoasn
  run openclash_chnroute.sh
  run openclash.sh
  if [ "$(uci -q get openclash.config.enable)" = "1" ]; then
    sleep 60
    if ! pidof clash >/dev/null; then
      log "not running after update, starting"
      /etc/init.d/openclash start
    fi
  fi
  log "=== update done ==="
}

if [ "$1" = "once" ]; then
  do_update
  exit 0
fi

while true; do
  today=$(date +%F)
  if [ "$(date +%H:%M)" = "$TARGET" ] && [ "$(cat /tmp/dataupdate.day 2>/dev/null)" != "$today" ]; then
    echo "$today" > /tmp/dataupdate.day
    do_update
  fi
  sleep 30
done
EOF

cat > files/etc/init.d/dataupdate <<'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
  procd_open_instance
  procd_set_param command /etc/data-update.sh
  procd_set_param respawn
  procd_close_instance
}
EOF

cat > files/etc/uci-defaults/99-dataupdate <<'EOF'
#!/bin/sh
/etc/init.d/dataupdate enable
/etc/init.d/dataupdate start
exit 0
EOF

chmod +x files/etc/data-update.sh files/etc/init.d/dataupdate files/etc/uci-defaults/99-dataupdate
# ===== 结束 =====
