#!/bin/bash
# Configuração inicial do Debian, executada UMA vez dentro do chroot.
set -e

# 1) Rede no Android: o kernel tem CONFIG_ANDROID_PARANOID_NETWORK=y.
#    Só processos do grupo 3003 (aid_inet) abrem sockets; 3004 permite sockets "raw" (ping).
#    root passa direto, mas o usuário _apt (usado pelo apt) e seus serviços precisam do grupo.
grep -q '^aid_inet:' /etc/group     || echo 'aid_inet:x:3003:' >> /etc/group
grep -q '^aid_net_raw:' /etc/group  || echo 'aid_net_raw:x:3004:' >> /etc/group
grep -q '^aid_net_admin:' /etc/group|| echo 'aid_net_admin:x:3005:' >> /etc/group
usermod -a -G aid_inet,aid_net_raw _apt 2>/dev/null || sed -i 's/^\(aid_inet:x:3003:.*\)$/\1_apt/' /etc/group

# 2) DNS e nome da máquina
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
echo a51-server > /etc/hostname
grep -q a51-server /etc/hosts || printf '127.0.0.1 localhost\n127.0.1.1 a51-server\n::1 localhost\n' > /etc/hosts

# 3) Pacotes base do servidor
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  openssh-server ca-certificates curl wget nano less htop procps iproute2 iputils-ping \
  sqlite3 tzdata locales sudo git
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# 4) Usuário de trabalho (sem senha; acesso só por chave SSH) + grupos de rede
id server >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,aid_inet,aid_net_raw server
# Senha "*" = sem senha, mas conta NAO travada. Com UsePAM no, o sshd recusa contas "!" (travadas) mesmo com chave valida.
usermod -p '*' server
echo 'server ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/server && chmod 440 /etc/sudoers.d/server
install -d -m 700 -o server -g server /home/server/.ssh
install -m 600 -o server -g server /tmp/authorized_keys /home/server/.ssh/authorized_keys

# 5) SSH: porta 22, só chave, sem login de root
mkdir -p /etc/ssh/sshd_config.d /run/sshd
cat > /etc/ssh/sshd_config.d/a51.conf <<'EOF'
Port 22
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
EOF
ssh-keygen -A
mkdir -p /etc/a51/services.d
echo "SETUP OK"
