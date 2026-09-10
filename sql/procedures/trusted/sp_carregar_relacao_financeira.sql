-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_RELACAO_FINANCEIRA
-- Grain: uma aresta por id_grafo_origem + id_grafo_destino.
-- Estratégia: normalização, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_relacao_financeira`()
BEGIN
  -- ETAPA 1 — NORMALIZAÇÃO
  CREATE TEMP TABLE tmp_relacao_financeira_normalizado AS
  SELECT
    NULLIF(TRIM(source), '') AS id_grafo_origem,
    LOWER(SPLIT(NULLIF(TRIM(source), ''), '#')[SAFE_OFFSET(0)]) AS tipo_entidade_origem,
    SPLIT(NULLIF(TRIM(source), ''), '#')[SAFE_OFFSET(1)] AS id_origem,
    NULLIF(TRIM(target), '') AS id_grafo_destino,
    LOWER(SPLIT(NULLIF(TRIM(target), ''), '#')[SAFE_OFFSET(0)]) AS tipo_entidade_destino,
    SPLIT(NULLIF(TRIM(target), ''), '#')[SAFE_OFFSET(1)] AS id_destino,
    SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP) AS ts_criado_em,
    SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP) AS ts_ingestao_origem,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.finance_relations`;

  -- ETAPA 2 — DEDUPLICAÇÃO
  CREATE TEMP TABLE tmp_relacao_financeira_deduplicado AS
  SELECT * FROM tmp_relacao_financeira_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_grafo_origem, id_grafo_destino
    ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 3 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.relacao_financeira` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.relacao_financeira`
  SELECT * FROM tmp_relacao_financeira_deduplicado;
  COMMIT TRANSACTION;
END;
