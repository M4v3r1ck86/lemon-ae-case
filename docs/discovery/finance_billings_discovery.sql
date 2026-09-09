-- =============================================================================
-- DATA DISCOVERY — raw.finance_billings
-- Dialeto: GoogleSQL (BigQuery)
-- Execute um bloco numerado por vez.
-- Nomes da fonte são preservados; indicadores derivados estão em português.
-- =============================================================================

-- 01. SCHEMA
SELECT
  ordinal_position AS posicao_coluna,
  column_name AS nome_coluna,
  data_type AS tipo_dado,
  is_nullable AS permite_nulo
FROM `lemon-ae-case.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'finance_billings'
ORDER BY ordinal_position;


-- 02. ESCOPO, GRAIN E CHAVES
WITH
place_mes AS (
  SELECT DISTINCT
    place_id,
    REGEXP_EXTRACT(billing_id, r'#(\d{4}-\d{2}-\d{2})$') AS mes_no_identificador
  FROM `lemon-ae-case.raw.finance_billings`
)
SELECT
  COUNT(*) AS quantidade_registros,
  COUNT(DISTINCT source) AS quantidade_identificadores_grafo,
  COUNT(DISTINCT billing_id) AS quantidade_ids_faturamento,
  COUNT(DISTINCT place_id) AS quantidade_locais,
  COUNT(DISTINCT billing_energy_farm_id) AS quantidade_ids_usina_backend,
  (SELECT COUNT(*) FROM place_mes) AS quantidade_combinacoes_local_mes,
  COUNTIF(source = CONCAT('billing#', billing_id))
    AS identificadores_grafo_compativeis_com_id_faturamento
FROM `lemon-ae-case.raw.finance_billings`;

SELECT
  billing_id,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.finance_billings`
GROUP BY billing_id
HAVING COUNT(*) > 1
ORDER BY quantidade_registros DESC, billing_id;


-- 03. COMPLETUDE E STATUS
SELECT
  status,
  COUNT(*) AS quantidade_registros,
  COUNTIF(NULLIF(billing_payment_date, '') IS NULL)
    AS pagamentos_sem_data,
  COUNTIF(billing_expected_total IS NULL) AS totais_esperados_nulos,
  COUNTIF(billing_paid_total IS NULL) AS totais_pagos_nulos,
  COUNTIF(due_date != original_due_date) AS vencimentos_alterados,
  COUNTIF(billing_rescheduled_times IS NOT NULL)
    AS reagendamentos_informados,
  SUM(amount) / 100.0 AS valor_nominal_total_brl
FROM `lemon-ae-case.raw.finance_billings`
GROUP BY status
ORDER BY quantidade_registros DESC;

SELECT
  COUNT(*) AS quantidade_registros,
  COUNTIF(source IS NULL OR source = '') AS identificadores_grafo_ausentes,
  COUNTIF(billing_id IS NULL OR billing_id = '') AS ids_faturamento_ausentes,
  COUNTIF(place_id IS NULL OR place_id = '') AS locais_ausentes,
  COUNTIF(amount IS NULL) AS valores_ausentes,
  COUNTIF(status IS NULL OR status = '') AS status_ausentes,
  COUNTIF(create_at IS NULL OR create_at = '') AS criacoes_ausentes,
  COUNTIF(due_date IS NULL OR due_date = '') AS vencimentos_ausentes,
  COUNTIF(billing_energy_farm_id IS NULL OR billing_energy_farm_id = '')
    AS ids_usina_backend_ausentes,
  COUNTIF(cancelled_at = '') AS cancelamentos_sem_data,
  COUNTIF(cancellation_reason = '') AS cancelamentos_sem_motivo
FROM `lemon-ae-case.raw.finance_billings`;


-- 04. VALORES EM CENTAVOS E RECONCILIAÇÃO INTERNA
SELECT
  MIN(amount) / 100.0 AS menor_valor_brl,
  ROUND(AVG(amount) / 100.0, 2) AS valor_medio_brl,
  MAX(amount) / 100.0 AS maior_valor_brl,
  SUM(amount) / 100.0 AS valor_total_brl,
  COUNTIF(
    amount != amount_without_discounts - temporary_discount_amount
  ) AS divergencias_desconto,
  COUNTIF(
    billing_expected_total IS NOT NULL
    AND billing_expected_total != amount
      + billing_expected_interest
      + billing_expected_fine
  ) AS divergencias_total_esperado,
  COUNTIF(
    billing_paid_total IS NOT NULL
    AND billing_paid_total != amount
      + billing_paid_interest
      + billing_paid_fine
  ) AS divergencias_total_pago,
  COUNTIF(
    billing_paid_total IS NOT NULL
    AND billing_paid_total != billing_expected_total
  ) AS pagamentos_diferentes_do_esperado
FROM `lemon-ae-case.raw.finance_billings`;

-- Linhas que não obedecem às equações monetárias candidatas.
SELECT
  source,
  status,
  amount,
  billing_expected_total,
  billing_expected_interest,
  billing_expected_fine,
  billing_paid_total,
  billing_paid_interest,
  billing_paid_fine
FROM `lemon-ae-case.raw.finance_billings`
WHERE
  (
    billing_expected_total IS NOT NULL
    AND billing_expected_total != amount
      + billing_expected_interest
      + billing_expected_fine
  )
  OR (
    billing_paid_total IS NOT NULL
    AND billing_paid_total != amount
      + billing_paid_interest
      + billing_paid_fine
  );


-- 05. TEMPORALIDADE E REAGENDAMENTO
SELECT
  MIN(SAFE_CAST(create_at AS TIMESTAMP)) AS primeira_criacao,
  MAX(SAFE_CAST(create_at AS TIMESTAMP)) AS ultima_criacao,
  MIN(SAFE_CAST(due_date AS DATE)) AS primeiro_vencimento,
  MAX(SAFE_CAST(due_date AS DATE)) AS ultimo_vencimento,
  MIN(SAFE_CAST(NULLIF(billing_payment_date, '') AS TIMESTAMP))
    AS primeiro_pagamento,
  MAX(SAFE_CAST(NULLIF(billing_payment_date, '') AS TIMESTAMP))
    AS ultimo_pagamento,
  MIN(SAFE_CAST(ingestion_time AS TIMESTAMP)) AS primeira_ingestao_origem,
  MAX(SAFE_CAST(ingestion_time AS TIMESTAMP)) AS ultima_ingestao_origem
FROM `lemon-ae-case.raw.finance_billings`;

SELECT
  billing_rescheduled_times,
  due_date = original_due_date AS vencimento_inalterado,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.finance_billings`
GROUP BY billing_rescheduled_times, vencimento_inalterado
ORDER BY billing_rescheduled_times, vencimento_inalterado;


-- 06. RECEBEDOR
SELECT
  billing_receiver_type,
  billing_receiver_id,
  status,
  COUNT(*) AS quantidade_registros,
  SUM(amount) / 100.0 AS valor_total_brl
FROM `lemon-ae-case.raw.finance_billings`
GROUP BY billing_receiver_type, billing_receiver_id, status
ORDER BY quantidade_registros DESC;


-- 07. RELACIONAMENTOS E CARDINALIDADE DOS INSTRUMENTOS
WITH arestas AS (
  SELECT
    source,
    COUNTIF(STARTS_WITH(target, 'charge#')) AS quantidade_cobrancas,
    COUNTIF(STARTS_WITH(target, 'boleto#')) AS quantidade_boletos,
    COUNTIF(STARTS_WITH(target, 'pix#')) AS quantidade_pix
  FROM `lemon-ae-case.raw.finance_relations`
  GROUP BY source
)
SELECT
  quantidade_cobrancas,
  quantidade_boletos,
  quantidade_pix,
  COUNT(*) AS quantidade_faturamentos
FROM arestas
GROUP BY quantidade_cobrancas, quantidade_boletos, quantidade_pix
ORDER BY quantidade_faturamentos DESC;

-- Confere o vínculo direto entre billing e charge.
SELECT
  COUNT(*) AS quantidade_cobrancas,
  COUNTIF(b.billing_id IS NOT NULL) AS cobrancas_com_faturamento,
  COUNTIF(c.amount = b.amount) AS valores_iguais,
  COUNTIF(c.status = b.status) AS status_iguais,
  COUNTIF(c.place_id = b.place_id) AS locais_iguais
FROM `lemon-ae-case.raw.finance_charges` AS c
LEFT JOIN `lemon-ae-case.raw.finance_billings` AS b
  ON c.billing_id = b.billing_id;

-- Resolve o ID de usina do backend por charge e cliente.
WITH pares AS (
  SELECT DISTINCT
    b.billing_energy_farm_id,
    e.usina,
    e.gerador,
    e.disco
  FROM `lemon-ae-case.raw.finance_billings` AS b
  JOIN `lemon-ae-case.raw.finance_charges` AS c
    ON b.billing_id = c.billing_id
  JOIN `lemon-ae-case.raw.energy_clients` AS e
    ON c.disco_consumer_unit_id = e.numero_instalacao
   AND c.reference_month = e.mes_referencia
),
por_id_backend AS (
  SELECT
    billing_energy_farm_id,
    COUNT(*) AS quantidade_usinas
  FROM pares
  GROUP BY billing_energy_farm_id
)
SELECT
  COUNT(*) AS quantidade_ids_usina_backend,
  COUNTIF(quantidade_usinas = 1) AS ids_associados_a_uma_usina,
  COUNTIF(quantidade_usinas > 1) AS ids_associados_a_varias_usinas,
  MAX(quantidade_usinas) AS maior_quantidade_usinas_por_id
FROM por_id_backend;


-- 08. RISCO DE FANOUT NA GENERATOR_REPORT
WITH
charges AS (
  SELECT source, COUNTIF(STARTS_WITH(target, 'charge#')) AS quantidade
  FROM `lemon-ae-case.raw.finance_relations`
  GROUP BY source
),
boletos AS (
  SELECT source, COUNTIF(STARTS_WITH(target, 'boleto#')) AS quantidade
  FROM `lemon-ae-case.raw.finance_relations`
  GROUP BY source
),
pixs AS (
  SELECT source, COUNTIF(STARTS_WITH(target, 'pix#')) AS quantidade
  FROM `lemon-ae-case.raw.finance_relations`
  GROUP BY source
)
SELECT
  COUNT(*) AS quantidade_faturamentos,
  SUM(charges.quantidade * boletos.quantidade)
    AS linhas_estimadas_ramo_boleto,
  SUM(charges.quantidade * pixs.quantidade)
    AS linhas_estimadas_ramo_pix,
  SUM(
    charges.quantidade
    * (boletos.quantidade + pixs.quantidade)
  ) AS linhas_estimadas_union_all
FROM charges
JOIN boletos USING (source)
JOIN pixs USING (source);
