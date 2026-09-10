-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.BOLETO
-- Origem: raw.finance_boletos
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.boleto`
(
  id_boleto INT64 NOT NULL OPTIONS(description = 'Identificador técnico do instrumento de pagamento boleto.'),
  id_grafo_boleto STRING NOT NULL OPTIONS(description = 'Identificador completo do nó de boleto usado no grafo financeiro.'),
  id_local STRING NOT NULL OPTIONS(description = 'Identificador do local ou estabelecimento associado ao boleto.'),
  status_boleto STRING OPTIONS(description = 'Status operacional do instrumento de pagamento boleto.'),
  ts_criado_em TIMESTAMP OPTIONS(description = 'Data e hora de criação ou emissão do boleto.'),
  dt_vencimento DATE OPTIONS(description = 'Data de vencimento do boleto.'),
  dt_pagamento DATE OPTIONS(description = 'Data de liquidação do boleto; nula quando não há pagamento.'),
  vlr_boleto_brl NUMERIC OPTIONS(description = 'Valor nominal do boleto convertido de centavos para reais.'),
  num_nosso_numero INT64 OPTIONS(description = 'Identificador bancário conhecido como Nosso Número.'),
  nome_recebedor STRING OPTIONS(description = 'Nome do recebedor associado ao boleto.'),
  id_recebedor STRING OPTIONS(description = 'Identificador da entidade ou conta recebedora.'),
  tipo_recebedor STRING OPTIONS(description = 'Tipo da entidade recebedora do boleto.'),
  vlr_total_esperado_brl NUMERIC OPTIONS(description = 'Valor total esperado no pagamento, incluindo encargos, convertido para reais.'),
  vlr_juros_esperado_brl NUMERIC OPTIONS(description = 'Valor de juros esperado, convertido de centavos para reais.'),
  vlr_multa_esperada_brl NUMERIC OPTIONS(description = 'Valor de multa esperada, convertido de centavos para reais.'),
  vlr_total_pago_brl NUMERIC OPTIONS(description = 'Valor total efetivamente pago, convertido de centavos para reais.'),
  vlr_juros_pago_brl NUMERIC OPTIONS(description = 'Valor de juros efetivamente pago, convertido de centavos para reais.'),
  vlr_multa_paga_brl NUMERIC OPTIONS(description = 'Valor de multa efetivamente paga, convertido de centavos para reais.'),
  ts_ingestao_origem TIMESTAMP OPTIONS(description = 'Data e hora de ingestão informada pelo sistema financeiro de origem.'),
  ingerido_em TIMESTAMP OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.')
)
PARTITION BY dt_vencimento
CLUSTER BY status_boleto, id_local, tipo_recebedor
OPTIONS (
  description = 'Entidade Trusted de instrumentos de pagamento por boleto, normalizada a partir de raw.finance_boletos.',
  labels = [('camada', 'trusted'), ('dominio', 'financeiro'), ('origem', 'finance_boletos')],
  require_partition_filter = FALSE
);
