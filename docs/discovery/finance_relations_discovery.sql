-- =============================================================================
-- DATA DISCOVERY — raw.finance_relations
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
WHERE table_name = 'finance_relations'
ORDER BY ordinal_position;


-- 02. ESCOPO, GRAIN, CHAVE E TIPOS DE ARESTA
WITH tipadas AS (
  SELECT
    source,
    target,
    SPLIT(source, '#')[SAFE_OFFSET(0)] AS tipo_origem,
    SPLIT(target, '#')[SAFE_OFFSET(0)] AS tipo_destino
  FROM `lemon-ae-case.raw.finance_relations`
)
SELECT
  tipo_origem,
  tipo_destino,
  COUNT(*) AS quantidade_arestas,
  COUNT(DISTINCT source) AS quantidade_origens,
  COUNT(DISTINCT target) AS quantidade_destinos
FROM tipadas
GROUP BY tipo_origem, tipo_destino
ORDER BY tipo_origem, tipo_destino;

WITH pares AS (
  SELECT DISTINCT source, target
  FROM `lemon-ae-case.raw.finance_relations`
)
SELECT
  (SELECT COUNT(*) FROM `lemon-ae-case.raw.finance_relations`)
    AS quantidade_arestas,
  (SELECT COUNT(*) FROM pares) AS quantidade_pares_unicos,
  (SELECT COUNT(DISTINCT source)
   FROM `lemon-ae-case.raw.finance_relations`)
    AS quantidade_identificadores_origem,
  (SELECT COUNT(DISTINCT target)
   FROM `lemon-ae-case.raw.finance_relations`)
    AS quantidade_identificadores_destino;


-- 03. INTEGRIDADE REFERENCIAL
SELECT
  COUNTIF(NOT STARTS_WITH(r.source, 'billing#'))
    AS origens_com_prefixo_invalido,
  COUNTIF(
    STARTS_WITH(r.target, 'charge#') AND c.source IS NULL
  ) AS cobrancas_orfas,
  COUNTIF(
    STARTS_WITH(r.target, 'boleto#') AND b.source IS NULL
  ) AS boletos_orfaos,
  COUNTIF(
    STARTS_WITH(r.target, 'pix#') AND p.source IS NULL
  ) AS pix_orfaos,
  COUNTIF(f.source IS NULL) AS faturamentos_orfaos
FROM `lemon-ae-case.raw.finance_relations` AS r
LEFT JOIN `lemon-ae-case.raw.finance_billings` AS f
  ON r.source = f.source
LEFT JOIN `lemon-ae-case.raw.finance_charges` AS c
  ON r.target = c.source
LEFT JOIN `lemon-ae-case.raw.finance_boletos` AS b
  ON r.target = b.source
LEFT JOIN `lemon-ae-case.raw.finance_pixs` AS p
  ON r.target = p.source;

SELECT
  (SELECT COUNT(*)
   FROM `lemon-ae-case.raw.finance_billings` AS f
   WHERE NOT EXISTS (
     SELECT 1
     FROM `lemon-ae-case.raw.finance_relations` AS r
     WHERE r.source = f.source
   )) AS faturamentos_sem_aresta,
  (SELECT COUNT(*)
   FROM `lemon-ae-case.raw.finance_charges` AS c
   WHERE NOT EXISTS (
     SELECT 1
     FROM `lemon-ae-case.raw.finance_relations` AS r
     WHERE r.target = c.source
   )) AS cobrancas_sem_aresta,
  (SELECT COUNT(*)
   FROM `lemon-ae-case.raw.finance_boletos` AS b
   WHERE NOT EXISTS (
     SELECT 1
     FROM `lemon-ae-case.raw.finance_relations` AS r
     WHERE r.target = b.source
   )) AS boletos_sem_aresta,
  (SELECT COUNT(*)
   FROM `lemon-ae-case.raw.finance_pixs` AS p
   WHERE NOT EXISTS (
     SELECT 1
     FROM `lemon-ae-case.raw.finance_relations` AS r
     WHERE r.target = p.source
   )) AS pix_sem_aresta;


-- 04. CARDINALIDADE POR BILLING
WITH por_billing AS (
  SELECT
    source,
    COUNTIF(STARTS_WITH(target, 'charge#')) AS quantidade_cobrancas,
    COUNTIF(STARTS_WITH(target, 'boleto#')) AS quantidade_boletos,
    COUNTIF(STARTS_WITH(target, 'pix#')) AS quantidade_pix,
    COUNT(*) AS quantidade_arestas
  FROM `lemon-ae-case.raw.finance_relations`
  GROUP BY source
)
SELECT
  quantidade_cobrancas,
  quantidade_boletos,
  quantidade_pix,
  quantidade_arestas,
  COUNT(*) AS quantidade_faturamentos
FROM por_billing
GROUP BY
  quantidade_cobrancas,
  quantidade_boletos,
  quantidade_pix,
  quantidade_arestas
ORDER BY quantidade_faturamentos DESC;


-- 05. CONSISTÊNCIA COM IDS DIRETOS DAS ENTIDADES
SELECT
  COUNT(*) AS quantidade_arestas_cobranca,
  COUNTIF(r.source = CONCAT('billing#', c.billing_id))
    AS arestas_cobranca_consistentes
FROM `lemon-ae-case.raw.finance_relations` AS r
JOIN `lemon-ae-case.raw.finance_charges` AS c
  ON r.target = c.source
WHERE STARTS_WITH(r.target, 'charge#');

SELECT
  COUNT(*) AS quantidade_arestas_pix,
  COUNTIF(r.source = CONCAT('billing#', p.billing_id))
    AS arestas_pix_consistentes
FROM `lemon-ae-case.raw.finance_relations` AS r
JOIN `lemon-ae-case.raw.finance_pixs` AS p
  ON r.target = p.source
WHERE STARTS_WITH(r.target, 'pix#');


-- 06. MÉTODOS DE PAGAMENTO E POSSÍVEL DUPLICIDADE
WITH instrumentos AS (
  SELECT
    r.source,
    COUNTIF(b.status = 'paid') AS quantidade_boletos_pagos,
  COUNTIF(p.status = 'paid') AS quantidade_pix_pagos,
    COUNTIF(b.status = 'waitingPayment')
      + COUNTIF(p.status = 'waitingPayment') AS quantidade_aguardando,
    COUNTIF(b.status = 'cancelled')
      + COUNTIF(p.status = 'cancelled') AS quantidade_cancelados
  FROM `lemon-ae-case.raw.finance_relations` AS r
  LEFT JOIN `lemon-ae-case.raw.finance_boletos` AS b
    ON r.target = b.source
  LEFT JOIN `lemon-ae-case.raw.finance_pixs` AS p
    ON r.target = p.source
  GROUP BY r.source
)
SELECT
  quantidade_boletos_pagos,
  quantidade_pix_pagos,
  quantidade_aguardando,
  quantidade_cancelados,
  COUNT(*) AS quantidade_faturamentos
FROM instrumentos
GROUP BY
  quantidade_boletos_pagos,
  quantidade_pix_pagos,
  quantidade_aguardando,
  quantidade_cancelados
ORDER BY quantidade_faturamentos DESC;

-- Compara o estado consolidado dos instrumentos com o status do billing.
WITH instrumentos AS (
  SELECT
    r.source,
    COUNTIF(b.status = 'paid') + COUNTIF(p.status = 'paid')
      AS quantidade_instrumentos_pagos,
    COUNTIF(b.status = 'waitingPayment')
      + COUNTIF(p.status = 'waitingPayment')
      AS quantidade_instrumentos_aguardando
  FROM `lemon-ae-case.raw.finance_relations` AS r
  LEFT JOIN `lemon-ae-case.raw.finance_boletos` AS b
    ON r.target = b.source
  LEFT JOIN `lemon-ae-case.raw.finance_pixs` AS p
    ON r.target = p.source
  GROUP BY r.source
)
SELECT
  f.status AS status_faturamento,
  i.quantidade_instrumentos_pagos,
  i.quantidade_instrumentos_aguardando,
  COUNT(*) AS quantidade_faturamentos
FROM instrumentos AS i
JOIN `lemon-ae-case.raw.finance_billings` AS f
  ON i.source = f.source
GROUP BY
  status_faturamento,
  quantidade_instrumentos_pagos,
  quantidade_instrumentos_aguardando
ORDER BY quantidade_faturamentos DESC;


-- 07. FANOUT PRODUZIDO PELOS DOIS RAMOS DA VIEW
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
    AS linhas_ramo_boleto,
  SUM(charges.quantidade * pixs.quantidade)
    AS linhas_ramo_pix,
  SUM(charges.quantidade * (boletos.quantidade + pixs.quantidade))
    AS linhas_apos_union_all
FROM charges
JOIN boletos USING (source)
JOIN pixs USING (source);


-- 08. TEMPORALIDADE DAS ARESTAS
SELECT
  MIN(SAFE_CAST(create_at AS TIMESTAMP)) AS primeira_criacao,
  MAX(SAFE_CAST(create_at AS TIMESTAMP)) AS ultima_criacao,
  MIN(SAFE_CAST(ingestion_time AS TIMESTAMP)) AS primeira_ingestao_origem,
  MAX(SAFE_CAST(ingestion_time AS TIMESTAMP)) AS ultima_ingestao_origem,
  COUNT(DISTINCT ingestion_time) AS quantidade_horarios_ingestao_origem,
  COUNTIF(
    SAFE_CAST(ingestion_time AS TIMESTAMP)
      < SAFE_CAST(create_at AS TIMESTAMP)
  ) AS ingestoes_anteriores_a_criacao
FROM `lemon-ae-case.raw.finance_relations`;
