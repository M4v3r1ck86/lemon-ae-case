-- BigQuery / GoogleSQL
-- =============================================================================
-- VIEW — REFINED.VW_RELATORIO_GERADOR_APRESENTACAO
--
-- Responsabilidade:
--   Disponibilizar uma visão enxuta e amigável do relatório do gerador.
--
-- Grain:
--   Uma linha por gerador + usina + distribuidora + mês de referência.
--
-- Observação:
--   Os percentuais permanecem numéricos e são apresentados na escala de 0 a
--   100, permitindo ordenação, filtros, agregações e cálculos corretos.
-- =============================================================================

CREATE OR REPLACE VIEW
  `lemon-ae-case.refined.vw_relatorio_gerador_apresentacao`
(
  id_gerador
    OPTIONS(description = 'Identificador numérico derivado do nome do gerador.'),
  gerador
    OPTIONS(description = 'Nome ou identificador funcional do gerador.'),
  id_usina
    OPTIONS(description = 'Identificador numérico derivado do nome da usina.'),
  usina
    OPTIONS(description = 'Nome ou identificador funcional da usina.'),
  dt_mes_referencia
    OPTIONS(description = 'Mês de competência do relatório do gerador.'),
  dt_fechamento_competencia
    OPTIONS(description = 'Data de maturação D+60 usada para fechar a competência.'),
  status_fechamento
    OPTIONS(description = 'Estado do fechamento publicado.'),
  perc_desempenho_lemon
    OPTIONS(description = 'Desempenho da Lemon em escala percentual de 0 a 100, arredondado para quatro casas decimais.'),
  perc_take_rate_aplicado
    OPTIONS(description = 'Take rate aplicado em escala percentual de 0 a 100, arredondado para duas casas decimais.'),
  vlr_cobranca_gerador_brl
    OPTIONS(description = 'Valor de cobrança atribuído ao gerador, em reais.'),
  vlr_receita_bruta_gerador_brl
    OPTIONS(description = 'Receita bruta principal atribuída ao gerador, em reais.'),
  vlr_liquidado_gerador_apos_d60_brl
    OPTIONS(description = 'Valor recebido após D+60, evidenciado como recuperação posterior.'),
  vlr_saldo_nao_liquidado_d60_brl
    OPTIONS(description = 'Saldo do gerador que não foi liquidado até D+60.'),
  vlr_receita_multas_brl
    OPTIONS(description = 'Receita recebida de multas e juros, em reais.'),
  vlr_tusd_descontada_gerador_brl
    OPTIONS(description = 'Valor de TUSD descontado do repasse do gerador, em reais.'),
  vlr_repasse_total_gerador_brl
    OPTIONS(description = 'Soma do repasse principal e das multas pertencentes ao gerador, em reais.'),
  vlr_repasse_total_lemon_brl
    OPTIONS(description = 'Soma do repasse principal e das multas pertencentes à Lemon, em reais.')
)
OPTIONS (
  description = 'Visão de apresentação do relatório mensal do gerador, com percentuais numéricos e repasses consolidados.'
)
AS
SELECT
  id_gerador,
  gerador,
  id_usina,
  usina,
  dt_mes_referencia,
  dt_fechamento_competencia,
  status_fechamento,
  ROUND(perc_desempenho_lemon * 100, 4) AS perc_desempenho_lemon,
  ROUND(perc_take_rate_aplicado * 100, 2) AS perc_take_rate_aplicado,
  vlr_cobranca_gerador_brl,
  vlr_receita_bruta_gerador_brl,
  vlr_liquidado_gerador_apos_d60_brl,
  vlr_saldo_nao_liquidado_d60_brl,
  vlr_receita_multas_brl,
  vlr_tusd_descontada_gerador_brl,
  vlr_repasse_gerador_brl
    + vlr_repasse_multas_gerador_brl AS vlr_repasse_total_gerador_brl,
  vlr_repasse_lemon_brl
    + vlr_repasse_multas_lemon_brl AS vlr_repasse_total_lemon_brl
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`;
