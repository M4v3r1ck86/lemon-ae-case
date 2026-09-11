-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_DESEMPENHO_USINA_MENSAL
-- Grain: gerador + usina + cod_distribuidora + dt_mes_referencia.
-- Estratégia: agregações no grão da usina, integração e full refresh.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_desempenho_usina_mensal`()
BEGIN
  -- ETAPA 1 — CLIENTES POR USINA E MÊS
  CREATE TEMP TABLE tmp_clientes_por_usina AS
  SELECT
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_referencia,
    COUNT(DISTINCT id_instalacao) AS qtd_instalacoes,
    SUM(qtd_creditos_recebidos_mes_kwh) AS qtd_creditos_recebidos_kwh,
    SUM(qtd_creditos_faturados_kwh) AS qtd_creditos_faturados_kwh,
    SUM(vlr_gmv_real_oficial_brl) AS vlr_gmv_real_oficial_brl,
    SUM(vlr_gmv_gerador_brl) AS vlr_gmv_gerador_brl,
    MAX(ingerido_em) AS ingerido_em
  FROM `lemon-ae-case.trusted.cliente_energia_mensal`
  GROUP BY gerador, usina, cod_distribuidora, dt_mes_referencia;

  -- ETAPA 2 — FATURAMENTOS POR USINA E MÊS
  -- A origem já possui uma linha por instalação e competência; por isso os
  -- valores não são multiplicados pela quantidade de boletos ou PIX.
  CREATE TEMP TABLE tmp_faturamentos_por_usina AS
  SELECT
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_referencia,
    COUNTIF(flg_emitido) AS qtd_faturamentos_emitidos,
    COUNTIF(flg_pago) AS qtd_faturamentos_pagos,
    COUNTIF(flg_pago_ate_d60) AS qtd_faturamentos_pagos_d60,
    COUNTIF(flg_pago_apos_d60) AS qtd_faturamentos_pagos_apos_d60,
    COUNTIF(flg_multiplos_instrumentos_pagos)
      AS qtd_faturamentos_multiplos_instrumentos_pagos,
    SUM(qtd_creditos_faturados_pagos_kwh)
      AS qtd_creditos_faturados_pagos_kwh,
    SUM(qtd_creditos_faturados_pagos_d60_kwh)
      AS qtd_creditos_faturados_pagos_d60_kwh,
    CASE
      WHEN COUNTIF(flg_emitido AND dt_limite_pagamento_d60 IS NULL) > 0
        THEN NULL
      ELSE MAX(dt_limite_pagamento_d60)
    END AS dt_fechamento_competencia,
    SUM(IF(flg_emitido, vlr_gmv_gerador_brl, 0))
      AS vlr_cobranca_gerador_brl,
    SUM(COALESCE(vlr_cobranca_brl, 0)) AS vlr_cobranca_brl,
    SUM(COALESCE(vlr_faturamento_brl, 0)) AS vlr_faturamento_brl,
    SUM(COALESCE(vlr_total_pago_brl, 0)) AS vlr_total_pago_brl,
    SUM(COALESCE(vlr_principal_pago_brl, 0)) AS vlr_principal_pago_brl,
    SUM(COALESCE(vlr_liquidado_gerador_brl, 0))
      AS vlr_liquidado_gerador_brl,
    SUM(COALESCE(vlr_liquidado_gerador_d60_brl, 0))
      AS vlr_liquidado_gerador_d60_brl,
    SUM(COALESCE(vlr_liquidado_gerador_apos_d60_brl, 0))
      AS vlr_liquidado_gerador_apos_d60_brl,
    SUM(IF(flg_pago_ate_d60, COALESCE(vlr_juros_pago_brl, 0), 0))
      AS vlr_juros_pago_d60_brl,
    SUM(IF(flg_pago_ate_d60, COALESCE(vlr_multa_paga_brl, 0), 0))
      AS vlr_multa_paga_d60_brl,
    SUM(COALESCE(vlr_juros_pago_brl, 0)) AS vlr_juros_pago_brl,
    SUM(COALESCE(vlr_multa_paga_brl, 0)) AS vlr_multa_paga_brl,
    MAX(ingerido_em) AS ingerido_em
  FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
  GROUP BY gerador, usina, cod_distribuidora, dt_mes_referencia;

  -- ETAPA 3 — INTEGRAÇÃO NO GRÃO DA USINA
  -- usina_energia_mensal define a população. As usinas existentes somente nas
  -- tabelas de clientes permanecem visíveis nas validações como ausência de
  -- cadastro operacional, mas não originam uma linha artificial de desempenho.
  CREATE TEMP TABLE tmp_desempenho_usina_base AS
  SELECT
    farm.gerador,
    farm.usina,
    farm.cod_distribuidora,
    farm.dt_mes_referencia,
    COALESCE(cliente.qtd_instalacoes, 0) AS qtd_instalacoes,
    COALESCE(financeiro.qtd_faturamentos_emitidos, 0)
      AS qtd_faturamentos_emitidos,
    COALESCE(financeiro.qtd_faturamentos_pagos, 0)
      AS qtd_faturamentos_pagos,
    COALESCE(financeiro.qtd_faturamentos_pagos_d60, 0)
      AS qtd_faturamentos_pagos_d60,
    COALESCE(financeiro.qtd_faturamentos_pagos_apos_d60, 0)
      AS qtd_faturamentos_pagos_apos_d60,
    COALESCE(financeiro.qtd_faturamentos_multiplos_instrumentos_pagos, 0)
      AS qtd_faturamentos_multiplos_instrumentos_pagos,
    farm.qtd_creditos_injetados_kwh,
    farm.qtd_geracao_prevista_contrato_kwh,
    farm.qtd_geracao_realizada_gerador_kwh,
    LEAST(
      farm.qtd_creditos_injetados_kwh,
      farm.qtd_geracao_prevista_contrato_kwh
    ) AS qtd_minima_injecao_kwh,
    COALESCE(cliente.qtd_creditos_recebidos_kwh, 0)
      AS qtd_creditos_recebidos_kwh,
    COALESCE(cliente.qtd_creditos_faturados_kwh, 0)
      AS qtd_creditos_faturados_kwh,
    COALESCE(financeiro.qtd_creditos_faturados_pagos_kwh, 0)
      AS qtd_creditos_faturados_pagos_kwh,
    COALESCE(financeiro.qtd_creditos_faturados_pagos_d60_kwh, 0)
      AS qtd_creditos_faturados_pagos_d60_kwh,
    financeiro.dt_fechamento_competencia,
    COALESCE(
      CURRENT_DATE() >= financeiro.dt_fechamento_competencia,
      FALSE
    ) AS flg_competencia_fechada,
    COALESCE(cliente.vlr_gmv_real_oficial_brl, 0)
      AS vlr_gmv_real_oficial_brl,
    COALESCE(cliente.vlr_gmv_gerador_brl, 0) AS vlr_gmv_gerador_brl,
    COALESCE(financeiro.vlr_cobranca_gerador_brl, 0)
      AS vlr_cobranca_gerador_brl,
    COALESCE(financeiro.vlr_cobranca_brl, 0) AS vlr_cobranca_brl,
    COALESCE(financeiro.vlr_faturamento_brl, 0) AS vlr_faturamento_brl,
    COALESCE(financeiro.vlr_total_pago_brl, 0) AS vlr_total_pago_brl,
    COALESCE(financeiro.vlr_principal_pago_brl, 0) AS vlr_principal_pago_brl,
    COALESCE(financeiro.vlr_liquidado_gerador_brl, 0)
      AS vlr_liquidado_gerador_brl,
    COALESCE(financeiro.vlr_liquidado_gerador_d60_brl, 0)
      AS vlr_liquidado_gerador_d60_brl,
    COALESCE(financeiro.vlr_liquidado_gerador_apos_d60_brl, 0)
      AS vlr_liquidado_gerador_apos_d60_brl,
    COALESCE(financeiro.vlr_juros_pago_d60_brl, 0)
      AS vlr_juros_pago_d60_brl,
    COALESCE(financeiro.vlr_multa_paga_d60_brl, 0)
      AS vlr_multa_paga_d60_brl,
    COALESCE(financeiro.vlr_juros_pago_brl, 0) AS vlr_juros_pago_brl,
    COALESCE(financeiro.vlr_multa_paga_brl, 0) AS vlr_multa_paga_brl,
    farm.vlr_tusd_brl,
    farm.dt_mes_desconto_tusd_gerador,
    farm.vlr_tusd_descontada_gerador_brl,
    farm.vlr_aluguel_imoveis_brl,
    farm.vlr_aluguel_equipamento_brl,
    farm.vlr_operacao_manutencao_brl,
    cliente.qtd_instalacoes IS NOT NULL AS flg_possui_clientes,
    COALESCE(financeiro.qtd_faturamentos_emitidos, 0) > 0
      AS flg_possui_faturamento,
    GREATEST(
      farm.ingerido_em,
      COALESCE(cliente.ingerido_em, farm.ingerido_em),
      COALESCE(financeiro.ingerido_em, farm.ingerido_em)
    ) AS ingerido_em
  FROM `lemon-ae-case.trusted.usina_energia_mensal` AS farm
  LEFT JOIN tmp_clientes_por_usina AS cliente
    USING (gerador, usina, cod_distribuidora, dt_mes_referencia)
  LEFT JOIN tmp_faturamentos_por_usina AS financeiro
    USING (gerador, usina, cod_distribuidora, dt_mes_referencia);

  -- ETAPA 4 — INDICADORES DE DESEMPENHO
  CREATE TEMP TABLE tmp_desempenho_usina_calculado AS
  SELECT
    * EXCEPT (flg_possui_clientes, flg_possui_faturamento, ingerido_em),
    SAFE_DIVIDE(
      qtd_creditos_injetados_kwh,
      NULLIF(qtd_geracao_prevista_contrato_kwh, 0)
    ) AS perc_injetado_vs_previsto,
    SAFE_DIVIDE(
      qtd_creditos_injetados_kwh,
      NULLIF(qtd_geracao_realizada_gerador_kwh, 0)
    ) AS perc_distribuidora_vs_inversor,
    SAFE_DIVIDE(
      qtd_creditos_recebidos_kwh,
      NULLIF(qtd_creditos_injetados_kwh, 0)
    ) AS perc_recebidos_vs_injetados,
    SAFE_DIVIDE(
      qtd_creditos_faturados_kwh,
      NULLIF(qtd_creditos_recebidos_kwh, 0)
    ) AS perc_faturados_vs_recebidos,
    SAFE_DIVIDE(
      qtd_creditos_faturados_kwh,
      NULLIF(qtd_minima_injecao_kwh, 0)
    ) AS perc_preenchimento_usina,
    SAFE_DIVIDE(
      qtd_creditos_faturados_pagos_d60_kwh,
      NULLIF(qtd_minima_injecao_kwh, 0)
    ) AS perc_desempenho_lemon,
    flg_possui_clientes,
    flg_possui_faturamento,
    ingerido_em
  FROM tmp_desempenho_usina_base;

  -- ETAPA 5 — DEDUPLICAÇÃO DEFENSIVA
  CREATE TEMP TABLE tmp_desempenho_usina_deduplicado AS
  SELECT *
  FROM tmp_desempenho_usina_calculado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY gerador, usina, cod_distribuidora, dt_mes_referencia
    ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 6 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.desempenho_usina_mensal` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.desempenho_usina_mensal` (
    gerador, usina, cod_distribuidora, dt_mes_referencia, qtd_instalacoes,
    qtd_faturamentos_emitidos, qtd_faturamentos_pagos,
    qtd_faturamentos_pagos_d60, qtd_faturamentos_pagos_apos_d60,
    qtd_faturamentos_multiplos_instrumentos_pagos,
    qtd_creditos_injetados_kwh, qtd_geracao_prevista_contrato_kwh,
    qtd_geracao_realizada_gerador_kwh, qtd_minima_injecao_kwh,
    qtd_creditos_recebidos_kwh, qtd_creditos_faturados_kwh,
    qtd_creditos_faturados_pagos_kwh,
    qtd_creditos_faturados_pagos_d60_kwh, dt_fechamento_competencia,
    flg_competencia_fechada, vlr_gmv_real_oficial_brl,
    vlr_gmv_gerador_brl, vlr_cobranca_gerador_brl, vlr_cobranca_brl,
    vlr_faturamento_brl, vlr_total_pago_brl, vlr_principal_pago_brl,
    vlr_liquidado_gerador_brl, vlr_liquidado_gerador_d60_brl,
    vlr_liquidado_gerador_apos_d60_brl, vlr_juros_pago_d60_brl,
    vlr_multa_paga_d60_brl, vlr_juros_pago_brl, vlr_multa_paga_brl,
    vlr_tusd_brl, dt_mes_desconto_tusd_gerador,
    vlr_tusd_descontada_gerador_brl, vlr_aluguel_imoveis_brl,
    vlr_aluguel_equipamento_brl, vlr_operacao_manutencao_brl,
    perc_injetado_vs_previsto, perc_distribuidora_vs_inversor,
    perc_recebidos_vs_injetados, perc_faturados_vs_recebidos,
    perc_preenchimento_usina, perc_desempenho_lemon,
    flg_possui_clientes, flg_possui_faturamento, ingerido_em
  )
  SELECT
    gerador, usina, cod_distribuidora, dt_mes_referencia, qtd_instalacoes,
    qtd_faturamentos_emitidos, qtd_faturamentos_pagos,
    qtd_faturamentos_pagos_d60, qtd_faturamentos_pagos_apos_d60,
    qtd_faturamentos_multiplos_instrumentos_pagos,
    qtd_creditos_injetados_kwh, qtd_geracao_prevista_contrato_kwh,
    qtd_geracao_realizada_gerador_kwh, qtd_minima_injecao_kwh,
    qtd_creditos_recebidos_kwh, qtd_creditos_faturados_kwh,
    qtd_creditos_faturados_pagos_kwh,
    qtd_creditos_faturados_pagos_d60_kwh, dt_fechamento_competencia,
    flg_competencia_fechada, vlr_gmv_real_oficial_brl,
    vlr_gmv_gerador_brl, vlr_cobranca_gerador_brl, vlr_cobranca_brl,
    vlr_faturamento_brl, vlr_total_pago_brl, vlr_principal_pago_brl,
    vlr_liquidado_gerador_brl, vlr_liquidado_gerador_d60_brl,
    vlr_liquidado_gerador_apos_d60_brl, vlr_juros_pago_d60_brl,
    vlr_multa_paga_d60_brl, vlr_juros_pago_brl, vlr_multa_paga_brl,
    vlr_tusd_brl, dt_mes_desconto_tusd_gerador,
    vlr_tusd_descontada_gerador_brl, vlr_aluguel_imoveis_brl,
    vlr_aluguel_equipamento_brl, vlr_operacao_manutencao_brl,
    perc_injetado_vs_previsto, perc_distribuidora_vs_inversor,
    perc_recebidos_vs_injetados, perc_faturados_vs_recebidos,
    perc_preenchimento_usina, perc_desempenho_lemon,
    flg_possui_clientes, flg_possui_faturamento, ingerido_em
  FROM tmp_desempenho_usina_deduplicado;
  COMMIT TRANSACTION;
END;
