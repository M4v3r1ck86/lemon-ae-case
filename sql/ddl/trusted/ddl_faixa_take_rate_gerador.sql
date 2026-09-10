-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.FAIXA_TAKE_RATE_GERADOR
-- Origem: raw.energy_generator_take_rates
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.faixa_take_rate_gerador`
(
  id_take_rate STRING NOT NULL
    OPTIONS(description = 'Identificador da configuração de take rate à qual a faixa pertence.'),
  perc_desempenho_min NUMERIC NOT NULL
    OPTIONS(description = 'Limite inferior inclusivo de desempenho para aplicação da faixa, em escala decimal.'),
  perc_desempenho_max NUMERIC NOT NULL
    OPTIONS(description = 'Limite superior exclusivo de desempenho para aplicação da faixa, em escala decimal.'),
  perc_take_rate NUMERIC NOT NULL
    OPTIONS(description = 'Percentual de participação da Lemon aplicável à faixa, em escala decimal.'),
  id_gerador STRING
    OPTIONS(description = 'Identificador técnico do gerador informado pela fonte.'),
  gerador STRING NOT NULL
    OPTIONS(description = 'Nome ou identificador funcional do gerador.'),
  cod_distribuidora STRING NOT NULL
    OPTIONS(description = 'Código ou nome padronizado da distribuidora de energia.'),
  status_take_rate STRING
    OPTIONS(description = 'Status informado pela origem para a configuração de take rate.'),
  dt_inicio_vigencia DATE NOT NULL
    OPTIONS(description = 'Data inicial inclusiva de vigência da configuração.'),
  dt_fim_vigencia DATE NOT NULL
    OPTIONS(description = 'Data final inclusiva de vigência da configuração.'),
  id_planilha_origem STRING
    OPTIONS(description = 'Identificador da planilha que forneceu a configuração.'),
  ts_atualizacao_origem TIMESTAMP
    OPTIONS(description = 'Data e hora de atualização informada pelo sistema de origem.'),
  ingerido_em TIMESTAMP
    OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.')
)
CLUSTER BY gerador, cod_distribuidora, id_take_rate
OPTIONS (
  description = 'Faixas temporais de take rate por gerador e distribuidora, normalizadas a partir de raw.energy_generator_take_rates.',
  labels = [('camada', 'trusted'), ('dominio', 'energia'), ('origem', 'generator_take_rates')]
);
