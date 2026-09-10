# Generator Report — Findings críticos da engenharia reversa

## 1. Objetivo

Este documento consolida os pontos mais críticos identificados durante a engenharia reversa da view `generator_report`.

O objetivo não é declarar automaticamente que o resultado refatorado representa a regra de negócio correta. O objetivo é separar:

- a primeira divergência observada no fluxo;
- a causa técnica ou lógica dessa divergência;
- as colunas que apenas herdam o valor divergente;
- o que está comprovado pelo SQL e pelos dados;
- o que ainda exige validação de negócio.

As fórmulas e origens detalhadas de todas as colunas estão documentadas em `generator_report_column_discovery.md`.

---

## 2. Evidências utilizadas

A análise comparou:

- o resultado original da `generator_report` executada no SQLite;
- o resultado da versão candidata refatorada no BigQuery;
- o SQL original adaptado para paridade no BigQuery;
- o SQL da versão candidata refatorada;
- as tabelas temporárias utilizadas para diagnosticar o fanout.

Resultado geral da comparação:

| Controle | Resultado |
|---|---:|
| Linhas no SQLite | 10 |
| Linhas no BigQuery refatorado | 10 |
| Chaves presentes nas duas versões | 10 |
| Chaves ausentes ou adicionais | 0 |
| Métricas numéricas comparadas | 18 |
| Métricas com diferença material em pelo menos uma linha | 12 |

A chave utilizada na reconciliação foi:

```text
gerador + usina + disco + mes_referencia
```

Foram validadas independentemente sete fórmulas derivadas, nas dez linhas e nas duas versões, totalizando 140 verificações. Todas fecharam dentro da tolerância numérica:

- `receita_bruta_gerador_brl`;
- `receita_multas_brl`;
- `repasse_pre_tusd_gerador`;
- `repasse_gerador`;
- `repasse_multas_lemon`;
- `repasse_multas_gerador`;
- `repasse_lemon`.

Conclusão:

> As principais diferenças dos repasses não nascem nas fórmulas finais. Elas são propagadas por valores divergentes produzidos em etapas anteriores.

---

## 3. Resumo dos findings críticos

| Finding | Primeira métrica afetada | Causa-raiz | Principais métricas propagadas | Situação |
|---|---|---|---|---|
| `FND-001` | `cobranca_gerador_mes` | Fanout entre billing, boleto e PIX | Cobrança e métricas que reutilizam as linhas financeiras | Problema técnico confirmado |
| `FND-002` | `valor_liquidado_gerador_mes` | GMV integral usado no lugar do valor proporcional calculado | Receita bruta e repasses da Lemon e do gerador | Comportamento legado confirmado; correção de negócio a validar |
| `FND-003` | `valor_liquidado_ex_multa_juros_mes` e `multa_juros_total_recebido_mes` | Divisão inteira dos valores em centavos | Receita de multas e divisão das multas | Problema de precisão confirmado |
| `FND-004` | `desempenho_lemon` | Numerador afetado pelo fluxo financeiro e semântica numérica da divisão | Seleção do take rate e, potencialmente, todos os repasses | Divergência confirmada; impacto futuro possível |

---

## 4. FND-001 — Fanout no fluxo de instrumentos financeiros

### Situação

**FATO:** um mesmo billing pode estar relacionado a mais de um boleto, mais de um PIX ou a ambos. Quando as ramificações são combinadas e depois relacionadas com clientes, uma mesma cobrança pode aparecer em várias linhas.

### Causa-raiz

O GMV é uma informação de `energy_clients`, mas é carregado para cada linha produzida pelo relacionamento financeiro:

```text
billing
  ├── boleto 1
  ├── boleto 2
  ├── PIX 1
  └── PIX 2
```

Se o grain esperado é uma linha por billing ou por cobrança, a agregação posterior passa a somar o mesmo GMV várias vezes.

### Primeira métrica visível afetada

```sql
SUM(IF(flag_emitido_do_mes, gmv_gerador_brl, 0))
  AS cobranca_gerador_mes
```

A fórmula condicional é a mesma nas duas versões. A diferença está no conjunto e na quantidade de linhas recebidas pela agregação.

### Evidência da Usina29

| Versão | `cobranca_gerador_mes` |
|---|---:|
| SQLite legado | R$ 146.084,18 |
| BigQuery refatorado | R$ 68.927,72 |
| Diferença | R$ 77.156,46 |

### Propagação

```text
múltiplos instrumentos por billing
        ↓
repetição das linhas financeiras
        ↓
repetição de GMV e créditos do cliente
        ↓
cobranca_gerador_mes inflada
```

### Decisão necessária

**DESCONHECIDO:** quando existem vários instrumentos, ainda deve ser confirmado se a regra correta é:

- considerar somente o instrumento efetivamente pago;
- considerar o instrumento pago mais recente;
- somar pagamentos parciais de vários instrumentos;
- considerar outra regra definida pelo processo financeiro.

Selecionar automaticamente o instrumento pago mais recente é uma regra candidata, não um fato de negócio confirmado.

---

## 5. FND-002 — Valor proporcional calculado e ignorado

### Situação

**FATO:** o fluxo legado calcula um valor proporcional do GMV:

```sql
valor_liquidado_ex_multa_juros_brl
/ valor_emitido_brl
* gmv_gerador_brl
AS valor_liquidado_gerador_brl
```

Porém, na agregação de `valor_liquidado_gerador_mes`, o SQL legado utiliza o `gmv_gerador_brl` integral:

```sql
SUM(IF(flag_liquidado_do_mes, gmv_gerador_brl, 0))
```

O campo proporcional previamente calculado não é usado.

### Primeira métrica afetada

```text
valor_liquidado_gerador_mes
```

Na versão candidata, a agregação utiliza `valor_liquidado_gerador_brl`. No conjunto analisado, o resultado refatorado corresponde a 50% do valor legado nas dez usinas.

### Evidência da Usina29

| Versão | `valor_liquidado_gerador_mes` |
|---|---:|
| SQLite legado | R$ 105.671,48 |
| BigQuery refatorado | R$ 52.835,74 |

### Propagação

```text
valor_liquidado_gerador_mes
        ↓
receita_bruta_gerador_brl
        ├── repasse_pre_tusd_gerador
        ├── repasse_gerador
        └── repasse_lemon
```

### Exemplo do `repasse_lemon`

O take rate da Usina29 permanece em 3% nas duas versões:

```text
Legado:     105.671,4838289 × 3% = 3.170,144514867
Refatorado:  52.835,74191445 × 3% = 1.585,072257434
```

Portanto, a fórmula de `repasse_lemon` fecha nas duas versões. A diferença é herdada da receita bruta.

### Decisão necessária

**FATO:** o valor proporcional é calculado e ignorado pelo SQL legado.

**HIPÓTESE:** utilizar o GMV proporcional ao valor pago representa melhor a intenção de negócio. Essa interpretação precisa ser confirmada antes de a versão candidata ser classificada como solução definitiva.

---

## 6. FND-003 — Perda de centavos nos valores financeiros

### Situação

**FATO:** os valores de boleto e PIX são armazenados em centavos. O comportamento legado utiliza divisão inteira por `100`, descartando a parte decimal.

Exemplo conceitual:

```text
34.002 centavos

Divisão inteira: 34.002 DIV 100 = 340
Divisão decimal:  34.002 / 100   = 340,02
```

### Primeiras métricas afetadas

- `valor_liquidado_ex_multa_juros_mes`;
- `multa_juros_total_recebido_mes`.

### Propagação das multas

```text
campos de multa e juros de boleto/PIX
        ↓
multa_juros_total_recebido_mes
        ↓
receita_multas_brl
        ├── repasse_multas_lemon
        └── repasse_multas_gerador
```

### Evidência da Usina29

| Campo | SQLite legado | BigQuery refatorado |
|---|---:|---:|
| `receita_multas_brl` | R$ 332,00 | R$ 340,02 |
| `tr_performado` | 3% | 3% |
| `repasse_multas_lemon` | R$ 9,96 | R$ 10,2006 |
| `repasse_multas_gerador` | R$ 322,04 | R$ 329,8194 |

As fórmulas de divisão das multas fecham nas duas versões:

```text
Legado:
332,00 × 3%  = 9,96
332,00 × 97% = 322,04

Refatorado:
340,02 × 3%  = 10,2006
340,02 × 97% = 329,8194
```

Conclusão:

> A divergência dos repasses de multas nasce na conversão dos valores em centavos, não nas fórmulas finais de distribuição.

---

## 7. FND-004 — Divergência no desempenho Lemon

### Fórmula conceitual

```sql
creditos_faturados_pagos_kwh
/ NULLIF(minima_injecao_k_wh, 0)
AS desempenho_lemon
```

Onde:

```sql
minima_injecao_k_wh = LEAST(
  creditos_injetados_k_wh,
  geracao_prevista_no_contrato_k_wh
)
```

### Causas da divergência

O `desempenho_lemon` pode divergir por uma combinação de fatores:

1. o numerador `creditos_faturados_pagos_kwh` percorre o fluxo financeiro e pode ser repetido pelo fanout;
2. a remoção do fanout altera esse numerador;
3. no SQLite, divisões entre operandos inteiros podem truncar razões menores que `1` para `0`;
4. a versão candidata utiliza divisão decimal segura.

### Evidência

Na comparação atual, `desempenho_lemon` apresentou diferença material em nove das dez usinas.

### Propagação potencial

```text
creditos_faturados_pagos_kwh
        ↓
desempenho_lemon
        ↓
faixa de desempenho
        ↓
tr_performado
        ↓
todos os repasses
```

No snapshot analisado, o `tr_performado` permaneceu numericamente igual nas dez linhas. Portanto, a divergência do desempenho ainda não alterou os repasses por meio do take rate neste mês.

Em outro período ou em uma usina próxima ao limite de uma faixa, a correção do desempenho pode selecionar outro percentual e alterar todos os repasses.

---

## 8. Mapa consolidado de propagação

```text
FND-001 — FANOUT
billing × boleto × PIX
        ↓
linhas financeiras repetidas
        ↓
cobranca_gerador_mes


FND-002 — LIQUIDAÇÃO DO GMV
GMV integral versus GMV proporcional
        ↓
valor_liquidado_gerador_mes
        ↓
receita_bruta_gerador_brl
        ├── repasse_pre_tusd_gerador
        ├── repasse_gerador
        └── repasse_lemon


FND-003 — PRECISÃO MONETÁRIA
centavos com divisão inteira
        ↓
valor líquido + multa/juros
        ↓
receita_multas_brl
        ├── repasse_multas_lemon
        └── repasse_multas_gerador


FND-004 — DESEMPENHO
créditos pagos + semântica da divisão
        ↓
desempenho_lemon
        ↓
tr_performado
        ↓
repasses
```

---

## 9. Colunas derivadas cuja fórmula final foi validada

| Coluna | Fórmula | Resultado da validação |
|---|---|---|
| `receita_bruta_gerador_brl` | `valor_liquidado_gerador_mes + valor_liquidado_gerador_meses_anteriores` | Fecha nas duas versões |
| `receita_multas_brl` | `multa_juros_total_recebido_mes + multa_juros_total_recebido_meses_anteriores` | Fecha nas duas versões |
| `repasse_pre_tusd_gerador` | `receita_bruta_gerador_brl * (1 - tr_performado)` | Fecha nas duas versões |
| `repasse_gerador` | `repasse_pre_tusd_gerador - tusd_descontada_gerador` | Fecha nas duas versões |
| `repasse_multas_lemon` | `receita_multas_brl * tr_performado` | Fecha nas duas versões |
| `repasse_multas_gerador` | `receita_multas_brl * (1 - tr_performado)` | Fecha nas duas versões |
| `repasse_lemon` | `receita_bruta_gerador_brl * tr_performado` | Fecha nas duas versões |

Essas colunas podem apresentar valores diferentes sem que sua própria fórmula esteja incorreta. Para encontrar a causa, deve-se seguir o lineage até a primeira entrada divergente.

---

## 10. Priorização para a reconstrução

### P0 — Definir o grain financeiro

- validar a cardinalidade entre billing, charge, boleto e PIX;
- definir o tratamento de múltiplos instrumentos;
- impedir que GMV e créditos sejam multiplicados acidentalmente.

### P0 — Validar a liquidação proporcional

- confirmar se pagamento parcial deve reconhecer apenas parte do GMV;
- confirmar se o valor proporcional calculado representa a regra pretendida;
- documentar formalmente a regra aprovada.

### P1 — Preservar precisão monetária

- converter centavos para `NUMERIC`;
- evitar `DIV` para valores monetários;
- aplicar arredondamento somente na etapa e precisão definidas pelo negócio.

### P1 — Validar desempenho e take rate

- garantir divisão decimal;
- validar o numerador de créditos pagos após eliminar o fanout;
- testar valores nos limites de cada faixa de take rate;
- comparar outros meses para identificar mudanças de faixa.

---

## 11. Conclusão

Os resultados divergentes do relatório não representam uma coleção de fórmulas finais independentes e incorretas. A maior parte das diferenças é explicada por poucos pontos upstream que se propagam pelo fluxo.

Os findings mais relevantes são:

1. multiplicação de linhas no relacionamento entre instrumentos financeiros;
2. uso do GMV integral apesar de existir um cálculo proporcional;
3. perda de centavos por divisão inteira;
4. desempenho calculado com numerador e semântica numérica afetados pelo fluxo legado.

A reconstrução deve corrigir e validar esses pontos na origem. Depois disso, as métricas derivadas devem ser reconciliadas para confirmar que as fórmulas finais continuam fechando com os novos valores de entrada.
