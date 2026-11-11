
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
		# 精确匹配目录名，避免 "*argon*" 之类模糊匹配误删 node-argon2 等无关包：
		# 命中形如 /luci-theme-argon（以 -NAME 结尾）或 /NAME-xxx（以 NAME- 开头）的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d 2>/dev/null \
			| grep -Ei "/([a-z0-9._]+-)*${NAME}$|/${NAME}-")

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
UPDATE_PACKAGE "argon" "jerrykuku/luci-theme-argon" "master" "" "argon-config"
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
# 解析 owrt 引用：默认跟随 owrt 分支 HEAD，可用 Scripts/pins.env 中的 OWRT_SHA 锁定
# =========================
OWRT_REF="owrt"
if [ -f "$GITHUB_WORKSPACE/Scripts/pins.env" ]; then
	. "$GITHUB_WORKSPACE/Scripts/pins.env"
fi
if [ -n "${OWRT_SHA:-}" ]; then
	OWRT_REF="$OWRT_SHA"
	echo ">>> 使用锁定的 owrt 提交: $OWRT_REF（来自 Scripts/pins.env）"
else
	OWRT_HEAD=$(git ls-remote https://github.com/VIKINGYFY/immortalwrt.git refs/heads/owrt 2>/dev/null | cut -f1)
	if [ -n "$OWRT_HEAD" ]; then
		echo ">>> owrt 当前提交（追溯用）: $OWRT_HEAD"
	else
		echo ">>> 警告: 无法解析 owrt 分支 HEAD，将直接使用分支名"
	fi
fi

# =========================
# 从 owrt 分支移植 luci-app-router-tool（含中继AP模式）
# 仅当源码树中没有该包时才下载（owrt 分支自带，会自动跳过）
# 失败视为硬错误：配置里已声明该包，缺失意味着固件功能不完整，不应静默通过
# =========================
if [ ! -d "./package/emortal/luci-app-router-tool" ]; then
	echo ">>> 源码树缺少 luci-app-router-tool，从 owrt 分支移植..."
	OWRT_TARBALL=$(mktemp)
	if ! curl -fsSL --retry 3 --connect-timeout 30 \
		"https://github.com/VIKINGYFY/immortalwrt/archive/${OWRT_REF}.tar.gz" -o "$OWRT_TARBALL"; then
		rm -f "$OWRT_TARBALL"
		echo ">>> 错误: owrt 源码包下载失败（引用 $OWRT_REF），中继AP模式无法移植"
		exit 1
	fi
	OWRT_TOP=$(tar tzf "$OWRT_TARBALL" 2>/dev/null | head -1 | cut -d/ -f1)
	if [ -z "$OWRT_TOP" ] || ! tar xzf "$OWRT_TARBALL" --strip-components=2 \
		-C ./package "$OWRT_TOP/package/emortal/luci-app-router-tool"; then
		rm -f "$OWRT_TARBALL"
		echo ">>> 错误: luci-app-router-tool 解包失败（该包可能已从 owrt 移除）"
		exit 1
	fi
	rm -f "$OWRT_TARBALL"
	if [ -f "./package/emortal/luci-app-router-tool/Makefile" ]; then
		echo ">>> luci-app-router-tool 移植成功（Makefile 已就位）"
	else
		echo ">>> 错误: 移植后缺少 Makefile，包结构异常"
		exit 1
	fi
else
	echo ">>> 源码树已自带 luci-app-router-tool，跳过移植"
fi

# =========================
# 内核补丁版本对齐：跟随 owrt 分支的内核 patch 版本
# （如 main 为 6.18.55 而 owrt 已升到 6.18.60，则自动同步版本定义，含官方 hash）
# 仅替换版本定义文件，补丁集保持本分支原样
# =========================
KVER_FILE="./target/linux/generic/kernel-6.18"
KVER_LOCAL=$(grep -oP '^LINUX_VERSION-6\.18 = \K\S+' "$KVER_FILE" 2>/dev/null)
KVER_OWRT=$(curl -fsSL --retry 3 --connect-timeout 30 \
	"https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/${OWRT_REF}/target/linux/generic/kernel-6.18" 2>/dev/null \
	| grep -oP '^LINUX_VERSION-6\.18 = \K\S+')

if [ ! -f "$KVER_FILE" ]; then
	echo ">>> 警告: 本树缺少 $KVER_FILE，跳过内核版本对齐"
elif [ -z "$KVER_OWRT" ]; then
	echo ">>> 警告: 无法读取 owrt 内核版本定义（引用 $OWRT_REF，本树 $KVER_LOCAL），跳过对齐"
elif [ "$KVER_LOCAL" = "$KVER_OWRT" ]; then
	echo ">>> 内核版本已与 owrt 一致（$KVER_LOCAL），无需对齐"
else
	echo ">>> 内核补丁版本对齐: 本树 $KVER_LOCAL → owrt $KVER_OWRT"
	if curl -fsSL --retry 3 --connect-timeout 30 \
		"https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/${OWRT_REF}/target/linux/generic/kernel-6.18" \
		-o "$KVER_FILE"; then
		echo ">>> 内核版本定义已更新: $(grep 'LINUX_VERSION-6.18' "$KVER_FILE")"
	else
		echo ">>> 错误: 内核版本定义更新失败，保持本树原版本 $KVER_LOCAL"
		exit 1
	fi
fi

# =========================
# 退役补丁：无条件执行（与版本号是否对齐无关，防止版本已对齐时补丁被重新启用）
# - 438/782/787/950: 修复内容已被 stable 6.18.60 上游吸收，属重复补丁
# - 304:     LoongArch 架构 vdso 补丁，与 qualcommax 目标无关且与新内核冲突
# - 0092:    IPQ5018 pinctrl pwm3 补丁，与 IPQ807x 目标无关且与新内核冲突
# 清单变更须同步 .github/workflows/PATCH-REHEARSE.yml 的 SKIP 表
# =========================
for RETIRED in \
	generic/backport-6.18/438-v7.3-mtd-spinand-Do-not-update-the-QE-bit-on-devices-without-one.patch \
	generic/backport-6.18/782-v7.3-USB-serial-option-add-Quectel-EG060W.patch \
	generic/backport-6.18/787-v7.3-net-usb-qmi_wwan-add-Quectel-EG120K-EA.patch \
	generic/backport-6.18/950-v7.3-cgroup-fix-spurious-SIGKILL-of-CLONE_INTO_CGROUP-children.patch \
	generic/pending-6.18/304-LoongArch-vdso-keep-the-prefix-map-flags.patch \
	qualcommax/patches-6.18/0092-v7.3-pinctrl-qcom-ipq5018-add-missing-pwm3-function-on-gpio13.patch \
; do
	if [ -f "./target/linux/$RETIRED" ]; then
		rm -f "./target/linux/$RETIRED" && echo ">>> 已移除退役补丁: $RETIRED"
	else
		echo ">>> 警告: 退役补丁未找到（路径或文件名有误，请检查清单）: $RETIRED"
	fi
done

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
