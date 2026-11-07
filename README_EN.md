[中文](README.md) | **English**

# SCR01 SMS Enable

A KernelSU module that enables SMS send/receive on the Samsung **SCR-01 (Galaxy 5G Mobile Wi-Fi)** data-only 5G router.

> [!WARNING]
> This module relies on temporary root (SCRoot). A kernel exploit may reboot or crash the device. Use only on a device you own.

## Features

- ✅ Receive SMS: verification codes etc. arrive in Fossify Messages
- ✅ Send SMS: send from Fossify Messages
- ✅ Carrier-agnostic IMS configuration for China Mobile / Unicom / Telecom
- ✅ Works with a Skinny NZ (53005) SIM roaming on China Mobile (46000)
- ✅ Built-in APN database (~4000 rows from LineageOS/AOSP, Apache-2.0); inserts the missing `default` / `ims` APNs for both the SIM PLMN and the registered PLMN
- ✅ Patches the active Samsung IMS profile (`support_roaming` / `smsip` / `ipv4v6` / `enc_algo=all`)
- ✅ Never forces mobile data or roaming data on; Samsung's IMS PDN is always-on
- ✅ No real partition is written: bind-mount + runtime overlay, one-click rollback via `uninstall.sh`
- ✅ Automatic on boot (no manual steps)
- ✅ Log rotation (128 KiB + one backup) and a `collect-logs.sh` helper

## Compatibility

| Item | Supported |
| --- | --- |
| Device | Samsung SCR-01 / SM-H412J (Galaxy 5G Mobile Wi-Fi) |
| Firmware | `SCR01KDU1AVK2` (Android 11) |
| Root | [SCRoot](https://github.com/hackintoanetwork/SCRoot) (KernelSU-Next, temporary root) |
| SMS app | [Fossify Messages](https://github.com/FossifyOrg/Messages) (default, configurable) |
| Carriers | China Mobile / Unicom / Telecom; Skinny NZ (53005) roaming on China Mobile (46000). Most other carriers are covered by the built-in APN database; the IMS profile is patched generically for the active SIM |

## Prerequisites

1. Temporary root via [SCRoot](https://github.com/hackintoanetwork/SCRoot), with **"Run at boot"** enabled.
2. [Fossify Messages](https://github.com/FossifyOrg/Messages) installed (available on F-Droid).

## Installation

1. Download `scr01_sms_enable-v2.2.zip` from [Releases](https://github.com/bestoko/SCR01_SMS_Enable/releases).
2. Install the module (either way):

   - **Recommended: install the zip directly from the KernelSU manager** (module files are at the zip root).
   - **Manual**: extract the zip and copy `module.prop`, `boot-completed.sh`, `collect-logs.sh`, `uninstall.sh` and `payload/` into `/data/adb/modules/scr01_sms_enable/`:

     ```bash
     adb push <extracted-dir> /data/local/tmp/scr01_sms_enable/
     adb shell su -c 'cp -r /data/local/tmp/scr01_sms_enable /data/adb/modules/'
     ```

3. Reboot. SCRoot re-roots the device about 2 minutes after boot; the module then applies automatically. **Do not run `su` before root has finished, or you will interrupt the root injection.**

## Usage

- No manual steps after reboot: the module configures the overlay, SMS role, APNs and IMS profile automatically.
- Open **Fossify Messages** to send and receive SMS.
- Rollback:

  ```bash
  adb shell su -c 'sh /data/adb/modules/scr01_sms_enable/uninstall.sh'
  ```

  Or delete `/data/adb/modules/scr01_sms_enable` and reboot.

## How it works

The SCR-01's static product overlay hard-codes `config_sms_capable=false`, so the telephony framework:

1. discards inbound SMS (`InboundSmsHandler.mSmsReceiveDisabled=true`);
2. rejects outbound SMS (`SMSDispatcher.mSmsSendDisabled=true`);
3. does not register `android.app.role.SMS` as available at boot, so SMS apps such as Fossify fail at startup with "unknown error" (`isRoleAvailable(SMS)` is false).

The module fixes all three at runtime without touching real partitions:

1. **Make `config_sms_capable=true` visible** by bind-mounting a minimal resource overlay (containing only `config_sms_capable=true`) over the mutable `AccentColorCinnamon` theme overlay and running `cmd overlay enable`. The resulting `ACTION_OVERLAY_CHANGED` broadcast makes `com.android.phone` and `permissioncontroller` re-read the resource as `true` after restart.
2. **Register the SMS role** by calling the system RoleManager `setRoleNamesFromController()` to force `android.app.role.SMS` into the available-role list. This makes `isRoleAvailable(SMS)` return true and allows the grant.
3. **Grant the role + configure IMS**: grant `android.app.role.SMS` to the SMS app (which grants RECEIVE_SMS/SEND_SMS/READ_SMS), add APNs for the SIM PLMN and the registered PLMN, patch the Samsung IMS profile, and enable volte/smsip so SMS travels over IMS (the device is data-only).

**Why not edit the overlay before boot?** Root arrives late on this device — SCRoot injects a few minutes after boot (via a Mali exploit), by which time zygote has already preloaded framework resources, so a late mount cannot change zygote's cached view. A "soft reboot" (zygote restart) to reload also fails — it breaks the framework because SCRoot's temporary credential hook is one-time. Hence the theme-overlay + process-restart approach.

### China Telecom (46011) quirk

China Telecom has two historical PLMNs: the legacy CDMA **46003** and the LTE **46011**. On some SIMs the HPLMN is empty and the EHPLMN is `46011,46003`, so the APN engine matches on **46003**: the module's 46011 IMS APN is never selected, while the built-in `cmnet` APN (46003, type includes `ims`) grabs the IMS PDN without a P-CSCF → IMS never registers → SMS reports "no service" (S4). Since v2.1 the module creates **both 46011 and 46003 IMS APNs** for 46011 SIMs and **strips `ims` from built-in APNs**.

> ⚠️ A "SIM PLMN ≠ APN-matching PLMN" mismatch can also occur on other carriers with legacy PLMN codes. If SMS still fails, collect the logs (see Troubleshooting) and include the output of `adb shell su -c 'content query --uri content://telephony/siminfo --projection display_name:ehplmns:hplmns'`; if `hplmns` is empty or `ehplmns` lists multiple PLMNs, please open an issue.

### Skinny NZ (53005) roaming in China

Measured in 2026-11 (SCR-01 + Skinny 53005 roaming on China Mobile 46000, LTE):

- The SCR-01's `/system/etc/apns-conf.xml` contains only one KDDI APN: when roaming on CMCC there is neither a data APN nor an IMS APN. v2.2 looks up the built-in APN database for the **SIM PLMN and the registered PLMN** and inserts the missing `default` / `ims` APNs (53005 → `internet.telecom.co.nz`, 46000 → `cmnet` / `ims`).
- The Samsung IMS profile for Spark is `support_roaming=false`, has no `smsip`, and uses `enc_algo=aes-cbc`; CMCC's P-CSCF offers `ealg=null` in the 401 challenge, which fails with `common security mechanism not found`. v2.2 changes the profile to `support_roaming=true`, adds `smsip`, sets `ipver=ipv4v6` and `enc_algo=all`; REGISTER then returns `200 OK` with `service=[smsip]`.
- **Mobile data and the "data roaming" switch can stay OFF**: Samsung's IMS PDN is always-on; with `mobile_data=0`, `data_roaming=0` and Wi-Fi off, `rmnet1` still comes up and completes IMS registration, and SMS is still received. Two real Xiaohongshu verification codes were received over IMS (`ImsSmsImpl NEW_SMS`) in this state.
- IMS APN traffic is only a few KB for registration/SMS and is normally not billed; check your carrier's policy.

> Note: the profile patch lives in `/data/user_de/0/com.sec.imsservice/shared_prefs/imsprofile_0.xml` and survives reboots. If a SIM change or clearing IMS data rebuilds that cache, run the module script once more.

### APN database

`payload/apns.tsv` is a compact table (3980 rows, ~230 KB) generated from [LineageOS `android_vendor_apn`](https://github.com/LineageOS/android_vendor_apn) (upstream AOSP `apns-conf.xml`, Apache-2.0). Fields:

```
numeric  mcc  mnc  carrier  apn  type  protocol  roaming_protocol  mvno_type  mvno_match_data
```

On boot the module looks up the **SIM PLMN** and the **registered PLMN**, and inserts only the missing `default` and `ims` APNs, so existing user configuration is not overwritten. It prefers APNs whose name contains `internet` (for 53005 it picks `internet.telecom.co.nz` instead of the legacy WAP APN). To regenerate: take `upstream/apns-conf.xml` from LineageOS `android_vendor_apn` (or `apns-conf.xml` from the Debian `lineageos-apndb` package) and convert it to TSV with the fields above.

## Troubleshooting

1. **Collect logs first** (root):

   ```bash
   adb shell su -c 'sh /data/adb/modules/scr01_sms_enable/collect-logs.sh'
   adb pull /data/local/tmp/scr01_sms_diag_*.tar.gz
   ```

   The archive contains `boot-completed.log` (including the rotated `.1`), `getprop`, `telephony.registry`, the APN list, `imsswitch`, the IMS profile, `ip addr`, and the tail of the radio/main logs. It may contain IMSI, ICCID and SMS PDUs — **keep it local**.

2. **Log rotation**: `boot-completed.log` is rotated to `.1` once it exceeds 128 KiB; at most two files are kept.

3. Useful checkpoints in `boot-completed.log`:
   - `SIM=... REG=... roaming=...`: whether the SIM and registered PLMN were detected correctly;
   - `APN ... already present` / `APN inserted from DB`: whether the APN lookup hit;
   - `volte+smsip enabled`: IMS switches;
   - `IMS profile changed; IMS service restarted` or `already patched`: profile patch;
   - `FAIL ...` / `WARN ...`: failure reasons.

4. If IMS does not register after a SIM change, check whether `ip addr show rmnet1` has an address while `mobile_data=0` and `data_roaming=0`. If not, the carrier has no always-on IMS PDN; enable data/roaming manually and retry.

5. SCRoot's root arrives late (about 2 minutes); do not run `su` immediately after reboot or you will interrupt the root injection.

## Repository layout

```
module/                 # installable KSU module
├── module.prop
├── boot-completed.sh   # main boot logic
├── collect-logs.sh     # diagnostic collector
├── uninstall.sh        # rollback
└── payload/
    ├── scr01-dynamic-sms.apk   # minimal resource overlay (config_sms_capable=true)
    ├── SmsRoleProbe.dex        # helper that forces the SMS role into the list
    ├── apns.tsv                # built-in APN database (LineageOS/AOSP, Apache-2.0)
    ├── APNS-LICENSE.txt        # Apache-2.0 license text
    └── APNS-NOTICE.txt         # APN data attribution
src/                    # payload sources
├── overlay/AndroidManifest.xml
├── overlay/res/values/bools.xml
└── SmsRoleProbe.java
tools/                  # release helpers
├── make_apn_tsv.py     # generate payload/apns.tsv from LineageOS/AOSP apns-conf.xml
└── build-release.py    # build release/scr01_sms_enable-v<version>.zip from module/
```

## Thanks

- [SCRoot](https://github.com/hackintoanetwork/SCRoot) — temporary root / KernelSU-Next environment this module runs on.
- [Fossify Messages](https://github.com/FossifyOrg/Messages) — open-source SMS app used by default.
- [LineageOS `android_vendor_apn`](https://github.com/LineageOS/android_vendor_apn) — source of the built-in APN database (upstream AOSP `apns-conf.xml`, Apache-2.0).
- [Samsung IMS Patcher](https://github.com/rezaf28/Samsung-IMS-Patcher) — reference for the structure of Samsung `imsservice` IMS profiles (this module does not ship its 1.4 MB proprietary profile JSON; it only patches the active profile at runtime).
