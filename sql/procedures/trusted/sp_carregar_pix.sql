-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_PIX
-- Grain: uma linha por id_pix.
-- Estratégia: normalização, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE `lemon-ae-case.trusted.sp_carregar_pix`()
BEGIN
  -- ETAPA 1 — NORMALIZAÇÃO
  CREATE TEMP TABLE tmp_pix_normalizado AS
  SELECT
    NULLIF(TRIM(pix_id), '') AS id_pix,
    NULLIF(TRIM(source), '') AS id_grafo_pix,
    NULLIF(TRIM(billing_id), '') AS id_faturamento,
    NULLIF(TRIM(tx_id), '') AS id_transacao,
    NULLIF(TRIM(place_id), '') AS id_local,
    NULLIF(TRIM(status), '') AS status_pix,
    SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP) AS ts_criado_em,
    SAFE_CAST(NULLIF(TRIM(due_date), '') AS DATE) AS dt_vencimento,
    SAFE_CAST(NULLIF(TRIM(payment_date), '') AS DATE) AS dt_pagamento,
    SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100) AS vlr_pix_brl,
    NULLIF(TRIM(receiver_id), '') AS id_recebedor,
    NULLIF(TRIM(receiver_type), '') AS tipo_recebedor,
    SAFE_DIVIDE(SAFE_CAST(pix_expected_total AS NUMERIC), 100) AS vlr_total_esperado_brl,
    SAFE_DIVIDE(SAFE_CAST(pix_expected_interest AS NUMERIC), 100) AS vlr_juros_esperado_brl,
    SAFE_DIVIDE(SAFE_CAST(pix_expected_fine AS NUMERIC), 100) AS vlr_multa_esperada_brl,
    SAFE_DIVIDE(SAFE_CAST(pix_paid_total AS NUMERIC), 100) AS vlr_total_pago_brl,
    SAFE_DIVIDE(SAFE_CAST(pix_paid_interest AS NUMERIC), 100) AS vlr_juros_pago_brl,
    SAFE_DIVIDE(SAFE_CAST(pix_paid_fine AS NUMERIC), 100) AS vlr_multa_paga_brl,
    NULLIF(TRIM(pix_code), '') AS cod_pix,
    SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP) AS ts_ingestao_origem,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.finance_pixs`;

  -- ETAPA 2 — DEDUPLICAÇÃO
  CREATE TEMP TABLE tmp_pix_deduplicado AS
  SELECT * FROM tmp_pix_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_pix ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 3 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.pix` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.pix`
  SELECT * FROM tmp_pix_deduplicado;
  COMMIT TRANSACTION;
END;
