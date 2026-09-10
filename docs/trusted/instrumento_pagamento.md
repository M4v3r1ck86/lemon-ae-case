# Trusted — `instrumento_pagamento`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.instrumento_pagamento` |
| Origem(ns) | `trusted.boleto`, `trusted.pix`, `trusted.relacao_financeira` |
| Grain | uma linha por `tipo_instrumento + id_instrumento` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_vencimento` |
| Clusterização | `id_faturamento, tipo_instrumento, status_instrumento` |

## Descrição funcional

Unifica boletos e PIX em um contrato comum, preservando cada instrumento emitido e seu vínculo com o faturamento.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `Literal 'boleto' ou 'pix', conforme a origem` | `tipo_instrumento` | `—` | `STRING` | Sim | Calculado/derivado | Tipo do instrumento de pagamento. Valores esperados: boleto ou pix. | Literal `'boleto'` ou `'pix'`, conforme a origem |
| `CAST(trusted.boleto.id_boleto AS STRING) ou trusted.pix.id_pix` | `id_instrumento` | `—` | `STRING` | Sim | Calculado/derivado | Identificador técnico do instrumento de pagamento sem o prefixo do grafo. | `CAST(trusted.boleto.id_boleto AS STRING)` ou `trusted.pix.id_pix` |
| `trusted.boleto.id_grafo_boleto ou trusted.pix.id_grafo_pix` | `id_grafo_instrumento` | `—` | `STRING` | Sim | Calculado/derivado | Identificador completo do instrumento utilizado no grafo financeiro. | `trusted.boleto.id_grafo_boleto` ou `trusted.pix.id_grafo_pix` |
| `trusted.relacao_financeira.id_origem para boleto; trusted.pix.id_faturamento para PIX` | `id_faturamento` | `—` | `STRING` | Sim | Calculado/derivado | Identificador do faturamento ao qual o instrumento de pagamento está vinculado. | `trusted.relacao_financeira.id_origem` para boleto; `trusted.pix.id_faturamento` para PIX |
| `trusted.boleto.id_local` | `id_local` | `STRING` | `STRING` | Sim | Herdado/integrado | Identificador do local ou estabelecimento associado ao instrumento de pagamento. | `trusted.boleto.id_local` |
| `trusted.boleto.status_boleto ou trusted.pix.status_pix` | `status_instrumento` | `—` | `STRING` | Não | Calculado/derivado | Status operacional do instrumento, como paid, cancelled ou waitingPayment. | `trusted.boleto.status_boleto` ou `trusted.pix.status_pix` |
| `trusted.boleto.ts_criado_em` | `ts_criado_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Herdado/integrado | Data e hora de criação ou emissão do instrumento de pagamento. | `trusted.boleto.ts_criado_em` |
| `trusted.boleto.dt_vencimento` | `dt_vencimento` | `DATE` | `DATE` | Não | Herdado/integrado | Data de vencimento do instrumento de pagamento. | `trusted.boleto.dt_vencimento` |
| `trusted.boleto.dt_pagamento` | `dt_pagamento` | `DATE` | `DATE` | Não | Herdado/integrado | Data de liquidação do instrumento; nula quando não existe pagamento registrado. | `trusted.boleto.dt_pagamento` |
| `trusted.boleto.vlr_boleto_brl ou trusted.pix.vlr_pix_brl` | `vlr_instrumento_brl` | `—` | `NUMERIC` | Não | Calculado/derivado | Valor nominal do instrumento de pagamento, em reais. | `trusted.boleto.vlr_boleto_brl` ou `trusted.pix.vlr_pix_brl` |
| `trusted.boleto.vlr_total_esperado_brl` | `vlr_total_esperado_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor total esperado no pagamento, incluindo multa e juros, em reais. | `trusted.boleto.vlr_total_esperado_brl` |
| `trusted.boleto.vlr_juros_esperado_brl` | `vlr_juros_esperado_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de juros esperado no pagamento do instrumento, em reais. | `trusted.boleto.vlr_juros_esperado_brl` |
| `trusted.boleto.vlr_multa_esperada_brl` | `vlr_multa_esperada_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de multa esperado no pagamento do instrumento, em reais. | `trusted.boleto.vlr_multa_esperada_brl` |
| `trusted.boleto.vlr_total_pago_brl` | `vlr_total_pago_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor total efetivamente registrado como pago, em reais. | `trusted.boleto.vlr_total_pago_brl` |
| `trusted.boleto.vlr_juros_pago_brl` | `vlr_juros_pago_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de juros efetivamente registrado como pago, em reais. | `trusted.boleto.vlr_juros_pago_brl` |
| `trusted.boleto.vlr_multa_paga_brl` | `vlr_multa_paga_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de multa efetivamente registrada como paga, em reais. | `trusted.boleto.vlr_multa_paga_brl` |
| `trusted.boleto.id_recebedor` | `id_recebedor` | `STRING` | `STRING` | Não | Herdado/integrado | Identificador da entidade ou conta recebedora do pagamento. | `trusted.boleto.id_recebedor` |
| `trusted.boleto.tipo_recebedor` | `tipo_recebedor` | `STRING` | `STRING` | Não | Herdado/integrado | Tipo da entidade recebedora do pagamento. | `trusted.boleto.tipo_recebedor` |
| `trusted.boleto.ts_ingestao_origem` | `ts_ingestao_origem` | `TIMESTAMP` | `TIMESTAMP` | Não | Herdado/integrado | Data e hora de ingestão informada pelo sistema financeiro de origem. | `trusted.boleto.ts_ingestao_origem` |
| `trusted.boleto.ingerido_em` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Herdado/integrado | Data e hora em que o registro original foi ingerido na camada Raw. | `trusted.boleto.ingerido_em` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `tipo_instrumento + id_instrumento`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_instrumento_pagamento.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_instrumento_pagamento.sql`
