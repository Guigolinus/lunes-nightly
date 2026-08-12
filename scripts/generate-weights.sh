#!/usr/bin/env bash
# ============================================================
# generate-weights.sh – Gera pesos de benchmarking para os pallets do runtime
#
# Uso:
#   ./scripts/generate-weights.sh [pallet_name]
#
# Exemplos:
#   ./scripts/generate-weights.sh pallet_balances   # apenas um pallet
#   ./scripts/generate-weights.sh                    # todos os pallets configurados
#
# Pré-requisito: compilar o nó com a feature de benchmarking:
#   cargo build --release --features runtime-benchmarks
# ============================================================

set -euo pipefail

BINARY="${CARGO_TARGET_DIR:-target}/release/lunes-node"
OUTPUT_DIR="runtime/src/weights"
CHAIN="dev"
STEPS="${STEPS:-50}"
REPEAT="${REPEAT:-20}"
TEMPLATE=".maintain/frame-weight-template.hbs"

# Pallets críticos para os quais geramos pesos dedicados.
PALLETS=(
	"frame_system"
	"pallet_balances"
	"pallet_timestamp"
	"pallet_grandpa"
	"pallet_contracts"
)

if [ ! -f "$BINARY" ]; then
	echo "❌ Binário não encontrado: $BINARY"
	echo "   Compile primeiro com:"
	echo "     cargo build --release --features runtime-benchmarks"
	exit 1
fi

mkdir -p "$OUTPUT_DIR"

run_benchmark() {
	local pallet="$1"
	local output_file="$OUTPUT_DIR/${pallet}.rs"

	echo "📊 Gerando pesos para: $pallet → $output_file"

	local template_args=()
	if [ -f "$TEMPLATE" ]; then
		template_args=(--template="$TEMPLATE")
	fi

	"$BINARY" benchmark pallet \
		--chain="$CHAIN" \
		--pallet="$pallet" \
		--extrinsic='*' \
		--steps="$STEPS" \
		--repeat="$REPEAT" \
		--output="$output_file" \
		"${template_args[@]}"

	echo "✅ Concluído: $pallet"
}

if [ "${1:-}" != "" ]; then
	run_benchmark "$1"
else
	for pallet in "${PALLETS[@]}"; do
		run_benchmark "$pallet"
	done
fi

echo ""
echo "✅ Benchmarks concluídos!"
echo "   Arquivos gerados em: $OUTPUT_DIR/"
echo ""
echo "⚠️  ATENÇÃO: execute em hardware de produção para obter pesos precisos"
echo "   e aponte a configuração dos pallets em runtime/src/lib.rs para os"
echo "   arquivos gerados (ex.: crate::weights::frame_system::SubstrateWeight<Runtime>)."
