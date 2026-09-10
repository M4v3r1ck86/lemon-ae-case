# Trusted — `faturamento`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.faturamento` |
| Origem(ns) | `raw.finance_billings` |
| Grain | uma linha por `id_faturamento` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `DATE(ts_criado_em)` |
| Clusterização | `status_faturamento, id_local, tipo_recebedor` |

## Descrição funcional

Normaliza faturamentos financeiros, vencimentos, pagamentos, reagendamentos, cancelamentos e valores.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `billing_id` | `id_faturamento` | `finance_charges.billing_id` | `STRING` | Sim | Normalizado | Identificador técnico do faturamento sem o prefixo de entidade. | `NULLIF(TRIM(billing_id), '')` |
| `source` | `id_grafo_faturamento` | `STRING` | `STRING` | Sim | Normalizado | Identificador completo do nó de faturamento usado no grafo financeiro. | `NULLIF(TRIM(source), '')` |
| `place_id` | `id_local` | `STRING` | `STRING` | Sim | Normalizado | Identificador do local ou estabelecimento associado ao faturamento. | `NULLIF(TRIM(place_id), '')` |
| `billing_energy_farm_id` | `id_usina_backend` | `STRING` | `STRING` | Não | Normalizado | Identificador de usina utilizado pelo backend financeiro. | `NULLIF(TRIM(billing_energy_farm_id), '')` |
| `status` | `status_faturamento` | `STRING` | `STRING` | Não | Normalizado | Status operacional do faturamento. | `NULLIF(TRIM(status), '')` |
| `amount` | `vlr_faturamento_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor nominal do faturamento convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100)` |
| `amount_without_discounts` | `vlr_sem_descontos_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor do faturamento antes de descontos, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(amount_without_discounts AS NUMERIC), 100)` |
| `temporary_discount_amount` | `vlr_desconto_temporario_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de desconto temporário, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(temporary_discount_amount AS NUMERIC), 100)` |
| `create_at` | `ts_criado_em` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de criação do faturamento. | `SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP)` |
| `due_date` | `dt_vencimento` | `STRING` | `DATE` | Não | Normalizado | Data de vencimento vigente do faturamento. | `SAFE_CAST(NULLIF(TRIM(due_date), '') AS DATE)` |
| `original_due_date` | `dt_vencimento_original` | `STRING` | `DATE` | Não | Normalizado | Data de vencimento original do faturamento. | `SAFE_CAST(NULLIF(TRIM(original_due_date), '') AS DATE)` |
| `billing_payment_date` | `ts_pagamento` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de pagamento registrada no nível do faturamento. | `SAFE_CAST(NULLIF(TRIM(billing_payment_date), '') AS TIMESTAMP)` |
| `billing_rescheduled_times` | `qtd_reagendamentos` | `INT64` | `INT64` | Não | Normalizado | Quantidade de reagendamentos registrada para o faturamento. | `SAFE_CAST(billing_rescheduled_times AS INT64)` |
| `cancelled_at` | `ts_cancelamento` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de cancelamento do faturamento. | `SAFE_CAST(NULLIF(TRIM(cancelled_at), '') AS TIMESTAMP)` |
| `cancellation_reason` | `motivo_cancelamento` | `STRING` | `STRING` | Não | Normalizado | Motivo informado para o cancelamento do faturamento. | `NULLIF(TRIM(cancellation_reason), '')` |
| `cancellation_type` | `tipo_cancelamento` | `STRING` | `STRING` | Não | Normalizado | Categoria informada para o cancelamento do faturamento. | `NULLIF(TRIM(cancellation_type), '')` |
| `cancelled_by` | `cancelado_por` | `STRING` | `STRING` | Não | Normalizado | Identificador do responsável pelo cancelamento. | `NULLIF(TRIM(cancelled_by), '')` |
| `cancellation_description` | `descricao_cancelamento` | `STRING` | `STRING` | Não | Normalizado | Descrição textual do cancelamento. | `NULLIF(TRIM(cancellation_description), '')` |
| `billing_expected_total` | `vlr_total_esperado_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor total esperado no recebimento, incluindo encargos, convertido para reais. | `SAFE_DIVIDE(SAFE_CAST(billing_expected_total AS NUMERIC), 100)` |
| `billing_expected_interest` | `vlr_juros_esperado_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de juros esperado, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(billing_expected_interest AS NUMERIC), 100)` |
| `billing_expected_fine` | `vlr_multa_esperada_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de multa esperado, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(billing_expected_fine AS NUMERIC), 100)` |
| `billing_paid_total` | `vlr_total_pago_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor total efetivamente pago, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(billing_paid_total AS NUMERIC), 100)` |
| `billing_paid_interest` | `vlr_juros_pago_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de juros efetivamente pago, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(billing_paid_interest AS NUMERIC), 100)` |
| `billing_paid_fine` | `vlr_multa_paga_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de multa efetivamente paga, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(billing_paid_fine AS NUMERIC), 100)` |
| `billing_receiver_id` | `id_recebedor` | `STRING` | `STRING` | Não | Normalizado | Identificador da entidade ou conta recebedora. | `NULLIF(TRIM(billing_receiver_id), '')` |
| `billing_receiver_type` | `tipo_recebedor` | `STRING` | `STRING` | Não | Normalizado | Tipo da entidade recebedora do faturamento. | `NULLIF(TRIM(billing_receiver_type), '')` |
| `ingestion_time` | `ts_ingestao_origem` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de ingestão informada pelo sistema financeiro de origem. | `SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP)` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `id_faturamento`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_faturamento.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_faturamento.sql`
