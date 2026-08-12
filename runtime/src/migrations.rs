//! Módulo de Runtime Migrations para Lunes Nightly
//!
//! Cada struct aqui representa uma migração de storage aplicada em uma
//! versão específica do runtime. As migrations são executadas na ordem
//! definida em `Executive` quando o runtime é atualizado.
//!
//! ## Como adicionar uma nova migration:
//!
//! 1. Criar uma struct `MigrationVXX` neste arquivo
//! 2. Implementar `frame_support::traits::OnRuntimeUpgrade` para ela
//! 3. Adicionar ao tipo `Migrations` no final deste arquivo
//! 4. Incrementar `spec_version` em runtime/src/lib.rs
//! 5. Incrementar `STORAGE_VERSION` no pallet afetado
//!
//! ## Executar migrations em dev:
//! ```bash
//! ./target/release/lunes-node --dev --tmp
//! # Atualizar runtime via extrinsic sudo(system::set_code)
//! ```

use frame_support::traits::OnRuntimeUpgrade;
use frame_support::weights::Weight;

// NOTA: em `polkadot-v0.9.40` os hooks de try-runtime usam `&'static str` como
// tipo de erro. A partir de versões mais novas do polkadot-sdk isso passa a ser
// `sp_runtime::TryRuntimeError` — ajustar durante a migração (ver MIGRATION_GUIDE.md).
#[cfg(feature = "try-runtime")]
use sp_std::vec::Vec;

// ─────────────────────────────────────────────────────────────────────────────
// Migration v1 → v2: Placeholder – remover quando não aplicável
// Exemplo de estrutura para migrations futuras
// ─────────────────────────────────────────────────────────────────────────────
pub struct MigrationV1ToV2;

impl OnRuntimeUpgrade for MigrationV1ToV2 {
	fn on_runtime_upgrade() -> Weight {
		// Esta migration é um no-op por ora.
		// Substituir pelo código de migration real quando necessário.
		log::info!(
			target: "runtime::migrations",
			"MigrationV1ToV2: sem alterações de storage nesta versão"
		);
		Weight::zero()
	}

	#[cfg(feature = "try-runtime")]
	fn pre_upgrade() -> Result<Vec<u8>, &'static str> {
		log::info!(target: "runtime::migrations", "MigrationV1ToV2::pre_upgrade");
		Ok(Vec::new())
	}

	#[cfg(feature = "try-runtime")]
	fn post_upgrade(_state: Vec<u8>) -> Result<(), &'static str> {
		log::info!(target: "runtime::migrations", "MigrationV1ToV2::post_upgrade: OK");
		Ok(())
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Tipo agregado de todas as migrations em ordem de aplicação
// Adicionar novas migrations SEMPRE ao final (antes das mais recentes)
// ─────────────────────────────────────────────────────────────────────────────
pub type Migrations = (MigrationV1ToV2,);
