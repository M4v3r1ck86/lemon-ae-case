# Trusted — `pix`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.pix` |
| Origem(ns) | `raw.finance_pixs` |
| Grain | uma linha por `id_pix` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_vencimento` |
| Clusterização | `id_faturamento, status_pix, id_local` |

## Descrição funcional

Normaliza instrumentos PIX, datas, status, recebedor, código e valores convertidos de centavos para reais.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `pix_id` | `id_pix` | `STRING` | `STRING` | Sim | Normalizado | Identificador técnico do instrumento de pagamento PIX. | `NULLIF(TRIM(pix_id), '')` |
| `source` | `id_grafo_pix` | `STRING` | `STRING` | Sim | Normalizado | Identificador completo do nó PIX usado no grafo financeiro. | `NULLIF(TRIM(source), '')` |
| `billing_id` | `id_faturamento` | `STRING` | `STRING` | Sim | Normalizado | Identificador do faturamento relacionado ao PIX. | `NULLIF(TRIM(billing_id), '')` |
| `tx_id` | `id_transacao` | `STRING` | `STRING` | Não | Normalizado | Identificador transacional do PIX informado pela fonte. | `NULLIF(TRIM(tx_id), '')` |
| `place_id` | `id_local` | `STRING` | `STRING` | Sim | Normalizado | Identificador do local ou estabelecimento associado ao PIX. | `NULLIF(TRIM(place_id), '')` |
| `status` | `status_pix` | `STRING` | `STRING` | Não | Normalizado | Status operacional do instrumento de pagamento PIX. | `NULLIF(TRIM(status), '')` |
| `create_at` | `ts_criado_em` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de criação do PIX. | `SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP)` |
| `due_date` | `dt_vencimento` | `STRING` | `DATE` | Não | Normalizado | Data de vencimento do PIX. | `SAFE_CAST(NULLIF(TRIM(due_date), '') AS DATE)` |
| `payment_date` | `dt_pagamento` | `STRING` | `DATE` | Não | Normalizado | Data de liquidação do PIX; nula quando não há pagamento. | `SAFE_CAST(NULLIF(TRIM(payment_date), '') AS DATE)` |
| `amount` | `vlr_pix_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor nominal do PIX convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100)` |
| `receiver_id` | `id_recebedor` | `STRING` | `STRING` | Não | Normalizado | Identificador da entidade ou conta recebedora. | `NULLIF(TRIM(receiver_id), '')` |
| `receiver_type` | `tipo_recebedor` | `STRING` | `STRING` | Não | Normalizado | Tipo da entidade recebedora do PIX. | `NULLIF(TRIM(receiver_type), '')` |
| `pix_expected_total` | `vlr_total_esperado_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor total esperado no pagamento, incluindo encargos, convertido para reais. | `SAFE_DIVIDE(SAFE_CAST(pix_expected_total AS NUMERIC), 100)` |
| `pix_expected_interest` | `vlr_juros_esperado_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de juros esperado, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(pix_expected_interest AS NUMERIC), 100)` |
| `pix_expected_fine` | `vlr_multa_esperada_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de multa esperada, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(pix_expected_fine AS NUMERIC), 100)` |
| `pix_paid_total` | `vlr_total_pago_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor total efetivamente pago, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(pix_paid_total AS NUMERIC), 100)` |
| `pix_paid_interest` | `vlr_juros_pago_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de juros efetivamente pago, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(pix_paid_interest AS NUMERIC), 100)` |
| `pix_paid_fine` | `vlr_multa_paga_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de multa efetivamente paga, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(pix_paid_fine AS NUMERIC), 100)` |
| `pix_code` | `cod_pix` | `STRING` | `STRING` | Não | Normalizado | Código completo de pagamento ou payload do QR Code PIX; dado técnico de acesso restrito. | `NULLIF(TRIM(pix_code), '')` |
| `ingestion_time` | `ts_ingestao_origem` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de ingestão informada pelo sistema financeiro de origem. | `SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP)` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `id_pix`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_pix.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_pix.sql`
