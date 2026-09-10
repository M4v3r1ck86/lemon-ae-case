-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.USINA_ENERGIA_MENSAL
-- Origem: raw.energy_farms
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.usina_energia_mensal`
(
  usina STRING NOT NULL
    OPTIONS(description = 'Nome ou identificador funcional da usina de energia.'),
  dt_mes_referencia DATE NOT NULL
    OPTIONS(description = 'Mês de competência das medições operacionais da usina.'),
  gerador STRING NOT NULL
    OPTIONS(description = 'Nome ou identificador funcional do gerador responsável pela usina.'),
  cod_distribuidora STRING NOT NULL
    OPTIONS(description = 'Código ou nome padronizado da distribuidora de energia.'),
  qtd_creditos_injetados_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia injetados na rede da distribuidora, em kWh.'),
  qtd_geracao_prevista_contrato_kwh NUMERIC
    OPTIONS(description = 'Quantidade de geração prevista contratualmente para a usina, em kWh.'),
  qtd_geracao_realizada_gerador_kwh NUMERIC
    OPTIONS(description = 'Quantidade de energia registrada como gerada pela usina, em kWh.'),
  vlr_tusd_brl NUMERIC
    OPTIONS(description = 'Valor monetário registrado na origem como Tarifa de Uso do Sistema de Distribuição, em reais.'),
  dt_mes_desconto_tusd_gerador DATE
    OPTIONS(description = 'Mês de competência em que a TUSD deve ser deduzida do repasse do gerador.'),
  vlr_aluguel_imoveis_brl NUMERIC
    OPTIONS(description = 'Valor de aluguel de imóveis associado à usina, em reais.'),
  vlr_aluguel_equipamento_brl NUMERIC
    OPTIONS(description = 'Valor de aluguel de equipamentos associado à usina, em reais.'),
  vlr_operacao_manutencao_brl NUMERIC
    OPTIONS(description = 'Valor de custos de operação e manutenção associado à usina, em reais.'),
  vlr_tusd_descontada_gerador_brl NUMERIC
    OPTIONS(description = 'Valor de TUSD deduzido do repasse do gerador, em reais.'),
  ingerido_em TIMESTAMP
    OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.')
)
PARTITION BY dt_mes_referencia
CLUSTER BY gerador, usina, cod_distribuidora
OPTIONS (
  description = 'Entidade mensal Trusted de operação e custos das usinas, normalizada a partir de raw.energy_farms.',
  labels = [('camada', 'trusted'), ('dominio', 'energia'), ('origem', 'energy_farms')],
  require_partition_filter = FALSE
);
