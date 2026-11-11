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

当前编译目标为 `VIKINGYFY/immortalwrt` 的 `owrt` 分支（内核 6.18，`zn_m2` 设备为其内置支持）。

- 硬件加速：该源码不提供 `nss_packages` feed，因此不再包含 `kmod-qca-nss-*`，改由 **PPE**（`qca-ppe-qos` / `luci-app-qca-ppe-qos`）承担加速与限速；
- 主题源码通过 `Scripts/Packages.sh` 拉取上游仓库的 package 目录，登录 LuCI 后可在「系统 → 系统 → 语言和界面」切换主题；
- 提供两套编译配置：`Config/IPQ60XX-WIFI.txt`（保留网络子系统）与 `Config/IPQ60XX-NOWIFI.txt`（编译期直接移除 WiFi 驱动、固件、hostapd/wpad 与无线 LuCI 页面）。