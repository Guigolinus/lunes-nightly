# Benchmark da Rede Lunes

> Medição de **capacidade (TPS)**, **tempo/tamanho de bloco** e **taxas estimadas em LUNES**
> por operação (transferência simples, mint de NFT e contrato inteligente).
>
> Todos os números deste documento são **rastreáveis**: ou foram extraídos diretamente do
> código-fonte do runtime, ou medidos em um nó `--dev` em execução via a API de pagamento
> (`payment_queryInfo` / `TransactionPaymentApi`). Onde um valor é projetado por fórmula, isso
> está explicitamente indicado.

---

## 1. Metodologia

| Item | Detalhe |
|------|---------|
| Nó usado | `artefacts/lunes-node` (binário do repositório), modo `--dev` |
| Consenso | Aura (produção) + GRANDPA (finalização), 1 validador local |
| Medição de pesos | `TransactionPaymentApi.query_info` para cada extrínseco assinado |
| Medição de taxas | `partialFee` real retornado pelo runtime em execução |
| Constantes de bloco | `system.blockWeights` / `system.blockLength` (consts do runtime) |
| Cliente | `@polkadot/api` 10.9.1 (Node.js) — script em `scripts/benchmark-network.js` |

### Descoberta importante — binário defasado

Durante a medição foi detectada uma divergência entre o **binário compilado** e o **código-fonte atual**:

| | spec_version | Taxa por peso (`weight_to_fee`) |
|---|---|---|
| **Binário `artefacts/lunes-node`** | **106** | **retorna 0** para qualquer peso (bug de taxa-zero) |
| **Código-fonte atual (`runtime/src/lib.rs`)** | **107** | `ref_time + proof_size` (piso de 1.000 planck) — correção da Fase 1 |

Ou seja, **o binário versionado no repositório é anterior à correção de segurança da Fase 1** e
ainda cobra taxa baseada **apenas no tamanho** do extrínseco (o componente de peso é zerado).
Confirmação direta obtida no nó em execução:

```
weight_to_fee(refTime=174250000, proofSize=0) = 0 planck   # binário 106
length_to_fee(144) = 144000 planck
```

Por isso este relatório apresenta **duas colunas de taxa**:

- **Binário atual (106)** — taxa *medida* no nó em execução (só tamanho).
- **Runtime corrigido (107)** — taxa *projetada* aplicando a fórmula do código-fonte atual
  aos **pesos reais medidos** (a `WeightInfo` de cada pallet não mudou entre 106 e 107; apenas o
  mapeamento peso→taxa mudou). Não foi possível compilar e executar o runtime 107 nesta máquina
  por ausência da toolchain Rust/`cargo`; os pesos, porém, são idênticos, então a projeção é exata.

---

## 2. Parâmetros de consenso e tempo de bloco

| Parâmetro | Valor | Fonte |
|-----------|-------|-------|
| Tempo de bloco (`MILLISECS_PER_BLOCK`) | **6 s** (6000 ms) | `constants.rs` / medido (`minimumPeriod × 2`) |
| `SLOT_DURATION` | 6000 ms | `constants.rs` |
| `minimumPeriod` (timestamp) | 3000 ms | `timestamp.minimumPeriod` (medido) |
| Confirmação empírica | blocos importados a cada ~6 s | log do nó `--dev` |

O tempo de bloco de 6 segundos foi **confirmado empiricamente** observando a importação de blocos
sequenciais no nó em execução.

---

## 3. Limites de bloco (peso e tamanho)

| Limite | Valor medido | Interpretação |
|--------|--------------|---------------|
| Peso máximo do bloco (`maxBlock.refTime`) | `2.000.000.000.000` | **2 s** de tempo de computação (ref_time) |
| Peso máximo `proof_size` | `u64::MAX` (`18.446.744.073.709.551.615`) | sem limite prático de PoV (solochain) |
| Ratio normal (`NORMAL_DISPATCH_RATIO`) | **75 %** | fração do bloco para extrínsecos normais |
| Peso disponível p/ normais (`normal.maxTotal.refTime`) | `1.500.000.000.000` | **1,5 s** = 75 % de 2 s |
| Peso base por extrínseco (`baseExtrinsic.refTime`) | `99.840.000` | custo fixo de qualquer extrínseco |
| Tamanho máximo do bloco (total) | `5.242.880` bytes | **5 MiB** (`MAX_BLOCK_SIZE`) |
| Tamanho máximo p/ normais (75 %) | `3.932.160` bytes | **3,75 MiB** |

---

## 4. Capacidade da rede (TPS)

Calculada para **transferências simples** (`balances.transferKeepAlive`), usando o peso real medido
e considerando o peso base por extrínseco. TPS é independente do modelo de taxa.

| Métrica | Valor |
|---------|-------|
| Peso por transferência (dispatch) | `174.250.000` ref_time |
| Peso base por extrínseco | `99.840.000` ref_time |
| Peso total por transferência | `274.090.000` ref_time |
| Orçamento de peso normal / bloco | `1.500.000.000.000` ref_time |
| **Transferências por bloco (limite por peso)** | **≈ 5.472** |
| Transferências por bloco (limite por tamanho) | ≈ 27.306 |
| **Gargalo** | **peso (ref_time)** |
| Tempo de bloco | 6 s |
| **Capacidade estimada** | **≈ 912 TPS** (5.472 ÷ 6 s) |

> O gargalo é o **tempo de computação (ref_time)**, não o tamanho do bloco. O `proof_size` é
> ilimitado (`u64::MAX`), como esperado em uma solochain, então não limita a capacidade.
>
> **≈ 912 transferências simples por segundo** é o teto teórico com blocos 100 % cheios de
> transferências. Cargas mistas (NFT, contratos), que consomem mais peso por operação, reduzem
> proporcionalmente o TPS.

Capacidade por tipo de operação (limite por peso, blocos cheios):

| Operação | Peso total/op (ref_time) | Ops por bloco | Ops por segundo |
|----------|--------------------------|---------------|-----------------|
| Transferência simples | 274.090.000 | ≈ 5.472 | ≈ 912 |
| Mint de NFT | 675.088.000 | ≈ 2.222 | ≈ 370 |
| Chamada de contrato | 3.797.368.000 | ≈ 394 | ≈ 65 |
| Deploy de contrato (~4 KB) | 7.379.508.548 | ≈ 203 | ≈ 33 |

*(peso total/op = peso base 99.840.000 + peso do dispatch medido)*

---

## 5. Taxas estimadas por operação (em LUNES)

Decimais do token: **8** (1 LUNES = 100.000.000 planck).

| Operação | ref_time (medido) | Tam. (bytes) | Taxa — **binário 106** (medida) | Taxa — **runtime 107** (projetada) |
|----------|-------------------|--------------|-------------------------------|-----------------------------------|
| Transferência simples | 174.250.000 | 144 | **0,00144 LUNES** | **2,74234 LUNES** |
| Mint de NFT (`nfts.mint`) | 575.248.000 | 149 | **0,00149 LUNES** | **6,75237 LUNES** |
| Criar coleção NFT (`nfts.create`) | 588.703.000 | 161 | 0,00161 LUNES | 6,88704 LUNES |
| Chamada de contrato (`contracts.call`) | 3.697.528.000 | 152 | **0,00152 LUNES** | **37,97520 LUNES** |
| Deploy de contrato ~4 KB (`instantiateWithCode`) | 7.279.668.548 | 4.219 | 0,04219 LUNES | 73,83728 LUNES |

**Composição da taxa (runtime 107):** `taxa = taxa_base + taxa_de_peso + taxa_de_tamanho`, com

- `taxa_base` = `weight_to_fee(peso_base)` = **99.840.000 planck ≈ 0,9984 LUNES** (fixa por extrínseco);
- `taxa_de_peso` = `ref_time + proof_size` (piso de 1.000 planck);
- `taxa_de_tamanho` = `tamanho_em_bytes × 1.000 planck` (`TransactionByteFee = 1 NANOUNIT`);
- `FeeMultiplier = 1` (constante, sem ajuste dinâmico de congestionamento).

### ⚠️ Observação sobre a magnitude das taxas (runtime 107)

No modelo corrigido, a `taxa_de_peso` mapeia o `ref_time` (em picossegundos) **1:1 para planck**,
sem coeficiente de escala. Consequência: uma transferência simples custa **~2,74 LUNES** e uma
chamada de contrato **~38 LUNES**. Isso elimina o bug de taxa-zero (objetivo da Fase 1), mas
resulta em taxas **altas em termos absolutos**. Se a intenção for taxas menores, recomenda-se
introduzir um coeficiente divisor em `WeightToFeeLunes` (ex.: `ref_time / N`), mantendo o piso
`MINIMUM_WEIGHT_FEE`. **Este relatório não altera o código** — apenas registra o comportamento atual.

### Notas sobre contratos e NFT

- **Deploy de contrato**: além da taxa de inclusão acima, o `pallet_contracts` cobra um
  **depósito de armazenamento** (storage deposit) proporcional ao tamanho do código e ao estado
  criado. Esse depósito é **reembolsável** e **não** faz parte da taxa; ele varia com o contrato
  e não está incluído nos valores da tabela. O valor tabelado usa um blob de exemplo de ~4 KB.
- **Contratos**: o `gas_limit` (WeightV2) informado na chamada é um teto; a taxa efetiva depende do
  gás realmente consumido pela execução do contrato.
- **NFT**: os valores referem-se à operação `nfts.mint` de um item; taxas de metadados/atributos são
  cobradas à parte quando aplicáveis.

---

## 6. Reprodutibilidade

```bash
# 1) Subir um nó de desenvolvimento
./artefacts/lunes-node --dev --base-path /tmp/lunes-dev \
  --rpc-port 9933 --ws-port 9944 --rpc-methods=Unsafe --rpc-cors=all

# 2) Instalar dependências do script
npm install @polkadot/api@10.9.1

# 3) Rodar o benchmark
node scripts/benchmark-network.js
```

O script imprime, em JSON: constantes da cadeia, tempo de bloco, limites de bloco, taxas por
operação (`partialFee` real) e a capacidade (TPS) com o gargalo identificado.

---

## 7. Resumo executivo

| Pergunta | Resposta |
|----------|----------|
| **Capacidade (TPS)** | ≈ **912 TPS** para transferências simples (gargalo: tempo de computação) |
| **Tempo de bloco** | **6 segundos** (confirmado empiricamente) |
| **Tamanho máx. por bloco** | **5 MiB** total (3,75 MiB para extrínsecos normais) |
| **Peso máx. por bloco** | **2 s** de computação (1,5 s para extrínsecos normais) |
| **Taxa — transferência simples** | 0,00144 LUNES (binário 106) · **~2,74 LUNES** (runtime 107) |
| **Taxa — mint de NFT** | 0,00149 LUNES (binário 106) · **~6,75 LUNES** (runtime 107) |
| **Taxa — contrato (chamada)** | 0,00152 LUNES (binário 106) · **~37,98 LUNES** (runtime 107) + depósito |

> **Ação recomendada:** recompilar e redistribuir o binário na **spec_version 107** para que a
> rede passe a aplicar a correção de taxa da Fase 1. O binário atual (`artefacts/lunes-node`,
> spec 106) ainda cobra taxa apenas por tamanho.
