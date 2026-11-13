#!/bin/bash

. "$(dirname "$(realpath "$0")")/function.sh"

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

# 说明：不再向 LuCI 状态页追加 " / DaeWRT-<日期>" 之类的编译者标识，
# 固件版本保持上游原样（ImmortalWrt SNAPSHOT rX-xxxxxxx / LuCI Master ...）。

# ============================================================
# ipq807x（Redmi AX6）：内置 /etc/config/network
#
# 现象：刷入后链路已协商到 1Gbps（PHY 正常），但 br-lan 里没有端口，
#       电脑拿不到 DHCP、静态 IP 也 ping 不通 10.0.0.1。
# 说明 board_detect -> board.json -> config_generate 这条链在 AX6 上没有
# 生成正确的 LAN 桥。这里直接写死配置，让网络不再依赖板级探测结果。
#
# 端口名取自 dts/ipq8071-xiaomi.dtsi：wan / lan1 / lan2 / lan3（DSA）。
# config_generate 只在 /etc/config/network 为空时才会生成，
# 因此内置此文件后它只负责补 /etc/config/system（主机名、LED 等）。
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

	cat ./files/etc/config/network
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

# 是否移除 WiFi 由配置文件名决定：
#   *NOWIFI*  -> 关闭整条无线软件栈（ZN-M2 无 WiFi 固件）
#   其它      -> 保留 WiFi（如 IPQ807X-WIFI-YES / Redmi AX6）
# 注意：本步骤在 generate_config 之后执行，写在这里的开关会覆盖设备配置，
# 因此必须按配置分流，不能无条件关闭。
if [[ "$WRT_CONFIG" == *"NOWIFI"* ]]; then
	echo "关闭 WiFi 软件栈：$WRT_CONFIG"
	echo "# CONFIG_PACKAGE_ipq-wifi-zn_m2 is not set" >> ./.config
	echo "# CONFIG_PACKAGE_kmod-ath11k is not set" >> ./.config
	echo "# CONFIG_PACKAGE_kmod-ath11k-ahb is not set" >> ./.config
	echo "# CONFIG_PACKAGE_kmod-ath11k-pci is not set" >> ./.config
	echo "# CONFIG_PACKAGE_ath11k-firmware-ipq6018 is not set" >> ./.config
	echo "# CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt is not set" >> ./.config
	echo "# CONFIG_PACKAGE_kmod-mac80211 is not set" >> ./.config
	echo "# CONFIG_PACKAGE_kmod-cfg80211 is not set" >> ./.config
	echo "# CONFIG_PACKAGE_kmod-lib80211 is not set" >> ./.config
	echo "# CONFIG_PACKAGE_wifi-scripts is not set" >> ./.config
	echo "# CONFIG_PACKAGE_wpad-openssl is not set" >> ./.config
	echo "# CONFIG_PACKAGE_wpad-basic-mbedtls is not set" >> ./.config
	echo "# CONFIG_PACKAGE_wpad-basic-wolfssl is not set" >> ./.config
	echo "# CONFIG_PACKAGE_hostapd-common is not set" >> ./.config
	echo "# CONFIG_PACKAGE_iw is not set" >> ./.config
	echo "# CONFIG_PACKAGE_iwinfo is not set" >> ./.config
	echo "# CONFIG_PACKAGE_luci-app-wireless is not set" >> ./.config
else
	echo "保留 WiFi 软件栈：$WRT_CONFIG"
fi

# 手动触发工作流时附加的插件配置。
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

# 高通 NSS 配置：仅为 ipq60xx（ZN-M2）调参，必须按子平台分流。
# 这段以前对 *QUALCOMMAX* 无条件追加，会把 NSS 固件版本钉成 12_5，
# 与 function.sh 中 ipq60xx 路径的 12_2 冲突；
# 而 ipq807x 的默认选型也会被搅乱，因此只在 ipq60xx 上应用。
if [[ "$(target_subtarget)" == "ipq60xx" ]]; then
	echo "应用 NSS 配置：$(target_subtarget)"
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
else
	echo "跳过 NSS 配置：$(target_subtarget) 沿用上游默认"
fi