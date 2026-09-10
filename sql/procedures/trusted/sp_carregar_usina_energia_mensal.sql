-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_USINA_ENERGIA_MENSAL
-- Grain: uma linha por usina + dt_mes_referencia.
-- Estratégia: normalização, deduplicação e full refresh transacional.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_usina_energia_mensal`()
BEGIN
  -- ETAPA 1 — NORMALIZAÇÃO
  CREATE TEMP TABLE tmp_usina_energia_normalizado AS
  SELECT
    NULLIF(TRIM(usina), '') AS usina,
    SAFE_CAST(NULLIF(TRIM(mes_referencia), '') AS DATE) AS dt_mes_referencia,
    NULLIF(TRIM(gerador), '') AS gerador,
    UPPER(NULLIF(TRIM(disco), '')) AS cod_distribuidora,
    SAFE_CAST(creditos_injetados_k_wh AS NUMERIC) AS qtd_creditos_injetados_kwh,
    SAFE_CAST(geracao_prevista_no_contrato_k_wh AS NUMERIC) AS qtd_geracao_prevista_contrato_kwh,
    SAFE_CAST(geracao_realizada_gerador_k_wh AS NUMERIC) AS qtd_geracao_realizada_gerador_kwh,
    SAFE_CAST(tusd_brl AS NUMERIC) AS vlr_tusd_brl,
    SAFE_CAST(NULLIF(TRIM(mes_de_desconto_tusd_gerador), '') AS DATE) AS dt_mes_desconto_tusd_gerador,
    SAFE_CAST(aluguel_imoveis_brl AS NUMERIC) AS vlr_aluguel_imoveis_brl,
    SAFE_CAST(aluguel_equipamento_brl AS NUMERIC) AS vlr_aluguel_equipamento_brl,
    SAFE_CAST(NULLIF(TRIM(operations_and_maintenance_cost_brl), '') AS NUMERIC) AS vlr_operacao_manutencao_brl,
    SAFE_CAST(tusd_descontada_gerador AS NUMERIC) AS vlr_tusd_descontada_gerador_brl,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.energy_farms`;

  -- ETAPA 2 — DEDUPLICAÇÃO
  CREATE TEMP TABLE tmp_usina_energia_deduplicado AS
  SELECT *
  FROM tmp_usina_energia_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY usina, dt_mes_referencia
    ORDER BY ingerido_em DESC
  ) = 1;

  -- ETAPA 3 — CARGA
  BEGIN TRANSACTION;
  DELETE FROM `lemon-ae-case.trusted.usina_energia_mensal` WHERE TRUE;
  INSERT INTO `lemon-ae-case.trusted.usina_energia_mensal`
  SELECT * FROM tmp_usina_energia_deduplicado;
  COMMIT TRANSACTION;
END;
