-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — REFINED.SP_CARREGAR_RELATORIO_GERADOR_MENSAL
-- Grain: gerador + usina + cod_distribuidora + dt_mes_referencia.
-- Política: fechamento imutável após maturação de 60 dias do vencimento.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.refined.sp_carregar_relatorio_gerador_mensal`()
BEGIN
  -- Apenas competências maduras podem ser publicadas como fechamento.
  CREATE TEMP TABLE tmp_desempenho_fechado AS
  SELECT *
  FROM `lemon-ae-case.trusted.desempenho_usina_mensal`
  WHERE flg_competencia_fechada;

  -- A TUSD é deslocada para o mês indicado pela própria fonte, não para o mês
  -- operacional da linha de energy_farms.
  CREATE TEMP TABLE tmp_tusd_por_mes_desconto AS
  SELECT
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_desconto_tusd_gerador AS dt_mes_referencia,
    SUM(COALESCE(vlr_tusd_descontada_gerador_brl, 0))
      AS vlr_tusd_descontada_gerador_brl
  FROM `lemon-ae-case.trusted.usina_energia_mensal`
  WHERE dt_mes_desconto_tusd_gerador IS NOT NULL
  GROUP BY gerador, usina, cod_distribuidora, dt_mes_referencia;

  -- A carga falha antes de alterar a tabela se uma linha não possuir exatamente
  -- uma faixa de take rate. Isso impede exclusão silenciosa e fanout.
  CREATE TEMP TABLE tmp_validacao_take_rate AS
  SELECT
    desempenho.gerador,
    desempenho.usina,
    desempenho.cod_distribuidora,
    desempenho.dt_mes_referencia,
    COUNT(faixa.id_take_rate) AS qtd_faixas_aplicaveis
  FROM tmp_desempenho_fechado AS desempenho
  LEFT JOIN `lemon-ae-case.trusted.faixa_take_rate_gerador` AS faixa
    ON faixa.gerador = desempenho.gerador
    AND faixa.cod_distribuidora = desempenho.cod_distribuidora
    AND desempenho.dt_mes_referencia
      BETWEEN faixa.dt_inicio_vigencia AND faixa.dt_fim_vigencia
    AND COALESCE(desempenho.perc_desempenho_lemon, 0)
      >= faixa.perc_desempenho_min
    AND COALESCE(desempenho.perc_desempenho_lemon, 0)
      < faixa.perc_desempenho_max
  GROUP BY
    desempenho.gerador,
    desempenho.usina,
    desempenho.cod_distribuidora,
    desempenho.dt_mes_referencia;

  ASSERT (
    SELECT COUNTIF(qtd_faixas_aplicaveis != 1) = 0
    FROM tmp_validacao_take_rate
  ) AS 'Cada linha fechada deve possuir exatamente uma faixa de take rate.';

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
    desempenho.dt_fechamento_competencia,
    60 AS dias_maturacao,
    'fechado' AS status_fechamento,
    desempenho.qtd_instalacoes,
    desempenho.qtd_creditos_injetados_kwh,
    desempenho.qtd_creditos_faturados_kwh,
    desempenho.qtd_creditos_faturados_pagos_d60_kwh
      AS qtd_creditos_faturados_pagos_kwh,
    desempenho.qtd_minima_injecao_kwh,
    desempenho.perc_desempenho_lemon,
    faixa.id_take_rate,
    faixa.perc_desempenho_min,
    faixa.perc_desempenho_max,
    faixa.perc_take_rate AS perc_take_rate_aplicado,
    desempenho.vlr_cobranca_gerador_brl,
    desempenho.vlr_liquidado_gerador_d60_brl
      AS vlr_liquidado_gerador_brl,
    desempenho.vlr_liquidado_gerador_apos_d60_brl,
    GREATEST(
      desempenho.vlr_gmv_gerador_brl
        - desempenho.vlr_liquidado_gerador_d60_brl,
      CAST(0 AS NUMERIC)
    ) AS vlr_saldo_nao_liquidado_d60_brl,
    desempenho.vlr_liquidado_gerador_d60_brl
      AS vlr_receita_bruta_gerador_brl,
    COALESCE(desempenho.vlr_juros_pago_d60_brl, 0)
      + COALESCE(desempenho.vlr_multa_paga_d60_brl, 0)
        AS vlr_receita_multas_brl,
    tusd.dt_mes_referencia AS dt_mes_desconto_tusd_gerador,
    COALESCE(tusd.vlr_tusd_descontada_gerador_brl, 0)
      AS vlr_tusd_descontada_gerador_brl
  FROM tmp_desempenho_fechado AS desempenho
  INNER JOIN `lemon-ae-case.trusted.faixa_take_rate_gerador` AS faixa
    ON faixa.gerador = desempenho.gerador
    AND faixa.cod_distribuidora = desempenho.cod_distribuidora
    AND desempenho.dt_mes_referencia
      BETWEEN faixa.dt_inicio_vigencia AND faixa.dt_fim_vigencia
    AND COALESCE(desempenho.perc_desempenho_lemon, 0)
      >= faixa.perc_desempenho_min
    AND COALESCE(desempenho.perc_desempenho_lemon, 0)
      < faixa.perc_desempenho_max
  LEFT JOIN tmp_tusd_por_mes_desconto AS tusd
    ON tusd.gerador = desempenho.gerador
    AND tusd.usina = desempenho.usina
    AND tusd.cod_distribuidora = desempenho.cod_distribuidora
    AND tusd.dt_mes_referencia = desempenho.dt_mes_referencia;

  CREATE TEMP TABLE tmp_relatorio_gerador AS
  SELECT
    base.*,
    vlr_receita_bruta_gerador_brl * (1 - perc_take_rate_aplicado)
      AS vlr_repasse_pre_tusd_gerador_brl,
    vlr_receita_bruta_gerador_brl * (1 - perc_take_rate_aplicado)
      - vlr_tusd_descontada_gerador_brl AS vlr_repasse_gerador_brl,
    vlr_receita_multas_brl * perc_take_rate_aplicado
      AS vlr_repasse_multas_lemon_brl,
    vlr_receita_multas_brl * (1 - perc_take_rate_aplicado)
      AS vlr_repasse_multas_gerador_brl,
    vlr_receita_bruta_gerador_brl * perc_take_rate_aplicado
      AS vlr_repasse_lemon_brl,
    CURRENT_TIMESTAMP() AS processado_em
  FROM tmp_desempenho_com_take_rate AS base;

  BEGIN TRANSACTION;
  -- Remove somente linhas da versão anterior, identificadas pela ausência dos
  -- metadados de fechamento. Fechamentos novos são inseridos uma única vez.
  DELETE FROM `lemon-ae-case.refined.relatorio_gerador_mensal`
  WHERE status_fechamento IS NULL;

  INSERT INTO `lemon-ae-case.refined.relatorio_gerador_mensal` (
    gerador, id_gerador, usina, id_usina, cod_distribuidora,
    dt_mes_referencia, dt_fechamento_competencia, dias_maturacao,
    status_fechamento, qtd_instalacoes, qtd_creditos_injetados_kwh,
    qtd_creditos_faturados_kwh, qtd_creditos_faturados_pagos_kwh,
    qtd_minima_injecao_kwh, perc_desempenho_lemon, id_take_rate,
    perc_desempenho_min, perc_desempenho_max, perc_take_rate_aplicado,
    vlr_cobranca_gerador_brl, vlr_liquidado_gerador_brl,
    vlr_liquidado_gerador_apos_d60_brl,
    vlr_saldo_nao_liquidado_d60_brl, vlr_receita_bruta_gerador_brl,
    vlr_receita_multas_brl, vlr_repasse_pre_tusd_gerador_brl,
    dt_mes_desconto_tusd_gerador, vlr_tusd_descontada_gerador_brl,
    vlr_repasse_gerador_brl, vlr_repasse_multas_lemon_brl,
    vlr_repasse_multas_gerador_brl, vlr_repasse_lemon_brl, processado_em
  )
  SELECT
    r.gerador, r.id_gerador, r.usina, r.id_usina, r.cod_distribuidora,
    r.dt_mes_referencia, r.dt_fechamento_competencia, r.dias_maturacao,
    r.status_fechamento, r.qtd_instalacoes, r.qtd_creditos_injetados_kwh,
    r.qtd_creditos_faturados_kwh, r.qtd_creditos_faturados_pagos_kwh,
    r.qtd_minima_injecao_kwh, r.perc_desempenho_lemon, r.id_take_rate,
    r.perc_desempenho_min, r.perc_desempenho_max, r.perc_take_rate_aplicado,
    r.vlr_cobranca_gerador_brl, r.vlr_liquidado_gerador_brl,
    r.vlr_liquidado_gerador_apos_d60_brl,
    r.vlr_saldo_nao_liquidado_d60_brl, r.vlr_receita_bruta_gerador_brl,
    r.vlr_receita_multas_brl, r.vlr_repasse_pre_tusd_gerador_brl,
    r.dt_mes_desconto_tusd_gerador, r.vlr_tusd_descontada_gerador_brl,
    r.vlr_repasse_gerador_brl, r.vlr_repasse_multas_lemon_brl,
    r.vlr_repasse_multas_gerador_brl, r.vlr_repasse_lemon_brl,
    r.processado_em
  FROM tmp_relatorio_gerador AS r
  WHERE NOT EXISTS (
    SELECT 1
    FROM `lemon-ae-case.refined.relatorio_gerador_mensal` AS existente
    WHERE existente.gerador = r.gerador
      AND existente.usina = r.usina
      AND existente.cod_distribuidora = r.cod_distribuidora
      AND existente.dt_mes_referencia = r.dt_mes_referencia
  );
  COMMIT TRANSACTION;
END;
