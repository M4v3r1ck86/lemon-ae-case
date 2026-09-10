-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.PIX
-- Origem: raw.finance_pixs
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.pix`
(
  id_pix STRING NOT NULL OPTIONS(description = 'Identificador técnico do instrumento de pagamento PIX.'),
  id_grafo_pix STRING NOT NULL OPTIONS(description = 'Identificador completo do nó PIX usado no grafo financeiro.'),
  id_faturamento STRING NOT NULL OPTIONS(description = 'Identificador do faturamento relacionado ao PIX.'),
  id_transacao STRING OPTIONS(description = 'Identificador transacional do PIX informado pela fonte.'),
  id_local STRING NOT NULL OPTIONS(description = 'Identificador do local ou estabelecimento associado ao PIX.'),
  status_pix STRING OPTIONS(description = 'Status operacional do instrumento de pagamento PIX.'),
  ts_criado_em TIMESTAMP OPTIONS(description = 'Data e hora de criação do PIX.'),
  dt_vencimento DATE OPTIONS(description = 'Data de vencimento do PIX.'),
  dt_pagamento DATE OPTIONS(description = 'Data de liquidação do PIX; nula quando não há pagamento.'),
  vlr_pix_brl NUMERIC OPTIONS(description = 'Valor nominal do PIX convertido de centavos para reais.'),
  id_recebedor STRING OPTIONS(description = 'Identificador da entidade ou conta recebedora.'),
  tipo_recebedor STRING OPTIONS(description = 'Tipo da entidade recebedora do PIX.'),
  vlr_total_esperado_brl NUMERIC OPTIONS(description = 'Valor total esperado no pagamento, incluindo encargos, convertido para reais.'),
  vlr_juros_esperado_brl NUMERIC OPTIONS(description = 'Valor de juros esperado, convertido de centavos para reais.'),
  vlr_multa_esperada_brl NUMERIC OPTIONS(description = 'Valor de multa esperada, convertido de centavos para reais.'),
  vlr_total_pago_brl NUMERIC OPTIONS(description = 'Valor total efetivamente pago, convertido de centavos para reais.'),
  vlr_juros_pago_brl NUMERIC OPTIONS(description = 'Valor de juros efetivamente pago, convertido de centavos para reais.'),
  vlr_multa_paga_brl NUMERIC OPTIONS(description = 'Valor de multa efetivamente paga, convertido de centavos para reais.'),
  cod_pix STRING OPTIONS(description = 'Código completo de pagamento ou payload do QR Code PIX; dado técnico de acesso restrito.'),
  ts_ingestao_origem TIMESTAMP OPTIONS(description = 'Data e hora de ingestão informada pelo sistema financeiro de origem.'),
  ingerido_em TIMESTAMP OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.')
)
PARTITION BY dt_vencimento
CLUSTER BY id_faturamento, status_pix, id_local
OPTIONS (
  description = 'Entidade Trusted de instrumentos de pagamento PIX, normalizada a partir de raw.finance_pixs.',
  labels = [('camada', 'trusted'), ('dominio', 'financeiro'), ('origem', 'finance_pixs')],
  require_partition_filter = FALSE
);
