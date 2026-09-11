-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.LIQUIDACAO_USINA_MENSAL
-- Grain: gerador + usina + distribuidora + competência de origem
--        + mês de liquidação + classificação D+60.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.liquidacao_usina_mensal`
(
  gerador STRING NOT NULL,
  usina STRING NOT NULL,
  cod_distribuidora STRING NOT NULL,
  dt_mes_competencia_origem DATE NOT NULL,
  dt_mes_liquidacao DATE NOT NULL,
  classificacao_liquidacao STRING NOT NULL
    OPTIONS(description = 'dentro_d60, recuperacao_apos_d60 ou vencimento_ausente.'),
  qtd_faturamentos INT64,
  qtd_instalacoes INT64,
  qtd_creditos_faturados_pagos_kwh NUMERIC,
  vlr_faturamento_brl NUMERIC,
  vlr_principal_pago_brl NUMERIC,
  vlr_liquidado_gerador_brl NUMERIC,
  vlr_juros_pago_brl NUMERIC,
  vlr_multa_paga_brl NUMERIC,
  ingerido_em TIMESTAMP
)
PARTITION BY dt_mes_liquidacao
CLUSTER BY gerador, usina, cod_distribuidora, dt_mes_competencia_origem
OPTIONS (
  description = 'Liquidações por mês de entrada do caixa, preservando a competência original e a classificação D+60.',
  labels = [
    ('camada', 'trusted'),
    ('dominio', 'financeiro_energia'),
    ('entidade', 'liquidacao_usina_mensal')
  ],
  require_partition_filter = FALSE
);
