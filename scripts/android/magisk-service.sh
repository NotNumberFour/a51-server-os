#!/system/bin/sh
# Magisk service.d: executado automaticamente a cada boot, como root, no namespace global.
# Espera o Android terminar de iniciar (rede e armazenamento prontos) e sobe o Debian.
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
sleep 10
/data/debian-server/start.sh
