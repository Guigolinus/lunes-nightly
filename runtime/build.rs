fn main() {
	#[cfg(feature = "std")]
	{
		substrate_wasm_builder::WasmBuilder::new()
			.with_current_project()
			.export_heap_base()
			.import_memory()
			// TODO (Fase PolkaVM): Adicionar .build_polkavm() quando migrar para
			// polkadot-sdk >= stable2409 que suporta PolkaVM como target alternativo.
			// Ref: https://github.com/paritytech/polkadot-sdk/pull/3741
			.build();
	}
}
