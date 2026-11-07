"""Desmonta / remonta boot.img Android header v2 (o formato do Galaxy A51).

Formato (system/tools/mkbootimg/include/bootimg/bootimg.h do AOSP):
  header v0..v2: magic, kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr,
  tags_addr, page_size, header_version, os_version, name[16], cmdline[512], id[32], extra_cmdline[1024],
  (v1) recovery_dtbo_size, recovery_dtbo_offset, header_size, (v2) dtb_size, dtb_addr.
  Depois do header (1 página): kernel, ramdisk, second, recovery_dtbo, dtb — cada um alinhado à página.
A Samsung acrescenta, depois das imagens, "SEANDROIDENFORCE" + assinatura "SignerVer02" e um AVB footer
no fim da partição. O bootloader deste A51 tolera boot modificado (estado orange) com vbmeta original.

Uso:
  python bootimg.py unpack <boot.img> <pasta>
  python bootimg.py pack <pasta> <novo-ramdisk> <saida.img> [tamanho_particao]
"""
import json
import os
import struct
import sys

HDR = "<8s10I16s512s32s1024sIQIIQ"


def unpack(path, out):
    b = open(path, "rb").read()
    f = struct.unpack_from(HDR, b, 0)
    (magic, ks, ka, rs, ra, ss, sa, ta, ps, hv, osv, name, cmd, idb, xcmd, rdtbo_s, rdtbo_o, hsz, dtbs, dtba) = f
    assert magic == b"ANDROID!" and hv == 2, (magic, hv)
    pages = lambda n: (n + ps - 1) // ps
    off = ps
    parts = {}
    for nm, sz in (("kernel", ks), ("ramdisk", rs), ("second", ss), ("recovery_dtbo", rdtbo_s), ("dtb", dtbs)):
        parts[nm] = (off, sz)
        off += pages(sz) * ps
    os.makedirs(out, exist_ok=True)
    for nm, (o, sz) in parts.items():
        if sz:
            open(os.path.join(out, nm), "wb").write(b[o:o + sz])
    meta = dict(kernel_addr=ka, ramdisk_addr=ra, second_addr=sa, tags_addr=ta, page_size=ps, recovery_dtbo_offset=rdtbo_o,
                os_version=osv, name=name.rstrip(b"\0").decode(), cmdline=cmd.rstrip(b"\0").decode(),
                extra_cmdline=xcmd.rstrip(b"\0").decode(), header_size=hsz, dtb_addr=dtba,
                sizes={k: v[1] for k, v in parts.items()}, images_end=off,
                partition_size=len(b))
    tail = b[off:off + 64]
    meta["after_images"] = tail[:16].decode("latin1")
    json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=2)
    print(json.dumps(meta, indent=2))


def pack(src, ramdisk_path, outp, part_size=None):
    m = json.load(open(os.path.join(src, "meta.json")))
    ps = m["page_size"]
    k = open(os.path.join(src, "kernel"), "rb").read()
    r = open(ramdisk_path, "rb").read()
    d = open(os.path.join(src, "dtb"), "rb").read()
    rp = os.path.join(src, "recovery_dtbo")          # só existe na imagem de recovery
    rd = open(rp, "rb").read() if os.path.exists(rp) else b""
    pages = lambda n: (n + ps - 1) // ps
    rd_off = (1 + pages(len(k)) + pages(len(r))) * ps if rd else 0
    # id = SHA-1 igual ao mkbootimg: cada imagem seguida do seu tamanho (uint32 LE); v1 recovery_dtbo, v2 dtb
    import hashlib
    h = hashlib.sha1()
    for blob in (k, r, b"", rd, d):
        h.update(blob)
        h.update(struct.pack("<I", len(blob)))
    hdr = struct.pack(HDR, b"ANDROID!", len(k), m["kernel_addr"], len(r), m["ramdisk_addr"], 0, m["second_addr"],
                      m["tags_addr"], ps, 2, m["os_version"], m["name"].encode(), m["cmdline"].encode(),
                      h.digest(), m["extra_cmdline"].encode(), len(rd), rd_off, m["header_size"], len(d), m["dtb_addr"])
    pad = lambda x: x + b"\0" * ((ps - len(x) % ps) % ps)
    img = pad(hdr) + pad(k) + pad(r) + (pad(rd) if rd else b"") + pad(d)
    size = int(part_size or m["partition_size"])
    tail_src = os.environ.get("SAMSUNG_TAIL_FROM")
    if tail_src:
        img = add_samsung_tail(img, tail_src, m["images_end"], size)
    assert len(img) <= size, "imagem maior que a particao"
    img += b"\0" * (size - len(img))
    open(outp, "wb").write(img)
    print("ok:", outp, len(img), "bytes; kernel", len(k), "ramdisk", len(r), "dtb", len(d))


def add_samsung_tail(img, orig_path, orig_images_end, size):
    """Copia do boot original (que o bootloader aceitou) o bloco Samsung (SEANDROIDENFORCE + SignerVer02)
    e o vbmeta embutido + AVB footer, como o Magisk faz. O footer é reescrito com os novos offsets.
    O vbmeta embutido continua o original (assinado); o hash dele não bate com o boot novo, o mesmo caso
    do boot do Magisk, aceito com bootloader desbloqueado."""
    o = open(orig_path, "rb").read()
    foot = o[-64:]
    assert foot[:4] == b"AVBf"
    maj, mnr, orig_size, vb_off, vb_size = struct.unpack(">IIQQQ", foot[4:36])
    samsung = o[orig_images_end:orig_size]            # SEANDROIDENFORCE + assinatura
    assert samsung.startswith(b"SEANDROIDENFORCE")
    vbmeta = o[vb_off:vb_off + vb_size]
    gap = vb_off - orig_size                          # alinhamento usado pelo avbtool (4 KiB)
    body = img + samsung
    new_orig_size = len(body)
    new_vb_off = (new_orig_size + 4095) // 4096 * 4096
    assert new_vb_off + vb_size + 64 <= size, "sem espaco para o footer"
    out = bytearray(size)
    out[:len(body)] = body
    out[new_vb_off:new_vb_off + vb_size] = vbmeta
    nf = foot[:12] + struct.pack(">QQQ", new_orig_size, new_vb_off, vb_size) + foot[36:]
    out[-64:] = nf
    print(f"samsung tail: {len(samsung)} B, vbmeta {vb_size} B @ {new_vb_off} (antes {vb_off}, gap {gap})")
    return bytes(out)


if __name__ == "__main__":
    if sys.argv[1] == "unpack":
        unpack(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "pack":
        pack(sys.argv[2], sys.argv[3], sys.argv[4], *(sys.argv[5:6]))
