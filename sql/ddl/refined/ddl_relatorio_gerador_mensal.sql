-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — REFINED.RELATORIO_GERADOR_MENSAL
--
-- Grain:
--   Uma linha por gerador + usina + distribuidora + mês de referência.
--
-- Responsabilidade:
--   Publicar o desempenho mensal da usina, a faixa de take rate aplicada e os
--   valores finais de receita e repasse do relatório do gerador.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.refined.relatorio_gerador_mensal`
(
  gerador STRING NOT NULL
    OPTIONS(description = 'Nome ou identificador funcional do gerador.'),
  id_gerador INT64
    OPTIONS(description = 'Identificador numérico derivado do sufixo do nome do gerador.'),
  usina STRING NOT NULL
    OPTIONS(description = 'Nome ou identificador funcional da usina.'),
  id_usina INT64
    OPTIONS(description = 'Identificador numérico derivado do sufixo do nome da usina.'),
  cod_distribuidora STRING NOT NULL
    OPTIONS(description = 'Código ou nome padronizado da distribuidora de energia.'),
  dt_mes_referencia DATE NOT NULL
    OPTIONS(description = 'Mês de competência do relatório do gerador.'),
  qtd_instalacoes INT64
    OPTIONS(description = 'Quantidade de instalações de clientes associadas à usina na competência.'),
  qtd_creditos_injetados_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos injetados pela usina na competência, em kWh.'),
  qtd_creditos_faturados_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos faturados para os clientes da usina, em kWh.'),
  qtd_creditos_faturados_pagos_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos faturados vinculados a faturamentos pagos, em kWh.'),
  qtd_minima_injecao_kwh NUMERIC
    OPTIONS(description = 'Menor valor entre os créditos injetados e a geração prevista, em kWh.'),
  perc_desempenho_lemon NUMERIC
    OPTIONS(description = 'Razão entre créditos faturados pagos e a quantidade mínima de injeção.'),
  id_take_rate STRING NOT NULL
    OPTIONS(description = 'Identificador da configuração de take rate selecionada para a linha.'),
  perc_desempenho_min NUMERIC NOT NULL
    OPTIONS(description = 'Limite inferior inclusivo da faixa de desempenho selecionada.'),
  perc_desempenho_max NUMERIC NOT NULL
    OPTIONS(description = 'Limite superior exclusivo da faixa de desempenho selecionada.'),
  perc_take_rate_aplicado NUMERIC NOT NULL
    OPTIONS(description = 'Percentual de take rate da Lemon aplicado aos cálculos, em escala decimal.'),
  vlr_cobranca_gerador_brl NUMERIC
    OPTIONS(description = 'Valor de cobrança atribuído ao gerador na competência, em reais.'),
  vlr_liquidado_gerador_brl NUMERIC
    OPTIONS(description = 'Parcela do principal liquidado atribuída ao gerador, em reais.'),
  vlr_receita_bruta_gerador_brl NUMERIC
    OPTIONS(description = 'Receita bruta do gerador antes do take rate e da TUSD, em reais.'),
  vlr_receita_multas_brl NUMERIC
    OPTIONS(description = 'Receita total recebida de multas e juros, em reais.'),
  vlr_repasse_pre_tusd_gerador_brl NUMERIC
    OPTIONS(description = 'Repasse do principal ao gerador antes da dedução da TUSD, em reais.'),
  dt_mes_desconto_tusd_gerador DATE
    OPTIONS(description = 'Mês informado para aplicação do desconto de TUSD do gerador.'),
  vlr_tusd_descontada_gerador_brl NUMERIC
    OPTIONS(description = 'Valor de TUSD deduzido do repasse do gerador, em reais.'),
  vlr_repasse_gerador_brl NUMERIC
    OPTIONS(description = 'Repasse do principal ao gerador após a dedução da TUSD, em reais.'),
  vlr_repasse_multas_lemon_brl NUMERIC
    OPTIONS(description = 'Parcela de multas e juros pertencente à Lemon, em reais.'),
  vlr_repasse_multas_gerador_brl NUMERIC
    OPTIONS(description = 'Parcela de multas e juros pertencente ao gerador, em reais.'),
  vlr_repasse_lemon_brl NUMERIC
    OPTIONS(description = 'Parcela da receita bruta principal pertencente à Lemon, em reais.'),
  processado_em TIMESTAMP NOT NULL
    OPTIONS(description = 'Data e hora de processamento da linha na camada Refined.')
)
PARTITION BY dt_mes_referencia
CLUSTER BY gerador, usina, cod_distribuidora
OPTIONS (
  description = 'Produto de dados mensal do relatório do gerador com desempenho, take rate, receitas e repasses.',
  labels = [
    ('camada', 'refined'),
    ('dominio', 'energia_financeiro'),
    ('entidade', 'relatorio_gerador_mensal')
  ],
  require_partition_filter = FALSE
);