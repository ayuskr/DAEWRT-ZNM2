#!/bin/bash

. "$(dirname "$(realpath "$0")")/function.sh"

# ============================================================
# 原则：凡上游 VIKINGYFY/OpenWRT-CI 已有的逻辑，这里不重复、不改写。
# 上游 Scripts/Settings.sh 里没有任何 NSS / PPE 的强制开关，
# NSS 与 PPE(ipq807x 4096 条) 都来自源码里目标平台的默认选包。
# 之前本仓库自行追加的 NSS 强制与强制关闭，反而把 NSS 关掉了，现已移除。
# ============================================================

# 修改默认主题依赖。
THEME_MAKEFILES=$(find ./feeds/luci/collections/ -type f -name "Makefile")

if [ -n "$THEME_MAKEFILES" ]; then
	sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $THEME_MAKEFILES
fi

# 修改 LuCI 默认访问地址。
FLASH_JS=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")

if [ -n "$FLASH_JS" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $FLASH_JS
fi

# 修改默认 IP 地址和主机名。
CFG_FILE="./package/base-files/files/bin/config_generate"

if [ -f "$CFG_FILE" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
fi

# ============================================================
# ipq807x（Redmi AX6 / stock layout）：内置 /etc/config/network
#
# 本机为原厂分区表，固件必须用 -stock 变体。
# 内置此文件可让网络不再依赖 board_detect -> board.json 的探测结果，
# 避免出现「链路 1Gbps、但 br-lan 无端口、拿不到 IP」这类问题。
#
# 端口名取自 dts/ipq8071-xiaomi.dtsi：wan / lan1 / lan2 / lan3（DSA）。
# config_generate 只在 /etc/config/network 为空时才生成网络配置，
# 因此内置后它只负责补 /etc/config/system（主机名、LED 等）。
# ============================================================
if [[ "$(target_subtarget)" == "ipq807x" ]]; then
	echo "内置 /etc/config/network（ipq807x：br-lan = lan1 lan2 lan3）"

	mkdir -p ./files/etc/config

	cat > ./files/etc/config/network <<EOF
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'auto'
	option dhcp_default_duid 'auto'

config device
	option name 'br-lan'
	option type 'bridge'
	list ports 'lan1'
	list ports 'lan2'
	list ports 'lan3'

config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	option ipaddr '$WRT_IP'
	option netmask '255.255.255.0'
	option ip6assign '60'

config interface 'wan'
	option device 'wan'
	option proto 'dhcp'

config interface 'wan6'
	option device 'wan'
	option proto 'dhcpv6'
EOF
fi

# ============================================================
# PPE / NSS 诊断（qualcommax：ipq807x + ipq60xx）
#
# 目的：确认 PPE 硬件 flow 表的真实容量（ipq807x 4096 / ipq60xx 2048 是否硬上限）。
# 用法：刷机后 SSH 执行 ppe-diag，或直接看 /tmp/ppe-diag.txt
#       （首启动会自动采集一次并写入 syslog，标签 ppe-diag）
# ============================================================
if [[ "$(target_subtarget)" == "ipq807x" || "$(target_subtarget)" == "ipq60xx" ]]; then
	echo "内置 ppe-diag 诊断脚本（输出 PPE/NSS 表容量与驱动参数）"

	mkdir -p ./files/usr/sbin ./files/etc/uci-defaults

	cat > ./files/usr/sbin/ppe-diag <<'PPE_DIAG_EOF'
#!/bin/sh
# PPE / NSS 诊断：打印硬件 flow 表容量、驱动参数与设备树节点
OUT=${1:-/tmp/ppe-diag.txt}

dump_node() {
	[ -d "$1" ] || return 0
	echo "[$1]"
	for f in "$1"/*; do
		[ -f "$f" ] || continue
		sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
		case "$sz" in
			1|2|4|8) echo "  $(basename "$f") = 0x$(od -An -tx1 "$f" | tr -d ' \n')" ;;
			"") : ;;
			*) echo "  $(basename "$f") = <${sz} bytes>" ;;
		esac
	done
}

{
	echo "===== PPE / NSS 诊断 $(date) ====="
	echo
	echo "--- 机型 ---"
	cat /tmp/sysinfo/model 2>/dev/null
	cat /tmp/sysinfo/board_name 2>/dev/null
	uname -a
	echo
	echo "--- 相关模块 ---"
	lsmod 2>/dev/null | grep -Ei 'ppe|nss|edma|dsa|qca' || echo "(无匹配模块)"
	echo
	echo "--- 模块参数（表容量常见于此）---"
	for d in /sys/module/*ppe* /sys/module/*nss* /sys/module/qca*; do
		[ -d "$d" ] || continue
		echo "[$d]"
		for p in "$d"/parameters/*; do
			[ -e "$p" ] && echo "  $(basename "$p") = $(cat "$p" 2>/dev/null)"
		done
	done
	echo
	echo "--- 设备树：ppe 节点 ---"
	found=""
	for n in $(find /proc/device-tree -maxdepth 4 -iname '*ppe*' 2>/dev/null); do
		found=1
		dump_node "$n"
	done
	[ -z "$found" ] && echo "(无 ppe 节点)"
	echo
	echo "--- 设备树：switch / ess 节点 ---"
	found=""
	for n in $(find /proc/device-tree -maxdepth 4 \( -iname '*switch*' -o -iname '*ess*' \) 2>/dev/null); do
		found=1
		dump_node "$n"
	done
	[ -z "$found" ] && echo "(无 switch/ess 节点)"
	echo
	echo "--- debugfs 顶层 ---"
	ls /sys/kernel/debug 2>/dev/null | head -40 || echo "(debugfs 未挂载)"
	echo
	echo "--- ecm / nss 状态 ---"
	ls /sys/kernel/debug/ecm 2>/dev/null || echo "(无 ecm)"
	echo
	echo "--- 中断（ppe/edma/nss）---"
	grep -Ei 'ppe|edma|nss' /proc/interrupts 2>/dev/null || echo "(无匹配)"
	echo
	echo "--- dmesg 关键行 ---"
	dmesg 2>/dev/null | grep -Ei 'ppe|nss|edma|dsa|switch' | tail -40 || echo "(无匹配)"
	echo
	echo "===== 诊断结束 ====="
} > "$OUT" 2>&1

cat "$OUT"
echo
echo "结果已保存到 $OUT"
PPE_DIAG_EOF

	chmod 0755 ./files/usr/sbin/ppe-diag

	cat > ./files/etc/uci-defaults/98-ppe-diag <<'UCI_EOF'
#!/bin/sh
# 首启动自动采集一次 PPE/NSS 诊断，写入 syslog（标签 ppe-diag）
[ -x /usr/sbin/ppe-diag ] && /usr/sbin/ppe-diag /tmp/ppe-diag.txt >/dev/null 2>&1
[ -f /tmp/ppe-diag.txt ] && logger -t ppe-diag -f /tmp/ppe-diag.txt

rm -f /etc/uci-defaults/98-ppe-diag
exit 0
UCI_EOF

	chmod 0755 ./files/etc/uci-defaults/98-ppe-diag
fi

# 将 Glass 设置为 LuCI 默认主题。
mkdir -p ./files/etc/uci-defaults

cat > ./files/etc/uci-defaults/99-default-theme <<'EOF'
#!/bin/sh

uci -q set luci.main.mediaurlbase='/luci-static/glass'
uci -q commit luci

rm -f /etc/uci-defaults/99-default-theme
exit 0
EOF

chmod 0755 ./files/etc/uci-defaults/99-default-theme

# 启用 LuCI、中文语言包和 Glass 主题。
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-glass=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-vantage=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-vantage=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-material3=y" >> ./.config

# 禁用原默认主题与其配置页面。
echo "# CONFIG_PACKAGE_luci-theme-bootstrap is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-argon is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-argon-config is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-theme-aurora is not set" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-aurora-config is not set" >> ./.config

# 手动触发工作流时附加的插件配置。
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi