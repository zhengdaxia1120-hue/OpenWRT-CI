
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
# 中继AP模式：luci-app-router-tool
# 该包只在 owrt 分支存在，main 源码树里没有（package/emortal 下无此目录），
# 而 Config/GENERAL.txt 已声明 CONFIG_PACKAGE_luci-app-router-tool=y，
# 所以 main 编译必须从 owrt 取；取不到就终止，不能静默少一个功能。
# 源码分支本身就是 owrt 时由源码树提供，无需移植。
# =========================
RT_DIR="./package/emortal/luci-app-router-tool"
if [ "${WRT_BRANCH:-}" = "owrt" ] && [ -d "$RT_DIR" ]; then
	echo ">>> 源码分支为 owrt，luci-app-router-tool 由源码树自带，跳过移植"
else
	echo ">>> 从 owrt 分支移植 luci-app-router-tool（中继AP模式）..."
	OWRT_TARBALL=$(mktemp)
	if ! curl -fsSL --retry 3 --connect-timeout 30 \
		"https://github.com/VIKINGYFY/immortalwrt/archive/owrt.tar.gz" -o "$OWRT_TARBALL"; then
		rm -f "$OWRT_TARBALL"
		echo ">>> 错误: owrt 源码包下载失败，中继AP模式无法移植"
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
		echo ">>> luci-app-router-tool 移植成功: $(grep -E '^PKG_VERSION' "$RT_DIR/Makefile" | tr '\n' ' ')"
	else
		echo ">>> 错误: 移植后缺少 Makefile，包结构异常"
		exit 1
	fi
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
