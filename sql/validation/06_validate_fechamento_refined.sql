-- BigQuery / GoogleSQL
-- =============================================================================
-- VALIDAÇÃO 06 — FECHAMENTO REFINED D+60
-- Execute depois da procedure Refined. Consultas marcadas como controle devem
-- retornar zero linhas.
-- =============================================================================

-- 1. Controle: unicidade do grain final.
SELECT
  gerador,
  usina,
  cod_distribuidora,
  dt_mes_referencia,
  COUNT(*) AS qtd_linhas
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) != 1;

-- 2. Controle: somente competências maduras e fechadas.
SELECT *
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`
WHERE status_fechamento != 'fechado'
   OR dias_maturacao != 60
   OR dt_fechamento_competencia > CURRENT_DATE();

-- 3. Controle: fórmulas financeiras da Refined.
SELECT
  gerador,
  usina,
  dt_mes_referencia,
  vlr_repasse_pre_tusd_gerador_brl,
  vlr_repasse_gerador_brl,
  vlr_repasse_lemon_brl
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`
WHERE ABS(
  vlr_repasse_pre_tusd_gerador_brl
  - vlr_receita_bruta_gerador_brl * (1 - perc_take_rate_aplicado)
) > NUMERIC '0.01'
OR ABS(
  vlr_repasse_gerador_brl
  - (vlr_repasse_pre_tusd_gerador_brl - vlr_tusd_descontada_gerador_brl)
) > NUMERIC '0.01'
OR ABS(
  vlr_repasse_lemon_brl
  - vlr_receita_bruta_gerador_brl * perc_take_rate_aplicado
) > NUMERIC '0.01';

-- 4. Controle: TUSD deve vir do mês de desconto, não do mês operacional.
WITH tusd_esperada AS (
  SELECT
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_desconto_tusd_gerador AS dt_mes_referencia,
    SUM(COALESCE(vlr_tusd_descontada_gerador_brl, 0)) AS valor
  FROM `lemon-ae-case.trusted.usina_energia_mensal`
  WHERE dt_mes_desconto_tusd_gerador IS NOT NULL
  GROUP BY 1, 2, 3, 4
)
SELECT
  r.gerador,
  r.usina,
  r.dt_mes_referencia,
  r.vlr_tusd_descontada_gerador_brl AS valor_refined,
  COALESCE(t.valor, 0) AS valor_esperado
FROM `lemon-ae-case.refined.relatorio_gerador_mensal` AS r
LEFT JOIN tusd_esperada AS t
  USING (gerador, usina, cod_distribuidora, dt_mes_referencia)
WHERE ABS(r.vlr_tusd_descontada_gerador_brl - COALESCE(t.valor, 0))
  > NUMERIC '0.01';

-- 5. Diagnóstico: explica repasses Lemon iguais a zero.
SELECT
  gerador,
  usina,
  dt_mes_referencia,
  perc_desempenho_lemon,
  perc_take_rate_aplicado,
  vlr_receita_bruta_gerador_brl,
  vlr_repasse_lemon_brl,
  CASE
    WHEN vlr_receita_bruta_gerador_brl = 0 THEN 'sem_receita_liquidada_d60'
    WHEN perc_take_rate_aplicado = 0 THEN 'faixa_take_rate_zero'
    ELSE 'revisar_arredondamento_ou_regra'
  END AS motivo
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`
WHERE vlr_repasse_lemon_brl = 0
ORDER BY gerador, usina;
