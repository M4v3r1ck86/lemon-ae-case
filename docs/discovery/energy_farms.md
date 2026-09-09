# Data Discovery — `energy_farms`

## Visão geral

| Atributo | Valor |
|---|---|
| Tabela analisada | `raw.energy_farms` |
| Tabela na fonte SQLite | `energy_farms` |
| Domínio | Energia |
| Tipo de dado | Registro operacional e financeiro mensal de usinas |
| Quantidade observada | 23 registros |
| Usinas observadas | 23 |
| Geradores observados | 7 |
| Distribuidoras observadas | 1 (`CEMIG`) |
| Meses de referência observados | 1 (`2025-01-01`) |
| Estado do discovery | Validado para o snapshot atual |

Este documento registra o entendimento consolidado da tabela `energy_farms`,
obtido por meio da análise do schema, do conteúdo da tabela, de seus
relacionamentos com as demais fontes e de evidências semânticas encontradas no
SQL original da view `generator_report`.

As conclusões são classificadas como:

- **FATO:** comprovado pelo schema, pelos dados ou pelo SQL existente;
- **HIPÓTESE:** interpretação consistente, mas ainda sem definição oficial;
- **DESCONHECIDO:** não há evidência suficiente para determinar o significado.

### Escopo do documento

Este documento descreve somente a tabela, seus campos e os conceitos
identificados nos dados. Ele não descreve a arquitetura interna da Lemon nem
propõe a arquitetura da solução no GCP.

O SQL da `generator_report` é utilizado apenas quando fornece evidência para o
significado ou o uso de um campo. A engenharia reversa completa da view será
realizada separadamente, depois da conclusão do discovery das oito tabelas.

## Descrição funcional

A `energy_farms` reúne informações mensais de usinas de energia associadas a
um gerador e uma distribuidora. Os registros combinam informações de:

1. identificação da usina, do gerador, da distribuidora e do mês;
2. geração prevista, geração realizada e créditos injetados;
3. valor rotulado como TUSD;
4. competência e valor da TUSD descontada do repasse do gerador;
5. aluguel de imóveis;
6. aluguel de equipamentos;
7. custo de operação e manutenção.

### Estado do mundo representado

> Uma linha representa a situação operacional e financeira de uma usina em um
> mês de referência, associada a um gerador e uma distribuidora.

A tabela não parece ser apenas um cadastro de usinas, pois seus valores de
energia, custos e mês de referência podem variar ao longo do tempo. Entretanto,
o snapshot analisado contém somente janeiro de 2025; por isso, a repetição de
uma mesma usina em diferentes meses ainda não pôde ser observada diretamente.

## Entidades e conceitos representados

| Conceito | Representação na tabela | Entendimento atual |
|---|---|---|
| Gerador | `gerador` | Entidade associada a uma ou mais usinas. A natureza jurídica ou contratual dessa associação é desconhecida. |
| Usina | `usina` | Unidade de geração à qual pertencem as métricas de energia e os valores do registro. | 
| Distribuidora | `disco` | Provável distribuidora responsável pela área ou medição da usina. O único valor observado é `CEMIG`. |
| Competência operacional | `mes_referencia` | Mês ao qual pertencem as métricas de geração e créditos da linha. |
| Energia gerada | `geracao_realizada_gerador_k_wh` | Quantidade de energia registrada como realizada pelo gerador. A view sugere que pode ser uma medição de inversor. |
| Energia injetada | `creditos_injetados_k_wh` | Quantidade registrada como créditos injetados na rede da distribuidora. Não é equivalente à geração realizada. |
| Geração contratada | `geracao_prevista_no_contrato_k_wh` | Referência contratual de geração utilizada para comparar a entrega da usina. |
| TUSD registrada | `tusd_brl` | Valor monetário rotulado como TUSD. Sua composição e origem contábil não aparecem na fonte nem na view. |
| Competência da dedução | `mes_de_desconto_tusd_gerador` | Mês usado pela view para contabilizar `tusd_descontada_gerador`. |
| TUSD deduzida do repasse | `tusd_descontada_gerador` | Valor que a view subtrai do repasse do gerador. Não é sinônimo comprovado de desconto tarifário. |
| Aluguel de imóvel | `aluguel_imoveis_brl` | Valor rotulado como aluguel de imóvel; responsável econômico e regra contratual desconhecidos. |
| Aluguel de equipamento | `aluguel_equipamento_brl` | Valor rotulado como aluguel de equipamento; responsável econômico e regra contratual desconhecidos. |
| Operação e manutenção | `operations_and_maintenance_cost_brl` | Campo destinado a custo de O&M; todas as linhas estão vazias no snapshot. |

## Schema e dicionário de campos

| Campo | Tipo na RAW | Nullable | Papel | Definição | Classificação |
|---|---|---:|---|---|---|
| `gerador` | `STRING` | Sim | Entidade / relacionamento | Nome ou código legível do gerador associado à usina. Um gerador pode estar associado a várias usinas. | FATO |
| `usina` | `STRING` | Sim | Entidade / business key | Nome ou código legível da unidade de geração. É única entre as 23 linhas do snapshot. | FATO no snapshot |
| `disco` | `STRING` | Sim | Entidade / relacionamento | Provável abreviação de distribuidora. O valor observado é `CEMIG`. | HIPÓTESE alta |
| `mes_referencia` | `STRING` | Sim | Data de referência | Competência usada pela view para relacionar a linha às informações mensais de clientes e desempenho. Todas as linhas contêm janeiro de 2025. Se corresponde exatamente ao mês físico de geração ainda não está documentado. | FATO sobre valor e uso; semântica de origem DESCONHECIDA |
| `creditos_injetados_k_wh` | `INT64` | Sim | Medida de energia | Quantidade registrada pela fonte como créditos injetados. A view trata o campo como energia disponibilizada pela usina e usa o termo `disco` na comparação com a geração realizada. A origem exata do medidor ainda não foi comprovada. | FATO funcional; origem da medição é HIPÓTESE |
| `geracao_prevista_no_contrato_k_wh` | `FLOAT64` | Sim | Medida de energia | Quantidade de geração prevista no contrato para a usina. É utilizada como limite contratual no cálculo atual. | FATO funcional |
| `geracao_realizada_gerador_k_wh` | `FLOAT64` | Sim | Medida de energia | Quantidade de geração registrada como realizada pelo gerador. A view compara esse valor com os créditos injetados e chama a razão de `disco_vs_inversor`, indício de medição no inversor. | FATO funcional; medição no inversor é HIPÓTESE |
| `tusd_brl` | `FLOAT64` | Sim | Valor monetário | Valor monetário rotulado como TUSD. Não é utilizado pela `generator_report`; sua base de cálculo, tarifa unitária e composição não existem nas colunas disponíveis. | DESCONHECIDO parcial |
| `mes_de_desconto_tusd_gerador` | `STRING` | Sim | Data de competência financeira | Competência para a qual a view transfere e agrega `tusd_descontada_gerador`. Pode ser diferente de `mes_referencia`. A causa dessa defasagem não está documentada. | FATO sobre o uso; motivo DESCONHECIDO |
| `aluguel_imoveis_brl` | `FLOAT64` | Sim | Valor monetário | Valor rotulado como aluguel de imóvel da usina. Não é utilizado pela view; não se sabe de quem é a obrigação contratual. | FATO sobre o conteúdo; regra DESCONHECIDA |
| `aluguel_equipamento_brl` | `FLOAT64` | Sim | Valor monetário | Valor rotulado como aluguel de equipamento da usina. Não é utilizado pela view; não se sabe de quem é a obrigação contratual. | FATO sobre o conteúdo; regra DESCONHECIDA |
| `operations_and_maintenance_cost_brl` | `STRING` | Sim | Valor monetário esperado | Campo destinado a custo de operação e manutenção. Todos os registros contêm string vazia, portanto não há valores monetários analisáveis. | FATO sobre os dados; semântica contratual DESCONHECIDA |
| `tusd_descontada_gerador` | `FLOAT64` | Sim | Valor monetário | Valor subtraído do repasse do gerador no SQL atual. O nome indica TUSD descontada **do gerador**, mas os dados não comprovam que seja um desconto aplicado sobre `tusd_brl`. | FATO funcional; fórmula DESCONHECIDA |
| `_ingested_at` | `TIMESTAMP` | Não | Metadado técnico | Momento em que o registro foi carregado na camada RAW do BigQuery. | FATO |

Os nomes físicos utilizam o sufixo `_k_wh`, mas a unidade correspondente é
quilowatt-hora, normalmente representada por `kWh`. O sufixo `_brl` identifica
valores monetários em reais.

Os campos `mes_referencia` e `mes_de_desconto_tusd_gerador` são `STRING` na
tabela analisada, embora representem semanticamente competências mensais.

## Conceitos de energia e reconciliação

Os três campos de energia não representam a mesma medida:

```text
geracao_prevista_no_contrato_k_wh
    = referência contratual

geracao_realizada_gerador_k_wh
    = energia registrada como gerada

creditos_injetados_k_wh
    = quantidade registrada como créditos injetados
```

No snapshot:

- em 18 usinas, a geração realizada é maior que os créditos injetados;
- em 3 usinas, os créditos injetados são maiores que a geração realizada;
- em 2 usinas, os valores são iguais;
- uma usina possui geração realizada e créditos injetados iguais a zero.

Essa diferença confirma que geração realizada e créditos injetados são
conceitos distintos. O alias `disco_vs_inversor`, encontrado no SQL existente,
sugere que os créditos injetados vêm da distribuidora e a geração realizada
vem do inversor, mas essa interpretação permanece uma **HIPÓTESE**.

### Exemplo: Gerador4 / Usina21

| Medida | Valor |
|---|---:|
| Geração prevista no contrato | 88.654,27712 kWh |
| Geração realizada | 94.555 kWh |
| Créditos injetados | 90.300 kWh |
| Realizada menos injetada | 4.255 kWh |
| Parcela da geração realizada registrada como injetada | aproximadamente 95,50% |

**FATO:** a linha registra uma diferença de 4.255 kWh entre geração realizada e
créditos injetados. A tabela não possui consumo auxiliar, perdas, leituras de
medidor, cortes horários, rejeições da distribuidora ou saldo de energia da
usina. Portanto, ela não permite determinar para onde foi essa diferença.

Explicações possíveis, ainda como **HIPÓTESES**, incluem:

- consumo interno ou auxiliar da própria usina antes do ponto de medição;
- perdas elétricas entre o inversor e o medidor da distribuidora;
- diferenças de período de leitura ou fechamento;
- ajustes ou validações da distribuidora;
- diferença de origem, precisão ou arredondamento entre medidores.

Não é correto concluir que os 4.255 kWh viraram saldo, foram perdidos ou foram
destinados a clientes sem outra fonte de evidência. No Sistema de Compensação
de Energia Elétrica, é a energia efetivamente injetada e reconhecida pela
distribuidora que pode ser compensada ou convertida em crédito. Eventual
excedente pode ser destinado a outras unidades participantes ou permanecer
como crédito para meses seguintes, conforme a modalidade. Esse contexto
regulatório não explica, por si só, a diferença entre os dois medidores desta
linha. Fonte externa: [ANEEL — Micro e Minigeração
Distribuída](https://www.gov.br/aneel/pt-br/assuntos/geracao-distribuida).

## Conceitos de TUSD

TUSD significa **Tarifa de Uso do Sistema de Distribuição** e está associada à
remuneração do serviço e da infraestrutura de distribuição. A ANEEL homologa
tarifas por distribuidora e seus valores dependem do enquadramento tarifário e
dos componentes aplicáveis. Fontes externas: [ANEEL —
Tarifas](https://www.gov.br/aneel/pt-br/assuntos/tarifas) e [Tarifas e
informações econômico-financeiras](https://www.gov.br/aneel/pt-br/centrais-de-conteudos/relatorios-e-indicadores/tarifas-e-informacoes-economico-financeiras).

Essa definição regulatória dá contexto ao nome do campo, mas não comprova a
regra usada pela Lemon para preencher os valores desta tabela.

A tabela contém dois valores diferentes:

```text
tusd_brl
tusd_descontada_gerador
```

Eles não são equivalentes: nenhuma das 23 linhas apresenta os dois valores
iguais. A `generator_report` utiliza somente `tusd_descontada_gerador` e o
subtrai do repasse do gerador:

```text
repasse final do gerador =
    repasse do gerador antes da TUSD - tusd_descontada_gerador
```

Nesse contexto, "descontada" significa **deduzida do repasse**. Não há
evidência de que represente um desconto percentual concedido sobre
`tusd_brl`.

### A fórmula é recuperável pela tabela?

Não com as colunas disponíveis. O profiling encontrou:

- 22 linhas nas quais é possível dividir `tusd_brl` pelos créditos injetados;
- razão entre `tusd_brl` e créditos injetados variando de aproximadamente
  R$ 0,072766/kWh a R$ 0,122558/kWh;
- 21 razões distintas nessas 22 linhas;
- 10 usinas com o mesmo `tusd_brl` de R$ 16.095,84, apesar de possuírem entre
  131.600 e 221.200 kWh de créditos injetados;
- razão entre `tusd_descontada_gerador` e `tusd_brl` variando de 3,65% a
  102,59%;
- uma linha com `tusd_brl` nulo e `tusd_descontada_gerador` positivo;
- uma linha em que `tusd_descontada_gerador` é maior que `tusd_brl`.

Essas evidências descartam, para o conjunto observado, tanto uma tarifa única
do tipo `créditos injetados × constante` quanto um percentual único aplicado a
`tusd_brl`. Para reconstruir o cálculo seriam necessários, no mínimo, a regra
contratual da Lemon, a memória de cálculo ou fatura da distribuidora e os
atributos tarifários que não aparecem na tabela.

### Exemplos observados

| Linha | `tusd_brl` | `tusd_descontada_gerador` | Relação entre os valores |
|---|---:|---:|---:|
| Gerador4 / Usina21 | R$ 8.155,41 | R$ 3.591,913894 | 44,04% |
| Gerador2 / Usina1 | R$ 38.399,84 | R$ 5.185,261847 | 13,50% |

No caso da Usina21, `tusd_brl / creditos_injetados_k_wh` resulta em cerca de
R$ 0,090315/kWh. Na Usina1, o mesmo cálculo resulta em cerca de
R$ 0,098310/kWh. Essas contas são apenas testes de reconciliação e não devem
ser promovidas a fórmula de negócio.

## Granularidade

### Grain funcional

> **Uma linha representa uma usina em um mês de referência.**

Representação mais completa:

```text
usina
+ mês de referência
→ gerador e distribuidora associados
→ métricas mensais de energia
→ valores e competências financeiras
```

No snapshot atual, `usina` sozinho também é único, porque existe apenas um mês.
Isso não significa que `usina` será uma chave suficiente quando outros meses
forem adicionados.

Distribuição observada:

| Gerador | Quantidade de usinas |
|---|---:|
| Gerador2 | 1 |
| Gerador3 | 3 |
| Gerador4 | 12 |
| Gerador5 | 1 |
| Gerador6 | 4 |
| Gerador7 | 1 |
| Gerador8 | 1 |
| **Total** | **23** |

## Chaves

Não existe chave primária declarada no schema da fonte.

| Chave candidata | Única no snapshot? | Possui NULL? | Interpretação |
|---|---:|---:|---|
| `usina` | Sim — 23 de 23 | Não | Única somente porque o snapshot contém um mês |
| `usina + mes_referencia` | Sim — 23 de 23 | Não | Melhor chave candidata para o grain mensal |
| `gerador + usina + disco` | Sim — 23 de 23 | Não | Identifica a associação observada, mas não comporta histórico mensal |
| `gerador + usina + disco + mes_referencia` | Sim — 23 de 23 | Não | Chave natural completa e defensiva |

No snapshot, cada `usina` está associada a exatamente um `gerador` e uma
`disco`. Não foram encontradas duplicidades para a chave natural completa.

A chave recomendada para representar o grain descoberto é:

```text
usina + mes_referencia
```

Essa recomendação depende da hipótese de que o código de usina seja globalmente
único. Caso a mesma identificação possa existir em distribuidoras diferentes,
a chave deverá incluir `disco`.

## Perfil dos valores

| Campo | Mínimo | Máximo | Observação |
|---|---:|---:|---|
| `creditos_injetados_k_wh` | 0 | 473.200 | 22 valores distintos |
| `geracao_prevista_no_contrato_k_wh` | 88.654,27712 | 519.900 | Todos os registros positivos |
| `geracao_realizada_gerador_k_wh` | 0 | 477.265 | Uma usina com valor zero |
| `tusd_brl` | 8.155,41 | 46.138,85 | Um registro nulo |
| `tusd_descontada_gerador` | 587,7193269 | 29.218,16528 | Preenchido nas 23 linhas |
| `aluguel_imoveis_brl` | 750,00 | 6.595,87 | 18 preenchidos e 5 nulos |
| `aluguel_equipamento_brl` | 66.941,06 | 84.643,70 | 5 preenchidos e 18 nulos |
| `operations_and_maintenance_cost_brl` | — | — | 23 strings vazias |

Combinações de aluguel observadas:

- 5 usinas possuem aluguel de imóvel e de equipamento;
- 13 possuem somente aluguel de imóvel;
- nenhuma possui somente aluguel de equipamento;
- 5 não possuem nenhum dos dois valores.

A presença ou ausência desses custos pode representar diferentes modelos
contratuais, mas essa interpretação ainda não foi comprovada.

## Temporalidade

A tabela possui duas competências distintas.

### Competência operacional

`mes_referencia` é a competência usada pelo SQL para relacionar as métricas de
geração e créditos às demais tabelas. Todas as 23 linhas contêm:

```text
2025-01-01
```

### Competência do desconto de TUSD

`mes_de_desconto_tusd_gerador` informa o mês ao qual a dedução é associada pelo
SQL atual:

| Mês do desconto | Geradores | Usinas |
|---|---|---:|
| `2024-12-01` | Gerador2 e Gerador4 | 13 |
| `2025-01-01` | Gerador3, Gerador5, Gerador6, Gerador7 e Gerador8 | 10 |

Portanto, a view pode ler uma linha cuja `mes_referencia` é janeiro e
contabilizar sua `tusd_descontada_gerador` em dezembro ou janeiro. Ela faz isso
ao renomear `mes_de_desconto_tusd_gerador` para `mes_referencia` na CTE `tusd`
e, em seguida, usar `usina + mes_referencia` nos joins financeiros.

**FATO:** Gerador2 e Gerador4 possuem linhas operacionais de janeiro cuja TUSD
descontada é direcionada para dezembro de 2024.

**DESCONHECIDO:** isso pode representar ajuste retroativo, competência de uma
fatura, defasagem operacional, regra contratual manual ou erro de dados/SQL. A
tabela não permite escolher entre essas explicações. Portanto, o campo não deve
ser interpretado como "mês em que a energia foi gerada".

## Relacionamentos essenciais

### Gerador e usina

O relacionamento observado é:

```text
1 gerador
→ uma ou mais usinas
```

No sentido inverso, cada uma das 23 usinas está associada a somente um gerador
no snapshot. Não está confirmado se essa associação é imutável ao longo do
tempo.

### Usinas e clientes

A chave de relacionamento observada é:

```text
gerador + usina + disco + mes_referencia
```

Resultados do cruzamento:

- todas as 23 linhas de `energy_farms` possuem clientes correspondentes;
- as usinas possuem entre 4 e 124 clientes no mês;
- 473 registros de clientes de janeiro se relacionam com as 23 usinas;
- `energy_clients` contém 8 usinas adicionais de janeiro sem registro em
  `energy_farms`;
- essas 8 usinas pertencem ao Gerador6 e concentram 222 registros de clientes.

Usinas presentes em `energy_clients` e ausentes em `energy_farms`:

```text
Usina6
Usina7
Usina14
Usina15
Usina16
Usina17
Usina32
Usina33
```

Ainda não está confirmado se essas ausências representam recorte de escopo,
cadastro incompleto, ausência de geração ou outra regra de negócio.

### Usinas e configurações de take rate

Todas as 23 usinas encontram uma configuração temporalmente válida em
`energy_generator_take_rates` por meio de:

```text
gerador + disco + mes_referencia
```

O relacionamento não utiliza um identificador técnico de usina ou gerador.

## Evidências complementares no SQL existente

Sem realizar ainda a engenharia reversa completa da `generator_report`, o SQL
permite confirmar os seguintes usos dos campos:

```text
minima_injecao_k_wh =
    mínimo entre créditos injetados e geração prevista no contrato
```

Esse valor é utilizado como denominador de indicadores de preenchimento e
desempenho.

O SQL também calcula comparações entre:

- créditos injetados e geração prevista;
- créditos injetados e geração realizada;
- créditos recebidos pelos clientes e créditos injetados;
- créditos faturados e créditos recebidos;
- créditos pagos e a referência mínima de injeção.

Para a TUSD, a view:

1. considera somente as linhas operacionais de janeiro de 2025;
2. utiliza `mes_de_desconto_tusd_gerador` como competência financeira;
3. soma `tusd_descontada_gerador` por usina e competência;
4. usa essa CTE como tabela inicial da `base`;
5. relaciona liquidações por `usina + mes_referencia`;
6. subtrai a TUSD descontada do repasse do gerador;
7. elimina no filtro final as linhas em que o gerador vindo das liquidações é
   nulo.

Essa sequência explica um comportamento central do relatório: as linhas de
Gerador2 e Gerador4, embora tenham `mes_referencia = 2025-01-01` na fonte,
entram na CTE `tusd` com `mes_referencia = 2024-12-01`. Se não encontrarem a
liquidação da mesma usina nessa competência, o gerador fica nulo e a linha é
removida pelo filtro final. Já Gerador3, Gerador5, Gerador6, Gerador7 e
Gerador8 permanecem em janeiro. Esse é um **FATO sobre o SQL atual**, não uma
regra de negócio validada.

Os campos `tusd_brl`, `aluguel_imoveis_brl`,
`aluguel_equipamento_brl` e `operations_and_maintenance_cost_brl` não são
utilizados no resultado atual da view.

## Definições ainda pendentes

As seguintes questões não devem ser transformadas em regras sem evidência
adicional:

1. `farm` e `usina` são sinônimos no modelo de negócio?
2. O gerador é proprietário, operador, parceiro ou apenas entidade associada à
   usina?
3. Qual é a fonte e o ponto de medição de `creditos_injetados_k_wh`?
4. `geracao_realizada_gerador_k_wh` corresponde à medição do inversor?
5. O que diferencia contabilmente `tusd_brl` de
   `tusd_descontada_gerador`?
6. Como `tusd_brl` é calculado e qual documento permite reconciliá-lo?
7. Como `tusd_descontada_gerador` é calculado e por que pode superar
   `tusd_brl`?
8. Por que uma dedução proveniente de uma linha de janeiro é contabilizada em
   dezembro para Gerador2 e Gerador4?
9. String vazia em `operations_and_maintenance_cost_brl` significa ausência de
   custo, dado indisponível ou custo não aplicável?
10. Os campos de aluguel representam custos da Lemon, do gerador ou da usina?
11. Por que oito usinas com clientes em janeiro não existem em
    `energy_farms`?
12. O código de `usina` é globalmente único ou depende da distribuidora?
13. A associação entre usina e gerador pode mudar ao longo do tempo?
14. Quais componentes explicam a diferença entre geração realizada e créditos
    injetados em cada usina?

## Resumo do contrato descoberto

```text
Tabela:
  raw.energy_farms

Entidade principal:
  usina de energia

Grain:
  uma usina em um mês de referência

Chave candidata:
  usina + mes_referencia

Relacionamentos principais:
  gerador → usina
  usina-mês → clientes
  gerador + distribuidora + mês → configuração de take rate

Métricas principais:
  geração prevista
  geração realizada
  créditos injetados

Valores financeiros:
  TUSD
  TUSD descontada do gerador
  aluguel de imóveis
  aluguel de equipamentos
  custo de operação e manutenção

Temporalidades:
  mês operacional da usina
  mês financeiro do desconto de TUSD
```
