-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_FAIXA_TAKE_RATE_GERADOR
-- Grain: uma faixa por id_take_rate + perc_desempenho_min.
-- Estratégia: normalização, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_faixa_take_rate_gerador`()
BEGIN
  -- ETAPA 1 — NORMALIZAÇÃO
  CREATE TEMP TABLE tmp_faixa_take_rate_normalizado AS
  SELECT
    NULLIF(TRIM(id_tr), '') AS id_take_rate,
    SAFE_CAST(desempenho_min AS NUMERIC) AS perc_desempenho_min,
    SAFE_CAST(desempenho_max AS NUMERIC) AS perc_desempenho_max,
    SAFE_CAST(tr_percentual AS NUMERIC) AS perc_take_rate,
    NULLIF(TRIM(id_gerador), '') AS id_gerador,
    NULLIF(TRIM(gerador), '') AS gerador,
    UPPER(NULLIF(TRIM(disco), '')) AS cod_distribuidora,
    NULLIF(TRIM(status), '') AS status_take_rate,
    SAFE_CAST(NULLIF(TRIM(data_inicio), '') AS DATE) AS dt_inicio_vigencia,
    SAFE_CAST(NULLIF(TRIM(data_final), '') AS DATE) AS dt_fim_vigencia,
    NULLIF(TRIM(spreadsheet_id), '') AS id_planilha_origem,
    SAFE_CAST(NULLIF(TRIM(update_time), '') AS TIMESTAMP) AS ts_atualizacao_origem,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.energy_generator_take_rates`;

  -- ETAPA 2 — DEDUPLICAÇÃO
  CREATE TEMP TABLE tmp_faixa_take_rate_deduplicado AS
  SELECT *
  FROM tmp_faixa_take_rate_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_take_rate, perc_desempenho_min
    ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 3 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.faixa_take_rate_gerador` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.faixa_take_rate_gerador`
  SELECT * FROM tmp_faixa_take_rate_deduplicado;
  COMMIT TRANSACTION;
END;
