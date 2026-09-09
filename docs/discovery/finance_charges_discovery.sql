-- =============================================================================
-- DATA DISCOVERY — raw.finance_charges
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
WHERE table_name = 'finance_charges'
ORDER BY ordinal_position;


-- 02. ESCOPO, GRAIN E CHAVES
WITH
instalacao_mes AS (
  SELECT DISTINCT disco_consumer_unit_id, reference_month
  FROM `lemon-ae-case.raw.finance_charges`
),
assinatura_mes AS (
  SELECT DISTINCT subscription_id, reference_month
  FROM `lemon-ae-case.raw.finance_charges`
),
plano_mes AS (
  SELECT DISTINCT billing_plan_id, reference_month
  FROM `lemon-ae-case.raw.finance_charges`
)
SELECT
  COUNT(*) AS quantidade_registros,
  COUNT(DISTINCT source) AS quantidade_identificadores_grafo,
  COUNT(DISTINCT charge_id) AS quantidade_ids_cobranca,
  COUNT(DISTINCT billing_id) AS quantidade_ids_faturamento,
  COUNT(DISTINCT disco_consumer_unit_id) AS quantidade_instalacoes,
  COUNT(DISTINCT place_id) AS quantidade_locais,
  COUNT(DISTINCT subscription_id) AS quantidade_assinaturas,
  (SELECT COUNT(*) FROM instalacao_mes) AS quantidade_instalacoes_mes,
  (SELECT COUNT(*) FROM assinatura_mes) AS quantidade_assinaturas_mes,
  (SELECT COUNT(*) FROM plano_mes) AS quantidade_planos_mes,
  COUNTIF(source = CONCAT('charge#', charge_id))
    AS identificadores_grafo_compativeis_com_id_cobranca,
  COUNTIF(billing_id = CONCAT(billing_plan_id, '#', reference_month))
    AS ids_faturamento_derivaveis
FROM `lemon-ae-case.raw.finance_charges`;

SELECT
  disco_consumer_unit_id,
  reference_month,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.finance_charges`
GROUP BY disco_consumer_unit_id, reference_month
HAVING COUNT(*) > 1
ORDER BY quantidade_registros DESC;


-- 03. DISTRIBUIÇÃO MENSAL, STATUS E COMPLETUDE
SELECT
  reference_month,
  COUNT(*) AS quantidade_registros,
  COUNT(DISTINCT disco_consumer_unit_id) AS quantidade_instalacoes,
  COUNTIF(status = 'paid') AS quantidade_pagas,
  COUNTIF(status = 'waitingPayment') AS quantidade_aguardando_pagamento,
  SUM(amount) / 100.0 AS valor_total_brl
FROM `lemon-ae-case.raw.finance_charges`
GROUP BY reference_month
ORDER BY SAFE_CAST(reference_month AS DATE);

SELECT
  status,
  COUNT(*) AS quantidade_registros,
  COUNTIF(NULLIF(payment_date, '') IS NULL) AS pagamentos_sem_data,
  COUNTIF(NULLIF(cancelled_at, '') IS NOT NULL)
    AS cancelamentos_com_data,
  SUM(amount) / 100.0 AS valor_total_brl
FROM `lemon-ae-case.raw.finance_charges`
GROUP BY status
ORDER BY quantidade_registros DESC;


-- 04. VALORES E DOMÍNIOS CATEGÓRICOS
SELECT
  MIN(amount) / 100.0 AS menor_valor_brl,
  ROUND(AVG(amount) / 100.0, 2) AS valor_medio_brl,
  MAX(amount) / 100.0 AS maior_valor_brl,
  SUM(amount) / 100.0 AS valor_total_brl,
  COUNTIF(
    amount != amount_without_discounts - temporary_discount_amount
  ) AS divergencias_desconto
FROM `lemon-ae-case.raw.finance_charges`;

SELECT
  distribution_company,
  product,
  charge_provider_type,
  subscriber_type,
  `type`,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.finance_charges`
GROUP BY
  distribution_company,
  product,
  charge_provider_type,
  subscriber_type,
  `type`;


-- 05. RECONCILIAÇÃO COM ENERGY_CLIENTS
-- amount está em centavos; gmv_real_oficial_brl está em BRL.
WITH resultado AS (
  SELECT
    f.source,
    f.disco_consumer_unit_id,
    f.reference_month,
    f.amount / 100.0 AS valor_cobranca_brl,
    c.gmv_real_oficial_brl,
    f.amount / 100.0 - c.gmv_real_oficial_brl AS diferenca_brl,
    c.numero_instalacao IS NOT NULL AS encontrou_cliente
  FROM `lemon-ae-case.raw.finance_charges` AS f
  LEFT JOIN `lemon-ae-case.raw.energy_clients` AS c
    ON f.disco_consumer_unit_id = c.numero_instalacao
   AND f.reference_month = c.mes_referencia
)
SELECT
  COUNT(*) AS quantidade_cobrancas,
  COUNTIF(encontrou_cliente) AS cobrancas_com_cliente,
  COUNTIF(NOT encontrou_cliente) AS cobrancas_sem_cliente,
  COUNTIF(encontrou_cliente AND ABS(diferenca_brl) <= 0.02)
    AS valores_reconciliados,
  COUNTIF(encontrou_cliente AND ABS(diferenca_brl) > 0.02)
    AS valores_divergentes,
  MAX(ABS(diferenca_brl)) AS maior_diferenca_brl
FROM resultado;

-- Mede também a obrigatoriedade no sentido cliente → charge.
SELECT
  COUNT(*) AS quantidade_clientes_mes,
  COUNTIF(f.source IS NOT NULL) AS clientes_com_cobranca,
  COUNTIF(f.source IS NULL) AS clientes_sem_cobranca
FROM `lemon-ae-case.raw.energy_clients` AS c
LEFT JOIN `lemon-ae-case.raw.finance_charges` AS f
  ON c.numero_instalacao = f.disco_consumer_unit_id
 AND c.mes_referencia = f.reference_month;


-- 06. ESTABILIDADE DOS IDENTIFICADORES DA UNIDADE
WITH por_instalacao AS (
  SELECT
    disco_consumer_unit_id,
    COUNT(DISTINCT place_id) AS quantidade_locais,
    COUNT(DISTINCT subscriber_id) AS quantidade_assinantes,
    COUNT(DISTINCT subscription_id) AS quantidade_assinaturas,
    COUNT(DISTINCT billing_plan_id) AS quantidade_planos,
    COUNT(DISTINCT distribution_company) AS quantidade_distribuidoras
  FROM `lemon-ae-case.raw.finance_charges`
  GROUP BY disco_consumer_unit_id
)
SELECT
  COUNT(*) AS quantidade_instalacoes,
  COUNTIF(quantidade_locais = 1) AS instalacoes_com_um_local,
  COUNTIF(quantidade_assinantes = 1) AS instalacoes_com_um_assinante,
  COUNTIF(quantidade_assinaturas = 1) AS instalacoes_com_uma_assinatura,
  COUNTIF(quantidade_planos = 1) AS instalacoes_com_um_plano,
  COUNTIF(quantidade_distribuidoras = 1)
    AS instalacoes_com_uma_distribuidora
FROM por_instalacao;

-- Confirma se algum identificador aponta para mais de uma unidade.
SELECT
  (SELECT COUNT(*)
   FROM (
     SELECT place_id
     FROM `lemon-ae-case.raw.finance_charges`
     GROUP BY place_id
     HAVING COUNT(DISTINCT disco_consumer_unit_id) > 1
   )) AS locais_com_multiplas_instalacoes,
  (SELECT COUNT(*)
   FROM (
     SELECT subscriber_id
     FROM `lemon-ae-case.raw.finance_charges`
     GROUP BY subscriber_id
     HAVING COUNT(DISTINCT disco_consumer_unit_id) > 1
   )) AS assinantes_com_multiplas_instalacoes,
  (SELECT COUNT(*)
   FROM (
     SELECT subscription_id
     FROM `lemon-ae-case.raw.finance_charges`
     GROUP BY subscription_id
     HAVING COUNT(DISTINCT disco_consumer_unit_id) > 1
   )) AS assinaturas_com_multiplas_instalacoes,
  (SELECT COUNT(*)
   FROM (
     SELECT billing_plan_id
     FROM `lemon-ae-case.raw.finance_charges`
     GROUP BY billing_plan_id
     HAVING COUNT(DISTINCT disco_consumer_unit_id) > 1
   )) AS planos_com_multiplas_instalacoes;


-- 07. RECONCILIAÇÃO COM BILLINGS E FINANCE_RELATIONS
SELECT
  COUNT(*) AS quantidade_cobrancas,
  COUNTIF(b.billing_id IS NOT NULL) AS cobrancas_com_faturamento,
  COUNTIF(c.amount = b.amount) AS valores_iguais,
  COUNTIF(c.status = b.status) AS status_iguais,
  COUNTIF(c.place_id = b.place_id) AS locais_iguais
FROM `lemon-ae-case.raw.finance_charges` AS c
LEFT JOIN `lemon-ae-case.raw.finance_billings` AS b
  ON c.billing_id = b.billing_id;

SELECT
  COUNT(*) AS quantidade_arestas_charge,
  COUNTIF(r.source = CONCAT('billing#', c.billing_id))
    AS arestas_compativeis_com_id_faturamento,
  COUNT(DISTINCT r.target) AS quantidade_destinos_cobranca
FROM `lemon-ae-case.raw.finance_relations` AS r
JOIN `lemon-ae-case.raw.finance_charges` AS c
  ON r.target = c.source
WHERE STARTS_WITH(r.target, 'charge#');


-- 08. DATAS DE PAGAMENTO ENTRE CHARGE E BILLING
SELECT
  CASE
    WHEN c.payment_date = '' THEN 'sem_pagamento'
    WHEN SAFE_CAST(c.payment_date AS DATE)
      = DATE(SAFE_CAST(NULLIF(b.billing_payment_date, '') AS TIMESTAMP))
      THEN 'mesma_data'
    ELSE 'data_diferente'
  END AS situacao_data_pagamento,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.finance_charges` AS c
JOIN `lemon-ae-case.raw.finance_billings` AS b
  ON c.billing_id = b.billing_id
GROUP BY situacao_data_pagamento
ORDER BY quantidade_registros DESC;
