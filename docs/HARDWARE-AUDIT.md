# Hardware and kernel audit: Galaxy A51 SM-A515F (U8)

Read-only findings collected over ADB before any modification. Firmware `A515FXXU8HWK1`, Android 13.

## Hardware
| Item | Value |
|---|---|
| SoC | Exynos 9611 (`universal9611`): 4× Cortex-A73 @ 2.31 GHz + 4× Cortex-A53 @ 1.74 GHz, ARMv8.0 (NEON, AES, SHA1/2, CRC32) |
| RAM | 4 GB physical, **3.49 GiB** visible to the kernel |
| Storage | UFS. `sda` = main LUN (~119 GiB on the 128 GB model), `sdb`/`sdc` = 4 MiB boot LUNs (bootloader, **never touch**) |
| GPU | Mali-G72 MP3 (Bifrost). The userspace driver is Android-only, so no GPU use in Debian |
| Wi-Fi/BT | Samsung S.LSI SCSC (`scsc_wlbt`, firmware `mx140*`). Wi-Fi works natively; Bluetooth is a proprietary stack, no BlueZ |
| PMIC / charger | S2MPU09 (+RTC) / SM5713 charger and fuel gauge |

## Partitions (sda, by name)
`efs`(sda1) `sec_efs`(2) `param`(3) `up_param`(4) `bota`(5) `keystorage`(6) `steady`(7) `uh`(8) `uhcfg`(9) `dtbo`(10) `blcmd`(11)
**`boot`(12, 59 MiB)** **`recovery`(13, 68 MiB)** `radio`(14) ... `misc`(18) ... `vbmeta`(22) `vbmeta_samsung`(23) `metadata`(24)
**`super`(25, 6.4 GiB, dynamic)** `prism`(26) `optics`(27) `cache`(28) `omr`(29) `spu`(30) `nad_fw`(31) **`userdata`(32, ~111 GiB, f2fs)**.

Not A/B. No dm-default-key (metadata encryption) on userdata. FBE (`fileencryption=ice`) only covers Android's own directories.

## Boot chain
BootROM → BL1/EPBL/BL2 (UFS boot LUNs) → EL3/TEEgris → S-Boot → Samsung hypervisor (`uh`) → **AVB check** (vbmeta +
vbmeta_samsung, must be Samsung-signed) → `boot` (kernel + ramdisk + DTB, header v2) + DTBO entry → `/init`.
The bootloader cmdline contains `root=/dev/ram0 console=ram firmware_class.path=/vendor/firmware androidboot.*`.

## Stock kernel 4.14.113: what matters for a server
| Feature | Status |
|---|---|
| `/proc/config.gz` | available (`IKCONFIG_PROC=y`), which made the audit precise |
| Namespaces | mnt, uts, pid, net, cgroup ✅ · **user ✗ · ipc ✗** |
| Cgroups | cpu, cpuacct, cpuset, memory, freezer, BPF ✅ · pids ✗ · devices ✗ · blkio ✗ |
| Filesystems | ext4, f2fs, **overlayfs**, fuse, vfat, tmpfs, devtmpfs, loop ✅ · btrfs/xfs/nfs ✗ |
| Netfilter | iptables v4 (filter/nat/MASQUERADE/conntrack), ip6tables filter ✅ · **nf_tables ✗** (use iptables-legacy) |
| Container networking | **veth ✗ · bridge ✗** · TUN ✅ |
| `SYSVIPC` | ✗ (PostgreSQL fails) |
| `FHANDLE` | ✗ (no systemd) |
| `ANDROID_PARANOID_NETWORK` | ✅ (sockets need GID 3003) |
| USB gadget | configfs ACM/NCM/RNDIS + Samsung `android_usb` hooks |
| USB host / Ethernet | DWC3 dual-role, xHCI, RTL8152/8153 and AX88179 drivers built in |
| Samsung security | DEFEX (**disabled when the bootloader is unlocked**), PROCA, FIVE, UH/RKP, SELinux (no policy is loaded in native mode) |
| `hung_task_panic` | **1**: must be set to 0 in native mode (see the lessons, item 5) |

## Mainline status (2026-11)
There is **no Exynos 9611 DTS or clock driver** in mainline Linux (the Exynos 850, including the A21s, is supported).
postmarketOS had a downstream-4.14 port (`samsung-a51`, now archived). Rebuilding Samsung's kernel source with
`SYSVIPC`, namespaces, veth and bridge is the realistic path to PostgreSQL and Docker on this phone.
