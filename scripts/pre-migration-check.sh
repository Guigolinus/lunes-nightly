#!/usr/bin/env bash
# ============================================================
# pre-migration-check.sh – Validação antes de qualquer migração de runtime
#
# Este script verifica a saúde do repositório antes de:
# - Executar uma runtime upgrade
# - Migrar para uma nova versão de polkadot-sdk
# - Aplicar mudanças críticas de armazenamento
# ============================================================

set -euo pipefail

PASS=0
FAIL=0
WARN=0

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        PASS) echo "✅ PASS: $message"; ((PASS++)) ;;
        FAIL) echo "❌ FAIL: $message"; ((FAIL++)) ;;
        WARN) echo "⚠️  WARN: $message"; ((WARN++)) ;;
    esac
}

echo "=============================================="
echo "  Lunes Nightly – Checklist Pré-Migração"
echo "=============================================="
echo ""

# 1. Verificar que testes passam
echo "▶ Executando testes unitários..."
if cargo test --workspace --lib -q 2>&1; then
    print_status PASS "Todos os testes unitários passam"
else
    print_status FAIL "Testes unitários falharam – corrigir antes de migrar"
fi

# 2. Verificar ausência de warnings de compilação críticos
echo "▶ Verificando warnings de compilação..."
if cargo check --workspace 2>&1 | grep -q "^error"; then
    print_status FAIL "Erros de compilação encontrados"
else
    print_status PASS "Sem erros de compilação"
fi

# 3. Verificar cargo audit
echo "▶ Verificando vulnerabilidades de dependências..."
if command -v cargo-audit &> /dev/null; then
    if cargo audit -q 2>&1 | grep -q "Vulnerability found"; then
        print_status WARN "Vulnerabilidades encontradas em dependências – revisar antes de migrar"
    else
        print_status PASS "Nenhuma vulnerabilidade crítica em dependências"
    fi
else
    print_status WARN "cargo-audit não instalado: cargo install cargo-audit"
fi

# 4. Verificar formatação
echo "▶ Verificando formatação do código..."
if cargo fmt --all -- --check 2>&1; then
    print_status PASS "Código formatado corretamente"
else
    print_status WARN "Formatação inconsistente – executar: cargo fmt --all"
fi

# 5. Verificar StorageVersion nos pallets
echo "▶ Verificando StorageVersion nos pallets..."
if grep -r "storage_version" pallets/ --include="*.rs" -q 2>/dev/null; then
    print_status PASS "StorageVersion encontrada nos pallets"
else
    print_status WARN "StorageVersion não encontrada – adicionar antes de migrations"
fi

# 6. Verificar se migrations module existe
echo "▶ Verificando módulo de migrations..."
if [ -f "runtime/src/migrations.rs" ]; then
    print_status PASS "Módulo de migrations existe"
else
    print_status FAIL "runtime/src/migrations.rs não encontrado"
fi

echo ""
echo "=============================================="
echo "  Resultado: ✅ $PASS passou | ⚠️  $WARN avisos | ❌ $FAIL falhou"
echo "=============================================="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "❌ MIGRAÇÃO BLOQUEADA: Corrija os itens com FAIL antes de prosseguir."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo ""
    echo "⚠️  Migração pode prosseguir, mas revise os avisos acima."
    exit 0
else
    echo ""
    echo "✅ Todos os checks passaram. Pronto para migrar!"
    exit 0
fi
