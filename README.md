# DAEWRT-AX1800PRO
京东云亚瑟AX1800pro专属固件包  
  
  固件集成增强版geoip.dat、geosite.dat,开箱即用，正确配置Dae不会报错


  源码来自：  [VIKINGYFY](https://github.com/VIKINGYFY/OpenWRT-CI) & [davidtall](https://github.com/davidtall/DaeWRT-CI)  
  略微修改，适度精简，确保最大性能发挥。  
  
  追求更加精简➡️https://github.com/GHNERCH/DAEWRT-AX1800PRO-MINI
  
  开启内核eBPF，Dae吃鹅优选，建议硬改1GB内存的使用。
  
  刷机前请更换分区表和uboot,参考链接: https://www.right.com.cn/forum/thread-8402269-1-1.html            
  全系带开源硬件加速。\
  一键加群👉：<a target="_blank" href="https://qm.qq.com/cgi-bin/qm/qr?k=6JLaTPbGP2Qc43A06HiIP7w-vCVrR7Iu&jump_from=webapi&authKey=aGTurX/4rsPB7hTWBLyXGQyzsYUdTyrjKXe7xwX0Dm3gqICCnIug5MkSoeeKqG0k"><img border="0" src="//pub.idqqimg.com/wpa/images/group.png" alt="GHNERCH-AX1800PRO交流群" title="GHNERCH-AX1800PRO交流群"></a>

## 新增 LuCI 主题

本修改版在固件中集成以下主题，默认仍使用 Glass，避免首次启动界面变化：

- **Vantage**：`luci-theme-vantage`，同时集成可选仪表盘应用 `luci-app-vantage`
- **Material Design 3**：`luci-theme-material3`

## 编译源码

当前编译目标为 `VIKINGYFY/immortalwrt` 的 `owrt` 分支（内核 6.18，`zn_m2` 与 `redmi_ax6` 均为其内置设备）。

- 硬件加速：该源码不提供 `nss_packages` feed，因此不再包含 `kmod-qca-nss-*`，改由 **PPE**（`qca-ppe-qos` / `luci-app-qca-ppe-qos`）承担加速与限速；
- 主题源码通过 `Scripts/Packages.sh` 拉取上游仓库的 package 目录，登录 LuCI 后可在「系统 → 系统 → 语言和界面」切换主题；
- 固件版本号保持上游原样（`ImmortalWrt SNAPSHOT rX-xxxxxxx / LuCI Master …`），不再附加编译者标识。

### 机型与配置文件

| 配置文件 | 机型 | WiFi | 说明 |
|---|---|---|---|
| `Config/IPQ60XX-NOWIFI.txt` | ZN-M2（京东云亚瑟 AX1800 Pro） | ❌ 编译期移除 | 主用配置 |
| `Config/IPQ807X-WIFI-YES.txt` | Redmi AX6 | ✅ 保留 | 需先刷 OpenWrt U-Boot（`redmi_ax6` = 扩展布局，kernel 分区 36MB） |
| `Config/IPQ60XX-WIFI-YES.txt` | ZN-M2 | ✅ 保留 | 备用，未加入 matrix |
| `Config/GENERAL.txt` | — | — | 共用插件清单，**不得包含任何 WiFi 开关** |

AX6 若仍使用原厂 bootloader，必须把 `redmi_ax6=y` 改为 `redmi_ax6-stock=y`，否则固件刷不进去。

## 编译说明（排障记录）

### 1. `config-default` 路径错误导致 eBPF 内核选项从未生效

早期版本用 `sed 's/.*_DEVICE_\(.*\)_DEVICE_.*/\1/p'` 从设备名推导子平台：

- `CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_zn_m2=y` → 被切成 `m2`；
- 于是 `target/linux/qualcommax/m2/config-default` 不存在，脚本只打印 `WARNING` 并静默跳过，
  eBPF/BTF 内核选项从未真正写入，`uname -r` 后面也看不到相关能力。

修复：新增 `target_subtarget()`，直接从配置文件解析

```sh
# 先取平台（qualcommax），再取 CONFIG_TARGET_qualcommax_<subtarget>=y
local platform=$(sed -n 's/^CONFIG_TARGET_\([A-Za-z0-9]*\)=y$/\1/p' Config/${WRT_CONFIG}.txt | head -n 1)
local subtarget=$(sed -n "s/^CONFIG_TARGET_${platform}_\([A-Za-z0-9]*\)=y$/\1/p" Config/${WRT_CONFIG}.txt | head -n 1)
```

日志中应出现 `kernel config-default target: qualcommax/ipq60xx`（或 `ipq807x`）。

### 2. 内核 config 片段触发 `syncconfig` 交互，导致 AX6 编译失败

现象（`target/linux` 阶段中断）：

```
* Restart config...
Allocate a PMD sized folio for zeroing (PERSISTENT_HUGE_ZERO_FOLIO) [N/y/?] (NEW)
make[8]: *** [scripts/kconfig/Makefile:85: syncconfig] Error 1
    ERROR: target/linux failed to build.
```

原因：向 `target/linux/qualcommax/<subtarget>/config-default` 追加的片段里含有**选项组（choice）**
与**版本敏感**符号：

- `CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS / _MADVISE / _NEVER` —— choice 组，会打开 THP 子菜单，
  引入 6.18 新增的无默认值符号（如 `PERSISTENT_HUGE_ZERO_FOLIO`）；
- `# CONFIG_DEBUG_INFO_REDUCED is not set` —— 与 `DEBUG_INFO` 的 choice 冲突；
- `CONFIG_SCHED_CLASS_EXT`、`CONFIG_ARM64_CONTPTE`、`CONFIG_PROBE_EVENTS_BTF_ARGS`、
  `CONFIG_IMX_SCMI_MISC_DRV` —— 新版本/依赖敏感，留下未回答项。

非交互环境下 `syncconfig` 遇到 `(NEW)` 提问即退出，内核编译直接失败。

修复：内核片段只保留 eBPF 必需的最小集（均为普通 bool/tristate，不打开子菜单），
BTF 交由 OpenWrt 层 `CONFIG_KERNEL_DEBUG_INFO_BTF=y`（走 OpenWrt 自己的合并流程，可自动 `olddefconfig`）：

```conf
CONFIG_BPF=y
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
CONFIG_BPF_EVENTS=y
```

同时给 `cat_kernel_config()` 加了两道保护：

- **换行保护**：文件末尾无换行时先补 `\n`，避免追加行与末行粘连；
- **去重**：符号已存在则跳过，日志输出 `cat_kernel_config -> … (added N, skipped M)`。

### 3. WiFi 开关必须按配置分流，否则 AX6 会被误关

WiFi 相关开关曾出现在**两个会被无条件执行**的位置：

- `Config/GENERAL.txt`（所有配置共用，`cat` 在设备配置之后，会覆盖设备配置）；
- `Scripts/Settings.sh`（在 `generate_config` **之后**执行，优先级更高）。

结果：AX6 配置本身想保留 WiFi，却仍被追加了 `# CONFIG_PACKAGE_kmod-ath11k is not set` 等 17 条，
编出的固件没有无线功能。

修复：

1. `GENERAL.txt` 只保留插件清单，**移除全部无线开关**；
2. `Settings.sh` 中的关闭块用配置名分流：

```sh
if [[ "$WRT_CONFIG" == *"NOWIFI"* ]]; then
	echo "关闭 WiFi 软件栈：$WRT_CONFIG"
	# … 17 条 is not set …
else
	echo "保留 WiFi 软件栈：$WRT_CONFIG"
fi
```

3. 无线组件只在 `*NOWIFI*` 配置中关闭；带 WiFi 的固件由目标默认包
   （`kmod-ath11k*`、`wpad-openssl`、`wifi-scripts`）与设备包（`ipq-wifi-*`）自动带入。

验证方式：刷机后 LuCI「网络 → 无线」应能看到 `phy0`（无线页面由 `luci-mod-network` 提供，
旧版 `luci-app-wireless` 已废弃，故不会出现在插件列表里）。

### 4. `remove_wifi` 清理不彻底导致镜像阶段缺包

`remove_wifi()` 原先只用 `sed 's/ipq-wifi-[^ ]*//g'` 这类匹配，**行尾**的
`DEVICE_PACKAGES := ipq-wifi-zn_m2` 匹配不到，删除 `package/firmware/ipq-wifi` 后会留下悬空引用。

修复：补充行尾清理 + 校验（残留则 `exit 1`），并打印清理后的 `zn_m2` 定义便于核对：

```sh
sed -i 's/[[:space:]]\+\(…\|ipq-wifi-\|…\)[^ ]*$//' target/linux/qualcommax/image/${target}.mk
if grep -q 'ipq-wifi-zn_m2' target/linux/qualcommax/image/${target}.mk; then
	echo "ERROR: ipq-wifi-zn_m2 still referenced after wifi removal"; exit 1
fi
```

### 排障小结

| 现象 | 根因 | 修复位置 |
|---|---|---|
| 内核选项没生效、`uname -r` 无变化 | 子平台被切成 `m2`，`config-default` 路径不存在 | `function.sh: target_subtarget()` |
| `syncconfig` 卡在 `(NEW)` 提问 | config 片段含 choice 组/版本敏感符号 | `function.sh: cat_kernel_config()` |
| AX6 固件没有 WiFi | WiFi 关闭项写在 GENERAL 与 Settings.sh 里无条件下发 | `GENERAL.txt`、`Settings.sh` |
| 镜像阶段 `Package ipq-wifi-zn_m2 is missing` | sed 漏掉行尾引用 | `function.sh: remove_wifi()` |
| 版本号出现 `DaeWRT-日期` | LuCI `10_system.js` 被追加编译者标识 | `Settings.sh`（已移除） |