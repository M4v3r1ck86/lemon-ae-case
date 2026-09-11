-- BigQuery / GoogleSQL
-- =============================================================================
-- VALIDAÇÃO 05 — TEMPORALIDADE D+60
-- Execute depois das procedures Trusted. As consultas de inconsistência devem
-- retornar zero linhas; os resumos servem para inspeção funcional.
-- =============================================================================

-- 1. Distribuição dos faturamentos pela regra temporal.
SELECT
  faixa_atraso,
  COUNT(*) AS qtd_faturamentos,
  SUM(COALESCE(vlr_principal_pago_brl, 0)) AS vlr_principal_pago_brl,
  SUM(COALESCE(vlr_liquidado_gerador_brl, 0))
    AS vlr_liquidado_gerador_brl
FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
GROUP BY faixa_atraso
ORDER BY faixa_atraso;

-- 2. Competência de origem versus mês em que o caixa entrou.
SELECT
  dt_mes_referencia AS dt_mes_competencia_origem,
  dt_mes_pagamento AS dt_mes_liquidacao,
  COUNT(*) AS qtd_faturamentos,
  COUNTIF(flg_pago_ate_d60) AS qtd_pago_ate_d60,
  COUNTIF(flg_pago_apos_d60) AS qtd_pago_apos_d60,
  SUM(COALESCE(vlr_liquidado_gerador_d60_brl, 0))
    AS vlr_liquidado_d60_brl,
  SUM(COALESCE(vlr_liquidado_gerador_apos_d60_brl, 0))
    AS vlr_recuperado_apos_d60_brl
FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
GROUP BY dt_mes_competencia_origem, dt_mes_liquidacao
ORDER BY dt_mes_competencia_origem, dt_mes_liquidacao;

-- 3. Deve retornar zero: flags temporais mutuamente exclusivas e coerentes.
SELECT *
FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
WHERE (flg_pago_ate_d60 AND flg_pago_apos_d60)
   OR (flg_pago AND NOT flg_pago_ate_d60 AND NOT flg_pago_apos_d60)
   OR (NOT flg_pago AND (flg_pago_ate_d60 OR flg_pago_apos_d60));

-- 4. Deve retornar zero: decomposição financeira não fecha.
SELECT
  id_instalacao,
  id_faturamento,
  vlr_liquidado_gerador_brl,
  vlr_liquidado_gerador_d60_brl,
  vlr_liquidado_gerador_apos_d60_brl
FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
WHERE ABS(
  COALESCE(vlr_liquidado_gerador_brl, 0)
  - COALESCE(vlr_liquidado_gerador_d60_brl, 0)
  - COALESCE(vlr_liquidado_gerador_apos_d60_brl, 0)
) > NUMERIC '0.01';

-- 5. Deve retornar zero: agregado de liquidação diverge do detalhe pago.
WITH detalhe AS (
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
    SUM(COALESCE(vlr_liquidado_gerador_brl, 0)) AS valor
  FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
  WHERE flg_pago AND dt_mes_pagamento IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT
  COALESCE(d.gerador, a.gerador) AS gerador,
  COALESCE(d.usina, a.usina) AS usina,
  COALESCE(d.dt_mes_competencia_origem, a.dt_mes_competencia_origem)
    AS dt_mes_competencia_origem,
  COALESCE(d.dt_mes_liquidacao, a.dt_mes_liquidacao) AS dt_mes_liquidacao,
  d.valor AS valor_detalhe,
  a.vlr_liquidado_gerador_brl AS valor_agregado
FROM detalhe AS d
FULL OUTER JOIN `lemon-ae-case.trusted.liquidacao_usina_mensal` AS a
  USING (
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_competencia_origem,
    dt_mes_liquidacao,
    classificacao_liquidacao
  )
WHERE ABS(COALESCE(d.valor, 0) - COALESCE(a.vlr_liquidado_gerador_brl, 0))
  > NUMERIC '0.01';
