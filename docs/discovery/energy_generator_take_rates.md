# Data Discovery — `energy_generator_take_rates`

## Visão geral

| Atributo | Valor |
|---|---|
| Tabela de origem | `raw.energy_generator_take_rates` |
| Domínio | Energia |
| Tipo de dado | Configuração temporal / tabela de referência |
| Fonte provável | Planilha Google Sheets |
| Quantidade observada | 38 registros |
| Configurações de take rate observadas | 9 |
| Geradores observados | 9 |
| Distribuidoras observadas | 1 (`CEMIG`) |
| Atualização informada pela fonte | `2025-07-30 17:21:40.746000 UTC` |
| Ingestão analisada | `2026-09-06 04:29:02.757077 UTC` |
| Estado do discovery | Validado para o snapshot atual |

Este documento registra o entendimento consolidado da tabela
`energy_generator_take_rates`, obtido por meio da análise do schema, do
conteúdo da tabela e do código SQL original da view `generator_report`.

As conclusões são classificadas como:

- **FATO:** comprovado pelo schema, pelos dados ou pelo SQL da view;
- **HIPÓTESE:** interpretação consistente, mas ainda sem definição oficial;
- **DESCONHECIDO:** não há evidência suficiente para determinar o significado.

### Escopo do documento

Este documento descreve a tabela e os conceitos identificados nos dados. Ele
não descreve a arquitetura interna da Lemon nem propõe a arquitetura da solução
no GCP.

O SQL da `generator_report` é utilizado somente como evidência complementar
quando ajuda a explicar o significado de um campo ou o comportamento de uma
regra. A engenharia reversa completa da view será documentada separadamente,
depois da conclusão do discovery das oito tabelas de origem.

## Descrição funcional

A tabela armazena configurações de **take rate** associadas a geradores de
energia. Cada configuração contém uma ou mais faixas de desempenho, e cada
faixa determina o percentual utilizado na divisão de receita entre a Lemon e o
gerador.

No código atual da `generator_report`, o percentual é aplicado da seguinte
forma:

```text
participação Lemon = receita bruta do gerador × take rate

participação do gerador antes da TUSD =
    receita bruta do gerador × (1 - take rate)
```

TUSD significa **Tarifa de Uso do Sistema de Distribuição**, tarifa associada
ao uso da infraestrutura da distribuidora de energia. No cálculo existente, o
campo `tusd_descontada_gerador` é subtraído da participação do gerador depois
da aplicação do take rate:

```text
repasse final do gerador =
    participação do gerador antes da TUSD - TUSD descontada do gerador
```

O código comprova essa subtração, mas não explica a origem contratual do valor
nem por que ele é atribuído ao gerador. A definição regulatória da TUSD pode ser
consultada no [glossário da ANEEL](https://www2.aneel.gov.br/cedoc/aren20221055_2.pdf).

Portanto, é **FATO** que `tr_percentual` representa a participação da Lemon no
cálculo atual. O uso do termo “comissão” como definição oficial permanece uma
**HIPÓTESE**.

### Estado do mundo representado

> Uma linha representa uma faixa de desempenho pertencente a uma configuração
> temporal de take rate, aplicável a um gerador e uma distribuidora.

A tabela não representa um pagamento, uma cobrança ou uma comissão já
realizada. Ela representa uma regra de configuração utilizada posteriormente
nos cálculos financeiros do Relatório do Gerador.

## Schema e dicionário de campos

| Campo | Tipo na RAW | Nullable | Papel | Definição | Classificação |
|---|---|---:|---|---|---|
| `update_time` | `STRING` | Sim | Campo técnico temporal | Data e hora informada pela origem para a atualização do conjunto de dados. Todas as linhas possuem o mesmo valor no snapshot. Ainda não está confirmado se representa a atualização da planilha, da extração ou de cada registro. | DESCONHECIDO |
| `spreadsheet_id` | `STRING` | Sim | Identificador técnico | Identificador da planilha de origem. Existe apenas um valor no snapshot analisado. A aba e o intervalo de células de origem não estão disponíveis. | FATO parcial |
| `id_gerador` | `STRING` | Sim | Identificador de entidade | Identificador técnico associado ao gerador. Possui 64 caracteres hexadecimais, mas o algoritmo de geração e sua estabilidade histórica não estão documentados. | HIPÓTESE alta |
| `id_tr` | `STRING` | Sim | Identificador da configuração | Agrupa todas as faixas pertencentes à mesma configuração de take rate. Não identifica uma faixa individualmente. | FATO no snapshot |
| `desempenho_min` | `FLOAT64` | Sim | Limite de faixa | Limite inferior de desempenho para aplicação do take rate. É inclusivo no SQL da `generator_report`. | FATO |
| `desempenho_max` | `FLOAT64` | Sim | Limite de faixa | Limite superior de desempenho para aplicação do take rate. É exclusivo no SQL da `generator_report`. | FATO |
| `tr_percentual` | `FLOAT64` | Sim | Percentual / medida | Percentual aplicado à receita quando o desempenho se encontra dentro da faixa. No cálculo atual, corresponde à participação da Lemon. | FATO |
| `status` | `STRING` | Sim | Status | Estado associado à configuração. Os valores observados são `Ativo` e `Inativo`, mas ainda não está confirmado se o status qualifica a configuração, o vínculo comercial ou outra entidade. | DESCONHECIDO |
| `data_inicio` | `STRING` | Sim | Início de validade | Primeiro dia em que a configuração pode ser utilizada. | FATO |
| `data_final` | `STRING` | Sim | Fim de validade | Último dia em que a configuração pode ser utilizada. | FATO |
| `gerador` | `STRING` | Sim | Atributo de relacionamento | Nome ou código legível do gerador. É utilizado como chave de relacionamento pela view atual. | FATO |
| `disco` | `STRING` | Sim | Atributo de relacionamento | Provável código ou nome da distribuidora de energia. O único valor observado é `CEMIG`. | HIPÓTESE alta |
| `_ingested_at` | `TIMESTAMP` | Não | Metadado técnico | Momento em que o registro foi carregado na camada RAW do BigQuery. | FATO |

Os campos temporais da fonte aparecem como `STRING` na tabela analisada, apesar
de representarem semanticamente um timestamp e duas datas de validade.

## Granularidade

### Grain funcional

> **Uma linha representa uma faixa de desempenho de uma configuração de take
> rate.**

Uma configuração, identificada por `id_tr`, pode possuir várias faixas:

```text
Configuração de take rate (`id_tr`)
└── uma ou mais faixas
    ├── desempenho mínimo
    ├── desempenho máximo
    └── percentual aplicável
```

A tabela possui 38 faixas distribuídas entre 9 configurações. Cada configuração
possui entre 1 e 9 faixas.

A tabela não possui grain de cliente, usina, transação ou mês. O mês de
referência é introduzido posteriormente pela `generator_report`, que expande as
configurações de acordo com o período de validade.

### Regra de seleção da faixa

A `generator_report` seleciona a faixa conforme a expressão:

```sql
COALESCE(desempenho_lemon, 0) >= desempenho_min
AND COALESCE(desempenho_lemon, 0) < desempenho_max
```

Consequentemente:

- o limite mínimo é inclusivo;
- o limite máximo é exclusivo;
- um desempenho nulo é tratado como zero pelo código atual.

## Chaves

Não existe chave primária declarada no schema da fonte.

| Chave candidata | Única no snapshot? | Possui NULL? | Uso recomendado |
|---|---:|---:|---|
| `id_gerador` | Não | Não | Identificar o gerador, após validação da origem do ID |
| `id_tr` | Não | Não | Identificar a configuração de take rate |
| `id_tr + desempenho_min` | Sim — 38 de 38 | Não | Chave candidata da faixa |
| `id_tr + desempenho_min + desempenho_max` | Sim — 38 de 38 | Não | Chave técnica de deduplicação mais defensiva |
| `gerador + disco + data_inicio + data_final + desempenho_min + desempenho_max` | Sim — 38 de 38 | Não | Chave natural observada, mas não recomendada como chave física |

O uso de valores `FLOAT64` e textos de negócio em uma chave física pode causar
instabilidade. A melhor chave candidata observada é:

```text
id_tr + desempenho_min
```

Para deduplicação defensiva, `desempenho_max` também pode ser incluído. A
estabilidade dessa chave entre diferentes snapshots ainda precisa ser validada.

## Estrutura das faixas

As nove configurações apresentaram o mesmo padrão estrutural:

- cobertura iniciando em `0`;
- cobertura terminando em `10`;
- nenhum intervalo com máximo menor ou igual ao mínimo;
- nenhum gap entre faixas consecutivas;
- nenhuma sobreposição entre faixas;
- nenhuma data inválida;
- nenhuma sobreposição temporal entre dois `id_tr` do mesmo gerador e
  distribuidora;
- take rate não decrescente conforme o desempenho aumenta.

Essas características são **FATOS do snapshot atual**. A obrigatoriedade de o
take rate sempre crescer ou permanecer constante ainda é uma **HIPÓTESE de
regra de negócio** e não deve ser imposta sem validação.

## Temporalidade

A configuração é considerada aplicável quando a data de referência satisfaz:

```sql
data_inicio <= mes_referencia
AND data_final >= mes_referencia
```

O SQL atual utiliza o primeiro dia do mês como `mes_referencia`.

Oito configurações estão marcadas como `Ativo` e são válidas de
`2025-01-01` até `2025-12-31`. A configuração do Gerador2 possui:

```text
status       = Inativo
data_inicio  = 2025-01-01
data_final   = 2025-04-24
```

O campo `status` não participa dos filtros da `generator_report`. Por isso, a
configuração do Gerador2 é considerada temporalmente válida para janeiro,
fevereiro, março e abril, mesmo estando marcada como inativa.

Como a referência de abril é `2025-04-01`, o código considera a configuração
válida no mês, embora sua validade termine no dia 24. Ainda não está confirmado
se uma validade parcial deve representar o mês inteiro.

## Relacionamentos essenciais

A view original não utiliza `id_gerador` nem o `id_tr` da fonte para relacionar
a configuração ao restante do modelo. O relacionamento é realizado por:

```text
gerador + disco + mes_referencia
```

| Destino | Chave utilizada ou observada | Cobertura | Cardinalidade física |
|---|---|---|---|
| `energy_clients` | `gerador + disco` | Os 9 pares aparecem no histórico de clientes | N:N antes da agregação |
| `energy_farms` | `gerador + disco` | 7 dos 9 pares possuem usinas | N:N antes da seleção temporal |
| `finance_relations` | Nenhuma relação direta identificada | Nenhum `id_tr` ou `id_gerador` encontrado | Não aplicável |

Gerador1 e Gerador9 possuem clientes históricos e configurações de take rate,
mas não possuem registros em `energy_farms`. Isso não comprova um erro: podem
ser configurações históricas, futuras ou geradores ainda sem usina cadastrada.

A relação com o domínio Financeiro é indireta. No SQL existente, os dados
financeiros participam do cálculo do desempenho; o desempenho seleciona uma
faixa; e a faixa determina o take rate. A composição completa desse fluxo será
tratada no discovery específico da `generator_report`.

## Definições ainda pendentes

As seguintes questões não devem ser convertidas em regras de transformação sem
validação adicional:

1. significado oficial de “TR” no vocabulário da Lemon;
2. entidade qualificada pelo campo `status`;
3. aplicação histórica de uma configuração atualmente inativa;
4. regra para validade encerrada no meio do mês;
5. significado do limite superior `10`;
6. tratamento esperado para desempenho igual ou superior a `10`;
7. algoritmo e estabilidade de `id_gerador` e `id_tr`;
8. motivo de Gerador1 e Gerador9 não possuírem usinas;
9. obrigatoriedade de o take rate ser monotônico.

## Resumo do contrato descoberto

```text
Tabela: raw.energy_generator_take_rates

Grain:
  uma faixa de desempenho de uma configuração de take rate

Chave candidata da faixa:
  id_tr + desempenho_min

Entidade principal:
  configuração temporal de take rate

Relacionamento operacional:
  gerador + distribuidora + mês de referência

Regra da faixa:
  desempenho_min <= desempenho < desempenho_max

Resultado:
  seleção do percentual usado na divisão da receita
  entre Lemon e gerador
```
