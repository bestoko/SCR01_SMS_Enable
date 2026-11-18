# v2.2.1 Release Notes

## 中文

修复 issue #1（中国电信 46011/46003 无法收发短信）：

- v2.2.0 在剥离内置 APN 的 `ims` 类型**之前**就判断“已有 IMS APN”，而中国电信内置的 `ctnet` / `ctlte` 本身就带 `ims`，模块因此跳过插入专用 IMS APN；随后剥离 `ims`，设备最终一条 IMS APN 都没有，IMS 无法注册。
- v2.2.1 改为**先剥离、再补 IMS APN**，并恢复 v2.1 的双 PLMN 处理：46011 SIM 同时补 **46011** 和 **46003** 两条 IMS APN。
- 中国电信的 `CTC Mobile` profile 本身已带 `smsip` / `support_roaming` / `enc_algo=all`，不需要额外改 profile。
- 升级：直接覆盖安装 v2.2.1 并重启；开机会自动补 APN。

## English

Fixes issue #1 (China Telecom 46011/46003 cannot send or receive SMS):

- v2.2.0 checked for an existing IMS APN **before** stripping the built-in `ims` APN types. China Telecom's built-in `ctnet` / `ctlte` APNs already carry `ims`, so the module skipped inserting a dedicated IMS APN; the following strip then left the device with no IMS APN at all, so IMS could not register.
- v2.2.1 **strips first, then ensures IMS APNs**, and restores the v2.1 dual-PLMN handling: a 46011 SIM gets both **46011** and **46003** IMS APNs.
- China Telecom's `CTC Mobile` profile already has `smsip` / `support_roaming` / `enc_algo=all`; no profile change is needed.
- Upgrade: install v2.2.1 over the old version and reboot; APNs are repaired on boot.
