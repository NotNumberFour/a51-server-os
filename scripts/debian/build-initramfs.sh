#!/bin/sh
# Gera os initramfs (test e prod) DENTRO do Debian nativo. Uso: sudo sh build-initramfs-native.sh /tmp/init
set -e
INIT="$1"
B=/tmp/a51-initramfs
for MODE in test prod; do
  rm -rf "$B"; mkdir -p "$B/bin" "$B/dev" "$B/proc" "$B/sys" "$B/mnt" "$B/newroot"
  cp /usr/bin/busybox "$B/bin/busybox"
  cp "$INIT" "$B/init"; chmod 755 "$B/init" "$B/bin/busybox"
  echo "$MODE" > "$B/a51-mode"
  mknod -m 600 "$B/dev/console" c 5 1
  mknod -m 666 "$B/dev/null" c 1 3
  (cd "$B" && find . | cpio -o -H newc --quiet | gzip -9) > "/tmp/initramfs-a51-$MODE.cpio.gz"
  chmod 644 "/tmp/initramfs-a51-$MODE.cpio.gz"
  ls -l "/tmp/initramfs-a51-$MODE.cpio.gz"
done
busybox sh -n "$INIT" && echo "sintaxe do init ok"
