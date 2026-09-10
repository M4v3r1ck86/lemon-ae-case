-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.FATURAMENTO
-- Origem: raw.finance_billings
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.faturamento`
(
  id_faturamento STRING NOT NULL OPTIONS(description = 'Identificador técnico do faturamento sem o prefixo de entidade.'),
  id_grafo_faturamento STRING NOT NULL OPTIONS(description = 'Identificador completo do nó de faturamento usado no grafo financeiro.'),
  id_local STRING NOT NULL OPTIONS(description = 'Identificador do local ou estabelecimento associado ao faturamento.'),
  id_usina_backend STRING OPTIONS(description = 'Identificador de usina utilizado pelo backend financeiro.'),
  status_faturamento STRING OPTIONS(description = 'Status operacional do faturamento.'),
  vlr_faturamento_brl NUMERIC OPTIONS(description = 'Valor nominal do faturamento convertido de centavos para reais.'),
  vlr_sem_descontos_brl NUMERIC OPTIONS(description = 'Valor do faturamento antes de descontos, convertido de centavos para reais.'),
  vlr_desconto_temporario_brl NUMERIC OPTIONS(description = 'Valor de desconto temporário, convertido de centavos para reais.'),
  ts_criado_em TIMESTAMP OPTIONS(description = 'Data e hora de criação do faturamento.'),
  dt_vencimento DATE OPTIONS(description = 'Data de vencimento vigente do faturamento.'),
  dt_vencimento_original DATE OPTIONS(description = 'Data de vencimento original do faturamento.'),
  ts_pagamento TIMESTAMP OPTIONS(description = 'Data e hora de pagamento registrada no nível do faturamento.'),
  qtd_reagendamentos INT64 OPTIONS(description = 'Quantidade de reagendamentos registrada para o faturamento.'),
  ts_cancelamento TIMESTAMP OPTIONS(description = 'Data e hora de cancelamento do faturamento.'),
  motivo_cancelamento STRING OPTIONS(description = 'Motivo informado para o cancelamento do faturamento.'),
  tipo_cancelamento STRING OPTIONS(description = 'Categoria informada para o cancelamento do faturamento.'),
  cancelado_por STRING OPTIONS(description = 'Identificador do responsável pelo cancelamento.'),
  descricao_cancelamento STRING OPTIONS(description = 'Descrição textual do cancelamento.'),
  vlr_total_esperado_brl NUMERIC OPTIONS(description = 'Valor total esperado no recebimento, incluindo encargos, convertido para reais.'),
  vlr_juros_esperado_brl NUMERIC OPTIONS(description = 'Valor de juros esperado, convertido de centavos para reais.'),
  vlr_multa_esperada_brl NUMERIC OPTIONS(description = 'Valor de multa esperado, convertido de centavos para reais.'),
  vlr_total_pago_brl NUMERIC OPTIONS(description = 'Valor total efetivamente pago, convertido de centavos para reais.'),
  vlr_juros_pago_brl NUMERIC OPTIONS(description = 'Valor de juros efetivamente pago, convertido de centavos para reais.'),
  vlr_multa_paga_brl NUMERIC OPTIONS(description = 'Valor de multa efetivamente paga, convertido de centavos para reais.'),
  id_recebedor STRING OPTIONS(description = 'Identificador da entidade ou conta recebedora.'),
  tipo_recebedor STRING OPTIONS(description = 'Tipo da entidade recebedora do faturamento.'),
  ts_ingestao_origem TIMESTAMP OPTIONS(description = 'Data e hora de ingestão informada pelo sistema financeiro de origem.'),
  ingerido_em TIMESTAMP OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.')
)
PARTITION BY DATE(ts_criado_em)
CLUSTER BY status_faturamento, id_local, tipo_recebedor
OPTIONS (
  description = 'Entidade Trusted de faturamentos financeiros, normalizada a partir de raw.finance_billings.',
  labels = [('camada', 'trusted'), ('dominio', 'financeiro'), ('origem', 'finance_billings')],
  require_partition_filter = FALSE
);
