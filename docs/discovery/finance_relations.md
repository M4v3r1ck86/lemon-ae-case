# Data Discovery — `finance_relations`

## Visão geral

| Atributo | Valor observado |
|---|---|
| Tabela de origem | `raw.finance_relations` |
| Domínio | Financeiro / relacionamentos do grafo |
| Tipo de dado | Tabela de arestas direcionadas |
| Quantidade | 6.212 arestas |
| Nós de origem | 2.000 billings |
| Nós de destino | 6.212 entidades distintas |
| Tipos de destino | Charge, boleto e PIX |
| Arestas órfãs | 0 |
| Estado do discovery | Validado para o snapshot do case |

As consultas em BigQuery estão em
[`finance_relations_discovery.sql`](finance_relations_discovery.sql).

## Descrição funcional

`finance_relations` materializa as relações do backend em grafo. Não contém os
atributos financeiros das entidades: registra somente que um nó billing está
conectado a uma charge ou a um instrumento de pagamento.

> **Uma linha representa uma aresta direcionada `source → target` entre um
> billing e uma entidade financeira relacionada.**

No snapshot, toda origem é um billing. O tipo do destino não possui coluna
própria; é inferido pelo prefixo textual do identificador.

## Schema e dicionário de campos

| Campo | Tipo RAW | Papel | Definição baseada nas evidências | Classificação |
|---|---|---|---|---|
| `source` | `STRING` | Nó de origem | Identificador completo do billing de origem. Todos começam com `billing#`. | FATO |
| `target` | `STRING` | Nó de destino | Identificador completo de charge, boleto ou PIX. Cada target aparece uma única vez no snapshot. | FATO |
| `create_at` | `STRING` | Data/hora da relação | Timestamp textual em UTC da criação da aresta. | FATO estrutural |
| `ingestion_time` | `STRING` | Timestamp técnico da origem | Momento em que a aresta foi ingerida pelo sistema de origem/NRT. | FATO técnico; sistema exato DESCONHECIDO |
| `_ingested_at` | `TIMESTAMP` | Metadado da plataforma | Momento em que o snapshot foi carregado na RAW do BigQuery. | FATO |

## Granularidade e chaves

As 6.212 linhas formam 6.212 pares distintos e possuem 6.212 targets
distintos.

| Chave candidata | Única? | Observação |
|---|---:|---|
| `source + target` | Sim | Chave conceitualmente correta para uma aresta |
| `target` | Sim no snapshot | Cada entidade filha possui um único billing pai |
| `source` | Não | Um billing possui várias arestas |

Embora `target` seja único, a chave defensiva deve permanecer `source + target`
porque a exclusividade de pai pode ser uma propriedade do snapshot e não do
modelo do grafo inteiro.

## Tipos de relacionamento

| Tipo de origem | Tipo de destino | Arestas | Origens | Destinos |
|---|---|---:|---:|---:|
| `billing` | `charge` | 2.000 | 2.000 | 2.000 |
| `billing` | `boleto` | 2.105 | 2.000 | 2.105 |
| `billing` | `pix` | 2.107 | 2.000 | 2.107 |

Não foram encontrados:

- billings sem aresta;
- charges, boletos ou PIX sem aresta;
- sources que não existam em `finance_billings`;
- targets que não existam na tabela indicada pelo prefixo;
- arestas duplicadas.

Além disso, as 2.000 arestas de charge e as 2.107 de PIX coincidem com os
`billing_id` armazenados diretamente nas entidades correspondentes.

## Cardinalidade por billing

Cada billing possui exatamente uma charge, pelo menos um boleto e pelo menos um
PIX.

| Charges | Boletos | PIX | Total de arestas | Billings |
|---:|---:|---:|---:|---:|
| 1 | 1 | 1 | 3 | 1.922 |
| 1 | 2 | 2 | 5 | 60 |
| 1 | 3 | 3 | 7 | 11 |
| 1 | 4 | 4 | 9 | 4 |
| 1 | 3 | 5 | 9 | 1 |
| 1 | 5 | 5 | 11 | 1 |
| 1 | 6 | 6 | 13 | 1 |

A relação observada é:

```text
Billing
├── exatamente 1 Charge
├── 1 a 6 Boletos
└── 1 a 6 PIX
```

O aumento da quantidade de instrumentos acompanha os reagendamentos do billing
na maioria dos casos. Ainda assim, há exceções; por isso “instrumento adicional
= reemissão” continua sendo **HIPÓTESE**.

## Temporalidade

- criação das arestas: 2025-01-09 a 2025-09-18;
- `ingestion_time`: 2025-01-09 a 2025-09-18;
- nenhuma ingestão ocorre antes da criação da respectiva aresta no snapshot;
- existem 5.461 valores distintos de `ingestion_time`, mostrando que várias
  arestas podem ter sido ingeridas no mesmo instante/lote.

As duas datas são da origem e permanecem como texto. `_ingested_at` pertence à
plataforma construída para o case.

## Instrumentos e estados

Na consolidação por billing:

- 902 possuem boleto pago e nenhum PIX pago;
- 968 possuem PIX pago e nenhum boleto pago;
- 128 não possuem instrumento pago;
- 2 possuem boleto e PIX marcados como `paid`.

Entre os 128 billings `waitingPayment`, somente dois possuem instrumentos ainda
em `waitingPayment`; os outros 126 preservam apenas instrumentos cancelados.
Isso é uma inconsistência de estado ou defasagem entre entidades, mas a causa é
**DESCONHECIDA**.

Os dois billings com ambos os métodos pagos precisam de reconciliação externa.
Os dados comprovam estados duplicados, não comprovam recebimento bancário em
duplicidade.

## Papel na `generator_report`

A view cria três subconjuntos:

```text
billing → charge
billing → boleto
billing → pix
```

Os tipos são identificados com `LIKE 'billing#%'`, `LIKE 'charge#%'`,
`LIKE 'boleto#%'` e `LIKE 'pix#%'`. Depois:

1. o ramo billing + charge + boleto produz 2.105 linhas;
2. o ramo billing + charge + PIX produz 2.107 linhas;
3. ambos são combinados com `UNION ALL`;
4. o resultado possui 4.212 linhas para 2.000 billings antes das agregações.

Essa multiplicação não é apenas hipotética: decorre diretamente do SQL e das
cardinalidades. A view não escolhe um único instrumento por billing e não
filtra o status dos boletos ou PIX.

O risco é particularmente relevante porque os campos da charge e do billing
são repetidos em cada instrumento. Mesmo quando o valor pago do instrumento
cancelado é nulo, outras medidas podem ser duplicadas.

## Confirmado

- A tabela representa arestas direcionadas do grafo financeiro.
- Toda origem é billing; todo destino é charge, boleto ou PIX.
- Não existem arestas duplicadas nem entidades órfãs no snapshot.
- O relacionamento billing → charge é 1:1.
- Os relacionamentos billing → boleto e billing → PIX são 1:N.
- A view gera fanout de 2.000 para 4.212 linhas no bloco financeiro.
- Existem dois billings com os dois métodos marcados como pagos.

## Hipóteses

- Múltiplos instrumentos são versões históricas causadas por reagendamento.
- `source` e `target` são IDs globais no backend e seus prefixos funcionam como
  tipos de nó.
- Billings aguardando pagamento sem instrumento ativo podem refletir atraso de
  sincronização, cancelamento incompleto ou regra operacional não exposta.

## Questões abertas

1. O grafo possui um tipo explícito de aresta não disponibilizado no case?
2. Qual instrumento deve ser considerado vigente por billing?
3. Por que 126 billings aguardando pagamento não possuem instrumento com o
   mesmo status?
4. Os dois casos com boleto e PIX pagos representam recebimentos duplicados?
5. A retenção de todas as versões é intencional e imutável?
6. Há relações válidas em outras direções fora do recorte fornecido?
