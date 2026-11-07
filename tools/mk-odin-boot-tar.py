#!/usr/bin/env python3
"""Build an Odin "AP" tar containing ONLY boot.img + the STOCK (Samsung-signed) vbmeta.img.

Why: on the Galaxy A51 (SM-A515F) with bootloader revision 8 (U8, Android 13), S-Boot rejects ANY
modified or unsigned vbmeta ("AVB Fail", "vbmeta: no sign info", "VERIFICATION_DISABLED bit is set"),
even with an unlocked bootloader. It does accept a modified boot.img (orange state) as long as vbmeta
is the original signed one. Magisk's patched AP tar replaces vbmeta, so it fails on this device.
See https://github.com/topjohnwu/Magisk/issues/2272 ("patch boot.img only").

Usage:
  pip install lz4
  python mk-odin-boot-tar.py --boot <boot.img | magisk_patched-*.tar> --ap <stock AP_*.tar.md5> --out out.tar

--boot accepts either a raw boot.img or Magisk's magisk_patched-*.tar (boot.img is taken from it).
Flash out.tar in Odin's AP slot with BL/CP/CSC EMPTY.
"""
import argparse, io, sys, tarfile

try:
    import lz4.frame
except ImportError:
    sys.exit("missing dependency: pip install lz4")


def read_member(tar_path, names):
    with tarfile.open(tar_path) as t:
        for n in names:
            try:
                data = t.extractfile(n).read()
            except KeyError:
                continue
            return lz4.frame.decompress(data) if n.endswith(".lz4") else data
    sys.exit(f"{tar_path}: none of {names} found")


ap = argparse.ArgumentParser()
ap.add_argument("--boot", required=True)
ap.add_argument("--ap", required=True, help="stock AP_*.tar.md5 of the SAME firmware version installed")
ap.add_argument("--out", required=True)
a = ap.parse_args()

boot = read_member(a.boot, ["boot.img", "boot.img.lz4"]) if a.boot.endswith(".tar") else open(a.boot, "rb").read()
if boot[:8] != b"ANDROID!":
    sys.exit("boot image does not start with ANDROID!")
vbmeta = read_member(a.ap, ["vbmeta.img.lz4", "vbmeta.img"])
if vbmeta[:4] != b"AVB0" or b"SignerVer02" not in vbmeta:
    sys.exit("vbmeta from AP is not a Samsung-signed AVB image")
flags = int.from_bytes(vbmeta[120:124], "big")
if flags != 0:
    sys.exit(f"vbmeta flags={flags}: expected the untouched stock image (flags=0)")

with tarfile.open(a.out, "w", format=tarfile.USTAR_FORMAT) as t:
    for name, data in (("boot.img", boot), ("vbmeta.img", vbmeta)):
        ti = tarfile.TarInfo(name); ti.size = len(data); ti.mode = 0o644
        t.addfile(ti, io.BytesIO(data))
print(f"ok: {a.out}  boot.img={len(boot)} B  vbmeta.img={len(vbmeta)} B (stock, signed)")
