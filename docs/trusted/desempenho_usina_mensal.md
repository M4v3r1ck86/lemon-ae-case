# Trusted — `desempenho_usina_mensal`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.desempenho_usina_mensal` |
| Origem(ns) | `trusted.usina_energia_mensal`, `trusted.cliente_energia_mensal`, `trusted.faturamento_cliente_mensal` |
| Grain | uma linha por `gerador + usina + cod_distribuidora + dt_mes_referencia` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_mes_referencia` |
| Clusterização | `gerador, usina, cod_distribuidora` |

## Descrição funcional

Consolida geração, clientes e resultados financeiros no nível mensal da usina e calcula indicadores reutilizáveis de desempenho.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `trusted.usina_energia_mensal.gerador` | `gerador` | `STRING` | `STRING` | Sim | Herdado/integrado | Nome ou identificador funcional do gerador responsável pela usina. | `trusted.usina_energia_mensal.gerador` |
| `trusted.usina_energia_mensal.usina` | `usina` | `STRING` | `STRING` | Sim | Herdado/integrado | Nome ou identificador funcional da usina de energia. | `trusted.usina_energia_mensal.usina` |
| `trusted.usina_energia_mensal.cod_distribuidora` | `cod_distribuidora` | `STRING` | `STRING` | Sim | Herdado/integrado | Código ou nome padronizado da distribuidora de energia. | `trusted.usina_energia_mensal.cod_distribuidora` |
| `trusted.usina_energia_mensal.dt_mes_referencia` | `dt_mes_referencia` | `DATE` | `DATE` | Sim | Herdado/integrado | Mês de competência das métricas operacionais, energéticas e financeiras da usina. | `trusted.usina_energia_mensal.dt_mes_referencia` |
| `COUNT(DISTINCT id_instalacao) por usina/mês` | `qtd_instalacoes` | `—` | `INT64` | Não | Calculado/derivado | Quantidade de instalações de clientes associadas à usina na competência. | `COUNT(DISTINCT id_instalacao)` por usina/mês |
| `COUNTIF(flg_emitido) por usina/mês` | `qtd_faturamentos_emitidos` | `—` | `INT64` | Não | Calculado/derivado | Quantidade de faturamentos emitidos para instalações da usina na competência. | `COUNTIF(flg_emitido)` por usina/mês |
| `COUNTIF(flg_pago) por usina/mês` | `qtd_faturamentos_pagos` | `—` | `INT64` | Não | Calculado/derivado | Quantidade de faturamentos pagos para instalações da usina na competência. | `COUNTIF(flg_pago)` por usina/mês |
| `COUNTIF(flg_multiplos_instrumentos_pagos) por usina/mês` | `qtd_faturamentos_multiplos_instrumentos_pagos` | `—` | `INT64` | Não | Calculado/derivado | Quantidade de faturamentos da usina com mais de um instrumento marcado como pago. | `COUNTIF(flg_multiplos_instrumentos_pagos)` por usina/mês |
| `trusted.usina_energia_mensal.qtd_creditos_injetados_kwh` | `qtd_creditos_injetados_kwh` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Quantidade de créditos de energia injetados na rede da distribuidora, em kWh. | `trusted.usina_energia_mensal.qtd_creditos_injetados_kwh` |
| `trusted.usina_energia_mensal.qtd_geracao_prevista_contrato_kwh` | `qtd_geracao_prevista_contrato_kwh` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Quantidade de geração prevista contratualmente para a usina, em kWh. | `trusted.usina_energia_mensal.qtd_geracao_prevista_contrato_kwh` |
| `trusted.usina_energia_mensal.qtd_geracao_realizada_gerador_kwh` | `qtd_geracao_realizada_gerador_kwh` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Quantidade de energia registrada como gerada pela usina, em kWh. | `trusted.usina_energia_mensal.qtd_geracao_realizada_gerador_kwh` |
| `LEAST(qtd_creditos_injetados_kwh, qtd_geracao_prevista_contrato_kwh)` | `qtd_minima_injecao_kwh` | `—` | `NUMERIC` | Não | Calculado/derivado | Menor valor entre créditos injetados e geração prevista no contrato, em kWh. | `LEAST(qtd_creditos_injetados_kwh, qtd_geracao_prevista_contrato_kwh)` |
| `SUM(qtd_creditos_recebidos_mes_kwh)` | `qtd_creditos_recebidos_kwh` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Quantidade de créditos recebidos pelas instalações vinculadas à usina na competência, em kWh. | `SUM(qtd_creditos_recebidos_mes_kwh)` |
| `SUM(qtd_creditos_faturados_kwh)` | `qtd_creditos_faturados_kwh` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Quantidade de créditos faturados pelas instalações vinculadas à usina na competência, em kWh. | `SUM(qtd_creditos_faturados_kwh)` |
| `SUM(qtd_creditos_faturados_pagos_kwh)` | `qtd_creditos_faturados_pagos_kwh` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Quantidade de créditos faturados associada a faturamentos pagos das instalações da usina, em kWh. | `SUM(qtd_creditos_faturados_pagos_kwh)` |
| `SUM(vlr_gmv_real_oficial_brl)` | `vlr_gmv_real_oficial_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma do GMV real oficial das instalações vinculadas à usina na competência, em reais. | `SUM(vlr_gmv_real_oficial_brl)` |
| `SUM(vlr_gmv_gerador_brl)` | `vlr_gmv_gerador_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma da parcela de GMV atribuída ao gerador para as instalações da usina, em reais. | `SUM(vlr_gmv_gerador_brl)` |
| `SUM(IF(flg_emitido, vlr_gmv_gerador_brl, 0))` | `vlr_cobranca_gerador_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma do GMV do gerador somente para instalações com faturamento emitido na competência, em reais. | `SUM(IF(flg_emitido, vlr_gmv_gerador_brl, 0))` |
| `SUM(COALESCE(vlr_cobranca_brl, 0))` | `vlr_cobranca_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma dos valores nominais das cobranças das instalações da usina, em reais. | `SUM(COALESCE(vlr_cobranca_brl, 0))` |
| `SUM(COALESCE(vlr_faturamento_brl, 0))` | `vlr_faturamento_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma dos valores nominais dos faturamentos das instalações da usina, em reais. | `SUM(COALESCE(vlr_faturamento_brl, 0))` |
| `SUM(COALESCE(vlr_total_pago_brl, 0))` | `vlr_total_pago_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma dos valores totais pagos, incluindo multa e juros, em reais. | `SUM(COALESCE(vlr_total_pago_brl, 0))` |
| `SUM(COALESCE(vlr_principal_pago_brl, 0))` | `vlr_principal_pago_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma dos valores pagos excluindo multa e juros, em reais. | `SUM(COALESCE(vlr_principal_pago_brl, 0))` |
| `Soma de (vlr_principal_pago_brl / vlr_faturamento_brl) * vlr_gmv_gerador_brl` | `vlr_liquidado_gerador_brl` | `—` | `NUMERIC` | Não | Calculado/derivado | Parcela do principal pago atribuída ao gerador proporcionalmente ao GMV do gerador, em reais. | Soma de `(vlr_principal_pago_brl / vlr_faturamento_brl) * vlr_gmv_gerador_brl` |
| `SUM(COALESCE(vlr_juros_pago_brl, 0))` | `vlr_juros_pago_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma dos valores de juros pagos, em reais. | `SUM(COALESCE(vlr_juros_pago_brl, 0))` |
| `SUM(COALESCE(vlr_multa_paga_brl, 0))` | `vlr_multa_paga_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Soma dos valores de multas pagas, em reais. | `SUM(COALESCE(vlr_multa_paga_brl, 0))` |
| `trusted.usina_energia_mensal.vlr_tusd_brl` | `vlr_tusd_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor monetário registrado na origem como TUSD para a usina, em reais. | `trusted.usina_energia_mensal.vlr_tusd_brl` |
| `trusted.usina_energia_mensal.dt_mes_desconto_tusd_gerador` | `dt_mes_desconto_tusd_gerador` | `DATE` | `DATE` | Não | Herdado/integrado | Mês de competência em que a TUSD deve ser deduzida do repasse do gerador. | `trusted.usina_energia_mensal.dt_mes_desconto_tusd_gerador` |
| `trusted.usina_energia_mensal.vlr_tusd_descontada_gerador_brl` | `vlr_tusd_descontada_gerador_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de TUSD deduzido do repasse do gerador, em reais. | `trusted.usina_energia_mensal.vlr_tusd_descontada_gerador_brl` |
| `trusted.usina_energia_mensal.vlr_aluguel_imoveis_brl` | `vlr_aluguel_imoveis_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de aluguel de imóveis associado à usina, em reais. | `trusted.usina_energia_mensal.vlr_aluguel_imoveis_brl` |
| `trusted.usina_energia_mensal.vlr_aluguel_equipamento_brl` | `vlr_aluguel_equipamento_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de aluguel de equipamentos associado à usina, em reais. | `trusted.usina_energia_mensal.vlr_aluguel_equipamento_brl` |
| `trusted.usina_energia_mensal.vlr_operacao_manutencao_brl` | `vlr_operacao_manutencao_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de custos de operação e manutenção associado à usina, em reais. | `trusted.usina_energia_mensal.vlr_operacao_manutencao_brl` |
| `SAFE_DIVIDE(qtd_creditos_injetados_kwh, qtd_geracao_prevista_contrato_kwh)` | `perc_injetado_vs_previsto` | `—` | `NUMERIC` | Não | Calculado/derivado | Razão entre créditos injetados e geração prevista no contrato. | `SAFE_DIVIDE(qtd_creditos_injetados_kwh, qtd_geracao_prevista_contrato_kwh)` |
| `SAFE_DIVIDE(qtd_creditos_injetados_kwh, qtd_geracao_realizada_gerador_kwh)` | `perc_distribuidora_vs_inversor` | `—` | `NUMERIC` | Não | Calculado/derivado | Razão entre créditos injetados e geração realizada pelo gerador. | `SAFE_DIVIDE(qtd_creditos_injetados_kwh, qtd_geracao_realizada_gerador_kwh)` |
| `SAFE_DIVIDE(qtd_creditos_recebidos_kwh, qtd_creditos_injetados_kwh)` | `perc_recebidos_vs_injetados` | `—` | `NUMERIC` | Não | Calculado/derivado | Razão entre créditos recebidos pelos clientes e créditos injetados pela usina. | `SAFE_DIVIDE(qtd_creditos_recebidos_kwh, qtd_creditos_injetados_kwh)` |
| `SAFE_DIVIDE(qtd_creditos_faturados_kwh, qtd_creditos_recebidos_kwh)` | `perc_faturados_vs_recebidos` | `—` | `NUMERIC` | Não | Calculado/derivado | Razão entre créditos faturados e créditos recebidos pelas instalações da usina. | `SAFE_DIVIDE(qtd_creditos_faturados_kwh, qtd_creditos_recebidos_kwh)` |
| `SAFE_DIVIDE(qtd_creditos_faturados_kwh, qtd_minima_injecao_kwh)` | `perc_preenchimento_usina` | `—` | `NUMERIC` | Não | Calculado/derivado | Razão entre créditos faturados e a quantidade mínima de injeção da usina. | `SAFE_DIVIDE(qtd_creditos_faturados_kwh, qtd_minima_injecao_kwh)` |
| `SAFE_DIVIDE(qtd_creditos_faturados_pagos_kwh, qtd_minima_injecao_kwh)` | `perc_desempenho_lemon` | `—` | `NUMERIC` | Não | Calculado/derivado | Razão entre créditos faturados pagos e a quantidade mínima de injeção da usina. | `SAFE_DIVIDE(qtd_creditos_faturados_pagos_kwh, qtd_minima_injecao_kwh)` |
| `Existe agregação correspondente em trusted.cliente_energia_mensal` | `flg_possui_clientes` | `—` | `BOOL` | Não | Calculado/derivado | Indica que a usina possui instalações de clientes associadas na competência. | Existe agregação correspondente em `trusted.cliente_energia_mensal` |
| `Quantidade de faturamentos emitidos maior que zero` | `flg_possui_faturamento` | `—` | `BOOL` | Não | Calculado/derivado | Indica que a usina possui pelo menos um faturamento emitido na competência. | Quantidade de faturamentos emitidos maior que zero |
| `Maior timestamp de ingestão entre as três entradas` | `ingerido_em` | `—` | `TIMESTAMP` | Não | Calculado/derivado | Data e hora mais recente de ingestão entre os registros utilizados na composição da linha. | Maior timestamp de ingestão entre as três entradas |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `gerador + usina + cod_distribuidora + dt_mes_referencia`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_desempenho_usina_mensal.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_desempenho_usina_mensal.sql`
