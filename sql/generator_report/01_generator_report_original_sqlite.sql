CREATE VIEW generator_report as
WITH
  billings AS (
	SELECT
      source AS billing_id,
      amount,
      billing_energy_farm_id,
      status,
      create_at,
      due_date
 FROM
		finance_billings
),
  billings2charges AS (
    SELECT
      source AS billing_id,
      target AS charge_id
    FROM
      finance_relations
    WHERE
      source LIKE 'billing#%'
      AND target LIKE 'charge#%'
  ),
  charges AS (
    SELECT
      source AS charge_id,
      cancelled_at,
      cancellation_reason,
      reference_month,
      disco_consumer_unit_id,
      payment_date,
      status,
      amount
    FROM
      finance_charges
  ),
  billings2boletos AS (
    SELECT
      source AS billing_id,
      target AS boleto_id
    FROM
      finance_relations
    WHERE
      source LIKE 'billing#%'
      AND target LIKE 'boleto#%'
  ),
  billings2pixs AS (
    SELECT
      source AS billing_id,
      target AS pix_id
    FROM
      finance_relations
    WHERE
      source LIKE 'billing#%'
      AND target LIKE 'pix#%'
  ),
  boletos AS (
    SELECT
      source AS boleto_id,
      amount,
      bank_slip_paid_total,
      bank_slip_paid_interest,
      bank_slip_paid_fine,
      bank_slip_paid_total,
      bank_slip_paid_interest,
      bank_slip_paid_fine
    FROM
      finance_boletos
  ),
  pixs AS (
    SELECT
      source AS pix_id,
      amount,
      pix_paid_total,
      pix_paid_interest,
      pix_paid_fine,
      pix_paid_total,
      pix_paid_interest,
      pix_paid_fine
    FROM
      finance_pixs
  ),
  boletos_join_billing AS (
    SELECT
      charges.cancelled_at,
      charges.cancellation_reason,
      charges.charge_id,
      charges.reference_month,
      charges.disco_consumer_unit_id,
      charges.payment_date,
      charges.status AS charge_status,
      (charges.amount / 100) AS charge_amount_brl,
      (billings.amount / 100) AS billing_amount_brl,
      billings.billing_energy_farm_id,
      billings.billing_id,
      billings.status AS billing_status,
      billings.create_at AS billing_create_at,
      billings.due_date AS billing_due_date,
      (boletos.amount / 100) AS instrumento_amount_brl,
      (boletos.bank_slip_paid_total / 100) AS instrumento_amount_paid_brl,
      (
        (
          boletos.bank_slip_paid_interest + boletos.bank_slip_paid_fine
        ) / 100
      ) AS instrumento_fine_and_interest_brl,
      (
        (
          boletos.bank_slip_paid_total - boletos.bank_slip_paid_interest - boletos.bank_slip_paid_fine
        ) / 100
      ) AS instrumento_amount_paid_net_brl
    FROM
      charges
      INNER JOIN billings2charges USING (charge_id)
      INNER JOIN billings USING (billing_id)
      LEFT JOIN billings2boletos USING (billing_id)
      LEFT JOIN boletos USING (boleto_id)
  ),
  pixs_join_billing AS (
    SELECT
      charges.cancelled_at,
      charges.cancellation_reason,
      charges.charge_id,
      charges.reference_month,
      charges.disco_consumer_unit_id,
      charges.payment_date,
      charges.status AS charge_status,
      (charges.amount / 100) AS charge_amount_brl,
      (billings.amount / 100) AS billing_amount_brl,
      billings.billing_energy_farm_id,
      billings.billing_id,
      billings.status AS billing_status,
      billings.create_at AS billing_create_at,
      billings.due_date AS billing_due_date,
      (pixs.amount / 100) AS instrumento_amount_brl,
      (pixs.pix_paid_total / 100) AS instrumento_amount_paid_brl,
      (
        (pixs.pix_paid_interest + pixs.pix_paid_fine) / 100
      ) AS instrumento_fine_and_interest_brl,
      (
        (
          pixs.pix_paid_total - pixs.pix_paid_interest - pixs.pix_paid_fine
        ) / 100
      ) AS instrumento_amount_paid_net_brl
    FROM
      charges
      INNER JOIN billings2charges USING (charge_id)
      INNER JOIN billings USING (billing_id)
      LEFT JOIN billings2pixs USING (billing_id)
      LEFT JOIN pixs USING (pix_id)
  ),
  union_boletos_pix AS (
    SELECT
      *
    FROM
      boletos_join_billing
    UNION ALL
    SELECT
      *
    FROM
      pixs_join_billing
  ),
  full_finance AS (
    SELECT
      disco_consumer_unit_id AS numero_instalacao,
      reference_month AS mes_referencia,
      charge_id AS identificador_cobranca,
      billing_id,
      CAST(billing_create_at AS DATE) AS data_emissao,
      date(CAST(billing_create_at AS DATE), 'start of month') AS mes_emissao,
      cancelled_at AS data_cancelamento,
      date(CAST(cancelled_at AS DATE), 'start of month') AS mes_cancelamento,
      cancellation_reason AS motivo_cancelamento,
      billing_due_date AS data_vencimento,
      date(billing_due_date, 'start of month') AS mes_vencimento,
      CAST(payment_date AS DATE) AS data_liquidacao,
      date(payment_date, 'start of month') AS mes_liquidacao,
      charge_amount_brl AS valor_emitido_brl,
      instrumento_amount_paid_brl AS valor_liquidado_brl,
      instrumento_fine_and_interest_brl AS multa_juros_recebido_brl,
      instrumento_amount_paid_net_brl AS valor_liquidado_ex_multa_juros_brl,
      charge_status AS payment_status,
      payment_date
    FROM
      union_boletos_pix
  ),
  clients AS (
    SELECT
      mes_referencia,
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
    FROM
      energy_clients
  ),
  pmc AS (
    SELECT
      *,
      b.valor_liquidado_ex_multa_juros_brl/nullif(
        b.valor_emitido_brl, 0
      ) * n.gmv_gerador_brl AS valor_liquidado_gerador_brl,
      (b.valor_liquidado_ex_multa_juros_brl/nullif(
        b.valor_emitido_brl,0
      ))+ b.multa_juros_recebido_brl AS liquidado_gerador_multas_juros,
      
      MIN(b.data_vencimento) OVER (
        PARTITION BY
          b.numero_instalacao,
          b.mes_referencia
      ) AS min_data_vencimento,
      MAX(b.data_liquidacao) OVER (
        PARTITION BY
          b.numero_instalacao,
          b.mes_referencia
      ) AS max_data_liquidacao
    FROM
      full_finance b
      JOIN clients AS n USING (numero_instalacao, mes_referencia)
  ),
  pmc_complete AS (
    SELECT
      usina,
      TRIM(gerador) AS gerador,
      disco,
      numero_instalacao AS n_de_instalacao,
      mes_referencia,
      identificador_cobranca,
      mes_emissao,
      mes_liquidacao,
      gmv_gerador_brl,
      valor_liquidado_gerador_brl,
      valor_liquidado_ex_multa_juros_brl,
      multa_juros_recebido_brl,
      creditos_faturados_k_wh
    FROM
      pmc
    WHERE
      numero_instalacao IS NOT NULL
      AND payment_status IN ('waitingPayment', 'paid')
  ),
  dates AS (
    SELECT
      date(
        mes_referencia
      ) AS mes_corte,
      date(
        mes_referencia,
        '-1 MONTH'
      ) AS mes_corte_report_anterior,
      date(
        mes_referencia,
        '-2 MONTHS'
      ) AS mes_referencia_report,
      date(
        mes_referencia,
        '-3 MONTHS'
      ) AS mes_referencia_report_anterior
    FROM
      (
        SELECT DISTINCT
          mes_referencia
        FROM
          pmc_complete
      )
  ),
  resumo_pgto AS (
    SELECT
      usina,
      gerador,
      disco,
      n_de_instalacao,
      mes_referencia,
      mes_referencia_report,
      gmv_gerador_brl,
      valor_liquidado_gerador_brl,
      valor_liquidado_ex_multa_juros_brl,
      multa_juros_recebido_brl,
      creditos_faturados_k_wh,
      mes_liquidacao,
      mes_corte,
      mes_referencia = mes_referencia_report AS flag_do_mes,
      mes_referencia < mes_referencia_report AS flag_meses_anteriores,
      mes_referencia = mes_referencia_report
      AND mes_emissao < mes_corte AS flag_emitido_do_mes,
      mes_referencia = mes_referencia_report
      AND mes_liquidacao < mes_corte AS flag_liquidado_do_mes,
      mes_referencia < mes_referencia_report
      AND mes_emissao = mes_corte_report_anterior AS flag_emitido_meses_anteriores,
      mes_referencia < mes_referencia_report
      AND mes_liquidacao = mes_corte_report_anterior AS flag_liquidado_meses_anteriores
    FROM
      pmc_complete
      FULL JOIN dates ON TRUE
    WHERE
      mes_referencia <= mes_referencia_report
  ),
  liquidacoes AS (
    SELECT
      usina,
      gerador,
      disco,
      mes_referencia_report,
      SUM(IF(flag_emitido_do_mes, gmv_gerador_brl, 0)) AS cobranca_gerador_mes,
      SUM(
        IF(flag_emitido_meses_anteriores, gmv_gerador_brl, 0)
      ) AS cobranca_gerador_meses_anteriores,
      SUM(IF(flag_liquidado_do_mes, gmv_gerador_brl, 0)) AS valor_liquidado_gerador_mes,
      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          gmv_gerador_brl,
          0
        )
      ) AS valor_liquidado_gerador_meses_anteriores,
      SUM(
        IF(
          flag_liquidado_do_mes,
          valor_liquidado_ex_multa_juros_brl,
          0
        )
      ) AS valor_liquidado_ex_multa_juros_mes,
      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          valor_liquidado_ex_multa_juros_brl,
          0
        )
      ) AS valor_liquidado_ex_multa_juros_meses_anteriores,
      SUM(
        IF(
          flag_liquidado_do_mes,
          multa_juros_recebido_brl,
          0
        )
      ) AS multa_juros_total_recebido_mes,
      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          multa_juros_recebido_brl,
          0
        )
      ) AS multa_juros_total_recebido_meses_anteriores,
      SUM(
        IF(flag_liquidado_do_mes, creditos_faturados_k_wh, 0)
      ) AS creditos_faturados_liquidados_mes,
      SUM(
        IF(
          flag_liquidado_meses_anteriores,
          creditos_faturados_k_wh,
          0
        )
      ) AS creditos_faturados_liquidados_meses_anteriores
    FROM
      resumo_pgto
    GROUP BY
      1,
      2,
      3,
      4
  ),
  liquidacoes_complete AS (
    SELECT
      gerador,
      usina,
      disco,
      mes_referencia_report AS mes_referencia,
      cobranca_gerador_mes,
      cobranca_gerador_meses_anteriores,
      valor_liquidado_gerador_mes,
      valor_liquidado_gerador_meses_anteriores,
      valor_liquidado_gerador_mes + valor_liquidado_gerador_meses_anteriores AS receita_bruta_gerador_brl,
      valor_liquidado_ex_multa_juros_mes,
      valor_liquidado_ex_multa_juros_meses_anteriores,
      valor_liquidado_ex_multa_juros_mes + valor_liquidado_ex_multa_juros_meses_anteriores AS receita_bruta_real_brl,
      multa_juros_total_recebido_mes,
      multa_juros_total_recebido_meses_anteriores,
      multa_juros_total_recebido_mes + multa_juros_total_recebido_meses_anteriores AS receita_multas_brl
    FROM
      liquidacoes
  ),
  info_usina AS (
    SELECT
      gerador,
      usina,
      disco,
      mes_referencia,
      creditos_injetados_k_wh,
      geracao_prevista_no_contrato_k_wh,
      geracao_realizada_gerador_k_wh,
      MIN(
        creditos_injetados_k_wh,
        geracao_prevista_no_contrato_k_wh
      ) AS minima_injecao_k_wh
    FROM
      energy_farms
  ),
  info_clientes AS (
    SELECT
      usina,
      mes_referencia,
      SUM(creditos_recebidos_no_mes_k_wh) AS creditos_recebidos_k_wh,
      SUM(creditos_faturados_k_wh) AS creditos_faturados_k_wh
    FROM
      energy_clients
    GROUP BY
      mes_referencia,
      usina
  ),
  info_liquidacoes AS (
    SELECT
      usina,
      gerador,
      disco,
      mes_referencia_report AS mes_referencia,
      creditos_faturados_liquidados_mes + creditos_faturados_liquidados_meses_anteriores AS creditos_faturados_pagos_kwh
    FROM
      liquidacoes
  ),
  date_range AS (
    SELECT
      DATE('2025-01-01') as mes_referencia
 union all
   SELECT    DATE('2025-02-01') as mes_referencia
 union all
   SELECT    DATE('2025-03-01') as mes_referencia

  ),
  escada_por_mes AS (
    SELECT
      date_range.mes_referencia,
      escada.*
    FROM
      energy_generator_take_rates AS escada
      JOIN date_range ON escada.data_inicio <= date_range.mes_referencia
      AND escada.data_final >= date_range.mes_referencia
  ),
  info_tr AS (
    SELECT
      mes_referencia,
      id_gerador,
      id_tr,
      gerador,
      disco,
      desempenho_min,
      desempenho_max,
      tr_percentual
    FROM
      escada_por_mes
  ),
  calculo_desempenhos AS (
    SELECT
      us.gerador,
      us.usina,
      us.disco,
      CONCAT(us.gerador, '_', us.disco) AS id_tr,
      us.mes_referencia,
      creditos_injetados_k_wh,
      geracao_prevista_no_contrato_k_wh,
      geracao_realizada_gerador_k_wh,
      creditos_recebidos_k_wh,
      creditos_faturados_k_wh,
      lq.creditos_faturados_pagos_kwh,
      creditos_injetados_k_wh/
        nullif(geracao_prevista_no_contrato_k_wh,0)
       AS injetado_vs_previsto,
      creditos_injetados_k_wh/
        nullif(geracao_realizada_gerador_k_wh, 0)
       AS disco_vs_inversor,
      creditos_recebidos_k_wh/nullif(creditos_injetados_k_wh, 0) AS recebidos_vs_injetados,
      creditos_faturados_k_wh/nullif(creditos_recebidos_k_wh, 0) AS faturados_vs_recebidos,
      creditos_faturados_k_wh/nullif(minima_injecao_k_wh, 0) AS preenchimento_usina,
        lq.creditos_faturados_pagos_kwh/
        nullif(minima_injecao_k_wh, 0)
       AS desempenho_lemon
    FROM
      info_usina AS us
      LEFT JOIN info_clientes USING (usina, mes_referencia)
      LEFT JOIN info_liquidacoes AS lq USING (usina, mes_referencia)
    WHERE
      mes_referencia <= '2025-03-01'
  ),
  dm_desempenho AS (
    SELECT
      cd.*,
      tr_percentual AS tr_performado
    FROM
      calculo_desempenhos cd
      LEFT JOIN info_tr USING (gerador, disco, mes_referencia)
    WHERE
      COALESCE(desempenho_lemon, 0) >= desempenho_min
      AND COALESCE(desempenho_lemon, 0) < desempenho_max
  ),
  desempenho AS (
    SELECT
      usina,
      mes_referencia,
      desempenho_lemon,
      tr_performado
    FROM
      dm_desempenho
  ),
  tusd AS (
    SELECT
      usina,
      mes_de_desconto_tusd_gerador AS mes_referencia,
      SUM(tusd_descontada_gerador) AS tusd_descontada_gerador
    FROM
      energy_farms
    where
      mes_referencia = '2025-01-01'
    GROUP BY
      1,
      2
  ),
  base AS (
    SELECT
      liquidacoes.*,
      tusd.tusd_descontada_gerador,
      desempenho.desempenho_lemon,
      desempenho.tr_performado
    FROM
      tusd
      LEFT JOIN liquidacoes_complete AS liquidacoes USING (usina, mes_referencia)
      LEFT JOIN desempenho USING (usina, mes_referencia)
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
  receita_bruta_gerador_brl * (1 - tr_performado) AS repasse_pre_tusd_gerador,
  tusd_descontada_gerador,
  receita_bruta_gerador_brl * (1 - tr_performado) - tusd_descontada_gerador AS repasse_gerador,
  receita_multas_brl * tr_performado AS repasse_multas_lemon,
  receita_multas_brl * (1 - tr_performado) AS repasse_multas_gerador,
  receita_bruta_gerador_brl * tr_performado AS repasse_lemon
FROM
  base
WHERE
  gerador IS NOT NULL