# Trusted — `cliente_energia_mensal`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.cliente_energia_mensal` |
| Origem(ns) | `raw.energy_clients` |
| Grain | uma linha por `id_instalacao + dt_mes_referencia` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_mes_referencia` |
| Clusterização | `gerador, usina, cod_distribuidora` |

## Descrição funcional

Normaliza o snapshot mensal de energia por instalação, incluindo saldos, créditos, componentes econômicos e estado operacional.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `numero_instalacao` | `id_instalacao` | `STRING` | `STRING` | Sim | Normalizado | Identificador da instalação ou unidade consumidora de energia. | `NULLIF(TRIM(numero_instalacao), '')` |
| `mes_referencia` | `dt_mes_referencia` | `STRING` | `DATE` | Sim | Normalizado | Mês de competência ao qual os dados energéticos e financeiros da instalação se referem. | `SAFE_CAST(NULLIF(TRIM(mes_referencia), '') AS DATE)` |
| `usina` | `usina` | `STRING` | `STRING` | Não | Normalizado | Nome ou identificador funcional da usina associada à instalação na competência. | `NULLIF(TRIM(usina), '')` |
| `gerador` | `gerador` | `STRING` | `STRING` | Não | Normalizado | Nome ou identificador funcional do gerador associado à instalação na competência. | `NULLIF(TRIM(gerador), '')` |
| `disco` | `cod_distribuidora` | `STRING` | `STRING` | Não | Normalizado | Código ou nome padronizado da distribuidora de energia responsável pela instalação. | `UPPER(NULLIF(TRIM(disco), ''))` |
| `saldo_bop_k_wh` | `saldo_bop_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Saldo de créditos de energia, em kWh, existente no início da competência. | `SAFE_CAST(saldo_bop_k_wh AS NUMERIC)` |
| `saldo_eop_k_wh` | `saldo_eop_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Saldo de créditos de energia, em kWh, remanescente no final da competência. | `SAFE_CAST(saldo_eop_k_wh AS NUMERIC)` |
| `churn_k_wh` | `qtd_churn_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Quantidade de energia, em kWh, associada a movimentações classificadas como churn pela fonte. | `SAFE_CAST(churn_k_wh AS NUMERIC)` |
| `creditos_recebidos_no_mes_k_wh` | `qtd_creditos_recebidos_mes_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Quantidade de créditos de energia, em kWh, recebidos durante a competência. | `SAFE_CAST(creditos_recebidos_no_mes_k_wh AS NUMERIC)` |
| `creditos_recebidos_de_meses_anteriores_k_wh` | `qtd_creditos_recebidos_meses_anteriores_kwh` | `INT64` | `NUMERIC` | Não | Normalizado | Quantidade de créditos de energia, em kWh, recebidos e atribuídos a competências anteriores. | `SAFE_CAST(creditos_recebidos_de_meses_anteriores_k_wh AS NUMERIC)` |
| `creditos_faturados_k_wh` | `qtd_creditos_faturados_kwh` | `INT64` | `NUMERIC` | Não | Normalizado | Quantidade de créditos de energia, em kWh, considerada no faturamento da competência. | `SAFE_CAST(creditos_faturados_k_wh AS NUMERIC)` |
| `creditos_compensados_do_mes_k_wh` | `qtd_creditos_compensados_mes_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Quantidade de créditos de energia, em kWh, compensada na competência; valores negativos da fonte são preservados. | `SAFE_CAST(creditos_compensados_do_mes_k_wh AS NUMERIC)` |
| `creditos_compensados_de_meses_anteriores_k_wh` | `qtd_creditos_compensados_meses_anteriores_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Quantidade de créditos de energia, em kWh, compensada e atribuída a competências anteriores. | `SAFE_CAST(creditos_compensados_de_meses_anteriores_k_wh AS NUMERIC)` |
| `desconto_cliente_percentage` | `perc_desconto_cliente` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Percentual decimal de desconto associado ao cliente na competência, preservando a escala registrada pela fonte. | `SAFE_CAST(desconto_cliente_percentage AS NUMERIC)` |
| `desconto_gerador_percentage` | `perc_desconto_gerador` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Percentual decimal de desconto associado ao gerador na competência, preservando a escala registrada pela fonte. | `SAFE_CAST(desconto_gerador_percentage AS NUMERIC)` |
| `gmv_real_oficial_brl` | `vlr_gmv_real_oficial_brl` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor oficial do GMV real da instalação na competência, expresso em reais. | `SAFE_CAST(gmv_real_oficial_brl AS NUMERIC)` |
| `gmv_gerador_brl` | `vlr_gmv_gerador_brl` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Parcela do GMV atribuída ao gerador na competência, expressa em reais. | `SAFE_CAST(gmv_gerador_brl AS NUMERIC)` |
| `take_rate_lemon_brl` | `vlr_take_rate_lemon_brl` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor de take rate atribuído à Lemon na competência, expresso em reais. | `SAFE_CAST(take_rate_lemon_brl AS NUMERIC)` |
| `tarifa_de_saida_brl_per_k_wh` | `vlr_tarifa_saida_brl_por_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor da tarifa de saída aplicado à energia, expresso em reais por kWh. | `SAFE_CAST(tarifa_de_saida_brl_per_k_wh AS NUMERIC)` |
| `pis_per_cofins_nao_compensado_lemon_brl_k_wh` | `vlr_pis_cofins_nao_compensado_lemon_brl_por_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor de PIS e COFINS não compensado pela Lemon, expresso em reais por kWh. | `SAFE_CAST(pis_per_cofins_nao_compensado_lemon_brl_k_wh AS NUMERIC)` |
| `icms_nao_compensado_lemon_brl_per_k_wh` | `vlr_icms_nao_compensado_lemon_brl_por_kwh` | `INT64` | `NUMERIC` | Não | Normalizado | Valor de ICMS não compensado pela Lemon, expresso em reais por kWh. | `SAFE_CAST(icms_nao_compensado_lemon_brl_per_k_wh AS NUMERIC)` |
| `ajuste_custo_disp_gerador_brl` | `vlr_ajuste_custo_disponibilidade_gerador_brl` | `INT64` | `NUMERIC` | Não | Normalizado | Valor do ajuste relacionado ao custo de disponibilidade atribuído ao gerador, expresso em reais. | `SAFE_CAST(ajuste_custo_disp_gerador_brl AS NUMERIC)` |
| `desconto_gerador_brl_per_k_wh` | `vlr_desconto_gerador_brl_por_kwh` | `FLOAT64` | `NUMERIC` | Não | Normalizado | Valor unitário do desconto associado ao gerador, expresso em reais por kWh. | `SAFE_CAST(desconto_gerador_brl_per_k_wh AS NUMERIC)` |
| `etapa` | `etapa_processamento` | `STRING` | `STRING` | Não | Normalizado | Etapa operacional informada pela fonte para o registro da instalação na competência. | `NULLIF(TRIM(etapa), '')` |
| `status` | `status_processamento` | `STRING` | `STRING` | Não | Normalizado | Status operacional informado pela fonte para o registro da instalação na competência. | `NULLIF(TRIM(status), '')` |
| `excecoes` | `txt_excecoes` | `STRING` | `STRING` | Não | Normalizado | Texto livre com exceções ou observações operacionais informadas pela fonte. | `NULLIF(NULLIF(TRIM(excecoes), ''), '-')` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `id_instalacao + dt_mes_referencia`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_cliente_energia_mensal.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_cliente_energia_mensal.sql`
