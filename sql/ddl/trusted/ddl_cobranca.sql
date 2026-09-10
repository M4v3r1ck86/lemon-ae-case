-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.COBRANCA
-- Origem: raw.finance_charges
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.cobranca`
(
  id_cobranca STRING NOT NULL OPTIONS(description = 'Identificador técnico da cobrança sem o prefixo de entidade.'),
  id_grafo_cobranca STRING NOT NULL OPTIONS(description = 'Identificador completo do nó de cobrança usado no grafo financeiro.'),
  id_faturamento STRING NOT NULL OPTIONS(description = 'Identificador do faturamento relacionado à cobrança.'),
  id_plano_faturamento STRING OPTIONS(description = 'Identificador do plano de faturamento associado à cobrança.'),
  id_local STRING NOT NULL OPTIONS(description = 'Identificador do local ou estabelecimento associado à cobrança.'),
  id_instalacao STRING NOT NULL OPTIONS(description = 'Identificador da instalação ou unidade consumidora na distribuidora.'),
  cod_distribuidora STRING OPTIONS(description = 'Código ou nome padronizado da distribuidora de energia.'),
  dt_mes_referencia DATE NOT NULL OPTIONS(description = 'Mês de competência da cobrança.'),
  id_pipedrive INT64 OPTIONS(description = 'Identificador externo da cobrança no Pipedrive.'),
  produto STRING OPTIONS(description = 'Produto associado à cobrança.'),
  tipo_provedor_cobranca STRING OPTIONS(description = 'Tipo do provedor responsável pela cobrança.'),
  status_cobranca STRING OPTIONS(description = 'Status operacional da cobrança.'),
  id_assinante STRING OPTIONS(description = 'Identificador do assinante ou entidade consumidora.'),
  tipo_assinante STRING OPTIONS(description = 'Tipo do assinante associado à cobrança.'),
  tipo_cobranca STRING OPTIONS(description = 'Categoria operacional da cobrança.'),
  id_assinatura STRING OPTIONS(description = 'Identificador da assinatura associada à cobrança.'),
  ts_criado_em TIMESTAMP OPTIONS(description = 'Data e hora de criação da cobrança.'),
  dt_pagamento DATE OPTIONS(description = 'Data de pagamento utilizada como data de liquidação da cobrança.'),
  vlr_cobranca_brl NUMERIC OPTIONS(description = 'Valor nominal da cobrança convertido de centavos para reais.'),
  vlr_sem_descontos_brl NUMERIC OPTIONS(description = 'Valor da cobrança antes de descontos, convertido de centavos para reais.'),
  vlr_desconto_temporario_brl NUMERIC OPTIONS(description = 'Valor de desconto temporário, convertido de centavos para reais.'),
  ts_cancelamento TIMESTAMP OPTIONS(description = 'Data e hora de cancelamento da cobrança.'),
  motivo_cancelamento STRING OPTIONS(description = 'Motivo informado para o cancelamento da cobrança.'),
  tipo_cancelamento STRING OPTIONS(description = 'Categoria informada para o cancelamento da cobrança.'),
  cancelado_por STRING OPTIONS(description = 'Identificador do responsável pelo cancelamento.'),
  descricao_cancelamento STRING OPTIONS(description = 'Descrição textual do cancelamento.'),
  ts_ingestao_origem TIMESTAMP OPTIONS(description = 'Data e hora de ingestão informada pelo sistema financeiro de origem.'),
  ingerido_em TIMESTAMP OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.')
)
PARTITION BY dt_mes_referencia
CLUSTER BY id_instalacao, status_cobranca, cod_distribuidora
OPTIONS (
  description = 'Entidade mensal Trusted de cobranças por instalação, normalizada a partir de raw.finance_charges.',
  labels = [('camada', 'trusted'), ('dominio', 'financeiro'), ('origem', 'finance_charges')],
  require_partition_filter = FALSE
);
