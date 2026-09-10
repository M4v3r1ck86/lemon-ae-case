-- BigQuery / GoogleSQL
-- =============================================================================
-- PROCEDURE — TRUSTED.SP_CARREGAR_FATURAMENTO_CLIENTE_MENSAL
-- Grain: uma linha por id_instalacao + dt_mes_referencia.
-- Estratégia: agregação prévia dos instrumentos, integração e full refresh.
-- =============================================================================

CREATE OR REPLACE PROCEDURE
  `lemon-ae-case.trusted.sp_carregar_faturamento_cliente_mensal`()
BEGIN
  -- ETAPA 1 — INSTRUMENTOS POR FATURAMENTO
  -- A agregação acontece antes do join para impedir que um cliente seja
  -- repetido pela quantidade de boletos e PIX do seu faturamento.
  CREATE TEMP TABLE tmp_instrumentos_por_faturamento AS
  SELECT
    id_faturamento,
    COUNT(*) AS qtd_instrumentos,
    COUNTIF(tipo_instrumento = 'boleto') AS qtd_boletos,
    COUNTIF(tipo_instrumento = 'pix') AS qtd_pixs,
    COUNTIF(LOWER(status_instrumento) = 'paid') AS qtd_instrumentos_pagos,
    MAX(ingerido_em) AS ingerido_em
  FROM `lemon-ae-case.trusted.instrumento_pagamento`
  GROUP BY id_faturamento;

  -- ETAPA 2 — INTEGRAÇÃO MENSAL
  -- Cliente é a base para preservar instalações sem cobrança ou faturamento.
  -- Cobrança e cliente se relacionam por instalação + mês; faturamento entra
  -- por id_faturamento e os instrumentos já chegam no mesmo grão.
  CREATE TEMP TABLE tmp_faturamento_cliente_integrado AS
  SELECT
    cliente.id_instalacao,
    cliente.dt_mes_referencia,
    cliente.gerador,
    cliente.usina,
    cliente.cod_distribuidora,
    cobranca.id_cobranca,
    cobranca.id_faturamento,
    cobranca.id_local,
    cobranca.status_cobranca,
    faturamento.status_faturamento,
    cobranca.ts_criado_em AS ts_criacao_cobranca,
    faturamento.ts_criado_em AS ts_criacao_faturamento,
    faturamento.dt_vencimento,
    faturamento.dt_vencimento_original,
    DATE(faturamento.ts_pagamento) AS dt_pagamento,
    DATE_TRUNC(DATE(faturamento.ts_pagamento), MONTH) AS dt_mes_pagamento,
    cliente.vlr_gmv_real_oficial_brl,
    cliente.vlr_gmv_gerador_brl,
    cobranca.vlr_cobranca_brl,
    faturamento.vlr_faturamento_brl,
    faturamento.vlr_total_pago_brl,
    CASE
      WHEN faturamento.vlr_total_pago_brl IS NULL THEN NULL
      ELSE faturamento.vlr_total_pago_brl
        - COALESCE(faturamento.vlr_juros_pago_brl, 0)
        - COALESCE(faturamento.vlr_multa_paga_brl, 0)
    END AS vlr_principal_pago_brl,
    faturamento.vlr_juros_pago_brl,
    faturamento.vlr_multa_paga_brl,
    cliente.qtd_creditos_faturados_kwh,
    CASE
      WHEN COALESCE(
        LOWER(faturamento.status_faturamento) = 'paid'
        OR faturamento.ts_pagamento IS NOT NULL,
        FALSE
      )
      THEN cliente.qtd_creditos_faturados_kwh
      ELSE CAST(0 AS NUMERIC)
    END AS qtd_creditos_faturados_pagos_kwh,
    COALESCE(instrumento.qtd_instrumentos, 0) AS qtd_instrumentos,
    COALESCE(instrumento.qtd_boletos, 0) AS qtd_boletos,
    COALESCE(instrumento.qtd_pixs, 0) AS qtd_pixs,
    COALESCE(instrumento.qtd_instrumentos_pagos, 0)
      AS qtd_instrumentos_pagos,
    faturamento.ts_criado_em IS NOT NULL AS flg_emitido,
    COALESCE(
      LOWER(faturamento.status_faturamento) = 'paid'
      OR faturamento.ts_pagamento IS NOT NULL,
      FALSE
    ) AS flg_pago,
    COALESCE(instrumento.qtd_instrumentos_pagos, 0) > 1
      AS flg_multiplos_instrumentos_pagos,
    GREATEST(
      cliente.ingerido_em,
      COALESCE(cobranca.ingerido_em, cliente.ingerido_em),
      COALESCE(faturamento.ingerido_em, cliente.ingerido_em),
      COALESCE(instrumento.ingerido_em, cliente.ingerido_em)
    ) AS ingerido_em
  FROM `lemon-ae-case.trusted.cliente_energia_mensal` AS cliente
  LEFT JOIN `lemon-ae-case.trusted.cobranca` AS cobranca
    ON cliente.id_instalacao = cobranca.id_instalacao
    AND cliente.dt_mes_referencia = cobranca.dt_mes_referencia
  LEFT JOIN `lemon-ae-case.trusted.faturamento` AS faturamento
    ON cobranca.id_faturamento = faturamento.id_faturamento
  LEFT JOIN tmp_instrumentos_por_faturamento AS instrumento
    ON cobranca.id_faturamento = instrumento.id_faturamento;

  -- ETAPA 3 — DEDUPLICAÇÃO DEFENSIVA
  CREATE TEMP TABLE tmp_faturamento_cliente_deduplicado AS
  SELECT *
  FROM tmp_faturamento_cliente_integrado
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_instalacao, dt_mes_referencia
    ORDER BY ingerido_em DESC, id_cobranca DESC, id_faturamento DESC
  ) = 1;

  -- ETAPA 4 — CARGA
  BEGIN TRANSACTION;

  DELETE FROM `lemon-ae-case.trusted.faturamento_cliente_mensal`
  WHERE TRUE;

  INSERT INTO `lemon-ae-case.trusted.faturamento_cliente_mensal`
  SELECT *
  FROM tmp_faturamento_cliente_deduplicado;

  COMMIT TRANSACTION;
END;
