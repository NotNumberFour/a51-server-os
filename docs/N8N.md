# Running n8n on the A51 server

> 🇧🇷 Versão em português: [N8N.pt-BR.md](N8N.pt-BR.md)

> **Status: untested proposal.** These steps follow this project's service layout and the official n8n documentation
> (checked November 2026, n8n 2.46.7), but nobody has run them end to end on a phone yet. If you try it, please report what happened.

[n8n](https://n8n.io) is a visual automation tool: you connect blocks ("a form arrived", "save it to a sheet", "send a message") and it runs the flow for you.

This guide covers **self-hosted n8n** (the free Community Edition running on your own phone, with no n8n Cloud account) and assumes a phone already running the native Debian server from the [main README](../README.md).

## Before you start

**Key decisions in this guide**

1. **No Docker.** The stock kernel can't run it, so n8n is installed with npm and supervised by runit.
2. **Private first.** n8n listens only on the phone itself and you reach it through an SSH tunnel. Publishing it is optional.
3. **Stay on n8n 2.x.** See [The n8n 3.0 problem](#the-n8n-30-problem).

**What to expect**

| Item | On the A51 | Effect on n8n |
|---|---|---|
| CPU | ARM64, 8 cores | Supported |
| Free RAM | About 3.2 GB on a clean server | Plenty, but it shrinks with every app you add |
| Database | No PostgreSQL (no `SYSVIPC`) | Uses SQLite |
| Docker | Not available | No container install and no isolated Code node |
| Load average | Around 16 at idle | Normal here: TrustZone threads sit in state `D` without using CPU |

**Good fit:** webhooks, notifications, API calls, spreadsheets and scheduled jobs with small amounts of data.
**Poor fit:** large files, video, many simultaneous runs, or running AI models on the phone.

n8n usually needs an estimated 150 to 300 MB when idle, and more while flows run. If `free -m` stays below 500 MB available, stop n8n or move it to another machine.

**License.** The MIT license of this repository covers this guide only. n8n has its own [Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md), which is not an OSI open source license. Read it, especially before offering n8n to customers.

## Security

n8n stores credentials for other services and can act on your server. Anything else on the phone is at risk if it is compromised.

- **The Code node can't be isolated here.** The safe runner mode needs a sidecar container. Without Docker only internal mode is left, which the n8n docs describe as insecure by design: anyone who can edit a workflow could potentially read the database, encryption key and credentials. This guide **blocks the Code node**.
- **Only give editor access to people you fully trust.**
- **Use a dedicated user.** n8n runs as `n8n`, never as `root`. This protects other apps' files, but it is not full isolation: the kernel is old and there are no containers.
- **Keep it updated** within 2.x, particularly if it is reachable from the internet.

## Install

Allow 20 to 40 minutes. `npm install` uses a lot of memory, so stop heavy jobs first.

Connect to the phone: `ssh -i ~/.ssh/YOUR_KEY server@PHONE_IP`

### 1. Check the phone and install dependencies

```sh
free -m                     # "available" should be above 1000 MB
ss -tln | grep 5678         # should print nothing
sudo apt-get update
sudo apt-get install -y --no-install-recommends xz-utils python3 make g++ cron sqlite3 curl
```

Install Node.js 24 (skip this if `node --version` already shows v24 or newer):

```sh
cd /tmp
curl -fsSLO https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt
FILE=$(grep -o 'node-v24[^ ]*-linux-arm64\.tar\.xz' SHASUMS256.txt)
curl -fsSLO "https://nodejs.org/dist/latest-v24.x/$FILE"
grep " $FILE\$" SHASUMS256.txt | sha256sum -c -
sudo mkdir -p /opt/node
sudo tar -xJf "$FILE" -C /opt/node --strip-components=1
sudo ln -sf /opt/node/bin/node /opt/node/bin/npm /opt/node/bin/npx /usr/local/bin/
node --version
```

### 2. Create the user and folders

```sh
sudo useradd --system --home-dir /srv/n8n --shell /usr/sbin/nologin n8n
sudo mkdir -p /srv/n8n/app /srv/n8n/data /srv/n8n/files /srv/n8n/backups /srv/n8n/env
sudo chown -R n8n:n8n /srv/n8n/app /srv/n8n/data /srv/n8n/files
sudo chmod 700 /srv/n8n/env /srv/n8n/backups
```

### 3. Install a pinned n8n version

Groups `3003` and `3004` are required: on this kernel a process without them can't use the network.

```sh
cd /srv/n8n/app
sudo setpriv --reuid=n8n --regid=n8n --groups=3003,3004 --inh-caps=-all \
  env HOME=/srv/n8n npm install --prefix /srv/n8n/app --cache /srv/n8n/app/.npm-cache --omit=dev n8n@2.46.7
```

### 4. Configure it

Adjust the time zone if needed.

```sh
KEY=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
sudo sh -c "umask 077; cat > /srv/n8n/env/n8n.env" <<EOF
HOME=/srv/n8n
NODE_ENV=production
NODE_OPTIONS=--max-old-space-size=512
TZ=America/Sao_Paulo
GENERIC_TIMEZONE=America/Sao_Paulo

N8N_USER_FOLDER=/srv/n8n/data
N8N_ENCRYPTION_KEY=$KEY
N8N_LISTEN_ADDRESS=127.0.0.1
N8N_PORT=5678

DB_TYPE=sqlite
DB_SQLITE_POOL_SIZE=2

N8N_CONCURRENCY_PRODUCTION_LIMIT=2
EXECUTIONS_TIMEOUT=300
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168
EXECUTIONS_DATA_PRUNE_MAX_COUNT=2000

N8N_DIAGNOSTICS_ENABLED=false
N8N_BLOCK_ENV_ACCESS_IN_NODE=true
N8N_RESTRICT_FILE_ACCESS_TO=/srv/n8n/files
NODES_EXCLUDE='["n8n-nodes-base.executeCommand","n8n-nodes-base.localFileTrigger","n8n-nodes-base.code"]'
EOF
unset KEY
```

| Setting | What it does |
|---|---|
| `NODE_OPTIONS` | Caps JavaScript memory at 512 MB |
| `N8N_ENCRYPTION_KEY` | Protects saved credentials. **Without it they can't be recovered** |
| `N8N_LISTEN_ADDRESS` | Accepts connections from the phone only |
| `N8N_CONCURRENCY_PRODUCTION_LIMIT` | Runs at most 2 flows at once; others wait in a queue |
| `EXECUTIONS_TIMEOUT` | Stops flows that run longer than 5 minutes |
| `EXECUTIONS_DATA_*` | Keeps 7 days of history, up to 2,000 runs |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE` | Stops flows from reading server environment variables |
| `N8N_RESTRICT_FILE_ACCESS_TO` | Limits flow file access to `/srv/n8n/files` |
| `NODES_EXCLUDE` | Blocks the command, Code and local file trigger nodes |

### 5. Create the runit service

```sh
sudo mkdir -p /etc/sv/n8n/log /var/log/n8n
sudo tee /etc/sv/n8n/run > /dev/null <<'EOF'
#!/bin/sh
exec 2>&1
set -a; . /srv/n8n/env/n8n.env; set +a
cd /srv/n8n/app
umask 0077
exec setpriv --reuid=n8n --regid=n8n --groups=3003,3004 --inh-caps=-all -- \
  /usr/local/bin/node /srv/n8n/app/node_modules/n8n/bin/n8n start
EOF
sudo tee /etc/sv/n8n/log/run > /dev/null <<'EOF'
#!/bin/sh
exec svlogd -tt /var/log/n8n
EOF
sudo chmod +x /etc/sv/n8n/run /etc/sv/n8n/log/run
sudo ln -s /etc/sv/n8n /etc/service-native/
```

The first start can take a few minutes. Then check it:

```sh
sudo sv status /etc/service-native/n8n
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5678/healthz   # expected: 200
```

### 6. Open it

On your computer, open a tunnel and leave it running:

```sh
ssh -i ~/.ssh/YOUR_KEY -L 5678:127.0.0.1:5678 server@PHONE_IP
```

Go to **http://localhost:5678** and create the owner account with a strong, unique password. Use `localhost`: n8n only sends its login cookie over HTTPS, and browsers make an exception for `localhost`.

## Publish it on the internet (optional)

You only need this to **receive webhooks** from outside services, or to use the editor away from home. Replace `n8n.example.com` with your own domain.

1. In Cloudflare Zero Trust, create a **new tunnel** for n8n and copy its token.
2. Point the public hostname `n8n.example.com` to `http://localhost:5678`.
3. **Protect the editor** with Cloudflare Access, requiring your own login. Add a Bypass policy only for `/webhook/*`.
4. Install `cloudflared` and create its service:

```sh
curl -fsSL -o /tmp/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
sudo install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared
sudo sh -c 'umask 077; printf "TUNNEL_TOKEN=%s\n" "PASTE_TOKEN_HERE" > /srv/n8n/env/tunnel.env'
sudo mkdir -p /etc/sv/n8n-tunnel
sudo tee /etc/sv/n8n-tunnel/run > /dev/null <<'EOF'
#!/bin/sh
exec 2>&1
set -a; . /srv/n8n/env/tunnel.env; set +a
exec setpriv --reuid=n8n --regid=n8n --groups=3003,3004 --inh-caps=-all -- \
  /usr/local/bin/cloudflared tunnel --no-autoupdate run
EOF
sudo chmod +x /etc/sv/n8n-tunnel/run
```

5. Add this to the end of `/srv/n8n/env/n8n.env`. Use `N8N_WEBHOOK_URL`, because the older `WEBHOOK_URL` is deprecated.

```sh
N8N_HOST=n8n.example.com
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://n8n.example.com/
N8N_WEBHOOK_URL=https://n8n.example.com/
N8N_PROXY_HOPS=1
```

6. Restart n8n and start the tunnel:

```sh
sudo sv restart /etc/service-native/n8n
sudo ln -s /etc/sv/n8n-tunnel /etc/service-native/
```

7. From another network, confirm that `https://n8n.example.com/` **asks for the Cloudflare login** before showing n8n.

Turn on authentication in every public Webhook node. Anyone who finds the address can call it.

## Using n8n

| Term | Meaning |
|---|---|
| **Workflow** | The whole automation, drawn as connected blocks |
| **Node** | One step: read a sheet, send a message, filter data |
| **Trigger** | The node that starts a flow: a schedule, webhook or new email |
| **Credential** | A saved, encrypted login for another service |
| **Execution** | One run of a flow, with its history |

**A first flow: is my site up?**

1. Click **Create Workflow**.
2. Add a **Schedule Trigger**, for example every day at 8:00.
3. Add **HTTP Request** with the address to check.
4. Add **IF**: is the status 200?
5. Send yourself a message by email or Telegram on each branch.
6. Click **Execute Workflow** to test it. Then publish or activate the flow, or it won't run by itself.

**Test and production webhooks.** The Webhook node shows two URLs. The **test** URL works only while the editor is listening. The **production** URL works only once the flow is published.

**Ideas:** send contact forms to a chat app, email a daily summary, get alerted when a service goes down, send appointment reminders, or check that yesterday's backup exists.

**Tips for this hardware**

- Filter early, so later steps handle less data.
- Split long lists with **Loop Over Items**.
- Pass links to large files instead of downloading them.
- Use the longest schedule interval that works for you.
- Set an **Error Workflow** to tell you when a flow fails.

## Maintenance

```sh
sudo sv status  /etc/service-native/n8n
sudo sv restart /etc/service-native/n8n
sudo sv down    /etc/service-native/n8n
sudo tail -n 100 /var/log/n8n/current
```

### Backups

You need both the database and the encryption key. A database without its key loses all credentials. The base system doesn't start `cron`, so create its service first:

```sh
sudo mkdir -p /etc/sv/cron
printf '#!/bin/sh\nexec /usr/sbin/cron -f\n' | sudo tee /etc/sv/cron/run > /dev/null
sudo chmod +x /etc/sv/cron/run
sudo ln -sfn /etc/sv/cron /etc/service-native/cron

sudo tee /usr/local/sbin/n8n-backup > /dev/null <<'EOF'
#!/bin/sh
set -e
SOURCE=/srv/n8n/data/.n8n/database.sqlite
TARGET=/srv/n8n/backups/n8n-$(date +%F).sqlite
umask 077
sqlite3 "$SOURCE" ".backup '$TARGET'"
gzip -f "$TARGET"
find /srv/n8n/backups -name 'n8n-*.sqlite.gz' -mtime +14 -delete
EOF
sudo chmod 700 /usr/local/sbin/n8n-backup
echo '45 3 * * * root /usr/local/sbin/n8n-backup' | sudo tee /etc/cron.d/n8n-backup > /dev/null
```

Keep a copy of `/srv/n8n/env/n8n.env` and the backups **off the phone**. **Never commit them to git.** Test a restore at least once.

To restore:

```sh
sudo sv down /etc/service-native/n8n
gunzip -c /srv/n8n/backups/n8n-YYYY-MM-DD.sqlite.gz | sudo tee /srv/n8n/data/.n8n/database.sqlite > /dev/null
sudo chown n8n:n8n /srv/n8n/data/.n8n/database.sqlite
sudo rm -f /srv/n8n/data/.n8n/database.sqlite-wal /srv/n8n/data/.n8n/database.sqlite-shm
sudo sv up /etc/service-native/n8n
```

### Updating

Back up first, read the release notes, and stay on 2.x:

```sh
sudo /usr/local/sbin/n8n-backup
sudo sv down /etc/service-native/n8n
cd /srv/n8n/app
sudo setpriv --reuid=n8n --regid=n8n --groups=3003,3004 --inh-caps=-all \
  env HOME=/srv/n8n npm install --prefix /srv/n8n/app --cache /srv/n8n/app/.npm-cache --omit=dev n8n@VERSION_2X
sudo sv up /etc/service-native/n8n
```

### The n8n 3.0 problem

The n8n docs state that npm installs are deprecated from 3.0 and that internal runner mode will be removed. Those are the two paths this phone can use. **Don't move to 3.x without reviewing this guide.** When 2.x stops getting security fixes, move n8n to a machine with Docker, or keep the phone off the internet and accept that it will fall behind.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Service keeps restarting | Bad configuration or no memory | Check the log and `free -m` |
| Network errors | Groups 3003/3004 are missing | Check `setpriv` in the `run` file |
| Secure cookie error at login | HTTP on an address other than `localhost` | Use the SSH tunnel or HTTPS |
| Webhook returns 404 | Test URL, or flow not published | Use the production URL and publish |
| Webhook shows `localhost` | `N8N_WEBHOOK_URL` is missing | Set it and restart |
| "Credentials could not be decrypted" | Encryption key changed | Restore the original key |
| Code node is missing | Blocked on purpose | Read [Security](#security) before unblocking it |
| Database keeps growing | Too much history | Lower `EXECUTIONS_DATA_MAX_AGE` |

## Uninstall

```sh
sudo sv down /etc/service-native/n8n /etc/service-native/n8n-tunnel
sudo rm -f /etc/service-native/n8n /etc/service-native/n8n-tunnel
sudo rm -rf /etc/sv/n8n /etc/sv/n8n-tunnel /etc/cron.d/n8n-backup /usr/local/sbin/n8n-backup /var/log/n8n
sudo userdel n8n
# Only after confirming you have any backup you need:
sudo rm -rf /srv/n8n
```

If you published it, also delete the tunnel and hostname in Cloudflare.

## References

Official n8n docs: [npm install](https://docs.n8n.io/hosting/installation/npm/), [task runners](https://docs.n8n.io/hosting/configuration/task-runners/), [webhook URL behind a proxy](https://docs.n8n.io/hosting/configuration/configuration-examples/webhook-url/), [blocking nodes](https://docs.n8n.io/hosting/securing/blocking-nodes/), [environment variables](https://docs.n8n.io/hosting/configuration/environment-variables/).
