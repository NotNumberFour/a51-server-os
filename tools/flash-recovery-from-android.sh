#!/system/bin/sh
# Grava uma imagem na partição RECOVERY com checagens. Uso: su -c sh flash-recovery.sh <imagem> <sha256-esperado>
# Recusa se: a partição não for a recovery, o tamanho não bater, ou o hash da imagem não bater.
# Depois de gravar, lê a partição de volta e confere o hash.
set -e
IMG="$1"; EXP="$2"
P=$(readlink -f /dev/block/by-name/recovery)
[ "$P" = /dev/block/sda13 ] || { echo "ABORTA: recovery nao e sda13 ($P)"; exit 1; }
PSZ=$(blockdev --getsize64 "$P"); ISZ=$(stat -c %s "$IMG")
echo "particao $P: $PSZ bytes | imagem: $ISZ bytes"
[ "$PSZ" = "$ISZ" ] || { echo "ABORTA: tamanhos diferentes"; exit 1; }
GOT=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$GOT" = "$EXP" ] || { echo "ABORTA: hash da imagem $GOT != $EXP"; exit 1; }
echo "checagens ok, gravando..."
dd if="$IMG" of="$P" bs=1M conv=fsync 2>&1 | tail -1
sync
BACK=$(dd if="$P" bs=1M 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "lido de volta: $BACK"
[ "$BACK" = "$EXP" ] && echo "GRAVACAO VERIFICADA OK" || { echo "ERRO: leitura difere"; exit 2; }
