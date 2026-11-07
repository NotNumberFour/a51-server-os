#!/system/bin/sh
# Abre um shell bash dentro do Debian (para manutenção via adb).
# Uso no PC:  adb shell su -mm -c /data/debian-server/shell.sh [comando]
R=/data/debian-server/rootfs
/data/debian-server/start.sh
if [ $# -gt 0 ]; then
  exec chroot "$R" /usr/bin/env -i HOME=/root TERM=xterm-256color LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -lc "$*"
fi
exec chroot "$R" /usr/bin/env -i HOME=/root TERM=xterm-256color LANG=C.UTF-8 \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -l
