# ============================================================
# Stage 1: Builder – Compila o nó Substrate
# ============================================================
FROM docker.io/paritytech/ci-linux:production AS builder

WORKDIR /build

# Copiar manifests primeiro para cache de dependências
COPY Cargo.toml Cargo.lock ./
COPY rust-toolchain.toml ./

# Copiar código-fonte
COPY node/ ./node/
COPY runtime/ ./runtime/
COPY pallets/ ./pallets/
COPY primitives/ ./primitives/

# Instalar toolchain correta e compilar em release
RUN rustup show && \
    cargo build --locked --release --features runtime-benchmarks 2>&1 | tail -20

# ============================================================
# Stage 2: Runner – Imagem mínima de produção
# ============================================================
FROM docker.io/debian:bullseye-slim

LABEL org.opencontainers.image.source="https://github.com/Guigolinus/lunes-nightly"
LABEL org.opencontainers.image.description="Lunes Nightly Blockchain Node"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# Dependências mínimas de runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl-dev \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Criar usuário não-root para executar o nó
RUN useradd -m -u 1000 -U -s /bin/sh -d /lunes lunes

# Copiar binário compilado
COPY --from=builder /build/target/release/lunes-node /usr/local/bin/lunes-node

# Verificar que o binário é válido
RUN lunes-node --version

# Configurar diretório de dados
RUN mkdir -p /data /lunes/.local/share && \
    chown -R lunes:lunes /data /lunes

USER lunes

EXPOSE 30333 9933 9944 9615

VOLUME ["/data"]

ENTRYPOINT ["/usr/local/bin/lunes-node"]
CMD ["--dev", "--ws-external", "--rpc-external", "--rpc-cors=all", "-d", "/data"]
