# Guia de Instalação de Nós — Rede Lunes

Este guia explica como instalar e operar um nó da rede Lunes (full node ou
validador) da forma **mais leve possível**, usando o instalador automatizado
[`scripts/lunes-node.sh`](../scripts/lunes-node.sh).

O instalador foi pensado para ser amigável a novos validadores e membros da
rede: por padrão ele **baixa um binário pré-compilado** (sem compilar nada),
cria um **usuário de sistema dedicado sem privilégios**, configura um
**serviço systemd endurecido** e conecta automaticamente aos bootnodes.

---

## 1. Requisitos

| Item | Mínimo (full node) | Recomendado (validador) |
|------|--------------------|-------------------------|
| SO | Linux (Debian/Ubuntu, RHEL/Fedora, Arch) | Ubuntu 22.04 LTS |
| Arquitetura | x86_64 | x86_64 |
| RAM | 2 GB | 8 GB |
| Disco | 40 GB SSD (nó podado) | 100 GB+ SSD NVMe |
| Rede | conexão estável | IP estável, porta 30333 aberta |
| Acesso | `sudo` | `sudo` |

As únicas dependências de runtime são `curl` e `jq`, instaladas
automaticamente. **Não é necessário instalar a toolchain Rust** no modo padrão.

---

## 2. Instalação rápida

Baixe o script e execute:

```bash
# Baixar o instalador
curl -fsSL https://raw.githubusercontent.com/Guigolinus/lunes-nightly/master/scripts/lunes-node.sh -o lunes-node.sh
chmod +x lunes-node.sh

# Full node na mainnet (padrão)
./lunes-node.sh install

# Ou como validador, com nome público
./lunes-node.sh install --validator --name meu-validador
```

O instalador mostra um resumo e pede confirmação. Para modo automático
(sem perguntas), acrescente `-y`.

---

## 3. Tipos de nó

### Full node / membro da rede
Sincroniza a blockchain e serve RPC local. Ideal para carteiras, exploradores,
dApps ou quem só quer acompanhar a rede.

```bash
./lunes-node.sh install
```

### Validador
Participa do consenso (produção de blocos e finalização GRANDPA). Requer
registro on-chain das chaves de sessão (ver seção 5).

```bash
./lunes-node.sh install --validator --name meu-validador
```

### Nó de arquivo (histórico completo)
Mantém todo o estado histórico — útil para exploradores/indexadores. Consome
muito mais disco.

```bash
./lunes-node.sh install --pruning archive
```

---

## 4. Opções de instalação

| Opção | Descrição | Padrão |
|-------|-----------|--------|
| `--network <mainnet\|testnet>` | Rede alvo | `mainnet` |
| `--validator` | Instala como validador | — |
| `--full` | Instala como full node | (padrão) |
| `--name <nome>` | Nome público (telemetria) | hostname |
| `--pruning <N\|archive>` | Blocos mantidos; `archive` = tudo | `1000` |
| `--rpc-external` | Expõe RPC/WS externamente | desligado |
| `--binary-url <URL>` | Baixa o binário desta URL | — |
| `--build-from-source` | Compila do fonte (pesado) | — |
| `-y, --yes` | Não perguntar confirmações | — |

> **Segurança:** mantenha o RPC restrito a localhost em validadores. Só use
> `--rpc-external` em full nodes de propósito específico e atrás de firewall.

---

## 5. Chaves de sessão (validadores)

Após o nó **sincronizar com a rede**, gere e insira as chaves de sessão:

```bash
./lunes-node.sh keys
```

O comando chama `author_rotateKeys` no RPC local e imprime a chave pública.
Em seguida, registre-a on-chain enviando o extrínseco:

```
session.setKeys(<chave_gerada>, 0x00)
```

a partir da sua conta de validador (via
[Polkadot-JS Apps](https://polkadot.js.org/apps) ou linha de comando).

---

## 6. Operação do dia a dia

```bash
./lunes-node.sh status     # estado do serviço + saúde do nó (peers, sync)
./lunes-node.sh logs       # logs em tempo real
```

Ou diretamente via systemd:

```bash
sudo systemctl status lunes-node
sudo systemctl restart lunes-node
sudo journalctl -u lunes-node -f
```

### Onde ficam os arquivos

| Caminho | Conteúdo |
|---------|----------|
| `/usr/local/bin/lunes-node` | Binário do nó |
| `/etc/systemd/system/lunes-node.service` | Definição do serviço |
| `/var/lib/lunes/data` | Banco de dados da blockchain |
| `/var/lib/lunes/specs` | Chain spec da rede |

O serviço roda com o usuário de sistema `lunes` (sem shell, sem root) e usa
sandbox do systemd (`ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`
etc.), reduzindo a superfície de ataque.

---

## 7. Atualização

Para atualizar o binário para uma nova versão, basta rodar o `install`
novamente — ele substitui o binário e reinicia o serviço, preservando os dados:

```bash
./lunes-node.sh install --network mainnet -y
```

---

## 8. Desinstalação

```bash
# Remove serviço e binário, PRESERVANDO os dados
./lunes-node.sh uninstall

# Remove tudo, inclusive dados e o usuário de sistema
./lunes-node.sh uninstall --purge
```

---

## 9. Portas utilizadas

| Porta | Protocolo | Uso |
|-------|-----------|-----|
| `30333` | TCP | P2P (libp2p) — **abra no firewall** |
| `9933` | TCP | RPC HTTP (localhost por padrão) |
| `9944` | TCP | RPC WebSocket (localhost por padrão) |
| `9615` | TCP | Métricas Prometheus (localhost) |

Para validadores, garanta que a porta **30333** esteja acessível para bons
peers, mas **não** exponha 9933/9944 publicamente.

---

## 10. Distribuição do binário (para mantenedores)

O modo padrão do instalador baixa o binário do **último GitHub Release** do
repositório. Para que isso funcione, publique um Release contendo o binário
`lunes-node` (o repositório já traz um binário pronto em `artefacts/lunes-node`).

Enquanto não houver Release publicado, os usuários podem:

- **Fornecer uma URL direta:** `./lunes-node.sh install --binary-url <URL>`
- **Compilar do código-fonte:** `./lunes-node.sh install --build-from-source`
  (instala a toolchain Rust e compila — leva vários minutos)

### Como publicar um Release (sugestão)

```bash
# via GitHub CLI, a partir da raiz do repositório
gh release create v4.0.0 artefacts/lunes-node \
  --title "Lunes Node v4.0.0" \
  --notes "Binário oficial do nó Lunes (x86_64-linux)."
```

Recomenda-se nomear o asset incluindo a arquitetura (ex.:
`lunes-node-x86_64-linux`) para que o instalador selecione o binário correto
automaticamente em múltiplas plataformas.

---

## 11. Solução de problemas

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| `Nenhum GitHub Release publicado` | Sem release com o binário | Use `--binary-url` ou `--build-from-source`, ou publique um Release |
| Serviço não fica ativo | Erro de inicialização | `./lunes-node.sh logs` para ver o motivo |
| `0 peers` por muito tempo | Porta 30333 bloqueada | Abra a porta 30333/TCP no firewall |
| `keys` retorna erro | RPC exposto externamente | Gere as chaves com o RPC em localhost |
| `--version` falha | Falta de bibliotecas do sistema | Instale `libssl`/`ca-certificates` |

---

Dúvidas? Comunidade Lunes Labs DAO no
[Discord](https://discord.gg/AFwdEKB4fW).
