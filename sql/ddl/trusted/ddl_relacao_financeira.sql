-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.RELACAO_FINANCEIRA
-- Origem: raw.finance_relations
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.relacao_financeira`
(
  id_grafo_origem STRING NOT NULL
    OPTIONS(description = 'Identificador completo do nó de origem da relação financeira.'),
  tipo_entidade_origem STRING NOT NULL
    OPTIONS(description = 'Tipo da entidade de origem extraído do prefixo do identificador; billing no snapshot analisado.'),
  id_origem STRING NOT NULL
    OPTIONS(description = 'Identificador da entidade de origem sem o prefixo do grafo.'),
  id_grafo_destino STRING NOT NULL
    OPTIONS(description = 'Identificador completo do nó de destino da relação financeira.'),
  tipo_entidade_destino STRING NOT NULL
    OPTIONS(description = 'Tipo da entidade de destino extraído do prefixo: charge, boleto ou pix.'),
  id_destino STRING NOT NULL
    OPTIONS(description = 'Identificador da entidade de destino sem o prefixo do grafo.'),
  ts_criado_em TIMESTAMP
    OPTIONS(description = 'Data e hora de criação da relação entre as entidades financeiras.'),
  ts_ingestao_origem TIMESTAMP
    OPTIONS(description = 'Data e hora de ingestão informada pelo sistema financeiro de origem.'),
  ingerido_em TIMESTAMP
    OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.')
)
PARTITION BY DATE(ts_criado_em)
CLUSTER BY tipo_entidade_destino, id_origem
OPTIONS (
  description = 'Arestas Trusted do grafo financeiro, normalizadas a partir de raw.finance_relations.',
  labels = [('camada', 'trusted'), ('dominio', 'financeiro'), ('origem', 'finance_relations')],
  require_partition_filter = FALSE
);
