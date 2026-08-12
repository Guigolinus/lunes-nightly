# Workflows pendentes de instalação

Estes arquivos de GitHub Actions (`ci.yml` e `security.yml`) fazem parte da
Fase 2 (CI/CD Pipeline), mas **não puderam ser colocados diretamente em
`.github/workflows/`** porque o token do GitHub App usado para abrir o PR não
possui a permissão `workflows` (o GitHub bloqueia a criação/atualização de
workflows sem essa permissão).

## Como ativar

Um mantenedor com permissão de escrita deve mover os arquivos para o diretório
de workflows e fazer commit:

```bash
git mv .github/workflows-pending/ci.yml       .github/workflows/ci.yml
git mv .github/workflows-pending/security.yml .github/workflows/security.yml
rmdir .github/workflows-pending 2>/dev/null || true
git commit -m "ci: activate Phase 2 CI/CD and security workflows"
git push
```

Alternativamente, conceda a permissão `workflows` ao GitHub App e reenvie o push.

## Conteúdo

- `ci.yml` — Pipeline principal: `fmt`, `clippy`, `test`, `audit`,
  `build-check` e `docker-build`.
- `security.yml` — Auditoria semanal com `cargo-audit` e `cargo-deny`.
