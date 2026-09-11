# Evidência de resultado — legado e produto Refined

## Objetivo

Esta análise registra por que a `generator_report` original retorna 10 linhas,
enquanto `refined.relatorio_gerador_mensal` retorna 23 para janeiro de 2025.
Os CSVs são evidências estáticas de uma execução do pipeline no BigQuery. As
validações reproduzíveis continuam versionadas em `sql/validation`.

## Evidências

| Resultado | Arquivo | Linhas | Grain observado |
|---|---|---:|---|
| View original | [`generator_report_original_10_rows.csv`](evidence/generator_report_original_10_rows.csv) | 10 | usina + mês de referência |
| Produto Refined | [`relatorio_gerador_mensal_refined_23_rows.csv`](evidence/relatorio_gerador_mensal_refined_23_rows.csv) | 23 | gerador + usina + distribuidora + mês de referência |

As 23 linhas da Refined correspondem a 23 combinações únicas do grain e a 7
geradores. Portanto, a diferença não é causada por duplicação ou fanout.

## Por que o legado retorna 10 linhas

Na view original, a composição final começa pela CTE `tusd`:

```sql
FROM tusd
LEFT JOIN liquidacoes_complete AS liquidacoes
  USING (usina, mes_referencia)
LEFT JOIN desempenho
  USING (usina, mes_referencia)
```

Essa direção do relacionamento transforma a existência de TUSD em condição
para uma usina chegar ao resultado. No snapshot, exatamente 10 usinas possuem
mês de desconto de TUSD. As chaves dessas 10 usinas coincidem com as 10 chaves
da saída original.

## Por que a Refined retorna 23 linhas

O produto proposto usa `trusted.desempenho_usina_mensal` como população e
associa a TUSD com `LEFT JOIN`. Assim, uma usina operacional permanece visível
mesmo quando não há desconto de TUSD associado à competência.

| Situação na Refined | Quantidade |
|---|---:|
| Usinas com mês de desconto de TUSD | 10 |
| Usinas sem mês de desconto de TUSD | 13 |
| Total de usinas preservadas | 23 |

Nas 13 linhas sem correspondência, `dt_mes_desconto_tusd_gerador` permanece
`NULL` e `vlr_tusd_descontada_gerador_brl` é apresentado como zero. A data é
mantida no contrato para distinguir “TUSD ausente” de “TUSD existente com valor
zero”.

## Interpretação das datas

- `dt_mes_referencia` identifica a competência energética e financeira da
  linha. No snapshot, todas as linhas representam janeiro de 2025.
- `dt_fechamento_competencia` registra quando os faturamentos da usina atingem
  a maturação D+60. Como os vencimentos variam, a data de fechamento também
  pode variar entre usinas da mesma competência.
- `dt_mes_desconto_tusd_gerador` identifica o mês em que a TUSD é efetivamente
  aplicada ao repasse. O campo é nulo quando não existe desconto associado.

## Decisão do produto

A Refined preserva as 23 usinas. Reproduzir a população de 10 linhas exigiria
que a TUSD voltasse a controlar a existência do registro, descartando 13 usinas
com desempenho e faturamento válidos. A view de apresentação segue a população
completa e expõe o mês de desconto para que o consumidor interprete os zeros de
TUSD corretamente.

O resultado original permanece disponível para rastreabilidade, mas não define
o grain nem a população do produto corrigido.

## Como reproduzir a contagem

```sql
SELECT
  COUNT(*) AS qtd_linhas,
  COUNT(DISTINCT STRUCT(
    gerador,
    usina,
    cod_distribuidora,
    dt_mes_referencia
  )) AS qtd_chaves_unicas,
  COUNTIF(dt_mes_desconto_tusd_gerador IS NOT NULL) AS qtd_com_tusd,
  COUNTIF(dt_mes_desconto_tusd_gerador IS NULL) AS qtd_sem_tusd
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`;
```

Resultado esperado para o snapshot:

| `qtd_linhas` | `qtd_chaves_unicas` | `qtd_com_tusd` | `qtd_sem_tusd` |
|---:|---:|---:|---:|
| 23 | 23 | 10 | 13 |
