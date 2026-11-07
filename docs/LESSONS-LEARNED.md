# Lessons learned: every wall we hit, and how we got past it

Device: SM-A515F, bootloader U8 (`A515FXXU8HWK1`), Android 13, kernel 4.14.113. Ordered by when each one showed up.

## 1. Magisk's patched AP causes `ODIN MODE (AVB Fail)`
**Symptom:** Odin says PASS, then the phone stops in Odin mode with `vbmeta: Error verifying vbmeta image ... (3)` and
`VERIFICATION_DISABLED bit is set`.

**What we tried, and failed:**
| vbmeta flashed | Result |
|---|---|
| Magisk's (flags=3, Samsung `SignerVer02` block kept but now invalid) | AVB Fail (3) |
| Unsigned, algorithm NONE, flags=3 (`avbtool make_vbmeta_image --flags 3`) | `vbmeta: no sign info` |
| Magisk boot with the AVB footer stripped + unsigned vbmeta | same |

**Cause:** this S-Boot **requires the stock Samsung-signed vbmeta** even with an unlocked bootloader, but it **tolerates a modified
boot.img**. **Fix:** flash only `boot.img` (patched) + the **stock** `vbmeta.img` (`tools/mk-odin-boot-tar.py`). Reference:
[Magisk #2272](https://github.com/topjohnwu/Magisk/issues/2272).

## 2. Odin rejects a renamed `.tar.md5`
Odin checks the file name embedded in the MD5 trailer. Renaming `BL_...tar.md5` to `1-BL.tar.md5` makes it report an invalid
binary. You can rename plain `.tar` files. Odin's file dialog may also filter to `*.tar.md5` only: paste the full path.

## 3. USB console: the Samsung gadget needs extra steps
A plain configfs gadget (`UDC` write) produced nothing. On this kernel:
- the DWC3 controller only starts **after the CCIC detects the cable** (~10 s into boot in Android), and an early `UDC` write fails with `-19`. **Retry for up to ~25 s.**
- Samsung adds `/sys/class/android_usb/android0/{functions,enable}`: write `acm,ncm` to `functions`, bind the `UDC`, then `enable=1`.
- The NCM interface is named **`ncm0`** (not `usb0`).

The ACM serial shows up in Windows as "USB Serial Device (COMx)", which makes it an excellent rescue console.

## 4. Services died instantly under runit (sshd alone survived)
**Cause:** with `console=ram` (from Samsung's cmdline), runit can't open `/dev/console`, so stage 2 and its children start with
**stdin/stdout/stderr closed**. The usual `exec 2>&1` at the top of a run script then fails, and the shell exits on the spot. sshd
survived only because its Debian service has a `log/` subservice that provides a pipe. **Fix:** in `/etc/runit/2`, do
`exec </dev/null >>/var/log/a51/services.log 2>&1` before `runsvdir`.

## 5. Kernel panic at exactly ~242 s after boot
`/proc/reset_reason` = `KPON`, `/proc/extra` = `PANIC: hung_task: blocked tasks`. The TrustZone threads (`tz_worker_thread`,
TEEgris) block forever waiting for Android's `tzdaemon`, and the Samsung kernel has **`hung_task_panic=1`** (120 s timeout, checked
twice). **Fix:** `echo 0 > /proc/sys/kernel/hung_task_panic` first thing in `/init`. The threads stay harmlessly in `D` state.
Samsung keeps the panic reason in `/proc/extra`, `/proc/auto_comment` and `/proc/last_kmsg`, so read those after any unexpected reboot.

## 6. Boot loop into recovery
`adb reboot recovery` makes Android write `boot-recovery` to the start of the **`misc`** partition (BCB). Stock recovery clears it
on exit; ours didn't, so every reboot went back to recovery. **Fix:** the test-mode `/init` zeroes the first 32 bytes of `misc` when
they say `boot-recovery`. A *reason-based* reboot from Linux (`reboot(2)` with `RESTART2 "recovery"`, see `a51-reboot recovery`)
doesn't touch `misc` and is one-shot.

## 7. The dead-man timer fired even after `switch_root`
We assumed that a background busybox shell left behind by the initramfs would stop being able to run applets once the initramfs
files were deleted. Debian's static busybox runs applets internally (standalone), so it kept working. We turned that into a
feature: a single timer started in `/init` covers every boot phase. It checks a health flag written by Debian on the data
partition, which stays visible to that process.

## 8. `sudo` didn't work in the chroot
Android mounts `/data` with `nosuid`. Bind-mount the rootfs onto itself and remount it with `suid,dev` (`scripts/android/start.sh`).

## 9. Boot-time scripts run with `umask 0`
Magisk `service.d` scripts start with umask 0, so `/run/sshd` was created world-writable and sshd refused to start. Set `umask 022`.

## 10. Locked accounts can't log in with a key when `UsePAM no`
A user created without a password gets `!` in `/etc/shadow`, and with `UsePAM no` sshd rejects it even with a valid key.
Use `usermod -p '*' user`.

## 11. Network permissions on an Android kernel
`CONFIG_ANDROID_PARANOID_NETWORK=y`: only root, or members of GID **3003** (`aid_inet`), may create sockets (3004 for raw/ping).
Add those groups to every service user, and to `_apt`.

## 12. The panel ignores brightness 0
Setting `/sys/class/backlight/panel/brightness` to 0 left the boot logo visible. `echo 4 > /sys/class/graphics/fb0/blank`
(POWERDOWN) really turns the panel off.

## 13. Windows tooling gotchas
- Git Bash rewrites `/sdcard/...` to `C:/Program Files/Git/sdcard/...` in `adb push`. Use PowerShell or `MSYS_NO_PATHCONV=1`.
- PowerShell 7 passes `-N '""'` to `ssh-keygen` as a literal two-character passphrase.
- Modern `scp` uses SFTP: install `openssh-sftp-server` on the phone.
- The Android file picker shows sizes cached by MediaStore, so a file that is still copying looks complete.

## 14. Download Mode only worked on one USB port
The other ports gave "Device Descriptor Request Failed". Try a rear (motherboard) USB 2.0 port without hubs.
