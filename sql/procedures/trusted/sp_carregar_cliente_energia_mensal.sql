-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_CLIENTE_ENERGIA_MENSAL
--
-- Objetivo:
--   Normalizar raw.energy_clients e carregar trusted.cliente_energia_mensal.
--
-- Grain:
--   Uma linha por id_instalacao + dt_mes_referencia.
--
-- Estratégia:
--   Full refresh dentro de uma transação. Esta opção mantém o código simples e
--   é adequada ao volume atual. A tabela só é alterada se o DELETE e o INSERT
--   forem concluídos com sucesso.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_cliente_energia_mensal`()
BEGIN
  -- ---------------------------------------------------------------------------
  -- ETAPA 1 — NORMALIZAÇÃO
  -- Padroniza nomes, textos e tipos sem aplicar regras do generator_report.
  -- ---------------------------------------------------------------------------
  CREATE TEMP TABLE tmp_cliente_energia_normalizado AS
  SELECT
    NULLIF(TRIM(numero_instalacao), '') AS id_instalacao,
    SAFE_CAST(NULLIF(TRIM(mes_referencia), '') AS DATE) AS dt_mes_referencia,
    NULLIF(TRIM(usina), '') AS usina,
    NULLIF(TRIM(gerador), '') AS gerador,
    UPPER(NULLIF(TRIM(disco), '')) AS cod_distribuidora,

    SAFE_CAST(saldo_bop_k_wh AS NUMERIC) AS saldo_bop_kwh,
    SAFE_CAST(saldo_eop_k_wh AS NUMERIC) AS saldo_eop_kwh,
    SAFE_CAST(churn_k_wh AS NUMERIC) AS qtd_churn_kwh,
    SAFE_CAST(creditos_recebidos_no_mes_k_wh AS NUMERIC)
      AS qtd_creditos_recebidos_mes_kwh,
    SAFE_CAST(creditos_recebidos_de_meses_anteriores_k_wh AS NUMERIC)
      AS qtd_creditos_recebidos_meses_anteriores_kwh,
    SAFE_CAST(creditos_faturados_k_wh AS NUMERIC)
      AS qtd_creditos_faturados_kwh,
    SAFE_CAST(creditos_compensados_do_mes_k_wh AS NUMERIC)
      AS qtd_creditos_compensados_mes_kwh,
    SAFE_CAST(creditos_compensados_de_meses_anteriores_k_wh AS NUMERIC)
      AS qtd_creditos_compensados_meses_anteriores_kwh,

    SAFE_CAST(desconto_cliente_percentage AS NUMERIC) AS perc_desconto_cliente,
    SAFE_CAST(desconto_gerador_percentage AS NUMERIC) AS perc_desconto_gerador,

    SAFE_CAST(gmv_real_oficial_brl AS NUMERIC) AS vlr_gmv_real_oficial_brl,
    SAFE_CAST(gmv_gerador_brl AS NUMERIC) AS vlr_gmv_gerador_brl,
    SAFE_CAST(take_rate_lemon_brl AS NUMERIC) AS vlr_take_rate_lemon_brl,
    SAFE_CAST(tarifa_de_saida_brl_per_k_wh AS NUMERIC)
      AS vlr_tarifa_saida_brl_por_kwh,
    SAFE_CAST(pis_per_cofins_nao_compensado_lemon_brl_k_wh AS NUMERIC)
      AS vlr_pis_cofins_nao_compensado_lemon_brl_por_kwh,
    SAFE_CAST(icms_nao_compensado_lemon_brl_per_k_wh AS NUMERIC)
      AS vlr_icms_nao_compensado_lemon_brl_por_kwh,
    SAFE_CAST(ajuste_custo_disp_gerador_brl AS NUMERIC)
      AS vlr_ajuste_custo_disponibilidade_gerador_brl,
    SAFE_CAST(desconto_gerador_brl_per_k_wh AS NUMERIC)
      AS vlr_desconto_gerador_brl_por_kwh,

    NULLIF(TRIM(etapa), '') AS etapa_processamento,
    NULLIF(TRIM(status), '') AS status_processamento,
    NULLIF(NULLIF(TRIM(excecoes), ''), '-') AS txt_excecoes,
    _ingested_at AS ingerido_em
  FROM `lemon-ae-case.raw.energy_clients`;

  -- ---------------------------------------------------------------------------
  -- ETAPA 2 — DEDUPLICAÇÃO
  -- Para cada instalação e competência, mantém a ingestão mais recente.
  -- ---------------------------------------------------------------------------
  CREATE TEMP TABLE tmp_cliente_energia_deduplicado AS
  SELECT *
  FROM tmp_cliente_energia_normalizado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_instalacao, dt_mes_referencia
    ORDER BY ingerido_em DESC
  ) = 1;

  -- ---------------------------------------------------------------------------
  -- ETAPA 3 — CARGA
  -- Substitui integralmente o conteúdo da Trusted de forma atômica.
  -- ---------------------------------------------------------------------------
  BEGIN TRANSACTION;

  DELETE FROM `lemon-ae-case.trusted.cliente_energia_mensal`
  WHERE TRUE;

  INSERT INTO `lemon-ae-case.trusted.cliente_energia_mensal`
  SELECT *
  FROM tmp_cliente_energia_deduplicado;

  COMMIT TRANSACTION;
END;
