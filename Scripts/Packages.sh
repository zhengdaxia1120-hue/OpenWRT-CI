
#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not fonud directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git" $REPO_PATH

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find $REPO_PATH/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf $REPO_PATH
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。
# UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "argon" "jerrykuku/luci-theme-argon" "master"
# UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
# UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"

# =========================
# UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" " luci-app-homeproxy "

# =========================
# AdGuardHome
# =========================
# UPDATE_PACKAGE "luci-app-adguardhome" "rufengsuixing/luci-app-adguardhome" "master" "" "adguardhome luci-app-adguardhome"
# =========================
# 科学上网
# =========================
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "master" "pkg"

# =========================
# 从 owrt 分支移植 luci-app-router-tool（含中继AP模式）
# 仅当源码树中没有该包时才下载（owrt 分支自带，会自动跳过）
# =========================
if [ ! -d "./package/emortal/luci-app-router-tool" ]; then
	echo ">>> 源码树缺少 luci-app-router-tool，从 owrt 分支移植..."
	OWRT_TARBALL=$(mktemp)
	if curl -sL --retry 3 --connect-timeout 30 \
		"https://github.com/VIKINGYFY/immortalwrt/archive/refs/heads/owrt.tar.gz" -o "$OWRT_TARBALL"; then
		if tar xzf "$OWRT_TARBALL" --strip-components=2 \
			-C ./package "immortalwrt-owrt/package/emortal/luci-app-router-tool"; then
			echo ">>> luci-app-router-tool 移植成功"
		else
			echo ">>> luci-app-router-tool 解包失败，跳过（中继AP模式将不可用）"
		fi
	else
		echo ">>> owrt 源码包下载失败，跳过 luci-app-router-tool 移植"
	fi
	rm -f "$OWRT_TARBALL"
fi

# =========================
# 内核补丁版本对齐：跟随 owrt 分支的内核 patch 版本
# （如 main 为 6.18.55 而 owrt 已升到 6.18.60，则自动同步版本定义，含官方 hash）
# 仅替换版本定义文件，补丁集保持本分支原样；若个别补丁应用失败需按日志处理
# =========================
KVER_FILE="./target/linux/generic/kernel-6.18"
KVER_LOCAL=$(grep -oP '^LINUX_VERSION-6\.18 = \K\S+' "$KVER_FILE" 2>/dev/null)
KVER_OWRT=$(curl -sL --retry 3 --connect-timeout 30 \
	"https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/owrt/target/linux/generic/kernel-6.18" \
	| grep -oP '^LINUX_VERSION-6\.18 = \K\S+')
if [ -f "$KVER_FILE" ] && [ -n "$KVER_OWRT" ] && [ "$KVER_LOCAL" != "$KVER_OWRT" ]; then
	echo ">>> 内核补丁版本对齐: 本树 $KVER_LOCAL → owrt $KVER_OWRT"
	if curl -sL --retry 3 --connect-timeout 30 \
		"https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/owrt/target/linux/generic/kernel-6.18" \
		-o "$KVER_FILE"; then
		echo ">>> 内核版本定义已更新: $(grep 'LINUX_VERSION-6.18' "$KVER_FILE")"
		# 清理与目标内核不兼容的补丁（按文件名精确匹配，不存在则无副作用）：
		# - 438/782: 修复内容已被 stable .60 上游吸收，属重复补丁
		# - 304:     LoongArch 架构 vdso 补丁，与 qualcommax 目标无关且与新内核冲突
		# - 0092:    IPQ5018 pinctrl pwm3 补丁，与 IPQ807x 目标无关且与新内核冲突
		for RETIRED in \
			generic/backport-6.18/438-v7.3-mtd-spinand-Do-not-update-the-QE-bit-on-devices-without-one.patch \
			generic/backport-6.18/782-v7.3-USB-serial-option-add-Quectel-EG060W.patch \
			generic/pending-6.18/304-LoongArch-vdso-keep-the-prefix-map-flags.patch \
			qualcommax/patches-6.18/0092-v7.3-pinctrl-qcom-ipq5018-add-missing-pwm3-function-on-gpio13.patch \
		; do
			if [ -f "./target/linux/$RETIRED" ]; then
				rm -f "./target/linux/$RETIRED" && echo ">>> 已移除不兼容补丁: $RETIRED"
			else
				echo ">>> 警告: 退役补丁未找到（路径或文件名有误）: $RETIRED"
			fi
		done
	else
		echo ">>> 内核版本定义更新失败，保持本树原版本 $KVER_LOCAL"
	fi
else
	echo ">>> 内核补丁版本无需对齐（本树 $KVER_LOCAL，owrt $KVER_OWRT）"
fi

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
