# Trusted — `cobranca`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.cobranca` |
| Origem(ns) | `raw.finance_charges` |
| Grain | uma linha por `id_cobranca` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_mes_referencia` |
| Clusterização | `id_instalacao, status_cobranca, cod_distribuidora` |

## Descrição funcional

Normaliza cobranças por instalação e competência, com vínculos de faturamento, valores, pagamento e cancelamento.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `charge_id` | `id_cobranca` | `STRING` | `STRING` | Sim | Normalizado | Identificador técnico da cobrança sem o prefixo de entidade. | `NULLIF(TRIM(charge_id), '')` |
| `source` | `id_grafo_cobranca` | `STRING` | `STRING` | Sim | Normalizado | Identificador completo do nó de cobrança usado no grafo financeiro. | `NULLIF(TRIM(source), '')` |
| `billing_id` | `id_faturamento` | `STRING` | `STRING` | Sim | Normalizado | Identificador do faturamento relacionado à cobrança. | `NULLIF(TRIM(billing_id), '')` |
| `billing_plan_id` | `id_plano_faturamento` | `STRING` | `STRING` | Não | Normalizado | Identificador do plano de faturamento associado à cobrança. | `NULLIF(TRIM(billing_plan_id), '')` |
| `place_id` | `id_local` | `STRING` | `STRING` | Sim | Normalizado | Identificador do local ou estabelecimento associado à cobrança. | `NULLIF(TRIM(place_id), '')` |
| `disco_consumer_unit_id` | `id_instalacao` | `STRING` | `STRING` | Sim | Normalizado | Identificador da instalação ou unidade consumidora na distribuidora. | `NULLIF(TRIM(disco_consumer_unit_id), '')` |
| `distribution_company` | `cod_distribuidora` | `STRING` | `STRING` | Não | Normalizado | Código ou nome padronizado da distribuidora de energia. | `UPPER(NULLIF(TRIM(distribution_company), ''))` |
| `reference_month` | `dt_mes_referencia` | `STRING` | `DATE` | Sim | Normalizado | Mês de competência da cobrança. | `SAFE_CAST(NULLIF(TRIM(reference_month), '') AS DATE)` |
| `pipedrive_id` | `id_pipedrive` | `INT64` | `INT64` | Não | Normalizado | Identificador externo da cobrança no Pipedrive. | `SAFE_CAST(pipedrive_id AS INT64)` |
| `product` | `produto` | `STRING` | `STRING` | Não | Normalizado | Produto associado à cobrança. | `NULLIF(TRIM(product), '')` |
| `charge_provider_type` | `tipo_provedor_cobranca` | `STRING` | `STRING` | Não | Normalizado | Tipo do provedor responsável pela cobrança. | `NULLIF(TRIM(charge_provider_type), '')` |
| `status` | `status_cobranca` | `STRING` | `STRING` | Não | Normalizado | Status operacional da cobrança. | `NULLIF(TRIM(status), '')` |
| `subscriber_id` | `id_assinante` | `STRING` | `STRING` | Não | Normalizado | Identificador do assinante ou entidade consumidora. | `NULLIF(TRIM(subscriber_id), '')` |
| `subscriber_type` | `tipo_assinante` | `STRING` | `STRING` | Não | Normalizado | Tipo do assinante associado à cobrança. | `NULLIF(TRIM(subscriber_type), '')` |
| `type` | `tipo_cobranca` | `STRING` | `STRING` | Não | Normalizado | Categoria operacional da cobrança. | `NULLIF(TRIM(type), '')` |
| `subscription_id` | `id_assinatura` | `STRING` | `STRING` | Não | Normalizado | Identificador da assinatura associada à cobrança. | `NULLIF(TRIM(subscription_id), '')` |
| `create_at` | `ts_criado_em` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de criação da cobrança. | `SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP)` |
| `payment_date` | `dt_pagamento` | `STRING` | `DATE` | Não | Normalizado | Data de pagamento utilizada como data de liquidação da cobrança. | `SAFE_CAST(NULLIF(TRIM(payment_date), '') AS DATE)` |
| `amount` | `vlr_cobranca_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor nominal da cobrança convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100)` |
| `amount_without_discounts` | `vlr_sem_descontos_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor da cobrança antes de descontos, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(amount_without_discounts AS NUMERIC), 100)` |
| `temporary_discount_amount` | `vlr_desconto_temporario_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de desconto temporário, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(temporary_discount_amount AS NUMERIC), 100)` |
| `cancelled_at` | `ts_cancelamento` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de cancelamento da cobrança. | `SAFE_CAST(NULLIF(TRIM(cancelled_at), '') AS TIMESTAMP)` |
| `cancellation_reason` | `motivo_cancelamento` | `STRING` | `STRING` | Não | Normalizado | Motivo informado para o cancelamento da cobrança. | `NULLIF(TRIM(cancellation_reason), '')` |
| `cancellation_type` | `tipo_cancelamento` | `STRING` | `STRING` | Não | Normalizado | Categoria informada para o cancelamento da cobrança. | `NULLIF(TRIM(cancellation_type), '')` |
| `cancelled_by` | `cancelado_por` | `STRING` | `STRING` | Não | Normalizado | Identificador do responsável pelo cancelamento. | `NULLIF(TRIM(cancelled_by), '')` |
| `cancellation_description` | `descricao_cancelamento` | `STRING` | `STRING` | Não | Normalizado | Descrição textual do cancelamento. | `NULLIF(TRIM(cancellation_description), '')` |
| `ingestion_time` | `ts_ingestao_origem` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de ingestão informada pelo sistema financeiro de origem. | `SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP)` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `id_cobranca`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_cobranca.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_cobranca.sql`
