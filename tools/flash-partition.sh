#!/bin/sh
# Grava uma imagem na partição BOOT ou RECOVERY a partir do Debian nativo, com checagens.
# Uso: sudo sh flash-boot-from-debian.sh <boot|recovery> <imagem> <sha256-esperado>
# Só aceita boot (sda12) e recovery (sda13); recusa se tamanho/hash/formato não baterem; confere lendo de volta.
set -e
NAME="$1"; IMG="$2"; EXP="$3"
case "$NAME" in boot) WANT=/dev/sda12 ;; recovery) WANT=/dev/sda13 ;; *) echo "ABORTA: so boot ou recovery"; exit 1 ;; esac
P=""
for u in /sys/class/block/*/uevent; do grep -qx "PARTNAME=$NAME" "$u" && P="/dev/$(sed -n 's/^DEVNAME=//p' "$u")"; done
[ "$P" = "$WANT" ] || { echo "ABORTA: $NAME nao e $WANT ($P)"; exit 1; }
PSZ=$(blockdev --getsize64 "$P"); ISZ=$(stat -c %s "$IMG")
echo "particao $NAME $P: $PSZ bytes | imagem: $ISZ bytes"
[ "$PSZ" = "$ISZ" ] || { echo "ABORTA: tamanhos diferentes"; exit 1; }
GOT=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$GOT" = "$EXP" ] || { echo "ABORTA: hash $GOT != $EXP"; exit 1; }
head -c 8 "$IMG" | grep -q 'ANDROID!' || { echo "ABORTA: nao e boot.img"; exit 1; }
echo "checagens ok, gravando $NAME..."
dd if="$IMG" of="$P" bs=1M conv=fsync status=none
sync
BACK=$(dd if="$P" bs=1M status=none | sha256sum | cut -d' ' -f1)
echo "lido de volta: $BACK"
[ "$BACK" = "$EXP" ] && echo "GRAVACAO $NAME VERIFICADA OK" || { echo "ERRO: leitura difere"; exit 2; }
