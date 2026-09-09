# Data Discovery — `finance_billings`

## Visão geral

| Atributo | Valor observado |
|---|---|
| Tabela de origem | `raw.finance_billings` |
| Domínio | Financeiro |
| Tipo de dado | Entidade transacional de faturamento/recebível |
| Quantidade | 2.000 registros |
| Faturamentos distintos | 2.000 |
| Locais (`place_id`) | 709 |
| IDs de usina do backend | 35 |
| Status | 1.872 `paid`; 128 `waitingPayment` |
| Período de criação | 2025-01-09 a 2025-04-11 |
| Estado do discovery | Validado para o snapshot do case |

As evidências foram obtidas diretamente do SQLite e podem ser reproduzidas no
BigQuery por meio de
[`finance_billings_discovery.sql`](finance_billings_discovery.sql).

As conclusões usam as seguintes classificações:

- **FATO:** comprovado pelo schema, pelos dados ou pelo SQL da
  `generator_report`;
- **HIPÓTESE:** interpretação plausível ainda sem definição oficial;
- **DESCONHECIDO:** não há evidência suficiente para concluir.

## Descrição funcional

`finance_billings` registra o faturamento financeiro central ao qual uma
cobrança e seus instrumentos de pagamento são conectados. A linha contém valor
nominal, vencimento, possível reagendamento, recebedor, situação de pagamento e
valores esperados/pagos.

> **Uma linha representa um faturamento mensal individual do backend para um
> `place_id`, associado a um recebedor e a um identificador de usina do
> backend.**

É **FATO** que a tabela funciona como nó central do subgrafo financeiro. O
significado jurídico exato de “billing” — fatura, recebível, contribuição ou
outro documento — permanece **DESCONHECIDO**.

## Schema e dicionário de campos

Todos os campos da fonte são fisicamente nullable no SQLite. `TEXT` é carregado
como `STRING`, `INTEGER` como `INT64`, e o loader acrescenta
`_ingested_at TIMESTAMP`.

| Campo | Tipo RAW | Papel | Definição baseada nas evidências | Classificação |
|---|---|---|---|---|
| `source` | `STRING` | Chave do grafo | Identificador completo do nó, sempre igual a `billing#` + `billing_id`. É a chave usada por `finance_relations`. | FATO |
| `billing_id` | `STRING` | Identificador do faturamento | Identificador sem o prefixo do tipo. É único nas 2.000 linhas e termina com uma data mensal. | FATO |
| `place_id` | `STRING` | Identificador de local | Identifica o local/estabelecimento associado. Há 709 valores e o mesmo campo existe nas charges e nos instrumentos. “Local” é HIPÓTESE semântica. | FATO estrutural; HIPÓTESE semântica |
| `amount` | `INT64` | Valor monetário | Valor nominal armazenado em centavos. A view divide o campo por 100. | FATO |
| `amount_without_discounts` | `INT64` | Valor monetário | Valor antes de descontos, em centavos. É igual a `amount` em todo o snapshot. | FATO no snapshot |
| `temporary_discount_amount` | `INT64` | Ajuste monetário | Desconto temporário em centavos. É zero em todas as linhas; a regra que o ativa é desconhecida. | FATO sobre os dados; regra DESCONHECIDA |
| `status` | `STRING` | Status | Estado do faturamento. Valores observados: `paid` e `waitingPayment`. | FATO |
| `create_at` | `STRING` | Data/hora de criação | Timestamp textual da criação. O nome provavelmente deveria ser `created_at`, mas não deve ser corrigido na RAW. | FATO; intenção do nome é HIPÓTESE alta |
| `due_date` | `STRING` | Data de vencimento | Vencimento vigente, que pode divergir do original após reagendamento. | FATO |
| `original_due_date` | `STRING` | Data de vencimento original | Primeiro vencimento observado para o faturamento. | FATO funcional no snapshot |
| `billing_payment_date` | `STRING` | Data/hora de pagamento | Timestamp de pagamento no nível do billing; vazio nos 128 registros aguardando pagamento. | FATO |
| `billing_energy_farm_id` | `STRING` | Identificador de entidade | ID de usina do backend. Possui correspondência 1:1 com 35 usinas quando o caminho billing → charge → cliente é percorrido, mas não existe diretamente em `energy_farms`. | FATO estrutural |
| `billing_rescheduled_times` | `INT64` | Contador | Quantidade informada de reagendamentos. Está preenchido em 77 linhas. | FATO; regra de atualização DESCONHECIDA |
| `cancelled_at` | `STRING` | Data de cancelamento | Campo destinado ao cancelamento; está vazio nas 2.000 linhas. | FATO |
| `cancellation_reason` | `STRING` | Motivo de cancelamento | Campo destinado ao motivo; está vazio no snapshot. | FATO |
| `cancellation_type` | `STRING` | Categoria de cancelamento | Tipo de cancelamento; está vazio no snapshot. | FATO |
| `cancelled_by` | `STRING` | Autor do cancelamento | Identificador esperado do responsável; está vazio no snapshot. | FATO |
| `cancellation_description` | `STRING` | Descrição | Texto livre de cancelamento; está vazio no snapshot. | FATO |
| `billing_expected_total` | `INT64` | Valor monetário | Total esperado em centavos. É preenchido nas 1.872 linhas pagas. | FATO |
| `billing_expected_interest` | `INT64` | Valor monetário | Juros esperados em centavos. | FATO pelo cálculo; regra contratual DESCONHECIDA |
| `billing_expected_fine` | `INT64` | Valor monetário | Multa esperada em centavos. | FATO pelo cálculo; regra contratual DESCONHECIDA |
| `billing_paid_total` | `INT64` | Valor monetário | Total pago em centavos. É preenchido nas 1.872 linhas pagas. | FATO |
| `billing_paid_interest` | `INT64` | Valor monetário | Juros efetivamente registrados no pagamento, em centavos. | FATO |
| `billing_paid_fine` | `INT64` | Valor monetário | Multa efetivamente registrada no pagamento, em centavos. | FATO |
| `billing_receiver_id` | `STRING` | Identificador de recebedor | Identifica a conta/entidade recebedora. Há 14 valores. | FATO estrutural |
| `billing_receiver_type` | `STRING` | Categoria | Tipo do recebedor: `consortium` ou `lemon`. | FATO |
| `ingestion_time` | `STRING` | Timestamp técnico da origem | Momento de ingestão informado pelo backend/NRT. Não deve ser confundido com `_ingested_at`. | FATO técnico; sistema exato DESCONHECIDO |
| `_ingested_at` | `TIMESTAMP` | Metadado da plataforma | Momento em que o loader carregou o snapshot no BigQuery. | FATO |

## Granularidade e chaves

As 2.000 linhas possuem 2.000 `source` e 2.000 `billing_id` distintos. A
combinação observada `place_id + mês codificado no billing_id` também possui
2.000 valores.

| Chave candidata | Única? | Nula/vazia? | Uso |
|---|---:|---:|---|
| `source` | Sim | Não | Chave canônica do nó no grafo |
| `billing_id` | Sim | Não | Identificador sem o prefixo de entidade |
| `place_id + mês do billing_id` | Sim no snapshot | Não | Chave natural candidata, ainda sem garantia histórica |
| `billing_energy_farm_id` | Não | Não | Relacionamento, não chave da linha |

Para relacionamentos provenientes do grafo, `source` é a melhor chave. A
unicidade entre snapshots ainda precisa ser testada antes de definir uma chave
histórica.

## Perfil financeiro

Os valores são inteiros em centavos:

| Métrica | Resultado |
|---|---:|
| Menor `amount` | R$ 2,37 |
| Média | R$ 704,06 |
| Maior `amount` | R$ 24.294,60 |
| Soma | R$ 1.408.117,44 |

Em todas as linhas:

```text
amount = amount_without_discounts - temporary_discount_amount
```

Como `temporary_discount_amount = 0` em todo o conjunto, o mecanismo de
desconto não é exercitado pelo snapshot.

Para os registros pagos, os campos esperados e pagos estão preenchidos. Em 291
linhas, o total efetivamente pago difere do total esperado. Existe uma linha em
que os campos de juros e multa estão preenchidos, mas o total informado é igual
ao principal, contrariando a soma candidata. Isso deve permanecer como exceção
observada, não como regra corrigida por inferência.

## Temporalidade e status

- criação: 2025-01-09 a 2025-04-11;
- vencimento vigente: 2025-01-22 a 2025-09-19;
- pagamento informado: 2025-01-09 a 2025-09-17;
- `ingestion_time`: 2025-09-26;
- 1.872 registros estão `paid` e possuem data de pagamento;
- 128 estão `waitingPayment` e não possuem valores esperado/pago;
- 78 vencimentos diferem do vencimento original;
- 77 desses registros possuem `billing_rescheduled_times`; uma divergência não
  possui contador preenchido.

Datas são armazenadas como texto e precisam de `SAFE_CAST` antes de qualquer
comparação na camada confiável.

## Relacionamentos essenciais

| Origem | Destino | Cardinalidade observada | Evidência |
|---|---|---|---|
| Billing | Charge | 1:1 | Cada um dos 2.000 billings possui exatamente uma aresta para charge |
| Billing | Boleto | 1:N | 2.105 boletos; entre 1 e 6 por billing |
| Billing | PIX | 1:N | 2.107 PIX; entre 1 e 6 por billing |
| `billing_id` | `finance_charges.billing_id` | 1:1 | Valores, status e `place_id` coincidem nas 2.000 linhas |
| `place_id` | Unidade consumidora | 1:1 no snapshot | Resolvido por `finance_charges` |
| `billing_energy_farm_id` | Usina | 1:1 no snapshot | Resolvido indiretamente por charge + `energy_clients`; não há chave direta em `energy_farms` |

Os instrumentos adicionais estão fortemente associados a vencimentos
reagendados, mas “cada linha adicional é uma reemissão” ainda é **HIPÓTESE**:
há exceções entre o contador e a quantidade de instrumentos.

## Papel na `generator_report`

A view:

1. renomeia `source` para `billing_id`;
2. usa `finance_relations` para localizar a charge, os boletos e os PIX;
3. leva `amount`, status, criação e vencimento para os dois ramos financeiros;
4. usa o valor da charge como `valor_emitido_brl`, e não o `amount` do billing;
5. não utiliza os campos `billing_expected_*`, `billing_paid_*`,
   `billing_payment_date`, descontos ou cancelamento do billing.

Há um risco estrutural confirmado: os ramos boleto e PIX produzem 2.105 e
2.107 linhas e são unidos com `UNION ALL`, totalizando 4.212 linhas para 2.000
billings antes das etapas seguintes. O impacto final precisa ser medido na
engenharia reversa da view, mas a multiplicação já é **FATO do SQL e das
cardinalidades**.

## Confirmado

- O billing é o nó central do subgrafo financeiro.
- `source` e `billing_id` são únicos e equivalentes após remoção do prefixo.
- Valores monetários estão em centavos.
- Existe uma charge por billing no snapshot.
- Existem pelo menos um boleto e um PIX por billing.
- Reagendamentos preservam instrumentos antigos, majoritariamente cancelados.
- Os campos de cancelamento do billing não são exercitados.

## Hipóteses

- `place_id` representa estabelecimento/local de consumo.
- `billing_energy_farm_id` é o ID da entidade usina no backend em grafo.
- Múltiplos instrumentos representam tentativas ou versões emitidas após
  reagendamento.
- A mudança de `billing_receiver_type` para `lemon` pode representar cobrança
  unificada; o snapshot não contém definição suficiente para provar isso.

## Questões abertas

1. Qual é a definição oficial de billing e sua diferença contratual para
   charge?
2. Qual campo determina a versão vigente após reagendamento?
3. Por que existem totais pagos diferentes dos esperados?
4. O que explica a linha cuja soma de principal, juros e multa diverge do total?
5. Qual sistema produz `ingestion_time`?
6. `billing_energy_farm_id` possui uma dimensão mestre não fornecida no case?
