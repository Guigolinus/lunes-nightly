# Guia de Migração: polkadot-v0.9.40 → polkadot-sdk (stable)

## Visão Geral

Este documento descreve o caminho planejado para migrar o Lunes Nightly do
Substrate `polkadot-v0.9.40` (EOL) para o `polkadot-sdk` moderno,
com suporte a **PolkaVM** como target de compilação de contratos inteligentes.

## Por que migrar?

| Aspecto | polkadot-v0.9.40 | polkadot-sdk (stable2409+) |
|---------|-----------------|---------------------------|
| Status  | EOL – sem patches de segurança | Suportado ativamente |
| PolkaVM | ❌ Não suportado | ✅ Suportado (via RISC-V) |
| FRAME 2.0 | ❌ FRAME clássico | ✅ FRAME moderno (macros simplificadas) |
| try-runtime | Parcial | ✅ Completo |
| Benchmarks | Legado | ✅ v2 com frame_benchmarking |

## Fases da Migração

### Fase Atual (Pré-migração) ✅
- [x] Correções de segurança críticas (PR #1)
- [x] Dockerfile + CI/CD (PR #2)
- [x] Otimização de pallets (PR #3)
- [x] Preparação PolkaVM (PR #4)

### Fase 5: Migração de Dependências (Próxima)
```bash
# 1. Atualizar rust-toolchain.toml para nightly compatível com polkadot-sdk
# 2. Atualizar todas as dependências do Cargo.toml workspace
sed -i 's/polkadot-v0.9.40/polkadot-v1.x.y/g' Cargo.toml
# (Substituir x.y pela versão estável mais recente)
```

**Mudanças necessárias em Cargo.toml:**
- Trocar `git = "https://github.com/paritytech/substrate"` por
  `git = "https://github.com/paritytech/polkadot-sdk"`
- Atualizar todos os `branch = "polkadot-v0.9.40"` para a nova versão

### Fase 6: Adaptar Runtime para FRAME 2.0
- Atualizar macros de pallet (`#[pallet::*]`)
- Migrar `construct_runtime!` para nova sintaxe sem tuplas
- Atualizar tipos de peso (Weight agora inclui `proof_size`)

### Fase 7: Habilitar PolkaVM
```toml
# runtime/Cargo.toml
[features]
polkavm = ["pallet-contracts/polkavm"]
```

```rust
// runtime/build.rs
substrate_wasm_builder::WasmBuilder::new()
    .with_current_project()
    .export_heap_base()
    .import_memory()
    .build_polkavm()  // ← Habilitar aqui
    .build();
```

## Checklist de Migração

### Pré-migração
- [ ] Todos os PRs de otimização mergeados e testes passando
- [ ] Snapshot do estado da chain antes da atualização
- [ ] Ambiente de teste isolado preparado

### Durante a Migração
- [ ] Atualizar dependências uma por uma (não tudo de uma vez)
- [ ] Verificar compatibilidade de tipos após cada atualização
- [ ] Executar `cargo check` a cada passo
- [ ] Testar migrations com `try-runtime` antes de aplicar

### Pós-migração
- [ ] Todos os testes passando (`cargo test --workspace`)
- [ ] Benchmarks regenerados para nova versão
- [ ] Nó consegue sincronizar com chain existente
- [ ] Contratos Wasm continuam executando corretamente

## Recursos Úteis

- [polkadot-sdk releases](https://github.com/paritytech/polkadot-sdk/releases)
- [Migration guide oficial (Parity)](https://github.com/paritytech/polkadot-sdk/blob/master/docs/CHANGELOG.md)
- [PolkaVM documentation](https://github.com/paritytech/polkavm)
- [try-runtime guide](https://paritytech.github.io/try-runtime/)
