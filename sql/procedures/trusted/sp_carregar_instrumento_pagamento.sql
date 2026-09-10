-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_INSTRUMENTO_PAGAMENTO
-- Objetivo: unificar boletos e PIX em um contrato comum de pagamento.
-- Grain: uma linha por tipo_instrumento + id_instrumento.
-- Estratégia: UNION ALL, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_instrumento_pagamento`()
BEGIN
  -- ETAPA 1 — BOLETOS
  -- O id_faturamento é recuperado pela relação faturamento para boleto.
  CREATE TEMP TABLE tmp_instrumento_boleto AS
  SELECT
    'boleto' AS tipo_instrumento,
    CAST(b.id_boleto AS STRING) AS id_instrumento,
    b.id_grafo_boleto AS id_grafo_instrumento,
    r.id_origem AS id_faturamento,
    b.id_local,
    b.status_boleto AS status_instrumento,
    b.ts_criado_em,
    b.dt_vencimento,
    b.dt_pagamento,
    b.vlr_boleto_brl AS vlr_instrumento_brl,
    b.vlr_total_esperado_brl,
    b.vlr_juros_esperado_brl,
    b.vlr_multa_esperada_brl,
    b.vlr_total_pago_brl,
    b.vlr_juros_pago_brl,
    b.vlr_multa_paga_brl,
    b.id_recebedor,
    b.tipo_recebedor,
    b.ts_ingestao_origem,
    b.ingerido_em
  FROM `lemon-ae-case.trusted.boleto` AS b
  LEFT JOIN `lemon-ae-case.trusted.relacao_financeira` AS r
    ON b.id_grafo_boleto = r.id_grafo_destino
    AND r.tipo_entidade_origem = 'billing'
    AND r.tipo_entidade_destino = 'boleto';

  -- ETAPA 2 — PIX
  -- O PIX já contém o id_faturamento diretamente.
  CREATE TEMP TABLE tmp_instrumento_pix AS
  SELECT
    'pix' AS tipo_instrumento,
    p.id_pix AS id_instrumento,
    p.id_grafo_pix AS id_grafo_instrumento,
    p.id_faturamento,
    p.id_local,
    p.status_pix AS status_instrumento,
    p.ts_criado_em,
    p.dt_vencimento,
    p.dt_pagamento,
    p.vlr_pix_brl AS vlr_instrumento_brl,
    p.vlr_total_esperado_brl,
    p.vlr_juros_esperado_brl,
    p.vlr_multa_esperada_brl,
    p.vlr_total_pago_brl,
    p.vlr_juros_pago_brl,
    p.vlr_multa_paga_brl,
    p.id_recebedor,
    p.tipo_recebedor,
    p.ts_ingestao_origem,
    p.ingerido_em
  FROM `lemon-ae-case.trusted.pix` AS p;

  -- ETAPA 3 — UNIÃO E DEDUPLICAÇÃO
  -- UNION ALL preserva todos os instrumentos e evita cruzar boleto com PIX.
  CREATE TEMP TABLE tmp_instrumento_pagamento_deduplicado AS
  SELECT *
  FROM (
    SELECT * FROM tmp_instrumento_boleto
    UNION ALL
    SELECT * FROM tmp_instrumento_pix
  )
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY tipo_instrumento, id_instrumento
    ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 4 — CARGA
  -- Substitui integralmente o conteúdo da tabela de forma atômica.
  BEGIN TRANSACTION;

  DELETE FROM `lemon-ae-case.trusted.instrumento_pagamento`
  WHERE TRUE;

  INSERT INTO `lemon-ae-case.trusted.instrumento_pagamento`
  SELECT *
  FROM tmp_instrumento_pagamento_deduplicado;

  COMMIT TRANSACTION;
END;
