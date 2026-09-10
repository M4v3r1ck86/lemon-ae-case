-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_BOLETO
-- Grain: uma linha por id_boleto.
-- Estratégia: normalização, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE `lemon-ae-case.trusted.sp_carregar_boleto`()
BEGIN
  -- ETAPA 1 — NORMALIZAÇÃO
  CREATE TEMP TABLE tmp_boleto_normalizado AS
  SELECT
    SAFE_CAST(bank_slip_id AS INT64) AS id_boleto,
    NULLIF(TRIM(source), '') AS id_grafo_boleto,
    NULLIF(TRIM(place_id), '') AS id_local,
    NULLIF(TRIM(status), '') AS status_boleto,
    SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP) AS ts_criado_em,
    SAFE_CAST(NULLIF(TRIM(due_date), '') AS DATE) AS dt_vencimento,
    SAFE_CAST(NULLIF(TRIM(payment_date), '') AS DATE) AS dt_pagamento,
    SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100) AS vlr_boleto_brl,
    SAFE_CAST(our_number AS INT64) AS num_nosso_numero,
    NULLIF(TRIM(receiver_name), '') AS nome_recebedor,
    NULLIF(TRIM(receiver_id), '') AS id_recebedor,
    NULLIF(TRIM(receiver_type), '') AS tipo_recebedor,
    SAFE_DIVIDE(SAFE_CAST(bank_slip_expected_total AS NUMERIC), 100) AS vlr_total_esperado_brl,
    SAFE_DIVIDE(SAFE_CAST(bank_slip_expected_interest AS NUMERIC), 100) AS vlr_juros_esperado_brl,
    SAFE_DIVIDE(SAFE_CAST(bank_slip_expected_fine AS NUMERIC), 100) AS vlr_multa_esperada_brl,
    SAFE_DIVIDE(SAFE_CAST(bank_slip_paid_total AS NUMERIC), 100) AS vlr_total_pago_brl,
    SAFE_DIVIDE(SAFE_CAST(bank_slip_paid_interest AS NUMERIC), 100) AS vlr_juros_pago_brl,
    SAFE_DIVIDE(SAFE_CAST(bank_slip_paid_fine AS NUMERIC), 100) AS vlr_multa_paga_brl,
    SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP) AS ts_ingestao_origem,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.finance_boletos`;

  -- ETAPA 2 — DEDUPLICAÇÃO
  CREATE TEMP TABLE tmp_boleto_deduplicado AS
  SELECT * FROM tmp_boleto_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_boleto ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 3 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.boleto` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.boleto`
  SELECT * FROM tmp_boleto_deduplicado;
  COMMIT TRANSACTION;
END;
