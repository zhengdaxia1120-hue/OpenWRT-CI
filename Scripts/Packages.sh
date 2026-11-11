
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
# 源码分支：由 workflow 的 env 段导出（WRT-CORE.yml 里取自 matrix.BRANCH，QCA-ALL.yml 传参）
# 这里显式校验：后面的 router-tool 跟随逻辑靠它区分 owrt / main，
# 变量丢失时宁可终止，也不要静默走错分支（否则"跳过移植"那条路径形同摆设）
# =========================
SUMMARY() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; }

if [ -z "${WRT_BRANCH:-}" ]; then
	echo ">>> 错误: 环境变量 WRT_BRANCH 未设置，无法判断源码分支（owrt / main），终止编译"
	exit 1
fi
echo ">>> 源码分支: $WRT_BRANCH"

# =========================
# owrt 引用解析：同一次编译只认一个提交
# - 默认跟随 owrt 分支 HEAD，解析成提交哈希后固定下来，后续所有下载都用这个哈希
# - 可用 Scripts/pins.env 的 OWRT_SHA 锁定，便于复现历史固件
# - 解析失败直接终止：否则三次下载各走一次分支名，日志记录的版本和实际取用的代码会对不上
# =========================
if [ -f "$GITHUB_WORKSPACE/Scripts/pins.env" ]; then
	. "$GITHUB_WORKSPACE/Scripts/pins.env"
fi

if [ -n "${OWRT_SHA:-}" ]; then
	OWRT_REF="$OWRT_SHA"
	echo ">>> owrt 引用: $OWRT_REF（pins.env 锁定，可复现）"
else
	OWRT_REF=$(git ls-remote https://github.com/VIKINGYFY/immortalwrt.git refs/heads/owrt 2>/dev/null | cut -f1)
	if [ -z "$OWRT_REF" ]; then
		echo ">>> 错误: 无法解析 owrt 分支 HEAD（网络不通或仓库不可达），终止编译"
		exit 1
	fi
	echo ">>> owrt 引用: $OWRT_REF（跟随 owrt HEAD，本次编译内固定，不会中途漂移）"
fi

SUMMARY "- 源码分支: \`$WRT_BRANCH\`"
SUMMARY "- owrt 引用: \`$OWRT_REF\`"

# =========================
# luci-app-router-tool（含中继AP模式）
# 该包为 owrt 分支独有，main 分支源码树里没有，必须从 owrt 移植
# 跟随策略（按源码分支判断，而不是按目录是否存在判断）：
#   - 源码分支就是 owrt：包由源码树直接提供，无需移植
#   - 其它分支（main 等）：无条件用 owrt@$OWRT_REF 覆盖
#     这样 owrt 更新 router-tool 后，main 一定用上新版；若将来 main 自带了该包，
#     也一律以 owrt 版本为准，日志会写明"覆盖"
# 失败视为硬错误：Config 里已声明该包，缺失意味着固件功能不完整，不应静默通过
# =========================
RT_DIR="./package/emortal/luci-app-router-tool"
if [ "$WRT_BRANCH" = "owrt" ]; then
	echo ">>> 源码分支为 owrt，luci-app-router-tool 由源码树直接提供，跳过移植"
	SUMMARY "- luci-app-router-tool: 源码自带（owrt 分支）"
else
	if [ -d "$RT_DIR" ]; then
		echo ">>> 源码树自带 luci-app-router-tool，按跟随策略改用 owrt 版本覆盖"
	else
		echo ">>> 源码树缺少 luci-app-router-tool，从 owrt 移植"
	fi
	OWRT_TARBALL=$(mktemp)
	if ! curl -fsSL --retry 3 --connect-timeout 30 \
		"https://github.com/VIKINGYFY/immortalwrt/archive/${OWRT_REF}.tar.gz" -o "$OWRT_TARBALL"; then
		rm -f "$OWRT_TARBALL"
		echo ">>> 错误: owrt 源码包下载失败（引用 $OWRT_REF），中继AP模式无法移植"
		exit 1
	fi
	OWRT_TOP=$(tar tzf "$OWRT_TARBALL" 2>/dev/null | head -1 | cut -d/ -f1)
	rm -rf "$RT_DIR"
	mkdir -p ./package/emortal
	if [ -z "$OWRT_TOP" ] || ! tar xzf "$OWRT_TARBALL" --strip-components=2 \
		-C ./package "$OWRT_TOP/package/emortal/luci-app-router-tool"; then
		rm -f "$OWRT_TARBALL"
		echo ">>> 错误: luci-app-router-tool 解包失败（该包可能已从 owrt 移除）"
		exit 1
	fi
	rm -f "$OWRT_TARBALL"
	if [ -f "$RT_DIR/Makefile" ]; then
		echo ">>> luci-app-router-tool 移植成功（来源 owrt@${OWRT_REF:0:7}）"
		SUMMARY "- luci-app-router-tool: 移植自 owrt@${OWRT_REF:0:7}"
	else
		echo ">>> 错误: 移植后缺少 Makefile，包结构异常"
		exit 1
	fi
fi

# =========================
# 内核补丁版本对齐：跟随 owrt 分支的内核 patch 版本
# （如 main 为 6.18.55 而 owrt 已升到 6.18.60，则自动同步版本定义，含官方 hash）
# 仅替换版本定义文件，补丁集保持本分支原样
# =========================
KVER_FILE="./target/linux/generic/kernel-6.18"
if [ ! -f "$KVER_FILE" ]; then
	echo ">>> 警告: 本树缺少 $KVER_FILE，跳过内核版本对齐"
	SUMMARY "- 内核版本: 未对齐（本树无 kernel-6.18 定义）"
else
	KVER_LOCAL=$(grep -oP '^LINUX_VERSION-6\.18 = \K\S+' "$KVER_FILE" 2>/dev/null)
	KVER_OWRT=$(curl -fsSL --retry 3 --connect-timeout 30 \
		"https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/${OWRT_REF}/target/linux/generic/kernel-6.18" 2>/dev/null \
		| grep -oP '^LINUX_VERSION-6\.18 = \K\S+')

	if [ -z "$KVER_OWRT" ]; then
		echo ">>> 警告: 无法读取 owrt 内核版本定义（引用 $OWRT_REF，本树 $KVER_LOCAL），跳过对齐"
		SUMMARY "- 内核版本: 对齐未执行（读取 owrt 定义失败，本树 $KVER_LOCAL）"
	elif [ "$KVER_LOCAL" = "$KVER_OWRT" ]; then
		echo ">>> 内核版本已与 owrt 一致（$KVER_LOCAL），无需对齐"
		SUMMARY "- 内核版本: $KVER_LOCAL（已与 owrt 一致）"
	else
		echo ">>> 内核补丁版本对齐: 本树 $KVER_LOCAL → owrt $KVER_OWRT"
		if curl -fsSL --retry 3 --connect-timeout 30 \
			"https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/${OWRT_REF}/target/linux/generic/kernel-6.18" \
			-o "$KVER_FILE"; then
			echo ">>> 内核版本定义已更新: $(grep 'LINUX_VERSION-6.18' "$KVER_FILE")"
			SUMMARY "- 内核版本: $KVER_LOCAL → $KVER_OWRT（对齐 owrt）"
		else
			echo ">>> 错误: 内核版本定义更新失败，保持本树原版本 $KVER_LOCAL"
			exit 1
		fi
	fi
fi

# =========================
# 退役补丁：无条件执行（与版本号是否对齐无关，防止版本已对齐时补丁被重新启用）
# 清单唯一来源：Scripts/retired-patches.txt
#   - 编译脚本按它会删除对应补丁
#   - .github/workflows/PATCH-REHEARSE.yml 按同一份文件跳过这些补丁
# 两边不再各自维护清单，改一次即可，演练结果与真实编译不会再分叉
# =========================
RETIRED_FILE="$GITHUB_WORKSPACE/Scripts/retired-patches.txt"
if [ ! -f "$RETIRED_FILE" ]; then
	echo ">>> 错误: 缺少退役补丁清单 $RETIRED_FILE，终止编译"
	exit 1
fi

RETIRED_DONE=0
RETIRED_MISSING=0
while IFS= read -r RETIRED || [ -n "$RETIRED" ]; do
	RETIRED=$(echo "$RETIRED" | tr -d '\r' | sed 's/[[:space:]]*$//')
	[ -z "$RETIRED" ] && continue
	case "$RETIRED" in \#*) continue ;; esac
	if [ -f "./target/linux/$RETIRED" ]; then
		rm -f "./target/linux/$RETIRED" && echo ">>> 已移除退役补丁: $RETIRED"
		RETIRED_DONE=$((RETIRED_DONE + 1))
	else
		echo ">>> 警告: 退役补丁未找到（路径或文件名有误，请检查清单）: $RETIRED"
		RETIRED_MISSING=$((RETIRED_MISSING + 1))
	fi
done < "$RETIRED_FILE"
echo ">>> 退役补丁处理完成: 移除 $RETIRED_DONE 个，清单中缺失 $RETIRED_MISSING 个"
SUMMARY "- 退役补丁: 移除 $RETIRED_DONE 个，缺失 $RETIRED_MISSING 个"

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
