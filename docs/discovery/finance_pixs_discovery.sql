-- =============================================================================
-- DATA DISCOVERY — raw.finance_pixs
-- Dialeto: GoogleSQL (BigQuery)
-- Execute um bloco numerado por vez.
-- =============================================================================

-- 01. SCHEMA
SELECT
  ordinal_position AS posicao_coluna,
  column_name AS nome_coluna,
  data_type AS tipo_dado,
  is_nullable AS permite_nulo
FROM `lemon-ae-case.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'finance_pixs'
ORDER BY ordinal_position;


-- 02. ESCOPO, GRAIN E CHAVES
SELECT
  COUNT(*) AS quantidade_registros,
  COUNT(DISTINCT source) AS quantidade_identificadores_grafo,
  COUNT(DISTINCT pix_id) AS quantidade_ids_pix,
  COUNT(DISTINCT tx_id) AS quantidade_ids_transacao,
  COUNT(DISTINCT billing_id) AS quantidade_ids_faturamento,
  COUNT(DISTINCT place_id) AS quantidade_locais,
  COUNT(DISTINCT receiver_id) AS quantidade_recebedores,
  COUNT(DISTINCT receiver_type) AS quantidade_tipos_recebedor,
  COUNT(DISTINCT pix_code) AS quantidade_codigos_pix,
  COUNTIF(source = CONCAT('pix#', pix_id))
    AS identificadores_grafo_compativeis_com_id_pix,
  COUNTIF(pix_id = tx_id) AS ids_pix_iguais_aos_ids_transacao
FROM `lemon-ae-case.raw.finance_pixs`;

SELECT
  pix_id,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.finance_pixs`
GROUP BY pix_id
HAVING COUNT(*) > 1
ORDER BY quantidade_registros DESC;


-- 03. STATUS E COMPLETUDE
SELECT
  status,
  COUNT(*) AS quantidade_registros,
  COUNTIF(NULLIF(payment_date, '') IS NULL) AS pagamentos_sem_data,
  COUNTIF(pix_expected_total IS NULL) AS totais_esperados_nulos,
  COUNTIF(pix_paid_total IS NULL) AS totais_pagos_nulos,
  SUM(amount) / 100.0 AS valor_nominal_total_brl
FROM `lemon-ae-case.raw.finance_pixs`
GROUP BY status
ORDER BY quantidade_registros DESC;

SELECT
  COUNT(*) AS quantidade_registros,
  COUNTIF(source IS NULL OR source = '') AS identificadores_grafo_ausentes,
  COUNTIF(pix_id IS NULL OR pix_id = '') AS ids_pix_ausentes,
  COUNTIF(tx_id IS NULL OR tx_id = '') AS ids_transacao_ausentes,
  COUNTIF(billing_id IS NULL OR billing_id = '') AS ids_faturamento_ausentes,
  COUNTIF(pix_code IS NULL OR pix_code = '') AS codigos_pix_ausentes,
  COUNTIF(place_id IS NULL OR place_id = '') AS locais_ausentes,
  COUNTIF(amount IS NULL) AS valores_ausentes,
  COUNTIF(due_date IS NULL OR due_date = '') AS vencimentos_ausentes
FROM `lemon-ae-case.raw.finance_pixs`;


-- 04. VALORES EM CENTAVOS E RECONCILIAÇÃO INTERNA
SELECT
  MIN(amount) / 100.0 AS menor_valor_brl,
  ROUND(AVG(amount) / 100.0, 2) AS valor_medio_brl,
  MAX(amount) / 100.0 AS maior_valor_brl,
  SUM(amount) / 100.0 AS valor_total_brl,
  COUNTIF(
    pix_expected_total IS NOT NULL
    AND pix_expected_total != amount
      + pix_expected_interest
      + pix_expected_fine
  ) AS divergencias_total_esperado,
  COUNTIF(
    pix_paid_total IS NOT NULL
    AND pix_paid_total != amount
      + pix_paid_interest
      + pix_paid_fine
  ) AS divergencias_total_pago,
  COUNTIF(
    pix_paid_total IS NOT NULL
    AND pix_paid_total - pix_paid_interest - pix_paid_fine < 0
  ) AS valores_liquidos_negativos
FROM `lemon-ae-case.raw.finance_pixs`;


-- 05. TEMPORALIDADE DO INSTRUMENTO
SELECT
  MIN(SAFE_CAST(create_at AS TIMESTAMP)) AS primeira_criacao,
  MAX(SAFE_CAST(create_at AS TIMESTAMP)) AS ultima_criacao,
  MIN(SAFE_CAST(due_date AS DATE)) AS primeiro_vencimento,
  MAX(SAFE_CAST(due_date AS DATE)) AS ultimo_vencimento,
  MIN(SAFE_CAST(NULLIF(payment_date, '') AS DATE)) AS primeiro_pagamento,
  MAX(SAFE_CAST(NULLIF(payment_date, '') AS DATE)) AS ultimo_pagamento
FROM `lemon-ae-case.raw.finance_pixs`;

SELECT
  CASE
    WHEN payment_date = '' THEN 'sem_pagamento'
    WHEN SAFE_CAST(payment_date AS DATE) <= SAFE_CAST(due_date AS DATE)
      THEN 'pago_ate_o_vencimento'
    ELSE 'pago_apos_o_vencimento'
  END AS faixa_pagamento,
  COUNT(*) AS quantidade_registros,
  ROUND(AVG(
    CASE
      WHEN payment_date != '' THEN DATE_DIFF(
        SAFE_CAST(payment_date AS DATE),
        SAFE_CAST(due_date AS DATE),
        DAY
      )
    END
  ), 2) AS media_dias_em_relacao_ao_vencimento
FROM `lemon-ae-case.raw.finance_pixs`
GROUP BY faixa_pagamento;


-- 06. VÍNCULO COM BILLING E REEMISSÕES
WITH pix_por_faturamento AS (
  SELECT
    billing_id,
    COUNT(*) AS quantidade_pix,
    COUNTIF(status = 'paid') AS quantidade_pix_pagos,
    COUNTIF(status = 'cancelled') AS quantidade_pix_cancelados,
    COUNTIF(status = 'waitingPayment') AS quantidade_pix_aguardando
  FROM `lemon-ae-case.raw.finance_pixs`
  GROUP BY billing_id
)
SELECT
  quantidade_pix,
  quantidade_pix_pagos,
  quantidade_pix_cancelados,
  quantidade_pix_aguardando,
  COUNT(*) AS quantidade_faturamentos
FROM pix_por_faturamento
GROUP BY
  quantidade_pix,
  quantidade_pix_pagos,
  quantidade_pix_cancelados,
  quantidade_pix_aguardando
ORDER BY quantidade_faturamentos DESC;

-- Redundância controlada: billing_id direto versus aresta no grafo.
SELECT
  COUNTIF(r.source IS NOT NULL) AS quantidade_arestas_pix,
  COUNTIF(r.source = CONCAT('billing#', p.billing_id))
    AS arestas_compativeis_com_id_faturamento,
  COUNTIF(f.source IS NOT NULL) AS pix_com_faturamento,
  COUNTIF(p.place_id = f.place_id) AS locais_iguais
FROM `lemon-ae-case.raw.finance_pixs` AS p
LEFT JOIN `lemon-ae-case.raw.finance_relations` AS r
  ON p.source = r.target
LEFT JOIN `lemon-ae-case.raw.finance_billings` AS f
  ON r.source = f.source;


-- 07. VALOR PAGO DO PIX VERSUS BILLING
WITH pixs_pagos AS (
  SELECT
    r.source AS identificador_grafo_faturamento,
    p.source AS identificador_grafo_pix,
    p.amount,
    p.pix_paid_total,
    p.pix_paid_interest,
    p.pix_paid_fine,
    p.payment_date
  FROM `lemon-ae-case.raw.finance_relations` AS r
  JOIN `lemon-ae-case.raw.finance_pixs` AS p
    ON r.target = p.source
  WHERE p.status = 'paid'
)
SELECT
  COUNT(*) AS quantidade_pix_pagos,
  COUNTIF(p.pix_paid_total = f.billing_paid_total)
    AS totais_pagos_iguais,
  COUNTIF(
    p.pix_paid_total - p.pix_paid_interest - p.pix_paid_fine = f.amount
  ) AS valores_principais_liquidos_iguais_ao_faturamento,
  COUNTIF(p.amount = f.amount) AS valores_nominais_iguais
FROM pixs_pagos AS p
JOIN `lemon-ae-case.raw.finance_billings` AS f
  ON p.identificador_grafo_faturamento = f.source;


-- 08. BILLINGS COM BOLETO E PIX PAGOS
WITH pagamentos AS (
  SELECT
    r.source AS identificador_grafo_faturamento,
    COUNTIF(b.status = 'paid') AS boletos_pagos,
    COUNTIF(p.status = 'paid') AS pix_pagos
  FROM `lemon-ae-case.raw.finance_relations` AS r
  LEFT JOIN `lemon-ae-case.raw.finance_boletos` AS b
    ON r.target = b.source
  LEFT JOIN `lemon-ae-case.raw.finance_pixs` AS p
    ON r.target = p.source
  GROUP BY r.source
)
SELECT
  boletos_pagos,
  pix_pagos,
  COUNT(*) AS quantidade_faturamentos
FROM pagamentos
GROUP BY boletos_pagos, pix_pagos
ORDER BY quantidade_faturamentos DESC;
