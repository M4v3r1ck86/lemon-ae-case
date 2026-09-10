-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.FATURAMENTO_CLIENTE_MENSAL
--
-- Responsabilidade:
--   Integrar cliente, cobrança, faturamento e indicadores dos instrumentos de
--   pagamento em uma entidade mensal sem fanout.
--
-- Grain:
--   Uma linha por id_instalacao + dt_mes_referencia.
--
-- Origens:
--   trusted.cliente_energia_mensal
--   trusted.cobranca
--   trusted.faturamento
--   trusted.instrumento_pagamento, previamente agregado por faturamento.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.faturamento_cliente_mensal`
(
  id_instalacao STRING NOT NULL
    OPTIONS(description = 'Identificador da instalação ou unidade consumidora de energia.'),
  dt_mes_referencia DATE NOT NULL
    OPTIONS(description = 'Mês de competência energética e financeira da instalação.'),
  gerador STRING
    OPTIONS(description = 'Nome ou identificador funcional do gerador associado à instalação.'),
  usina STRING
    OPTIONS(description = 'Nome ou identificador funcional da usina associada à instalação.'),
  cod_distribuidora STRING
    OPTIONS(description = 'Código ou nome padronizado da distribuidora de energia.'),
  id_cobranca STRING
    OPTIONS(description = 'Identificador da cobrança associada à instalação e competência.'),
  id_faturamento STRING
    OPTIONS(description = 'Identificador do faturamento associado à cobrança.'),
  id_local STRING
    OPTIONS(description = 'Identificador do local ou estabelecimento associado ao faturamento.'),
  status_cobranca STRING
    OPTIONS(description = 'Status operacional da cobrança.'),
  status_faturamento STRING
    OPTIONS(description = 'Status operacional do faturamento.'),
  ts_criacao_cobranca TIMESTAMP
    OPTIONS(description = 'Data e hora de criação da cobrança.'),
  ts_criacao_faturamento TIMESTAMP
    OPTIONS(description = 'Data e hora de criação do faturamento.'),
  dt_vencimento DATE
    OPTIONS(description = 'Data de vencimento vigente do faturamento.'),
  dt_vencimento_original DATE
    OPTIONS(description = 'Data de vencimento original do faturamento.'),
  dt_pagamento DATE
    OPTIONS(description = 'Data em que o pagamento foi registrado no faturamento.'),
  dt_mes_pagamento DATE
    OPTIONS(description = 'Primeiro dia do mês em que o pagamento foi registrado, utilizado para análises por competência de liquidação.'),
  vlr_gmv_real_oficial_brl NUMERIC
    OPTIONS(description = 'Valor oficial do GMV da instalação na competência, em reais.'),
  vlr_gmv_gerador_brl NUMERIC
    OPTIONS(description = 'Parcela do GMV atribuída ao gerador na competência, em reais.'),
  vlr_cobranca_brl NUMERIC
    OPTIONS(description = 'Valor nominal da cobrança associada à instalação, em reais.'),
  vlr_faturamento_brl NUMERIC
    OPTIONS(description = 'Valor nominal registrado no faturamento, em reais.'),
  vlr_total_pago_brl NUMERIC
    OPTIONS(description = 'Valor total pago registrado no faturamento, incluindo multa e juros, em reais.'),
  vlr_principal_pago_brl NUMERIC
    OPTIONS(description = 'Valor pago excluindo multa e juros, calculado a partir dos valores do faturamento, em reais.'),
  vlr_juros_pago_brl NUMERIC
    OPTIONS(description = 'Valor de juros pago registrado no faturamento, em reais.'),
  vlr_multa_paga_brl NUMERIC
    OPTIONS(description = 'Valor de multa paga registrado no faturamento, em reais.'),
  qtd_creditos_faturados_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia faturados para a instalação na competência, em kWh.'),
  qtd_creditos_faturados_pagos_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos faturados associada a faturamento pago; zero quando o faturamento não está pago.'),
  qtd_instrumentos INT64
    OPTIONS(description = 'Quantidade total de boletos e PIX vinculados ao faturamento.'),
  qtd_boletos INT64
    OPTIONS(description = 'Quantidade de boletos vinculados ao faturamento.'),
  qtd_pixs INT64
    OPTIONS(description = 'Quantidade de instrumentos PIX vinculados ao faturamento.'),
  qtd_instrumentos_pagos INT64
    OPTIONS(description = 'Quantidade de instrumentos vinculados ao faturamento com status pago.'),
  flg_emitido BOOL
    OPTIONS(description = 'Indica que existe faturamento emitido para a instalação e competência.'),
  flg_pago BOOL
    OPTIONS(description = 'Indica que o faturamento está pago ou possui data de pagamento registrada.'),
  flg_multiplos_instrumentos_pagos BOOL
    OPTIONS(description = 'Indica que mais de um instrumento está marcado como pago para o mesmo faturamento.'),
  ingerido_em TIMESTAMP
    OPTIONS(description = 'Data e hora mais recente de ingestão entre os registros utilizados na composição da linha.')
)
PARTITION BY dt_mes_referencia
CLUSTER BY gerador, usina, cod_distribuidora, status_faturamento
OPTIONS (
  description = 'Entidade Trusted mensal que integra clientes, cobranças, faturamentos e indicadores de instrumentos sem multiplicar valores financeiros.',
  labels = [
    ('camada', 'trusted'),
    ('dominio', 'financeiro_energia'),
    ('entidade', 'faturamento_cliente_mensal')
  ],
  require_partition_filter = FALSE
);
