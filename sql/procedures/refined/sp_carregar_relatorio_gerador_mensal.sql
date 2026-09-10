-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — REFINED.SP_CARREGAR_RELATORIO_GERADOR_MENSAL
-- Grain: gerador + usina + cod_distribuidora + dt_mes_referencia.
-- Pré-requisito: exatamente uma faixa de take rate aplicável a cada linha.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.refined.sp_carregar_relatorio_gerador_mensal`()
BEGIN
  -- ETAPA 1 — APLICAÇÃO DA VIGÊNCIA E DA FAIXA DE DESEMPENHO
  CREATE TEMP TABLE tmp_desempenho_com_take_rate AS
  SELECT
    desempenho.gerador,
    SAFE_CAST(REGEXP_EXTRACT(desempenho.gerador, r'(\d+)$') AS INT64)
      AS id_gerador,
    desempenho.usina,
    SAFE_CAST(REGEXP_EXTRACT(desempenho.usina, r'(\d+)$') AS INT64)
      AS id_usina,
    desempenho.cod_distribuidora,
    desempenho.dt_mes_referencia,
    desempenho.qtd_instalacoes,
    desempenho.qtd_creditos_injetados_kwh,
    desempenho.qtd_creditos_faturados_kwh,
    desempenho.qtd_creditos_faturados_pagos_kwh,
    desempenho.qtd_minima_injecao_kwh,
    desempenho.perc_desempenho_lemon,
    faixa.id_take_rate,
    faixa.perc_desempenho_min,
    faixa.perc_desempenho_max,
    faixa.perc_take_rate AS perc_take_rate_aplicado,
    desempenho.vlr_cobranca_gerador_brl,
    desempenho.vlr_liquidado_gerador_brl,
    desempenho.vlr_liquidado_gerador_brl AS vlr_receita_bruta_gerador_brl,
    COALESCE(desempenho.vlr_juros_pago_brl, 0)
      + COALESCE(desempenho.vlr_multa_paga_brl, 0)
        AS vlr_receita_multas_brl,
    desempenho.dt_mes_desconto_tusd_gerador,
    COALESCE(desempenho.vlr_tusd_descontada_gerador_brl, 0)
      AS vlr_tusd_descontada_gerador_brl
  FROM `lemon-ae-case.trusted.desempenho_usina_mensal` AS desempenho
  INNER JOIN `lemon-ae-case.trusted.faixa_take_rate_gerador` AS faixa
    ON faixa.gerador = desempenho.gerador
    AND faixa.cod_distribuidora = desempenho.cod_distribuidora
    AND desempenho.dt_mes_referencia
      BETWEEN faixa.dt_inicio_vigencia AND faixa.dt_fim_vigencia
    AND COALESCE(desempenho.perc_desempenho_lemon, 0)
      >= faixa.perc_desempenho_min
    AND COALESCE(desempenho.perc_desempenho_lemon, 0)
      < faixa.perc_desempenho_max;

  -- ETAPA 2 — RECEITA, TAKE RATE E REPASSES
  CREATE TEMP TABLE tmp_relatorio_gerador AS
  SELECT
    * EXCEPT (
      vlr_receita_bruta_gerador_brl,
      vlr_receita_multas_brl,
      dt_mes_desconto_tusd_gerador,
      vlr_tusd_descontada_gerador_brl
    ),
    vlr_receita_bruta_gerador_brl,
    vlr_receita_multas_brl,
    vlr_receita_bruta_gerador_brl * (1 - perc_take_rate_aplicado)
      AS vlr_repasse_pre_tusd_gerador_brl,
    dt_mes_desconto_tusd_gerador,
    vlr_tusd_descontada_gerador_brl,
    vlr_receita_bruta_gerador_brl * (1 - perc_take_rate_aplicado)
      - vlr_tusd_descontada_gerador_brl AS vlr_repasse_gerador_brl,
    vlr_receita_multas_brl * perc_take_rate_aplicado
      AS vlr_repasse_multas_lemon_brl,
    vlr_receita_multas_brl * (1 - perc_take_rate_aplicado)
      AS vlr_repasse_multas_gerador_brl,
    vlr_receita_bruta_gerador_brl * perc_take_rate_aplicado
      AS vlr_repasse_lemon_brl,
    CURRENT_TIMESTAMP() AS processado_em
  FROM tmp_desempenho_com_take_rate;

  -- ETAPA 3 — CARGA INTEGRAL DA TABELA REFINED
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.refined.relatorio_gerador_mensal` WHERE TRUE;
  INSERT INTO `lemon-ae-case.refined.relatorio_gerador_mensal` (
    gerador,
    id_gerador,
    usina,
    id_usina,
    cod_distribuidora,
    dt_mes_referencia,
    qtd_instalacoes,
    qtd_creditos_injetados_kwh,
    qtd_creditos_faturados_kwh,
    qtd_creditos_faturados_pagos_kwh,
    qtd_minima_injecao_kwh,
    perc_desempenho_lemon,
    id_take_rate,
    perc_desempenho_min,
    perc_desempenho_max,
    perc_take_rate_aplicado,
    vlr_cobranca_gerador_brl,
    vlr_liquidado_gerador_brl,
    vlr_receita_bruta_gerador_brl,
    vlr_receita_multas_brl,
    vlr_repasse_pre_tusd_gerador_brl,
    dt_mes_desconto_tusd_gerador,
    vlr_tusd_descontada_gerador_brl,
    vlr_repasse_gerador_brl,
    vlr_repasse_multas_lemon_brl,
    vlr_repasse_multas_gerador_brl,
    vlr_repasse_lemon_brl,
    processado_em
  )
  SELECT * FROM tmp_relatorio_gerador;
  COMMIT TRANSACTION;
END;
