# Data Discovery — `finance_charges`

## Visão geral

| Atributo | Valor observado |
|---|---|
| Tabela de origem | `raw.finance_charges` |
| Domínio | Financeiro |
| Tipo de dado | Cobrança mensal por unidade consumidora |
| Quantidade | 2.000 registros |
| Unidades consumidoras | 709 |
| Meses de referência | Janeiro, fevereiro e março de 2025 |
| Status | 1.872 `paid`; 128 `waitingPayment` |
| Distribuidora | `cemig` |
| Estado do discovery | Validado para o snapshot do case |

As consultas equivalentes em GoogleSQL estão em
[`finance_charges_discovery.sql`](finance_charges_discovery.sql).

Classificações utilizadas:

- **FATO:** demonstrado pelo schema, dados ou SQL da view;
- **HIPÓTESE:** interpretação provável, ainda não confirmada pelo negócio;
- **DESCONHECIDO:** evidência insuficiente.

## Descrição funcional

`finance_charges` registra a cobrança financeira de uma unidade consumidora em
um mês de referência. É a tabela que conecta o domínio financeiro ao cliente
por `disco_consumer_unit_id + reference_month`.

> **Uma linha representa uma cobrança mensal de uma assinatura/unidade
> consumidora, vinculada a um billing.**

O valor da charge, convertido de centavos para reais, reconcilia com
`energy_clients.gmv_real_oficial_brl` nas 2.000 linhas com diferença máxima de
aproximadamente meio centavo. Portanto, é **FATO** que `amount` materializa o
valor oficial cobrado ao cliente no conjunto analisado.

## Schema e dicionário de campos

| Campo | Tipo RAW | Papel | Definição baseada nas evidências | Classificação |
|---|---|---|---|---|
| `source` | `STRING` | Chave do grafo | Identificador completo do nó, sempre `charge#` + `charge_id`; utilizado como `target` em `finance_relations`. | FATO |
| `charge_id` | `STRING` | Identificador da cobrança | ID único sem o prefixo da entidade. Contém assinatura, mês e um sufixo técnico. | FATO estrutural |
| `create_at` | `STRING` | Data/hora de criação | Timestamp textual da criação da cobrança. | FATO |
| `payment_date` | `STRING` | Data de pagamento | Data usada pela `generator_report` como liquidação; vazia em 128 charges. | FATO |
| `amount` | `INT64` | Valor monetário | Valor da cobrança em centavos; reconcilia com o GMV oficial do cliente. | FATO |
| `amount_without_discounts` | `INT64` | Valor monetário | Valor anterior a descontos; igual a `amount` em todas as linhas. | FATO no snapshot |
| `temporary_discount_amount` | `INT64` | Ajuste monetário | Desconto temporário; sempre zero. | FATO sobre os dados; regra DESCONHECIDA |
| `billing_plan_id` | `STRING` | Identificador de plano | Identifica o plano de faturamento. Há 709 valores e um por unidade no snapshot. | FATO estrutural; semântica oficial DESCONHECIDA |
| `place_id` | `STRING` | Identificador de local | Identificador com correspondência 1:1 à unidade consumidora no snapshot. | FATO estrutural; nome de negócio é HIPÓTESE |
| `disco_consumer_unit_id` | `STRING` | Business key/FK | Identificador da instalação na distribuidora; corresponde a `energy_clients.numero_instalacao`. | FATO |
| `distribution_company` | `STRING` | Categoria | Distribuidora; todas as linhas contêm `cemig`. | FATO |
| `reference_month` | `STRING` | Competência | Mês de referência da cobrança; é parte do grain e do join com clientes. | FATO |
| `pipedrive_id` | `INT64` | Identificador externo | Possível identificador de negócio no Pipedrive. É único nas 2.000 linhas, mas o objeto de origem não foi informado. | HIPÓTESE alta |
| `product` | `STRING` | Produto | Valor constante `businessDistributedEnergyGeneration`. | FATO sobre o valor; tradução oficial DESCONHECIDA |
| `charge_provider_type` | `STRING` | Categoria | Tipo do provedor da cobrança; sempre `consortium`. | FATO |
| `status` | `STRING` | Status | Situação da charge: `paid` ou `waitingPayment`. | FATO |
| `subscriber_id` | `STRING` | Identificador de entidade | ID do assinante/entidade consumidora no backend; um por instalação. | FATO estrutural |
| `subscriber_type` | `STRING` | Categoria | Tipo do assinante; sempre `consumerUnit`. | FATO |
| `cancelled_at` | `STRING` | Data de cancelamento | Campo de cancelamento; vazio em todas as linhas. | FATO |
| `cancellation_reason` | `STRING` | Motivo de cancelamento | Vazio em todas as linhas. | FATO |
| `cancellation_type` | `STRING` | Categoria de cancelamento | Vazio em todas as linhas. | FATO |
| `cancelled_by` | `STRING` | Autor do cancelamento | Vazio em todas as linhas. | FATO |
| `cancellation_description` | `STRING` | Descrição | Vazio em todas as linhas. | FATO |
| `type` | `STRING` | Categoria de cobrança | Valor constante `anniversary`. A regra operacional desse tipo é desconhecida. | FATO sobre o valor; semântica DESCONHECIDA |
| `billing_id` | `STRING` | FK lógica | Identifica o billing relacionado. É igual a `billing_plan_id#reference_month`. | FATO |
| `subscription_id` | `STRING` | Identificador de assinatura | Há 709 valores, com correspondência 1:1 à unidade no snapshot. | FATO estrutural |
| `ingestion_time` | `STRING` | Timestamp técnico da origem | Momento de ingestão informado pela fonte/backend. | FATO técnico; sistema exato DESCONHECIDO |
| `_ingested_at` | `TIMESTAMP` | Metadado da plataforma | Momento da carga do snapshot para a RAW do BigQuery. | FATO |

## Granularidade e chaves

As seguintes combinações possuem 2.000 valores distintos:

- `source`;
- `charge_id`;
- `billing_id`;
- `disco_consumer_unit_id + reference_month`;
- `subscription_id + reference_month`;
- `billing_plan_id + reference_month`.

| Chave candidata | Única? | Observação |
|---|---:|---|
| `source` | Sim | Preferida para relações do grafo |
| `charge_id` | Sim | Identificador técnico sem prefixo |
| `disco_consumer_unit_id + reference_month` | Sim | Melhor chave de negócio observada |
| `billing_id` | Sim no snapshot | Pode deixar de ser 1:1 se um billing consolidar charges no futuro |

O grain comprovado é unidade consumidora × mês, mas a modelagem deve preservar
`charge_id`: a estrutura do grafo permite cardinalidades futuras diferentes.

## Perfil quantitativo

| Mês | Charges | Unidades | Pagas | Aguardando | Valor total |
|---|---:|---:|---:|---:|---:|
| 2025-01 | 676 | 676 | 627 | 49 | R$ 452.621,69 |
| 2025-02 | 663 | 663 | 621 | 42 | R$ 455.208,34 |
| 2025-03 | 661 | 661 | 624 | 37 | R$ 500.287,41 |

Perfil de `amount`:

- mínimo: R$ 2,37;
- média: R$ 704,06;
- máximo: R$ 24.294,60;
- total: R$ 1.408.117,44.

Não há desconto temporário no snapshot e não existem charges canceladas.

## Identidades da unidade

Para cada uma das 709 unidades consumidoras existe exatamente um:

- `place_id`;
- `subscriber_id`;
- `subscription_id`;
- `billing_plan_id`;
- `distribution_company`.

O relacionamento inverso também é 1:1 no snapshot. Isso comprova estabilidade
interna no período, mas não garante que esses identificadores sejam imutáveis
fora do recorte.

## Relacionamentos essenciais

| Origem | Destino | Cardinalidade observada | Evidência |
|---|---|---|---|
| Charge | `energy_clients` | 1:1 por instalação/mês | Todas as 2.000 charges encontram cliente |
| Charge | Billing | 1:1 | `billing_id`, valor, status e `place_id` coincidem |
| `finance_relations.target` | Charge | 1:1 | Há uma aresta charge para cada billing |
| Unidade | Place/subscriber/subscription/plan | 1:1 no snapshot | 709 mapeamentos estáveis |

As 95 linhas de `energy_clients` sem charge não são órfãs da tabela financeira:
o relacionamento é obrigatório da charge para o cliente, mas não do cliente
para a charge.

## Temporalidade e pagamento

`reference_month` é a competência de negócio. `create_at` registra criação,
`payment_date` registra a data de pagamento e `ingestion_time` registra o
momento técnico informado pela origem.

O status e a ausência de `payment_date` são consistentes: todas as 1.872 charges
pagas possuem data e as 128 aguardando pagamento não possuem.

Ao comparar com `billing_payment_date`, somente 717 pagamentos apresentam a
mesma data após conversão direta. A maioria das demais diferenças observáveis é
de um dia. Diferença de fuso ou convenção de fechamento é uma **HIPÓTESE**, não
um fato. A `generator_report` escolhe `finance_charges.payment_date`.

## Papel na `generator_report`

A tabela é a ponte semântica entre clientes e finanças. A view:

1. renomeia `source` para `charge_id`;
2. usa a aresta billing → charge de `finance_relations`;
3. utiliza `disco_consumer_unit_id + reference_month` para juntar
   `energy_clients`;
4. divide `amount` por 100 e o chama de `valor_emitido_brl`;
5. usa `payment_date` para criar data e mês de liquidação;
6. usa `status` no filtro `waitingPayment`/`paid`;
7. carrega campos de cancelamento, embora estejam vazios no snapshot.

Como a charge é repetida em cada instrumento dos ramos boleto e PIX, seus dados
também participam do risco de fanout da view.

## Confirmado

- Grain: uma charge por unidade consumidora e mês no snapshot.
- O valor da charge reconcilia integralmente com o GMV oficial do cliente.
- Todas as charges possuem billing e cliente correspondentes.
- Status, valor e `place_id` coincidem entre charge e billing.
- Campos categóricos de produto, provedor, assinante e tipo são constantes.
- Não existem charges canceladas no recorte.

## Hipóteses

- `pipedrive_id` identifica um objeto de cobrança ou negócio no CRM.
- `anniversary` indica cobrança recorrente no ciclo da assinatura.
- `billing_plan_id` descreve uma regra/plano de faturamento, não o próprio
  billing.
- A diferença de um dia entre datas de pagamento decorre de fuso horário.

## Questões abertas

1. Qual é a definição oficial de charge versus billing?
2. O que representam exatamente `place`, `subscriber`, `subscription` e
   `billing_plan` no grafo?
3. O que é o objeto identificado por `pipedrive_id`?
4. Qual timezone deve ser usado para normalizar as datas?
5. Quais situações ativam desconto temporário e cancelamento?
