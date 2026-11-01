# SCR01 SMS Enable

让三星 **SCR-01（Galaxy 5G Mobile Wi-Fi）纯数据 5G 路由器**支持收发短信（接收验证码、发送短信）的 KernelSU 模块。

A KernelSU module that enables SMS send/receive on the Samsung **SCR-01 (Galaxy 5G Mobile Wi-Fi)** data-only 5G router.

> [!WARNING]
> 本模块依赖临时 root（SCRoot）。临时 root 依赖内核漏洞，可能重启或崩溃设备。仅在你自己拥有的设备上使用。
> This module relies on temporary root (SCRoot). A kernel exploit may reboot or crash the device. Use only on a device you own.

## 功能 / Features

- ✅ 收短信：验证码等短信送达 Fossify Messages
- ✅ 发短信：从 Fossify Messages 发送短信
- ✅ 三网通用：中国移动 / 联通 / 电信 IMS 配置自适应
- ✅ 不写真实分区：bind-mount + 运行时 overlay，`uninstall.sh` 一键回滚
- ✅ 开机自动生效（无需手动操作）

- ✅ Receive SMS: verification codes etc. arrive in Fossify Messages
- ✅ Send SMS: send from Fossify Messages
- ✅ Carrier-agnostic: China Mobile / Unicom / Telecom IMS config auto-adapts
- ✅ No real partition is written: bind-mount + runtime overlay, one-click rollback via `uninstall.sh`
- ✅ Automatic on boot (no manual steps)

## 兼容性 / Compatibility

| 项目 Item | 支持 Supported |
| --- | --- |
| 设备 Device | Samsung SCR-01 / SM-H412J（Galaxy 5G Mobile Wi-Fi） |
| 固件 Firmware | `SCR01KDU1AVK2`（Android 11） |
| Root | [SCRoot](https://github.com/hackintoanetwork/SCRoot)（KernelSU-Next，临时 root） |
| 短信应用 SMS app | [Fossify Messages](https://github.com/FossifyOrg/Messages)（默认，可配置） |

## 前置条件 / Prerequisites

1. 已通过 [SCRoot](https://github.com/hackintoanetwork/SCRoot) 获取临时 root，并开启 **“开机自动 root（Run at boot）”**。
2. 已安装 [Fossify Messages](https://github.com/FossifyOrg/Messages)（F-Droid 可装）。

## 安装 / Installation

1. 从 [Releases](https://github.com/bestoko/SCR01_SMS_Enable/releases) 下载 `scr01_sms_enable-v2.0.zip`。
2. 安装模块（二选一）：

   - **方法一（推荐）：用 KernelSU 管理器直接安装 zip**（模块文件在 zip 根目录，管理器可直接识别）。
   - **方法二（手动）**：解压 zip，把里面的文件（`module.prop`、`boot-completed.sh`、`uninstall.sh`、`payload/`）放进 `/data/adb/modules/scr01_sms_enable/`：

     ```bash
     adb push <解压目录> /data/local/tmp/scr01_sms_enable/
     adb shell su -c 'cp -r /data/local/tmp/scr01_sms_enable /data/adb/modules/'
     ```

3. 重启设备。SCRoot 会在开机后几分钟自动重新 root，之后本模块自动生效。

## 用法 / Usage

- 重启后无需手动操作，模块自动完成配置（overlay + 角色 + IMS 通道）。
- 打开 **Fossify Messages** 即可收发短信。
- 回滚 / Rollback：

  ```bash
  adb shell su -c 'sh /data/adb/modules/scr01_sms_enable/uninstall.sh'
  ```

  或直接删除 `/data/adb/modules/scr01_sms_enable` 后重启。

## 工作原理 / How it works

SCR-01 自带的静态 product overlay 把系统资源 `config_sms_capable` 写死为 **false**，于是 Android 电话框架会：

1. 丢弃收到的短信（`InboundSmsHandler.mSmsReceiveDisabled=true`）；
2. 拒绝发送短信（`SMSDispatcher.mSmsSendDisabled=true`）；
3. 开机时不把 `android.app.role.SMS` 注册为“可用角色”，导致 Fossify 等短信应用启动时报“发生不明错误”（因为 `isRoleAvailable(SMS)` 为 false）。

本模块在运行时、不碰真实分区地修复以上三点：

1. **让框架看到 `config_sms_capable=true`**：把只含 `config_sms_capable=true` 的最小资源 overlay bind-mount 到可变的 `AccentColorCinnamon` 主题 overlay 上，再 `cmd overlay enable`。这会广播 `ACTION_OVERLAY_CHANGED`，使 `com.android.phone` 与 `permissioncontroller` 进程重启后重新读到 true。
2. **注册短信角色**：调用系统 RoleManager 的 `setRoleNamesFromController()`，把 `android.app.role.SMS` 强制加入可用角色列表（正常情况下因 `config_sms_capable=false` 而缺失）。这让 `isRoleAvailable(SMS)` 变为 true，也允许后续授权。
3. **授予角色 + 配置 IMS**：把 `android.app.role.SMS` 授予短信应用（自动授予 RECEIVE_SMS/SEND_SMS/READ_SMS），并新增 IMS APN、打开 volte/smsip，让短信走 IMS（本设备是纯数据路由器，无电路域短信）。

**为什么不能“开机前改 overlay”？** 在这台设备上 root 来得晚——SCRoot 是通过 Mali 漏洞在开机几分钟后才注入的，此时 zygote 早已预加载了 framework 资源；晚挂载的 overlay 改不动 zygote 的缓存视图。而“软重启 zygote”来重新加载也不行——它会搞挂 framework，因为 SCRoot 的临时凭据钩子是一次性的。所以采用上面的“主题 overlay + 进程重启”方案。

The SCR-01's static product overlay hard-codes `config_sms_capable=false`, so the telephony framework (1) discards inbound SMS, (2) rejects outbound SMS, and (3) does not register `android.app.role.SMS` as available at boot (so SMS apps like Fossify fail at startup with "unknown error"). This module fixes all three at runtime without touching real partitions:

1. **Make `config_sms_capable=true` visible** by bind-mounting a minimal resource overlay (containing only `config_sms_capable=true`) over the mutable `AccentColorCinnamon` theme overlay and running `cmd overlay enable`. The resulting `ACTION_OVERLAY_CHANGED` broadcast makes `com.android.phone` and `permissioncontroller` re-read the resource as `true` after restart.
2. **Register the SMS role** by calling the system RoleManager `setRoleNamesFromController()` to force `android.app.role.SMS` into the available-role list (normally absent due to `config_sms_capable=false`). This makes `isRoleAvailable(SMS)` return true and allows the grant.
3. **Grant the role + configure IMS** by granting `android.app.role.SMS` to the SMS app (which grants RECEIVE_SMS/SEND_SMS/READ_SMS), adding an IMS APN, and enabling volte/smsip so SMS travels over IMS (the device is data-only).

**Why not edit the overlay before boot?** Root arrives late on this device — SCRoot injects a few minutes after boot (via a Mali exploit), by which time zygote has already preloaded framework resources, so a late mount cannot change zygote's cached view. A "soft reboot" (zygote restart) to reload also fails — it breaks the framework because SCRoot's temporary credential hook is one-time. Hence the theme-overlay + process-restart approach.

## 源码结构 / Repository layout

```
module/                 # 可直接安装的 KSU 模块
├── module.prop
├── boot-completed.sh   # 开机自动执行的主逻辑
├── uninstall.sh        # 回滚
└── payload/
    ├── scr01-dynamic-sms.apk   # 最小资源 overlay（config_sms_capable=true）
    └── SmsRoleProbe.dex        # 强制注册 SMS 角色的辅助程序
src/                    # payload 的源码
├── overlay/AndroidManifest.xml
├── overlay/res/values/bools.xml
└── SmsRoleProbe.java
```

## 致谢 / Thanks

- [SCRoot](https://github.com/hackintoanetwork/SCRoot) —— 提供 SCR-01 的临时 root / KernelSU-Next 环境，本模块运行其上。
- [Fossify Messages](https://github.com/FossifyOrg/Messages) —— 开源短信应用，本模块默认配合它收发短信。
