//! Pesos gerados via benchmarking para o runtime Lunes Nightly.
//!
//! Este módulo concentra os pesos (`WeightInfo`) customizados dos pallets, gerados
//! a partir de execuções de benchmarking em hardware de referência. Enquanto os
//! pesos dedicados não são regenerados em hardware de produção, o runtime usa como
//! baseline os pesos do Substrate upstream (`<pallet>::weights::SubstrateWeight`).
//!
//! ## Como regenerar
//!
//! ```bash
//! # Compilar o nó com a feature de benchmarking
//! cargo build --release --features runtime-benchmarks
//!
//! # Gerar os pesos de um pallet específico
//! ./scripts/generate-weights.sh pallet_balances
//!
//! # Ou regenerar todos os pallets configurados
//! ./scripts/generate-weights.sh
//! ```
//!
//! O comando equivalente executado pelo script é:
//!
//! ```bash
//! ./target/release/lunes-node benchmark pallet \
//!   --chain=dev \
//!   --pallet=<PALLET> \
//!   --extrinsic='*' \
//!   --steps=50 \
//!   --repeat=20 \
//!   --output=runtime/src/weights/<pallet>.rs
//! ```
//!
//! Hardware de referência recomendado: Intel Core i7 (ou equivalente),
//! 16 GB de RAM, disco NVMe SSD.
//!
//! ## Como ativar os pesos customizados
//!
//! Após gerar um arquivo (por exemplo `runtime/src/weights/frame_system.rs`), aponte
//! a configuração do pallet para ele em `runtime/src/lib.rs`, por exemplo:
//!
//! ```ignore
//! type SystemWeightInfo = crate::weights::frame_system::SubstrateWeight<Runtime>;
//! ```

#![allow(unused_parens)]
#![allow(unused_imports)]
#![allow(clippy::unnecessary_cast)]

/// Pesos baseline para `frame_system` (template de referência – Fase 3).
pub mod frame_system;
