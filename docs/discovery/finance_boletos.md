# Data Discovery — `finance_boletos`

## Visão geral

| Atributo | Valor observado |
|---|---|
| Tabela de origem | `raw.finance_boletos` |
| Domínio | Financeiro |
| Tipo de dado | Instrumento/tentativa de pagamento por boleto |
| Quantidade | 2.105 registros |
| Boletos distintos | 2.105 |
| Locais (`place_id`) | 709 |
| Recebedores | 14 |
| Status | 904 `paid`; 1.199 `cancelled`; 2 `waitingPayment` |
| Período de criação | 2025-01-09 a 2025-09-17 |
| Estado do discovery | Validado para o snapshot do case |

As consultas em GoogleSQL estão em
[`finance_boletos_discovery.sql`](finance_boletos_discovery.sql).

## Descrição funcional

`finance_boletos` armazena instrumentos de pagamento do tipo boleto. O boleto
não é a própria charge nem o billing: ele é uma forma de liquidar um billing e
pode ser cancelado e substituído por outro instrumento.

> **Uma linha representa uma emissão individual de boleto associada a um
> billing por meio de `finance_relations`.**

O termo “reemissão” para todos os instrumentos adicionais é uma **HIPÓTESE
alta**: a multiplicidade aumenta junto com os reagendamentos, mas existem
exceções entre o contador do billing e a quantidade de boletos.

## Schema e dicionário de campos

| Campo | Tipo RAW | Papel | Definição baseada nas evidências | Classificação |
|---|---|---|---|---|
| `source` | `STRING` | Chave do grafo | Identificador completo, sempre `boleto#` + `bank_slip_id`; aparece como `target` em `finance_relations`. | FATO |
| `bank_slip_id` | `INT64` | Identificador | ID único do boleto sem o prefixo de entidade. | FATO |
| `create_at` | `STRING` | Data/hora de criação | Momento textual de criação/emissão do instrumento. | FATO estrutural |
| `amount` | `INT64` | Valor monetário | Valor nominal do boleto em centavos. | FATO |
| `place_id` | `STRING` | Identificador de local | Local associado ao instrumento; coincide com o `place_id` do billing em todas as relações. | FATO estrutural |
| `due_date` | `STRING` | Vencimento | Data de vencimento do boleto. | FATO |
| `our_number` | `INT64` | Identificador bancário | Número único do boleto. “Nosso Número” bancário é a interpretação provável pelo nome. | FATO de unicidade; HIPÓTESE semântica alta |
| `receiver_name` | `STRING` | Atributo de recebedor | Nome textual do recebedor. Há 14 valores no snapshot. | FATO |
| `receiver_id` | `STRING` | Identificador de recebedor | Identificador da entidade/conta que recebe o pagamento. | FATO estrutural |
| `receiver_type` | `STRING` | Categoria | Tipo do recebedor: `consortium` ou `lemon`. | FATO |
| `bank_slip_expected_total` | `INT64` | Valor monetário | Total esperado no pagamento, em centavos. Preenchido nos boletos pagos. | FATO |
| `bank_slip_expected_interest` | `INT64` | Valor monetário | Juros esperados em centavos. | FATO pelo cálculo |
| `bank_slip_expected_fine` | `INT64` | Valor monetário | Multa esperada em centavos. | FATO pelo cálculo |
| `bank_slip_paid_total` | `INT64` | Valor monetário | Total efetivamente registrado no pagamento, em centavos. | FATO |
| `bank_slip_paid_interest` | `INT64` | Valor monetário | Juros registrados no pagamento, em centavos. | FATO |
| `bank_slip_paid_fine` | `INT64` | Valor monetário | Multa registrada no pagamento, em centavos. | FATO |
| `payment_date` | `STRING` | Data de pagamento | Data da liquidação do boleto; vazia quando ele não foi pago. | FATO |
| `status` | `STRING` | Status | Situação do instrumento: `paid`, `cancelled` ou `waitingPayment`. | FATO |
| `ingestion_time` | `STRING` | Timestamp técnico da origem | Momento de ingestão informado pela fonte/backend. | FATO técnico; origem exata DESCONHECIDA |
| `_ingested_at` | `TIMESTAMP` | Metadado da plataforma | Momento da carga do snapshot para o BigQuery. | FATO |

## Granularidade e chaves

`source`, `bank_slip_id` e `our_number` possuem 2.105 valores distintos e não
apresentam nulos.

| Chave candidata | Única? | Uso |
|---|---:|---|
| `source` | Sim | Chave canônica para a aresta do grafo |
| `bank_slip_id` | Sim | Identificador técnico do instrumento |
| `our_number` | Sim no snapshot | Identificador bancário candidato |
| `place_id` | Não | Relacionamento, não identifica boleto |

A tabela não contém `billing_id`; o vínculo com o faturamento depende de
`finance_relations`.

## Perfil financeiro

| Métrica de `amount` | Resultado |
|---|---:|
| Mínimo | R$ 2,37 |
| Média | R$ 792,34 |
| Máximo | R$ 25.566,01 |
| Soma nominal de todos os instrumentos | R$ 1.667.880,75 |

A soma nominal inclui instrumentos cancelados e versões associadas ao mesmo
billing; portanto, não representa receita.

Para todos os boletos com campos preenchidos:

```text
bank_slip_expected_total
  = amount + bank_slip_expected_interest + bank_slip_expected_fine

bank_slip_paid_total
  = amount + bank_slip_paid_interest + bank_slip_paid_fine
```

Não existem valores líquidos negativos após retirar juros e multa.

## Temporalidade e status

- 904 boletos pagos, todos com data e valores de pagamento;
- 1.199 cancelados, sem data ou valores de pagamento;
- 2 aguardando pagamento, igualmente sem pagamento;
- 639 pagamentos ocorreram até o vencimento;
- 265 ocorreram depois do vencimento, em média 7,1 dias após a data;
- criação entre 2025-01-09 e 2025-09-17;
- vencimentos entre 2025-01-22 e 2025-09-19;
- pagamentos entre 2025-01-10 e 2025-07-04.

O status descreve o instrumento, não necessariamente o billing. Instrumentos
antigos podem estar cancelados enquanto outro método do mesmo billing foi pago.

## Relacionamentos essenciais

| Origem | Destino | Cardinalidade observada | Evidência |
|---|---|---|---|
| Billing | Boleto | 1:N | 2.105 boletos para 2.000 billings |
| Boleto | Billing | N:1 | Cada boleto possui exatamente uma aresta de origem billing |
| `place_id` do boleto | `place_id` do billing | Igual em 2.105 relações | Validação direta |
| Boleto pago | Billing pago | 904 instrumentos ligados a billings pagos | Status e campos financeiros |

Dos 2.000 billings, 1.922 possuem um boleto. Os outros 78 possuem múltiplos
instrumentos, chegando a seis boletos para um mesmo billing.

## Papel na `generator_report`

A view:

1. usa `source` como `boleto_id`;
2. encontra o billing por `finance_relations`;
3. divide `amount` e os campos pagos por 100;
4. calcula juros e multa recebidos;
5. calcula o principal líquido como total pago menos juros e multa;
6. une o ramo de boletos ao ramo de PIX com `UNION ALL`.

Dois pontos merecem atenção:

- `status`, `payment_date`, `due_date`, `receiver_id` e `our_number` do boleto
  não são usados pela view;
- a seleção não escolhe explicitamente o boleto vigente ou pago. Todos os
  boletos relacionados entram no ramo, inclusive cancelados.

Os boletos cancelados normalmente possuem valores pagos nulos, mas ainda
multiplicam os campos provenientes de billing e charge.

## Confirmado

- Grain: uma emissão individual de boleto.
- IDs do instrumento são únicos e completos.
- Todo boleto possui um billing correspondente e nenhum target está órfão.
- A maior parte dos boletos cancelados representa instrumentos não liquidados.
- As equações internas de principal, juros, multa e total reconciliam.
- Múltiplos boletos podem existir para o mesmo billing.

## Hipóteses

- Instrumentos adicionais são reemissões decorrentes de reagendamento.
- `our_number` segue o conceito bancário brasileiro de “Nosso Número”.
- O instrumento mais recente não é necessariamente o que deve ser selecionado;
  a regra correta pode priorizar o pago ou o vigente.

## Questões abertas

1. Qual é a regra oficial para identificar o boleto vigente?
2. Um boleto cancelado deve permanecer no histórico analítico ou ser excluído
   dos cálculos?
3. Qual evento cancela o boleto anterior após uma reemissão?
4. Os juros e a multa pertencem integralmente ao recebedor indicado?
5. Por que o último pagamento de boleto ocorre em julho enquanto outros campos
   financeiros continuam até setembro?
