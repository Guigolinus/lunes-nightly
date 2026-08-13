#!/usr/bin/env bash
#
# lunes-node.sh — Instalador leve e gerenciador de nós da rede Lunes
# =================================================================
#
# Um único script para instalar, configurar e operar um nó Lunes
# (full node ou validador) da forma mais leve possível: por padrão baixa
# um binário pré-compilado (sem compilar nada) e configura um serviço
# systemd com usuário dedicado e sem privilégios de root.
#
# Uso rápido:
#   ./lunes-node.sh install                 # instala full node na mainnet
#   ./lunes-node.sh install --validator     # instala como validador
#   ./lunes-node.sh install --network testnet
#   ./lunes-node.sh keys                     # gera/insere chaves de sessão (validador)
#   ./lunes-node.sh status                   # estado do serviço
#   ./lunes-node.sh logs                     # acompanha os logs
#   ./lunes-node.sh uninstall                # remove tudo (preserva dados por padrão)
#
# Rode `./lunes-node.sh --help` para ver todas as opções.
#
set -euo pipefail

# ------------------------------------------------------------------
# Constantes da rede Lunes
# ------------------------------------------------------------------
readonly LUNES_REPO="Guigolinus/lunes-nightly"
readonly RAW_BASE="https://raw.githubusercontent.com/${LUNES_REPO}/master"
readonly BIN_NAME="lunes-node"
readonly INSTALL_BIN="/usr/local/bin/${BIN_NAME}"
readonly SERVICE_NAME="lunes-node"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly LUNES_USER="lunes"
readonly LUNES_HOME="/var/lib/lunes"
readonly DATA_DIR="${LUNES_HOME}/data"
readonly SPEC_DIR="${LUNES_HOME}/specs"

# Chain specs por rede (arquivos versionados no repositório)
readonly MAINNET_SPEC_URL="${RAW_BASE}/lunes-staging-raw.json"
readonly TESTNET_SPEC_URL="${RAW_BASE}/testnet/lunes-testnet-staging-raw.json"

# Portas padrão (mesmo esquema usado pela rede)
readonly P2P_PORT=30333
readonly RPC_PORT=9933
readonly WS_PORT=9944
readonly PROM_PORT=9615

# ------------------------------------------------------------------
# Cores e helpers de log
# ------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET='\033[0m'; C_BOLD='\033[1m'
    C_RED='\033[0;31m'; C_GRN='\033[0;32m'; C_YLW='\033[0;33m'; C_BLU='\033[0;34m'
else
    C_RESET=''; C_BOLD=''; C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''
fi

info()  { printf "${C_BLU}==>${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GRN}  ✓${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YLW}  ! ${C_RESET}%s\n" "$*" >&2; }
err()   { printf "${C_RED}  ✗ %s${C_RESET}\n" "$*" >&2; }
die()   { err "$*"; exit 1; }
step()  { printf "\n${C_BOLD}%s${C_RESET}\n" "$*"; }

# ------------------------------------------------------------------
# Defaults configuráveis por flags/ambiente
# ------------------------------------------------------------------
NETWORK="mainnet"          # mainnet | testnet
ROLE="full"                # full | validator
NODE_NAME=""               # nome público do nó (telemetria)
PRUNING="1000"             # nº de blocos mantidos; "archive" p/ histórico completo
RPC_EXTERNAL="false"       # expor RPC/WS externamente (padrão: só localhost)
BINARY_URL=""              # URL direta para o binário (sobrepõe releases)
BUILD_FROM_SOURCE="false"  # compilar do código-fonte (pesado; fallback)
ASSUME_YES="false"         # modo não-interativo
KEEP_DATA="true"           # no uninstall, preservar dados

# ------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif have sudo; then
        SUDO="sudo"
    else
        die "Este comando precisa de privilégios de root e 'sudo' não está disponível."
    fi
}

confirm() {
    # confirm "pergunta" -> retorna 0 se sim
    [ "$ASSUME_YES" = "true" ] && return 0
    local reply
    printf "${C_YLW}?${C_RESET} %s [s/N] " "$1"
    read -r reply || true
    case "$reply" in [sSyY]*) return 0 ;; *) return 1 ;; esac
}

detect_arch() {
    local m
    m="$(uname -m)"
    case "$m" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) echo "$m" ;;
    esac
}

require_linux() {
    [ "$(uname -s)" = "Linux" ] || die "Este instalador suporta apenas Linux."
}

spec_url_for() {
    case "$NETWORK" in
        mainnet) echo "$MAINNET_SPEC_URL" ;;
        testnet) echo "$TESTNET_SPEC_URL" ;;
        *) die "Rede inválida: $NETWORK (use 'mainnet' ou 'testnet')" ;;
    esac
}

spec_path_for() {
    echo "${SPEC_DIR}/lunes-${NETWORK}-raw.json"
}

# ------------------------------------------------------------------
# 1) Dependências mínimas de runtime (NÃO instala toolchain de build)
# ------------------------------------------------------------------
install_runtime_deps() {
    step "1/6 Verificando dependências de runtime"
    local pkgs=""
    have curl || pkgs="$pkgs curl"
    have jq   || pkgs="$pkgs jq"
    # ca-certificates garante TLS; libgcc/libssl vêm no sistema base do Debian/Ubuntu
    if [ -n "$pkgs" ]; then
        info "Instalando:${pkgs}"
        if have apt-get; then
            $SUDO apt-get update -qq
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs ca-certificates >/dev/null
        elif have dnf; then
            $SUDO dnf install -y -q $pkgs
        elif have yum; then
            $SUDO yum install -y -q $pkgs
        elif have pacman; then
            $SUDO pacman -Sy --noconfirm $pkgs
        else
            warn "Gerenciador de pacotes não reconhecido. Instale manualmente:${pkgs}"
        fi
    fi
    ok "Dependências de runtime prontas"
}

# ------------------------------------------------------------------
# 2) Obtenção do binário (o caminho mais leve primeiro)
# ------------------------------------------------------------------
fetch_binary() {
    step "2/6 Obtendo o binário ${BIN_NAME}"
    local arch tmp
    arch="$(detect_arch)"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    # Estratégia A: URL explícita
    if [ -n "$BINARY_URL" ]; then
        info "Baixando de URL fornecida..."
        _download_binary "$BINARY_URL" "$tmp/${BIN_NAME}" && { _install_binary "$tmp/${BIN_NAME}"; return; }
        die "Falha ao baixar do --binary-url informado."
    fi

    # Estratégia B: build do fonte, se solicitado explicitamente
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        _build_from_source "$tmp"
        _install_binary "$tmp/target/release/${BIN_NAME}"
        return
    fi

    # Estratégia C: último GitHub Release com asset compatível
    info "Procurando release no GitHub (${LUNES_REPO})..."
    local api url
    api="https://api.github.com/repos/${LUNES_REPO}/releases/latest"
    url="$(curl -fsSL "$api" 2>/dev/null \
        | jq -r --arg arch "$arch" \
          '.assets[]? | select(.name|test($arch)) | .browser_download_url' \
        | head -n1 || true)"
    if [ -z "$url" ]; then
        # sem match por arch: tenta um asset chamado exatamente lunes-node
        url="$(curl -fsSL "$api" 2>/dev/null \
            | jq -r '.assets[]? | select(.name=="lunes-node" or (.name|test("lunes-node"))) | .browser_download_url' \
            | head -n1 || true)"
    fi

    if [ -n "$url" ] && [ "$url" != "null" ]; then
        info "Baixando release: $url"
        if _download_binary "$url" "$tmp/${BIN_NAME}"; then
            _install_binary "$tmp/${BIN_NAME}"
            return
        fi
        warn "Download do release falhou."
    else
        warn "Nenhum GitHub Release publicado ainda para ${LUNES_REPO}."
    fi

    # Sem binário disponível: orienta o usuário
    err "Não foi possível obter um binário pré-compilado."
    cat <<EOF

  Opções:
    1) Peça ao mantenedor para publicar um Release com o binário '${BIN_NAME}'
       (o repositório já contém um binário em 'artefacts/lunes-node').
    2) Forneça uma URL direta:   $0 install --binary-url <URL>
    3) Compile do código-fonte:  $0 install --build-from-source
       (requer ~4GB RAM livre e vários minutos; instala a toolchain Rust)
EOF
    exit 1
}

_download_binary() {
    # _download_binary <url> <destino>
    local url="$1" dest="$2"
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url" || return 1
    # Se veio comprimido, tenta descomprimir
    case "$url" in
        *.tar.gz|*.tgz) tar -xzf "$dest" -C "$(dirname "$dest")" && \
                        mv "$(dirname "$dest")/${BIN_NAME}" "$dest" 2>/dev/null || true ;;
        *.gz)           gunzip -f "$dest" 2>/dev/null && mv "${dest%.gz}" "$dest" 2>/dev/null || true ;;
    esac
    chmod +x "$dest" 2>/dev/null || true
    # Valida que é um ELF executável
    if have file && ! file "$dest" | grep -q 'ELF'; then
        warn "O arquivo baixado não parece um executável ELF."
        return 1
    fi
    return 0
}

_install_binary() {
    local src="$1"
    [ -f "$src" ] || die "Binário não encontrado após obtenção: $src"
    info "Instalando em ${INSTALL_BIN}"
    $SUDO install -m 0755 "$src" "$INSTALL_BIN"
    # Verifica versão (sanidade)
    if "$INSTALL_BIN" --version >/dev/null 2>&1; then
        ok "$("$INSTALL_BIN" --version 2>/dev/null | head -n1)"
    else
        warn "Binário instalado, mas '--version' falhou (dependências de sistema?)."
    fi
}

_build_from_source() {
    local tmp="$1"
    step "Compilando do código-fonte (modo pesado)"
    warn "Isso instala a toolchain Rust e compila o node — pode levar 15-40 min."
    if ! have rustup; then
        info "Instalando Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
    fi
    info "Instalando dependências de build..."
    if have apt-get; then
        $SUDO apt-get update -qq
        $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            build-essential git clang curl libssl-dev protobuf-compiler pkg-config >/dev/null
    fi
    info "Clonando o repositório..."
    git clone --depth=1 "https://github.com/${LUNES_REPO}.git" "$tmp/src"
    ( cd "$tmp/src" && rustup show && cargo build --locked --release )
    mkdir -p "$tmp/target/release"
    cp "$tmp/src/target/release/${BIN_NAME}" "$tmp/target/release/${BIN_NAME}"
    ok "Compilação concluída"
}

# ------------------------------------------------------------------
# 3) Usuário de sistema dedicado (sem shell, sem root)
# ------------------------------------------------------------------
create_user() {
    step "3/6 Criando usuário de sistema '${LUNES_USER}'"
    if id "$LUNES_USER" >/dev/null 2>&1; then
        ok "Usuário '${LUNES_USER}' já existe"
    else
        $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin "$LUNES_USER"
        ok "Usuário '${LUNES_USER}' criado"
    fi
    $SUDO mkdir -p "$DATA_DIR" "$SPEC_DIR"
    $SUDO chown -R "$LUNES_USER:$LUNES_USER" "$LUNES_HOME"
    ok "Diretórios em ${LUNES_HOME} prontos"
}

# ------------------------------------------------------------------
# 4) Chain spec da rede escolhida
# ------------------------------------------------------------------
fetch_chainspec() {
    step "4/6 Baixando chain spec (${NETWORK})"
    local url dest
    url="$(spec_url_for)"
    dest="$(spec_path_for)"
    info "$url"
    local tmp; tmp="$(mktemp)"
    curl -fL --retry 3 -o "$tmp" "$url" || die "Falha ao baixar a chain spec."
    # Sanidade: precisa ser JSON válido com bootNodes
    if have jq && ! jq -e '.bootNodes' "$tmp" >/dev/null 2>&1; then
        die "Chain spec baixada é inválida (sem bootNodes)."
    fi
    $SUDO install -m 0644 "$tmp" "$dest"
    $SUDO chown "$LUNES_USER:$LUNES_USER" "$dest"
    rm -f "$tmp"
    ok "Chain spec salva em $dest"
}

# ------------------------------------------------------------------
# 5) Serviço systemd (parametrizado por papel)
# ------------------------------------------------------------------
write_service() {
    step "5/6 Instalando serviço systemd"
    local spec name role_flags rpc_flags
    spec="$(spec_path_for)"
    name="${NODE_NAME:-lunes-${NETWORK}-$(hostname -s 2>/dev/null || echo node)}"

    # RPC no modo 'Auto': expõe métodos unsafe (ex.: author_rotateKeys) SOMENTE
    # quando o RPC está ligado a localhost; se for exposto externamente, o
    # próprio Substrate restringe automaticamente para os métodos Safe.
    # Isso permite `lunes-node.sh keys` localmente sem abrir mão da segurança.
    rpc_flags="--rpc-methods=Auto"
    if [ "$ROLE" = "validator" ]; then
        # Validador: participa do consenso.
        role_flags="--validator"
    else
        # Full node / membro: apenas sincroniza e serve RPC local.
        role_flags=""
    fi

    # Exposição externa de RPC/WS (opcional; desaconselhado em validadores)
    local ext_flags=""
    if [ "$RPC_EXTERNAL" = "true" ]; then
        ext_flags="--rpc-external --ws-external --rpc-cors=all"
        [ "$ROLE" = "validator" ] && warn "RPC externo em validador não é recomendado."
    fi

    # Modo de pruning (nesta versão o Substrate separa estado e blocos).
    #   número            -> nó leve (mantém apenas os últimos N blocos finalizados)
    #   archive           -> nó de arquivo (mantém todo o histórico)
    local prune_flags
    if [ "$PRUNING" = "archive" ]; then
        prune_flags="--state-pruning archive --blocks-pruning archive"
    else
        prune_flags="--state-pruning ${PRUNING}"
    fi

    local exec_line
    exec_line="${INSTALL_BIN} \\
    --base-path ${DATA_DIR} \\
    --chain ${spec} \\
    --name \"${name}\" \\
    --port ${P2P_PORT} \\
    --rpc-port ${RPC_PORT} \\
    --ws-port ${WS_PORT} \\
    --prometheus-port ${PROM_PORT} \\
    ${prune_flags} \\
    ${rpc_flags} ${role_flags} ${ext_flags}"

    local tmp; tmp="$(mktemp)"
    cat > "$tmp" <<EOF
[Unit]
Description=Lunes ${NETWORK} node (${ROLE})
Documentation=https://github.com/${LUNES_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${LUNES_USER}
Group=${LUNES_USER}
Restart=always
RestartSec=3
LimitNOFILE=65536

# --- Endurecimento de segurança (sandbox systemd) ---
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
ReadWritePaths=${LUNES_HOME}

ExecStart=${exec_line}

[Install]
WantedBy=multi-user.target
EOF

    $SUDO install -m 0644 "$tmp" "$SERVICE_FILE"
    rm -f "$tmp"
    $SUDO systemctl daemon-reload
    ok "Serviço instalado em $SERVICE_FILE"
}

# ------------------------------------------------------------------
# 6) Ativar e iniciar
# ------------------------------------------------------------------
start_service() {
    step "6/6 Habilitando e iniciando o serviço"
    $SUDO systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
    $SUDO systemctl restart "$SERVICE_NAME"
    sleep 2
    if $SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
        ok "Serviço '${SERVICE_NAME}' está ativo"
    else
        warn "O serviço não ficou ativo. Veja: $0 logs"
    fi
}

# ------------------------------------------------------------------
# Comando: install
# ------------------------------------------------------------------
cmd_install() {
    require_linux
    case "$NETWORK" in mainnet|testnet) ;; *) die "Rede inválida: $NETWORK (use 'mainnet' ou 'testnet')" ;; esac
    case "$ROLE" in full|validator) ;; *) die "Papel inválido: $ROLE" ;; esac
    need_sudo
    print_install_summary
    if ! confirm "Prosseguir com a instalação?"; then
        info "Instalação cancelada."; exit 0
    fi
    install_runtime_deps
    fetch_binary
    create_user
    fetch_chainspec
    write_service
    start_service
    print_post_install
}

print_install_summary() {
    cat <<EOF

${C_BOLD}Resumo da instalação${C_RESET}
  Rede........: ${NETWORK}
  Papel.......: ${ROLE}
  Binário.....: ${INSTALL_BIN}
  Dados.......: ${DATA_DIR}
  Pruning.....: ${PRUNING}
  RPC externo.: ${RPC_EXTERNAL}
  Origem bin..: $( [ -n "$BINARY_URL" ] && echo "URL informada" || { [ "$BUILD_FROM_SOURCE" = true ] && echo "compilação do fonte" || echo "GitHub Release"; } )
EOF
}

print_post_install() {
    cat <<EOF

${C_GRN}${C_BOLD}Instalação concluída!${C_RESET}

  Comandos úteis:
    $0 status          # estado do nó
    $0 logs            # acompanhar logs em tempo real
    $0 keys            # (validadores) gerar e inserir chaves de sessão

  Ou diretamente via systemd:
    ${SUDO:-sudo} systemctl status ${SERVICE_NAME}
    ${SUDO:-sudo} journalctl -u ${SERVICE_NAME} -f

EOF
    if [ "$ROLE" = "validator" ]; then
        cat <<EOF
${C_YLW}Próximo passo para validadores:${C_RESET}
  1) Aguarde o nó sincronizar com a rede.
  2) Rode:  $0 keys
     Isso gera as chaves de sessão (author_rotateKeys) e mostra a chave
     pública que você deve registrar on-chain via extrínseco session.setKeys.

EOF
    fi
}

# ------------------------------------------------------------------
# Comando: keys (gera/rotaciona chaves de sessão do validador)
# ------------------------------------------------------------------
cmd_keys() {
    need_sudo
    local rpc="http://127.0.0.1:${RPC_PORT}"
    step "Gerando chaves de sessão via ${rpc}"
    if ! $SUDO systemctl is-active --quiet "$SERVICE_NAME"; then
        die "O serviço não está ativo. Inicie-o antes: ${SUDO:-sudo} systemctl start ${SERVICE_NAME}"
    fi
    have curl || die "curl é necessário."
    local resp key
    resp="$(curl -fsS -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"author_rotateKeys","params":[]}' \
        "$rpc" || true)"
    key="$(printf '%s' "$resp" | (jq -r '.result // empty' 2>/dev/null || true))"
    if [ -z "$key" ]; then
        err "Não foi possível obter as chaves. Resposta do nó:"
        printf '%s\n' "$resp" >&2
        warn "Dica: author_rotateKeys exige RPC 'unsafe' local. Se necessário, reinstale com o RPC no modo apropriado ou consulte a documentação."
        exit 1
    fi
    ok "Chaves de sessão geradas com sucesso"
    cat <<EOF

${C_BOLD}Sua nova chave de sessão (public keys concatenadas):${C_RESET}
  ${key}

${C_YLW}Ação necessária:${C_RESET} registre esta chave on-chain enviando o extrínseco
  ${C_BOLD}session.setKeys(${key}, 0x00)${C_RESET}
a partir da sua conta de validador (via Polkadot-JS Apps ou CLI).

EOF
}

# ------------------------------------------------------------------
# Comando: status / logs
# ------------------------------------------------------------------
cmd_status() {
    need_sudo
    $SUDO systemctl status "$SERVICE_NAME" --no-pager || true
    echo
    local rpc="http://127.0.0.1:${RPC_PORT}"
    if have curl; then
        info "Consultando saúde do nó (${rpc})..."
        local health
        health="$(curl -fsS -H 'Content-Type: application/json' \
            -d '{"jsonrpc":"2.0","id":1,"method":"system_health","params":[]}' \
            "$rpc" 2>/dev/null || true)"
        if [ -n "$health" ]; then
            printf '%s\n' "$health" | (jq . 2>/dev/null || printf '%s\n' "$health")
        else
            warn "RPC local não respondeu (nó ainda iniciando?)."
        fi
    fi
}

cmd_logs() {
    need_sudo
    exec $SUDO journalctl -u "$SERVICE_NAME" -f --no-pager
}

# ------------------------------------------------------------------
# Comando: uninstall
# ------------------------------------------------------------------
cmd_uninstall() {
    need_sudo
    step "Removendo o nó Lunes"
    if $SUDO systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
        $SUDO systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        $SUDO systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        $SUDO rm -f "$SERVICE_FILE"
        $SUDO systemctl daemon-reload
        ok "Serviço systemd removido"
    fi
    [ -f "$INSTALL_BIN" ] && { $SUDO rm -f "$INSTALL_BIN"; ok "Binário removido"; }

    if [ "$KEEP_DATA" = "true" ]; then
        warn "Dados preservados em ${LUNES_HOME} (use --purge para apagar)."
    else
        if confirm "Apagar TODOS os dados em ${LUNES_HOME}? (irreversível)"; then
            $SUDO rm -rf "$LUNES_HOME"
            ok "Dados removidos"
            if id "$LUNES_USER" >/dev/null 2>&1; then
                $SUDO userdel "$LUNES_USER" 2>/dev/null || true
                ok "Usuário '${LUNES_USER}' removido"
            fi
        fi
    fi
    ok "Desinstalação concluída"
}

# ------------------------------------------------------------------
# Parser de argumentos
# ------------------------------------------------------------------
usage() {
    cat <<EOF
${C_BOLD}lunes-node.sh${C_RESET} — instalador leve e gerenciador de nós Lunes

USO:
  $0 <comando> [opções]

COMANDOS:
  install       Instala e inicia um nó (full node por padrão)
  keys          Gera/insere chaves de sessão (para validadores)
  status        Mostra o estado do serviço e a saúde do nó
  logs          Acompanha os logs em tempo real
  uninstall     Remove o serviço e o binário (preserva dados por padrão)

OPÇÕES (install):
  --network <mainnet|testnet>   Rede alvo (padrão: mainnet)
  --validator                   Instala como validador (participa do consenso)
  --full                        Instala como full node (padrão)
  --name <nome>                 Nome público do nó (telemetria)
  --pruning <N|archive>         Blocos mantidos; 'archive' = histórico completo (padrão: 1000)
  --rpc-external                Expõe RPC/WS externamente (padrão: só localhost)
  --binary-url <URL>            Baixa o binário desta URL (pula releases)
  --build-from-source           Compila do código-fonte (pesado; fallback)
  -y, --yes                     Não perguntar confirmações (modo automático)

OPÇÕES (uninstall):
  --purge                       Apaga também os dados e o usuário de sistema

GERAIS:
  -h, --help                    Mostra esta ajuda

EXEMPLOS:
  $0 install                         # full node na mainnet, binário pré-compilado
  $0 install --validator --name meu-validador
  $0 install --network testnet -y
  $0 install --pruning archive       # nó de arquivo (histórico completo)
  $0 keys                            # após sincronizar, gera chaves do validador
  $0 uninstall --purge               # remove tudo, inclusive dados
EOF
}

main() {
    [ $# -eq 0 ] && { usage; exit 0; }
    local cmd="$1"; shift || true

    while [ $# -gt 0 ]; do
        case "$1" in
            --network) NETWORK="${2:-}"; shift 2 ;;
            --validator) ROLE="validator"; shift ;;
            --full) ROLE="full"; shift ;;
            --name) NODE_NAME="${2:-}"; shift 2 ;;
            --pruning) PRUNING="${2:-}"; shift 2 ;;
            --rpc-external) RPC_EXTERNAL="true"; shift ;;
            --binary-url) BINARY_URL="${2:-}"; shift 2 ;;
            --build-from-source) BUILD_FROM_SOURCE="true"; shift ;;
            --purge) KEEP_DATA="false"; shift ;;
            -y|--yes) ASSUME_YES="true"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Opção desconhecida: $1 (use --help)" ;;
        esac
    done

    case "$cmd" in
        install)   cmd_install ;;
        keys)      cmd_keys ;;
        status)    cmd_status ;;
        logs)      cmd_logs ;;
        uninstall) cmd_uninstall ;;
        -h|--help|help) usage ;;
        *) die "Comando desconhecido: $cmd (use --help)" ;;
    esac
}

main "$@"
