-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.DESEMPENHO_USINA_MENSAL
--
-- Responsabilidade:
--   Consolidar geração, créditos de clientes e resultados financeiros no grão
--   mensal da usina, oferecendo indicadores reutilizáveis de desempenho.
--
-- Grain:
--   Uma linha por gerador + usina + cod_distribuidora + dt_mes_referencia.
--
-- Origens:
--   trusted.usina_energia_mensal
--   trusted.cliente_energia_mensal, agregada por usina e mês.
--   trusted.faturamento_cliente_mensal, agregada por usina e mês.
--
-- Fora do escopo:
--   Seleção de faixa de take rate e cálculo dos repasses do relatório final.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.desempenho_usina_mensal`
(
  gerador STRING NOT NULL
    OPTIONS(description = 'Nome ou identificador funcional do gerador responsável pela usina.'),
  usina STRING NOT NULL
    OPTIONS(description = 'Nome ou identificador funcional da usina de energia.'),
  cod_distribuidora STRING NOT NULL
    OPTIONS(description = 'Código ou nome padronizado da distribuidora de energia.'),
  dt_mes_referencia DATE NOT NULL
    OPTIONS(description = 'Mês de competência das métricas operacionais, energéticas e financeiras da usina.'),
  qtd_instalacoes INT64
    OPTIONS(description = 'Quantidade de instalações de clientes associadas à usina na competência.'),
  qtd_faturamentos_emitidos INT64
    OPTIONS(description = 'Quantidade de faturamentos emitidos para instalações da usina na competência.'),
  qtd_faturamentos_pagos INT64
    OPTIONS(description = 'Quantidade de faturamentos pagos para instalações da usina na competência.'),
  qtd_faturamentos_pagos_d60 INT64
    OPTIONS(description = 'Quantidade de faturamentos pagos até D+60 na competência.'),
  qtd_faturamentos_pagos_apos_d60 INT64
    OPTIONS(description = 'Quantidade de faturamentos pagos após D+60 na competência.'),
  qtd_faturamentos_multiplos_instrumentos_pagos INT64
    OPTIONS(description = 'Quantidade de faturamentos da usina com mais de um instrumento marcado como pago.'),
  qtd_creditos_injetados_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia injetados na rede da distribuidora, em kWh.'),
  qtd_geracao_prevista_contrato_kwh NUMERIC
    OPTIONS(description = 'Quantidade de geração prevista contratualmente para a usina, em kWh.'),
  qtd_geracao_realizada_gerador_kwh NUMERIC
    OPTIONS(description = 'Quantidade de energia registrada como gerada pela usina, em kWh.'),
  qtd_minima_injecao_kwh NUMERIC
    OPTIONS(description = 'Menor valor entre créditos injetados e geração prevista no contrato, em kWh.'),
  qtd_creditos_recebidos_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos recebidos pelas instalações vinculadas à usina na competência, em kWh.'),
  qtd_creditos_faturados_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos faturados pelas instalações vinculadas à usina na competência, em kWh.'),
  qtd_creditos_faturados_pagos_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos faturados associada a faturamentos pagos das instalações da usina, em kWh.'),
  qtd_creditos_faturados_pagos_d60_kwh NUMERIC
    OPTIONS(description = 'Créditos faturados associados a pagamentos elegíveis até D+60.'),
  dt_fechamento_competencia DATE
    OPTIONS(description = 'Maior data D+60 entre os faturamentos da usina e competência.'),
  flg_competencia_fechada BOOL
    OPTIONS(description = 'Indica que a data de processamento já alcançou o fechamento D+60.'),
  vlr_gmv_real_oficial_brl NUMERIC
    OPTIONS(description = 'Soma do GMV real oficial das instalações vinculadas à usina na competência, em reais.'),
  vlr_gmv_gerador_brl NUMERIC
    OPTIONS(description = 'Soma da parcela de GMV atribuída ao gerador para as instalações da usina, em reais.'),
  vlr_cobranca_gerador_brl NUMERIC
    OPTIONS(description = 'Soma do GMV do gerador somente para instalações com faturamento emitido na competência, em reais.'),
  vlr_cobranca_brl NUMERIC
    OPTIONS(description = 'Soma dos valores nominais das cobranças das instalações da usina, em reais.'),
  vlr_faturamento_brl NUMERIC
    OPTIONS(description = 'Soma dos valores nominais dos faturamentos das instalações da usina, em reais.'),
  vlr_total_pago_brl NUMERIC
    OPTIONS(description = 'Soma dos valores totais pagos, incluindo multa e juros, em reais.'),
  vlr_principal_pago_brl NUMERIC
    OPTIONS(description = 'Soma dos valores pagos excluindo multa e juros, em reais.'),
  vlr_liquidado_gerador_brl NUMERIC
    OPTIONS(description = 'Parcela do principal pago atribuída ao gerador proporcionalmente ao GMV do gerador, em reais.'),
  vlr_liquidado_gerador_d60_brl NUMERIC
    OPTIONS(description = 'Parcela liquidada do gerador reconhecida até D+60, em reais.'),
  vlr_liquidado_gerador_apos_d60_brl NUMERIC
    OPTIONS(description = 'Parcela liquidada do gerador recebida depois de D+60, em reais.'),
  vlr_juros_pago_d60_brl NUMERIC
    OPTIONS(description = 'Juros pagos em faturamentos elegíveis até D+60, em reais.'),
  vlr_multa_paga_d60_brl NUMERIC
    OPTIONS(description = 'Multas pagas em faturamentos elegíveis até D+60, em reais.'),
  vlr_juros_pago_brl NUMERIC
    OPTIONS(description = 'Soma dos valores de juros pagos, em reais.'),
  vlr_multa_paga_brl NUMERIC
    OPTIONS(description = 'Soma dos valores de multas pagas, em reais.'),
  vlr_tusd_brl NUMERIC
    OPTIONS(description = 'Valor monetário registrado na origem como TUSD para a usina, em reais.'),
  dt_mes_desconto_tusd_gerador DATE
    OPTIONS(description = 'Mês de competência em que a TUSD deve ser deduzida do repasse do gerador.'),
  vlr_tusd_descontada_gerador_brl NUMERIC
    OPTIONS(description = 'Valor de TUSD deduzido do repasse do gerador, em reais.'),
  vlr_aluguel_imoveis_brl NUMERIC
    OPTIONS(description = 'Valor de aluguel de imóveis associado à usina, em reais.'),
  vlr_aluguel_equipamento_brl NUMERIC
    OPTIONS(description = 'Valor de aluguel de equipamentos associado à usina, em reais.'),
  vlr_operacao_manutencao_brl NUMERIC
    OPTIONS(description = 'Valor de custos de operação e manutenção associado à usina, em reais.'),
  perc_injetado_vs_previsto NUMERIC
    OPTIONS(description = 'Razão entre créditos injetados e geração prevista no contrato.'),
  perc_distribuidora_vs_inversor NUMERIC
    OPTIONS(description = 'Razão entre créditos injetados e geração realizada pelo gerador.'),
  perc_recebidos_vs_injetados NUMERIC
    OPTIONS(description = 'Razão entre créditos recebidos pelos clientes e créditos injetados pela usina.'),
  perc_faturados_vs_recebidos NUMERIC
    OPTIONS(description = 'Razão entre créditos faturados e créditos recebidos pelas instalações da usina.'),
  perc_preenchimento_usina NUMERIC
    OPTIONS(description = 'Razão entre créditos faturados e a quantidade mínima de injeção da usina.'),
  perc_desempenho_lemon NUMERIC
    OPTIONS(description = 'Razão entre créditos faturados pagos e a quantidade mínima de injeção da usina.'),
  flg_possui_clientes BOOL
    OPTIONS(description = 'Indica que a usina possui instalações de clientes associadas na competência.'),
  flg_possui_faturamento BOOL
    OPTIONS(description = 'Indica que a usina possui pelo menos um faturamento emitido na competência.'),
  ingerido_em TIMESTAMP
    OPTIONS(description = 'Data e hora mais recente de ingestão entre os registros utilizados na composição da linha.')
)
PARTITION BY dt_mes_referencia
CLUSTER BY gerador, usina, cod_distribuidora
OPTIONS (
  description = 'Entidade Trusted mensal de desempenho energético e financeiro das usinas, sem aplicação de take rate ou cálculo de repasses.',
  labels = [
    ('camada', 'trusted'),
    ('dominio', 'energia_financeiro'),
    ('entidade', 'desempenho_usina_mensal')
  ],
  require_partition_filter = FALSE
);
