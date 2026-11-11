
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
		# 命中 basename 等于 NAME、以 NAME- 开头、或以 -NAME 结尾的目录
		# 用 case 做字面比较而非正则：包名里出现 + . 等正则元字符也不会失效，且大小写敏感
		echo "Search directory: $NAME"
		local FOUND=0
		while read -r DIR; do
			[ -n "$DIR" ] || continue
			local BASE=$(basename "$DIR")
			local HIT=0
			[ "$BASE" = "$NAME" ] && HIT=1
			case "$BASE" in
				"$NAME"-*) HIT=1 ;;
				*-"$NAME") HIT=1 ;;
			esac
			if [ "$HIT" = 1 ]; then
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
				FOUND=$((FOUND + 1))
			fi
		done < <(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d 2>/dev/null)
		[ "$FOUND" = 0 ] && echo "Not found directory: $NAME"
	done

	# 克隆 GitHub 仓库
	if ! git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git" "$REPO_PATH"; then
		echo ">>> 错误: 克隆 $PKG_REPO ($PKG_BRANCH) 失败"
		exit 1
	fi

	# 处理克隆的仓库：只拷贝目录名精确等于包名或其 luci 前端的目录
	# 不用 -iname "*$PKG_NAME*"：命中范围取决于 shell 通配符是否展开点目录、以及 -prune 剪枝的深度，
	# 当前碰巧只命中 luci-app-openclash，但安全是巧合而非设计；精确匹配的命中范围可预期，且拷贝前有清单可查
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		local COPIED=0
		while read -r DIR; do
			[ -n "$DIR" ] || continue
			case "$(basename "$DIR")" in
				"$PKG_NAME"|"luci-app-$PKG_NAME")
					cp -rf "$DIR" ./package
					echo "Copy package directory: $DIR"
					COPIED=$((COPIED + 1))
					;;
			esac
		done < <(find "$REPO_PATH" -maxdepth 3 -type d 2>/dev/null)
		rm -rf "$REPO_PATH"
		if [ "$COPIED" = 0 ]; then
			echo ">>> 错误: $REPO_NAME 中未找到 $PKG_NAME / luci-app-$PKG_NAME 目录"
			exit 1
		fi
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
# owrt 源码 + main overlay
# 两个矩阵都使用 owrt 源码（见 WRT-CORE 的 Clone Code），本脚本只做"叠加"：
#   - owrt 分支：不叠加任何内容，编译结果与上游 owrt 一致
#   - main 分支：叠加 Overlay/main/ 中的 NSS 包与 NSS 配置（main 独有，owrt 没有）
# 通用部分（插件、主题、配置）两边都执行
# =========================
SUMMARY() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; }
SUMMARY "- 源码: owrt 提交 \`${WRT_HASH:-unknown}\`"
SUMMARY "- 分支标签: \`${WRT_BRANCH:-unknown}\`"

if [ -z "${WRT_BRANCH:-}" ]; then
	echo ">>> 错误: 环境变量 WRT_BRANCH 未设置，终止编译"
	exit 1
fi

if [ "$WRT_BRANCH" = "main" ]; then
	OVERLAY_PKG="$GITHUB_WORKSPACE/Overlay/main/package"
	if [ ! -d "$OVERLAY_PKG" ]; then
		echo ">>> 错误: 缺少 main overlay 目录 $OVERLAY_PKG，终止编译"
		exit 1
	fi
	cp -rf "$OVERLAY_PKG/." ./package/
	OVERLAY_N=$(find "$OVERLAY_PKG" -mindepth 2 -maxdepth 2 -type d | wc -l)
	echo ">>> main overlay 已叠加: $OVERLAY_N 个包目录"
	SUMMARY "- main overlay: 叠加 $OVERLAY_N 个包目录（NSS）"
else
	echo ">>> owrt 分支: 不叠加 overlay，源码保持上游原样"
	SUMMARY "- overlay: 无（owrt 上游原样）"
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
		local PKG_TAG=$(curl -fsSL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name" 2>/dev/null)

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -fsSL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [ -z "$NEW_VER" ] || [ -z "$NEW_HASH" ]; then
			echo "$PKG_FILE 版本查询失败（网络异常或仓库无可用 release），保持原版本"
			continue
		fi

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
