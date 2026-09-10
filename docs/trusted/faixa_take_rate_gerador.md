# Trusted — `faixa_take_rate_gerador`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.faixa_take_rate_gerador` |
| Origem(ns) | `raw.energy_generator_take_rates` |
| Grain | uma faixa por `id_take_rate + perc_desempenho_min` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `não definido` |
| Clusterização | `gerador, cod_distribuidora, id_take_rate` |

## Descrição funcional

Normaliza as faixas temporais de desempenho que determinam o percentual de take rate por gerador e distribuidora.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `id_tr` | `id_take_rate` | `STRING` | `STRING` | Sim | Normalizado | Identificador da configuração de take rate à qual a faixa pertence. | `NULLIF(TRIM(id_tr), '')` |
| `desempenho_min` | `perc_desempenho_min` | `FLOAT64` | `NUMERIC` | Sim | Normalizado | Limite inferior inclusivo de desempenho para aplicação da faixa, em escala decimal. | `SAFE_CAST(desempenho_min AS NUMERIC)` |
| `desempenho_max` | `perc_desempenho_max` | `FLOAT64` | `NUMERIC` | Sim | Normalizado | Limite superior exclusivo de desempenho para aplicação da faixa, em escala decimal. | `SAFE_CAST(desempenho_max AS NUMERIC)` |
| `tr_percentual` | `perc_take_rate` | `FLOAT64` | `NUMERIC` | Sim | Normalizado | Percentual de participação da Lemon aplicável à faixa, em escala decimal. | `SAFE_CAST(tr_percentual AS NUMERIC)` |
| `id_gerador` | `id_gerador` | `STRING` | `STRING` | Não | Normalizado | Identificador técnico do gerador informado pela fonte. | `NULLIF(TRIM(id_gerador), '')` |
| `gerador` | `gerador` | `STRING` | `STRING` | Sim | Normalizado | Nome ou identificador funcional do gerador. | `NULLIF(TRIM(gerador), '')` |
| `disco` | `cod_distribuidora` | `STRING` | `STRING` | Sim | Normalizado | Código ou nome padronizado da distribuidora de energia. | `UPPER(NULLIF(TRIM(disco), ''))` |
| `status` | `status_take_rate` | `STRING` | `STRING` | Não | Normalizado | Status informado pela origem para a configuração de take rate. | `NULLIF(TRIM(status), '')` |
| `data_inicio` | `dt_inicio_vigencia` | `STRING` | `DATE` | Sim | Normalizado | Data inicial inclusiva de vigência da configuração. | `SAFE_CAST(NULLIF(TRIM(data_inicio), '') AS DATE)` |
| `data_final` | `dt_fim_vigencia` | `STRING` | `DATE` | Sim | Normalizado | Data final inclusiva de vigência da configuração. | `SAFE_CAST(NULLIF(TRIM(data_final), '') AS DATE)` |
| `spreadsheet_id` | `id_planilha_origem` | `STRING` | `STRING` | Não | Normalizado | Identificador da planilha que forneceu a configuração. | `NULLIF(TRIM(spreadsheet_id), '')` |
| `update_time` | `ts_atualizacao_origem` | `STRING` | `TIMESTAMP` | Não | Normalizado | Data e hora de atualização informada pelo sistema de origem. | `SAFE_CAST(NULLIF(TRIM(update_time), '') AS TIMESTAMP)` |
| `_ingested_at` | `ingerido_em` | `TIMESTAMP` | `TIMESTAMP` | Não | Normalizado | Data e hora em que o registro foi ingerido na camada Raw. | `_ingested_at` |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma faixa por `id_take_rate + perc_desempenho_min`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_faixa_take_rate_gerador.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_faixa_take_rate_gerador.sql`
