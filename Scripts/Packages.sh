#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
# 用法：在 OpenWrt 源码树根目录执行（即存在 package/ 的目录）
# 改动：仓库只克隆一次；pkg 模式精确提取子目录；单包模式防 Makefile 深埋
set -euo pipefail

UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=${4:-}
	local PKG_LIST=("$PKG_NAME" ${5:-})
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_TMP="./package/$REPO_NAME-tmp"   # 临时目录，原子落地
	local REPO_DST="./package/$REPO_NAME"       # 最终仓库目录（兜底用）
	local DST_DIR="./package/$PKG_NAME"         # 最终落盘名（=包名）

	echo " "

	# 1) 清理旧目录：feeds + package/ 都扫，但绝不删自己刚装好的 DST
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND
		FOUND=$(find ./feeds/luci/ ./feeds/packages/ ./package/ \
			-maxdepth 4 -type d -iname "*$NAME*" 2>/dev/null \
			| grep -v "^$DST_DIR$" \
			| grep -v "^$REPO_TMP$" \
			| grep -v "^$REPO_TMP/" || true)
		if [ -n "$FOUND" ]; then
			while read -r DIR; do
				rm -rf "$DIR" && echo "Delete directory: $DIR"
			done <<< "$FOUND"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 2) 克隆：同一仓库只克隆一次（VIKINGYFY/packages 被调 8 次，只 clone 1 次）
	if [ -d "$REPO_TMP/.git" ]; then
		echo "Already cloned, reuse: $REPO_TMP"
	elif git ls-remote --exit-code --heads "https://github.com/$PKG_REPO.git" "$PKG_BRANCH" >/dev/null 2>&1; then
		echo "Branch mode: $PKG_BRANCH"
		git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
			"https://github.com/$PKG_REPO.git" "$REPO_TMP"
	else
		echo "Branch '$PKG_BRANCH' not found for $PKG_REPO, fall back to default branch"
		git clone --depth=1 "https://github.com/$PKG_REPO.git" "$REPO_TMP"
	fi

	# 3) 处理仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 一仓多包：按 PKG_NAME 精确提取子目录，目录名=包名
		find "$REPO_TMP" -mindepth 1 -maxdepth 4 -type d -name "$PKG_NAME" -print0 2>/dev/null | \
		while IFS= read -r -d '' DIR; do
			local BASENAME
			BASENAME=$(basename "$DIR")
			rm -rf "./package/$BASENAME"
			cp -rf "$DIR" "./package/$BASENAME"
			rm -rf "./package/$BASENAME/.git"
			echo "Extracted sub-package: ./package/$BASENAME"
		done
	else
		# 单包仓库：按 PKG_NAME 提取子目录；兜底用仓库根
		local PKG_SUB
		PKG_SUB=$(find "$REPO_TMP" -mindepth 1 -maxdepth 4 -type d -iname "$PKG_NAME" | head -1)
		if [ -n "$PKG_SUB" ]; then
			rm -rf "$DST_DIR"
			cp -rf "$PKG_SUB" "$DST_DIR"
			rm -rf "$DST_DIR/.git"
		else
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

	# 4) 校验
	if [ ! -f "$DST_DIR/Makefile" ]; then
		echo "ERROR: package directory not created: $DST_DIR" >&2
		return 1
	fi
	echo "Installed: $DST_DIR"
}

# ===================== 主题 =====================
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

# 集客等一仓多包：逐个提取，目录名=包名；已移除官方已有的 miniupnpd / luci-app-upnp
UPDATE_PACKAGE "axonhub" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "gecoosac" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "sing-box" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-homeproxy" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-timewol" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-wolplus" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-wolultra" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "v2dat" "sbwml/luci-app-mosdns" "v5" "pkg"

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
UPDATE_PACKAGE "openwrt-stuntman" "muink/openwrt-starmtan" "master"
UPDATE_PACKAGE "luci-app-natmapt" "muink/luci-app-natmapt" "master"

UPDATE_PACKAGE "luci-app-airpi3000m-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main"
UPDATE_PACKAGE "luci-app-chfs" "LianXia233/luci-app-chfs" "main"
UPDATE_PACKAGE "luci-app-fm350" "LianXia233/luci-app-fm350" "main"
UPDATE_PACKAGE "luci-app-h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"
UPDATE_PACKAGE "luci-app-mt5700" "LianXia233/luci-app-mt5700" "main"
UPDATE_PACKAGE "luci-app-mt5700m" "LianXia233/luci-app-mt5700m" "main"
UPDATE_PACKAGE "luci-app-netmonitor" "LianXia233/luci-app-netmonitor" "main"
UPDATE_PACKAGE "luci-app-qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"

# ========== 第三方扩展插件 ==========
echo "========================================"
echo "      EXTRA PACKAGES INSTALL START      "
echo "========================================"

# iStore：主包 + taskd 异步任务库（缺 luci-lib-taskd 则“安装”按钮无响应）
UPDATE_PACKAGE "luci-app-store" "linkease/istore" "main" "pkg" "store luci-lib-taskd taskd luci-lib-xterm"

# OAF 应用过滤：一仓三包 -> luci-app-oaf / oaf(kmod) / open-app-filter
# 注意：oaf 是内核模块，必须与内核同编，不可事后 opkg 补装
UPDATE_PACKAGE "luci-app-oaf" "destan19/OpenAppFilter" "master" "pkg" "oaf open-app-filter"

echo "========================================"
echo "       EXTRA PACKAGES INSTALL DONE      "
echo "========================================"

# ===================== linkease（易有云）=====================
# 主程序 Makefile 在 network/services/linkease/，前端在 luci/luci-app-linkease/
UPDATE_PACKAGE "linkease" "linkease/nas-packages" "master" "pkg"
UPDATE_PACKAGE "luci-app-linkease" "linkease/nas-packages-luci" "main" "pkg"

# ===================== 版本更新函数 =====================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES
	PKG_FILES=$(find ./package/ ./package/*/ ./feeds/packages/ ./feeds/luci/ \
		-maxdepth 4 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null | sort -u)

	[ -z "$PKG_FILES" ] && { echo "$PKG_NAME not found!"; return; }

	echo -e "\n$PKG_NAME version update has started!"
	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO
		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE" || true)
		[ -z "$PKG_REPO" ] && { echo "  skip (no github source): $PKG_FILE"; continue; }

		command -v jq >/dev/null 2>&1 || { echo "  skip (no jq)"; return; }
		local PKG_TAG
		PKG_TAG=$(curl -sL --retry 2 "https://api.github.com/repos/$PKG_REPO/releases" | \
			jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name" 2>/dev/null || true)
		[ -z "$PKG_TAG" ] || [ "$PKG_TAG" = "null" ] && { echo "  skip (no release): $PKG_REPO"; continue; }

		local OLD_VER OLD_URL OLD_FILE OLD_HASH
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL
		PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")
		local NEW_VER
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL
		NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH
		NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER" 2>/dev/null; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/; s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

# 引入私有扩展脚本
if [ -f "${GITHUB_WORKSPACE:-}/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
