#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
# =====================================================================
# 在作者原版基础上的最小化修正（行为不变，只修会炸的点）：
#
# 1) aurora：PKG_NAME 从 "aurora" 改为正式包名 "luci-theme-aurora"，
#    与 .config 里的 CONFIG_PACKAGE_luci-theme-aurora=y 严格对齐，
#    根治 package/install 阶段的 "luci-theme-aurora (no such package)"。
#    同时加第5参数，让清理阶段把旧目录 ./package/aurora 也清掉。
#
# 2) viking（集客等一仓多包）：从"整仓 mv"改为 "pkg" 精准展开。
#    原版整仓 mv 后目录名为 package/VIKINGYFY-packages，扫描器
#    能识别，但和 PKG_NAME=viking 不对应，且与你 .config 里
#    CONFIG_PACKAGE_gecoosac=y 的依赖链不一致；用 pkg 让每个子包
#    独立落到 package/ 下，目录名=包名。
#
# 3) 修复原版三个真实 bug（不改动原版的设计意图）：
#    a) 无 "pkg" 分支时，仓库 clone 到 package/REPO_NAME，但脚本
#       从不 mv 它 → 目录名是 "luci-theme-aurora"/"nas-packages" 之类，
#       而 menuconfig 可见名来自 Makefile 的 PKG_NAME，两者不一致
#       正是 aurora 报错的根因之一。这里统一在 clone 后按 PKG_NAME 落盘。
#    b) 未设 trap：clone 失败/中途退出会留下 $TMP 或残缺目录。
#    c) 分支不存在时 git clone --branch 直接失败退出（set -e）。
#
# 4) 补上易有云：linkease / luci-app-linkease，走 pkg 精准展开，
#    依赖（luci-lib-linkeasefile 等）随仓库子目录一并被扫描注册。
#
# 注意：本脚本须在 OpenWrt 源码树根目录执行（即存在 package/ 的目录）。
# =====================================================================
set -euo pipefail

UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=${4:-}
	local PKG_LIST=("$PKG_NAME" ${5:-})
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"
	local DST_DIR="./package/$PKG_NAME"

	echo " "

	# 删除本地可能存在的不同名称的软件包（feeds + package/ 都扫，避免旧目录干扰）
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS
		FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ ./package/ \
			-maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null | grep -v "^$DST_DIR$" || true)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 幂等：已是 git 仓库则跳过克隆（离线/重跑友好）
	if [ -d "$REPO_PATH/.git" ]; then
		echo "Already exists, skip clone: $REPO_PATH"
	elif git ls-remote --exit-code --heads "https://github.com/$PKG_REPO.git" "$PKG_BRANCH" >/dev/null 2>&1; then
		echo "Branch mode: $PKG_BRANCH"
		git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
			"https://github.com/$PKG_REPO.git" "$REPO_PATH"
	else
		echo "Branch '$PKG_BRANCH' not found for $PKG_REPO, fall back to default branch"
		git clone --depth=1 "https://github.com/$PKG_REPO.git" "$REPO_PATH"
	fi

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		# 从大杂烩中按 PKG_NAME 精准提取子包到 package/ 下，目录名=包名
		find "$REPO_PATH" -maxdepth 3 -type d -iname "*$PKG_NAME*" -print0 2>/dev/null | \
		while IFS= read -r -d '' DIR; do
			local BASENAME
			BASENAME=$(basename "$DIR")
			cp -rf "$DIR" "./package/$BASENAME"
			echo "Extracted sub-package: ./package/$BASENAME"
		done
		rm -rf "$REPO_PATH"
	else
		# 单包仓库：统一以正式包名 PKG_NAME 落盘，保证目录名=PKG_NAME
		if [ -d "$REPO_PATH" ] && [ "$REPO_PATH" != "$DST_DIR" ]; then
			rm -rf "$DST_DIR"
			mv -f "$REPO_PATH" "$DST_DIR"
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
# 关键修复：PKG_NAME 用正式包名 luci-theme-aurora，与 .config 对齐
UPDATE_PACKAGE "luci-theme-aurora" "eamonxg/luci-theme-aurora" "master" "" "aurora"
UPDATE_PACKAGE "luci-theme-argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "luci-app-aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "luci-theme-fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "luci-theme-footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "luci-theme-kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "luci-app-kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "luci-theme-shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "luci-theme-vantage" "anothaDev/luci-theme-vantage" "main"

# ===================== 网络 / 代理 =====================
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

# ===================== 工具 / 系统 =====================
UPDATE_PACKAGE "luci-app-mini-diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "luci-app-easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "QModem" "FUjr/QModem" "main"
# 集客等一仓多包：用 pkg 精准展开，每个子目录独立成包（目录名=包名）
UPDATE_PACKAGE "gecoosac" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-gecoosac" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "axonhub" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "sing-box" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-homeproxy" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-timewol" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-wolplus" "VIKINGYFY/packages" "main" "pkg"
UPDATE_PACKAGE "luci-app-wolultra" "VIKINGYFY/packages" "main" "pkg"
# 注：miniupnpd / luci-app-upnp 属 OpenWrt 官方 feeds 已有包，
#     不建议从第三方覆盖，已从原 viking 列表移除，避免覆盖官方包导致 coremark 类错误。

UPDATE_PACKAGE "luci-app-diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "luci-app-mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
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

# ===================== 易有云（linkease）=====================
# 走 pkg 精准展开：主程序 + luci 前端 + 依赖库(luci-lib-linkeasefile 等) 一并注册
UPDATE_PACKAGE "linkease" "linkease/nas-packages" "master" "pkg"
UPDATE_PACKAGE "luci-app-linkease" "linkease/nas-packages-luci" "main" "pkg"

# ===================== 版本更新函数 =====================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES
	PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null)

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

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
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
if [ -f "${GITHUB_WORKSPACE:-}/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
