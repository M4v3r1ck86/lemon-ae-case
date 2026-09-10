# Trusted — `usina_energia_mensal`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.usina_energia_mensal` |
| Origem(ns) | `raw.energy_farms` |
| Grain | uma linha por `usina + dt_mes_referencia` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_mes_referencia` |
| Clusterização | `gerador, usina, cod_distribuidora` |

## Descrição funcional

Normaliza medições mensais, geração, créditos e custos operacionais das usinas.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `usina` | `usina` | `STRING` | `STRING` | Sim | Normalizado | Nome ou identificador funcional da usina de energia. | `NULLIF(TRIM(usina), '')` |
| `mes_referencia` | `dt_mes_referencia` | `STRING` | `DATE` | Sim | Normalizado | Mês de competência das medições operacionais da usina. | `SAFE_CAST(NULLIF(TRIM(mes_referencia), '') AS DATE)` |
| `gerador` | `gerador` | `STRING` | `STRING` | Sim | Normalizado | Nome ou identificador funcional do gerador responsável pela usina. | `NULLIF(TRIM(gerador), '')` |
| `disco` | `cod_distribuidora` | `STRING` | `STRING` | Sim | Normalizado | Código ou nome padronizado da distribuidora de energia. | `UPPER(NULLIF(TRIM(disco), ''))` |
| `creditos_injetados_k_wh` | `qtd_creditos_injetados_kwh` | `INT64` | `NUMERIC` | Não | Normalizado | Quantidade de créditos de energia injetados na rede da distribuidora, em kWh. | `SAFE_CAST(creditos_injetados_k_wh AS NUMERIC)` |
| `geracao_prevista_no_contrato_k_wh` | `qtd_geracao_prevista_contrato_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Quantidade de geração prevista contratualmente para a usina, em kWh. | `SAFE_CAST(geracao_prevista_no_contrato_k_wh AS NUMERIC)` |
| `geracao_realizada_gerador_k_wh` | `qtd_geracao_realizada_gerador_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Quantidade de energia registrada como gerada pela usina, em kWh. | `SAFE_CAST(geracao_realizada_gerador_k_wh AS NUMERIC)` |
| `tusd_brl` | `vlr_tusd_brl` | `tusd_descontada_gerador` | `NUMERIC` | Não | Normalizado | Valor monetário registrado na origem como Tarifa de Uso do Sistema de Distribuição, em reais. | `SAFE_CAST(tusd_brl AS NUMERIC)` |
| `mes_de_desconto_tusd_gerador` | `dt_mes_desconto_tusd_gerador` | `STRING` | `DATE` | Não | Normalizado | Mês de competência em que a TUSD deve ser deduzida do repasse do gerador. | `SAFE_CAST(NULLIF(TRIM(mes_de_desconto_tusd_gerador), '') AS DATE)` |
| `aluguel_imoveis_brl` | `vlr_aluguel_imoveis_brl` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor de aluguel de imóveis associado à usina, em reais. | `SAFE_CAST(aluguel_imoveis_brl AS NUMERIC)` |
| `aluguel_equipamento_brl` | `vlr_aluguel_equipamento_brl` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor de aluguel de equipamentos associado à usina, em reais. | `SAFE_CAST(aluguel_equipamento_brl AS NUMERIC)` |
| `operations_and_maintenance_cost_brl` | `vlr_operacao_manutencao_brl` | `STRING` | `NUMERIC` | Não | Normalizado | Valor de custos de operação e manutenção associado à usina, em reais. | `SAFE_CAST(NULLIF(TRIM(operations_and_maintenance_cost_brl), '') AS NUMERIC)` |
| `tusd_descontada_gerador` | `vlr_tusd_descontada_gerador_brl` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor de TUSD deduzido do repasse do gerador, em reais. | `SAFE_CAST(tusd_descontada_gerador AS NUMERIC)` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `usina + dt_mes_referencia`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_usina_energia_mensal.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_usina_energia_mensal.sql`
