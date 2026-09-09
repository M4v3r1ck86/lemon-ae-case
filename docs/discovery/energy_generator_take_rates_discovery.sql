-- =============================================================================
-- DATA DISCOVERY — raw.energy_generator_take_rates
-- Dialeto: GoogleSQL (BigQuery)
-- Objetivo: validar schema, grain, chaves, faixas, temporalidade e relações.
-- Observação: nomes da fonte são preservados; indicadores derivados estão em PT-BR.
-- =============================================================================

-- 01. SCHEMA
-- Pergunta: quais colunas, tipos e regras de nulabilidade existem na RAW?
SELECT
  ordinal_position AS posicao_coluna,
  column_name AS nome_coluna,
  data_type AS tipo_dado,
  is_nullable AS aceita_nulo
FROM `lemon-ae-case.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'energy_generator_take_rates'
ORDER BY ordinal_position;


-- 02. ESCOPO, GRAIN E CHAVES CANDIDATAS
-- Pergunta: qual é o volume e quais combinações identificam configuração e faixa?
WITH
configuracoes AS (
  SELECT DISTINCT id_tr
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
),
faixas_por_minimo AS (
  SELECT DISTINCT id_tr, desempenho_min
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
),
faixas_por_intervalo AS (
  SELECT DISTINCT id_tr, desempenho_min, desempenho_max
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
),
chaves_naturais AS (
  SELECT DISTINCT
    gerador,
    disco,
    data_inicio,
    data_final,
    desempenho_min,
    desempenho_max
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
)
SELECT
  (SELECT COUNT(*) FROM `lemon-ae-case.raw.energy_generator_take_rates`)
    AS quantidade_registros,
  (SELECT COUNT(*) FROM configuracoes)
    AS quantidade_configuracoes,
  (SELECT COUNT(*) FROM faixas_por_minimo)
    AS quantidade_chaves_id_tr_minimo,
  (SELECT COUNT(*) FROM faixas_por_intervalo)
    AS quantidade_chaves_id_tr_intervalo,
  (SELECT COUNT(*) FROM chaves_naturais)
    AS quantidade_chaves_naturais,
  (SELECT COUNT(DISTINCT id_gerador)
   FROM `lemon-ae-case.raw.energy_generator_take_rates`)
    AS quantidade_ids_gerador,
  (SELECT COUNT(DISTINCT gerador)
   FROM `lemon-ae-case.raw.energy_generator_take_rates`)
    AS quantidade_geradores,
  (SELECT COUNT(DISTINCT disco)
   FROM `lemon-ae-case.raw.energy_generator_take_rates`)
    AS quantidade_distribuidoras;

-- Exibe qualquer duplicidade da chave candidata da faixa.
SELECT
  id_tr,
  desempenho_min,
  COUNT(*) AS quantidade_registros
FROM `lemon-ae-case.raw.energy_generator_take_rates`
GROUP BY id_tr, desempenho_min
HAVING COUNT(*) > 1
ORDER BY quantidade_registros DESC, id_tr, desempenho_min;


-- 03. COMPLETUDE DOS CAMPOS ESSENCIAIS
-- Pergunta: há nulos nos identificadores, limites, percentual ou validade?
SELECT
  COUNT(*) AS quantidade_registros,
  COUNTIF(id_gerador IS NULL) AS nulos_id_gerador,
  COUNTIF(id_tr IS NULL) AS nulos_id_tr,
  COUNTIF(gerador IS NULL OR TRIM(gerador) = '') AS nulos_ou_vazios_gerador,
  COUNTIF(disco IS NULL OR TRIM(disco) = '') AS nulos_ou_vazios_distribuidora,
  COUNTIF(desempenho_min IS NULL) AS nulos_desempenho_min,
  COUNTIF(desempenho_max IS NULL) AS nulos_desempenho_max,
  COUNTIF(tr_percentual IS NULL) AS nulos_tr_percentual,
  COUNTIF(status IS NULL OR TRIM(status) = '') AS nulos_ou_vazios_status,
  COUNTIF(SAFE_CAST(data_inicio AS DATE) IS NULL) AS datas_inicio_invalidas,
  COUNTIF(SAFE_CAST(data_final AS DATE) IS NULL) AS datas_final_invalidas
FROM `lemon-ae-case.raw.energy_generator_take_rates`;


-- 04. INTEGRIDADE DAS FAIXAS
-- Pergunta: cada configuração cobre o domínio sem intervalos inválidos,
-- lacunas ou sobreposições entre faixas consecutivas?
WITH faixas_ordenadas AS (
  SELECT
    id_tr,
    gerador,
    disco,
    desempenho_min,
    desempenho_max,
    tr_percentual,
    data_inicio,
    data_final,
    LAG(desempenho_max) OVER (
      PARTITION BY id_tr
      ORDER BY desempenho_min, desempenho_max
    ) AS desempenho_max_anterior
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
)
SELECT
  id_tr,
  ANY_VALUE(gerador) AS gerador,
  ANY_VALUE(disco) AS disco,
  COUNT(*) AS quantidade_faixas,
  MIN(desempenho_min) AS inicio_cobertura,
  MAX(desempenho_max) AS fim_cobertura,
  COUNTIF(desempenho_max <= desempenho_min) AS intervalos_invalidos,
  COUNTIF(
    desempenho_max_anterior IS NOT NULL
    AND desempenho_min > desempenho_max_anterior
  ) AS quantidade_lacunas,
  COUNTIF(
    desempenho_max_anterior IS NOT NULL
    AND desempenho_min < desempenho_max_anterior
  ) AS quantidade_sobreposicoes,
  COUNTIF(
    SAFE_CAST(data_inicio AS DATE) IS NULL
    OR SAFE_CAST(data_final AS DATE) IS NULL
    OR SAFE_CAST(data_inicio AS DATE) > SAFE_CAST(data_final AS DATE)
  ) AS datas_invalidas
FROM faixas_ordenadas
GROUP BY id_tr
ORDER BY gerador, id_tr;


-- 05. SOBREPOSIÇÃO TEMPORAL ENTRE CONFIGURAÇÕES
-- Pergunta: dois id_tr diferentes ficam válidos ao mesmo tempo para o mesmo
-- gerador e distribuidora? Resultado vazio significa ausência de sobreposição.
WITH configuracoes AS (
  SELECT DISTINCT
    id_tr,
    gerador,
    disco,
    SAFE_CAST(data_inicio AS DATE) AS data_inicio,
    SAFE_CAST(data_final AS DATE) AS data_final
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
)
SELECT
  a.gerador,
  a.disco,
  a.id_tr AS id_tr_a,
  a.data_inicio AS data_inicio_a,
  a.data_final AS data_final_a,
  b.id_tr AS id_tr_b,
  b.data_inicio AS data_inicio_b,
  b.data_final AS data_final_b
FROM configuracoes AS a
JOIN configuracoes AS b
  ON a.gerador = b.gerador
 AND a.disco = b.disco
 AND a.id_tr < b.id_tr
 AND a.data_inicio <= b.data_final
 AND b.data_inicio <= a.data_final
ORDER BY a.gerador, a.id_tr, b.id_tr;


-- 06. COMPORTAMENTO DO TAKE RATE POR FAIXA
-- Pergunta: o percentual diminui quando a faixa de desempenho aumenta?
WITH faixas_ordenadas AS (
  SELECT
    id_tr,
    gerador,
    tr_percentual,
    LAG(tr_percentual) OVER (
      PARTITION BY id_tr
      ORDER BY desempenho_min, desempenho_max
    ) AS tr_percentual_anterior
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
)
SELECT
  id_tr,
  ANY_VALUE(gerador) AS gerador,
  COUNTIF(
    tr_percentual_anterior IS NOT NULL
    AND tr_percentual < tr_percentual_anterior
  ) AS transicoes_decrescentes,
  MIN(tr_percentual) AS menor_take_rate,
  MAX(tr_percentual) AS maior_take_rate
FROM faixas_ordenadas
GROUP BY id_tr
ORDER BY gerador, id_tr;


-- 07. STATUS E VALIDADE DAS CONFIGURAÇÕES
-- Pergunta: qual período e status estão associados a cada agenda de faixas?
SELECT
  id_tr,
  gerador,
  disco,
  status,
  SAFE_CAST(data_inicio AS DATE) AS data_inicio,
  SAFE_CAST(data_final AS DATE) AS data_final,
  COUNT(*) AS quantidade_faixas,
  MIN(tr_percentual) AS menor_take_rate,
  MAX(tr_percentual) AS maior_take_rate
FROM `lemon-ae-case.raw.energy_generator_take_rates`
GROUP BY
  id_tr,
  gerador,
  disco,
  status,
  SAFE_CAST(data_inicio AS DATE),
  SAFE_CAST(data_final AS DATE)
ORDER BY gerador, data_inicio;


-- 08. COBERTURA DOS RELACIONAMENTOS ESSENCIAIS
-- Pergunta: cada cliente encontra exatamente uma configuração válida no mês?
WITH configuracoes AS (
  SELECT DISTINCT
    id_tr,
    gerador,
    disco,
    SAFE_CAST(data_inicio AS DATE) AS data_inicio,
    SAFE_CAST(data_final AS DATE) AS data_final
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
),
cobertura_clientes AS (
  SELECT
    c.numero_instalacao,
    c.mes_referencia,
    c.gerador,
    c.disco,
    COUNT(t.id_tr) AS quantidade_configuracoes_validas
  FROM `lemon-ae-case.raw.energy_clients` AS c
  LEFT JOIN configuracoes AS t
    ON c.gerador = t.gerador
   AND c.disco = t.disco
   AND SAFE_CAST(c.mes_referencia AS DATE)
     BETWEEN t.data_inicio AND t.data_final
  GROUP BY
    c.numero_instalacao,
    c.mes_referencia,
    c.gerador,
    c.disco
)
SELECT
  quantidade_configuracoes_validas,
  COUNT(*) AS quantidade_clientes_mes
FROM cobertura_clientes
GROUP BY quantidade_configuracoes_validas
ORDER BY quantidade_configuracoes_validas;

-- Pergunta: quais geradores da tabela de take rate aparecem nas usinas?
WITH
take_rates AS (
  SELECT DISTINCT gerador, disco
  FROM `lemon-ae-case.raw.energy_generator_take_rates`
),
usinas AS (
  SELECT DISTINCT gerador, disco
  FROM `lemon-ae-case.raw.energy_farms`
)
SELECT
  t.gerador,
  t.disco,
  u.gerador IS NOT NULL AS existe_na_tabela_de_usinas
FROM take_rates AS t
LEFT JOIN usinas AS u
  USING (gerador, disco)
ORDER BY t.gerador, t.disco;
