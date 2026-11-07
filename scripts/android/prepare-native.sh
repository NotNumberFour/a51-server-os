#!/system/bin/sh
# N1 — prepara o Debian para rodar sem Android. Executar no Android como root: su -c sh n1-prepare.sh
set -e
R=/data/debian-server/rootfs
umask 022

echo "== firmware"
mkdir -p "$R/vendor/etc" "$R/vendor/firmware"
cp -a /vendor/etc/wifi "$R/vendor/etc/"
cp -a /vendor/firmware/. "$R/vendor/firmware/" 2>/dev/null || true
du -sh "$R/vendor/etc/wifi" "$R/vendor/firmware"

echo "== pontos de montagem"
mkdir -p "$R/efs" "$R/mnt/userdata"

echo "== rede Wi-Fi salva no Android -> wpa_supplicant (sem exibir senha)"
X=/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml
OUT="$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
mkdir -p "$R/etc/wpa_supplicant"
if [ -f "$X" ]; then
  {
    echo "ctrl_interface=/run/wpa_supplicant"
    echo "update_config=1"
    echo "country=BR"
    # Cada <Network>: SSID e PreSharedKey vêm entre &quot; ... &quot;
    awk '
      /<Network>/ {ssid=""; psk=""}
      /name="SSID"/ {s=$0; sub(/.*name="SSID">/,"",s); sub(/<\/string>.*/,"",s); gsub(/&quot;/,"\"",s); ssid=s}
      /name="PreSharedKey"/ {s=$0; sub(/.*name="PreSharedKey">/,"",s); sub(/<\/string>.*/,"",s); gsub(/&quot;/,"\"",s); psk=s}
      /<\/Network>/ { if (ssid != "" && psk != "") { print "network={"; print "  ssid=" ssid; print "  psk=" psk; print "}" ; n++ } }
      END { }
    ' "$X"
  } > "$OUT"
  chmod 600 "$OUT"
  echo "redes com senha encontradas: $(grep -c '^network=' "$OUT")"
else
  echo "WifiConfigStore.xml nao encontrado"
fi
echo "N1 OK"
