-- Discovery principal: raw.energy_farms
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
WHERE table_name = 'energy_farms'
ORDER BY ordinal_position;


-- =============================================================================
-- 02. ESCOPO, GRAIN E CHAVES CANDIDATAS
-- Pergunta: quantas entidades existem e qual combinação identifica uma linha?
-- =============================================================================

WITH base AS (
  SELECT *
  FROM `lemon-ae-case.raw.energy_farms`
),
metricas AS (
  SELECT
    COUNT(*) AS quantidade_linhas,
    COUNT(DISTINCT usina) AS quantidade_usinas,
    COUNT(DISTINCT gerador) AS quantidade_geradores,
    COUNT(DISTINCT disco) AS quantidade_distribuidoras,
    COUNT(DISTINCT mes_referencia) AS quantidade_meses,
    COUNTIF(usina IS NULL) AS usinas_nulas,
    COUNTIF(gerador IS NULL) AS geradores_nulos,
    COUNTIF(disco IS NULL) AS distribuidoras_nulas,
    COUNTIF(mes_referencia IS NULL) AS meses_nulos
  FROM base
),
usina_mes AS (
  SELECT COUNT(*) AS combinacoes_usina_mes
  FROM (
    SELECT DISTINCT usina, mes_referencia
    FROM base
  )
),
chave_completa AS (
  SELECT COUNT(*) AS combinacoes_chave_completa
  FROM (
    SELECT DISTINCT gerador, usina, disco, mes_referencia
    FROM base
  )
)
SELECT
  metricas.*,
  usina_mes.combinacoes_usina_mes,
  chave_completa.combinacoes_chave_completa
FROM metricas
CROSS JOIN usina_mes
CROSS JOIN chave_completa;

SELECT
  gerador,
  usina,
  disco,
  mes_referencia,
  COUNT(*) AS quantidade_linhas
FROM `lemon-ae-case.raw.energy_farms`
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) > 1
ORDER BY quantidade_linhas DESC;


-- =============================================================================
-- 03. COMPLETUDE E CAMPOS SEM CONTEÚDO
-- Pergunta: quais campos estão ausentes, nulos ou vazios?
-- =============================================================================

SELECT
  COUNT(*) AS quantidade_linhas,
  COUNTIF(creditos_injetados_k_wh IS NULL) AS creditos_injetados_nulos,
  COUNTIF(geracao_prevista_no_contrato_k_wh IS NULL)
    AS geracoes_previstas_nulas,
  COUNTIF(geracao_realizada_gerador_k_wh IS NULL)
    AS geracoes_realizadas_nulas,
  COUNTIF(tusd_brl IS NULL) AS tusd_nulas,
  COUNTIF(mes_de_desconto_tusd_gerador IS NULL)
    AS meses_desconto_tusd_nulos,
  COUNTIF(aluguel_imoveis_brl IS NULL) AS alugueis_imoveis_nulos,
  COUNTIF(aluguel_equipamento_brl IS NULL)
    AS alugueis_equipamentos_nulos,
  COUNTIF(operations_and_maintenance_cost_brl IS NULL)
    AS custos_operacao_manutencao_nulos,
  COUNTIF(operations_and_maintenance_cost_brl = '')
    AS custos_operacao_manutencao_vazios,
  COUNTIF(tusd_descontada_gerador IS NULL)
    AS tusd_descontadas_nulas
FROM `lemon-ae-case.raw.energy_farms`;


-- =============================================================================
-- 04. GERAÇÃO PREVISTA, REALIZADA E CRÉDITOS INJETADOS
-- Pergunta: como as três medidas de energia se relacionam?
-- =============================================================================

SELECT
  COUNT(*) AS quantidade_usinas,
  COUNTIF(
    geracao_realizada_gerador_k_wh > creditos_injetados_k_wh
  ) AS realizadas_maiores_que_injetadas,
  COUNTIF(
    geracao_realizada_gerador_k_wh < creditos_injetados_k_wh
  ) AS realizadas_menores_que_injetadas,
  COUNTIF(
    geracao_realizada_gerador_k_wh = creditos_injetados_k_wh
  ) AS realizadas_iguais_as_injetadas,
  SUM(geracao_prevista_no_contrato_k_wh) AS geracao_prevista_total_k_wh,
  SUM(geracao_realizada_gerador_k_wh) AS geracao_realizada_total_k_wh,
  SUM(creditos_injetados_k_wh) AS creditos_injetados_total_k_wh
FROM `lemon-ae-case.raw.energy_farms`;

SELECT
  mes_referencia,
  gerador,
  usina,
  geracao_prevista_no_contrato_k_wh,
  geracao_realizada_gerador_k_wh,
  creditos_injetados_k_wh,
  geracao_realizada_gerador_k_wh - creditos_injetados_k_wh
    AS diferenca_realizada_injetada_k_wh,
  creditos_injetados_k_wh - geracao_prevista_no_contrato_k_wh
    AS diferenca_injetada_prevista_k_wh,
  SAFE_DIVIDE(
    creditos_injetados_k_wh,
    geracao_realizada_gerador_k_wh
  ) AS percentual_realizado_registrado_como_injetado
FROM `lemon-ae-case.raw.energy_farms`
ORDER BY gerador, usina;


-- =============================================================================
-- 05. RECONCILIAÇÃO DOS DOIS CAMPOS DE TUSD
-- Pergunta: existe tarifa unitária ou percentual de desconto único?
-- =============================================================================

SELECT
  COUNT(*) AS quantidade_linhas,
  COUNTIF(tusd_brl IS NULL) AS tusd_nulas,
  COUNTIF(tusd_descontada_gerador IS NULL) AS tusd_descontadas_nulas,
  COUNTIF(ABS(tusd_brl - tusd_descontada_gerador) <= 0.01)
    AS valores_tusd_iguais,
  MIN(SAFE_DIVIDE(tusd_brl, creditos_injetados_k_wh))
    AS menor_tusd_brl_por_k_wh_injetado,
  MAX(SAFE_DIVIDE(tusd_brl, creditos_injetados_k_wh))
    AS maior_tusd_brl_por_k_wh_injetado,
  MIN(SAFE_DIVIDE(tusd_descontada_gerador, tusd_brl))
    AS menor_percentual_tusd_descontada,
  MAX(SAFE_DIVIDE(tusd_descontada_gerador, tusd_brl))
    AS maior_percentual_tusd_descontada
FROM `lemon-ae-case.raw.energy_farms`;

SELECT
  gerador,
  usina,
  creditos_injetados_k_wh,
  tusd_brl,
  tusd_descontada_gerador,
  SAFE_DIVIDE(tusd_brl, creditos_injetados_k_wh)
    AS tusd_brl_por_k_wh_injetado,
  SAFE_DIVIDE(tusd_descontada_gerador, tusd_brl)
    AS percentual_tusd_descontada,
  tusd_brl - tusd_descontada_gerador AS diferenca_entre_tusd_brl
FROM `lemon-ae-case.raw.energy_farms`
ORDER BY gerador, usina;


-- =============================================================================
-- 06. COMPETÊNCIAS DA TUSD
-- Pergunta: o mês operacional é igual ao mês da dedução no relatório?
-- =============================================================================

SELECT
  mes_referencia,
  mes_de_desconto_tusd_gerador,
  gerador,
  COUNT(*) AS quantidade_usinas,
  SUM(tusd_descontada_gerador) AS tusd_descontada_total_brl
FROM `lemon-ae-case.raw.energy_farms`
GROUP BY 1, 2, 3
ORDER BY
  SAFE_CAST(mes_referencia AS DATE),
  SAFE_CAST(mes_de_desconto_tusd_gerador AS DATE),
  gerador;

SELECT
  COUNT(*) AS quantidade_linhas,
  COUNTIF(mes_referencia = mes_de_desconto_tusd_gerador)
    AS competencias_iguais,
  COUNTIF(mes_referencia != mes_de_desconto_tusd_gerador)
    AS competencias_diferentes
FROM `lemon-ae-case.raw.energy_farms`;


-- =============================================================================
-- 07. RELAÇÃO COM CLIENTES E TAKE RATES
-- Pergunta: as usinas possuem clientes e uma configuração válida de take rate?
-- =============================================================================

WITH clientes_por_usina AS (
  SELECT
    mes_referencia,
    gerador,
    usina,
    disco,
    COUNT(*) AS quantidade_instalacoes,
    SUM(creditos_recebidos_no_mes_k_wh) AS creditos_recebidos_total_k_wh,
    SUM(creditos_faturados_k_wh) AS creditos_faturados_total_k_wh
  FROM `lemon-ae-case.raw.energy_clients`
  GROUP BY 1, 2, 3, 4
)
SELECT
  f.mes_referencia,
  f.gerador,
  f.usina,
  f.disco,
  c.quantidade_instalacoes,
  f.creditos_injetados_k_wh,
  c.creditos_recebidos_total_k_wh,
  c.creditos_faturados_total_k_wh,
  SAFE_DIVIDE(
    c.creditos_recebidos_total_k_wh,
    f.creditos_injetados_k_wh
  ) AS percentual_recebido_sobre_injetado,
  SAFE_DIVIDE(
    c.creditos_faturados_total_k_wh,
    c.creditos_recebidos_total_k_wh
  ) AS percentual_faturado_sobre_recebido
FROM `lemon-ae-case.raw.energy_farms` AS f
LEFT JOIN clientes_por_usina AS c
  USING (mes_referencia, gerador, usina, disco)
ORDER BY f.gerador, f.usina;

WITH configuracoes AS (
  SELECT DISTINCT
    id_tr,
    gerador,
    disco,
    SAFE_CAST(data_inicio AS DATE) AS data_inicio,
    SAFE_CAST(data_final AS DATE) AS data_final
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
),
resultado AS (
  SELECT
    f.gerador,
    f.usina,
    f.disco,
    f.mes_referencia,
    COUNT(DISTINCT c.id_tr) AS quantidade_configuracoes_validas
  FROM `lemon-ae-case.raw.energy_farms` AS f
  LEFT JOIN configuracoes AS c
    ON f.gerador = c.gerador
    AND f.disco = c.disco
    AND SAFE_CAST(f.mes_referencia AS DATE)
      BETWEEN c.data_inicio AND c.data_final
  GROUP BY 1, 2, 3, 4
)
SELECT
  COUNT(*) AS quantidade_usinas,
  COUNTIF(quantidade_configuracoes_validas = 0)
    AS usinas_sem_configuracao,
  COUNTIF(quantidade_configuracoes_validas = 1)
    AS usinas_com_uma_configuracao,
  COUNTIF(quantidade_configuracoes_validas > 1)
    AS usinas_com_multiplas_configuracoes
FROM resultado;
