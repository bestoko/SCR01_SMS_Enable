**中文** | [English](README_EN.md)

# SCR01 SMS Enable

让三星 **SCR-01（Galaxy 5G Mobile Wi-Fi）纯数据 5G 路由器**支持收发短信（接收验证码、发送短信）的 KernelSU 模块。

> [!WARNING]
> 本模块依赖临时 root（SCRoot）。临时 root 依赖内核漏洞，可能重启或崩溃设备。仅在你自己拥有的设备上使用。

## 功能

- ✅ 收短信：验证码等短信送达 Fossify Messages
- ✅ 发短信：从 Fossify Messages 发送短信
- ✅ 中国移动 / 联通 / 电信 IMS 配置自适应
- ✅ 新西兰 Skinny（53005）在中国漫游（China Mobile 46000）可用
- ✅ 内置 APN 数据库（约 4000 条，来自 LineageOS/AOSP，Apache-2.0），按 SIM PLMN + 注册 PLMN 自动补 `default` / `ims` APN
- ✅ 自动修补 Samsung IMS profile（`support_roaming` / `smsip` / `ipv4v6` / `enc_algo=all`）
- ✅ 不强制打开移动数据或漫游数据；三星的 IMS PDN 是 always-on 的
- ✅ 不写真实分区：bind-mount + 运行时 overlay，`uninstall.sh` 一键回滚
- ✅ 开机自动生效（无需手动操作）
- ✅ 日志轮转（128 KiB + 一份备份）与 `collect-logs.sh` 一键排障

## 兼容性

| 项目 | 支持 |
| --- | --- |
| 设备 | Samsung SCR-01 / SM-H412J（Galaxy 5G Mobile Wi-Fi） |
| 固件 | `SCR01KDU1AVK2`（Android 11） |
| Root | [SCRoot](https://github.com/hackintoanetwork/SCRoot)（KernelSU-Next，临时 root） |
| 短信应用 | [Fossify Messages](https://github.com/FossifyOrg/Messages)（默认，可配置） |
| 运营商 | 中国移动 / 联通 / 电信；新西兰 Skinny（53005）在中国漫游（China Mobile 46000）。其他运营商通常可由内置 APN 库覆盖，IMS profile 会按当前 SIM 打通用补丁 |

## 前置条件

1. 已通过 [SCRoot](https://github.com/hackintoanetwork/SCRoot) 获取临时 root，并开启 **“开机自动 root（Run at boot）”**。
2. 已安装 [Fossify Messages](https://github.com/FossifyOrg/Messages)（F-Droid 可装）。

## 安装

1. 从 [Releases](https://github.com/bestoko/SCR01_SMS_Enable/releases) 下载 `scr01_sms_enable-v2.2.1.zip`。
2. 安装模块（二选一）：

   - **方法一（推荐）：用 KernelSU 管理器直接安装 zip**（模块文件在 zip 根目录，管理器可直接识别）。
   - **方法二（手动）**：解压 zip，把里面的文件（`module.prop`、`boot-completed.sh`、`collect-logs.sh`、`uninstall.sh`、`payload/`）放进 `/data/adb/modules/scr01_sms_enable/`：

     ```bash
     adb push <解压目录> /data/local/tmp/scr01_sms_enable/
     adb shell su -c 'cp -r /data/local/tmp/scr01_sms_enable /data/adb/modules/'
     ```

3. 重启设备。SCRoot 会在开机后约 2 分钟自动重新 root，之后本模块自动生效。**重启后请等 root 完成，不要提前执行 `su`，否则会打断 root 注入。**

## 用法

- 重启后无需手动操作，模块自动完成配置（overlay + 角色 + APN + IMS profile）。
- 打开 **Fossify Messages** 即可收发短信。
- 回滚：

  ```bash
  adb shell su -c 'sh /data/adb/modules/scr01_sms_enable/uninstall.sh'
  ```

  或直接删除 `/data/adb/modules/scr01_sms_enable` 后重启。

## 工作原理

SCR-01 自带的静态 product overlay 把系统资源 `config_sms_capable` 写死为 **false**，于是 Android 电话框架会：

1. 丢弃收到的短信（`InboundSmsHandler.mSmsReceiveDisabled=true`）；
2. 拒绝发送短信（`SMSDispatcher.mSmsSendDisabled=true`）；
3. 开机时不把 `android.app.role.SMS` 注册为“可用角色”，导致 Fossify 等短信应用启动时报“发生不明错误”（因为 `isRoleAvailable(SMS)` 为 false）。

本模块在运行时、不碰真实分区地修复以上三点：

1. **让框架看到 `config_sms_capable=true`**：把只含 `config_sms_capable=true` 的最小资源 overlay bind-mount 到可变的 `AccentColorCinnamon` 主题 overlay 上，再 `cmd overlay enable`。这会广播 `ACTION_OVERLAY_CHANGED`，使 `com.android.phone` 与 `permissioncontroller` 进程重启后重新读到 true。
2. **注册短信角色**：调用系统 RoleManager 的 `setRoleNamesFromController()`，把 `android.app.role.SMS` 强制加入可用角色列表（正常情况下因 `config_sms_capable=false` 而缺失）。这让 `isRoleAvailable(SMS)` 变为 true，也允许后续授权。
3. **授予角色 + 配置 IMS**：把 `android.app.role.SMS` 授予短信应用（自动授予 RECEIVE_SMS/SEND_SMS/READ_SMS），按 SIM PLMN 与注册 PLMN 补 APN，修补 Samsung IMS profile，并打开 volte/smsip，让短信走 IMS（本设备是纯数据路由器，无电路域短信）。

**为什么不能“开机前改 overlay”？** 在这台设备上 root 来得晚——SCRoot 是通过 Mali 漏洞在开机几分钟后才注入的，此时 zygote 早已预加载了 framework 资源；晚挂载的 overlay 改不动 zygote 的缓存视图。而“软重启 zygote”来重新加载也不行——它会搞挂 framework，因为 SCRoot 的临时凭据钩子是一次性的。所以采用上面的“主题 overlay + 进程重启”方案。

### 中国电信（46011）特例

中国电信有两个历史 PLMN：CDMA 遗留的 **46003** 与 LTE 的 **46011**。部分电信卡的 HPLMN 为空、EHPLMN 为 `46011,46003`，设备的 APN 引擎会按 **46003** 做匹配，于是模块建的 46011 IMS APN 永远不被选中，而内置 `cmnet`（46003，type 带 `ims`）抢走了 IMS 数据连接却拿不到 P-CSCF → IMS 不注册 → 短信“无服务(S4)”。v2.1 起对 46011 SIM **同时建 46011 / 46003 两条 IMS APN**，并**剥掉内置 APN 的 `ims` 类型**来修复。

> v2.2.0 回归（issue #1）：代码先判断“已有 IMS APN”再剥离内置 APN 的 `ims`，而内置 `ctnet`/`ctlte` 本身就带 `ims`，于是模块误判“已有”并跳过插入，剥离后设备最终一条 IMS APN 都没有。v2.2.1 改为**先剥离、再补 46011/46003 两条 IMS APN**。

> ⚠️ 其他国家/运营商也可能出现“SIM PLMN 与 APN 匹配 PLMN 不一致”。如果刷入模块后短信仍不可用，请先导出日志（见“排障”），并附上 `adb shell su -c 'content query --uri content://telephony/siminfo --projection display_name:ehplmns:hplmns'` 的结果；如果 `hplmns` 为空或 `ehplmns` 列出多个 PLMN，请开 issue。

### 新西兰 Skinny（53005）在中国漫游

2026-11 实测（SCR-01 + Skinny 53005，漫游在 China Mobile 46000，LTE）：

- SCR-01 的 `/system/etc/apns-conf.xml` 只有一条 KDDI APN，漫游到 CMCC 时既没有数据 APN 也没有 IMS APN。v2.2 按 **SIM PLMN + 当前注册 PLMN** 从内置 APN 数据库补 `default` / `ims` APN（53005 → `internet.telecom.co.nz`，46000 → `cmnet` / `ims`）。
- 三星 IMS 里 Spark 的 profile 是 `support_roaming=false`、没有 `smsip`、`enc_algo=aes-cbc`；CMCC 的 P-CSCF 在 401 里给的是 `ealg=null`，会报 `common security mechanism not found`。v2.2 把 profile 改成 `support_roaming=true`、加 `smsip`、`ipver=ipv4v6`、`enc_algo=all` 后，REGISTER 直接 `200 OK`（`service=[smsip]`）。
- **不需要打开移动数据，也不需要在设置里打开“数据漫游”**：三星的 IMS PDN 是 always-on 的，`mobile_data=0`、`data_roaming=0`、Wi-Fi 关闭时 `rmnet1` 仍会自动建立并完成 IMS 注册，短信照常收。实测两条小红书验证码都在这个状态下通过 IMS（`ImsSmsImpl NEW_SMS`）收到。
- IMS APN 的流量只有注册/短信的几 KB，通常不计费；但各运营商策略不同，请以账单为准。

> 注意：profile 补丁写在 `/data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_0.xml`，重启后仍保留；如果换卡或清除 IMS 数据导致该缓存重建，重新执行一次模块脚本即可。

### APN 数据库

模块的 `payload/apns.tsv` 是从 [LineageOS `android_vendor_apn`](https://github.com/LineageOS/android_vendor_apn)（上游为 AOSP `apns-conf.xml`，Apache-2.0）生成的精简表（3980 条、约 230 KB），字段为：

```
numeric  mcc  mnc  carrier  apn  type  protocol  roaming_protocol  mvno_type  mvno_match_data
```

开机时模块会按 **SIM PLMN** 和 **当前注册 PLMN** 查询该表，只在对应 APN 类型不存在时插入 `default` 和 `ims` 两条，避免覆盖用户已有配置。查询时优先选 APN 名含 `internet` 的记录（例如 53005 会选 `internet.telecom.co.nz` 而不是旧的 WAP APN）。生成方法：从 LineageOS `android_vendor_apn` 取 `upstream/apns-conf.xml`（或 Debian `lineageos-apndb` 包里的 `apns-conf.xml`），按上述字段转成 TSV。

## 排障

1. **先导出日志**（root）：

   ```bash
   adb shell su -c 'sh /data/adb/modules/scr01_sms_enable/collect-logs.sh'
   adb pull /data/local/tmp/scr01_sms_diag_*.tar.gz
   ```

   压缩包内含：`boot-completed.log`（含轮转的 `.1`）、`getprop`、`telephony.registry`、APN 列表、`imsswitch`、IMS profile、`ip addr`、radio/main 日志尾部。注意其中可能包含 IMSI、ICCID、短信 PDU 等，**仅本地保存**。

2. **日志轮转**：`boot-completed.log` 超过 128 KiB 会轮转为 `.1`，最多保留两份；不会无限增长。

3. 常见检查点（都在 `boot-completed.log` 里）：
   - `SIM=... REG=... roaming=...`：SIM 与注册 PLMN 是否识别正确；
   - `APN ... already present` / `APN inserted from DB`：APN 是否命中；
   - `volte+smsip enabled`：IMS 开关；
   - `IMS profile changed; IMS service restarted` 或 `already patched`：profile 补丁；
   - `FAIL ...` / `WARN ...`：失败原因。

4. 换卡后如果 IMS 不注册，先确认 `mobile_data=0`、`data_roaming=0` 时 `ip addr show rmnet1` 是否有地址；没有地址说明该运营商没有 always-on IMS PDN，需要手动打开数据/漫游再试。

5. SCRoot 的 root 来得晚（约 2 分钟），重启后不要提前 `su`，否则会打断 root 注入。

## 源码结构

```
module/                 # 可直接安装的 KSU 模块
├── module.prop
├── boot-completed.sh   # 开机自动执行的主逻辑
├── collect-logs.sh     # 一键导出排障日志
├── uninstall.sh        # 回滚
└── payload/
    ├── scr01-dynamic-sms.apk   # 最小资源 overlay（config_sms_capable=true）
    ├── SmsRoleProbe.dex        # 强制注册 SMS 角色的辅助程序
    ├── apns.tsv                # 内置 APN 数据库（LineageOS/AOSP，Apache-2.0）
    ├── APNS-LICENSE.txt        # Apache-2.0 许可证全文
    └── APNS-NOTICE.txt         # APN 数据来源与版权说明
src/                    # payload 的源码
├── overlay/AndroidManifest.xml
├── overlay/res/values/bools.xml
└── SmsRoleProbe.java
tools/                  # 发布辅助脚本
├── make_apn_tsv.py     # 从 LineageOS/AOSP apns-conf.xml 生成 payload/apns.tsv
└── build-release.py    # 从 module/ 打包 release/scr01_sms_enable-v<版本>.zip
```

## 致谢

- [SCRoot](https://github.com/hackintoanetwork/SCRoot) —— 提供 SCR-01 的临时 root / KernelSU-Next 环境，本模块运行其上。
- [Fossify Messages](https://github.com/FossifyOrg/Messages) —— 开源短信应用，本模块默认配合它收发短信。
- [LineageOS `android_vendor_apn`](https://github.com/LineageOS/android_vendor_apn) —— 内置 APN 数据库的来源（上游为 AOSP `apns-conf.xml`，Apache-2.0）。
- [Samsung IMS Patcher](https://github.com/rezaf28/Samsung-IMS-Patcher) —— 参考了它关于 Samsung `imsservice` IMS profile 结构的说明（本模块不包含其 1.4 MB 私有 profile JSON，只在运行时按 PLMN 打小补丁）。
