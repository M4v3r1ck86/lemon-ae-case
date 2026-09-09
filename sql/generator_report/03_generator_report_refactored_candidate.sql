-- BigQuery / GoogleSQL
-- Versao refatorada e tecnicamente corrigida do generator_report.
--
-- Esta view e uma candidata de validacao. Ela nao deve substituir a versao
-- legada antes da reconciliacao dos resultados e da aprovacao das regras.

CREATE OR REPLACE VIEW
  `lemon-ae-case.validation.generator_report_refactored_candidate`
AS
WITH
  params AS (
    SELECT
      DATE '2025-01-01' AS mes_referencia_relatorio,
      DATE '2025-03-01' AS mes_corte,
      DATE '2025-02-01' AS mes_corte_anterior,
      DATE '2025-01-01' AS mes_fonte_tusd
  ),

  billings AS (
    SELECT
      source AS billing_id,
      SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), NUMERIC '100')
        AS valor_billing_brl,
      billing_energy_farm_id,
      status AS billing_status,
      SAFE_CAST(create_at AS TIMESTAMP) AS criado_em,
      SAFE_CAST(due_date AS DATE) AS data_vencimento
    FROM `lemon-ae-case.raw.finance_billings`
  ),

  charges AS (
    SELECT
      source AS charge_id,
      SAFE_CAST(reference_month AS DATE) AS mes_referencia,
      disco_consumer_unit_id AS numero_instalacao,
      SAFE_CAST(payment_date AS DATE) AS data_liquidacao,
      status AS payment_status,
      SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), NUMERIC '100')
        AS valor_emitido_brl,
      cancelled_at,
      cancellation_reason
    FROM `lemon-ae-case.raw.finance_charges`
  ),

  billing_charge_relations AS (
    SELECT
      source AS billing_id,
      target AS charge_id
    FROM `lemon-ae-case.raw.finance_relations`
    WHERE
      source LIKE 'billing#%'
      AND target LIKE 'charge#%'
  ),

  -- Normaliza boleto e PIX em uma unica entidade de instrumento de pagamento.
  payment_instrument_candidates AS (
    SELECT
      relation.source AS billing_id,
      boleto.source AS instrumento_id,
      'boleto' AS tipo_instrumento,
      boleto.status AS instrumento_status,
      SAFE_CAST(boleto.create_at AS TIMESTAMP) AS instrumento_criado_em,
      SAFE_CAST(boleto.payment_date AS DATE) AS instrumento_data_pagamento,
      SAFE_DIVIDE(SAFE_CAST(boleto.amount AS NUMERIC), NUMERIC '100')
        AS instrumento_amount_brl,
      SAFE_DIVIDE(
        SAFE_CAST(boleto.bank_slip_paid_total AS NUMERIC),
        NUMERIC '100'
      ) AS instrumento_amount_paid_brl,
      SAFE_DIVIDE(
        SAFE_CAST(
          COALESCE(boleto.bank_slip_paid_interest, 0)
            + COALESCE(boleto.bank_slip_paid_fine, 0)
          AS NUMERIC
        ),
        NUMERIC '100'
      ) AS instrumento_fine_and_interest_brl,
      SAFE_DIVIDE(
        SAFE_CAST(boleto.bank_slip_paid_total AS NUMERIC)
          - SAFE_CAST(COALESCE(boleto.bank_slip_paid_interest, 0) AS NUMERIC)
          - SAFE_CAST(COALESCE(boleto.bank_slip_paid_fine, 0) AS NUMERIC),
        NUMERIC '100'
      ) AS instrumento_amount_paid_net_brl,
      boleto._ingested_at
    FROM `lemon-ae-case.raw.finance_relations` AS relation
    INNER JOIN `lemon-ae-case.raw.finance_boletos` AS boleto
      ON boleto.source = relation.target
    WHERE
      relation.source LIKE 'billing#%'
      AND relation.target LIKE 'boleto#%'

    UNION ALL

    SELECT
      relation.source AS billing_id,
      pix.source AS instrumento_id,
      'pix' AS tipo_instrumento,
      pix.status AS instrumento_status,
      SAFE_CAST(pix.create_at AS TIMESTAMP) AS instrumento_criado_em,
      SAFE_CAST(pix.payment_date AS DATE) AS instrumento_data_pagamento,
      SAFE_DIVIDE(SAFE_CAST(pix.amount AS NUMERIC), NUMERIC '100')
        AS instrumento_amount_brl,
      SAFE_DIVIDE(
        SAFE_CAST(pix.pix_paid_total AS NUMERIC),
        NUMERIC '100'
      ) AS instrumento_amount_paid_brl,
      SAFE_DIVIDE(
        SAFE_CAST(
          COALESCE(pix.pix_paid_interest, 0)
            + COALESCE(pix.pix_paid_fine, 0)
          AS NUMERIC
        ),
        NUMERIC '100'
      ) AS instrumento_fine_and_interest_brl,
      SAFE_DIVIDE(
        SAFE_CAST(pix.pix_paid_total AS NUMERIC)
          - SAFE_CAST(COALESCE(pix.pix_paid_interest, 0) AS NUMERIC)
          - SAFE_CAST(COALESCE(pix.pix_paid_fine, 0) AS NUMERIC),
        NUMERIC '100'
      ) AS instrumento_amount_paid_net_brl,
      pix._ingested_at
    FROM `lemon-ae-case.raw.finance_relations` AS relation
    INNER JOIN `lemon-ae-case.raw.finance_pixs` AS pix
      ON pix.source = relation.target
    WHERE
      relation.source LIKE 'billing#%'
      AND relation.target LIKE 'pix#%'
  ),

  -- Uma cobranca pode possuir varias tentativas de boleto e PIX. Para impedir
  -- fanout, selecionamos um unico instrumento por billing:
  --   1. instrumento pago;
  --   2. pagamento mais recente;
  --   3. criacao mais recente;
  --   4. desempate deterministico por tipo e ID.
  selected_payment_instrument AS (
    SELECT
      *,
      COUNT(*) OVER (PARTITION BY billing_id) AS quantidade_instrumentos,
      COUNTIF(LOWER(instrumento_status) = 'paid') OVER (
        PARTITION BY billing_id
      ) AS quantidade_instrumentos_pagos
    FROM payment_instrument_candidates
    QUALIFY
      ROW_NUMBER() OVER (
        PARTITION BY billing_id
        ORDER BY
          IF(LOWER(instrumento_status) = 'paid', 0, 1),
          instrumento_data_pagamento DESC,
          instrumento_criado_em DESC,
          _ingested_at DESC,
          tipo_instrumento,
          instrumento_id
      ) = 1
  ),

  finance_base AS (
    SELECT
      charge.numero_instalacao,
      charge.mes_referencia,
      charge.charge_id AS identificador_cobranca,
      billing.billing_id,
      DATE(billing.criado_em) AS data_emissao,
      DATE_TRUNC(DATE(billing.criado_em), MONTH) AS mes_emissao,
      billing.data_vencimento,
      DATE_TRUNC(billing.data_vencimento, MONTH) AS mes_vencimento,
      charge.data_liquidacao,
      DATE_TRUNC(charge.data_liquidacao, MONTH) AS mes_liquidacao,
      charge.valor_emitido_brl,
      instrument.instrumento_amount_paid_brl AS valor_liquidado_brl,
      instrument.instrumento_fine_and_interest_brl
        AS multa_juros_recebido_brl,
      instrument.instrumento_amount_paid_net_brl
        AS valor_liquidado_ex_multa_juros_brl,
      charge.payment_status,
      instrument.tipo_instrumento,
      instrument.instrumento_status,
      instrument.quantidade_instrumentos,
      instrument.quantidade_instrumentos_pagos
    FROM charges AS charge
    INNER JOIN billing_charge_relations AS relation
      ON relation.charge_id = charge.charge_id
    INNER JOIN billings AS billing
      ON billing.billing_id = relation.billing_id
    LEFT JOIN selected_payment_instrument AS instrument
      ON instrument.billing_id = billing.billing_id
  ),

  clients AS (
    SELECT
      numero_instalacao,
      SAFE_CAST(mes_referencia AS DATE) AS mes_referencia,
      usina,
      TRIM(gerador) AS gerador,
      disco,
      creditos_faturados_k_wh,
      SAFE_CAST(gmv_gerador_brl AS NUMERIC) AS gmv_gerador_brl
    FROM `lemon-ae-case.raw.energy_clients`
  ),

  payment_client_month AS (
    SELECT
      client.usina,
      client.gerador,
      client.disco,
      client.numero_instalacao AS n_de_instalacao,
      client.mes_referencia,
      finance.identificador_cobranca,
      finance.billing_id,
      finance.mes_emissao,
      finance.mes_liquidacao,
      finance.valor_emitido_brl,
      finance.valor_liquidado_ex_multa_juros_brl,
      finance.multa_juros_recebido_brl,
      client.gmv_gerador_brl,
      client.creditos_faturados_k_wh,
      finance.payment_status,

      SAFE_DIVIDE(
        finance.valor_liquidado_ex_multa_juros_brl,
        NULLIF(finance.valor_emitido_brl, NUMERIC '0')
      ) AS proporcao_liquidada,

      SAFE_DIVIDE(
        finance.valor_liquidado_ex_multa_juros_brl,
        NULLIF(finance.valor_emitido_brl, NUMERIC '0')
      ) * client.gmv_gerador_brl AS valor_liquidado_gerador_brl
    FROM finance_base AS finance
    INNER JOIN clients AS client
      USING (numero_instalacao, mes_referencia)
    WHERE
      finance.numero_instalacao IS NOT NULL
      AND finance.payment_status IN ('waitingPayment', 'paid')
  ),

  payment_flags AS (
    SELECT
      payment.*,
      payment.mes_referencia = params.mes_referencia_relatorio
        AND payment.mes_emissao < params.mes_corte
        AS flag_emitido_do_mes,

      payment.mes_referencia = params.mes_referencia_relatorio
        AND payment.mes_liquidacao < params.mes_corte
        AS flag_liquidado_do_mes,

      payment.mes_referencia < params.mes_referencia_relatorio
        AND payment.mes_emissao = params.mes_corte_anterior
        AS flag_emitido_meses_anteriores,

      payment.mes_referencia < params.mes_referencia_relatorio
        AND payment.mes_liquidacao = params.mes_corte_anterior
        AS flag_liquidado_meses_anteriores
    FROM payment_client_month AS payment
    CROSS JOIN params
    WHERE payment.mes_referencia <= params.mes_referencia_relatorio
  ),

  liquidacoes AS (
    SELECT
      gerador,
      usina,
      disco,
      params.mes_referencia_relatorio AS mes_referencia,

      SUM(
        IF(flag_emitido_do_mes, COALESCE(gmv_gerador_brl, NUMERIC '0'), NUMERIC '0')
      ) AS cobranca_gerador_mes,

      SUM(
        IF(
          flag_emitido_meses_anteriores,
          COALESCE(gmv_gerador_brl, NUMERIC '0'),
          NUMERIC '0'
        )
      ) AS cobranca_gerador_meses_anteriores,

      SUM(
        IF(
          flag_liquidado_do_mes,
          COALESCE(valor_liquidado_gerador_brl, NUMERIC '0'),
          NUMERIC '0'
        )
      ) AS valor_liquidado_gerador_mes,

      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          COALESCE(valor_liquidado_gerador_brl, NUMERIC '0'),
          NUMERIC '0'
        )
      ) AS valor_liquidado_gerador_meses_anteriores,

      SUM(
        IF(
          flag_liquidado_do_mes,
          COALESCE(valor_liquidado_ex_multa_juros_brl, NUMERIC '0'),
          NUMERIC '0'
        )
      ) AS valor_liquidado_ex_multa_juros_mes,

      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          COALESCE(valor_liquidado_ex_multa_juros_brl, NUMERIC '0'),
          NUMERIC '0'
        )
      ) AS valor_liquidado_ex_multa_juros_meses_anteriores,

      SUM(
        IF(
          flag_liquidado_do_mes,
          COALESCE(multa_juros_recebido_brl, NUMERIC '0'),
          NUMERIC '0'
        )
      ) AS multa_juros_total_recebido_mes,

      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          COALESCE(multa_juros_recebido_brl, NUMERIC '0'),
          NUMERIC '0'
        )
      ) AS multa_juros_total_recebido_meses_anteriores,

      SUM(
        IF(
          flag_liquidado_do_mes,
          COALESCE(creditos_faturados_k_wh, 0),
          0
        )
      ) AS creditos_faturados_liquidados_mes,

      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          COALESCE(creditos_faturados_k_wh, 0),
          0
        )
      ) AS creditos_faturados_liquidados_meses_anteriores
    FROM payment_flags
    CROSS JOIN params
    GROUP BY 1, 2, 3, 4
  ),

  liquidacoes_complete AS (
    SELECT
      *,
      valor_liquidado_gerador_mes
        + valor_liquidado_gerador_meses_anteriores
        AS receita_bruta_gerador_brl,

      valor_liquidado_ex_multa_juros_mes
        + valor_liquidado_ex_multa_juros_meses_anteriores
        AS receita_bruta_real_brl,

      multa_juros_total_recebido_mes
        + multa_juros_total_recebido_meses_anteriores
        AS receita_multas_brl,

      creditos_faturados_liquidados_mes
        + creditos_faturados_liquidados_meses_anteriores
        AS creditos_faturados_pagos_kwh
    FROM liquidacoes
  ),

  farm_energy AS (
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
    FROM `lemon-ae-case.raw.energy_farms`
  ),

  client_energy_by_farm AS (
    SELECT
      usina,
      SAFE_CAST(mes_referencia AS DATE) AS mes_referencia,
      SUM(creditos_recebidos_no_mes_k_wh) AS creditos_recebidos_k_wh,
      SUM(creditos_faturados_k_wh) AS creditos_faturados_k_wh
    FROM `lemon-ae-case.raw.energy_clients`
    GROUP BY 1, 2
  ),

  performance_base AS (
    SELECT
      farm.gerador,
      farm.usina,
      farm.disco,
      farm.mes_referencia,
      farm.creditos_injetados_k_wh,
      farm.geracao_prevista_no_contrato_k_wh,
      farm.geracao_realizada_gerador_k_wh,
      client.creditos_recebidos_k_wh,
      client.creditos_faturados_k_wh,
      settlement.creditos_faturados_pagos_kwh,

      SAFE_DIVIDE(
        farm.creditos_injetados_k_wh,
        NULLIF(farm.geracao_prevista_no_contrato_k_wh, 0)
      ) AS injetado_vs_previsto,

      SAFE_DIVIDE(
        farm.creditos_injetados_k_wh,
        NULLIF(farm.geracao_realizada_gerador_k_wh, 0)
      ) AS disco_vs_inversor,

      SAFE_DIVIDE(
        client.creditos_recebidos_k_wh,
        NULLIF(farm.creditos_injetados_k_wh, 0)
      ) AS recebidos_vs_injetados,

      SAFE_DIVIDE(
        client.creditos_faturados_k_wh,
        NULLIF(client.creditos_recebidos_k_wh, 0)
      ) AS faturados_vs_recebidos,

      SAFE_DIVIDE(
        client.creditos_faturados_k_wh,
        NULLIF(farm.minima_injecao_k_wh, 0)
      ) AS preenchimento_usina,

      SAFE_DIVIDE(
        settlement.creditos_faturados_pagos_kwh,
        NULLIF(farm.minima_injecao_k_wh, 0)
      ) AS desempenho_lemon
    FROM farm_energy AS farm
    CROSS JOIN params
    LEFT JOIN client_energy_by_farm AS client
      USING (usina, mes_referencia)
    LEFT JOIN liquidacoes_complete AS settlement
      USING (usina, gerador, disco, mes_referencia)
    WHERE farm.mes_referencia = params.mes_referencia_relatorio
  ),

  valid_take_rate_bands AS (
    SELECT
      params.mes_referencia_relatorio AS mes_referencia,
      take_rate.id_tr,
      take_rate.gerador,
      take_rate.disco,
      take_rate.desempenho_min,
      take_rate.desempenho_max,
      take_rate.tr_percentual,
      SAFE_CAST(take_rate.data_inicio AS DATE) AS data_inicio,
      SAFE_CAST(take_rate.data_final AS DATE) AS data_final
    FROM `lemon-ae-case.raw.energy_generator_take_rates` AS take_rate
    CROSS JOIN params
    WHERE
      SAFE_CAST(take_rate.data_inicio AS DATE)
        <= params.mes_referencia_relatorio
      AND SAFE_CAST(take_rate.data_final AS DATE)
        >= params.mes_referencia_relatorio
  ),

  performance_with_take_rate AS (
    SELECT
      performance.usina,
      performance.gerador,
      performance.disco,
      performance.mes_referencia,
      performance.desempenho_lemon,
      take_rate.tr_percentual AS tr_performado
    FROM performance_base AS performance
    INNER JOIN valid_take_rate_bands AS take_rate
      ON take_rate.gerador = performance.gerador
      AND take_rate.disco = performance.disco
      AND take_rate.mes_referencia = performance.mes_referencia
      AND COALESCE(performance.desempenho_lemon, 0)
        >= take_rate.desempenho_min
      AND COALESCE(performance.desempenho_lemon, 0)
        < take_rate.desempenho_max
    QUALIFY
      ROW_NUMBER() OVER (
        PARTITION BY
          performance.usina,
          performance.gerador,
          performance.disco,
          performance.mes_referencia
        ORDER BY
          take_rate.data_inicio DESC,
          take_rate.desempenho_min DESC,
          take_rate.id_tr
      ) = 1
  ),

  tusd AS (
    SELECT
      farm.usina,
      SAFE_CAST(farm.mes_de_desconto_tusd_gerador AS DATE) AS mes_referencia,
      SUM(SAFE_CAST(farm.tusd_descontada_gerador AS NUMERIC))
        AS tusd_descontada_gerador
    FROM `lemon-ae-case.raw.energy_farms` AS farm
    CROSS JOIN params
    WHERE
      SAFE_CAST(farm.mes_referencia AS DATE) = params.mes_fonte_tusd
      AND SAFE_CAST(farm.mes_de_desconto_tusd_gerador AS DATE)
        = params.mes_referencia_relatorio
    GROUP BY 1, 2
  ),

  report_base AS (
    SELECT
      settlement.*,
      tusd.tusd_descontada_gerador,
      performance.desempenho_lemon,
      performance.tr_performado
    FROM liquidacoes_complete AS settlement
    INNER JOIN tusd
      USING (usina, mes_referencia)
    LEFT JOIN performance_with_take_rate AS performance
      USING (usina, gerador, disco, mes_referencia)
  )

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

  receita_bruta_gerador_brl
    * (NUMERIC '1' - SAFE_CAST(tr_performado AS NUMERIC))
    AS repasse_pre_tusd_gerador,

  tusd_descontada_gerador,

  receita_bruta_gerador_brl
    * (NUMERIC '1' - SAFE_CAST(tr_performado AS NUMERIC))
    - tusd_descontada_gerador
    AS repasse_gerador,

  receita_multas_brl * SAFE_CAST(tr_performado AS NUMERIC)
    AS repasse_multas_lemon,

  receita_multas_brl
    * (NUMERIC '1' - SAFE_CAST(tr_performado AS NUMERIC))
    AS repasse_multas_gerador,

  receita_bruta_gerador_brl * SAFE_CAST(tr_performado AS NUMERIC)
    AS repasse_lemon
FROM report_base
WHERE gerador IS NOT NULL;
