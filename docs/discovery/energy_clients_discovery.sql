-- Discovery principal: raw.energy_clients
-- Dialeto: GoogleSQL (BigQuery)
-- Execute um bloco numerado por vez.

-- =============================================================================
-- 01. SCHEMA
-- Pergunta: quais colunas existem e quais são seus tipos físicos?
-- =============================================================================

SELECT
  ordinal_position AS posicao_coluna,
  column_name AS nome_coluna,
  data_type AS tipo_dado,
  is_nullable AS permite_nulo
FROM `lemon-ae-case.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'energy_clients'
ORDER BY ordinal_position;


-- =============================================================================
-- 02. ESCOPO, GRAIN E CHAVES CANDIDATAS
-- Pergunta: quantas entidades existem e qual combinação identifica uma linha?
-- =============================================================================

WITH base AS (
  SELECT *
  FROM `lemon-ae-case.raw.energy_clients`
),
metricas AS (
  SELECT
    COUNT(*) AS quantidade_linhas,
    COUNT(DISTINCT numero_instalacao) AS quantidade_instalacoes,
    COUNT(DISTINCT mes_referencia) AS quantidade_meses,
    COUNT(DISTINCT usina) AS quantidade_usinas,
    COUNT(DISTINCT gerador) AS quantidade_geradores,
    COUNT(DISTINCT disco) AS quantidade_distribuidoras,
    COUNTIF(numero_instalacao IS NULL) AS instalacoes_nulas,
    COUNTIF(mes_referencia IS NULL) AS meses_nulos,
    COUNTIF(usina IS NULL) AS usinas_nulas,
    COUNTIF(gerador IS NULL) AS geradores_nulos,
    COUNTIF(disco IS NULL) AS distribuidoras_nulas
  FROM base
),
instalacao_mes AS (
  SELECT COUNT(*) AS combinacoes_instalacao_mes
  FROM (
    SELECT DISTINCT numero_instalacao, mes_referencia
    FROM base
  )
),
chave_completa AS (
  SELECT COUNT(*) AS combinacoes_chave_completa
  FROM (
    SELECT DISTINCT
      numero_instalacao,
      mes_referencia,
      usina,
      gerador,
      disco
    FROM base
  )
)
SELECT
  metricas.*,
  instalacao_mes.combinacoes_instalacao_mes,
  chave_completa.combinacoes_chave_completa
FROM metricas
CROSS JOIN instalacao_mes
CROSS JOIN chave_completa;

-- Confirmação de duplicidade da chave candidata.
SELECT
  numero_instalacao,
  mes_referencia,
  COUNT(*) AS quantidade_linhas
FROM `lemon-ae-case.raw.energy_clients`
GROUP BY 1, 2
HAVING COUNT(*) > 1
ORDER BY quantidade_linhas DESC;


-- =============================================================================
-- 03. COMPLETUDE POR COLUNA
-- Pergunta: existem campos nulos na fonte?
-- =============================================================================

BEGIN
  DECLARE consulta_nulos STRING;

  SET consulta_nulos = (
    SELECT STRING_AGG(
      FORMAT(
        """
        SELECT
          '%s' AS nome_coluna,
          COUNTIF(`%s` IS NULL) AS quantidade_nulos,
          ROUND(100 * SAFE_DIVIDE(COUNTIF(`%s` IS NULL), COUNT(*)), 2)
            AS percentual_nulos
        FROM `lemon-ae-case.raw.energy_clients`
        """,
        column_name,
        column_name,
        column_name
      ),
      ' UNION ALL '
      ORDER BY ordinal_position
    )
    FROM `lemon-ae-case.raw.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'energy_clients'
  );

  EXECUTE IMMEDIATE consulta_nulos;
END;


-- =============================================================================
-- 04. DISTRIBUIÇÃO TEMPORAL E ESTABILIDADE DAS ASSOCIAÇÕES
-- Pergunta: volume e vínculos mudam entre os meses?
-- =============================================================================

SELECT
  mes_referencia,
  COUNT(*) AS quantidade_linhas,
  COUNT(DISTINCT numero_instalacao) AS quantidade_instalacoes,
  COUNT(DISTINCT usina) AS quantidade_usinas,
  COUNT(DISTINCT gerador) AS quantidade_geradores
FROM `lemon-ae-case.raw.energy_clients`
GROUP BY 1
ORDER BY SAFE_CAST(mes_referencia AS DATE);

WITH por_instalacao AS (
  SELECT
    numero_instalacao,
    COUNT(DISTINCT mes_referencia) AS quantidade_meses,
    COUNT(DISTINCT usina) AS quantidade_usinas,
    COUNT(DISTINCT gerador) AS quantidade_geradores,
    COUNT(DISTINCT disco) AS quantidade_distribuidoras
  FROM `lemon-ae-case.raw.energy_clients`
  GROUP BY 1
)
SELECT
  COUNT(*) AS quantidade_instalacoes,
  COUNTIF(quantidade_meses = 1) AS presentes_em_um_mes,
  COUNTIF(quantidade_meses = 2) AS presentes_em_dois_meses,
  COUNTIF(quantidade_meses = 3) AS presentes_em_tres_meses,
  COUNTIF(quantidade_usinas > 1) AS instalacoes_que_mudaram_de_usina,
  COUNTIF(quantidade_geradores > 1) AS instalacoes_que_mudaram_de_gerador,
  COUNTIF(quantidade_distribuidoras > 1)
    AS instalacoes_que_mudaram_de_distribuidora
FROM por_instalacao;

-- Continuidade mensal de saldo: EOP anterior deve ser o BOP seguinte.
WITH historico AS (
  SELECT
    numero_instalacao,
    SAFE_CAST(mes_referencia AS DATE) AS mes_referencia,
    saldo_bop_k_wh,
    LAG(SAFE_CAST(mes_referencia AS DATE)) OVER (
      PARTITION BY numero_instalacao
      ORDER BY SAFE_CAST(mes_referencia AS DATE)
    ) AS mes_anterior,
    LAG(saldo_eop_k_wh) OVER (
      PARTITION BY numero_instalacao
      ORDER BY SAFE_CAST(mes_referencia AS DATE)
    ) AS saldo_eop_mes_anterior
  FROM `lemon-ae-case.raw.energy_clients`
),
transicoes AS (
  SELECT
    *,
    saldo_bop_k_wh - saldo_eop_mes_anterior AS diferenca_saldo_k_wh
  FROM historico
  WHERE DATE_DIFF(mes_referencia, mes_anterior, MONTH) = 1
)
SELECT
  COUNT(*) AS quantidade_transicoes,
  COUNTIF(ABS(diferenca_saldo_k_wh) <= 0.000001)
    AS transicoes_exatas,
  COUNTIF(ABS(diferenca_saldo_k_wh) > 0.000001)
    AS transicoes_divergentes,
  MAX(ABS(diferenca_saldo_k_wh)) AS maior_diferenca_absoluta_k_wh
FROM transicoes;


-- =============================================================================
-- 05. RECONCILIAÇÃO DOS CRÉDITOS
-- Pergunta: quais movimentos explicam o saldo e o faturamento?
-- =============================================================================

WITH calculos AS (
  SELECT
    *,
    saldo_eop_k_wh - (
      saldo_bop_k_wh
      + creditos_recebidos_no_mes_k_wh
      + creditos_recebidos_de_meses_anteriores_k_wh
      - creditos_compensados_do_mes_k_wh
      - creditos_compensados_de_meses_anteriores_k_wh
    ) AS diferenca_saldo_k_wh,
    creditos_faturados_k_wh
      - creditos_compensados_do_mes_k_wh
      - creditos_compensados_de_meses_anteriores_k_wh
        AS diferenca_faturamento_k_wh
  FROM `lemon-ae-case.raw.energy_clients`
)
SELECT
  COUNT(*) AS quantidade_linhas,
  COUNTIF(ABS(diferenca_saldo_k_wh) <= 0.02)
    AS saldos_reconciliados,
  COUNTIF(ABS(diferenca_saldo_k_wh) > 0.02)
    AS saldos_divergentes,
  COUNTIF(ABS(diferenca_faturamento_k_wh) <= 0.02)
    AS faturamentos_reconciliados,
  COUNTIF(ABS(diferenca_faturamento_k_wh) > 0.02)
    AS faturamentos_divergentes,
  COUNTIF(creditos_compensados_do_mes_k_wh < 0)
    AS compensacoes_negativas,
  COUNTIF(churn_k_wh > 0) AS linhas_com_churn,
  COUNTIF(
    churn_k_wh > 0
    AND ABS(churn_k_wh - saldo_eop_k_wh) <= 0.000001
  ) AS churn_igual_ao_saldo_final
FROM calculos;

-- Exibe somente as linhas que exigem investigação.
WITH calculos AS (
  SELECT
    *,
    saldo_eop_k_wh - (
      saldo_bop_k_wh
      + creditos_recebidos_no_mes_k_wh
      + creditos_recebidos_de_meses_anteriores_k_wh
      - creditos_compensados_do_mes_k_wh
      - creditos_compensados_de_meses_anteriores_k_wh
    ) AS diferenca_saldo_k_wh,
    creditos_faturados_k_wh
      - creditos_compensados_do_mes_k_wh
      - creditos_compensados_de_meses_anteriores_k_wh
        AS diferenca_faturamento_k_wh
  FROM `lemon-ae-case.raw.energy_clients`
)
SELECT
  numero_instalacao,
  mes_referencia,
  usina,
  gerador,
  saldo_bop_k_wh,
  saldo_eop_k_wh,
  churn_k_wh,
  creditos_recebidos_no_mes_k_wh,
  creditos_compensados_do_mes_k_wh,
  creditos_compensados_de_meses_anteriores_k_wh,
  creditos_faturados_k_wh,
  etapa,
  status,
  excecoes,
  diferenca_saldo_k_wh,
  diferenca_faturamento_k_wh
FROM calculos
WHERE
  ABS(diferenca_saldo_k_wh) > 0.02
  OR ABS(diferenca_faturamento_k_wh) > 0.02
  OR creditos_compensados_do_mes_k_wh < 0
ORDER BY GREATEST(
  ABS(diferenca_saldo_k_wh),
  ABS(diferenca_faturamento_k_wh)
) DESC;


-- =============================================================================
-- 06. ETAPA, STATUS E EXCEÇÕES
-- Pergunta: os estados operacionais explicam ausência de faturamento?
-- =============================================================================

SELECT
  etapa,
  status,
  COUNT(*) AS quantidade_linhas,
  COUNTIF(creditos_faturados_k_wh = 0) AS linhas_sem_creditos_faturados,
  COUNTIF(gmv_gerador_brl = 0) AS linhas_sem_gmv_gerador
FROM `lemon-ae-case.raw.energy_clients`
GROUP BY 1, 2
ORDER BY quantidade_linhas DESC, etapa, status;

-- As famílias abaixo podem se sobrepor.
SELECT
  COUNT(DISTINCT excecoes) AS quantidade_textos_excecao,
  COUNTIF(excecoes = '-') AS linhas_sem_excecao_aparente,
  COUNTIF(LOWER(excecoes) LIKE '%cancelamento%')
    AS linhas_com_cancelamento,
  COUNTIF(LOWER(excecoes) LIKE '%energia de outras fontes%')
    AS linhas_com_energia_de_outras_fontes,
  COUNTIF(LOWER(excecoes) LIKE '%baixa renda%')
    AS linhas_com_baixa_renda,
  COUNTIF(LOWER(excecoes) LIKE '%ajuste de cobran%')
    AS linhas_com_ajuste_de_cobranca
FROM `lemon-ae-case.raw.energy_clients`;


-- =============================================================================
-- 07. FÓRMULAS ECONÔMICAS CANDIDATAS
-- Pergunta: os campos disponíveis reproduzem os valores armazenados?
-- =============================================================================

WITH calculos AS (
  SELECT
    *,
    desconto_gerador_brl_per_k_wh
      - tarifa_de_saida_brl_per_k_wh * desconto_gerador_percentage
        AS diferenca_desconto_gerador_brl_k_wh,
    gmv_real_oficial_brl - (
      creditos_faturados_k_wh * (
        tarifa_de_saida_brl_per_k_wh
        * (1 - desconto_cliente_percentage)
        - pis_per_cofins_nao_compensado_lemon_brl_k_wh
        - icms_nao_compensado_lemon_brl_per_k_wh
      )
    ) AS diferenca_gmv_real_brl,
    gmv_gerador_brl - (
      creditos_faturados_k_wh * (
        tarifa_de_saida_brl_per_k_wh
        - desconto_gerador_brl_per_k_wh
        - pis_per_cofins_nao_compensado_lemon_brl_k_wh
        - icms_nao_compensado_lemon_brl_per_k_wh
      )
      + ajuste_custo_disp_gerador_brl
    ) AS diferenca_gmv_gerador_brl,
    take_rate_lemon_brl
      - (gmv_real_oficial_brl - gmv_gerador_brl)
        AS diferenca_take_rate_brl
  FROM `lemon-ae-case.raw.energy_clients`
)
SELECT
  COUNT(*) AS quantidade_linhas,
  COUNTIF(ABS(diferenca_desconto_gerador_brl_k_wh) <= 0.000001)
    AS descontos_reconciliados,
  COUNTIF(
    creditos_faturados_k_wh > 0
    AND ABS(diferenca_gmv_real_brl) <= 0.02
  ) AS gmv_real_reconciliado,
  COUNTIF(
    creditos_faturados_k_wh > 0
    AND ABS(diferenca_gmv_gerador_brl) <= 0.02
  ) AS gmv_gerador_reconciliado,
  COUNTIF(
    creditos_faturados_k_wh > 0
    AND ABS(diferenca_take_rate_brl) <= 0.02
  ) AS take_rate_reconciliado_com_diferenca_dos_gmvs
FROM calculos;

-- Analise as exceções das fórmulas, especialmente baixa renda e ajustes.
WITH calculos AS (
  SELECT
    *,
    gmv_real_oficial_brl - (
      creditos_faturados_k_wh * (
        tarifa_de_saida_brl_per_k_wh
        * (1 - desconto_cliente_percentage)
        - pis_per_cofins_nao_compensado_lemon_brl_k_wh
        - icms_nao_compensado_lemon_brl_per_k_wh
      )
    ) AS diferenca_gmv_real_brl,
    gmv_gerador_brl - (
      creditos_faturados_k_wh * (
        tarifa_de_saida_brl_per_k_wh
        - desconto_gerador_brl_per_k_wh
        - pis_per_cofins_nao_compensado_lemon_brl_k_wh
        - icms_nao_compensado_lemon_brl_per_k_wh
      )
      + ajuste_custo_disp_gerador_brl
    ) AS diferenca_gmv_gerador_brl
  FROM `lemon-ae-case.raw.energy_clients`
  WHERE creditos_faturados_k_wh > 0
)
SELECT
  numero_instalacao,
  mes_referencia,
  usina,
  gerador,
  creditos_faturados_k_wh,
  gmv_real_oficial_brl,
  gmv_gerador_brl,
  status,
  excecoes,
  diferenca_gmv_real_brl,
  diferenca_gmv_gerador_brl
FROM calculos
WHERE
  ABS(diferenca_gmv_real_brl) > 0.02
  OR ABS(diferenca_gmv_gerador_brl) > 0.02
ORDER BY GREATEST(
  ABS(diferenca_gmv_real_brl),
  ABS(diferenca_gmv_gerador_brl)
) DESC;


-- =============================================================================
-- 08. RELACIONAMENTOS ESSENCIAIS
-- Pergunta: há cobertura e multiplicação ao relacionar usinas e cobranças?
-- =============================================================================

-- energy_clients → energy_farms
WITH resultado AS (
  SELECT
    c.mes_referencia,
    c.gerador,
    c.usina,
    f.usina IS NOT NULL AS encontrou_usina
  FROM `lemon-ae-case.raw.energy_clients` AS c
  LEFT JOIN `lemon-ae-case.raw.energy_farms` AS f
    ON c.mes_referencia = f.mes_referencia
    AND c.gerador = f.gerador
    AND c.usina = f.usina
    AND c.disco = f.disco
)
SELECT
  mes_referencia,
  COUNT(*) AS quantidade_linhas_clientes,
  COUNTIF(encontrou_usina) AS linhas_com_usina,
  COUNTIF(NOT encontrou_usina) AS linhas_sem_usina,
  COUNT(DISTINCT IF(NOT encontrou_usina, usina, NULL))
    AS quantidade_usinas_ausentes
FROM resultado
GROUP BY 1
ORDER BY SAFE_CAST(mes_referencia AS DATE);

-- energy_clients → finance_charges
WITH cobrancas AS (
  SELECT
    disco_consumer_unit_id AS numero_instalacao,
    reference_month AS mes_referencia,
    COUNT(*) AS quantidade_cobrancas
  FROM `lemon-ae-case.raw.finance_charges`
  GROUP BY 1, 2
),
resultado AS (
  SELECT
    c.numero_instalacao,
    c.mes_referencia,
    c.etapa,
    c.status,
    COALESCE(f.quantidade_cobrancas, 0) AS quantidade_cobrancas
  FROM `lemon-ae-case.raw.energy_clients` AS c
  LEFT JOIN cobrancas AS f
    USING (numero_instalacao, mes_referencia)
)
SELECT
  quantidade_cobrancas,
  COUNT(*) AS quantidade_linhas_clientes,
  COUNTIF(etapa = 'Enviada') AS linhas_na_etapa_enviada
FROM resultado
GROUP BY 1
ORDER BY quantidade_cobrancas;

-- Validação de fanout do join financeiro.
WITH antes AS (
  SELECT COUNT(*) AS quantidade_linhas
  FROM `lemon-ae-case.raw.energy_clients`
),
depois AS (
  SELECT COUNT(*) AS quantidade_linhas
  FROM `lemon-ae-case.raw.energy_clients` AS c
  LEFT JOIN `lemon-ae-case.raw.finance_charges` AS f
    ON c.numero_instalacao = f.disco_consumer_unit_id
    AND c.mes_referencia = f.reference_month
)
SELECT
  antes.quantidade_linhas AS linhas_antes_join,
  depois.quantidade_linhas AS linhas_depois_join,
  depois.quantidade_linhas - antes.quantidade_linhas
    AS linhas_adicionadas_pelo_join
FROM antes
CROSS JOIN depois;
