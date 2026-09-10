-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.INSTRUMENTO_PAGAMENTO
--
-- Responsabilidade:
--   Unificar boletos e PIX em uma entidade comum de instrumentos de pagamento,
--   preservando todas as emissões, reemissões e situações operacionais.
--
-- Grain:
--   Uma linha por tipo_instrumento + id_instrumento.
--
-- Origens:
--   trusted.boleto
--   trusted.pix
--   trusted.relacao_financeira, para identificar o faturamento do boleto.
--
-- Observação:
--   Esta tabela não escolhe um instrumento preferencial, não elimina registros
--   cancelados e não consolida valores por faturamento.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.instrumento_pagamento`
(
  tipo_instrumento STRING NOT NULL
    OPTIONS(description = 'Tipo do instrumento de pagamento. Valores esperados: boleto ou pix.'),

  id_instrumento STRING NOT NULL
    OPTIONS(description = 'Identificador técnico do instrumento de pagamento sem o prefixo do grafo.'),

  id_grafo_instrumento STRING NOT NULL
    OPTIONS(description = 'Identificador completo do instrumento utilizado no grafo financeiro.'),

  id_faturamento STRING NOT NULL
    OPTIONS(description = 'Identificador do faturamento ao qual o instrumento de pagamento está vinculado.'),

  id_local STRING NOT NULL
    OPTIONS(description = 'Identificador do local ou estabelecimento associado ao instrumento de pagamento.'),

  status_instrumento STRING
    OPTIONS(description = 'Status operacional do instrumento, como paid, cancelled ou waitingPayment.'),

  ts_criado_em TIMESTAMP
    OPTIONS(description = 'Data e hora de criação ou emissão do instrumento de pagamento.'),

  dt_vencimento DATE
    OPTIONS(description = 'Data de vencimento do instrumento de pagamento.'),

  dt_pagamento DATE
    OPTIONS(description = 'Data de liquidação do instrumento; nula quando não existe pagamento registrado.'),

  vlr_instrumento_brl NUMERIC
    OPTIONS(description = 'Valor nominal do instrumento de pagamento, em reais.'),

  vlr_total_esperado_brl NUMERIC
    OPTIONS(description = 'Valor total esperado no pagamento, incluindo multa e juros, em reais.'),

  vlr_juros_esperado_brl NUMERIC
    OPTIONS(description = 'Valor de juros esperado no pagamento do instrumento, em reais.'),

  vlr_multa_esperada_brl NUMERIC
    OPTIONS(description = 'Valor de multa esperado no pagamento do instrumento, em reais.'),

  vlr_total_pago_brl NUMERIC
    OPTIONS(description = 'Valor total efetivamente registrado como pago, em reais.'),

  vlr_juros_pago_brl NUMERIC
    OPTIONS(description = 'Valor de juros efetivamente registrado como pago, em reais.'),

  vlr_multa_paga_brl NUMERIC
    OPTIONS(description = 'Valor de multa efetivamente registrada como paga, em reais.'),

  id_recebedor STRING
    OPTIONS(description = 'Identificador da entidade ou conta recebedora do pagamento.'),

  tipo_recebedor STRING
    OPTIONS(description = 'Tipo da entidade recebedora do pagamento.'),

  ts_ingestao_origem TIMESTAMP
    OPTIONS(description = 'Data e hora de ingestão informada pelo sistema financeiro de origem.'),

  ingerido_em TIMESTAMP
    OPTIONS(description = 'Data e hora em que o registro original foi ingerido na camada Raw.')
)
PARTITION BY dt_vencimento
CLUSTER BY id_faturamento, tipo_instrumento, status_instrumento
OPTIONS (
  description = 'Entidade Trusted unificada de instrumentos de pagamento por boleto e PIX, preservando uma linha por instrumento emitido.',
  labels = [
    ('camada', 'trusted'),
    ('dominio', 'financeiro'),
    ('entidade', 'instrumento_pagamento')
  ],
  require_partition_filter = FALSE
);
