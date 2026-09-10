# Trusted — `boleto`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.boleto` |
| Origem(ns) | `raw.finance_boletos` |
| Grain | uma linha por `id_boleto` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_vencimento` |
| Clusterização | `status_boleto, id_local, tipo_recebedor` |

## Descrição funcional

Normaliza boletos financeiros, datas, status, recebedor e valores monetários convertidos de centavos para reais.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `bank_slip_id` | `id_boleto` | `INT64` | `INT64` | Sim | Normalizado | Identificador técnico do instrumento de pagamento boleto. | `SAFE_CAST(bank_slip_id AS INT64)` |
| `source` | `id_grafo_boleto` | `STRING` | `STRING` | Sim | Normalizado | Identificador completo do nó de boleto usado no grafo financeiro. | `NULLIF(TRIM(source), '')` |
| `place_id` | `id_local` | `STRING` | `STRING` | Sim | Normalizado | Identificador do local ou estabelecimento associado ao boleto. | `NULLIF(TRIM(place_id), '')` |
| `status` | `status_boleto` | `STRING` | `STRING` | Não | Normalizado | Status operacional do instrumento de pagamento boleto. | `NULLIF(TRIM(status), '')` |
| `create_at` | `ts_criado_em` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de criação ou emissão do boleto. | `SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP)` |
| `due_date` | `dt_vencimento` | `STRING` | `DATE` | Não | Normalizado | Data de vencimento do boleto. | `SAFE_CAST(NULLIF(TRIM(due_date), '') AS DATE)` |
| `payment_date` | `dt_pagamento` | `STRING` | `DATE` | Não | Normalizado | Data de liquidação do boleto; nula quando não há pagamento. | `SAFE_CAST(NULLIF(TRIM(payment_date), '') AS DATE)` |
| `amount` | `vlr_boleto_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor nominal do boleto convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100)` |
| `our_number` | `num_nosso_numero` | `INT64` | `INT64` | Não | Normalizado | Identificador bancário conhecido como Nosso Número. | `SAFE_CAST(our_number AS INT64)` |
| `receiver_name` | `nome_recebedor` | `STRING` | `STRING` | Não | Normalizado | Nome do recebedor associado ao boleto. | `NULLIF(TRIM(receiver_name), '')` |
| `receiver_id` | `id_recebedor` | `STRING` | `STRING` | Não | Normalizado | Identificador da entidade ou conta recebedora. | `NULLIF(TRIM(receiver_id), '')` |
| `receiver_type` | `tipo_recebedor` | `STRING` | `STRING` | Não | Normalizado | Tipo da entidade recebedora do boleto. | `NULLIF(TRIM(receiver_type), '')` |
| `bank_slip_expected_total` | `vlr_total_esperado_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor total esperado no pagamento, incluindo encargos, convertido para reais. | `SAFE_DIVIDE(SAFE_CAST(bank_slip_expected_total AS NUMERIC), 100)` |
| `bank_slip_expected_interest` | `vlr_juros_esperado_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de juros esperado, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(bank_slip_expected_interest AS NUMERIC), 100)` |
| `bank_slip_expected_fine` | `vlr_multa_esperada_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de multa esperada, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(bank_slip_expected_fine AS NUMERIC), 100)` |
| `bank_slip_paid_total` | `vlr_total_pago_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor total efetivamente pago, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(bank_slip_paid_total AS NUMERIC), 100)` |
| `bank_slip_paid_interest` | `vlr_juros_pago_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de juros efetivamente pago, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(bank_slip_paid_interest AS NUMERIC), 100)` |
| `bank_slip_paid_fine` | `vlr_multa_paga_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de multa efetivamente paga, convertido de centavos para reais. | `SAFE_DIVIDE(SAFE_CAST(bank_slip_paid_fine AS NUMERIC), 100)` |
| `ingestion_time` | `ts_ingestao_origem` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de ingestão informada pelo sistema financeiro de origem. | `SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP)` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `id_boleto`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_boleto.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_boleto.sql`
