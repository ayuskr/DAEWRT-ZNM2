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