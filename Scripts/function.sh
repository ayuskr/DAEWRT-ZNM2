#!/bin/bash

# 只追加“不会打开子菜单、不与版本相关”的内核符号。
# 教训：追加 TRANSPARENT_HUGEPAGE_*/DEBUG_INFO_REDUCED/SCHED_CLASS_EXT/ARM64_CONTPTE 这类
# 选项组或新版本符号，会让 6.18 的 syncconfig 重新进入交互模式（Restart config / (NEW)），
# 在 CI 非交互环境下直接 Error 1，内核编译中断。
# eBPF 所需的 BTF 由上层的 CONFIG_KERNEL_DEBUG_INFO_BTF 负责，不需要在这里重复。
KERNEL_SAFE_SYMBOLS='CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_CGROUPS=y
CONFIG_KPROBES=y
CONFIG_NET_INGRESS=y
CONFIG_NET_EGRESS=y
CONFIG_NET_SCH_INGRESS=m
CONFIG_NET_CLS_BPF=m
CONFIG_NET_CLS_ACT=y
CONFIG_BPF_STREAM_PARSER=y
CONFIG_KPROBE_EVENTS=y
CONFIG_BPF_EVENTS=y'

function cat_kernel_config() {
  local file=$1
  if [ ! -f "$file" ]; then
    echo "WARNING: kernel config-default not found: $file (skip kernel fragment)"
    return 0
  fi

  # 保证文件以换行结尾，否则追加的第一行会和原末行粘连
  if [ -n "$(tail -c 1 "$file")" ]; then
    echo "" >> "$file"
  fi

  local added=0 skipped=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local sym
    sym=$(echo "$line" | sed -E 's/^(CONFIG_[A-Za-z0-9_]+)=.*/\1/')
    if grep -qE "^${sym}=|^# ${sym} is not set$" "$file"; then
      skipped=$((skipped + 1))
      continue
    fi
    echo "$line" >> "$file"
    added=$((added + 1))
  done <<< "$KERNEL_SAFE_SYMBOLS"

  echo "cat_kernel_config -> $file (added ${added}, skipped ${skipped} existing)"
}

function cat_ebpf_config() {

#ebpf相关
  cat >> $1 <<EOF
#eBPF
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
EOF
}

function cat_usb_net() {
  cat >> $1 <<EOF
#USB CPE Driver
CONFIG_PACKAGE_kmod-usb-net=y
CONFIG_PACKAGE_kmod-usb-net-cdc-eem=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-net-cdc-mbim=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ncm=y
CONFIG_PACKAGE_kmod-usb-net-cdc-subset=y
CONFIG_PACKAGE_kmod-usb-net-huawei-cdc-ncm=y
CONFIG_PACKAGE_kmod-usb-net-ipheth=y
CONFIG_PACKAGE_kmod-usb-net-rndis=y
CONFIG_PACKAGE_kmod-usb-net-rtl8150=y
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
EOF
#6.12内核不包含以下驱动
if echo "$CI_NAME" | grep -v "6.12" > /dev/null; then
  cat >> $1 <<EOF
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan-fibocom=y
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan-quectel=y
EOF
fi

}

function set_nss_driver() {
  cat >> $1 <<EOF
#NSS驱动相关
CONFIG_NSS_FIRMWARE_VERSION_11_4=n
# CONFIG_NSS_FIRMWARE_VERSION_12_5 is not set
CONFIG_NSS_FIRMWARE_VERSION_12_2=y
CONFIG_PACKAGE_kmod-qca-nss-dp=y
CONFIG_PACKAGE_kmod-qca-nss-drv=y
CONFIG_PACKAGE_kmod-qca-nss-drv-bridge-mgr=y
CONFIG_PACKAGE_kmod-qca-nss-drv-vlan=y
CONFIG_PACKAGE_kmod-qca-nss-drv-igs=y
#CONFIG_PACKAGE_kmod-qca-nss-drv-map-t=y
CONFIG_PACKAGE_kmod-qca-nss-drv-pppoe=y
CONFIG_PACKAGE_kmod-qca-nss-drv-pptp=y
CONFIG_PACKAGE_kmod-qca-nss-drv-qdisc=y
CONFIG_PACKAGE_kmod-qca-nss-ecm=y
CONFIG_PACKAGE_kmod-qca-nss-macsec=y
CONFIG_PACKAGE_kmod-qca-nss-drv-l2tpv2=y
CONFIG_PACKAGE_kmod-qca-nss-drv-lag-mgr=y
EOF
}
function kernel_version() {
  echo $(sed -n 's/^KERNEL_PATCHVER:=\(.*\)/\1/p' target/linux/qualcommax/Makefile)
}
function remove_wifi() {
  local target=$1
  #去除依赖（含行尾形式）
  sed -i 's/\(ath11k-firmware-[^ ]*\|ipq-wifi-[^ ]*\|kmod-ath11k-[^ ]*\)//g' ./target/linux/qualcommax/Makefile
  sed -i 's/\(ath11k-firmware-[^ ]*\|ipq-wifi-[^ ]*\|kmod-ath11k-[^ ]*\)//g' ./target/linux/qualcommax/${target}/target.mk
  sed -i 's/\(ath11k-firmware-[^ ]*\|ipq-wifi-[^ ]*\|kmod-ath11k-[^ ]*\)//g' ./target/linux/qualcommax/image/${target}.mk
  sed -i 's/\(ath10k-firmware-[^ ]*\|kmod-ath10k [^ ]*\|kmod-ath10k-[^ ]*\)//g' ./target/linux/qualcommax/image/${target}.mk
  #清除行尾残留（如 DEVICE_PACKAGES := ipq-wifi-zn_m2）
  sed -i 's/[[:space:]]\+\(ath11k-firmware-\|ath10k-firmware-\|ipq-wifi-\|kmod-ath11k-\|kmod-ath10k-\)[^ ]*$//' ./target/linux/qualcommax/image/${target}.mk
  sed -i 's/^[[:space:]]*\(ath11k-firmware-\|ath10k-firmware-\|ipq-wifi-\|kmod-ath11k-\|kmod-ath10k-\)[^ ]*[[:space:]]*$//' ./target/linux/qualcommax/image/${target}.mk
  #删除无线组件
  rm -rf package/network/services/hostapd
  rm -rf package/firmware/ipq-wifi

  echo "---- zn_m2 device definition after wifi removal ----"
  sed -n '/^define Device\/zn_m2/,/^endef/p' ./target/linux/qualcommax/image/${target}.mk

  if grep -q 'ipq-wifi-zn_m2' ./target/linux/qualcommax/image/${target}.mk; then
    echo "ERROR: ipq-wifi-zn_m2 still referenced after wifi removal"
    exit 1
  fi
}

function set_kernel_size() {
  #修改jdc ax1800 pro 的内核大小为12M
  image_file='./target/linux/qualcommax/image/ipq60xx.mk'
  sed -i "/^define Device\/jdcloud_re-ss-01/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/jdcloud_re-cs-02/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/jdcloud_re-cs-07/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/redmi_ax5-jdcloud/,/^endef/ { /KERNEL_SIZE := 6144k/s//KERNEL_SIZE := 12288k/ }" $image_file
  sed -i "/^define Device\/linksys_mr/,/^endef/ { /KERNEL_SIZE := 8192k/s//KERNEL_SIZE := 12288k/ }" $image_file
}
#开启内存回收补丁
function enable_skb_recycler() {
  cat >> $1 <<EOF
CONFIG_KERNEL_SKB_RECYCLER=y
CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y
EOF
}

# 从配置文件解析明确的目标子平台名，例如 ipq60xx / ipq807x。
# 不能再用 WRT_ARCH 切割：zn_m2 会被切成 m2，导致 config-default 路径失效。
function target_subtarget() {
  local platform=$(sed -n 's/^CONFIG_TARGET_\([A-Za-z0-9]*\)=y$/\1/p' \
    "$GITHUB_WORKSPACE/Config/${WRT_CONFIG}.txt" | head -n 1)
  local subtarget=$(sed -n "s/^CONFIG_TARGET_${platform}_\([A-Za-z0-9]*\)=y$/\1/p" \
    "$GITHUB_WORKSPACE/Config/${WRT_CONFIG}.txt" | head -n 1)

  if [ -z "$subtarget" ] && [ -n "$WRT_ARCH" ]; then
    subtarget=$(echo "$WRT_ARCH" | cut -d'_' -f1)
  fi

  echo "$subtarget"
}

function generate_config() {
  config_file=".config"
  #如配置文件已存在
  cat $GITHUB_WORKSPACE/Config/${WRT_CONFIG}.txt $GITHUB_WORKSPACE/Config/GENERAL.txt  > $config_file
  local target=$(target_subtarget)
  echo "kernel config-default target: qualcommax/${target}"

  #删除wifi依赖
  if [[ "$WRT_CONFIG" == *"NOWIFI"* ]]; then
    remove_wifi $target
  fi

  #ipk仓库
  if [[ "${GITHUB_REPOSITORY,,}" == *"openwrt-ci-ipk"* ]]; then
    echo "CONFIG_USE_APK=n" >> $config_file
  fi

  set_nss_driver $config_file
  #增加ebpf
  cat_ebpf_config $config_file
  enable_skb_recycler $config_file
  set_kernel_size
  #增加内核选项（仅安全子集）
  cat_kernel_config "target/linux/qualcommax/${target}/config-default"
}