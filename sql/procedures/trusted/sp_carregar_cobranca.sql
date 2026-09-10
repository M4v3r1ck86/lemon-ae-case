-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_COBRANCA
-- Grain: uma linha por id_cobranca.
-- Estratégia: normalização, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE `lemon-ae-case.trusted.sp_carregar_cobranca`()
BEGIN
  -- ETAPA 1 — NORMALIZAÇÃO
  CREATE TEMP TABLE tmp_cobranca_normalizado AS
  SELECT
    NULLIF(TRIM(charge_id), '') AS id_cobranca,
    NULLIF(TRIM(source), '') AS id_grafo_cobranca,
    NULLIF(TRIM(billing_id), '') AS id_faturamento,
    NULLIF(TRIM(billing_plan_id), '') AS id_plano_faturamento,
    NULLIF(TRIM(place_id), '') AS id_local,
    NULLIF(TRIM(disco_consumer_unit_id), '') AS id_instalacao,
    UPPER(NULLIF(TRIM(distribution_company), '')) AS cod_distribuidora,
    SAFE_CAST(NULLIF(TRIM(reference_month), '') AS DATE) AS dt_mes_referencia,
    SAFE_CAST(pipedrive_id AS INT64) AS id_pipedrive,
    NULLIF(TRIM(product), '') AS produto,
    NULLIF(TRIM(charge_provider_type), '') AS tipo_provedor_cobranca,
    NULLIF(TRIM(status), '') AS status_cobranca,
    NULLIF(TRIM(subscriber_id), '') AS id_assinante,
    NULLIF(TRIM(subscriber_type), '') AS tipo_assinante,
    NULLIF(TRIM(type), '') AS tipo_cobranca,
    NULLIF(TRIM(subscription_id), '') AS id_assinatura,
    SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP) AS ts_criado_em,
    SAFE_CAST(NULLIF(TRIM(payment_date), '') AS DATE) AS dt_pagamento,
    SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), 100) AS vlr_cobranca_brl,
    SAFE_DIVIDE(SAFE_CAST(amount_without_discounts AS NUMERIC), 100) AS vlr_sem_descontos_brl,
    SAFE_DIVIDE(SAFE_CAST(temporary_discount_amount AS NUMERIC), 100) AS vlr_desconto_temporario_brl,
    SAFE_CAST(NULLIF(TRIM(cancelled_at), '') AS TIMESTAMP) AS ts_cancelamento,
    NULLIF(TRIM(cancellation_reason), '') AS motivo_cancelamento,
    NULLIF(TRIM(cancellation_type), '') AS tipo_cancelamento,
    NULLIF(TRIM(cancelled_by), '') AS cancelado_por,
    NULLIF(TRIM(cancellation_description), '') AS descricao_cancelamento,
    SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP) AS ts_ingestao_origem,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.finance_charges`;

  -- ETAPA 2 — DEDUPLICAÇÃO
  CREATE TEMP TABLE tmp_cobranca_deduplicado AS
  SELECT * FROM tmp_cobranca_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_cobranca ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 3 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.cobranca` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.cobranca`
  SELECT * FROM tmp_cobranca_deduplicado;
  COMMIT TRANSACTION;
END;
