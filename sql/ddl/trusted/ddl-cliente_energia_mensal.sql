-- BigQuery / GoogleSQL
-- =============================================================================
-- DDL — TRUSTED.CLIENTE_ENERGIA_MENSAL
--
-- Responsabilidade:
--   Criar somente a estrutura física e o contrato de dados da tabela Trusted.
--   A carga dos dados deve ser executada por uma procedure DML separada.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `lemon-ae-case.trusted.cliente_energia_mensal`
(
  id_instalacao STRING NOT NULL
    OPTIONS(description = 'Identificador da instalação ou unidade consumidora de energia.'),

  dt_mes_referencia DATE NOT NULL
    OPTIONS(description = 'Mês de competência ao qual os dados energéticos e financeiros da instalação se referem.'),

  usina STRING
    OPTIONS(description = 'Nome ou identificador funcional da usina associada à instalação na competência.'),

  gerador STRING
    OPTIONS(description = 'Nome ou identificador funcional do gerador associado à instalação na competência.'),

  cod_distribuidora STRING
    OPTIONS(description = 'Código ou nome padronizado da distribuidora de energia responsável pela instalação.'),

  saldo_bop_kwh NUMERIC
    OPTIONS(description = 'Saldo de créditos de energia, em kWh, existente no início da competência.'),

  saldo_eop_kwh NUMERIC
    OPTIONS(description = 'Saldo de créditos de energia, em kWh, remanescente no final da competência.'),

  qtd_churn_kwh NUMERIC
    OPTIONS(description = 'Quantidade de energia, em kWh, associada a movimentações classificadas como churn pela fonte.'),

  qtd_creditos_recebidos_mes_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia, em kWh, recebidos durante a competência.'),

  qtd_creditos_recebidos_meses_anteriores_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia, em kWh, recebidos e atribuídos a competências anteriores.'),

  qtd_creditos_faturados_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia, em kWh, considerada no faturamento da competência.'),

  qtd_creditos_compensados_mes_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia, em kWh, compensada na competência; valores negativos da fonte são preservados.'),

  qtd_creditos_compensados_meses_anteriores_kwh NUMERIC
    OPTIONS(description = 'Quantidade de créditos de energia, em kWh, compensada e atribuída a competências anteriores.'),

  perc_desconto_cliente NUMERIC
    OPTIONS(description = 'Percentual decimal de desconto associado ao cliente na competência, preservando a escala registrada pela fonte.'),

  perc_desconto_gerador NUMERIC
    OPTIONS(description = 'Percentual decimal de desconto associado ao gerador na competência, preservando a escala registrada pela fonte.'),

  vlr_gmv_real_oficial_brl NUMERIC
    OPTIONS(description = 'Valor oficial do GMV real da instalação na competência, expresso em reais.'),

  vlr_gmv_gerador_brl NUMERIC
    OPTIONS(description = 'Parcela do GMV atribuída ao gerador na competência, expressa em reais.'),

  vlr_take_rate_lemon_brl NUMERIC
    OPTIONS(description = 'Valor de take rate atribuído à Lemon na competência, expresso em reais.'),

  vlr_tarifa_saida_brl_por_kwh NUMERIC
    OPTIONS(description = 'Valor da tarifa de saída aplicado à energia, expresso em reais por kWh.'),

  vlr_pis_cofins_nao_compensado_lemon_brl_por_kwh NUMERIC
    OPTIONS(description = 'Valor de PIS e COFINS não compensado pela Lemon, expresso em reais por kWh.'),

  vlr_icms_nao_compensado_lemon_brl_por_kwh NUMERIC
    OPTIONS(description = 'Valor de ICMS não compensado pela Lemon, expresso em reais por kWh.'),

  vlr_ajuste_custo_disponibilidade_gerador_brl NUMERIC
    OPTIONS(description = 'Valor do ajuste relacionado ao custo de disponibilidade atribuído ao gerador, expresso em reais.'),

  vlr_desconto_gerador_brl_por_kwh NUMERIC
    OPTIONS(description = 'Valor unitário do desconto associado ao gerador, expresso em reais por kWh.'),

  etapa_processamento STRING
    OPTIONS(description = 'Etapa operacional informada pela fonte para o registro da instalação na competência.'),

  status_processamento STRING
    OPTIONS(description = 'Status operacional informado pela fonte para o registro da instalação na competência.'),

  txt_excecoes STRING
    OPTIONS(description = 'Texto livre com exceções ou observações operacionais informadas pela fonte.'),

  ingerido_em TIMESTAMP
    OPTIONS(description = 'Data e hora em que o registro foi ingerido na camada Raw.'),

  processado_em TIMESTAMP NOT NULL
    OPTIONS(description = 'Data e hora em que o registro foi processado e publicado na camada Trusted.'),

  hash_registro STRING NOT NULL
    OPTIONS(description = 'Hash SHA-256 do conteúdo normalizado, utilizado para detectar alterações e apoiar a rastreabilidade.'),

  qtd_duplicatas_origem INT64 NOT NULL
    OPTIONS(description = 'Quantidade de registros encontrados na Raw para a mesma instalação e competência antes da deduplicação.'),

  flg_registro_valido BOOL NOT NULL
    OPTIONS(description = 'Indica se o registro atende aos requisitos técnicos mínimos definidos para publicação na Trusted.')
)
PARTITION BY dt_mes_referencia
CLUSTER BY gerador, usina, cod_distribuidora
OPTIONS (
  description = 'Entidade mensal Trusted de clientes de energia, normalizada a partir da tabela raw.energy_clients.',
  labels = [
    ('camada', 'trusted'),
    ('dominio', 'energia'),
    ('origem', 'energy_clients')
  ],
  require_partition_filter = FALSE
);
