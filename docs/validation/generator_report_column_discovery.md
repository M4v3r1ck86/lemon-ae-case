# Generator Report — Discovery e construção por coluna

## 1. Objetivo

Este documento descreve como cada coluna da view `generator_report` é construída.

Para cada coluna, são documentados:

- conceito funcional;
- classificação como campo de origem ou campo calculado;
- tabela e coluna de origem;
- colunas auxiliares necessárias;
- regra SQL utilizada;
- observações e riscos identificados na implementação legada.

As origens e fórmulas são **FATOS**, pois foram extraídas do SQL da view. As descrições de negócio são interpretações da regra implementada e permanecem **HIPÓTESES** enquanto não forem confirmadas por um stakeholder ou dicionário oficial.

---

## 2. Grain do resultado

O grain observado da view é:

> Uma linha por gerador × usina × distribuidora × mês de referência do relatório.

Chave candidata do resultado:

```text
gerador + usina + disco + mes_referencia
```

No snapshot analisado, a view possui 10 linhas e essa combinação é única.

---

## 3. Tabelas utilizadas

| Tabela raw | Função no relatório |
|---|---|
| `energy_clients` | Fornece cliente/instalação, usina, gerador, distribuidora, GMV do gerador e créditos faturados/recebidos. |
| `energy_farms` | Fornece geração, créditos injetados, geração prevista, geração realizada e desconto de TUSD. |
| `energy_generator_take_rates` | Fornece as faixas de desempenho e o percentual de take rate. |
| `finance_billings` | Fornece billing, data de emissão e vencimento. |
| `finance_charges` | Fornece cobrança, instalação, competência, status, valor, liquidação e cancelamento. |
| `finance_boletos` | Fornece valores pagos, multa e juros de boletos. |
| `finance_pixs` | Fornece valores pagos, multa e juros de PIX. |
| `finance_relations` | Relaciona billing com charge, boleto e PIX. |

---

## 4. Fluxo lógico de construção

```text
finance_billings
finance_charges
finance_relations
finance_boletos
finance_pixs
        │
        ▼
base financeira por instalação e competência
        │
        ├────────── energy_clients
        │                  │
        ▼                  ▼
registros financeiros + GMV + créditos + gerador/usina/disco
        │
        ▼
flags de emissão e liquidação
        │
        ▼
liquidações agregadas por gerador/usina/disco/mês
        │
        ├────────── energy_farms
        │                  │
        │                  ├── geração e injeção
        │                  └── TUSD descontada
        │
        ├────────── energy_generator_take_rates
        │                  │
        ▼                  ▼
desempenho + take rate + receitas
        │
        ▼
repasses Lemon e gerador
```

---

## 5. Colunas auxiliares fundamentais

As colunas abaixo não aparecem no resultado final, mas são necessárias para construir as métricas.

### 5.1 `gmv_gerador_brl`

| Propriedade | Definição |
|---|---|
| Classificação | Campo de origem |
| Origem | `energy_clients.gmv_gerador_brl` |
| Conceito provável | Parcela do GMV atribuída ao gerador para a instalação e competência. |
| Uso | Base de `cobranca_gerador_*` e, no SQL legado, de `valor_liquidado_gerador_*`. |

### 5.2 `mes_emissao`

| Propriedade | Definição |
|---|---|
| Classificação | Calculada |
| Origem | `finance_billings.create_at` |
| Cálculo pretendido | Primeiro dia do mês de emissão do billing. |
| BigQuery recomendado | `DATE_TRUNC(DATE(SAFE_CAST(create_at AS TIMESTAMP)), MONTH)` |

Problema legado: o SQLite executa `DATE(CAST(create_at AS DATE), 'start of month')`. Para textos como `2025-01-16 19:01:25`, o `CAST` gera o inteiro `2025`, que depois é interpretado como dia juliano. A data resultante fica incorreta.

### 5.3 `mes_liquidacao`

| Propriedade | Definição |
|---|---|
| Classificação | Calculada |
| Origem | `finance_charges.payment_date` |
| Cálculo | Primeiro dia do mês de liquidação. |
| BigQuery | `DATE_TRUNC(SAFE_CAST(payment_date AS DATE), MONTH)` |

Observação: a view usa `finance_charges.payment_date`, embora boletos e PIX também possuam data de pagamento. Essa escolha ainda precisa ser validada como regra de negócio.

### 5.4 `valor_emitido_brl`

| Propriedade | Definição |
|---|---|
| Classificação | Calculada a partir da origem |
| Origem | `finance_charges.amount` |
| Unidade na raw | Centavos |
| Cálculo legado | `amount / 100` com divisão inteira no SQLite |
| BigQuery recomendado | `SAFE_DIVIDE(SAFE_CAST(amount AS NUMERIC), NUMERIC '100')` |

### 5.5 `valor_liquidado_ex_multa_juros_brl`

Origem possível em boleto:

```sql
(bank_slip_paid_total
 - bank_slip_paid_interest
 - bank_slip_paid_fine) / 100
```

Origem possível em PIX:

```sql
(pix_paid_total
 - pix_paid_interest
 - pix_paid_fine) / 100
```

Conceito provável:

> Valor efetivamente pago do instrumento, excluindo multa e juros.

### 5.6 `multa_juros_recebido_brl`

Para boleto:

```sql
(bank_slip_paid_interest + bank_slip_paid_fine) / 100
```

Para PIX:

```sql
(pix_paid_interest + pix_paid_fine) / 100
```

### 5.7 `minima_injecao_k_wh`

| Propriedade | Definição |
|---|---|
| Classificação | Calculada |
| Origem | `energy_farms` |
| Dependências | `creditos_injetados_k_wh`, `geracao_prevista_no_contrato_k_wh` |

SQL legado:

```sql
MIN(
  creditos_injetados_k_wh,
  geracao_prevista_no_contrato_k_wh
)
```

BigQuery:

```sql
LEAST(
  creditos_injetados_k_wh,
  geracao_prevista_no_contrato_k_wh
)
```

Conceito provável:

> Limite de energia utilizado como denominador do desempenho, escolhendo o menor valor entre a injeção registrada e a geração prevista em contrato.

### 5.8 `creditos_faturados_pagos_kwh`

```sql
creditos_faturados_liquidados_mes
+ creditos_faturados_liquidados_meses_anteriores
```

Sua origem principal é `energy_clients.creditos_faturados_k_wh`, mas a inclusão depende das flags financeiras de liquidação.

### 5.9 Flags temporais

#### `flag_emitido_do_mes`

```sql
mes_referencia = mes_referencia_report
AND mes_emissao < mes_corte
```

Interpretação provável:

> A competência pertence ao mês do relatório e o billing foi emitido antes do fechamento.

#### `flag_emitido_meses_anteriores`

```sql
mes_referencia < mes_referencia_report
AND mes_emissao = mes_corte_report_anterior
```

Interpretação provável:

> Uma competência anterior ao mês do relatório foi emitida durante o mês imediatamente anterior ao corte.

#### `flag_liquidado_do_mes`

```sql
mes_referencia = mes_referencia_report
AND mes_liquidacao < mes_corte
```

Interpretação provável:

> A competência pertence ao mês do relatório e foi liquidada antes do fechamento.

#### `flag_liquidado_meses_anteriores`

```sql
mes_referencia < mes_referencia_report
AND mes_liquidacao = mes_corte_report_anterior
```

Interpretação provável:

> Uma competência anterior foi liquidada no mês imediatamente anterior ao corte.

### 5.10 Calendário do relatório

O SQL legado deriva:

```sql
mes_corte                     = mes_referencia da base financeira
mes_corte_report_anterior     = mes_corte - 1 mês
mes_referencia_report         = mes_corte - 2 meses
mes_referencia_report_anterior = mes_corte - 3 meses
```

Para o resultado observado:

```text
mes_corte             = 2025-03-01
mes_corte_anterior    = 2025-02-01
mes_referencia_report = 2025-01-01
```

---

## 6. Dicionário das colunas finais

## 6.1 `gerador`

| Propriedade | Definição |
|---|---|
| Conceito | Nome do gerador responsável pela usina e pelos clientes agregados na linha. |
| Classificação | Campo de origem com normalização |
| Origem escolhida | `energy_clients.gerador` |
| Transformação | `TRIM(gerador)` |
| Dependências de relacionamento | É comparado com `energy_farms.gerador` e `energy_generator_take_rates.gerador`. |

Embora três tabelas possuam `gerador`, o valor final percorre o fluxo `energy_clients → clients → pmc → pmc_complete → liquidacoes → liquidacoes_complete`.

## 6.2 `usina`

| Propriedade | Definição |
|---|---|
| Conceito | Usina de energia associada aos clientes, à geração e ao repasse. |
| Classificação | Campo de origem |
| Origem escolhida | `energy_clients.usina` |
| Uso adicional | Chave de junção com `energy_farms` e com as informações de TUSD/desempenho. |

O valor final vem do fluxo financeiro enriquecido com `energy_clients`. A presença da linha final também depende de existir correspondência de TUSD para a usina.

## 6.3 `disco`

| Propriedade | Definição |
|---|---|
| Conceito provável | Distribuidora de energia da operação. No snapshot, o valor observado é `CEMIG`. |
| Classificação | Campo de origem |
| Origem escolhida | `energy_clients.disco` |
| Uso adicional | Chave de seleção da faixa de take rate junto com `gerador` e `mes_referencia`. |

## 6.4 `mes_referencia`

| Propriedade | Definição |
|---|---|
| Conceito | Competência apresentada na linha do relatório. |
| Classificação | Calculada |
| Origem técnica | `dates.mes_referencia_report` |
| Dependência inicial | Meses encontrados após o join entre `finance_charges.reference_month` e `energy_clients.mes_referencia`. |
| Cálculo legado | `mes_corte - 2 meses` |

Além de identificar a competência financeira, essa data deve coincidir com:

- `energy_farms.mes_referencia` para desempenho;
- `energy_farms.mes_de_desconto_tusd_gerador` para TUSD;
- o mês de validade da faixa de take rate.

## 6.5 `cobranca_gerador_mes`

| Propriedade | Definição |
|---|---|
| Conceito provável | GMV do gerador associado às cobranças da competência do relatório emitidas antes do corte. |
| Classificação | Calculada e agregada |
| Origem do valor | `energy_clients.gmv_gerador_brl` |
| Origem da condição | `finance_charges.reference_month`, `finance_charges.status` e `finance_billings.create_at` |

SQL legado:

```sql
SUM(
  IF(
    flag_emitido_do_mes,
    gmv_gerador_brl,
    0
  )
) AS cobranca_gerador_mes
```

Lógica por linha:

```text
se flag_emitido_do_mes = TRUE  → usa gmv_gerador_brl
se flag_emitido_do_mes = FALSE → usa 0
depois soma todos os valores do mesmo gerador/usina/disco/mês
```

Importante: ela não soma `finance_charges.amount`. O nome pode sugerir “valor da cobrança”, mas o SQL soma o GMV atribuído ao gerador.

## 6.6 `cobranca_gerador_meses_anteriores`

| Propriedade | Definição |
|---|---|
| Conceito provável | GMV de competências anteriores que foi emitido no mês anterior ao corte. |
| Classificação | Calculada e agregada |
| Origem do valor | `energy_clients.gmv_gerador_brl` |

```sql
SUM(
  IF(
    flag_emitido_meses_anteriores,
    gmv_gerador_brl,
    0
  )
) AS cobranca_gerador_meses_anteriores
```

Não representa necessariamente todo o estoque histórico. A regra seleciona apenas competências anteriores cuja emissão ocorreu exatamente no `mes_corte_report_anterior`.

## 6.7 `valor_liquidado_gerador_mes`

| Propriedade | Definição |
|---|---|
| Conceito provável | GMV do gerador associado às cobranças da competência do relatório liquidadas antes do corte. |
| Classificação | Calculada e agregada |
| Origem do valor no SQL legado | `energy_clients.gmv_gerador_brl` |
| Origem da condição | `finance_charges.payment_date` |

```sql
SUM(
  IF(
    flag_liquidado_do_mes,
    gmv_gerador_brl,
    0
  )
) AS valor_liquidado_gerador_mes
```

Problema identificado: o SQL calcula anteriormente um `valor_liquidado_gerador_brl` proporcional ao valor pago, mas não utiliza esse campo na agregação. Assim, um pagamento parcial pode incluir o GMV integral do gerador.

## 6.8 `valor_liquidado_gerador_meses_anteriores`

| Propriedade | Definição |
|---|---|
| Conceito provável | GMV de competências anteriores associado às liquidações ocorridas no mês anterior ao corte. |
| Classificação | Calculada e agregada |
| Origem do valor no SQL legado | `energy_clients.gmv_gerador_brl` |

```sql
SUM(
  IF(
    flag_liquidado_meses_anteriores,
    gmv_gerador_brl,
    0
  )
) AS valor_liquidado_gerador_meses_anteriores
```

Possui o mesmo risco de considerar o GMV integral em pagamentos parciais.

## 6.9 `valor_liquidado_ex_multa_juros_mes`

| Propriedade | Definição |
|---|---|
| Conceito | Valor pago no mês, excluindo multa e juros, para a competência do relatório. |
| Classificação | Calculada e agregada |
| Origem | `finance_boletos` ou `finance_pixs` |

```sql
SUM(
  IF(
    flag_liquidado_do_mes,
    valor_liquidado_ex_multa_juros_brl,
    0
  )
) AS valor_liquidado_ex_multa_juros_mes
```

## 6.10 `valor_liquidado_ex_multa_juros_meses_anteriores`

| Propriedade | Definição |
|---|---|
| Conceito | Valor líquido de multa e juros referente a competências anteriores e liquidado no mês anterior ao corte. |
| Classificação | Calculada e agregada |
| Origem | `finance_boletos` ou `finance_pixs` |

```sql
SUM(
  IF(
    flag_liquidado_meses_anteriores,
    valor_liquidado_ex_multa_juros_brl,
    0
  )
) AS valor_liquidado_ex_multa_juros_meses_anteriores
```

## 6.11 `multa_juros_total_recebido_mes`

| Propriedade | Definição |
|---|---|
| Conceito | Multas e juros recebidos nas liquidações da competência do relatório antes do corte. |
| Classificação | Calculada e agregada |
| Origem | Campos de multa e juros de `finance_boletos` ou `finance_pixs` |

```sql
SUM(
  IF(
    flag_liquidado_do_mes,
    multa_juros_recebido_brl,
    0
  )
) AS multa_juros_total_recebido_mes
```

## 6.12 `multa_juros_total_recebido_meses_anteriores`

| Propriedade | Definição |
|---|---|
| Conceito | Multas e juros de competências anteriores recebidos no mês anterior ao corte. |
| Classificação | Calculada e agregada |
| Origem | Campos de multa e juros de `finance_boletos` ou `finance_pixs` |

```sql
SUM(
  IF(
    flag_liquidado_meses_anteriores,
    multa_juros_recebido_brl,
    0
  )
) AS multa_juros_total_recebido_meses_anteriores
```

## 6.13 `receita_bruta_gerador_brl`

| Propriedade | Definição |
|---|---|
| Conceito provável | Receita bruta do gerador considerada no ciclo atual, combinando a competência do relatório e competências anteriores. |
| Classificação | Calculada a partir de colunas do relatório |
| Origem | `valor_liquidado_gerador_mes` e `valor_liquidado_gerador_meses_anteriores` |

```sql
valor_liquidado_gerador_mes
+ valor_liquidado_gerador_meses_anteriores
AS receita_bruta_gerador_brl
```

O valor herda o problema da utilização do GMV integral em vez do valor proporcionalmente liquidado.

## 6.14 `receita_multas_brl`

| Propriedade | Definição |
|---|---|
| Conceito | Total de multas e juros recebidos considerados no ciclo. |
| Classificação | Calculada a partir de colunas do relatório |
| Origem | `multa_juros_total_recebido_mes` e `multa_juros_total_recebido_meses_anteriores` |

```sql
multa_juros_total_recebido_mes
+ multa_juros_total_recebido_meses_anteriores
AS receita_multas_brl
```

## 6.15 `desempenho_lemon`

| Propriedade | Definição |
|---|---|
| Conceito provável | Proporção da capacidade elegível da usina que está associada a créditos faturados e pagos. |
| Classificação | Calculada |
| Numerador | Créditos faturados considerados liquidados, vindos de `energy_clients.creditos_faturados_k_wh` |
| Denominador | Menor valor entre créditos injetados e geração prevista, vindos de `energy_farms` |

```sql
creditos_faturados_pagos_kwh
/ NULLIF(minima_injecao_k_wh, 0)
AS desempenho_lemon
```

Composição do numerador:

```sql
creditos_faturados_liquidados_mes
+ creditos_faturados_liquidados_meses_anteriores
```

Problema comprovado: quando o numerador e o denominador são inteiros no SQLite, razões menores que 1 são truncadas para zero. No BigQuery, a coerção para `FLOAT64` preserva a fração.

## 6.16 `tr_performado`

| Propriedade | Definição |
|---|---|
| Conceito provável | Percentual de take rate selecionado para o desempenho da usina no mês. |
| Classificação | Campo de origem selecionado por regra |
| Origem | `energy_generator_take_rates.tr_percentual` |
| Chaves de relacionamento | `gerador`, `disco`, `mes_referencia` |

Regra de validade temporal:

```sql
data_inicio <= mes_referencia
AND data_final >= mes_referencia
```

Regra de seleção da faixa:

```sql
COALESCE(desempenho_lemon, 0) >= desempenho_min
AND COALESCE(desempenho_lemon, 0) < desempenho_max
```

O intervalo é fechado no mínimo e aberto no máximo:

```text
[desempenho_min, desempenho_max)
```

O campo `energy_generator_take_rates.status` não é usado pela view.

## 6.17 `repasse_pre_tusd_gerador`

| Propriedade | Definição |
|---|---|
| Conceito | Participação calculada para o gerador antes do desconto da TUSD. |
| Classificação | Calculada a partir de colunas do relatório |
| Origem | `receita_bruta_gerador_brl` e `tr_performado` |

```sql
receita_bruta_gerador_brl
* (1 - tr_performado)
AS repasse_pre_tusd_gerador
```

## 6.18 `tusd_descontada_gerador`

| Propriedade | Definição |
|---|---|
| Conceito provável | Valor de TUSD descontado do repasse do gerador. |
| Classificação | Campo de origem agregado |
| Origem | `energy_farms.tusd_descontada_gerador` |
| Mês apresentado | `energy_farms.mes_de_desconto_tusd_gerador` |

```sql
SUM(tusd_descontada_gerador)
GROUP BY
  usina,
  mes_de_desconto_tusd_gerador
```

No SQL legado, a fonte é filtrada por:

```sql
energy_farms.mes_referencia = '2025-01-01'
```

Depois, `mes_de_desconto_tusd_gerador` é renomeado como `mes_referencia` e usado no join com o relatório.

## 6.19 `repasse_gerador`

| Propriedade | Definição |
|---|---|
| Conceito | Valor final destinado ao gerador após o desconto da TUSD. |
| Classificação | Calculada a partir de colunas do relatório |
| Origem | `receita_bruta_gerador_brl`, `tr_performado` e `tusd_descontada_gerador` |

```sql
receita_bruta_gerador_brl
* (1 - tr_performado)
- tusd_descontada_gerador
AS repasse_gerador
```

Forma equivalente:

```sql
repasse_pre_tusd_gerador
- tusd_descontada_gerador
```

## 6.20 `repasse_multas_lemon`

| Propriedade | Definição |
|---|---|
| Conceito provável | Parcela das multas e juros atribuída à Lemon conforme o take rate. |
| Classificação | Calculada a partir de colunas do relatório |
| Origem | `receita_multas_brl` e `tr_performado` |

```sql
receita_multas_brl
* tr_performado
AS repasse_multas_lemon
```

## 6.21 `repasse_multas_gerador`

| Propriedade | Definição |
|---|---|
| Conceito provável | Parcela das multas e juros atribuída ao gerador. |
| Classificação | Calculada a partir de colunas do relatório |
| Origem | `receita_multas_brl` e `tr_performado` |

```sql
receita_multas_brl
* (1 - tr_performado)
AS repasse_multas_gerador
```

## 6.22 `repasse_lemon`

| Propriedade | Definição |
|---|---|
| Conceito provável | Participação da Lemon sobre a receita bruta do gerador. |
| Classificação | Calculada a partir de colunas do relatório |
| Origem | `receita_bruta_gerador_brl` e `tr_performado` |

```sql
receita_bruta_gerador_brl
* tr_performado
AS repasse_lemon
```

---

## 7. Matriz principal de documentação das 22 colunas

Esta é a tabela central para reconstruir a view. Ela consolida o significado, a origem física e a regra completa de cada coluna sem exigir a consulta das seções individuais anteriores.

### Como ler a matriz

- **Campo de origem:** coluna ou conjunto de colunas raw necessário para produzir o resultado. Quando a coluna nasce apenas de outras métricas da própria view, aparece como `Nenhum (Calculado)` e suas dependências são informadas.
- **Campo final:** nome exposto pela `generator_report`. Ele foi mantido sem renomeação para facilitar a comparação com a view original.
- **Tipo atual/recomendado:** tipo produzido pela implementação de paridade no BigQuery e, quando necessário, o tipo recomendado para uma implementação confiável.
- **Direto:** cópia do valor de origem sem operação de negócio.
- **Transformado:** campo de origem submetido a limpeza ou conversão técnica.
- **Calculado:** resultado de condição, agregação, razão, lookup ou fórmula entre campos.
- **Origem física:** lista as tabelas raw efetivamente envolvidas. CTEs como `liquidacoes` e `desempenho` são etapas de processamento, não sistemas de origem.
- **Regra:** reproduz o comportamento efetivo da versão de paridade do SQL legado. Diferenças em relação à provável intenção da regra são identificadas no próprio campo.

| # | Campo de origem | Campo final | Tipo atual/recomendado no BigQuery | Conceito / aplicação | Origem física da coluna | Tipo de atribuição | Regra exata de transformação / cálculo |
|---:|---|---|---|---|---|---|---|
| 1 | `gerador` | `gerador` | `STRING` | Identifica o gerador ao qual pertencem a usina e os valores consolidados da linha. | Principal: `energy_clients.gerador`.<br>Usado também para localizar a faixa em `energy_generator_take_rates.gerador`.<br>`energy_farms.gerador` participa do cálculo de desempenho, mas não fornece o valor final. | Transformado | Após o relacionamento da base financeira com clientes por `numero_instalacao + mes_referencia`, aplica-se `TRIM(energy_clients.gerador)`. A coluna é mantida no `GROUP BY gerador, usina, disco, mes_referencia_report`. |
| 2 | `usina` | `usina` | `STRING` | Identifica a usina à qual os clientes, a geração, o desempenho, a TUSD e os repasses estão associados. | Principal: `energy_clients.usina`.<br>Relacionada com `energy_farms.usina` para desempenho e TUSD. | Direto | Seleciona `energy_clients.usina` após o join financeiro-cliente. O valor é agrupado nas liquidações e depois relacionado a desempenho e TUSD por `usina + mes_referencia`. A linha final só sobrevive quando há correspondência no fluxo iniciado pela TUSD. |
| 3 | `disco` | `disco` | `STRING` | Identifica a distribuidora de energia da operação usada no relatório e na seleção do take rate. | Principal: `energy_clients.disco`.<br>Chave de correspondência com `energy_generator_take_rates.disco`; `energy_farms.disco` participa do cálculo de desempenho. | Direto | Seleciona `energy_clients.disco` após o join financeiro-cliente e preserva o campo no agrupamento final. Para o take rate, relaciona `gerador + disco + mes_referencia`. |
| 4 | `reference_month` e `mes_referencia` | `mes_referencia` | `DATE` | Competência que a linha representa no relatório. Não é simplesmente a competência original da cobrança: o SQL gera um calendário de reporte com defasagem de dois meses. | `finance_charges.reference_month` e `energy_clients.mes_referencia`.<br>Também é usada nos relacionamentos com `energy_farms.mes_referencia`, `energy_farms.mes_de_desconto_tusd_gerador` e a vigência de `energy_generator_take_rates`. | Calculado | 1. `mes_base = SAFE_CAST(finance_charges.reference_month AS DATE)`.<br>2. O join com clientes exige `mes_base = SAFE_CAST(energy_clients.mes_referencia AS DATE)`.<br>3. Para cada mês distinto da base: `mes_corte = mes_base`.<br>4. `mes_referencia = DATE_SUB(mes_corte, INTERVAL 2 MONTH)`.<br>Exemplo: corte `2025-03-01` produz referência `2025-01-01`. |
| 5 | `gmv_gerador_brl`, `reference_month`, `status`, `create_at` | `cobranca_gerador_mes` | Provável `FLOAT64`; recomendado `NUMERIC` para BRL | GMV do gerador associado à competência do relatório considerado emitido no ciclo. Apesar do nome, não soma `finance_charges.amount`; soma o GMV atribuído ao gerador. | Valor: `energy_clients.gmv_gerador_brl`.<br>Competência e status: `finance_charges.reference_month`, `finance_charges.status`.<br>Emissão: `finance_billings.create_at`.<br>Relacionamentos: `finance_relations`. | Calculado — agregação condicional | Primeiro filtra `finance_charges.status IN ('waitingPayment', 'paid')`. Na paridade legada: `flag_emitido_do_mes = (mes_referencia_cliente = mes_referencia_report AND finance_billings.create_at IS NOT NULL)`. Depois: `SUM(IF(flag_emitido_do_mes, energy_clients.gmv_gerador_brl, 0))` por `gerador + usina + disco + mes_referencia_report`.<br>Observação: `create_at IS NOT NULL` reproduz o efeito do cast de data defeituoso do SQLite; a provável intenção era comparar `mes_emissao < mes_corte`. |
| 6 | `gmv_gerador_brl`, `reference_month`, `create_at` | `cobranca_gerador_meses_anteriores` | Provável `FLOAT64`; recomendado `NUMERIC` para BRL | GMV de competências anteriores que deveria representar cobranças emitidas no mês anterior ao corte. | `energy_clients.gmv_gerador_brl`.<br>`finance_charges.reference_month`.<br>`finance_billings.create_at`.<br>`finance_relations`. | Calculado — agregação condicional | Comportamento efetivo reproduzido: `flag_emitido_meses_anteriores = FALSE`; portanto `SUM(IF(FALSE, gmv_gerador_brl, 0))`, resultando em zero.<br>Regra aparentemente pretendida: `mes_referencia_cliente < mes_referencia_report AND mes_emissao = DATE_SUB(mes_corte, INTERVAL 1 MONTH)`. O cast de data do SQLite impede que essa condição funcione como esperado. |
| 7 | `gmv_gerador_brl`, `reference_month`, `payment_date`, `status` | `valor_liquidado_gerador_mes` | Provável `FLOAT64`; recomendado `NUMERIC` para BRL | GMV integral do gerador associado às cobranças da competência do relatório liquidadas antes do corte. | Valor: `energy_clients.gmv_gerador_brl`.<br>Competência, pagamento e status: `finance_charges.reference_month`, `finance_charges.payment_date`, `finance_charges.status`.<br>Relacionamentos: `finance_relations`. | Calculado — agregação condicional | `mes_liquidacao = DATE_TRUNC(SAFE_CAST(finance_charges.payment_date AS DATE), MONTH)`.<br>`flag_liquidado_do_mes = (mes_referencia_cliente = mes_referencia_report AND mes_liquidacao < mes_corte)`.<br>Resultado: `SUM(IF(flag_liquidado_do_mes, energy_clients.gmv_gerador_brl, 0))`.<br>O SQL calcula um valor proporcional pago, mas não o usa aqui; pagamentos parciais podem incluir o GMV integral. |
| 8 | `gmv_gerador_brl`, `reference_month`, `payment_date`, `status` | `valor_liquidado_gerador_meses_anteriores` | Provável `FLOAT64`; recomendado `NUMERIC` para BRL | GMV integral de competências anteriores associado a pagamentos ocorridos no mês imediatamente anterior ao corte. | `energy_clients.gmv_gerador_brl`.<br>`finance_charges.reference_month`, `finance_charges.payment_date`, `finance_charges.status`.<br>`finance_relations`. | Calculado — agregação condicional | `mes_liquidacao = DATE_TRUNC(SAFE_CAST(payment_date AS DATE), MONTH)`.<br>`mes_corte_report_anterior = DATE_SUB(mes_corte, INTERVAL 1 MONTH)`.<br>`flag = (mes_referencia_cliente < mes_referencia_report AND mes_liquidacao = mes_corte_report_anterior)`.<br>Resultado: `SUM(IF(flag, gmv_gerador_brl, 0))`. Também herda o risco de considerar GMV integral em pagamento parcial. |
| 9 | Boleto: `bank_slip_paid_total`, `bank_slip_paid_interest`, `bank_slip_paid_fine`.<br>PIX: `pix_paid_total`, `pix_paid_interest`, `pix_paid_fine`.<br>Condição: `reference_month`, `payment_date`, `status`. | `valor_liquidado_ex_multa_juros_mes` | `INT64` na paridade por uso de `DIV`; recomendado `NUMERIC` para BRL | Valor efetivamente pago, sem multa e juros, para a competência do relatório liquidada antes do corte. | `finance_boletos`, `finance_pixs`, `finance_charges` e `finance_relations`. | Calculado — união, conversão e agregação condicional | Boleto: `DIV(bank_slip_paid_total - bank_slip_paid_interest - bank_slip_paid_fine, 100)`.<br>PIX: `DIV(pix_paid_total - pix_paid_interest - pix_paid_fine, 100)`.<br>As ramificações são combinadas por `UNION ALL`.<br>Resultado final: `SUM(IF(flag_liquidado_do_mes, valor_liquidado_ex_multa_juros_brl, 0))`.<br>`DIV` reproduz o truncamento de centavos do SQLite; para correção, usar `SAFE_DIVIDE(CAST(valor AS NUMERIC), 100)`. |
| 10 | Mesmos campos financeiros da coluna 9 | `valor_liquidado_ex_multa_juros_meses_anteriores` | `INT64` na paridade; recomendado `NUMERIC` para BRL | Valor pago sem multa e juros de competências anteriores, liquidado no mês imediatamente anterior ao corte. | `finance_boletos`, `finance_pixs`, `finance_charges` e `finance_relations`. | Calculado — união, conversão e agregação condicional | Calcula o líquido do instrumento como na coluna 9. Depois: `flag = (mes_referencia_cliente < mes_referencia_report AND mes_liquidacao = mes_corte_report_anterior)` e `SUM(IF(flag, valor_liquidado_ex_multa_juros_brl, 0))`. |
| 11 | Boleto: `bank_slip_paid_interest`, `bank_slip_paid_fine`.<br>PIX: `pix_paid_interest`, `pix_paid_fine`.<br>Condição: `reference_month`, `payment_date`, `status`. | `multa_juros_total_recebido_mes` | `INT64` na paridade; recomendado `NUMERIC` para BRL | Total de multa e juros recebido para a competência do relatório antes do corte. | `finance_boletos`, `finance_pixs`, `finance_charges` e `finance_relations`. | Calculado — união, conversão e agregação condicional | Boleto: `DIV(bank_slip_paid_interest + bank_slip_paid_fine, 100)`.<br>PIX: `DIV(pix_paid_interest + pix_paid_fine, 100)`.<br>Após `UNION ALL`: `SUM(IF(flag_liquidado_do_mes, multa_juros_recebido_brl, 0))`. O `DIV` trunca centavos no baseline. |
| 12 | Mesmos campos financeiros da coluna 11 | `multa_juros_total_recebido_meses_anteriores` | `INT64` na paridade; recomendado `NUMERIC` para BRL | Multa e juros de competências anteriores recebidos no mês imediatamente anterior ao corte. | `finance_boletos`, `finance_pixs`, `finance_charges` e `finance_relations`. | Calculado — união, conversão e agregação condicional | Calcula multa e juros do instrumento como na coluna 11. Depois: `SUM(IF(mes_referencia_cliente < mes_referencia_report AND mes_liquidacao = mes_corte_report_anterior, multa_juros_recebido_brl, 0))`. |
| 13 | Nenhum (calculado a partir de `valor_liquidado_gerador_mes` e `valor_liquidado_gerador_meses_anteriores`) | `receita_bruta_gerador_brl` | Provável `FLOAT64`; recomendado `NUMERIC` para BRL | Receita bruta do gerador considerada no ciclo, reunindo a competência atual do relatório e competências anteriores liquidadas no período selecionado. | Derivada das colunas 7 e 8.<br>Origem ancestral: `energy_clients.gmv_gerador_brl`, condicionada por `finance_charges` e `finance_relations`. | Calculado | `valor_liquidado_gerador_mes + valor_liquidado_gerador_meses_anteriores`.<br>Herda a utilização do GMV integral e o possível fanout dos instrumentos financeiros. |
| 14 | Nenhum (calculado a partir de `multa_juros_total_recebido_mes` e `multa_juros_total_recebido_meses_anteriores`) | `receita_multas_brl` | `INT64` na paridade; recomendado `NUMERIC` para BRL | Total de multas e juros considerado no ciclo do relatório. | Derivada das colunas 11 e 12.<br>Origem ancestral: `finance_boletos`, `finance_pixs`, `finance_charges` e `finance_relations`. | Calculado | `multa_juros_total_recebido_mes + multa_juros_total_recebido_meses_anteriores`. |
| 15 | `creditos_faturados_k_wh`, `creditos_injetados_k_wh`, `geracao_prevista_no_contrato_k_wh`, além das datas e status de liquidação | `desempenho_lemon` | `FLOAT64` | Mede a proporção entre créditos faturados considerados pagos e a energia elegível da usina, definida pelo menor valor entre injeção registrada e previsão contratual. | Numerador: `energy_clients.creditos_faturados_k_wh`, condicionado por `finance_charges.reference_month`, `payment_date`, `status` e `finance_relations`.<br>Denominador: `energy_farms.creditos_injetados_k_wh` e `energy_farms.geracao_prevista_no_contrato_k_wh`. | Calculado — agregações e razão | `creditos_faturados_pagos_kwh = SUM(IF(flag_liquidado_do_mes, creditos_faturados_k_wh, 0)) + SUM(IF(flag_liquidado_meses_anteriores, creditos_faturados_k_wh, 0))`.<br>`minima_injecao_k_wh = LEAST(creditos_injetados_k_wh, geracao_prevista_no_contrato_k_wh)`.<br>`desempenho_lemon = creditos_faturados_pagos_kwh / NULLIF(minima_injecao_k_wh, 0)`.<br>As partes são relacionadas por `usina + mes_referencia`. No SQLite, operandos inteiros podem truncar a razão para zero. |
| 16 | `tr_percentual`, `desempenho_min`, `desempenho_max`, `data_inicio`, `data_final`, `gerador`, `disco` | `tr_performado` | `FLOAT64` | Take rate selecionado para o gerador conforme o mês de vigência e a faixa em que o desempenho calculado se enquadra. | `energy_generator_take_rates`. A entrada usada no lookup é `desempenho_lemon`, calculada a partir de `energy_clients`, `energy_farms` e dados financeiros. | Calculado — lookup por vigência e faixa | Primeiro mantém a agenda quando `SAFE_CAST(data_inicio AS DATE) <= mes_referencia AND SAFE_CAST(data_final AS DATE) >= mes_referencia`.<br>Relaciona por `gerador + disco + mes_referencia`.<br>Seleciona `tr_percentual` quando `COALESCE(desempenho_lemon, 0) >= desempenho_min AND COALESCE(desempenho_lemon, 0) < desempenho_max`.<br>O intervalo é `[mínimo, máximo)`. O campo `status` da tabela não é utilizado. |
| 17 | Nenhum (calculado a partir de `receita_bruta_gerador_brl` e `tr_performado`) | `repasse_pre_tusd_gerador` | `FLOAT64`; recomendado `NUMERIC` para BRL | Parcela da receita bruta atribuída ao gerador antes do desconto da TUSD. | Derivada das colunas 13 e 16.<br>Origens ancestrais: `energy_clients`, tabelas financeiras e `energy_generator_take_rates`. | Calculado | `receita_bruta_gerador_brl * (1 - tr_performado)`. |
| 18 | `tusd_descontada_gerador`, `mes_de_desconto_tusd_gerador`, `mes_referencia`, `usina` | `tusd_descontada_gerador` | Provável `FLOAT64`; recomendado `NUMERIC` para BRL | Valor de TUSD associado à usina e ao mês de desconto, subtraído posteriormente do repasse do gerador. | `energy_farms`. | Calculado — filtro, conversão e agregação | Filtra a fonte por `energy_farms.mes_referencia = '2025-01-01'`.<br>Define o mês da métrica como `SAFE_CAST(mes_de_desconto_tusd_gerador AS DATE)`.<br>Calcula `SUM(tusd_descontada_gerador)` por `usina + mes_de_desconto_tusd_gerador`.<br>Relaciona com liquidações por `usina + mes_referencia`. Portanto, o mês final vem do campo de desconto, não do `mes_referencia` usado no filtro. |
| 19 | Nenhum (calculado a partir de `receita_bruta_gerador_brl`, `tr_performado` e `tusd_descontada_gerador`) | `repasse_gerador` | `FLOAT64`; recomendado `NUMERIC` para BRL | Valor final destinado ao gerador depois da aplicação do take rate e do desconto da TUSD. | Derivada das colunas 13, 16 e 18.<br>Origens ancestrais: `energy_clients`, tabelas financeiras, `energy_generator_take_rates` e `energy_farms`. | Calculado | `receita_bruta_gerador_brl * (1 - tr_performado) - tusd_descontada_gerador`.<br>Equivale a `repasse_pre_tusd_gerador - tusd_descontada_gerador`. |
| 20 | Nenhum (calculado a partir de `receita_multas_brl` e `tr_performado`) | `repasse_multas_lemon` | `FLOAT64`; recomendado `NUMERIC` para BRL | Parcela das multas e juros atribuída à Lemon usando o mesmo take rate selecionado pelo desempenho. | Derivada das colunas 14 e 16.<br>Origens ancestrais: `finance_boletos`, `finance_pixs`, `finance_charges`, `finance_relations` e `energy_generator_take_rates`. | Calculado | `receita_multas_brl * tr_performado`. |
| 21 | Nenhum (calculado a partir de `receita_multas_brl` e `tr_performado`) | `repasse_multas_gerador` | `FLOAT64`; recomendado `NUMERIC` para BRL | Parcela das multas e juros atribuída ao gerador. | Derivada das colunas 14 e 16.<br>Origens ancestrais: tabelas financeiras e `energy_generator_take_rates`. | Calculado | `receita_multas_brl * (1 - tr_performado)`. |
| 22 | Nenhum (calculado a partir de `receita_bruta_gerador_brl` e `tr_performado`) | `repasse_lemon` | `FLOAT64`; recomendado `NUMERIC` para BRL | Parcela da receita bruta do gerador atribuída à Lemon pelo take rate selecionado. | Derivada das colunas 13 e 16.<br>Origens ancestrais: `energy_clients`, tabelas financeiras e `energy_generator_take_rates`. | Calculado | `receita_bruta_gerador_brl * tr_performado`. |

---

## 8. Problemas e riscos comprovados ou observados

### 8.1 Fanout entre boleto e PIX

O SQL cria uma ramificação para boleto e outra para PIX e depois usa `UNION ALL`. Como o mesmo billing pode possuir os dois instrumentos e várias tentativas, o GMV e os créditos podem ser repetidos antes das agregações.

### 8.2 Divisão inteira de valores monetários

No SQLite, valores inteiros em centavos divididos por `100` podem ser truncados. Exemplo:

```text
75061 / 100 = 750
```

O valor com centavos seria `750,61`.

### 8.3 Divisão inteira no desempenho

Quando o numerador e o denominador de `desempenho_lemon` são inteiros, uma razão menor que 1 vira zero no SQLite. Essa divergência foi comprovada em 8 das 10 linhas comparadas com o BigQuery.

### 8.4 Data de emissão interpretada incorretamente

O `CAST(... AS DATE)` do SQLite não produz a data esperada para timestamps armazenados como texto. Isso afeta as flags de emissão.

### 8.5 Valor proporcional calculado e ignorado

O SQL calcula:

```sql
valor_liquidado_ex_multa_juros_brl
/ valor_emitido_brl
* gmv_gerador_brl
AS valor_liquidado_gerador_brl
```

Mas `valor_liquidado_gerador_mes` soma `gmv_gerador_brl`, não o valor proporcional calculado.

### 8.6 Status carregados e não utilizados

- `finance_billings.status` é carregado, mas não filtra o relatório;
- `energy_generator_take_rates.status` é carregado na raw, mas não participa da seleção da faixa;
- o filtro financeiro utiliza somente `finance_charges.status IN ('waitingPayment', 'paid')`.

### 8.7 Dependência obrigatória de TUSD

A CTE `base` começa por `tusd` e o resultado final exige `gerador IS NOT NULL`. Na prática, isso restringe o relatório às usinas que conseguem casar com uma linha de TUSD no mês.

### 8.8 Datas fixas

A agenda de take rates é expandida apenas para:

```text
2025-01-01
2025-02-01
2025-03-01
```

A TUSD também utiliza um filtro fixo de janeiro de 2025. A view não é automaticamente reutilizável para outros períodos.

---

## 9. Ordem recomendada para reconstrução incremental

### Etapa 1 — Base financeira

Construir e inspecionar:

```text
billing → charge
billing → boleto
billing → PIX
```

Validar quantas linhas cada billing produz antes de fazer qualquer soma.

### Etapa 2 — Enriquecimento com clientes

Fazer o join:

```text
numero_instalacao + mes_referencia
```

Adicionar:

- gerador;
- usina;
- disco;
- `gmv_gerador_brl`;
- `creditos_faturados_k_wh`.

### Etapa 3 — Calendário e flags

Criar:

- mês de corte;
- mês do relatório;
- mês de corte anterior;
- flags de emissão;
- flags de liquidação.

### Etapa 4 — Colunas financeiras agregadas

Construir primeiro:

1. `cobranca_gerador_mes`;
2. `cobranca_gerador_meses_anteriores`;
3. `valor_liquidado_gerador_mes`;
4. `valor_liquidado_gerador_meses_anteriores`;
5. valores líquidos de multa e juros;
6. multas e juros.

### Etapa 5 — Receitas

Criar:

- `receita_bruta_gerador_brl`;
- `receita_multas_brl`.

### Etapa 6 — Energia e desempenho

Combinar:

- créditos pagos;
- créditos injetados;
- geração prevista;
- mínima injeção;
- desempenho Lemon.

### Etapa 7 — Take rate

Selecionar a faixa válida por:

```text
gerador + distribuidora + mês + desempenho
```

### Etapa 8 — TUSD e repasses

Adicionar a TUSD e calcular:

- repasse pré-TUSD;
- repasse do gerador;
- repasse da Lemon;
- divisão das multas.

---

## 10. Contrato resumido da view

> Para cada gerador, usina, distribuidora e competência, a view reúne o GMV associado às cobranças emitidas e liquidadas, calcula os créditos faturados pagos e o desempenho da operação, seleciona uma faixa de take rate e divide a receita e as multas entre Lemon e gerador, descontando a TUSD do repasse do gerador.

Essa descrição representa a lógica observada no SQL. Ela não substitui a validação formal das regras de negócio.
