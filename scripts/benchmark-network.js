// Uso: node scripts/benchmark-network.js  (nó dev em ws://127.0.0.1:9944; defina WS=... para outro endpoint)
// Benchmark da rede Lunes — mede constantes de consenso, limites de bloco,
// capacidade (TPS) e taxas reais por operação via payment_queryInfo.
const { ApiPromise, WsProvider, Keyring } = require('@polkadot/api');

const WS = process.env.WS || 'ws://127.0.0.1:9944';

function n(x) { return BigInt(x.toString()); }
function fmtPlanck(p, decimals) {
  const s = p.toString().padStart(decimals + 1, '0');
  const int = s.slice(0, s.length - decimals);
  const frac = s.slice(s.length - decimals).replace(/0+$/, '');
  return frac ? `${int}.${frac}` : int;
}

async function queryInfo(api, tx) {
  const info = await api.rpc.payment.queryInfo(tx.toHex());
  return {
    refTime: n(info.weight.refTime ?? info.weight),
    proofSize: n(info.weight.proofSize ?? 0),
    partialFee: n(info.partialFee),
    len: tx.toU8a().length,
    class: info.class.toString(),
  };
}

async function main() {
  const provider = new WsProvider(WS);
  const api = await ApiPromise.create({ provider });
  await api.isReady;

  const out = {};

  // ---- Chain / token ----
  const chain = (await api.rpc.system.chain()).toString();
  const props = await api.rpc.system.properties();
  const decimals = props.tokenDecimals.isSome ? props.tokenDecimals.unwrap()[0].toNumber() : 8;
  const symbol = props.tokenSymbol.isSome ? props.tokenSymbol.unwrap()[0].toString() : 'LUNES';
  out.chain = { chain, decimals, symbol };

  // ---- Consenso / tempo ----
  // MinimumPeriod * 2 = slot duration; block time in dev = 6s (from constants)
  const minPeriod = n(api.consts.timestamp.minimumPeriod);
  out.time = {
    minimumPeriodMs: minPeriod.toString(),
    blockTimeMs: (minPeriod * 2n).toString(),
  };

  // ---- Limites de bloco (peso e tamanho) ----
  const bw = api.consts.system.blockWeights;
  const maxBlockRef = n(bw.maxBlock.refTime ?? bw.maxBlock);
  const maxBlockPov = n(bw.maxBlock.proofSize ?? 0);
  const normal = bw.perClass.normal;
  const baseExtrinsicRef = n(normal.baseExtrinsic.refTime ?? normal.baseExtrinsic);
  const baseExtrinsicPov = n(normal.baseExtrinsic.proofSize ?? 0);
  const maxExtNormalRef = normal.maxTotal.isSome ? n(normal.maxTotal.unwrap().refTime ?? normal.maxTotal.unwrap()) : maxBlockRef;
  const maxExtNormalPov = normal.maxTotal.isSome ? n(normal.maxTotal.unwrap().proofSize ?? 0) : maxBlockPov;

  const bl = api.consts.system.blockLength;
  const maxBlockLenNormal = n(bl.max.normal);
  const maxBlockLenTotal = n(bl.max.operational ?? bl.max.normal);

  out.blockLimits = {
    maxBlockRefTime: maxBlockRef.toString(),
    maxBlockProofSize: maxBlockPov.toString(),
    baseExtrinsicRefTime: baseExtrinsicRef.toString(),
    baseExtrinsicProofSize: baseExtrinsicPov.toString(),
    normalMaxTotalRefTime: maxExtNormalRef.toString(),
    normalMaxTotalProofSize: maxExtNormalPov.toString(),
    maxBlockLengthNormalBytes: maxBlockLenNormal.toString(),
    maxBlockLengthTotalBytes: maxBlockLenTotal.toString(),
  };

  // ---- Existential deposit ----
  out.existentialDeposit = n(api.consts.balances.existentialDeposit).toString();

  // ---- Preparar contas dev ----
  const keyring = new Keyring({ type: 'sr25519' });
  const alice = keyring.addFromUri('//Alice');
  const bob = keyring.addFromUri('//Bob');

  // ---- Extrínsecos a medir ----
  const ops = [];

  // 1) Transferência simples
  try {
    const tx = api.tx.balances.transferKeepAlive(bob.address, n(1) * 10n ** BigInt(decimals));
    await tx.signAsync(alice, { nonce: 0 });
    ops.push(['Transferência simples (balances.transferKeepAlive)', await queryInfo(api, tx)]);
  } catch (e) { ops.push(['Transferência simples', { error: String(e) }]); }

  // 2) Mint de NFT (nfts.mint) — não precisa existir a coleção p/ estimar peso/taxa
  try {
    let tx;
    if (api.tx.nfts && api.tx.nfts.mint) {
      // assinatura pode variar: mint(collection, item, mintTo, witnessData)
      try { tx = api.tx.nfts.mint(0, 0, alice.address, null); }
      catch (_) { tx = api.tx.nfts.mint(0, 0, alice.address); }
    }
    if (tx) {
      await tx.signAsync(alice, { nonce: 0 });
      ops.push(['Mint de NFT (nfts.mint)', await queryInfo(api, tx)]);
    } else {
      ops.push(['Mint de NFT', { error: 'pallet nfts.mint indisponível' }]);
    }
  } catch (e) { ops.push(['Mint de NFT (nfts.mint)', { error: String(e) }]); }

  // 2b) Criação de coleção NFT (contexto)
  try {
    if (api.tx.nfts && api.tx.nfts.create) {
      const cfg = { settings: 0, maxSupply: null, mintSettings: { mintType: { Issuer: null }, price: null, startBlock: null, endBlock: null, defaultItemSettings: 0 } };
      let tx;
      try { tx = api.tx.nfts.create(alice.address, cfg); } catch (_) { tx = null; }
      if (tx) { await tx.signAsync(alice, { nonce: 0 }); ops.push(['Criar coleção NFT (nfts.create)', await queryInfo(api, tx)]); }
    }
  } catch (e) { /* opcional */ }

  // 3) Contrato inteligente — chamada a um contrato (contracts.call)
  try {
    if (api.tx.contracts && api.tx.contracts.call) {
      const gasLimit = api.registry.createType('WeightV2', { refTime: 3_000_000_000n, proofSize: 262_144n });
      const dummyAddr = bob.address; // endereço qualquer p/ estimativa de peso da chamada
      const tx = api.tx.contracts.call(dummyAddr, 0, gasLimit, null, '0x');
      await tx.signAsync(alice, { nonce: 0 });
      ops.push(['Chamada de contrato (contracts.call)', await queryInfo(api, tx)]);
    }
  } catch (e) { ops.push(['Chamada de contrato (contracts.call)', { error: String(e) }]); }

  // 3b) Deploy de contrato (contracts.instantiateWithCode) — código pequeno de exemplo
  try {
    if (api.tx.contracts && api.tx.contracts.instantiateWithCode) {
      // blob de código de exemplo (~4KB) só para dimensionar a taxa de comprimento
      const code = '0x' + '00'.repeat(4096);
      const gasLimit = api.registry.createType('WeightV2', { refTime: 5_000_000_000n, proofSize: 262_144n });
      const tx = api.tx.contracts.instantiateWithCode(0, gasLimit, null, code, '0x', '0x');
      await tx.signAsync(alice, { nonce: 0 });
      ops.push(['Deploy de contrato (~4KB) (contracts.instantiateWithCode)', await queryInfo(api, tx)]);
    }
  } catch (e) { ops.push(['Deploy de contrato', { error: String(e) }]); }

  out.operations = ops.map(([name, r]) => ({ name, ...r,
    partialFeeLunes: r.partialFee ? fmtPlanck(r.partialFee, decimals) : null }));

  // ---- Capacidade (TPS) para transferências simples ----
  const transfer = ops.find(([nm]) => nm.startsWith('Transferência'));
  if (transfer && transfer[1].refTime) {
    const t = transfer[1];
    const perTxRef = baseExtrinsicRef + t.refTime;
    const perTxPov = baseExtrinsicPov + t.proofSize;
    const blockTimeSec = Number((minPeriod * 2n)) / 1000;

    const byRef = maxExtNormalRef / perTxRef;
    const byPov = perTxPov > 0n ? maxExtNormalPov / perTxPov : null;
    const byLen = maxBlockLenNormal / n(t.len);

    // gargalo = menor limite
    let perBlock = byRef;
    let bound = 'ref_time';
    if (byPov !== null && byPov < perBlock) { perBlock = byPov; bound = 'proof_size'; }
    if (byLen < perBlock) { perBlock = byLen; bound = 'tamanho (bytes)'; }

    out.capacity = {
      blockTimeSec,
      transfersPerBlock_byRefTime: byRef.toString(),
      transfersPerBlock_byProofSize: byPov ? byPov.toString() : 'n/a',
      transfersPerBlock_byLength: byLen.toString(),
      bottleneck: bound,
      transfersPerBlock: perBlock.toString(),
      tps: (Number(perBlock) / blockTimeSec).toFixed(1),
      perTxLenBytes: t.len,
    };
  }

  console.log(JSON.stringify(out, (k, v) => (typeof v === 'bigint' ? v.toString() : v), 2));
  await api.disconnect();
}

main().catch((e) => { console.error('ERRO:', e); process.exit(1); });
