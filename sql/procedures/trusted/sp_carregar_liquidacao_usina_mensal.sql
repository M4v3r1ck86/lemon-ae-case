-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_LIQUIDACAO_USINA_MENSAL
-- Preserva simultaneamente o mês da competência e o mês da entrada do caixa.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_liquidacao_usina_mensal`()
BEGIN
  CREATE TEMP TABLE tmp_liquidacao_usina_mensal AS
  SELECT
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_referencia AS dt_mes_competencia_origem,
    dt_mes_pagamento AS dt_mes_liquidacao,
    CASE
      WHEN flg_pago_ate_d60 THEN 'dentro_d60'
      WHEN flg_pago_apos_d60 THEN 'recuperacao_apos_d60'
      ELSE 'vencimento_ausente'
    END AS classificacao_liquidacao,
    COUNT(DISTINCT id_faturamento) AS qtd_faturamentos,
    COUNT(DISTINCT id_instalacao) AS qtd_instalacoes,
    SUM(qtd_creditos_faturados_pagos_kwh)
      AS qtd_creditos_faturados_pagos_kwh,
    SUM(COALESCE(vlr_faturamento_brl, 0)) AS vlr_faturamento_brl,
    SUM(COALESCE(vlr_principal_pago_brl, 0)) AS vlr_principal_pago_brl,
    SUM(COALESCE(vlr_liquidado_gerador_brl, 0))
      AS vlr_liquidado_gerador_brl,
    SUM(COALESCE(vlr_juros_pago_brl, 0)) AS vlr_juros_pago_brl,
    SUM(COALESCE(vlr_multa_paga_brl, 0)) AS vlr_multa_paga_brl,
    MAX(ingerido_em) AS ingerido_em
  FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
  WHERE flg_pago
    AND dt_mes_pagamento IS NOT NULL
  GROUP BY
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_competencia_origem,
    dt_mes_liquidacao,
    classificacao_liquidacao;

  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.liquidacao_usina_mensal` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.liquidacao_usina_mensal`
  SELECT * FROM tmp_liquidacao_usina_mensal;
  COMMIT TRANSACTION;
END;
