//! Pesos para `frame_system` — template de referência (Fase 3).
//!
//! ATENÇÃO: os valores abaixo são um baseline derivado dos pesos do Substrate
//! upstream. **Regenere com `cargo benchmark` em hardware de produção** antes de
//! usar em rede principal. Enquanto não regenerado, a configuração do runtime
//! continua usando `frame_system::weights::SubstrateWeight<Runtime>`.
//!
//! Estrutura idêntica à de um arquivo gerado por
//! `frame-benchmarking-cli`, para facilitar a substituição direta.

#![allow(unused_parens)]
#![allow(unused_imports)]
#![allow(clippy::unnecessary_cast)]

use frame_support::{
	traits::Get,
	weights::{constants::RocksDbWeight, Weight},
};
use sp_std::marker::PhantomData;

/// Pesos baseline para `frame_system` usando `T` como runtime.
pub struct SubstrateWeight<T>(PhantomData<T>);

impl<T: frame_system::Config> frame_system::WeightInfo for SubstrateWeight<T> {
	/// `remark` — custo proporcional ao tamanho `b` (bytes) do remark.
	fn remark(b: u32) -> Weight {
		Weight::from_parts(2_007_000_u64, 0)
			.saturating_add(Weight::from_parts(408_u64, 0).saturating_mul(b as u64))
	}

	/// `remark_with_event` — emite evento além do remark.
	fn remark_with_event(b: u32) -> Weight {
		Weight::from_parts(8_000_000_u64, 0)
			.saturating_add(Weight::from_parts(1_500_u64, 0).saturating_mul(b as u64))
	}

	/// `set_heap_pages` — 1 leitura, 2 escritas.
	fn set_heap_pages() -> Weight {
		Weight::from_parts(6_000_000_u64, 0)
			.saturating_add(T::DbWeight::get().reads(1_u64))
			.saturating_add(T::DbWeight::get().writes(2_u64))
	}

	/// `set_storage` — grava `i` itens de storage.
	fn set_storage(i: u32) -> Weight {
		Weight::from_parts(0_u64, 0)
			.saturating_add(Weight::from_parts(596_000_u64, 0).saturating_mul(i as u64))
			.saturating_add(T::DbWeight::get().writes(i as u64))
	}

	/// `kill_storage` — remove `i` itens de storage.
	fn kill_storage(i: u32) -> Weight {
		Weight::from_parts(0_u64, 0)
			.saturating_add(Weight::from_parts(434_000_u64, 0).saturating_mul(i as u64))
			.saturating_add(T::DbWeight::get().writes(i as u64))
	}

	/// `kill_prefix` — remove `p` chaves sob um prefixo.
	fn kill_prefix(p: u32) -> Weight {
		Weight::from_parts(0_u64, 0)
			.saturating_add(Weight::from_parts(1_002_000_u64, 0).saturating_mul(p as u64))
			.saturating_add(T::DbWeight::get().writes(p as u64))
	}
}

// Mantém `RocksDbWeight` importado como referência para regeneração manual,
// caso se prefira pesos de banco fixos em vez de `T::DbWeight`.
#[allow(dead_code)]
fn _rocksdb_reference() -> Weight {
	RocksDbWeight::get().reads(1)
}
