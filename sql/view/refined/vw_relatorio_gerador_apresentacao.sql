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
--   Os percentuais são convertidos em texto somente para apresentação.
--   A tabela refined.relatorio_gerador_mensal preserva os valores numéricos.
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
  perc_desempenho_lemon
    OPTIONS(description = 'Desempenho da Lemon formatado como percentual com quatro casas decimais.'),
  perc_take_rate_aplicado
    OPTIONS(description = 'Take rate aplicado formatado como percentual com duas casas decimais.'),
  vlr_cobranca_gerador_brl
    OPTIONS(description = 'Valor de cobrança atribuído ao gerador, em reais.'),
  vlr_receita_bruta_gerador_brl
    OPTIONS(description = 'Receita bruta principal atribuída ao gerador, em reais.'),
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
  description = 'Visão de apresentação do relatório mensal do gerador, com percentuais formatados e repasses consolidados.'
)
AS
SELECT
  id_gerador,
  gerador,
  id_usina,
  usina,
  dt_mes_referencia,
  REPLACE(
    FORMAT('%.4f%%', perc_desempenho_lemon * 100),
    '.',
    ','
  ) AS perc_desempenho_lemon,
  REPLACE(
    FORMAT('%.2f%%', perc_take_rate_aplicado * 100),
    '.',
    ','
  ) AS perc_take_rate_aplicado,
  vlr_cobranca_gerador_brl,
  vlr_receita_bruta_gerador_brl,
  vlr_receita_multas_brl,
  vlr_tusd_descontada_gerador_brl,
  vlr_repasse_gerador_brl
    + vlr_repasse_multas_gerador_brl AS vlr_repasse_total_gerador_brl,
  vlr_repasse_lemon_brl
    + vlr_repasse_multas_lemon_brl AS vlr_repasse_total_lemon_brl
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`;
