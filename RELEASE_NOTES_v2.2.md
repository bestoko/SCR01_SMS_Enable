# v2.2 Release Notes

## 中文

相对于 v2.1：

- **内置 APN 数据库**（LineageOS/AOSP，Apache-2.0，约 3980 条）：按 SIM PLMN + 当前注册 PLMN 自动补 `default` / `ims` APN。SCR-01 出厂只有 KDDI APN，换卡或漫游不再需要手动加 APN。
- **修复 5/6 位 PLMN 解析**：旧逻辑会把 `53005` 算成 `mcc=53`、`46011` 算成 `mcc=46`。
- **新增 Samsung IMS profile 补丁**：`support_roaming=true`、加 `smsip`、`ipver=ipv4v6`、`enc_algo=all`。修复 Spark 53005 在 China Mobile 46000 漫游时 401 `common security mechanism not found`。
- **不强制打开移动数据/漫游数据**：三星的 IMS PDN 是 always-on 的，实测 `mobile_data=0`、`data_roaming=0` 时仍能注册 IMS 并收短信。
- **健壮性**：APN 插入幂等、profile 补丁重试与校验、仅在 profile 变化时重启 IMS、日志轮转（128 KiB + 一份 `.1` 备份）、新增 `collect-logs.sh` 一键导出排障包。
- **文档拆分**：中文 `README.md` / English `README_EN.md`，顶部可互相切换。

## English

Changes since v2.1:

- **Built-in APN database** (LineageOS/AOSP, Apache-2.0, ~3980 rows): inserts the missing `default` / `ims` APNs for both the SIM PLMN and the registered PLMN. The SCR-01 ships with a KDDI-only APN list, so no manual APN entry is needed for other carriers or roaming.
- **Fixed 5-/6-digit PLMN parsing**: `53005` was parsed as `mcc=53` and `46011` as `mcc=46`.
- **Samsung IMS profile patch**: sets `support_roaming=true`, adds `smsip`, `ipver=ipv4v6`, `enc_algo=all`. Fixes Spark 53005 roaming on China Mobile 46000 failing with 401 `common security mechanism not found`.
- **Does not force mobile data or roaming data on**: Samsung's IMS PDN is always-on; IMS registration and SMS still work with `mobile_data=0` and `data_roaming=0`.
- **Robustness**: idempotent APN insertion, profile patch retries and verification, IMS restart only when the profile changed, log rotation (128 KiB + one `.1` backup), and `collect-logs.sh` for one-shot diagnostics.
- **Docs split** into Chinese `README.md` and English `README_EN.md`, with a switcher at the top.
