# n8n no servidor A51

> 🇺🇸 English version: [N8N.md](N8N.md)

> **Situação: proposta não testada.** Os passos seguem a organização de serviços deste projeto e a documentação oficial do n8n
> (consultada em novembro de 2026, n8n 2.46.7), mas ninguém os executou do início ao fim em um celular. Se você testar, conte o que aconteceu.

O [n8n](https://n8n.io) é uma ferramenta de automação visual: você liga blocos ("chegou um formulário", "salve na planilha", "envie uma mensagem") e ele executa o fluxo para você.

Este guia trata do **n8n self-hosted** (a Community Edition gratuita, rodando no seu próprio celular, sem conta no n8n Cloud) e parte de um celular que já roda o servidor Debian nativo do [README principal](../README.pt-BR.md).

## Antes de começar

**Principais decisões deste guia**

1. **Sem Docker.** O kernel original não suporta, então o n8n é instalado por npm e supervisionado pelo runit.
2. **Primeiro só para você.** O n8n escuta apenas no próprio celular e você acessa por um túnel SSH. Publicar é opcional.
3. **Fique no n8n 2.x.** Veja [O problema do n8n 3.0](#o-problema-do-n8n-30).

**O que esperar**

| Item | No A51 | Efeito no n8n |
|---|---|---|
| CPU | ARM64, 8 núcleos | Compatível |
| RAM livre | Cerca de 3,2 GB em um servidor limpo | Sobra, mas diminui a cada app que você adiciona |
| Banco | Sem PostgreSQL (sem `SYSVIPC`) | Usa SQLite |
| Docker | Indisponível | Sem instalação em container e sem nó Code isolado |
| Load average | Cerca de 16 parado | Normal aqui: threads do TrustZone ficam em estado `D` sem usar CPU |

**Funciona bem para:** webhooks, avisos, chamadas de API, planilhas e tarefas agendadas com poucos dados.
**Funciona mal para:** arquivos grandes, vídeo, muitas execuções ao mesmo tempo ou modelos de IA rodando no celular.

Estima-se que o n8n use de 150 a 300 MB parado, e mais durante os fluxos. Se o `free -m` ficar abaixo de 500 MB disponíveis de forma constante, pare o n8n ou leve-o para outra máquina.

**Licença.** A licença MIT deste repositório cobre apenas este guia. O n8n tem a própria [Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md), que não é uma licença de código aberto aprovada pela OSI. Leia os termos, principalmente antes de oferecer o n8n a clientes.

## Segurança

O n8n guarda credenciais de outros serviços e pode executar ações no servidor. Tudo o que estiver no celular corre risco se ele for invadido.

- **O nó Code não tem como ser isolado aqui.** O modo seguro depende de um container separado. Sem Docker, sobra o modo interno, que a documentação do n8n chama de inseguro por natureza: quem edita um fluxo pode, em tese, ler o banco, a chave de criptografia e as credenciais. Este guia **bloqueia o nó Code**.
- **Dê acesso ao editor só a pessoas de total confiança.**
- **Use um usuário próprio.** O n8n roda como `n8n`, nunca como `root`. Isso protege os arquivos de outros apps, mas não é um isolamento completo: o kernel é antigo e não há containers.
- **Mantenha atualizado** dentro da série 2.x, principalmente se estiver acessível pela internet.

## Instalação

Reserve de 20 a 40 minutos. O `npm install` consome bastante memória, então pare tarefas pesadas antes.

Conecte ao celular: `ssh -i ~/.ssh/SUA_CHAVE server@IP_DO_CELULAR`

### 1. Verificar o celular e instalar as dependências

```sh
free -m                     # "available" deve estar acima de 1000 MB
ss -tln | grep 5678         # não deve mostrar nada
sudo apt-get update
sudo apt-get install -y --no-install-recommends xz-utils python3 make g++ cron sqlite3 curl
```

Instale o Node.js 24 (pule se `node --version` já mostrar v24 ou mais novo):

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

### 2. Criar o usuário e as pastas

```sh
sudo useradd --system --home-dir /srv/n8n --shell /usr/sbin/nologin n8n
sudo mkdir -p /srv/n8n/app /srv/n8n/data /srv/n8n/files /srv/n8n/backups /srv/n8n/env
sudo chown -R n8n:n8n /srv/n8n/app /srv/n8n/data /srv/n8n/files
sudo chmod 700 /srv/n8n/env /srv/n8n/backups
```

### 3. Instalar uma versão fixa do n8n

Os grupos `3003` e `3004` são obrigatórios: neste kernel, um processo sem eles não consegue usar a rede.

```sh
cd /srv/n8n/app
sudo setpriv --reuid=n8n --regid=n8n --groups=3003,3004 --inh-caps=-all \
  env HOME=/srv/n8n npm install --prefix /srv/n8n/app --cache /srv/n8n/app/.npm-cache --omit=dev n8n@2.46.7
```

### 4. Configurar

Ajuste o fuso horário, se precisar.

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

| Configuração | O que faz |
|---|---|
| `NODE_OPTIONS` | Limita a memória JavaScript a 512 MB |
| `N8N_ENCRYPTION_KEY` | Protege as credenciais salvas. **Sem ela, não dá para recuperá-las** |
| `N8N_LISTEN_ADDRESS` | Aceita conexões só do próprio celular |
| `N8N_CONCURRENCY_PRODUCTION_LIMIT` | Roda no máximo 2 fluxos ao mesmo tempo; os demais esperam na fila |
| `EXECUTIONS_TIMEOUT` | Interrompe fluxos com mais de 5 minutos |
| `EXECUTIONS_DATA_*` | Mantém 7 dias de histórico, até 2.000 execuções |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE` | Impede os fluxos de lerem as variáveis do servidor |
| `N8N_RESTRICT_FILE_ACCESS_TO` | Limita o acesso dos fluxos a `/srv/n8n/files` |
| `NODES_EXCLUDE` | Bloqueia os nós de comando, de código e o gatilho de arquivos locais |

### 5. Criar o serviço no runit

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

A primeira inicialização pode levar alguns minutos. Depois confira:

```sh
sudo sv status /etc/service-native/n8n
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5678/healthz   # esperado: 200
```

### 6. Abrir

No seu computador, abra um túnel e deixe rodando:

```sh
ssh -i ~/.ssh/SUA_CHAVE -L 5678:127.0.0.1:5678 server@IP_DO_CELULAR
```

Acesse **http://localhost:5678** e crie a conta de dono, com senha forte e exclusiva. Use `localhost`: o n8n só envia o cookie de login em HTTPS, e os navegadores abrem essa exceção para `localhost`.

## Publicar na internet (opcional)

Só é necessário para **receber webhooks** de serviços externos ou usar o editor fora de casa. Troque `n8n.exemplo.com` pelo seu domínio.

1. No Cloudflare Zero Trust, crie um **túnel novo** para o n8n e copie o token.
2. Aponte o hostname público `n8n.exemplo.com` para `http://localhost:5678`.
3. **Proteja o editor** com o Cloudflare Access, exigindo o seu login. Crie uma política Bypass só para `/webhook/*`.
4. Instale o `cloudflared` e crie o serviço:

```sh
curl -fsSL -o /tmp/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
sudo install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared
sudo sh -c 'umask 077; printf "TUNNEL_TOKEN=%s\n" "COLE_O_TOKEN_AQUI" > /srv/n8n/env/tunnel.env'
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

5. Acrescente ao fim de `/srv/n8n/env/n8n.env`. Use `N8N_WEBHOOK_URL`, porque o nome antigo, `WEBHOOK_URL`, foi descontinuado.

```sh
N8N_HOST=n8n.exemplo.com
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://n8n.exemplo.com/
N8N_WEBHOOK_URL=https://n8n.exemplo.com/
N8N_PROXY_HOPS=1
```

6. Reinicie o n8n e ligue o túnel:

```sh
sudo sv restart /etc/service-native/n8n
sudo ln -s /etc/sv/n8n-tunnel /etc/service-native/
```

7. De outra rede, confirme que `https://n8n.exemplo.com/` **pede o login da Cloudflare** antes de mostrar o n8n.

Ligue a autenticação em todo nó Webhook público. Qualquer pessoa que descubra o endereço consegue chamá-lo.

## Como usar

| Termo | O que é |
|---|---|
| **Workflow (fluxo)** | A automação inteira, desenhada como blocos ligados |
| **Node (nó)** | Uma etapa: ler planilha, enviar mensagem, filtrar dados |
| **Trigger (gatilho)** | O nó que dá início: horário, webhook, novo e-mail |
| **Credential** | Login salvo de outro serviço, guardado de forma criptografada |
| **Execution** | Cada vez que o fluxo rodou, com o histórico |

**Primeiro fluxo: meu site está no ar?**

1. Clique em **Create Workflow**.
2. Adicione um **Schedule Trigger**, por exemplo todo dia às 8h.
3. Adicione **HTTP Request** com o endereço a conferir.
4. Adicione **IF**: o status é 200?
5. Envie uma mensagem para você por e-mail ou Telegram em cada caminho.
6. Clique em **Execute Workflow** para testar. Depois publique ou ative o fluxo, senão ele não roda sozinho.

**Webhook de teste e de produção.** O nó Webhook mostra duas URLs. A de **teste** só funciona enquanto o editor está aguardando. A de **produção** só funciona com o fluxo publicado.

**Ideias:** enviar formulários de contato para um app de mensagens, mandar um resumo diário por e-mail, avisar quando um serviço cair, enviar lembretes de agendamento ou conferir se o backup de ontem existe.

**Dicas para este aparelho**

- Filtre logo no início, para as etapas seguintes lidarem com menos dados.
- Divida listas longas com **Loop Over Items**.
- Passe links de arquivos grandes em vez de baixá-los.
- Use o maior intervalo de agendamento que atenda.
- Configure um **Error Workflow** para avisar quando um fluxo falhar.

## Manutenção

```sh
sudo sv status  /etc/service-native/n8n
sudo sv restart /etc/service-native/n8n
sudo sv down    /etc/service-native/n8n
sudo tail -n 100 /var/log/n8n/current
```

### Backup

São necessários o banco e a chave de criptografia. O banco sem a chave perde todas as credenciais. O sistema base não inicia o `cron`, então crie o serviço primeiro:

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

Guarde uma cópia de `/srv/n8n/env/n8n.env` e dos backups **fora do celular**. **Nunca coloque esses arquivos no git.** Teste a restauração pelo menos uma vez.

Para restaurar:

```sh
sudo sv down /etc/service-native/n8n
gunzip -c /srv/n8n/backups/n8n-AAAA-MM-DD.sqlite.gz | sudo tee /srv/n8n/data/.n8n/database.sqlite > /dev/null
sudo chown n8n:n8n /srv/n8n/data/.n8n/database.sqlite
sudo rm -f /srv/n8n/data/.n8n/database.sqlite-wal /srv/n8n/data/.n8n/database.sqlite-shm
sudo sv up /etc/service-native/n8n
```

### Atualizar

Faça backup, leia as notas da versão e fique na série 2.x:

```sh
sudo /usr/local/sbin/n8n-backup
sudo sv down /etc/service-native/n8n
cd /srv/n8n/app
sudo setpriv --reuid=n8n --regid=n8n --groups=3003,3004 --inh-caps=-all \
  env HOME=/srv/n8n npm install --prefix /srv/n8n/app --cache /srv/n8n/app/.npm-cache --omit=dev n8n@VERSAO_2X
sudo sv up /etc/service-native/n8n
```

### O problema do n8n 3.0

A documentação do n8n informa que a instalação por npm será descontinuada a partir da 3.0 e que o modo interno de execução será removido. São os dois caminhos que este celular consegue usar. **Não vá para a 3.x sem revisar este guia.** Quando a 2.x parar de receber correções de segurança, leve o n8n para uma máquina com Docker, ou mantenha o celular fora da internet sabendo que ele vai ficar desatualizado.

## Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| Serviço reiniciando sem parar | Erro de configuração ou falta de memória | Veja o log e o `free -m` |
| Erros de rede | Faltam os grupos 3003/3004 | Confira o `setpriv` no arquivo `run` |
| Erro de cookie seguro no login | HTTP em endereço diferente de `localhost` | Use o túnel SSH ou HTTPS |
| Webhook responde 404 | URL de teste, ou fluxo não publicado | Use a URL de produção e publique |
| Webhook mostra `localhost` | Falta `N8N_WEBHOOK_URL` | Configure e reinicie |
| "Credentials could not be decrypted" | A chave de criptografia mudou | Restaure a chave original |
| Nó Code não aparece | Bloqueado de propósito | Leia [Segurança](#segurança) antes de liberar |
| Banco cresce demais | Histórico em excesso | Reduza `EXECUTIONS_DATA_MAX_AGE` |

## Remover

```sh
sudo sv down /etc/service-native/n8n /etc/service-native/n8n-tunnel
sudo rm -f /etc/service-native/n8n /etc/service-native/n8n-tunnel
sudo rm -rf /etc/sv/n8n /etc/sv/n8n-tunnel /etc/cron.d/n8n-backup /usr/local/sbin/n8n-backup /var/log/n8n
sudo userdel n8n
# Só depois de confirmar que tem os backups de que precisa:
sudo rm -rf /srv/n8n
```

Se tiver publicado, apague também o túnel e o hostname na Cloudflare.

## Referências

Documentação oficial do n8n: [instalação por npm](https://docs.n8n.io/hosting/installation/npm/), [task runners](https://docs.n8n.io/hosting/configuration/task-runners/), [webhook atrás de proxy](https://docs.n8n.io/hosting/configuration/configuration-examples/webhook-url/), [bloqueio de nós](https://docs.n8n.io/hosting/securing/blocking-nodes/), [variáveis de ambiente](https://docs.n8n.io/hosting/configuration/environment-variables/).
