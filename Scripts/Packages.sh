#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
# =====================================================================
# 在原版基础上修掉会炸的点（行为/调用方式尽量不变）：
#
#   1) 所有 PKG_NAME 改为与 .config 里的 CONFIG_PACKAGE_xxx 严格一致
#      （原版 argon/aurora/vantage/diskmanager 等与实际包名不符，
#       导致 package/install 阶段 "no such package"）。
#
#   2) viking 一仓多包：由「整仓残留」改为「pkg 精准展开」。
#      原版 PKG_NAME=viking，但仓库里根本没有 viking 目录，
#      find *viking* 什么都删不掉，旧包残留 → coremark / 依赖错乱。
#      现改为每个子包单独调用，逐一把子目录 cp 到 package/ 下。
#
#   3) pkg 模式的 find 去掉 -maxdepth 3 的深度限制，并改用
#      basename 精确匹配（原版用 *PKG_NAME* 模糊匹配会误拷）。
#
#   4) 分支不存在时 git clone --branch 会直接失败退出，
#      先 ls-remote 探活，失败则回退默认分支。
#
#   5) 未设 -e 时 clone 失败后的残缺目录会污染下次运行，
#      这里统一用「先 clone 到临时目录 → 校验 → 改名」的原子流程。
#
#   6) 原版 UPDATE_VERSION 扫不到放在仓库子目录里的包，
#      路径由 ./package/ 放宽到 ./package/*/ 两级，并把 grep 失败
#      与空结果都兜底处理，避免 jq/curl 异常时写坏 Makefile。
#
# 注意：本脚本须在 OpenWrt 源码树根目录执行（即存在 package/ 的目录）。
# =====================================================================

# 安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" ${5:-})
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_TMP="./package/$REPO_NAME-tmp"   # 临时目录，原子落地
	local REPO_DST="./package/$REPO_NAME"       # 最终仓库目录（pkg 模式用）
	local DST_DIR="./package/$PKG_NAME"         # 单包模式的最终落盘名

	echo " "

	# 删除本地可能存在的不同名称的软件包（feeds + package/ 都扫）
	# 同时排除本次的目标目录，避免把自己刚装的包删掉
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS
		FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ ./package/ \
			-maxdepth 4 -type d -iname "*$NAME*" 2>/dev/null \
			| grep -v "^$DST_DIR$" \
			| grep -v "^$REPO_DST$" \
			| grep -v "^$REPO_DST/" || true)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库（先探活，分支不存在则回退默认分支；原子落地）
	rm -rf "$REPO_TMP"
	if git ls-remote --exit-code --heads "https://github.com/$PKG_REPO.git" "$PKG_BRANCH" >/dev/null 2>&1; then
		echo "Branch mode: $PKG_BRANCH"
		git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
			"https://github.com/$PKG_REPO.git" "$REPO_TMP"
	else
		echo "Branch '$PKG_BRANCH' not found for $PKG_REPO, fall back to default branch"
		git clone --depth=1 "https://github.com/$PKG_REPO.git" "$REPO_TMP"
	fi

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 一仓多包：按 PKG_NAME 精确提取子目录（basename 完全一致），
		# 目录名=包名，与 .config 里的 CONFIG_PACKAGE_xxx 一一对应。
		find "$REPO_TMP" -mindepth 1 -maxdepth 4 -type d -iname "$PKG_NAME" -print0 2>/dev/null | \
		while IFS= read -r -d '' DIR; do
			local BASENAME
			BASENAME=$(basename "$DIR")
			rm -rf "./package/$BASENAME"
			cp -rf "$DIR" "./package/$BASENAME"
			rm -rf "./package/$BASENAME/.git"
			echo "Extracted sub-package: ./package/$BASENAME"
		done
		rm -rf "$REPO_TMP"
	else
		# 单包仓库：同样按 PKG_NAME 精确提取子目录，避免整仓 mv 后
		# Makefile 被埋在深度 4~5 导致扫描器漏扫（实测：仓库根目录
		# 结构为 any/depth/luci-theme-aurora 时，mv 后深度=5，不可见）。
		# 最终保证 package/$PKG_NAME/Makefile 深度=2，100% 可见。
		local PKG_SUB
		PKG_SUB=$(find "$REPO_TMP" -mindepth 1 -maxdepth 4 -type d -iname "$PKG_NAME" | head -1)
		if [ -n "$PKG_SUB" ]; then
			rm -rf "$DST_DIR"
			cp -rf "$PKG_SUB" "$DST_DIR"
			rm -rf "$DST_DIR/.git"
		else
			# 兜底：仓库根就是包（含 Makefile），则整仓落盘
			if [ -f "$REPO_TMP/Makefile" ]; then
				rm -rf "$DST_DIR"
				mv -f "$REPO_TMP" "$DST_DIR"
				rm -rf "$DST_DIR/.git"
			else
				echo "ERROR: cannot locate package '$PKG_NAME' in $REPO_TMP" >&2
				rm -rf "$REPO_TMP"
				return 1
			fi
		fi
	fi

	# 校验最终目录存在
	if [ ! -d "$DST_DIR" ]; then
		echo "ERROR: package directory not created: $DST_DIR" >&2
		return 1
	fi
	echo "Installed: $DST_DIR"
}

# ===================== 主题 =====================
# 关键：PKG_NAME 用正式包名（luci-theme-xxx），与 .config 对齐
UPDATE_PACKAGE "luci-theme-argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "luci-theme-aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "luci-app-aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "luci-theme-fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "luci-theme-footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "luci-theme-kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "luci-app-kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "luci-theme-shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "luci-theme-vantage" "anothaDev/luci-theme-vantage" "main"

# ===================== 网络 / 代理 =====================
UPDATE_PACKAGE "OpenWrt-momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "OpenWrt-nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "openwrt-passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "openwrt-passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

# ===================== 工具 / 系统 =====================
UPDATE_PACKAGE "luci-app-mini-diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "luci-app-easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "QModem" "FUjr/QModem" "main"

# 集客等一仓多包：pkg 精准展开，每个子包独立落到 package/ 下（目录名=包名）
# 原版整仓残留会覆盖官方 miniupnpd / luci-app-upnp，已从列表移除，避免 coremark 类错误
UPDATE_PACKAGE "axonhub" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "gecoosac" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "sing-box" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-homeproxy" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-timewol" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-wolplus" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-wolultra" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "v2dat" "VIKINGYFY/packages" "main" "pkg"

UPDATE_PACKAGE "luci-app-diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "luci-app-mosdns" "sbwml/luci-app-mosdns" "v5"
UPDATE_PACKAGE "luci-app-openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "luci-app-qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "luci-app-quickfile" "sbwml/luci-app-quickfile" "main"

UPDATE_PACKAGE "luci-app-ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "luci-app-netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "luci-app-partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "luci-app-timecontrol" "sirpdboy/luci-app-timecontrol" "main"

UPDATE_PACKAGE "openwrt-natmapt" "muink/openwrt-natmapt" "master"
UPDATE_PACKAGE "openwrt-stuntman" "muink/openwrt-stuntman" "master"
UPDATE_PACKAGE "luci-app-natmapt" "muink/luci-app-natmapt" "master"

UPDATE_PACKAGE "luci-app-airpi3000m-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main"
UPDATE_PACKAGE "luci-app-chfs" "LianXia233/luci-app-chfs" "main"
UPDATE_PACKAGE "luci-app-fm350" "LianXia233/luci-app-fm350" "main"
UPDATE_PACKAGE "luci-app-h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"
UPDATE_PACKAGE "luci-app-mt5700" "LianXia233/luci-app-mt5700" "main"
UPDATE_PACKAGE "luci-app-mt5700m" "LianXia233/luci-app-mt5700m" "main"
UPDATE_PACKAGE "luci-app-netmonitor" "LianXia233/luci-app-netmonitor" "main"
UPDATE_PACKAGE "luci-app-qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"

# ===================== 版本更新函数 =====================
# 说明：
#   - 扫描路径放宽到 ./package/*/ 两级，能覆盖放在仓库子目录里的包
#   - 任何一步解析失败（无 github 源 / 无 release / jq 缺失）都 skip，
#     不写坏 Makefile
#   - dpkg 比较加 2>/dev/null 兜底，非标准版本号不会炸
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES
	PKG_FILES=$(find ./package/ ./package/*/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null | sort -u)

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO
		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE" || true)
		if [ -z "$PKG_REPO" ]; then
			echo "  skip (no github source): $PKG_FILE"
			continue
		fi

		local PKG_TAG
		if ! command -v jq >/dev/null 2>&1; then
			echo "  skip (jq not installed): $PKG_FILE" >&2
			continue
		fi
		PKG_TAG=$(curl -sL --retry 2 "https://api.github.com/repos/$PKG_REPO/releases" | \
			jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name" 2>/dev/null || true)
		if [ -z "$PKG_TAG" ] || [ "$PKG_TAG" = "null" ]; then
			echo "  skip (no release found): $PKG_REPO"
			continue
		fi

		local OLD_VER OLD_URL OLD_FILE OLD_HASH
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL
		PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER NEW_URL NEW_HASH
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER" 2>/dev/null; then
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

# ===================== 主题固化（aurora，首次启动自动生效） =====================
{
	for _f in package/emortal/default-settings/files/zzz-default-settings \
			  package/default-settings/files/zzz-default-settings; do
		if [ -f "$_f" ]; then
			sed -i '/luci.main.theme/d' "$_f"
			sed -i '/mediaurlbase/d' "$_f"
			sed -i '/luci.themes.aurora/d' "$_f"
		fi
	done

	mkdir -p files/etc/uci-defaults
	cat > files/etc/uci-defaults/99-set-theme <<'EOF'
#!/bin/sh
uci set luci.main.theme="aurora"
uci set luci.main.mediaurlbase="/luci-static/aurora"
uci set luci.themes.aurora=1
uci commit luci
rm -rf /tmp/luci-*
if [ -x /etc/init.d/uhttpd ]; then
	/etc/init.d/uhttpd restart
fi
exit 0
EOF
	chmod +x files/etc/uci-defaults/99-set-theme
	echo "Theme pin script installed: files/etc/uci-defaults/99-set-theme"
}

# 引入私有扩展脚本
if [ -f "${GITHUB_WORKSPACE:-}/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
