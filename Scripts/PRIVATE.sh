#!/bin/bash
# 预置 OpenClash Smart 内核 (aarch64 / AX3600)

CORE_DIR="./package/base-files/files/etc/openclash/core"
mkdir -p "$CORE_DIR"

# Smart 内核下载地址（官方）
CORE_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/smart/clash-linux-arm64.tar.gz"

echo "Downloading OpenClash Smart core for arm64..."
curl -L --retry 3 --connect-timeout 30 -o /tmp/clash-core.tar.gz "$CORE_URL" || {
  echo "Download failed, trying mirror..."
  curl -L --retry 3 -o /tmp/clash-core.tar.gz \
    "https://cdn.jsdelivr.net/gh/vernesong/OpenClash@core/master/smart/clash-linux-arm64.tar.gz"
}

if [ -f /tmp/clash-core.tar.gz ]; then
  tar -xzf /tmp/clash-core.tar.gz -C /tmp
  if [ -f /tmp/clash ]; then
    mv /tmp/clash "$CORE_DIR/clash_meta"
    chmod +x "$CORE_DIR/clash_meta"
    echo "OpenClash Smart core pre-installed successfully!"
  else
    echo "Extract failed: clash binary not found"
  fi
  rm -f /tmp/clash-core.tar.gz /tmp/clash
else
  echo "Failed to download OpenClash Smart core"
fi
# ------------------------------------------------
# 2. AdGuardHome update_core.sh 兼容 apk/opkg
# ------------------------------------------------
echo ">>> Applying AdGuardHome update_core.sh (apk compatible)"

AGH_UPDATE_SCRIPT=""

# 自动查找 update_core.sh 路径（按你仓库实际路径调整）
if [ -f "package/luci-app-adguardhome/root/usr/share/AdGuardHome/update_core.sh" ]; then
	AGH_UPDATE_SCRIPT="package/luci-app-adguardhome/root/usr/share/AdGuardHome/update_core.sh"
elif [ -f "feeds/luci/applications/luci-app-adguardhome/root/usr/share/AdGuardHome/update_core.sh" ]; then
	AGH_UPDATE_SCRIPT="feeds/luci/applications/luci-app-adguardhome/root/usr/share/AdGuardHome/update_core.sh"
elif [ -f "package/feeds/luci/luci-app-adguardhome/root/usr/share/AdGuardHome/update_core.sh" ]; then
	AGH_UPDATE_SCRIPT="package/feeds/luci/luci-app-adguardhome/root/usr/share/AdGuardHome/update_core.sh"
fi

if [ -n "$AGH_UPDATE_SCRIPT" ] && [ -f "$AGH_UPDATE_SCRIPT" ]; then
	cat > "$AGH_UPDATE_SCRIPT" << 'EOF'
#!/bin/bash
PATH="/usr/sbin:/usr/bin:/sbin:/bin"
binpath=$(uci get AdGuardHome.AdGuardHome.binpath)
if [ -z "$binpath" ]; then
	uci set AdGuardHome.AdGuardHome.binpath="/tmp/AdGuardHome/AdGuardHome"
	binpath="/tmp/AdGuardHome/AdGuardHome"
fi
mkdir -p ${binpath%/*}
upxflag=$(uci get AdGuardHome.AdGuardHome.upxflag 2>/dev/null)

# 自动检测包管理器
if command -v apk >/dev/null 2>&1; then
	PKG_MGR="apk"
	PKG_UPDATE="apk update"
	PKG_INSTALL="apk add"
	PKG_REMOVE="apk del"
elif command -v opkg >/dev/null 2>&1; then
	PKG_MGR="opkg"
	PKG_UPDATE="opkg update"
	PKG_INSTALL="opkg install"
	PKG_REMOVE="opkg remove --force-depends"
else
	PKG_MGR="none"
fi

check_if_already_running(){
	running_tasks="$(ps | grep "AdGuardHome" | grep "update_core" | grep -v "grep" | awk '{print $1}' | wc -l)"
	[ "${running_tasks}" -gt "2" ] && echo -e "\nA task is already running." && EXIT 2
}

check_wgetcurl(){
	which curl && downloader="curl -L -k --retry 2 --connect-timeout 20 -o" && return
	which wget-ssl && downloader="wget-ssl --no-check-certificate -t 2 -T 20 -O" && return
	which wget && downloader="wget --no-check-certificate -t 2 -T 20 -O" && return

	if [ "$PKG_MGR" = "none" ]; then
		echo "error: neither apk nor opkg found, and no curl/wget available" && EXIT 1
	fi

	[ -z "$1" ] && $PKG_UPDATE || (echo "error $PKG_MGR" && EXIT 1)
	[ -z "$1" ] && ($PKG_REMOVE wget wget-nossl 2>/dev/null; $PKG_INSTALL wget; check_wgetcurl 1; return)
	[ "$1" == "1" ] && ($PKG_INSTALL curl; check_wgetcurl 2; return)
	echo error curl and wget && EXIT 1
}

get_arch(){
	local arch=""
	if [ -f /etc/os-release ]; then
		arch=$(grep -E '^OPENWRT_ARCH=' /etc/os-release 2>/dev/null | cut -d'"' -f2 | cut -d'_' -f1)
	fi
	if [ -z "$arch" ]; then
		arch=$(uname -m)
	fi
	case $arch in
		x86_64|amd64)   echo "x86" ;;
		i386|i686)      echo "i386" ;;
		aarch64|arm64)  echo "aarch64" ;;
		armv7l|armv7|arm) echo "arm" ;;
		armeb)          echo "armeb" ;;
		mipsel)         echo "mipsel" ;;
		mips64el)       echo "mips64el" ;;
		mips)           echo "mips" ;;
		mips64)         echo "mips64" ;;
		powerpc)        echo "powerpc" ;;
		powerpc64)      echo "powerpc64" ;;
		*)              echo "$arch" ;;
	esac
}

check_latest_version(){
	check_wgetcurl
	latest_ver="$($downloader - https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest 2>/dev/null | grep -E 'tag_name' | grep -E 'v[0-9.]+' -o 2>/dev/null)"
	if [ -z "${latest_ver}" ]; then
		echo -e "\nFailed to check latest version, please try again later." && EXIT 1
	fi
	now_ver="$($binpath -c /dev/null --check-config 2>&1 | grep -m 1 -E 'v[0-9.]+' -o)"
	if [ "${latest_ver}"x != "${now_ver}"x ] || [ "$1" == "force" ]; then
		echo -e "Local version: ${now_ver}., cloud version: ${latest_ver}."
		doupdate_core
	else
		echo -e "\nLocal version: ${now_ver}, cloud version: ${latest_ver}."
		echo -e "You're already using the latest version."
		if [ ! -z "$upxflag" ]; then
			filesize=$(ls -l $binpath | awk '{ print $5 }')
			if [ $filesize -gt 8000000 ]; then
				echo -e "start upx may take a long time"
				doupx
				mkdir -p "/tmp/AdGuardHomeupdate/AdGuardHome" >/dev/null 2>&1
				rm -fr /tmp/AdGuardHomeupdate/AdGuardHome/${binpath##*/}
				/tmp/upx-${upx_latest_ver}-${Arch}_linux/upx $upxflag $binpath -o /tmp/AdGuardHomeupdate/AdGuardHome/${binpath##*/}
				rm -rf /tmp/upx-${upx_latest_ver}-${Arch}_linux
				/etc/init.d/AdGuardHome stop nobackup
				rm $binpath
				mv -f /tmp/AdGuardHomeupdate/AdGuardHome/${binpath##*/} $binpath
				/etc/init.d/AdGuardHome start
				echo -e "finished"
			fi
		fi
		EXIT 0
	fi
}

doupx(){
	Archt="$(get_arch)"
	case $Archt in
	"i386") Arch="i386" ;;
	"x86") Arch="amd64" ;;
	"mipsel") Arch="mipsel" ;;
	"mips64el") Arch="mipsel"; echo -e "mips64el use $Arch may have bug" ;;
	"mips") Arch="mips" ;;
	"mips64") Arch="mips"; echo -e "mips64 use $Arch may have bug" ;;
	"arm") Arch="arm" ;;
	"armeb") Arch="armeb" ;;
	"aarch64") Arch="arm64" ;;
	"powerpc") Arch="powerpc" ;;
	"powerpc64") Arch="powerpc64" ;;
	*) echo -e "error not support $Archt if you can use offical release please issue a bug"; EXIT 1 ;;
	esac
	upx_latest_ver="$($downloader - https://api.github.com/repos/upx/upx/releases/latest 2>/dev/null | grep -E 'tag_name' | grep -E '[0-9.]+' -o 2>/dev/null)"
	$downloader /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz "https://github.com/upx/upx/releases/download/v${upx_latest_ver}/upx-${upx_latest_ver}-${Arch}_linux.tar.xz" 2>&1
	which xz || {
		if [ "$PKG_MGR" != "none" ]; then
			$PKG_UPDATE
			$PKG_INSTALL xz
		else
			echo "xz download fail" && EXIT 1
		fi
	} || (echo "xz download fail" && EXIT 1)
	mkdir -p /tmp/upx-${upx_latest_ver}-${Arch}_linux
	xz -d -c /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz | tar -x -C "/tmp" >/dev/null 2>&1
	if [ ! -e "/tmp/upx-${upx_latest_ver}-${Arch}_linux/upx" ]; then
		echo -e "Failed to download upx."
		EXIT 1
	fi
	rm /tmp/upx-${upx_latest_ver}-${Arch}_linux.tar.xz
}

doupdate_core(){
	echo -e "Updating core..."
	mkdir -p "/tmp/AdGuardHomeupdate"
	rm -rf /tmp/AdGuardHomeupdate/* >/dev/null 2>&1
	Archt="$(get_arch)"
	case $Archt in
	"i386") Arch="386" ;;
	"x86") Arch="amd64" ;;
	"mipsel") Arch="mipsle" ;;
	"mips64el") Arch="mipsle"; echo -e "mips64el use $Arch may have bug" ;;
	"mips") Arch="mips" ;;
	"mips64") Arch="mips"; echo -e "mips64 use $Arch may have bug" ;;
	"arm") Arch="arm" ;;
	"aarch64") Arch="arm64" ;;
	"powerpc"|"powerpc64") echo -e "error not support $Archt"; EXIT 1 ;;
	*) echo -e "error not support $Archt if you can use offical release please issue a bug"; EXIT 1 ;;
	esac
	echo -e "start download"
	grep -v "^#" /usr/share/AdGuardHome/links.txt >/tmp/run/AdHlinks.txt
	while read link
	do
		eval link="$link"
		$downloader /tmp/AdGuardHomeupdate/${link##*/} "$link" 2>&1
		if [ "$?" != "0" ]; then
			echo "download failed try another download"
			rm -f /tmp/AdGuardHomeupdate/${link##*/}
		else
			local success="1"
			break
		fi
	done < "/tmp/run/AdHlinks.txt"
	rm /tmp/run/AdHlinks.txt
	[ -z "$success" ] && echo "no download success" && EXIT 1
	if [ "${link##*.}" == "gz" ]; then
		tar -zxf "/tmp/AdGuardHomeupdate/${link##*/}" -C "/tmp/AdGuardHomeupdate/"
		if [ ! -e "/tmp/AdGuardHomeupdate/AdGuardHome" ]; then
			echo -e "Failed to download core."
			rm -rf "/tmp/AdGuardHomeupdate" >/dev/null 2>&1
			EXIT 1
		fi
		downloadbin="/tmp/AdGuardHomeupdate/AdGuardHome/AdGuardHome"
	else
		downloadbin="/tmp/AdGuardHomeupdate/${link##*/}"
	fi
	chmod 755 $downloadbin
	echo -e "download success start copy"
	if [ -n "$upxflag" ]; then
		echo -e "start upx may take a long time"
		doupx
		/tmp/upx-${upx_latest_ver}-${Arch}_linux/upx $upxflag $downloadbin
		rm -rf /tmp/upx-${upx_latest_ver}-${Arch}_linux
	fi
	echo -e "start copy"
	/etc/init.d/AdGuardHome stop nobackup
	rm "$binpath"
	mv -f "$downloadbin" "$binpath"
	if [ "$?" == "1" ]; then
		echo "mv failed maybe not enough space please use upx or change bin to /tmp/AdGuardHome"
		EXIT 1
	fi
	/etc/init.d/AdGuardHome start
	rm -rf "/tmp/AdGuardHomeupdate" >/dev/null 2>&1
	echo -e "Succeeded in updating core."
	echo -e "Local version: ${latest_ver}, cloud version: ${latest_ver}.\n"
	EXIT 0
}

EXIT(){
	rm /var/run/update_core 2>/dev/null
	[ "$1" != "0" ] && touch /var/run/update_core_error
	exit $1
}

main(){
	check_if_already_running
	check_latest_version $1
}

trap "EXIT 1" SIGTERM SIGINT
touch /var/run/update_core
rm /var/run/update_core_error 2>/dev/null
main $1
EOF
	chmod +x "$AGH_UPDATE_SCRIPT"
	echo ">>> AdGuardHome update_core.sh 已替换为 apk 兼容版本 → $AGH_UPDATE_SCRIPT"
else
	echo ">>> 未找到 luci-app-adguardhome 的 update_core.sh，跳过替换"
fi

echo ">>> PRIVATE.sh 执行完毕"



# =================== 自定义添加 Samba 用户与目录赋权 ===================
mkdir -p ./files/etc/uci-defaults
cat << 'EOF' > ./files/etc/uci-defaults/98-samba-user.sh
#!/bin/sh

# 1. 检查并添加系统用户 shareuser
if ! grep -q "shareuser" /etc/passwd; then
    useradd -m -s /bin/false shareuser
    echo "shareuser:zbc" | chpasswd
    (echo "zbc"; echo "zbc") | smbpasswd -a shareuser
fi

# 2. 确保共享文件夹存在，并把所有权给这个新用户（防止以后往里传文件提示无权限）
mkdir -p /root/share
chown -R shareuser:shareuser /root/share

exit 0
EOF
chmod +x ./files/etc/uci-defaults/98-samba-user.sh


