# Trusted — `relacao_financeira`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.relacao_financeira` |
| Origem(ns) | `raw.finance_relations` |
| Grain | uma aresta por `id_grafo_origem + id_grafo_destino` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `DATE(ts_criado_em)` |
| Clusterização | `tipo_entidade_destino, id_origem` |

## Descrição funcional

Normaliza as arestas do grafo financeiro e separa tipo e identificador dos nós de origem e destino.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `source` | `id_grafo_origem` | `STRING` | `STRING` | Sim | Normalizado | Identificador completo do nó de origem da relação financeira. | `NULLIF(TRIM(source), '')` |
| `source` | `tipo_entidade_origem` | `STRING` | `STRING` | Sim | Normalizado | Tipo da entidade de origem extraído do prefixo do identificador; billing no snapshot analisado. | `LOWER(SPLIT(NULLIF(TRIM(source), ''), '#')[SAFE_OFFSET(0)])` |
| `source` | `id_origem` | `STRING` | `STRING` | Sim | Normalizado | Identificador da entidade de origem sem o prefixo do grafo. | `REGEXP_REPLACE( NULLIF(TRIM(source), ''), r'^[^#]+#', '' )` |
| `target` | `id_grafo_destino` | `STRING` | `STRING` | Sim | Normalizado | Identificador completo do nó de destino da relação financeira. | `NULLIF(TRIM(target), '')` |
| `target` | `tipo_entidade_destino` | `STRING` | `STRING` | Sim | Normalizado | Tipo da entidade de destino extraído do prefixo: charge, boleto ou pix. | `LOWER(SPLIT(NULLIF(TRIM(target), ''), '#')[SAFE_OFFSET(0)])` |
| `target` | `id_destino` | `STRING` | `STRING` | Sim | Normalizado | Identificador da entidade de destino sem o prefixo do grafo. | `REGEXP_REPLACE( NULLIF(TRIM(target), ''), r'^[^#]+#', '' )` |
| `create_at` | `ts_criado_em` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de criação da relação entre as entidades financeiras. | `SAFE_CAST(NULLIF(TRIM(create_at), '') AS TIMESTAMP)` |
| `ingestion_time` | `ts_ingestao_origem` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de ingestão informada pelo sistema financeiro de origem. | `SAFE_CAST(NULLIF(TRIM(ingestion_time), '') AS TIMESTAMP)` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma aresta por `id_grafo_origem + id_grafo_destino`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_relacao_financeira.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_relacao_financeira.sql`
