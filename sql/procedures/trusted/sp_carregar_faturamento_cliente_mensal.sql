-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_FATURAMENTO_CLIENTE_MENSAL
-- Grain: uma linha por id_instalacao + dt_mes_referencia.
-- Regra temporal: pagamento reconhecido na competência até 60 dias corridos
-- após o vencimento vigente; na ausência dele, usa o vencimento original.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_faturamento_cliente_mensal`()
BEGIN
  CREATE TEMP TABLE tmp_instrumentos_por_faturamento AS
  SELECT
    id_faturamento,
    COUNT(*) AS qtd_instrumentos,
    COUNTIF(tipo_instrumento = 'boleto') AS qtd_boletos,
    COUNTIF(tipo_instrumento = 'pix') AS qtd_pixs,
    COUNTIF(LOWER(status_instrumento) = 'paid') AS qtd_instrumentos_pagos,
    MAX(ingerido_em) AS ingerido_em
  FROM `lemon-ae-case.trusted.instrumento_pagamento`
  GROUP BY id_faturamento;

  CREATE TEMP TABLE tmp_faturamento_cliente_base AS
  SELECT
    cliente.id_instalacao,
    cliente.dt_mes_referencia,
    cliente.gerador,
    cliente.usina,
    cliente.cod_distribuidora,
    cobranca.id_cobranca,
    cobranca.id_faturamento,
    cobranca.id_local,
    cobranca.status_cobranca,
    faturamento.status_faturamento,
    cobranca.ts_criado_em AS ts_criacao_cobranca,
    faturamento.ts_criado_em AS ts_criacao_faturamento,
    faturamento.dt_vencimento,
    faturamento.dt_vencimento_original,
    DATE(faturamento.ts_pagamento) AS dt_pagamento,
    DATE_TRUNC(DATE(faturamento.ts_pagamento), MONTH) AS dt_mes_pagamento,
    COALESCE(faturamento.dt_vencimento, faturamento.dt_vencimento_original)
      AS dt_vencimento_base_d60,
    DATE_ADD(
      COALESCE(faturamento.dt_vencimento, faturamento.dt_vencimento_original),
      INTERVAL 60 DAY
    ) AS dt_limite_pagamento_d60,
    cliente.vlr_gmv_real_oficial_brl,
    cliente.vlr_gmv_gerador_brl,
    cobranca.vlr_cobranca_brl,
    faturamento.vlr_faturamento_brl,
    faturamento.vlr_total_pago_brl,
    CASE
      WHEN faturamento.vlr_total_pago_brl IS NULL THEN NULL
      ELSE faturamento.vlr_total_pago_brl
        - COALESCE(faturamento.vlr_juros_pago_brl, 0)
        - COALESCE(faturamento.vlr_multa_paga_brl, 0)
    END AS vlr_principal_pago_brl,
    faturamento.vlr_juros_pago_brl,
    faturamento.vlr_multa_paga_brl,
    cliente.qtd_creditos_faturados_kwh,
    COALESCE(
      LOWER(faturamento.status_faturamento) = 'paid'
      OR faturamento.ts_pagamento IS NOT NULL,
      FALSE
    ) AS flg_pago,
    COALESCE(instrumento.qtd_instrumentos, 0) AS qtd_instrumentos,
    COALESCE(instrumento.qtd_boletos, 0) AS qtd_boletos,
    COALESCE(instrumento.qtd_pixs, 0) AS qtd_pixs,
    COALESCE(instrumento.qtd_instrumentos_pagos, 0)
      AS qtd_instrumentos_pagos,
    faturamento.ts_criado_em IS NOT NULL AS flg_emitido,
    COALESCE(instrumento.qtd_instrumentos_pagos, 0) > 1
      AS flg_multiplos_instrumentos_pagos,
    GREATEST(
      cliente.ingerido_em,
      COALESCE(cobranca.ingerido_em, cliente.ingerido_em),
      COALESCE(faturamento.ingerido_em, cliente.ingerido_em),
      COALESCE(instrumento.ingerido_em, cliente.ingerido_em)
    ) AS ingerido_em
  FROM `lemon-ae-case.trusted.cliente_energia_mensal` AS cliente
  LEFT JOIN `lemon-ae-case.trusted.cobranca` AS cobranca
    ON cliente.id_instalacao = cobranca.id_instalacao
    AND cliente.dt_mes_referencia = cobranca.dt_mes_referencia
  LEFT JOIN `lemon-ae-case.trusted.faturamento` AS faturamento
    ON cobranca.id_faturamento = faturamento.id_faturamento
  LEFT JOIN tmp_instrumentos_por_faturamento AS instrumento
    ON cobranca.id_faturamento = instrumento.id_faturamento;

  CREATE TEMP TABLE tmp_faturamento_cliente_temporal AS
  SELECT
    base.* EXCEPT (flg_pago),
    DATE_DIFF(dt_pagamento, dt_vencimento_base_d60, DAY)
      AS qtd_dias_para_pagamento,
    CASE
      WHEN dt_pagamento IS NULL THEN 'pendente'
      WHEN dt_vencimento_base_d60 IS NULL THEN 'vencimento_ausente'
      WHEN dt_pagamento <= dt_vencimento_base_d60 THEN 'em_dia'
      WHEN DATE_DIFF(dt_pagamento, dt_vencimento_base_d60, DAY) <= 30
        THEN 'atraso_1_30'
      WHEN DATE_DIFF(dt_pagamento, dt_vencimento_base_d60, DAY) <= 60
        THEN 'atraso_31_60'
      ELSE 'atraso_acima_60'
    END AS faixa_atraso,
    CASE
      WHEN vlr_principal_pago_brl IS NULL THEN NULL
      ELSE SAFE_DIVIDE(
        vlr_principal_pago_brl,
        NULLIF(vlr_faturamento_brl, 0)
      ) * vlr_gmv_gerador_brl
    END AS vlr_liquidado_gerador_brl,
    IF(flg_pago, qtd_creditos_faturados_kwh, CAST(0 AS NUMERIC))
      AS qtd_creditos_faturados_pagos_kwh,
    flg_pago,
    COALESCE(
      flg_pago
      AND dt_limite_pagamento_d60 IS NOT NULL
      AND dt_pagamento <= dt_limite_pagamento_d60,
      FALSE
    ) AS flg_pago_ate_d60,
    COALESCE(
      flg_pago
      AND dt_limite_pagamento_d60 IS NOT NULL
      AND dt_pagamento > dt_limite_pagamento_d60,
      FALSE
    ) AS flg_pago_apos_d60
  FROM tmp_faturamento_cliente_base AS base;

  CREATE TEMP TABLE tmp_faturamento_cliente_calculado AS
  SELECT
    temporal.*,
    IF(flg_pago_ate_d60, vlr_liquidado_gerador_brl, CAST(0 AS NUMERIC))
      AS vlr_liquidado_gerador_d60_brl,
    IF(flg_pago_apos_d60, vlr_liquidado_gerador_brl, CAST(0 AS NUMERIC))
      AS vlr_liquidado_gerador_apos_d60_brl,
    IF(
      flg_pago_ate_d60,
      qtd_creditos_faturados_kwh,
      CAST(0 AS NUMERIC)
    ) AS qtd_creditos_faturados_pagos_d60_kwh,
    NOT flg_pago_ate_d60 AS flg_pendente_d60
  FROM tmp_faturamento_cliente_temporal AS temporal;

  CREATE TEMP TABLE tmp_faturamento_cliente_deduplicado AS
  SELECT *
  FROM tmp_faturamento_cliente_calculado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_instalacao, dt_mes_referencia
    ORDER BY ingerido_em DESC, id_cobranca DESC, id_faturamento DESC
  ) = 1;

  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.faturamento_cliente_mensal` WHERE TRUE;

  INSERT INTO `lemon-ae-case.trusted.faturamento_cliente_mensal` (
    id_instalacao, dt_mes_referencia, gerador, usina, cod_distribuidora,
    id_cobranca, id_faturamento, id_local, status_cobranca,
    status_faturamento, ts_criacao_cobranca, ts_criacao_faturamento,
    dt_vencimento, dt_vencimento_original, dt_pagamento, dt_mes_pagamento,
    dt_vencimento_base_d60, dt_limite_pagamento_d60,
    qtd_dias_para_pagamento, faixa_atraso, vlr_gmv_real_oficial_brl,
    vlr_gmv_gerador_brl, vlr_cobranca_brl, vlr_faturamento_brl,
    vlr_total_pago_brl, vlr_principal_pago_brl,
    vlr_liquidado_gerador_brl, vlr_liquidado_gerador_d60_brl,
    vlr_liquidado_gerador_apos_d60_brl, vlr_juros_pago_brl,
    vlr_multa_paga_brl, qtd_creditos_faturados_kwh,
    qtd_creditos_faturados_pagos_kwh,
    qtd_creditos_faturados_pagos_d60_kwh, qtd_instrumentos, qtd_boletos,
    qtd_pixs, qtd_instrumentos_pagos, flg_emitido, flg_pago,
    flg_pago_ate_d60, flg_pago_apos_d60, flg_pendente_d60,
    flg_multiplos_instrumentos_pagos, ingerido_em
  )
  SELECT
    id_instalacao, dt_mes_referencia, gerador, usina, cod_distribuidora,
    id_cobranca, id_faturamento, id_local, status_cobranca,
    status_faturamento, ts_criacao_cobranca, ts_criacao_faturamento,
    dt_vencimento, dt_vencimento_original, dt_pagamento, dt_mes_pagamento,
    dt_vencimento_base_d60, dt_limite_pagamento_d60,
    qtd_dias_para_pagamento, faixa_atraso, vlr_gmv_real_oficial_brl,
    vlr_gmv_gerador_brl, vlr_cobranca_brl, vlr_faturamento_brl,
    vlr_total_pago_brl, vlr_principal_pago_brl,
    vlr_liquidado_gerador_brl, vlr_liquidado_gerador_d60_brl,
    vlr_liquidado_gerador_apos_d60_brl, vlr_juros_pago_brl,
    vlr_multa_paga_brl, qtd_creditos_faturados_kwh,
    qtd_creditos_faturados_pagos_kwh,
    qtd_creditos_faturados_pagos_d60_kwh, qtd_instrumentos, qtd_boletos,
    qtd_pixs, qtd_instrumentos_pagos, flg_emitido, flg_pago,
    flg_pago_ate_d60, flg_pago_apos_d60, flg_pendente_d60,
    flg_multiplos_instrumentos_pagos, ingerido_em
  FROM tmp_faturamento_cliente_deduplicado;
  COMMIT TRANSACTION;
END;
