# Monitoring dashboard / Painel de monitoramento

A modern, read-only web dashboard for the A51 server: usage gauges, per-core CPU (A53/A73), the **real** temperatures
(CPU clusters, GPU, ISP), battery (level, charging, temperature, 85% cap), Wi-Fi traffic and the state of every runit service.

> 🇧🇷 Painel web moderno e somente leitura: uso, CPU por núcleo, temperaturas reais, bateria, rede Wi-Fi e o estado de todos os
> serviços do runit. Consome ~55 MB de RAM e ~1% de CPU. Instruções abaixo (comandos iguais para os dois idiomas).

## How it works

| Piece | What it does | Cost (measured) |
|---|---|---|
| `dashboard/index.html` | a single page (HTML/CSS/JS, no external libraries, works offline on the LAN) | — |
| `busybox httpd` (`/etc/sv/dash`) | serves the page on port 80 and drops privileges to user `server` | ~0.5 MB |
| `dash-sensores` (`/etc/sv/dash-sensores`) | every 5 s writes `sensores.json`: temperatures and battery read from `/sys`, service states from `sv status` | negligible |
| Glances (`/etc/sv/glances`) | CPU/RAM/swap/disk/network API on port 61208 (CORS enabled) | ~55 MB, ~1% CPU |

Why not use Glances' own UI or psutil for sensors? On this phone psutil reports the Samsung battery as 0% and does not see
the CPU thermal zones (`BIG`, `LITTLE`, `G3D`, `ISP`), so the page reads them from `sensores.json` instead. Glances' process
list is disabled: on the Exynos 9611 it cost ~25% of a core.

## Install (inside the native Debian)

```sh
# 1) Glances with its prebuilt web UI (Debian 13's package ships the UI unbuilt)
sudo apt install python3-venv
sudo python3 -m venv /opt/glances
sudo /opt/glances/bin/pip install "glances[web]"

# 2) page, configs and services (from this repo)
sudo mkdir -p /srv/a51-dash /etc/glances
sudo install -m 644 dashboard/index.html /srv/a51-dash/index.html
sudo install -m 644 rootfs-overlay/etc/glances/glances.conf /etc/glances/
sudo install -m 644 rootfs-overlay/etc/a51-dash-httpd.conf /etc/
for s in glances dash dash-sensores; do
  sudo mkdir -p /etc/sv/$s && sudo install -m 755 rootfs-overlay/etc/sv/$s/run /etc/sv/$s/run
  sudo ln -sfn /etc/sv/$s /etc/service-native/$s
done
```

Open `http://<phone-ip>/` from any device on your network.

**Optional:** to show a "Site" status tile, set `SITE_URL` at the top of `/etc/sv/dash-sensores/run` (e.g. `http://127.0.0.1:3000/`)
and `sudo sv restart /etc/service-native/dash-sensores`.

**Service names:** known system services get friendly names (edit the `SVC` map in `index.html`). Everything else is listed under
"Aplicações" using the runit folder name.

## Security
- Read-only: the page cannot start, stop or change anything.
- No authentication: the dashboard and Glances are meant for your **LAN only**. Don't publish ports 80/61208 to the internet
  (a Cloudflare Tunnel or router port-forward for these ports would expose system metrics).
- Screenshots don't show IP addresses, but check before sharing.
