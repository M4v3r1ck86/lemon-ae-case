-- =============================================================================
-- DATA DISCOVERY — raw.finance_boletos
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
WHERE table_name = 'finance_boletos'
ORDER BY ordinal_position;


-- 02. ESCOPO, GRAIN E CHAVES
SELECT
  COUNT(*) AS quantidade_registros,
  COUNT(DISTINCT source) AS quantidade_identificadores_grafo,
  COUNT(DISTINCT bank_slip_id) AS quantidade_ids_boleto,
  COUNT(DISTINCT our_number) AS quantidade_nossos_numeros,
  COUNT(DISTINCT place_id) AS quantidade_locais,
  COUNT(DISTINCT receiver_name) AS quantidade_nomes_recebedor,
  COUNT(DISTINCT receiver_id) AS quantidade_recebedores,
  COUNT(DISTINCT receiver_type) AS quantidade_tipos_recebedor,
  COUNTIF(source = CONCAT('boleto#', CAST(bank_slip_id AS STRING)))
    AS identificadores_grafo_compativeis_com_id_boleto
FROM `lemon-ae-case.raw.finance_boletos`;

SELECT
  bank_slip_id,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.finance_boletos`
GROUP BY bank_slip_id
HAVING COUNT(*) > 1
ORDER BY quantidade_registros DESC;


-- 03. STATUS E COMPLETUDE
SELECT
  status,
  COUNT(*) AS quantidade_registros,
  COUNTIF(NULLIF(payment_date, '') IS NULL) AS pagamentos_sem_data,
  COUNTIF(bank_slip_expected_total IS NULL) AS totais_esperados_nulos,
  COUNTIF(bank_slip_paid_total IS NULL) AS totais_pagos_nulos,
  SUM(amount) / 100.0 AS valor_nominal_total_brl
FROM `lemon-ae-case.raw.finance_boletos`
GROUP BY status
ORDER BY quantidade_registros DESC;

SELECT
  COUNT(*) AS quantidade_registros,
  COUNTIF(source IS NULL OR source = '') AS identificadores_grafo_ausentes,
  COUNTIF(bank_slip_id IS NULL) AS ids_boleto_ausentes,
  COUNTIF(our_number IS NULL) AS nossos_numeros_ausentes,
  COUNTIF(place_id IS NULL OR place_id = '') AS locais_ausentes,
  COUNTIF(receiver_id IS NULL OR receiver_id = '') AS recebedores_ausentes,
  COUNTIF(amount IS NULL) AS valores_ausentes,
  COUNTIF(due_date IS NULL OR due_date = '') AS vencimentos_ausentes
FROM `lemon-ae-case.raw.finance_boletos`;


-- 04. VALORES EM CENTAVOS E RECONCILIAÇÃO INTERNA
SELECT
  MIN(amount) / 100.0 AS menor_valor_brl,
  ROUND(AVG(amount) / 100.0, 2) AS valor_medio_brl,
  MAX(amount) / 100.0 AS maior_valor_brl,
  SUM(amount) / 100.0 AS valor_total_brl,
  COUNTIF(
    bank_slip_expected_total IS NOT NULL
    AND bank_slip_expected_total != amount
      + bank_slip_expected_interest
      + bank_slip_expected_fine
  ) AS divergencias_total_esperado,
  COUNTIF(
    bank_slip_paid_total IS NOT NULL
    AND bank_slip_paid_total != amount
      + bank_slip_paid_interest
      + bank_slip_paid_fine
  ) AS divergencias_total_pago,
  COUNTIF(
    bank_slip_paid_total IS NOT NULL
    AND bank_slip_paid_total
      - bank_slip_paid_interest
      - bank_slip_paid_fine < 0
  ) AS valores_liquidos_negativos
FROM `lemon-ae-case.raw.finance_boletos`;


-- 05. TEMPORALIDADE DO INSTRUMENTO
SELECT
  MIN(SAFE_CAST(create_at AS TIMESTAMP)) AS primeira_criacao,
  MAX(SAFE_CAST(create_at AS TIMESTAMP)) AS ultima_criacao,
  MIN(SAFE_CAST(due_date AS DATE)) AS primeiro_vencimento,
  MAX(SAFE_CAST(due_date AS DATE)) AS ultimo_vencimento,
  MIN(SAFE_CAST(NULLIF(payment_date, '') AS DATE)) AS primeiro_pagamento,
  MAX(SAFE_CAST(NULLIF(payment_date, '') AS DATE)) AS ultimo_pagamento
FROM `lemon-ae-case.raw.finance_boletos`;

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
FROM `lemon-ae-case.raw.finance_boletos`
GROUP BY faixa_pagamento;


-- 06. VÍNCULO COM BILLING E REEMISSÕES
WITH boletos_por_billing AS (
  SELECT
    r.source AS identificador_grafo_faturamento,
    COUNT(*) AS quantidade_boletos,
    COUNTIF(b.status = 'paid') AS quantidade_boletos_pagos,
    COUNTIF(b.status = 'cancelled') AS quantidade_boletos_cancelados,
    COUNTIF(b.status = 'waitingPayment') AS quantidade_boletos_aguardando
  FROM `lemon-ae-case.raw.finance_relations` AS r
  JOIN `lemon-ae-case.raw.finance_boletos` AS b
    ON r.target = b.source
  WHERE STARTS_WITH(r.target, 'boleto#')
  GROUP BY r.source
)
SELECT
  quantidade_boletos,
  quantidade_boletos_pagos,
  quantidade_boletos_cancelados,
  quantidade_boletos_aguardando,
  COUNT(*) AS quantidade_faturamentos
FROM boletos_por_billing
GROUP BY
  quantidade_boletos,
  quantidade_boletos_pagos,
  quantidade_boletos_cancelados,
  quantidade_boletos_aguardando
ORDER BY quantidade_faturamentos DESC;

-- Confere cobertura da aresta e consistência do local.
SELECT
  COUNT(*) AS quantidade_boletos,
  COUNTIF(r.source IS NOT NULL) AS boletos_com_aresta,
  COUNTIF(f.source IS NOT NULL) AS boletos_com_faturamento,
  COUNTIF(b.place_id = f.place_id) AS locais_iguais
FROM `lemon-ae-case.raw.finance_boletos` AS b
LEFT JOIN `lemon-ae-case.raw.finance_relations` AS r
  ON b.source = r.target
LEFT JOIN `lemon-ae-case.raw.finance_billings` AS f
  ON r.source = f.source;


-- 07. VALOR PAGO DO BOLETO VERSUS BILLING
WITH boletos_pagos AS (
  SELECT
    r.source AS identificador_grafo_faturamento,
    b.source AS identificador_grafo_boleto,
    b.amount,
    b.bank_slip_paid_total,
    b.bank_slip_paid_interest,
    b.bank_slip_paid_fine,
    b.payment_date
  FROM `lemon-ae-case.raw.finance_relations` AS r
  JOIN `lemon-ae-case.raw.finance_boletos` AS b
    ON r.target = b.source
  WHERE b.status = 'paid'
)
SELECT
  COUNT(*) AS quantidade_boletos_pagos,
  COUNTIF(
    p.bank_slip_paid_total = f.billing_paid_total
  ) AS totais_pagos_iguais,
  COUNTIF(
    p.bank_slip_paid_total
      - p.bank_slip_paid_interest
      - p.bank_slip_paid_fine = f.amount
  ) AS valores_principais_liquidos_iguais_ao_faturamento,
  COUNTIF(p.amount = f.amount) AS valores_nominais_iguais
FROM boletos_pagos AS p
JOIN `lemon-ae-case.raw.finance_billings` AS f
  ON p.identificador_grafo_faturamento = f.source;
