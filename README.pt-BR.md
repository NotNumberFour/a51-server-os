# A51 Server OS: Debian nativo no Samsung Galaxy A51

Transforme um **Samsung Galaxy A51 (SM-A515F)** num **servidor Debian 13 ARM64** sem tela, que **inicia direto no Debian, sem
nenhum Android rodando**, usando o próprio kernel da Samsung. No fim do guia o celular oferece:

- runit como PID 1, com serviços supervisionados (sshd, Wi-Fi, DHCP, NTP) que reiniciam sozinhos se caírem
- **~3,2 GB de RAM livres** para os seus apps (com o Android sobravam ~1,3 GB)
- Wi-Fi sem Android (o driver Samsung `scsc_wlbt`, com o firmware copiado do seu próprio aparelho)
- um **console root de emergência pela serial USB**, além de uma rede USB opcional
- a tela desligada, a **carga da bateria limitada a 85%** e recuperação automática se o Wi-Fi cair

> 🇺🇸 English version: [README.md](README.md)

> **Testado em uma única configuração:** SM-A515F, bootloader **U8** (`A515FXXU8HWK1`, Android 13 / One UI 5.1).
> Outras revisões de bootloader ou variantes (A515U/W/FN, A51 5G) podem se comportar diferente. Leia antes [docs/LESSONS-LEARNED.md](docs/LESSONS-LEARNED.md) (em inglês).

## ⚠️ Leia antes de começar

| Risco | Consequência |
|---|---|
| Desbloquear o bootloader | **Apaga todos os dados** |
| Iniciar qualquer imagem modificada | **Queima o e-fuse do Knox para sempre** (Samsung Pay, Pasta Segura e alguns apps de banco param de funcionar, mesmo voltando ao firmware original) |
| Gravar na partição errada (`efs`, `sec_efs`, `param`, as LUNs de boot `sdb`/`sdc`, `uh`...) | Perda do IMEI ou **brick definitivo** |
| Celular 24 h na tomada | A bateria pode estufar: mantenha o limite de 85% e ventilação |

Tudo aqui é feito **por sua conta e risco**. Nenhum firmware ou blob proprietário é distribuído: você extrai os do seu aparelho.

## Como funciona

```
S-Boot (Samsung) ──> boot.img  =  kernel Samsung 4.14 (intacto) + DTB Samsung (intacto) + NOSSO initramfs
                                   │
                                   └─ /init (busybox): monta userdata ─> switch_root ─> /data/debian-server/rootfs
                                                                                          └─ runit (PID 1) ─> serviços
```

- **Só o ramdisk é trocado.** O kernel, o DTB e o bloco de assinatura Samsung/footer AVB ficam idênticos byte a byte.
- O bootloader exige o **`vbmeta` original assinado pela Samsung**, mas aceita um `boot.img` modificado (estado *orange*). É esse fato que torna tudo isto possível.
- O Debian fica em `/data/debian-server/rootfs`, uma pasta da partição userdata (f2fs) **fora da criptografia por arquivo do Android**, por isso o boot nativo consegue lê-la.
- As partições de sistema do Android continuam instaladas, mas **dormentes**, e dá para voltar a qualquer momento (veja [Voltar ao Android](#voltar-ao-android)).

## Requisitos

- Galaxy A51 SM-A515F (veja a nota acima), cabo USB, PC (Windows ou Linux)
- `adb`, **Odin** (Windows) ou Heimdall, Python 3 com `pip install lz4`
- O **firmware original da sua versão exata** (por exemplo com o [Bifrost](https://github.com/zacharee/Bifrost) ou o samloader)
- [Magisk](https://github.com/topjohnwu/Magisk) (usado uma vez, para ter root e preparar tudo pelo Android)
- Umas 2 horas, e um celular que você pode apagar

## Passo a passo

### 1. Desbloquear o bootloader
Configurações → Opções do desenvolvedor → **Desbloqueio OEM** ligado. Desligue o celular, segure **Volume + e Volume −** e conecte
o cabo USB. Na tela de aviso, **segure Volume +** e confirme. O celular apaga tudo e reinicia. Faça a configuração **com internet**
e confira se o "Desbloqueio OEM" ficou **cinza**. No Download Mode, o `KG STATE` não pode estar `Prenormal`.

### 2. Root com Magisk: o jeito que funciona no A51 U8
1. Copie o `AP_*.tar.md5` original para o celular e corrija-o no app Magisk ("Selecionar e corrigir um arquivo").
2. Puxe com `adb pull` o `magisk_patched-*.tar` gerado.
3. **Não grave esse tar direto**, porque o vbmeta modificado causa `AVB Fail / vbmeta: no sign info`. Monte um tar só com o boot corrigido e o vbmeta original:
   ```sh
   python tools/mk-odin-boot-tar.py --boot magisk_patched-XXXX.tar --ap AP_A515F....tar.md5 --out magisk-boot.tar
   ```
4. No Odin, coloque o `magisk-boot.tar` no campo **AP** e deixe os outros vazios. Quando o celular cair no Recovery, faça **Wipe data/factory reset** e depois Reboot.
5. Configure o celular, instale o app Magisk, aceite a "configuração adicional" e dê root ao *Shell* na aba Superusuário.

### 3. Backup das partições críticas (não pule)
```sh
for p in efs sec_efs cpefs boot recovery vbmeta vbmeta_samsung dtbo param up_param persistent steady keystorage; do
  adb exec-out su -c "dd if=/dev/block/by-name/$p" > $p.img       # só leitura
done
```
Guarde a **`efs`/`sec_efs`** (IMEI e calibração do rádio) num lugar seguro. Ela não pode ser recuperada de nenhum outro lugar.

### 4. Instalar o Debian (chroot, pelo Android)
```sh
# rootfs Debian 13 arm64 (por exemplo a camada oficial debian:trixie-slim) -> /data/debian-server/rootfs
adb push rootfs.tar.gz /data/local/tmp/
adb shell su -c 'mkdir -p /data/debian-server/rootfs && tar -xzpf /data/local/tmp/rootfs.tar.gz -C /data/debian-server/rootfs'
adb push scripts/android/start.sh scripts/android/shell.sh /data/debian-server/
adb push scripts/android/setup-inside.sh sua_chave.pub /data/debian-server/rootfs/tmp/   # renomeie a chave para authorized_keys
adb shell su -mm -c '/data/debian-server/shell.sh bash /tmp/setup-inside.sh'
```
O `setup-inside.sh` contorna a *paranoid network* do Android (grupos 3003/3004), instala o sshd e cria o usuário `server`
(login só por chave). Instale também os pacotes do boot nativo:
`apt install busybox-static runit chrony wpasupplicant dhcpcd-base cpio kmod openssh-sftp-server`.

### 5. Preparar o boot nativo
```sh
adb push scripts/android/prepare-native.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/prepare-native.sh'   # copia o firmware Wi-Fi, importa a rede salva e cria /efs
```
Copie o `rootfs-overlay/` para dentro do rootfs (estágios do runit, serviços, `a51-reboot`), crie `/etc/service-native/` com links
para `/etc/sv/{wpa,dhcp,ssh,chrony,usbcon,usbdhcp,bootlog}` e gere o initramfs **dentro do Debian**:
```sh
sh scripts/debian/build-initramfs.sh initramfs/init     # -> /tmp/initramfs-a51-{test,prod}.cpio.gz
```

### 6. Montar as imagens de boot
```sh
python tools/bootimg.py unpack boot.img boot-unpacked            # backup do seu boot com Magisk (o que funciona)
python tools/bootimg.py unpack recovery.img recovery-unpacked    # backup do recovery original
SAMSUNG_TAIL_FROM=recovery.img python tools/bootimg.py pack recovery-unpacked initramfs-a51-test.cpio.gz recovery-native-test.img
SAMSUNG_TAIL_FROM=boot.img     python tools/bootimg.py pack boot-unpacked     initramfs-a51-prod.cpio.gz boot-native-prod.img
```
O `bootimg.py` remonta as imagens originais **idênticas byte a byte**. Confira isso com os seus arquivos antes de confiar nele.

### 7. Testar com segurança pela partição recovery
O initramfs de **teste** tem um **temporizador de segurança**: se em 5 minutos o Debian não ficar saudável (SSH no ar e uma rede
alcançável), ele reinicia, e o boot normal traz o Android de volta. Ele também apaga o recado `boot-recovery` que o Android grava na `misc`.
```sh
adb push recovery-native-test.img /data/local/tmp/
adb shell su -c 'sh tools/flash-recovery-from-android.sh /data/local/tmp/recovery-native-test.img <sha256>'
adb reboot recovery
```
Procure o celular na sua rede (`ssh server@<ip>`) ou na porta COM da serial USB.

### 8. Tornar permanente
De dentro do Debian nativo, já rodando:
```sh
sudo sh tools/flash-partition.sh boot /tmp/boot-native-prod.img <sha256>
sudo a51-reboot
```
A partir daí todo boot vai para o Debian. O recovery fica com a imagem de teste, como reserva de manutenção.

## Uso no dia a dia

```sh
sudo sv status /etc/service-native/*          # serviços
sudo a51-reboot [poweroff|recovery|download]  # não há systemd
cat /var/log/a51/boot.log                     # log do boot (initramfs + runit); kernel em /var/log/a51/dmesg-*.txt
```
**Para adicionar o seu serviço:** crie `/etc/sv/meuapp/run` (`#!/bin/sh`, `exec 2>&1`, `exec chpst -u server /caminho/app`),
dê `chmod +x` e rode `ln -s /etc/sv/meuapp /etc/service-native/`. Processos sem root precisam dos **grupos 3003/3004** para abrir
sockets (o kernel Android tem `CONFIG_ANDROID_PARANOID_NETWORK`).

## Limitações (kernel original)

| Falta | Por quê | Alternativa |
|---|---|---|
| PostgreSQL | sem `CONFIG_SYSVIPC` (`shmget: Function not implemented`) | SQLite, ou recompilar o kernel |
| Docker / Podman | sem namespaces de usuário/IPC, veth, bridge | rodar os apps como serviços do runit (namespaces de montagem funcionam) |
| systemd | sem `CONFIG_FHANDLE` | runit (incluído) |
| Bluetooth, câmera, áudio, modem | pilhas proprietárias do Android | nenhuma |

As threads do TrustZone ficam em estado `D` para sempre (esperam o `tzdaemon` do Android), o que eleva o *load average* (~16) sem usar CPU.

## Voltar ao Android
Rode `sudo a51-reboot download` e, no Odin, grave um tar com o **`boot.img` do Magisk que você guardou + o vbmeta original**
(montado com o `mk-odin-boot-tar.py`). Para restaurar tudo de fábrica, grave BL+AP+CP+CSC do firmware original.

## Estrutura do repositório
| Caminho | O quê |
|---|---|
| `initramfs/init` | o `/init` em busybox: console USB, montagem da userdata, `switch_root`, temporizador (modo teste) |
| `rootfs-overlay/` | estágios 1/2/3 do runit, serviços, `a51-reboot` |
| `tools/bootimg.py` | desmonta/monta boot image Android v2 (inclui o recovery DTBO e a assinatura Samsung/footer AVB) |
| `tools/mk-odin-boot-tar.py` | tar do Odin (AP) = boot.img + vbmeta **original** |
| `tools/flash-*.sh` | gravadores de partição com checagem de tamanho/hash e conferência por leitura (só boot/recovery) |
| `scripts/android/` | fase chroot (start/shell/setup, `service.d` do Magisk), importação do firmware e do Wi-Fi |
| `docs/` | [lições aprendidas](docs/LESSONS-LEARNED.md), [auditoria de hardware e kernel](docs/HARDWARE-AUDIT.md) (em inglês) |

## Créditos
- Issue do Magisk [#2272](https://github.com/topjohnwu/Magisk/issues/2272): "vbmeta error no sign info (A51)", a dica de corrigir só o boot
- Port postmarketOS [samsung-a51](https://wiki.postmarketos.org/wiki/Samsung_Galaxy_A51_(samsung-a51)): lista do firmware Wi-Fi, notas sobre rede USB
- Debian, BusyBox, runit, Magisk, Bifrost

Licença: MIT (só os scripts e a documentação, veja [LICENSE](LICENSE)).
