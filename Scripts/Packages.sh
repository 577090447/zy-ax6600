#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
# =====================================================================
# 修复要点（方案1 根治 luci-theme-aurora no such package）：
# 1) 所有第三方包统一克隆/移动到 package/ 目录下，确保被 OpenWrt 扫描。
# 2) 目录名一律等于 OpenWrt 真实包名（PKG_NAME），避免 menuconfig 可见
#    但 package/install 阶段 apk 索引里没有的问题。
# 3) aurora 主题：PKG_NAME 用正式包名 luci-theme-aurora，与 .config 里的
#    CONFIG_PACKAGE_luci-theme-aurora=y 严格对齐。
# 4) 增加幂等：package/ 下已存在且为 git 仓库时跳过克隆。
# 5) 删除旧包时，额外扫描 ./package/，保证旧目录被清干净。
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
	# 所有包最终都落到 package/ 下，目录名 = 包名
	local DST_DIR="package/$PKG_NAME"

	echo " "

	# 删除本地可能存在的同名/近似软件包目录（feeds + package/ 都扫）
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS
		FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ ./package/ \
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

	# 若 package/ 下已是目标目录且为 git 仓库，跳过克隆（幂等/离线友好）
	if [ -d "$DST_DIR/.git" ]; then
		echo "Already exists, skip clone: $DST_DIR"
	else
		# 先克隆到临时目录，再统一放进 package/
		local TMP_DIR
		TMP_DIR=$(mktemp -d "./.tmp_${PKG_NAME}_XXXXXX")
		trap 'rm -rf "$TMP_DIR"' RETURN

		# 克隆 GitHub 仓库（支持分支和 tag 自动识别）
		if git ls-remote --tags "https://github.com/$PKG_REPO.git" 2>/dev/null \
			| grep -q "refs/tags/$PKG_BRANCH$"; then
			echo "Tag mode detected: $PKG_BRANCH"
			git clone --depth=1 "https://github.com/$PKG_REPO.git" "$TMP_DIR/repo"
			git -C "$TMP_DIR/repo" fetch --depth=1 origin "refs/tags/$PKG_BRANCH:refs/tags/$PKG_BRANCH"
			git -C "$TMP_DIR/repo" checkout -q "refs/tags/$PKG_BRANCH"
		else
			echo "Branch mode: $PKG_BRANCH"
			git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
				"https://github.com/$PKG_REPO.git" "$TMP_DIR/repo"
		fi

		# 处理克隆的仓库
		if [[ "$PKG_SPECIAL" == "pkg" ]]; then
			# 仓库内含多个子包：找出名为 PKG_NAME 的子目录，拷到 package/ 下
			find "$TMP_DIR/repo"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune \
				-exec cp -rf {} "./package/" \;
		else
			# 默认 / name：目录名统一为正式包名 PKG_NAME
			mv -f "$TMP_DIR/repo" "$DST_DIR"
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
# UPDATE_PACKAGE "luci-theme-argon" "sbwml/luci-theme-argon" "openwrt-25.12"
# ↑↑↑ 关键修复：PKG_NAME 用正式包名 luci-theme-aurora，与 .config 对齐
UPDATE_PACKAGE "luci-theme-aurora" "eamonxg/luci-theme-aurora" "master"
# UPDATE_PACKAGE "luci-app-aurora-config" "eamonxg/luci-app-aurora-config" "master"
# UPDATE_PACKAGE "luci-theme-kucat" "sirpdboy/luci-theme-kucat" "master"
# UPDATE_PACKAGE "luci-app-kucat-config" "sirpdboy/luci-app-kucat-config" "master"
# UPDATE_PACKAGE "luci-theme-noobwrt" "nooblk-98/luci-theme-noobwrt" "master"
# UPDATE_PACKAGE "luci-theme-shadcn" "eamonxg/luci-theme-shadcn" "main"
# UPDATE_PACKAGE "luci-theme-fluent" "LazuliKao/luci-theme-fluent" "main"

# 👇 新增主题（PKG_NAME 统一用正式包名）
UPDATE_PACKAGE "luci-theme-footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "luci-theme-vantage" "anothaDev/luci-theme-vantage" "main"

# ===================== 网络 / 代理 =====================
UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

# ===================== 工具 / 系统 =====================
# UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
UPDATE_PACKAGE "luci-app-tcpdump" "KFERMercer/luci-app-tcpdump" "master" "" "tcpdump"

UPDATE_PACKAGE "luci-app-ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "luci-app-diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "luci-app-mini-diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "luci-app-easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "luci-app-mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "luci-app-netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "luci-app-openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "luci-app-partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "luci-app-qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "luci-app-quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "luci-app-timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac sing-box luci-app-homeproxy luci-app-timewol luci-app-wolplus luci-app-wolultra"
UPDATE_PACKAGE "luci-app-vnt" "lmq8267/luci-app-vnt" "main"

# ===================== LED 控制器 (雅典娜 AX6600) =====================
# UPDATE_PACKAGE "athena-led" "577090447/JDC-AX6600-Athena-LED-Controller" "main" "pkg"
# UPDATE_PACKAGE "luci-app-athena-led" "577090447/JDC-AX6600-Athena-LED-Controller" "main" "pkg"

# ========== 第三方扩展插件 ==========
echo "========================================"
echo "      EXTRA PACKAGES INSTALL START      "
echo "========================================"
UPDATE_PACKAGE "luci-app-store" "linkease/istore" "main" "" "store"
UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf open-app-filter"
UPDATE_PACKAGE "luci-app-harbor-file" "destan19/luci-app-harbor-file" "main" "" "luci-app-harbor-file"
echo "========================================"
echo "       EXTRA PACKAGES INSTALL DONE      "
echo "========================================"

# ===================== linkease（易有云） =====================
# ↑ 注意：nas-packages / nas-packages-luci 都是"一仓多包"结构，
#   必须用 "pkg" 模式把子目录逐个展开到 package/ 下，否则顶层无 Makefile 导致漏编。
#   PKG_NAME 用该仓库里你实际需要的那个包名（与 .config 对齐）：
#     linkease/nas-packages  -> 主包 PKG_NAME 为 linkease（master 分支 network/services/linkease）
#     nas-packages-luci      -> 主包 luci-app-linkease，依赖 +linkease +luci-lib-linkeasefile
UPDATE_PACKAGE "linkease" "linkease/nas-packages" "master" "pkg"
UPDATE_PACKAGE "luci-app-linkease" "linkease/nas-packages-luci" "main" "pkg"

# ===================== 版本更新函数 =====================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES
	PKG_FILES=$(find ./package/ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null)

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
		PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

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

# 引入私有扩展脚本
if [ -f "${GITHUB_WORKSPACE:-}/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

# ===================== 主题固化（✅ 已切换为 aurora） =====================
# 注意：uci 里的 theme="aurora" 是 LuCI 主题标识（对应 /luci-static/aurora），
#       与包名 luci-theme-aurora 是两码事，这里无需改动。
sed -i '/luci.main.theme/d' package/emortal/default-settings/files/zzz-default-settings
sed -i '/mediaurlbase/d' package/emortal/default-settings/files/zzz-default-settings

mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-set-theme <<'EOF'
#!/bin/sh
uci set luci.main.theme="aurora"
uci set luci.main.mediaurlbase="/luci-static/aurora"
uci commit luci
rm -rf /tmp/luci-*
/etc/init.d/uhttpd restart
exit 0
EOF

chmod +x files/etc/uci-defaults/*
