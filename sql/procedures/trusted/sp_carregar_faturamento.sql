-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_FATURAMENTO
-- Grain: uma linha por id_faturamento.
-- Estratégia: normalização, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE `lemon-ae-case.trusted.sp_carregar_faturamento`()
BEGIN
  -- ETAPA 1 — NORMALIZAÇÃO
  CREATE TEMP TABLE tmp_faturamento_normalizado AS
  SELECT
    NULLIF(TRIM(billing_id), '') AS id_faturamento,
    NULLIF(TRIM(source), '') AS id_grafo_faturamento,
    NULLIF(TRIM(place_id), '') AS id_local,
    NULLIF(TRIM(billing_energy_farm_id), '') AS id_usina_backend,
    NULLIF(TRIM(status), '') AS status_faturamento,
    SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100) AS vlr_faturamento_brl,
    SAFE_DIVIDE(SAFE_CAST(amount_without_discounts AS NUMERIC), 100) AS vlr_sem_descontos_brl,
    SAFE_DIVIDE(SAFE_CAST(temporary_discount_amount AS NUMERIC), 100) AS vlr_desconto_temporario_brl,
    SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP) AS ts_criado_em,
    SAFE_CAST(NULLIF(TRIM(due_date), '') AS DATE) AS dt_vencimento,
    SAFE_CAST(NULLIF(TRIM(original_due_date), '') AS DATE) AS dt_vencimento_original,
    SAFE_CAST(NULLIF(TRIM(billing_payment_date), '') AS TIMESTAMP) AS ts_pagamento,
    SAFE_CAST(billing_rescheduled_times AS INT64) AS qtd_reagendamentos,
    SAFE_CAST(NULLIF(TRIM(cancelled_at), '') AS TIMESTAMP) AS ts_cancelamento,
    NULLIF(TRIM(cancellation_reason), '') AS motivo_cancelamento,
    NULLIF(TRIM(cancellation_type), '') AS tipo_cancelamento,
    NULLIF(TRIM(cancelled_by), '') AS cancelado_por,
    NULLIF(TRIM(cancellation_description), '') AS descricao_cancelamento,
    SAFE_DIVIDE(SAFE_CAST(billing_expected_total AS NUMERIC), 100) AS vlr_total_esperado_brl,
    SAFE_DIVIDE(SAFE_CAST(billing_expected_interest AS NUMERIC), 100) AS vlr_juros_esperado_brl,
    SAFE_DIVIDE(SAFE_CAST(billing_expected_fine AS NUMERIC), 100) AS vlr_multa_esperada_brl,
    SAFE_DIVIDE(SAFE_CAST(billing_paid_total AS NUMERIC), 100) AS vlr_total_pago_brl,
    SAFE_DIVIDE(SAFE_CAST(billing_paid_interest AS NUMERIC), 100) AS vlr_juros_pago_brl,
    SAFE_DIVIDE(SAFE_CAST(billing_paid_fine AS NUMERIC), 100) AS vlr_multa_paga_brl,
    NULLIF(TRIM(billing_receiver_id), '') AS id_recebedor,
    NULLIF(TRIM(billing_receiver_type), '') AS tipo_recebedor,
    SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP) AS ts_ingestao_origem,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.finance_billings`;

  -- ETAPA 2 — DEDUPLICAÇÃO
  CREATE TEMP TABLE tmp_faturamento_deduplicado AS
  SELECT * FROM tmp_faturamento_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_faturamento ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 3 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.faturamento` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.faturamento`
  SELECT * FROM tmp_faturamento_deduplicado;
  COMMIT TRANSACTION;
END;
