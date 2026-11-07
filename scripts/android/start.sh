#!/system/bin/sh
# A51 Server OS — sobe o Debian (chroot) e seus serviços.
# Roda como root no Android (Magisk). Idempotente: pode rodar várias vezes.
#
# Conceito: "chroot" faz um processo enxergar outra pasta como "/".
# O kernel continua o mesmo (Linux 4.14 da Samsung), mas todos os programas,
# bibliotecas e configurações vêm do Debian em $R.

R=/data/debian-server/rootfs
LOG=/data/debian-server/start.log
# No boot, o Magisk roda os scripts com umask 0 (tudo criado ficaria gravável por todos; o sshd recusa).
umask 022
exec >>"$LOG" 2>&1
echo "=== start $(date)"

# Impede o "deep sleep": com a tela apagada o Android suspende a CPU e os serviços param de responder.
# Um wakelock do kernel mantém a CPU ativa (a tela continua podendo apagar). Remover: echo a51-server > /sys/power/wake_unlock
grep -qw a51-server /sys/power/wake_lock 2>/dev/null || echo a51-server > /sys/power/wake_lock

# O Android monta /data com "nosuid" (sudo não funcionaria). Uma bind-mount da própria pasta
# com suid liberado vale só para o Debian, sem mudar o resto do /data.
if ! grep -qE " $R (ext4|f2fs) " /proc/mounts; then
  mount -o bind "$R" "$R" && mount -o remount,bind,suid,dev "$R"
fi

# Monta os sistemas de arquivos virtuais que todo Linux precisa.
mnt() { # mnt <tipo|bind> <origem> <destino> [opcoes]
  grep -q " $3 " /proc/mounts && return 0
  mkdir -p "$3"
  if [ "$1" = bind ]; then mount -o bind "$2" "$3"; else mount -t "$1" ${4:+-o "$4"} "$2" "$3"; fi
}
mnt proc  proc   "$R/proc"
mnt sysfs sysfs  "$R/sys"
mnt bind  /dev   "$R/dev"
mnt bind  /dev/pts "$R/dev/pts"
mnt tmpfs tmpfs  "$R/dev/shm" mode=1777
mnt tmpfs tmpfs  "$R/tmp"     mode=1777
mnt tmpfs tmpfs  "$R/run"     mode=0755
mkdir -p "$R/run/sshd" "$R/run/lock"
chown 0:0 "$R/run/sshd"; chmod 0755 "$R/run/sshd" "$R/run"

# Roda um comando dentro do Debian com ambiente limpo.
in_debian() {
  chroot "$R" /usr/bin/env -i HOME=/root TERM=xterm-256color LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"
}

# Serviços: SSH primeiro. Outros serviços entram em /etc/a51/services.d/*.sh
# Porta 22 = 0x0016; estado 0A = LISTEN (checa direto nas tabelas do kernel)
listening22() { grep -q ':0016 [0-9A-F:]* 0A' /proc/net/tcp /proc/net/tcp6 2>/dev/null; }
if [ -x "$R/usr/sbin/sshd" ] && ! listening22; then
  in_debian /usr/sbin/sshd || echo "sshd falhou"
fi
for s in "$R"/etc/a51/services.d/*.sh; do
  [ -f "$s" ] && in_debian /bin/sh "/etc/a51/services.d/$(basename "$s")" &
done
echo "=== ok"
