# Data Discovery — `energy_clients`

## Visão geral

| Atributo | Valor observado |
|---|---|
| Tabela analisada | `raw.energy_clients` |
| Tabela na fonte SQLite | `energy_clients` |
| Domínio físico | Energia |
| Domínio semântico | Alocação de energia entre usinas e unidades consumidoras |
| Tipo de dado | Snapshot operacional e econômico mensal por unidade consumidora |
| Registros | 2.095 |
| Unidades consumidoras | 709 |
| Usinas | 35 |
| Geradores | 9 |
| Distribuidoras | 1 (`CEMIG`) |
| Meses observados | Janeiro, fevereiro e março de 2025 |
| Colunas na fonte | 26 |
| Metadado adicionado na RAW | `_ingested_at` |

Este documento consolida o entendimento da tabela `energy_clients` obtido pela
análise do schema, dos dados, das relações com outras tabelas e do SQL original
da view `generator_report`.

As conclusões são classificadas como:

- **FATO:** comprovado pelo schema, pelos dados, pelo texto do case ou pelo SQL;
- **HIPÓTESE:** interpretação consistente, mas ainda sem definição oficial;
- **DESCONHECIDO:** não há evidência suficiente para determinar a semântica.

### Escopo

O objetivo é documentar o que a tabela representa no ambiente fornecido pela
Lemon. Este documento não descreve a arquitetura que está sendo construída no
GCP e não propõe ainda o modelo Trusted ou Refined.

O SQL da `generator_report` é usado somente como evidência do papel dos campos.
A engenharia reversa integral da view será documentada separadamente.

## Descrição funcional

A `energy_clients` registra, para cada unidade consumidora e competência:

1. a usina, o gerador e a distribuidora associados;
2. o saldo inicial e final de créditos de energia;
3. créditos recebidos, compensados, faturados e classificados como churn;
4. percentuais e valores usados na composição econômica da linha;
5. a etapa operacional, o status e as exceções aplicáveis.

O whiteboard do case informa que parte do processo consiste na **alocação da
energia gerada pelos geradores entre os clientes**. Os dados observados são
compatíveis com esse contexto.

### Estado do mundo representado

> Uma linha representa a situação mensal de uma unidade consumidora, vinculada
> a uma usina, um gerador e uma distribuidora, incluindo a movimentação de seus
> créditos de energia, valores econômicos e estado operacional.

### O nome físico pode induzir ao erro

A tabela não é um cadastro mestre de pessoas ou empresas clientes. Ela não
contém nome, documento, endereço ou identificador explícito de pessoa.

Sua entidade de menor granularidade é `numero_instalacao`, que se comporta como
identificador pseudonimizado de uma unidade consumidora. Portanto, o nome
`energy_clients` deve ser lido como dados mensais de energia das unidades
consumidoras, e não como uma dimensão cadastral de clientes.

## Schema e dicionário individual dos campos

Todos os 26 campos da fonte estão documentados individualmente. Embora o schema
SQLite permita `NULL`, nenhum dos 2.095 registros apresenta valor nulo em
qualquer coluna.

| Campo | Tipo na RAW | Papel | Definição descoberta | Classificação |
|---|---|---|---|---|
| `numero_instalacao` | `STRING` | Business key / relacionamento | Identificador da instalação ou unidade consumidora. Existem 709 valores, todos com 64 caracteres hexadecimais. Relaciona-se a `finance_charges.disco_consumer_unit_id`. O algoritmo de anonimização não foi fornecido. | FATO funcional; pseudonimização é HIPÓTESE alta |
| `mes_referencia` | `STRING` | Data de competência | Competência mensal da linha. É usada com `numero_instalacao` para formar a chave do registro e relacionar a tabela ao domínio financeiro. | FATO |
| `usina` | `STRING` | Entidade / relacionamento | Usina à qual a unidade consumidora está associada naquela competência. Uma instalação pode mudar de usina entre meses. | FATO |
| `gerador` | `STRING` | Entidade / relacionamento | Gerador responsável pelo conjunto de usinas ao qual a linha está associada. | FATO funcional |
| `disco` | `STRING` | Entidade / relacionamento | Provável abreviação de distribuidora. O único valor observado é `CEMIG`, e o SQL usa o termo em relações com medições e configurações do gerador. | HIPÓTESE alta |
| `saldo_bop_k_wh` | `FLOAT64` | Medida de energia / saldo inicial | Saldo de créditos no início da competência. `BOP` é compatível com *Beginning of Period*. Para todas as 1.386 transições mensais comparáveis, corresponde exatamente ao `saldo_eop_k_wh` do mês anterior. | FATO funcional; expansão da sigla é HIPÓTESE alta |
| `saldo_eop_k_wh` | `FLOAT64` | Medida de energia / saldo final | Saldo de créditos no encerramento da competência. `EOP` é compatível com *End of Period* e alimenta exatamente o BOP do mês seguinte nas instalações que permanecem na base. | FATO funcional; expansão da sigla é HIPÓTESE alta |
| `churn_k_wh` | `FLOAT64` | Medida de energia / classificação | Quantidade marcada como churn. Apenas 9 linhas são positivas e, nas 9, o valor é exatamente igual ao saldo EOP. Isso sugere classificação do saldo remanescente de uma unidade em saída, não uma subtração no balanço do mesmo mês. | FATO sobre o padrão; interpretação é HIPÓTESE |
| `creditos_recebidos_no_mes_k_wh` | `FLOAT64` | Movimento de energia | Créditos atribuídos à unidade na competência. A view soma o campo por usina e compara o total aos créditos injetados da `energy_farms`. | FATO funcional |
| `creditos_recebidos_de_meses_anteriores_k_wh` | `INT64` | Movimento de energia | Campo destinado a créditos recebidos de competências anteriores. Todos os 2.095 valores são zero; por isso sua regra não pôde ser observada. | FATO sobre os dados; semântica operacional DESCONHECIDA |
| `creditos_faturados_k_wh` | `INT64` | Medida de energia faturada | Quantidade de créditos associada ao faturamento da unidade. É usada na view para métricas de desempenho e de créditos pagos. | FATO funcional |
| `creditos_compensados_do_mes_k_wh` | `FLOAT64` | Movimento de compensação | Quantidade registrada como compensada e atribuída ao mês. O significado de “do mês” — competência do consumo ou origem do crédito — não está documentado. | FATO sobre o conteúdo; recorte temporal DESCONHECIDO |
| `creditos_compensados_de_meses_anteriores_k_wh` | `FLOAT64` | Movimento de compensação | Quantidade registrada como compensada e atribuída a meses anteriores. Em conjunto com a compensação do mês, reconcilia os créditos faturados em 2.089 das 2.095 linhas. | FATO funcional; interpretação temporal exata DESCONHECIDA |
| `desconto_cliente_percentage` | `FLOAT64` | Percentual / atributo contratual | Percentual rotulado como desconto do cliente. Possui valores entre 5% e 35%. Participa de uma fórmula candidata para `gmv_real_oficial_brl`, mas não é selecionado pela view. | FATO sobre valor; regra contratual é HIPÓTESE |
| `desconto_gerador_percentage` | `FLOAT64` | Percentual / atributo contratual | Percentual rotulado como desconto do gerador. Possui valores entre 5% e 25% e normalmente se relaciona a `desconto_gerador_brl_per_k_wh`. | FATO sobre valor; regra contratual é HIPÓTESE |
| `gmv_real_oficial_brl` | `FLOAT64` | Valor monetário | Valor em reais rotulado como GMV real oficial da unidade na competência. O significado formal de GMV e os componentes oficiais não foram fornecidos. É selecionado na CTE `clients`, mas não participa do resultado final da view. | FATO sobre conteúdo e uso; definição de negócio DESCONHECIDA |
| `gmv_gerador_brl` | `FLOAT64` | Valor monetário | Valor em reais atribuído ao gerador na linha. É levado ao fluxo financeiro da `generator_report` e usado nas agregações por usina. | FATO funcional |
| `take_rate_lemon_brl` | `FLOAT64` | Valor monetário | Valor em reais rotulado como take rate da Lemon na unidade. Não é o mesmo campo que `tr_percentual` da tabela de faixas e não é usado no cálculo final da `generator_report`. Sua fórmula exata não foi recuperada. | FATO sobre conteúdo e uso; semântica econômica é HIPÓTESE |
| `tarifa_de_saida_brl_per_k_wh` | `FLOAT64` | Tarifa unitária | Valor unitário em reais por kWh rotulado como tarifa de saída. Existem 19 valores distintos. O evento ou contrato ao qual “saída” se refere não está documentado. | FATO sobre unidade e valores; conceito de negócio DESCONHECIDO |
| `pis_per_cofins_nao_compensado_lemon_brl_k_wh` | `FLOAT64` | Valor unitário tributário | Valor por kWh rotulado como PIS/COFINS não compensado da Lemon. Participa das fórmulas candidatas de GMV. O nome físico não usa `_per_` de forma consistente. | FATO funcional; regra tributária DESCONHECIDA |
| `icms_nao_compensado_lemon_brl_per_k_wh` | `INT64` | Valor unitário tributário | Campo destinado ao ICMS não compensado da Lemon por kWh. Todos os valores são zero, impedindo validar tipo decimal e regra de cálculo. | FATO sobre os dados; regra DESCONHECIDA |
| `ajuste_custo_disp_gerador_brl` | `INT64` | Ajuste monetário | Valor rotulado como ajuste de custo de disponibilidade do gerador. Todos os valores são zero e a view não utiliza o campo. | FATO sobre os dados; regra DESCONHECIDA |
| `desconto_gerador_brl_per_k_wh` | `FLOAT64` | Valor unitário | Desconto do gerador expresso em reais por kWh. Em 2.032 linhas equivale, com tolerância mínima, a `tarifa_de_saida × desconto_gerador_percentage`; há 63 exceções. | FATO sobre a relação observada; regra completa DESCONHECIDA |
| `etapa` | `STRING` | Estado de processo | Etapa operacional com três valores observados: enviada, não enviada e não enviada com crédito a considerar. Possui relação quase determinística com a existência de créditos faturados e de cobrança. | FATO funcional |
| `status` | `STRING` | Status operacional | Resultado detalhado do processamento da unidade no mês, incluindo sucesso, não compensação, inatividade, cancelamento e churn. | FATO funcional |
| `excecoes` | `STRING` | Regra ou anotação de exceção | Texto livre com exceções como baixa renda, cancelamentos, energia de outras fontes e ajustes de cobrança. O hífen `-` representa ausência aparente de exceção. | FATO sobre o conteúdo; origem e governança DESCONHECIDAS |
| `_ingested_at` | `TIMESTAMP` | Metadado técnico | Momento em que o registro foi carregado na camada RAW do BigQuery. Não existe no SQLite original. | FATO |

Os nomes usam o sufixo `_k_wh`, mas a unidade convencional é `kWh`. Campos de
competência permanecem como `STRING` na RAW, e percentuais são armazenados como
frações decimais: por exemplo, `0.15` representa 15%.

## Granularidade

### Grain funcional

> **Uma linha representa uma unidade consumidora em um mês de referência.**

Representação completa:

```text
numero_instalacao
+ mes_referencia
→ usina, gerador e distribuidora associados
→ saldo e movimentos de créditos
→ valores econômicos
→ etapa, status e exceções
```

### Validação do grain

| Teste | Resultado |
|---|---:|
| Total de linhas | 2.095 |
| Combinações distintas `numero_instalacao + mes_referencia` | 2.095 |
| Grupos duplicados nessa combinação | 0 |
| Instalações distintas | 709 |
| Componentes da chave com NULL | 0 |

`numero_instalacao` sozinho não é chave, porque a mesma unidade reaparece em
competências diferentes.

## Chaves candidatas

Não existe chave primária declarada no schema da fonte.

| Chave candidata | Única? | Nullable nos dados? | Avaliação |
|---|---:|---:|---|
| `numero_instalacao` | Não — 709 valores em 2.095 linhas | Não | Identifica a unidade, mas não o snapshot mensal |
| `numero_instalacao + mes_referencia` | Sim — 2.095 de 2.095 | Não | Melhor chave candidata para o grain observado |
| `numero_instalacao + mes_referencia + usina` | Sim | Não | Inclui a alocação, mas é redundante no snapshot atual |
| `numero_instalacao + mes_referencia + usina + gerador + disco` | Sim | Não | Chave natural defensiva, porém mais ampla que o grain necessário |

A chave recomendada para representar o contrato descoberto é:

```text
numero_instalacao + mes_referencia
```

Essa recomendação deve ser revista caso uma unidade possa receber energia de
mais de uma usina na mesma competência. Esse comportamento não existe nos dados
observados.

## Temporalidade

Apesar de o texto do case mencionar um mês e sete geradores, a tabela física
contém três competências e nove geradores. O recorte de janeiro contém os sete
geradores de Gerador2 a Gerador8.

| Competência | Linhas | Unidades consumidoras | Usinas | Geradores |
|---|---:|---:|---:|---:|
| `2025-01-01` | 695 | 695 | 31 | 7 |
| `2025-02-01` | 698 | 698 | 32 | 8 |
| `2025-03-01` | 702 | 702 | 30 | 9 |

Presença das 709 instalações:

| Meses presentes | Instalações |
|---:|---:|
| 1 | 11 |
| 2 | 10 |
| 3 | 688 |

### Continuidade dos saldos

Foram encontradas 693 instalações comuns entre janeiro e fevereiro e outras
693 entre fevereiro e março. Em todas as 1.386 transições:

```text
saldo_eop_k_wh do mês anterior
= saldo_bop_k_wh do mês seguinte
```

Essa continuidade é a principal evidência para interpretar BOP e EOP como
saldo inicial e saldo final.

### Mudança de usina

- 76 instalações mudam de `usina` entre os meses disponíveis;
- nenhuma instalação muda de `gerador`;
- nenhuma instalação muda de `disco`.

**FATO:** o vínculo instalação–usina é temporal.

**HIPÓTESE:** as mudanças podem representar realocação de clientes entre usinas
do mesmo gerador. A causa operacional não está descrita na fonte.

## Movimentação dos créditos de energia

### Equação de saldo candidata

A relação que melhor reconcilia os dados é:

```text
saldo_eop_k_wh
≈ saldo_bop_k_wh
  + creditos_recebidos_no_mes_k_wh
  + creditos_recebidos_de_meses_anteriores_k_wh
  - creditos_compensados_do_mes_k_wh
  - creditos_compensados_de_meses_anteriores_k_wh
```

Resultados:

- igualdade exata em 2.041 linhas;
- igualdade com tolerância de 0,02 kWh em 2.042 linhas;
- 53 linhas não reconciliadas dentro dessa tolerância;
- `creditos_recebidos_de_meses_anteriores_k_wh` é sempre zero.

Portanto, a equação é uma regra observada majoritária, não um contrato de
negócio integralmente provado.

### Compensação e faturamento

A seguinte identidade é verdadeira em 2.089 das 2.095 linhas:

```text
creditos_faturados_k_wh
= creditos_compensados_do_mes_k_wh
  + creditos_compensados_de_meses_anteriores_k_wh
```

As 6 exceções possuem `status = 'Churn'`, créditos faturados iguais a zero e
valores de compensação ainda registrados. Isso indica tratamento específico de
encerramento, mas a regra não deve ser inferida sem documentação.

### Comportamento de `churn_k_wh`

- 2.086 linhas possuem churn igual a zero;
- 9 linhas possuem churn positivo;
- nas 9 linhas, `churn_k_wh = saldo_eop_k_wh` exatamente.

O campo parece classificar o saldo final afetado por churn; ele não deve ser
subtraído novamente na equação de saldo sem uma regra explícita.

### Valores negativos

Existem 51 registros negativos em
`creditos_compensados_do_mes_k_wh`, variando de `-0,02` a `-12.673,98` kWh.
Eles podem representar estorno ou ajuste, mas essa interpretação permanece uma
**HIPÓTESE**.

## Componentes econômicos

### Perfil resumido

| Campo | Mínimo | Máximo | Observação |
|---|---:|---:|---|
| `saldo_bop_k_wh` | 0 | 63.321,67 | 270 zeros |
| `saldo_eop_k_wh` | 0 | 96.333,75 | 223 zeros |
| `churn_k_wh` | 0 | 12.529,29 | 9 valores positivos |
| `creditos_recebidos_no_mes_k_wh` | 0 | 88.160,36 | 92 zeros |
| `creditos_recebidos_de_meses_anteriores_k_wh` | 0 | 0 | Coluna constante |
| `creditos_faturados_k_wh` | 0 | 38.060 | 91 zeros |
| `creditos_compensados_do_mes_k_wh` | -12.673,98 | 38.060 | 51 negativos |
| `creditos_compensados_de_meses_anteriores_k_wh` | 0 | 13.595,98 | 1.189 zeros |
| `desconto_cliente_percentage` | 5% | 35% | 11 valores distintos |
| `desconto_gerador_percentage` | 5% | 25% | 9 valores distintos |
| `gmv_real_oficial_brl` | R$ 0 | R$ 24.294,59747 | 91 zeros |
| `gmv_gerador_brl` | R$ 0 | R$ 29.326,66699 | 91 zeros |
| `take_rate_lemon_brl` | R$ 0 | R$ 3.812,466708 | 884 zeros |
| `tarifa_de_saida_brl_per_k_wh` | R$ 0/kWh | R$ 1,022791513/kWh | 19 valores distintos |
| `pis_per_cofins_nao_compensado_lemon_brl_k_wh` | R$ 0/kWh | R$ 0,134157452/kWh | 91 zeros |
| `icms_nao_compensado_lemon_brl_per_k_wh` | 0 | 0 | Coluna constante |
| `ajuste_custo_disp_gerador_brl` | 0 | 0 | Coluna constante |
| `desconto_gerador_brl_per_k_wh` | R$ 0/kWh | R$ 0,255697878/kWh | 91 zeros |

### Fórmulas candidatas observadas

Para as 2.004 linhas com créditos faturados positivos, esta relação reconcilia
2.001 linhas com diferença inferior a R$ 0,02:

```text
gmv_real_oficial_brl
≈ creditos_faturados_k_wh
  × (
      tarifa_de_saida_brl_per_k_wh
      × (1 - desconto_cliente_percentage)
      - pis_per_cofins_nao_compensado_lemon_brl_k_wh
      - icms_nao_compensado_lemon_brl_per_k_wh
    )
```

Há três exceções materiais; portanto, essa é uma fórmula candidata e não uma
regra universal.

Para `gmv_gerador_brl`, uma fórmula semelhante usando
`desconto_gerador_brl_per_k_wh` reconcilia 1.941 das 2.004 linhas dentro de
R$ 0,02. As 63 exceções incluem principalmente linhas de baixa renda e alguns
ajustes não identificados. Isso mostra que o cálculo possui tratamentos que não
estão expressos apenas nas colunas percentuais.

`take_rate_lemon_brl` não pôde ser reproduzido de forma confiável como simples
diferença entre os dois GMVs ou como produto do spread entre os percentuais.

### Dois conceitos diferentes de take rate

```text
energy_clients.take_rate_lemon_brl
    = valor monetário armazenado por unidade consumidora

energy_generator_take_rates.tr_percentual
    = percentual selecionado por faixa de desempenho da usina
```

A `generator_report` ignora o primeiro e utiliza o segundo para calcular os
repasses finais. Eles não devem ser tratados como o mesmo atributo.

## Etapa, status e exceções

### Etapa

| Etapa | Linhas | Créditos faturados iguais a zero |
|---|---:|---:|
| `Enviada` | 2.003 | 0 |
| `Não Enviada` | 91 | 91 |
| `Não enviada com crédito a considerar` | 1 | 0 |

Isso comprova forte relação entre `etapa` e geração de faturamento, mas não
define para qual sistema ou processo o registro foi enviado.

### Status

| Status | Linhas |
|---|---:|
| `OK - Automática` | 1.772 |
| `OK` | 231 |
| `Não compensou - Alocação zerada - Compensou todo saldo` | 38 |
| `Não compensou - Sem consumo compensável - Consumo zerado ou menor que disponibilidade` | 21 |
| `Inativo - UC com pendências na distribuidora` | 10 |
| `Não compensou - Sem consumo compensável - Compensou somente placas` | 8 |
| `Churn` | 6 |
| `Em cancelamento - Energia de outra empresa de GD` | 4 |
| `Inativo - Cliente esperando finalizar saldo de concorrente` | 3 |
| `Em cancelamento - Energia de placas` | 1 |
| `Regra de negócio - Valor GMV abaixo do mínimo para faturar` | 1 |

Os valores misturam resultado técnico, etapa de relacionamento, causa de
inatividade e regra de faturamento. Portanto, `status` não representa uma única
máquina de estados claramente normalizada.

### Exceções

Foram encontrados 90 textos distintos. Famílias observadas, que podem se
sobrepor:

| Família textual | Linhas |
|---|---:|
| Sem exceção aparente (`-`) | 1.793 |
| Cancelamento | 251 |
| Energia de outras fontes | 77 |
| Baixa renda | 45 |
| Ajuste de cobrança | 3 |

O campo mistura categorias, datas e valores monetários em texto livre. Algumas
linhas possuem múltiplas exceções separadas por `|`. Essa estrutura permite
leitura humana, mas não define regras estruturadas ou prioridades entre elas.

## Relacionamentos essenciais

### Unidade consumidora e financeiro

Relacionamento confirmado no SQL:

```text
energy_clients.numero_instalacao
+ energy_clients.mes_referencia
        ↓
finance_charges.disco_consumer_unit_id
+ finance_charges.reference_month
```

| Evidência | Resultado |
|---|---:|
| Chaves de cobrança | 2.000 |
| Chaves de cobrança únicas | 2.000 |
| Linhas de cliente com exatamente uma cobrança | 2.000 |
| Linhas de cliente sem cobrança | 95 |
| Cobranças órfãs em relação a `energy_clients` | 0 |

As demais entidades financeiras são alcançadas por `finance_relations`, que
conecta cobranças, billings, boletos e PIX conforme o modelo de grafo descrito
no case.

### Unidade consumidora e usina

O relacionamento mensal observado é:

```text
muitas unidades consumidoras
→ uma usina na competência
```

Em janeiro:

- 695 linhas existem em `energy_clients`;
- 473 encontram a mesma combinação de gerador, usina, distribuidora e mês em
  `energy_farms`;
- 222 pertencem a oito usinas ausentes de `energy_farms`;
- as oito usinas ausentes são Usina6, Usina7, Usina14, Usina15, Usina16,
  Usina17, Usina32 e Usina33, todas associadas ao Gerador6.

Todas as 23 usinas existentes em `energy_farms` possuem ao menos uma unidade
consumidora correspondente.

### Unidade consumidora e configuração de take rate

Todas as 2.095 linhas encontram uma configuração temporal válida em
`energy_generator_take_rates` por:

```text
gerador + disco + mes_referencia
```

A seleção da faixa percentual não ocorre diretamente por cliente. A view
primeiro agrega os indicadores no nível da usina e depois seleciona a faixa de
take rate aplicável ao desempenho da usina.

## Papel na `generator_report`

### Campos que afetam o resultado

| Campo | Uso atual |
|---|---|
| `numero_instalacao` | Join com o financeiro |
| `mes_referencia` | Join temporal e agregações |
| `usina` | Agregação e relacionamento com geração |
| `gerador` | Identificação do parceiro e take rate |
| `disco` | Identificação e relacionamento com take rate |
| `creditos_recebidos_no_mes_k_wh` | Soma por usina e comparação com créditos injetados |
| `creditos_faturados_k_wh` | Desempenho, faturamento e créditos pagos |
| `gmv_gerador_brl` | Valores de cobrança e liquidação atribuídos ao gerador |

### Campos selecionados, mas descartados antes do resultado

A CTE `clients` carrega os campos abaixo, porém nenhuma CTE posterior os usa
para cálculo, join ou filtro final:

```text
saldo_bop_k_wh
saldo_eop_k_wh
churn_k_wh
creditos_recebidos_de_meses_anteriores_k_wh
desconto_gerador_percentage
gmv_real_oficial_brl
take_rate_lemon_brl
tarifa_de_saida_brl_per_k_wh
pis_per_cofins_nao_compensado_lemon_brl_k_wh
icms_nao_compensado_lemon_brl_per_k_wh
ajuste_custo_disp_gerador_brl
desconto_gerador_brl_per_k_wh
etapa
status
excecoes
```

Consequência importante:

> A view não aplica nenhuma regra baseada em `etapa`, `status` ou `excecoes`,
> embora carregue esses campos no início do SQL.

Isso confirma que as exceções operacionais não são automatizadas pela
`generator_report` atual.

### Campos nem sequer selecionados pela CTE `clients`

```text
creditos_compensados_do_mes_k_wh
creditos_compensados_de_meses_anteriores_k_wh
desconto_cliente_percentage
```

### Resumo do fluxo dentro da view

```text
energy_clients
    ├─ numero_instalacao + mes_referencia ─► dados financeiros
    ├─ usina + mês ─► soma de créditos recebidos e faturados
    ├─ gmv_gerador_brl ─► agregações financeiras do gerador
    └─ métricas agregadas ─► desempenho da usina ─► faixa de take rate
```

## Achados essenciais

### Confirmados

- O grain é unidade consumidora × mês.
- A chave `numero_instalacao + mes_referencia` é completa, única e não nula.
- BOP e EOP formam uma cadeia mensal perfeitamente contínua para as unidades
  presentes em meses consecutivos.
- A instalação pode mudar de usina, mas não foi observada mudança de gerador ou
  distribuidora.
- Créditos faturados reconciliam as duas origens de compensação em 2.089 de
  2.095 linhas.
- As seis divergências dessa reconciliação são linhas de churn.
- As nove linhas com `churn_k_wh > 0` repetem exatamente o saldo EOP.
- A tabela possui três meses e nove geradores; janeiro possui sete geradores.
- `etapa`, `status` e `excecoes` não influenciam a view atual.
- `take_rate_lemon_brl` não é o take rate percentual usado no repasse final.

### Hipóteses ainda válidas

- `numero_instalacao` é um hash ou identificador pseudonimizado de unidade
  consumidora.
- Mudanças de usina representam realocação mensal de clientes dentro do mesmo
  gerador.
- Valores negativos de compensação representam estornos ou ajustes.
- `churn_k_wh` classifica o saldo final associado à saída do cliente.
- `take_rate_lemon_brl` representa alguma forma de receita ou margem monetária
  da Lemon no nível da unidade.

## Questões em aberto

1. `numero_instalacao` identifica uma unidade consumidora, um contrato ou um
   cliente? Um cliente pode possuir várias instalações?
2. A tabela consolida as planilhas “Guias” e “Generalistas” mencionadas no
   whiteboard? Como identificar a origem de cada linha?
3. Uma instalação pode receber créditos de mais de uma usina no mesmo mês?
4. Qual evento operacional produz uma mudança de usina?
5. “Créditos recebidos de meses anteriores” representa data de alocação, origem
   do crédito ou reprocessamento?
6. “Créditos compensados do mês” classifica a origem do crédito ou o mês do
   consumo?
7. O que explica as 53 linhas que não reconciliam a equação majoritária de
   saldo?
8. Valores negativos de compensação são estornos, correções ou erros?
9. Qual é a definição oficial de GMV neste produto?
10. Qual é a fórmula oficial de `gmv_real_oficial_brl`, `gmv_gerador_brl` e
    `take_rate_lemon_brl`?
11. Quais tratamentos especiais são aplicados às linhas de baixa renda?
12. Para onde a etapa `Enviada` envia a informação?
13. Qual a precedência quando `excecoes` contém várias regras separadas por
    `|`?
14. Por que três linhas com etapa enviada não possuem cobrança?
15. Por que existem oito usinas do Gerador6 em `energy_clients` que não existem
    em `energy_farms` no mesmo mês?
16. O campo `status` representa estado atual, resultado do processamento mensal
    ou ambos?

## Resumo do contrato descoberto

```text
Tabela:
  raw.energy_clients

Entidade principal:
  unidade consumidora de energia

Grain:
  uma unidade consumidora em um mês de referência

Chave candidata:
  numero_instalacao + mes_referencia

Relacionamentos principais:
  unidade consumidora-mês → usina e gerador
  unidade consumidora-mês → cobrança financeira
  gerador + distribuidora + mês → configuração de take rate

Movimentos de energia:
  saldo inicial
  créditos recebidos
  créditos compensados
  créditos faturados
  saldo final
  saldo classificado como churn

Componentes econômicos:
  descontos do cliente e do gerador
  GMV real oficial
  GMV do gerador
  take rate monetário da Lemon
  tarifa de saída
  tributos não compensados
  ajustes

Estado operacional:
  etapa
  status
  exceções em texto livre
```
