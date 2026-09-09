# Data Discovery — `finance_pixs`

## Visão geral

| Atributo | Valor observado |
|---|---|
| Tabela de origem | `raw.finance_pixs` |
| Domínio | Financeiro |
| Tipo de dado | Instrumento/tentativa de pagamento por PIX |
| Quantidade | 2.107 registros |
| PIX distintos | 2.107 |
| Billings distintos | 2.000 |
| Locais (`place_id`) | 709 |
| Status | 970 `paid`; 1.135 `cancelled`; 2 `waitingPayment` |
| Período de criação | 2025-01-09 a 2025-09-17 |
| Estado do discovery | Validado para o snapshot do case |

As consultas reproduzíveis estão em
[`finance_pixs_discovery.sql`](finance_pixs_discovery.sql).

## Descrição funcional

`finance_pixs` registra instrumentos individuais de cobrança via PIX. Um
billing pode possuir mais de um PIX, preservando instrumentos cancelados e uma
eventual versão paga ou ainda aguardando pagamento.

> **Uma linha representa uma emissão individual de cobrança PIX vinculada a um
> billing.**

A tabela representa instrumentos, não pagamentos necessariamente realizados:
1.137 linhas não possuem valores ou data de pagamento.

## Schema e dicionário de campos

| Campo | Tipo RAW | Papel | Definição baseada nas evidências | Classificação |
|---|---|---|---|---|
| `source` | `STRING` | Chave do grafo | Identificador completo, sempre `pix#` + `pix_id`; utilizado como target em `finance_relations`. | FATO |
| `pix_id` | `STRING` | Identificador | ID único do instrumento PIX sem prefixo. | FATO |
| `create_at` | `STRING` | Data/hora de criação | Timestamp textual da criação do instrumento. | FATO estrutural |
| `status` | `STRING` | Status | Situação: `paid`, `cancelled` ou `waitingPayment`. | FATO |
| `amount` | `INT64` | Valor monetário | Valor nominal em centavos. | FATO |
| `due_date` | `STRING` | Vencimento | Data limite associada à cobrança PIX. | FATO |
| `place_id` | `STRING` | Identificador de local | Identificador do local; coincide com o billing relacionado. | FATO estrutural |
| `receiver_id` | `STRING` | Identificador de recebedor | Conta ou entidade que receberia o pagamento. | FATO estrutural |
| `receiver_type` | `STRING` | Categoria | Tipo do recebedor: `consortium` ou `lemon`. | FATO |
| `pix_expected_total` | `INT64` | Valor monetário | Total esperado em centavos; preenchido nos PIX pagos. | FATO |
| `pix_expected_interest` | `INT64` | Valor monetário | Juros esperados em centavos. | FATO pelo cálculo |
| `pix_expected_fine` | `INT64` | Valor monetário | Multa esperada em centavos. | FATO pelo cálculo |
| `pix_paid_total` | `INT64` | Valor monetário | Total efetivamente registrado como pago, em centavos. | FATO |
| `pix_paid_interest` | `INT64` | Valor monetário | Juros registrados no pagamento. | FATO |
| `pix_paid_fine` | `INT64` | Valor monetário | Multa registrada no pagamento. | FATO |
| `payment_date` | `STRING` | Data de pagamento | Data de liquidação; vazia nos instrumentos não pagos. | FATO |
| `billing_id` | `STRING` | FK lógica | Billing relacionado sem o prefixo `billing#`. Há 2.000 IDs para 2.107 PIX. | FATO |
| `pix_code` | `STRING` | Payload técnico | Código completo de pagamento/QR Code. É único no snapshot e não deve ser exposto em produtos analíticos sem necessidade. | FATO estrutural |
| `tx_id` | `STRING` | Identificador transacional | Igual a `pix_id` nas 2.107 linhas; não acrescenta cardinalidade no snapshot. | FATO |
| `ingestion_time` | `STRING` | Timestamp técnico da origem | Momento de ingestão informado pela fonte/backend. | FATO técnico; origem exata DESCONHECIDA |
| `_ingested_at` | `TIMESTAMP` | Metadado da plataforma | Momento da carga do snapshot para o BigQuery. | FATO |

## Granularidade e chaves

| Chave candidata | Única? | Uso |
|---|---:|---|
| `source` | Sim | Chave do nó no grafo |
| `pix_id` | Sim | Identificador do instrumento |
| `tx_id` | Sim | Redundante com `pix_id` no snapshot |
| `billing_id` | Não | Relacionamento N:1 com billing |

Todos os `source`, `pix_id`, `tx_id` e `pix_code` são preenchidos. A igualdade
entre `pix_id` e `tx_id` é um fato apenas deste snapshot; os dois conceitos
podem divergir em outros provedores ou versões.

## Perfil financeiro

| Métrica de `amount` | Resultado |
|---|---:|
| Mínimo | R$ 2,37 |
| Média | R$ 792,60 |
| Máximo | R$ 25.566,01 |
| Soma nominal de todos os instrumentos | R$ 1.670.010,63 |

Essa soma não representa receita, pois inclui 1.135 instrumentos cancelados e
várias versões do mesmo billing.

As equações internas reconciliam em todos os registros preenchidos:

```text
pix_expected_total
  = amount + pix_expected_interest + pix_expected_fine

pix_paid_total
  = amount + pix_paid_interest + pix_paid_fine
```

## Temporalidade e status

- 970 PIX pagos, todos com data e campos de pagamento;
- 1.135 cancelados, sem pagamento;
- 2 aguardando pagamento;
- 576 pagamentos ocorreram até o vencimento;
- 394 ocorreram após o vencimento, em média 12,63 dias depois;
- criação entre 2025-01-09 e 2025-09-17;
- vencimentos entre 2025-01-22 e 2025-09-19;
- pagamentos entre 2025-01-13 e 2025-09-18.

O status é do instrumento PIX. Um billing pago pode conservar outro PIX
cancelado associado a ele.

## Relacionamentos essenciais

| Origem | Destino | Cardinalidade observada | Evidência |
|---|---|---|---|
| Billing | PIX | 1:N | 2.107 PIX para 2.000 billings |
| PIX | Billing | N:1 | `billing_id` e `finance_relations` apontam para o mesmo billing em 2.107 linhas |
| `place_id` do PIX | `place_id` do billing | Igual em todas as relações | Validação direta |
| PIX pago | Billing pago | 970 instrumentos ligados a billings pagos | Status e valores |

Dos 2.000 billings, 1.922 possuem um PIX; os demais 78 possuem múltiplos,
chegando a seis instrumentos. O padrão acompanha os reagendamentos, com algumas
exceções.

Existem dois billings nos quais um boleto e um PIX aparecem com status `paid`,
mesmo valor e mesma data. Isso comprova dois registros de instrumentos pagos;
**não comprova recebimento financeiro em duplicidade** sem extrato ou
identificador de liquidação externo.

## Papel na `generator_report`

A view:

1. usa `source` como `pix_id`;
2. encontra o billing por `finance_relations`, embora a tabela já possua
   `billing_id`;
3. converte os campos monetários de centavos para reais;
4. calcula juros/multa e o principal líquido recebido;
5. une os resultados aos boletos com `UNION ALL`.

Assim como no ramo dos boletos, a view não filtra `finance_pixs.status`, não usa
`payment_date` do PIX e não escolhe explicitamente um instrumento vigente ou
pago. Instrumentos cancelados permanecem no conjunto intermediário e aumentam
a cardinalidade.

`pix_code` e `tx_id` não participam do relatório.

## Confirmado

- Grain: uma emissão individual de PIX.
- Todo PIX possui um billing válido por campo direto e por aresta.
- Não existem targets PIX órfãos.
- As fórmulas internas de principal, juros, multa e total reconciliam.
- Um billing pode possuir múltiplos PIX.
- `pix_id` e `tx_id` são iguais em todas as linhas do snapshot.
- Dois billings possuem simultaneamente boleto e PIX marcados como pagos.

## Hipóteses

- PIX adicionais são novas tentativas ou reemissões após reagendamento.
- Instrumentos cancelados foram substituídos por outro método ou versão.
- O recebedor `lemon` pode estar relacionado à modalidade de cobrança
  unificada, mas essa semântica não está comprovada pelos dados.

## Questões abertas

1. Qual é a regra oficial para selecionar o PIX vigente?
2. `pix_id` e `tx_id` podem divergir em produção?
3. Os dois casos com boleto e PIX pagos representam duplicidade financeira ou
   duplicidade de estado?
4. O `pix_code` precisa ser retido fora da RAW por alguma necessidade de
   auditoria?
5. Qual é a semântica do recebedor após uma alteração ou reagendamento?
