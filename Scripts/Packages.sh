#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"

		local FOUND_DIRS
		FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ \
			-maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				[ -n "$DIR" ] || continue
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 删除之前可能存在的同名仓库
	rm -rf "$REPO_PATH"

	# 克隆 GitHub 仓库
	echo "Clone: https://github.com/$PKG_REPO.git"
	git clone --depth=1 --single-branch \
		--branch "$PKG_BRANCH" \
		"https://github.com/$PKG_REPO.git" \
		"$REPO_PATH"

	if [ $? -ne 0 ]; then
		echo "Failed to clone $PKG_REPO"
		return 1
	fi

	# 处理需要提取 package 的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "$REPO_PATH" -mindepth 2 -maxdepth 3 \
			-type d -iname "*$PKG_NAME*" -prune \
			-exec cp -rf {} ./package \;

		rm -rf "$REPO_PATH"
	fi
}

# =========================
# LuCI 主题
# =========================
# UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "argon" "jerrykuku/luci-theme-argon" "master"

# =========================
# 科学上网
# =========================
# UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "master" "pkg"
echo " "
echo "Search directory: openclash"
rm -rf ./feeds/luci/applications/luci-app-openclash
rm -rf ./package/OpenClash
git clone --depth=1 --single-branch --branch dev \
    https://github.com/vernesong/OpenClash.git ./package/OpenClash
find ./package/OpenClash -maxdepth 2 -type d -iname "luci-app-openclash" \
    -exec cp -rf {} ./package/ \;
rm -rf ./package/OpenClash

# =========================
# 网络/系统工具
# =========================
# UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
# UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
# UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
# UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"

# =========================
# Viking 扩展包
# =========================
# UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac sing-box luci-app-homeproxy luci-app-timewol luci-app-wolplus luci-app-wolultra"

# =========================
# 其他插件（暂不使用）
# =========================
# UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
# UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
# UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
# UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

# =========================
# 存储相关：无外挂硬盘，不使用
# =========================
# UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
# UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
# UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
# UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
# UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
# UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"

# =========================
# DNS
# =========================
# 如果确定不用 mosdns，则暂时不加入
# UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"

# =========================
# NAT / STUN
# =========================
# CONFIG_PACKAGE_luci-app-natmapt=n，所以这里不拉
# UPDATE_PACKAGE "natmapt" "muink/openwrt-natmapt" "master"
# UPDATE_PACKAGE "stuntman" "muink/openwrt-stuntman" "master"
# UPDATE_PACKAGE "luci-app-natmapt" "muink/luci-app-natmapt" "master"

# =========================
# 4G / 5G Modem
# =========================
# UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
# UPDATE_PACKAGE "fm350" "LianXia233/luci-app-fm350" "main"
# UPDATE_PACKAGE "h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"
# UPDATE_PACKAGE "mt5700" "LianXia233/luci-app-mt5700" "main"
# UPDATE_PACKAGE "mt5700m" "LianXia233/luci-app-mt5700m" "main"
# UPDATE_PACKAGE "qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"

# =========================
# 其他硬件专用插件
# =========================
# UPDATE_PACKAGE "airpi3000m-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main"
# UPDATE_PACKAGE "chfs" "LianXia233/luci-app-chfs" "main"
# UPDATE_PACKAGE "netmonitor" "LianXia233/luci-app-netmonitor" "main"
# UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"


# 更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}

	local PKG_FILES
	PKG_FILES=$(find ./ ./feeds/packages/ \
		-maxdepth 3 \
		-type f \
		-wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do

		local PKG_REPO
		PKG_REPO=$(grep -Po \
			"PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" \
			"$PKG_FILE")

		if [ -z "$PKG_REPO" ]; then
			echo "$PKG_NAME GitHub repository not found!"
			continue
		fi

		local PKG_TAG
		PKG_TAG=$(curl -sL \
			"https://api.github.com/repos/$PKG_REPO/releases" |
			jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		if [ -z "$PKG_TAG" ] || [ "$PKG_TAG" = "null" ]; then
			echo "$PKG_NAME latest release not found!"
			continue
		fi

		local OLD_VER
		local OLD_URL
		local OLD_FILE
		local OLD_HASH

		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL
		PKG_URL=$(
			[[ "$OLD_URL" == *"releases"* ]] &&
			echo "${OLD_URL%/}/$OLD_FILE" ||
			echo "${OLD_URL%/}"
		)

		local NEW_VER
		NEW_VER=$(echo "$PKG_TAG" |
			sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')

		local NEW_URL
		NEW_URL=$(echo "$PKG_URL" |
			sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")

		local NEW_HASH
		NEW_HASH=$(curl -sL "$NEW_URL" |
			sha256sum |
			cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] &&
			dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then

			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"

			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

# UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
# UPDATE_VERSION "sing-box"


# 引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
