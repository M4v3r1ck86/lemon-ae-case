-- BigQuery / GoogleSQL
-- ============================================================================
-- GENERATOR REPORT — PARIDADE COM A LÓGICA ORIGINAL EM TABELAS TEMPORÁRIAS
-- ============================================================================
--
-- OBJETIVO
-- Reproduzir, em etapas inspecionáveis, a lógica da view
-- validation.generator_report_legacy_parity.
--
-- POR QUE ESTE ARQUIVO EXISTE
-- A versão implantável da view precisa permanecer em uma única instrução
-- CREATE VIEW e, por isso, utiliza CTEs. Este arquivo troca cada CTE por uma
-- tabela temporária para permitir:
--
--   1. executar uma transformação por vez;
--   2. consultar o resultado de cada etapa;
--   3. conferir grain, chaves, duplicidades e filtros;
--   4. localizar exatamente onde os valores são multiplicados;
--   5. comparar o resultado intermediário com a view original.
--
-- PADRÃO DE NOMENCLATURA
-- Todas as tabelas temporárias seguem:
--
--   tmp_<função_da_etapa>
--
-- tmp              = objeto temporário da sessão do BigQuery;
-- função_da_etapa  = descrição funcional em inglês, sem siglas opacas.
--
--
-- LIMITAÇÃO DO BIGQUERY
-- Uma view persistente não pode depender destas tabelas temporárias, pois elas
-- deixam de existir ao final do script. O resultado final deste arquivo é a
-- temporária tmp_final_result. A criação da view
-- persistente de paridade é mantida separadamente no dataset validation.
--
-- COMO EXECUTAR
-- Execute este arquivo como um único script. Os SELECTs de diagnóstico podem
-- ser executados individualmente depois que as temporárias anteriores tiverem
-- sido criadas na mesma sessão.


-- ============================================================================
-- ETAPA 01 — TMP_BILLINGS
-- BILLINGS E DATAS DE EMISSÃO
--
-- O QUE REPRESENTA
-- Um billing financeiro emitido pela plataforma.
--
-- POR QUE EXISTE
-- A cobrança identifica instalação e competência, mas a data de emissão usada
-- nas flags do relatório está no billing.
--
-- SAÍDA PRINCIPAL
-- billing_id, valor, status, data de criação e vencimento.
--
-- UTILIZADA POR
-- tmp_bank_slip_payment_events e tmp_pix_payment_events.
-- ============================================================================


CREATE OR REPLACE TEMP TABLE tmp_billings AS
SELECT
  source AS billing_id,
  amount,
  billing_energy_farm_id,
  status,
  create_at,
  due_date
FROM `lemon-ae-case.raw.finance_billings`;

-- SELECT * FROM tmp_billings;



-- ============================================================================
-- ETAPA 02 — TMP_BILLING_CHARGE_RELATIONS
-- PONTE ENTRE BILLING E COBRANÇA
--
-- O QUE REPRESENTA
-- As arestas billing → charge registradas em finance_relations.
--
-- POR QUE EXISTE
-- finance_charges não contém uma FK tradicional apontando diretamente para o
-- billing usado pelo relatório. A tabela grafo fornece essa ligação.
--
-- LEITURA DO FILTRO
-- source LIKE 'billing#%' mantém IDs iniciados por billing#.
-- target LIKE 'charge#%' mantém IDs iniciados por charge#.
-- O caractere % aceita qualquer conteúdo depois do prefixo.
--
-- GRAIN ESPERADO
-- Uma linha por relacionamento billing × charge.
--
-- UTILIZADA POR
-- As duas ramificações de instrumento: boleto e PIX.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_billing_charge_relations AS
SELECT
  source AS billing_id,
  target AS charge_id
FROM `lemon-ae-case.raw.finance_relations`
WHERE
  source LIKE 'billing#%'
  AND target LIKE 'charge#%';




-- ============================================================================
-- ETAPA 03 — TMP_CHARGES
-- COBRANÇAS, INSTALAÇÕES, COMPETÊNCIAS E LIQUIDAÇÕES
--
-- O QUE REPRESENTA
-- Uma cobrança financeira associada a uma unidade consumidora.
--
-- POR QUE EXISTE
-- Fornece as duas chaves usadas para chegar ao cliente:
-- numero_instalacao + mes_referencia. Também fornece status e payment.
--
-- UTILIZADA POR
-- tmp_bank_slip_payment_events e tmp_pix_payment_events.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_charges AS
SELECT
  source AS charge_id,
  cancelled_at,
  cancellation_reason,
  reference_month,
  disco_consumer_unit_id,
  payment_date,
  status,
  amount
FROM `lemon-ae-case.raw.finance_charges`;


-- ============================================================================
-- ETAPA 04 — TMP_BILLING_BANK_SLIP_RELATIONS
-- PONTE ENTRE BILLING E BOLETO
--
-- O QUE REPRESENTA
-- As arestas billing → boleto registradas em finance_relations.
--
-- POR QUE EXISTE
-- Permite localizar todos os boletos e tentativas de boleto de um billing.
--
-- PONTO DE ATENÇÃO
-- Um billing pode possuir mais de um bank_slip. Cada relação adicional pode criar
-- uma nova linha quando o join for executado.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_billing_bank_slip_relations AS
SELECT
  source AS billing_id,
  target AS boleto_id
FROM `lemon-ae-case.raw.finance_relations`
WHERE
  source LIKE 'billing#%'
  AND target LIKE 'boleto#%';


-- ============================================================================
-- ETAPA 05 — TMP_BILLING_PIX_RELATIONS
-- PONTE ENTRE BILLING E PIX
--
-- O QUE REPRESENTA
-- As arestas billing → PIX registradas em finance_relations.
--
-- POR QUE EXISTE
-- Permite localizar todos os PIX e tentativas de PIX de um billing.
--
-- PONTO DE ATENÇÃO
-- Um billing pode possuir mais de um PIX. Cada relação adicional pode criar
-- uma nova linha quando o join for executado.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_billing_pix_relations AS
SELECT
  source AS billing_id,
  target AS pix_id
FROM `lemon-ae-case.raw.finance_relations`
WHERE
  source LIKE 'billing#%'
  AND target LIKE 'pix#%';


-- ============================================================================
-- ETAPA 06 — TMP_BANK_SLIPS
-- VALORES PAGOS, MULTA E JUROS DOS BOLETOS
--
-- O QUE REPRESENTA
-- Um instrumento ou tentativa de pagamento via bank_slip.
--
-- POR QUE EXISTE
-- Fornece total pago, juros e multa para os cálculos financeiros posteriores.
--
-- UTILIZADA POR
-- tmp_bank_slip_payment_events.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_bank_slips AS
SELECT
  source AS boleto_id,
  amount,
  bank_slip_paid_total,
  bank_slip_paid_interest,
  bank_slip_paid_fine
FROM `lemon-ae-case.raw.finance_boletos`;


-- ============================================================================
-- ETAPA 07 — TMP_PIX_PAYMENTS
-- VALORES PAGOS, MULTA E JUROS DOS PIXS
--
-- O QUE REPRESENTA
-- Um instrumento ou tentativa de pagamento via PIX.
--
-- POR QUE EXISTE
-- Fornece total pago, juros e multa para os cálculos financeiros posteriores.
--
-- UTILIZADA POR
-- tmp_pix_payment_events.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_pix_payments AS
SELECT
  source AS pix_id,
  amount,
  pix_paid_total,
  pix_paid_interest,
  pix_paid_fine
FROM `lemon-ae-case.raw.finance_pixs`;


-- ============================================================================
-- DIAGNÓSTICO 01 — QUANTIDADE DE INSTRUMENTOS POR BILLING
--
-- O QUE MOSTRA
-- Quantos boletos e PIX estão ligados a cada billing antes dos joins.
--
-- POR QUE É IMPORTANTE
-- A implementação original cria uma ramificação para boleto e outra para PIX.
-- Depois usa UNION ALL. A quantidade de linhas produzida por billing é:
--
--   MAX(qtd_boletos, 1) + MAX(qtd_pixs, 1)
--
-- Exemplos encontrados nos dados:
--   1 boleto + 1 PIX  → 2 linhas;
--   2 boletos + 2 PIX → 4 linhas;
--   3 boletos + 3 PIX → 6 linhas.
--
-- Essa multiplicidade é legítima para inspecionar tentativas de pagamento,
-- mas é indevida quando uma medida no grain instalação × mês, como
-- gmv_gerador_brl, é repetida e somada em cada linha de instrumento.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_diagnostic_payment_instrument_counts AS
WITH bank_slips_per_billing AS (
  SELECT
    billing_id,
    COUNT(*) AS quantidade_boletos
  FROM tmp_billing_bank_slip_relations
  GROUP BY billing_id
),
pix_payments_per_billing AS (
  SELECT
    billing_id,
    COUNT(*) AS quantidade_pixs
  FROM tmp_billing_pix_relations
  GROUP BY billing_id
)
SELECT
  relation.billing_id,
  relation.charge_id,
  COALESCE(bank_slip.quantidade_boletos, 0) AS quantidade_boletos,
  COALESCE(pix.quantidade_pixs, 0) AS quantidade_pixs,
  GREATEST(COALESCE(bank_slip.quantidade_boletos, 0), 1)
    + GREATEST(COALESCE(pix.quantidade_pixs, 0), 1)
      AS quantidade_linhas_produzidas_no_legado
FROM tmp_billing_charge_relations AS relation
LEFT JOIN bank_slips_per_billing AS bank_slip USING (billing_id)
LEFT JOIN pix_payments_per_billing AS pix USING (billing_id);

-- Execute para localizar billings com maior multiplicidade.
SELECT
  *
FROM tmp_diagnostic_payment_instrument_counts
WHERE
  quantidade_boletos > 1
  OR quantidade_pixs > 1
ORDER BY
  quantidade_linhas_produzidas_no_legado DESC,
  billing_id;


-- ============================================================================
-- ETAPA 08 — TMP_BANK_SLIP_PAYMENT_EVENTS
-- RAMIFICAÇÃO FINANCEIRA DE BOLETOS
--
-- O QUE FAZ
-- Parte de charge → billing e adiciona todos os boletos do billing.
--
-- POR QUE EXISTE
-- Normaliza os nomes específicos do boleto para nomes comuns de instrumento,
-- permitindo o UNION ALL posterior com a ramificação de PIX.
--
-- PONTO EXATO DO FANOUT
-- O LEFT JOIN com billings2boletos gera uma linha para cada boleto relacionado.
-- Se não existir boleto, o LEFT JOIN ainda preserva uma linha com campos NULL.
--
-- CONVERSÃO MONETÁRIA ORIGINAL PRESERVADA
-- DIV(valor, 100) reproduz a divisão inteira do SQLite e descarta centavos.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_bank_slip_payment_events AS
SELECT
  charge.cancelled_at,
  charge.cancellation_reason,
  charge.charge_id,
  charge.reference_month,
  charge.disco_consumer_unit_id,
  charge.payment_date,
  charge.status AS charge_status,
  DIV(charge.amount, 100) AS charge_amount_brl,
  DIV(billing.amount, 100) AS billing_amount_brl,
  billing.billing_energy_farm_id,
  billing.billing_id,
  billing.status AS billing_status,
  billing.create_at AS billing_create_at,
  billing.due_date AS billing_due_date,
  DIV(bank_slip.amount, 100) AS instrumento_amount_brl,
  DIV(bank_slip.bank_slip_paid_total, 100) AS instrumento_amount_paid_brl,
  DIV(
    bank_slip.bank_slip_paid_interest + bank_slip.bank_slip_paid_fine,
    100
  ) AS instrumento_fine_and_interest_brl,
  DIV(
    bank_slip.bank_slip_paid_total
      - bank_slip.bank_slip_paid_interest
      - bank_slip.bank_slip_paid_fine,
    100
  ) AS instrumento_amount_paid_net_brl,
  billing.create_at IS NOT NULL AS possui_data_emissao
FROM tmp_charges AS charge
INNER JOIN tmp_billing_charge_relations AS relation
  ON relation.charge_id = charge.charge_id
INNER JOIN tmp_billings AS billing
  ON billing.billing_id = relation.billing_id
LEFT JOIN tmp_billing_bank_slip_relations AS bank_slip_relation
  ON bank_slip_relation.billing_id = billing.billing_id
LEFT JOIN tmp_bank_slips AS bank_slip
  ON bank_slip.boleto_id = bank_slip_relation.boleto_id;


-- ============================================================================
-- ETAPA 09 — TMP_PIX_PAYMENT_EVENTS
-- RAMIFICAÇÃO FINANCEIRA DE PIX
--
-- O QUE FAZ
-- Parte da mesma relação charge → billing e adiciona todos os PIX do billing.
--
-- POR QUE EXISTE
-- Normaliza os campos específicos do PIX para o mesmo schema criado no bloco
-- de bank_slip.
--
-- PONTO EXATO DO FANOUT
-- O LEFT JOIN gera uma linha para cada PIX relacionado. Se não existir PIX,
-- ainda preserva uma linha com campos NULL.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_pix_payment_events AS
SELECT
  charge.cancelled_at,
  charge.cancellation_reason,
  charge.charge_id,
  charge.reference_month,
  charge.disco_consumer_unit_id,
  charge.payment_date,
  charge.status AS charge_status,
  DIV(charge.amount, 100) AS charge_amount_brl,
  DIV(billing.amount, 100) AS billing_amount_brl,
  billing.billing_energy_farm_id,
  billing.billing_id,
  billing.status AS billing_status,
  billing.create_at AS billing_create_at,
  billing.due_date AS billing_due_date,
  DIV(pix.amount, 100) AS instrumento_amount_brl,
  DIV(pix.pix_paid_total, 100) AS instrumento_amount_paid_brl,
  DIV(
    pix.pix_paid_interest + pix.pix_paid_fine,
    100
  ) AS instrumento_fine_and_interest_brl,
  DIV(
    pix.pix_paid_total
      - pix.pix_paid_interest
      - pix.pix_paid_fine,
    100
  ) AS instrumento_amount_paid_net_brl,
  billing.create_at IS NOT NULL AS possui_data_emissao
FROM tmp_charges AS charge
INNER JOIN tmp_billing_charge_relations AS relation
  ON relation.charge_id = charge.charge_id
INNER JOIN tmp_billings AS billing
  ON billing.billing_id = relation.billing_id
LEFT JOIN tmp_billing_pix_relations AS pix_relation
  ON pix_relation.billing_id = billing.billing_id
LEFT JOIN tmp_pix_payments AS pix
  ON pix.pix_id = pix_relation.pix_id;


-- ============================================================================
-- ETAPA 10 — TMP_PAYMENT_EVENTS
-- UNIÃO DAS DUAS RAMIFICAÇÕES DE INSTRUMENTO
--
-- O QUE FAZ
-- Empilha todas as linhas de boleto e todas as linhas de PIX.
--
-- POR QUE EXISTE
-- Permite que as etapas seguintes tratem os dois meios de pagamento com os
-- mesmos nomes de coluna.
--
-- ERRO REPRODUZIDO INTENCIONALMENTE
-- UNION ALL não elimina duplicidades. Como cada ramificação parte novamente do
-- mesmo charge × billing, o GMV e os créditos adicionados posteriormente são
-- repetidos pelo número de linhas desta união.
--
-- Este arquivo mantém o comportamento para provar a paridade. A versão
-- refatorada seleciona um instrumento antes de anexar métricas de outro grain.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_payment_events AS
SELECT *
FROM tmp_bank_slip_payment_events

UNION ALL

SELECT *
FROM tmp_pix_payment_events;


-- ============================================================================
-- DIAGNÓSTICO 02 — CONTAGEM ANTES E DEPOIS DO UNION ALL
--
-- O QUE MOSTRA
-- A quantidade de charge × billing antes dos instrumentos e a quantidade de
-- linhas produzida depois de boleto + PIX.
-- ============================================================================

-- SELECT
--   (SELECT COUNT(*) FROM tmp_billing_charge_relations)
--     AS relacionamentos_billing_charge,
--   (SELECT COUNT(*) FROM tmp_bank_slip_payment_events)
--     AS linhas_ramificacao_boleto,
--   (SELECT COUNT(*) FROM tmp_pix_payment_events)
--     AS linhas_ramificacao_pix,
--   (SELECT COUNT(*) FROM tmp_payment_events)
--     AS linhas_depois_union_all;


-- ============================================================================
-- ETAPA 11 — TMP_NORMALIZED_FINANCIAL_EVENTS
-- PADRONIZAÇÃO DA BASE FINANCEIRA
--
-- O QUE FAZ
-- Converte identificadores e datas para o vocabulário usado nas etapas de
-- pagamento e renomeia as medidas normalizadas de boleto/PIX.
--
-- POR QUE EXISTE
-- Entrega um único schema financeiro para o join com energy_clients.
--
-- GRAIN REAL
-- Ainda é charge × billing × linha produzida pela ramificação de instrumento.
-- Não é uma linha única por cobrança.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_normalized_financial_events AS
SELECT
  disco_consumer_unit_id AS numero_instalacao,
  SAFE_CAST(reference_month AS DATE) AS mes_referencia,
  charge_id AS identificador_cobranca,
  billing_id,
  SAFE_CAST(SUBSTR(billing_create_at, 1, 10) AS DATE) AS data_emissao,
  DATE_TRUNC(
    SAFE_CAST(SUBSTR(billing_create_at, 1, 10) AS DATE),
    MONTH
  ) AS mes_emissao,
  cancelled_at AS data_cancelamento,
  DATE_TRUNC(
    SAFE_CAST(SUBSTR(cancelled_at, 1, 10) AS DATE),
    MONTH
  ) AS mes_cancelamento,
  cancellation_reason AS motivo_cancelamento,
  billing_due_date AS data_vencimento,
  DATE_TRUNC(SAFE_CAST(billing_due_date AS DATE), MONTH) AS mes_vencimento,
  SAFE_CAST(payment_date AS DATE) AS data_liquidacao,
  DATE_TRUNC(SAFE_CAST(payment_date AS DATE), MONTH) AS mes_liquidacao,
  charge_amount_brl AS valor_emitido_brl,
  instrumento_amount_paid_brl AS valor_liquidado_brl,
  instrumento_fine_and_interest_brl AS multa_juros_recebido_brl,
  instrumento_amount_paid_net_brl AS valor_liquidado_ex_multa_juros_brl,
  charge_status AS payment_status,
  payment_date,
  possui_data_emissao
FROM tmp_payment_events;


-- ============================================================================
-- ETAPA 12 — TMP_CLIENT_ENERGY_ALLOCATIONS
-- CLIENTES, GERADORES, USINAS, GMV E CRÉDITOS
--
-- O QUE REPRESENTA
-- A alocação mensal de uma instalação a uma usina e a um gerador.
--
-- POR QUE EXISTE
-- É a origem de gerador, usina, disco, gmv_gerador_brl e créditos. Esses campos
-- não existem na base financeira.
--
-- CHAVE DE JUNÇÃO COM O FINANCEIRO
-- numero_instalacao + mes_referencia.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_client_energy_allocations AS
SELECT
  SAFE_CAST(mes_referencia AS DATE) AS mes_referencia,
  numero_instalacao,
  usina,
  gerador,
  disco,
  creditos_faturados_k_wh,
  gmv_real_oficial_brl,
  gmv_gerador_brl,
  take_rate_lemon_brl,
  saldo_bop_k_wh,
  creditos_recebidos_no_mes_k_wh,
  creditos_recebidos_de_meses_anteriores_k_wh,
  saldo_eop_k_wh,
  churn_k_wh,
  desconto_gerador_percentage,
  tarifa_de_saida_brl_per_k_wh,
  pis_per_cofins_nao_compensado_lemon_brl_k_wh,
  icms_nao_compensado_lemon_brl_per_k_wh,
  ajuste_custo_disp_gerador_brl,
  desconto_gerador_brl_per_k_wh,
  etapa,
  status,
  excecoes
FROM `lemon-ae-case.raw.energy_clients`;


-- ============================================================================
-- ETAPA 13 — TMP_FINANCIAL_EVENTS_ENRICHED_WITH_CLIENTS
-- BASE FINANCEIRA ENRIQUECIDA COM CLIENTE E GMV
--
-- O QUE FAZ
-- Junta cada linha financeira à instalação da mesma competência.
--
-- POR QUE EXISTE
-- Coloca no mesmo registro a emissão/pagamento financeiro e o GMV/créditos do
-- cliente, permitindo as flags e agregações seguintes.
--
-- PONTO CRÍTICO
-- O gmv_gerador_brl está no grain instalação × mês. Como full_finance já pode
-- possuir várias linhas para o mesmo billing, o GMV é copiado em todas elas.
-- A multiplicação torna-se monetária quando o SUM é executado mais adiante.
--
-- CÁLCULO ORIGINAL PRESERVADO
-- valor_liquidado_gerador_brl é calculado proporcionalmente, mas a view original
-- não usa esse campo em valor_liquidado_gerador_mes; ela volta a somar o GMV.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_financial_events_enriched_with_clients AS
SELECT
  financial_event.*,
  client.* EXCEPT (numero_instalacao, mes_referencia),
  DIV(
    financial_event.valor_liquidado_ex_multa_juros_brl,
    NULLIF(financial_event.valor_emitido_brl, 0)
  ) * client.gmv_gerador_brl AS valor_liquidado_gerador_brl,
  DIV(
    financial_event.valor_liquidado_ex_multa_juros_brl,
    NULLIF(financial_event.valor_emitido_brl, 0)
  ) + financial_event.multa_juros_recebido_brl
    AS liquidado_gerador_multas_juros,
  MIN(financial_event.data_vencimento) OVER (
    PARTITION BY financial_event.numero_instalacao, financial_event.mes_referencia
  ) AS min_data_vencimento,
  MAX(financial_event.data_liquidacao) OVER (
    PARTITION BY financial_event.numero_instalacao, financial_event.mes_referencia
  ) AS max_data_liquidacao
FROM tmp_normalized_financial_events AS financial_event
INNER JOIN tmp_client_energy_allocations AS client
  USING (numero_instalacao, mes_referencia);


-- ============================================================================
-- ETAPA 14 — TMP_ELIGIBLE_FINANCIAL_EVENTS
-- RECORTE FINANCEIRO ACEITO PELO RELATÓRIO
--
-- O QUE FAZ
-- Seleciona somente os campos necessários às flags e remove cobranças com
-- status fora de waitingPayment e paid.
--
-- POR QUE EXISTE
-- Define a população financeira que pode contribuir para as métricas finais.
--
-- PONTO DE ATENÇÃO
-- O status de billing, o status de take rate e os campos etapa/status/excecoes
-- de clients não são usados para filtrar o resultado final.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_eligible_financial_events AS
SELECT
  usina,
  TRIM(gerador) AS gerador,
  disco,
  numero_instalacao AS n_de_instalacao,
  mes_referencia,
  identificador_cobranca,
  billing_id,
  mes_emissao,
  mes_liquidacao,
  gmv_gerador_brl,
  valor_liquidado_gerador_brl,
  valor_liquidado_ex_multa_juros_brl,
  multa_juros_recebido_brl,
  creditos_faturados_k_wh,
  possui_data_emissao
FROM tmp_financial_events_enriched_with_clients
WHERE
  numero_instalacao IS NOT NULL
  AND payment_status IN ('waitingPayment', 'paid');


-- ============================================================================
-- DIAGNÓSTICO DO FANOUT DE GMV — VERSÃO DESMEMBRADA
-- ============================================================================


-- ============================================================================
-- ETAPA 01 — COBRANÇA ASSOCIADA AO BILLING
--
-- PARTE DE:
--   tmp_charges
--
-- INNER JOIN:
--   tmp_billing_charge_relations
--
-- OBJETIVO:
-- Descobrir a qual billing cada cobrança está relacionada.
--
-- FILTRO:
-- Mantém somente cobranças que podem participar do relatório original.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE
  tmp_diagnostic_eligible_charge_relations AS

SELECT
  charge.charge_id,
  charge.reference_month,
  charge.disco_consumer_unit_id,
  relation.billing_id
FROM tmp_charges AS charge
INNER JOIN tmp_billing_charge_relations AS relation
  ON relation.charge_id = charge.charge_id
WHERE
  charge.status IN ('waitingPayment', 'paid');


-- Consulta opcional para inspecionar a primeira etapa.
-- SELECT
--   *
-- FROM tmp_diagnostic_eligible_charge_relations
-- ORDER BY
--   billing_id,
--   charge_id
-- LIMIT 100;


-- ============================================================================
-- ETAPA 02 — COBRANÇA ASSOCIADA A UM BILLING EMITIDO
--
-- PARTE DE:
--   tmp_diagnostic_eligible_charge_relations
--
-- INNER JOIN:
--   tmp_billings
--
-- OBJETIVO:
-- Confirmar que o billing relacionado existe e possui data de emissão.
--
-- FILTRO:
-- billing.create_at IS NOT NULL reproduz a mesma condição da implementação
-- original.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE
  tmp_diagnostic_emitted_charge_billings AS

SELECT
  source_record.charge_id,
  source_record.reference_month,
  source_record.disco_consumer_unit_id,
  billing.billing_id
FROM tmp_diagnostic_eligible_charge_relations AS source_record
INNER JOIN tmp_billings AS billing
  ON billing.billing_id = source_record.billing_id
WHERE
  billing.create_at IS NOT NULL;


-- Consulta opcional para inspecionar a segunda etapa.
-- SELECT
--   *
-- FROM tmp_diagnostic_emitted_charge_billings
-- ORDER BY
--   billing_id,
--   charge_id
-- LIMIT 100;


-- ============================================================================
-- ETAPA 03 — BASE SEM BOLETO OU PIX
--
-- PARTE DE:
--   tmp_diagnostic_emitted_charge_billings
--
-- INNER JOIN:
--   tmp_client_energy_allocations
--
-- CHAVES:
--   numero_instalacao
--   mes_referencia
--
-- OBJETIVO:
-- Associar cada charge × billing ao cliente, gerador, usina, distribuidora
-- e GMV da instalação.
--
-- POR QUE É "SEM INSTRUMENTO":
-- Até este ponto não ocorreu nenhum JOIN com boleto ou PIX. Portanto, o GMV
-- ainda não foi repetido pela quantidade de instrumentos de payment.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE
  tmp_diagnostic_gmv_before_payment_instruments AS

SELECT
  client.gerador,
  client.usina,
  client.disco,
  client.numero_instalacao,
  client.mes_referencia,
  client.gmv_gerador_brl,
  source_record.charge_id,
  source_record.billing_id
FROM tmp_diagnostic_emitted_charge_billings AS source_record
INNER JOIN tmp_client_energy_allocations AS client
  ON client.numero_instalacao = source_record.disco_consumer_unit_id
  AND client.mes_referencia =
    SAFE_CAST(source_record.reference_month AS DATE);


-- Consulta opcional para visualizar o GMV antes do fanout.
-- SELECT
--   *
-- FROM tmp_diagnostic_gmv_before_payment_instruments
-- ORDER BY
--   gerador,
--   usina,
--   numero_instalacao,
--   billing_id
-- LIMIT 100;


-- ============================================================================
-- ETAPA 04 — APLICAÇÃO DA MULTIPLICIDADE DA LÓGICA ORIGINAL
--
-- PARTE DE:
--   tmp_diagnostic_gmv_before_payment_instruments
--
-- INNER JOIN:
--   tmp_diagnostic_payment_instrument_counts
--
-- CHAVES:
--   billing_id
--   charge_id
--
-- OBJETIVO:
-- Acrescentar a quantidade de boletos, PIX e linhas produzidas pelo pipeline
-- original para cada charge × billing.
--
-- CÁLCULO:
-- gmv_apos_fanout_legado =
--   gmv_gerador_brl × quantidade_linhas_produzidas_no_legado
-- ============================================================================

CREATE OR REPLACE TEMP TABLE
  tmp_diagnostic_gmv_fanout_impact AS

SELECT
  base.*,
  diagnostic.quantidade_boletos,
  diagnostic.quantidade_pixs,
  diagnostic.quantidade_linhas_produzidas_no_legado,
  base.gmv_gerador_brl
    * diagnostic.quantidade_linhas_produzidas_no_legado
      AS gmv_apos_fanout_legado
FROM tmp_diagnostic_gmv_before_payment_instruments AS base
INNER JOIN tmp_diagnostic_payment_instrument_counts AS diagnostic
  USING (billing_id, charge_id);


-- Consulta opcional para visualizar o cálculo linha a linha.
-- SELECT
--   *
-- FROM tmp_diagnostic_gmv_fanout_impact
-- ORDER BY
--   quantidade_linhas_produzidas_no_legado DESC,
--   gerador,
--   usina
-- LIMIT 100;


-- ============================================================================
-- RESULTADO 01 — IMPACTO AGREGADO DO FANOUT
--
-- Compara o GMV no grain charge × billing com o GMV reproduzido depois de
-- considerar a quantidade de linhas geradas pelos instrumentos.
-- ============================================================================

-- SELECT
--   gerador,
--   usina,
--   mes_referencia,
--   COUNT(*) AS quantidade_charge_billings,
--   SUM(gmv_gerador_brl) AS cobranca_sem_fanout,
--   SUM(gmv_apos_fanout_legado) AS cobranca_com_fanout_legado,
--   SUM(gmv_apos_fanout_legado) - SUM(gmv_gerador_brl)
--     AS diferenca_causada_pelo_fanout
-- FROM tmp_diagnostic_gmv_fanout_impact
-- GROUP BY
--   gerador,
--   usina,
--   mes_referencia
-- HAVING
--   diferenca_causada_pelo_fanout != 0
-- ORDER BY
--   ABS(diferenca_causada_pelo_fanout) DESC;


-- ============================================================================
-- RESULTADO 02 — CASOS COM MAIOR MULTIPLICIDADE
--
-- Exibe casos como:
--   2 boletos + 2 PIX → 4 linhas;
--   3 boletos + 3 PIX → 6 linhas.
-- ============================================================================

-- SELECT
--   gerador,
--   usina,
--   numero_instalacao,
--   billing_id,
--   gmv_gerador_brl,
--   quantidade_boletos,
--   quantidade_pixs,
--   quantidade_linhas_produzidas_no_legado,
--   gmv_apos_fanout_legado
-- FROM tmp_diagnostic_gmv_fanout_impact
-- WHERE
--   quantidade_linhas_produzidas_no_legado > 2
-- ORDER BY
--   quantidade_linhas_produzidas_no_legado DESC,
--   gerador,
--   usina;


-- ============================================================================
-- ETAPA 15 — TMP_REPORTING_CALENDAR
-- CALENDÁRIO RELATIVO DO RELATÓRIO
--
-- O QUE FAZ
-- Para cada competência financeira disponível, cria o mês de corte e os meses
-- relativos usados pelas flags.
--
-- REGRA ORIGINAL PRESERVADA
-- mes_referencia_report = mes_corte - 2 meses.
-- Assim, corte março/2025 produz relatório janeiro/2025.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_reporting_calendar AS
SELECT
  mes_referencia AS mes_corte,
  DATE_SUB(mes_referencia, INTERVAL 1 MONTH) AS mes_corte_report_anterior,
  DATE_SUB(mes_referencia, INTERVAL 2 MONTH) AS mes_referencia_report,
  DATE_SUB(mes_referencia, INTERVAL 3 MONTH)
    AS mes_referencia_report_anterior
FROM (
  SELECT DISTINCT
    mes_referencia
  FROM tmp_eligible_financial_events
);


-- ============================================================================
-- ETAPA 16 — TMP_PAYMENT_TIMING_FLAGS
-- EXPANSÃO TEMPORAL E FLAGS DE EMISSÃO/LIQUIDAÇÃO
--
-- O QUE FAZ
-- Cruza todas as linhas financeiras com os meses do calendário e classifica se
-- cada linha pertence ao mês do relatório ou a competências anteriores.
--
-- POR QUE EXISTE
-- As métricas seguintes são somas condicionais controladas por estas flags.
--
-- COMPORTAMENTO DE PARIDADE
-- flag_emitido_do_mes usa possui_data_emissao, e
-- flag_emitido_meses_anteriores é sempre FALSE. Isso reproduz o efeito do cast
-- de data defeituoso executado pela view original no SQLite.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_payment_timing_flags AS
SELECT
  payment.usina,
  payment.gerador,
  payment.disco,
  payment.n_de_instalacao,
  payment.mes_referencia,
  calendar.mes_referencia_report,
  payment.gmv_gerador_brl,
  payment.valor_liquidado_gerador_brl,
  payment.valor_liquidado_ex_multa_juros_brl,
  payment.multa_juros_recebido_brl,
  payment.creditos_faturados_k_wh,
  payment.mes_liquidacao,
  calendar.mes_corte,
  payment.mes_referencia = calendar.mes_referencia_report
    AS flag_do_mes,
  payment.mes_referencia < calendar.mes_referencia_report
    AS flag_meses_anteriores,
  payment.mes_referencia = calendar.mes_referencia_report
    AND payment.possui_data_emissao
      AS flag_emitido_do_mes,
  payment.mes_referencia = calendar.mes_referencia_report
    AND payment.mes_liquidacao < calendar.mes_corte
      AS flag_liquidado_do_mes,
  FALSE AS flag_emitido_meses_anteriores,
  payment.mes_referencia < calendar.mes_referencia_report
    AND payment.mes_liquidacao = calendar.mes_corte_report_anterior
      AS flag_liquidado_meses_anteriores
FROM tmp_eligible_financial_events AS payment
CROSS JOIN tmp_reporting_calendar AS calendar
WHERE
  payment.mes_referencia <= calendar.mes_referencia_report;


-- ============================================================================
-- ETAPA 17 — TMP_MONTHLY_SETTLEMENT_AGGREGATES
-- AGREGAÇÕES FINANCEIRAS POR GERADOR, USINA, DISCO E MÊS
--
-- O QUE FAZ
-- Converte as flags em métricas por meio de SUM(IF(...)).
--
-- PONTO ONDE O FANOUT SE TORNA UM VALOR INCORRETO
-- As linhas já foram multiplicadas em boleto + PIX. Ao somar gmv_gerador_brl e
-- creditos_faturados_k_wh, o SQL contabiliza essas medidas uma vez por linha de
-- instrumento, embora elas pertençam ao grain instalação × competência.
--
-- EXEMPLO
-- Um billing com 2 boletos e 2 PIX gera 4 linhas e soma o mesmo GMV 4 vezes.
-- Um billing com 3 boletos e 3 PIX gera 6 linhas e soma o mesmo GMV 6 vezes.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_monthly_settlement_aggregates AS
SELECT
  usina,
  gerador,
  disco,
  mes_referencia_report,
  SUM(IF(flag_emitido_do_mes, gmv_gerador_brl, 0))
    AS cobranca_gerador_mes,
  SUM(IF(flag_emitido_meses_anteriores, gmv_gerador_brl, 0))
    AS cobranca_gerador_meses_anteriores,
  SUM(IF(flag_liquidado_do_mes, gmv_gerador_brl, 0))
    AS valor_liquidado_gerador_mes,
  SUM(IF(flag_liquidado_meses_anteriores, gmv_gerador_brl, 0))
    AS valor_liquidado_gerador_meses_anteriores,
  SUM(IF(flag_liquidado_do_mes, valor_liquidado_ex_multa_juros_brl, 0))
    AS valor_liquidado_ex_multa_juros_mes,
  SUM(
    IF(
      flag_liquidado_meses_anteriores,
      valor_liquidado_ex_multa_juros_brl,
      0
    )
  ) AS valor_liquidado_ex_multa_juros_meses_anteriores,
  SUM(IF(flag_liquidado_do_mes, multa_juros_recebido_brl, 0))
    AS multa_juros_total_recebido_mes,
  SUM(
    IF(
      flag_liquidado_meses_anteriores,
      multa_juros_recebido_brl,
      0
    )
  ) AS multa_juros_total_recebido_meses_anteriores,
  SUM(IF(flag_liquidado_do_mes, creditos_faturados_k_wh, 0))
    AS creditos_faturados_liquidados_mes,
  SUM(
    IF(
      flag_liquidado_meses_anteriores,
      creditos_faturados_k_wh,
      0
    )
  ) AS creditos_faturados_liquidados_meses_anteriores
FROM tmp_payment_timing_flags
GROUP BY
  usina,
  gerador,
  disco,
  mes_referencia_report;


-- ============================================================================
-- ETAPA 18 — TMP_MONTHLY_REVENUE_METRICS
-- RECEITAS DERIVADAS DAS AGREGAÇÕES FINANCEIRAS
--
-- O QUE FAZ
-- Soma as parcelas do mês e de meses anteriores para produzir receita bruta,
-- receita efetivamente paga e receita de multas.
--
-- HERANÇA DE QUALIDADE
-- As métricas herdam qualquer multiplicação ocorrida antes da agregação.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_monthly_revenue_metrics AS
SELECT
  gerador,
  usina,
  disco,
  mes_referencia_report AS mes_referencia,
  cobranca_gerador_mes,
  cobranca_gerador_meses_anteriores,
  valor_liquidado_gerador_mes,
  valor_liquidado_gerador_meses_anteriores,
  valor_liquidado_gerador_mes
    + valor_liquidado_gerador_meses_anteriores
      AS receita_bruta_gerador_brl,
  valor_liquidado_ex_multa_juros_mes,
  valor_liquidado_ex_multa_juros_meses_anteriores,
  valor_liquidado_ex_multa_juros_mes
    + valor_liquidado_ex_multa_juros_meses_anteriores
      AS receita_bruta_real_brl,
  multa_juros_total_recebido_mes,
  multa_juros_total_recebido_meses_anteriores,
  multa_juros_total_recebido_mes
    + multa_juros_total_recebido_meses_anteriores
      AS receita_multas_brl
FROM tmp_monthly_settlement_aggregates;


-- ============================================================================
-- ETAPA 19 — TMP_FARM_GENERATION_METRICS
-- GERAÇÃO, INJEÇÃO E LIMITE DE ENERGIA ELEGÍVEL
--
-- O QUE FAZ
-- Extrai dados físicos da usina e calcula a menor medida entre créditos
-- injetados e geração prevista.
--
-- POR QUE EXISTE
-- minima_injecao_k_wh será o denominador de desempenho_lemon.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_farm_generation_metrics AS
SELECT
  gerador,
  usina,
  disco,
  SAFE_CAST(mes_referencia AS DATE) AS mes_referencia,
  creditos_injetados_k_wh,
  geracao_prevista_no_contrato_k_wh,
  geracao_realizada_gerador_k_wh,
  LEAST(
    creditos_injetados_k_wh,
    geracao_prevista_no_contrato_k_wh
  ) AS minima_injecao_k_wh
FROM `lemon-ae-case.raw.energy_farms`;


-- ============================================================================
-- ETAPA 20 — TMP_FARM_CLIENT_CREDIT_METRICS
-- CRÉDITOS AGREGADOS POR USINA E MÊS
--
-- O QUE FAZ
-- Soma créditos recebidos e faturados de todas as instalações da mesma usina.
--
-- POR QUE EXISTE
-- Fornece medidas energéticas intermediárias do cálculo de performance.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_farm_client_credit_metrics AS
SELECT
  usina,
  SAFE_CAST(mes_referencia AS DATE) AS mes_referencia,
  SUM(creditos_recebidos_no_mes_k_wh) AS creditos_recebidos_k_wh,
  SUM(creditos_faturados_k_wh) AS creditos_faturados_k_wh
FROM `lemon-ae-case.raw.energy_clients`
GROUP BY 1, 2;


-- ============================================================================
-- ETAPA 21 — TMP_FARM_PAID_CREDIT_METRICS
-- CRÉDITOS FATURADOS CONSIDERADOS PAGOS
--
-- O QUE FAZ
-- Soma os créditos das liquidações do mês e de meses anteriores.
--
-- POR QUE EXISTE
-- O resultado será o numerador de desempenho_lemon.
--
-- HERANÇA DE QUALIDADE
-- Como esses créditos foram agregados depois do fanout, também podem estar
-- multiplicados por boleto/PIX.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_farm_paid_credit_metrics AS
SELECT
  usina,
  gerador,
  disco,
  mes_referencia_report AS mes_referencia,
  creditos_faturados_liquidados_mes
    + creditos_faturados_liquidados_meses_anteriores
      AS creditos_faturados_pagos_kwh
FROM tmp_monthly_settlement_aggregates;


-- ============================================================================
-- ETAPA 22 — TMP_TAKE_RATE_REPORTING_MONTHS
-- MESES FIXOS USADOS PARA EXPANDIR A AGENDA DE TAKE RATE
--
-- O QUE FAZ
-- Reproduz os três meses codificados diretamente na view original.
--
-- PROBLEMA CONHECIDO
-- A lista não avança automaticamente para novos períodos.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_take_rate_reporting_months AS
SELECT DATE '2025-01-01' AS mes_referencia
UNION ALL
SELECT DATE '2025-02-01'
UNION ALL
SELECT DATE '2025-03-01';


-- ============================================================================
-- ETAPA 23 — TMP_MONTHLY_TAKE_RATE_BANDS
-- EXPANSÃO TEMPORAL DAS FAIXAS DE TAKE RATE
--
-- O QUE FAZ
-- Replica cada configuração de take rate para os meses fixos que estiverem
-- entre data_inicio e data_final.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_monthly_take_rate_bands AS
SELECT
  calendar.mes_referencia,
  take_rate_band.*
FROM `lemon-ae-case.raw.energy_generator_take_rates` AS take_rate_band
INNER JOIN tmp_take_rate_reporting_months AS calendar
  ON SAFE_CAST(take_rate_band.data_inicio AS DATE) <= calendar.mes_referencia
  AND SAFE_CAST(take_rate_band.data_final AS DATE) >= calendar.mes_referencia;


-- ============================================================================
-- ETAPA 24 — TMP_TAKE_RATE_BAND_LOOKUP
-- CAMPOS NECESSÁRIOS PARA O LOOKUP DA FAIXA
--
-- O QUE FAZ
-- Seleciona gerador, distribuidora, mês, limites de desempenho e percentual.
--
-- PONTO DE ATENÇÃO
-- O status da agenda não é utilizado pela implementação original.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_take_rate_band_lookup AS
SELECT
  mes_referencia,
  id_gerador,
  id_tr,
  gerador,
  disco,
  desempenho_min,
  desempenho_max,
  tr_percentual
FROM tmp_monthly_take_rate_bands;


-- ============================================================================
-- ETAPA 25 — TMP_FARM_PERFORMANCE_METRICS
-- INDICADORES ENERGÉTICOS E DESEMPENHO DA LEMON
--
-- O QUE FAZ
-- Junta geração, créditos de clientes e créditos considerados pagos por usina
-- e mês; depois calcula razões de performance.
--
-- CÁLCULO USADO NO RESULTADO FINAL
-- desempenho_lemon = creditos_faturados_pagos_kwh / minima_injecao_k_wh.
--
-- HERANÇA DE QUALIDADE
-- O numerador pode estar inflado pelo fanout financial_event.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_farm_performance_metrics AS
SELECT
  farm.gerador,
  farm.usina,
  farm.disco,
  CONCAT(farm.gerador, '_', farm.disco) AS id_tr,
  farm.mes_referencia,
  farm.creditos_injetados_k_wh,
  farm.geracao_prevista_no_contrato_k_wh,
  farm.geracao_realizada_gerador_k_wh,
  client.creditos_recebidos_k_wh,
  client.creditos_faturados_k_wh,
  settlement.creditos_faturados_pagos_kwh,
  farm.creditos_injetados_k_wh
    / NULLIF(farm.geracao_prevista_no_contrato_k_wh, 0)
      AS injetado_vs_previsto,
  farm.creditos_injetados_k_wh
    / NULLIF(farm.geracao_realizada_gerador_k_wh, 0)
      AS disco_vs_inversor,
  client.creditos_recebidos_k_wh
    / NULLIF(farm.creditos_injetados_k_wh, 0)
      AS recebidos_vs_injetados,
  client.creditos_faturados_k_wh
    / NULLIF(client.creditos_recebidos_k_wh, 0)
      AS faturados_vs_recebidos,
  client.creditos_faturados_k_wh
    / NULLIF(farm.minima_injecao_k_wh, 0)
      AS preenchimento_usina,
  settlement.creditos_faturados_pagos_kwh
    / NULLIF(farm.minima_injecao_k_wh, 0)
      AS desempenho_lemon
FROM tmp_farm_generation_metrics AS farm
LEFT JOIN tmp_farm_client_credit_metrics AS client
  ON client.usina = farm.usina
  AND client.mes_referencia = farm.mes_referencia
LEFT JOIN tmp_farm_paid_credit_metrics AS settlement
  ON settlement.usina = farm.usina
  AND settlement.mes_referencia = farm.mes_referencia
WHERE
  farm.mes_referencia <= DATE '2025-03-01';


-- ============================================================================
-- ETAPA 26 — TMP_PERFORMANCE_TAKE_RATE_MATCH
-- SELEÇÃO DO TAKE RATE POR FAIXA
--
-- O QUE FAZ
-- Relaciona desempenho à agenda vigente e mantém a faixa em que:
-- desempenho_min <= desempenho_lemon < desempenho_max.
--
-- RESULTADO
-- tr_percentual é renomeado como tr_performado.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_performance_take_rate_match AS
SELECT
  performance.*,
  take_rate.tr_percentual AS tr_performado
FROM tmp_farm_performance_metrics AS performance
LEFT JOIN tmp_take_rate_band_lookup AS take_rate
  USING (gerador, disco, mes_referencia)
WHERE
  COALESCE(performance.desempenho_lemon, 0) >= take_rate.desempenho_min
  AND COALESCE(performance.desempenho_lemon, 0) < take_rate.desempenho_max;


-- ============================================================================
-- ETAPA 27 — TMP_SELECTED_PERFORMANCE_METRICS
-- RECORTE FINAL DO DESEMPENHO
--
-- O QUE FAZ
-- Mantém somente as chaves necessárias para enriquecer a base financeira.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_selected_performance_metrics AS
SELECT
  usina,
  mes_referencia,
  desempenho_lemon,
  tr_performado
FROM tmp_performance_take_rate_match;


-- ============================================================================
-- ETAPA 28 — TMP_MONTHLY_FARM_TUSD
-- TUSD AGREGADA POR USINA E MÊS DE DESCONTO
--
-- O QUE FAZ
-- Soma a TUSD descontada e usa mes_de_desconto_tusd_gerador como o mês que será
-- relacionado ao relatório.
--
-- REGRA FIXA ORIGINAL PRESERVADA
-- A fonte é filtrada por mes_referencia = '2025-01-01'.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_monthly_farm_tusd AS
SELECT
  usina,
  SAFE_CAST(mes_de_desconto_tusd_gerador AS DATE) AS mes_referencia,
  SUM(tusd_descontada_gerador) AS tusd_descontada_gerador
FROM `lemon-ae-case.raw.energy_farms`
WHERE
  mes_referencia = '2025-01-01'
GROUP BY 1, 2;


-- ============================================================================
-- ETAPA 29 — TMP_REPORT_ENRICHED_BASE
-- ENCONTRO ENTRE TUSD, LIQUIDAÇÕES E DESEMPENHO
--
-- O QUE FAZ
-- Parte da TUSD e procura liquidação e desempenho para a mesma usina e mês.
--
-- CONSEQUÊNCIA DO DRIVER
-- Como a base começa em TUSD, somente usinas presentes nesse recorte podem
-- chegar ao resultado. O filtro final gerador IS NOT NULL transforma, na
-- prática, a relação com liquidações em uma interseção obrigatória.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_report_enriched_base AS
SELECT
  settlement.*,
  tusd.tusd_descontada_gerador,
  performance.desempenho_lemon,
  performance.tr_performado
FROM tmp_monthly_farm_tusd AS tusd
LEFT JOIN tmp_monthly_revenue_metrics AS settlement
  USING (usina, mes_referencia)
LEFT JOIN tmp_selected_performance_metrics AS performance
  USING (usina, mes_referencia);


-- ============================================================================
-- ETAPA 30 — TMP_FINAL_RESULT
-- RESULTADO FINAL DA RECONSTRUÇÃO TEMPORÁRIA
--
-- O QUE FAZ
-- Seleciona as 22 colunas da generator_report e calcula os repasses finais.
--
-- IMPORTANTE
-- Esta temporária reproduz intencionalmente o fanout e as demais regras da
-- versão de paridade com a lógica original. Ela é um artefato de diagnóstico,
-- não a proposta de
-- produto de dados corrigido.
-- ============================================================================

CREATE OR REPLACE TEMP TABLE tmp_final_result AS
SELECT
  gerador,
  usina,
  disco,
  mes_referencia,
  cobranca_gerador_mes,
  cobranca_gerador_meses_anteriores,
  valor_liquidado_gerador_mes,
  valor_liquidado_gerador_meses_anteriores,
  valor_liquidado_ex_multa_juros_mes,
  valor_liquidado_ex_multa_juros_meses_anteriores,
  multa_juros_total_recebido_mes,
  multa_juros_total_recebido_meses_anteriores,
  receita_bruta_gerador_brl,
  receita_multas_brl,
  desempenho_lemon,
  tr_performado,
  receita_bruta_gerador_brl * (1 - tr_performado)
    AS repasse_pre_tusd_gerador,
  tusd_descontada_gerador,
  receita_bruta_gerador_brl * (1 - tr_performado)
    - tusd_descontada_gerador AS repasse_gerador,
  receita_multas_brl * tr_performado AS repasse_multas_lemon,
  receita_multas_brl * (1 - tr_performado) AS repasse_multas_gerador,
  receita_bruta_gerador_brl * tr_performado AS repasse_lemon
FROM tmp_report_enriched_base
WHERE
  gerador IS NOT NULL;


-- ============================================================================
-- RESULTADO
-- Exibe a reconstrução final com temporárias.
-- ============================================================================

-- SELECT
--   *
-- FROM tmp_final_result
-- ORDER BY
--   gerador,
--   usina,
--   mes_referencia;


CREATE OR REPLACE TABLE
  `lemon-ae-case.validation.generator_report_formatado_em_temp_tables_result`
AS
SELECT
  *
FROM tmp_final_result;

CREATE OR REPLACE VIEW
  `lemon-ae-case.validation.generator_report_formatado_em_temp_tables`
AS
SELECT
  *
FROM `lemon-ae-case.validation.generator_report_formatado_em_temp_tables_result`;

-- ============================================================================
-- RECONCILIAÇÃO OPCIONAL COM A VIEW PERSISTENTE
--
-- Se as duas consultas abaixo não retornarem linhas, o conjunto temporário e a
-- view de paridade possuem os mesmos registros no nível de comparação exata.
-- ============================================================================

-- SELECT
--   'TEMP_MENOS_VIEW' AS origem_diferenca,
--   diferenca.*
-- FROM (
--   SELECT * FROM tmp_final_result
--   EXCEPT DISTINCT
--   SELECT *
--   FROM `lemon-ae-case.validation.generator_report_legacy_parity`
-- ) AS diferenca

-- UNION ALL

-- SELECT
--   'VIEW_MENOS_TEMP' AS origem_diferenca,
--   diferenca.*
-- FROM (
--   SELECT *
--   FROM `lemon-ae-case.validation.generator_report_legacy_parity`
--   EXCEPT DISTINCT
--   SELECT * FROM tmp_final_result
-- ) AS diferenca;
