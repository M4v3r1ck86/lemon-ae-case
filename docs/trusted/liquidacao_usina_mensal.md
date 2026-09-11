# Trusted — `liquidacao_usina_mensal`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.liquidacao_usina_mensal` |
| Origem | `trusted.faturamento_cliente_mensal` |
| Grain | gerador + usina + distribuidora + competência de origem + mês de liquidação + classificação D+60 |
| Estratégia | Full refresh transacional |
| Particionamento | `dt_mes_liquidacao` |

## Descrição funcional

Preserva os dois relógios financeiros do produto: o mês ao qual a fatura
pertence e o mês em que o dinheiro entrou. Pagamentos posteriores ao limite de
60 dias não reabrem a competência; permanecem identificados como recuperação
posterior.

## Dicionário de campos

| Campo de origem | Campo Trusted | Tipo | Definição |
|---|---|---|---|
| `gerador` | `gerador` | `STRING` | Gerador associado à liquidação |
| `usina` | `usina` | `STRING` | Usina associada à liquidação |
| `cod_distribuidora` | `cod_distribuidora` | `STRING` | Distribuidora da usina |
| `dt_mes_referencia` | `dt_mes_competencia_origem` | `DATE` | Competência original da fatura |
| `dt_mes_pagamento` | `dt_mes_liquidacao` | `DATE` | Mês em que o pagamento entrou |
| flags D+60 | `classificacao_liquidacao` | `STRING` | `dentro_d60`, `recuperacao_apos_d60` ou `vencimento_ausente` |
| `COUNT(DISTINCT id_faturamento)` | `qtd_faturamentos` | `INT64` | Faturamentos liquidados no agrupamento |
| `COUNT(DISTINCT id_instalacao)` | `qtd_instalacoes` | `INT64` | Instalações liquidadas no agrupamento |
| soma dos créditos pagos | `qtd_creditos_faturados_pagos_kwh` | `NUMERIC` | Créditos associados aos pagamentos |
| soma do faturamento | `vlr_faturamento_brl` | `NUMERIC` | Valor nominal dos faturamentos |
| soma do principal pago | `vlr_principal_pago_brl` | `NUMERIC` | Principal recebido, sem encargos |
| soma da parcela proporcional | `vlr_liquidado_gerador_brl` | `NUMERIC` | Valor recebido atribuído ao gerador |
| soma dos juros | `vlr_juros_pago_brl` | `NUMERIC` | Juros recebidos |
| soma das multas | `vlr_multa_paga_brl` | `NUMERIC` | Multas recebidas |
| maior `ingerido_em` | `ingerido_em` | `TIMESTAMP` | Momento mais recente entre as linhas agregadas |

## Regra D+60

```text
pagamento <= vencimento vigente + 60 dias → dentro_d60
pagamento >  vencimento vigente + 60 dias → recuperacao_apos_d60
```

Na ausência do vencimento vigente, a transformação usa o vencimento original.

## Artefatos

- DDL: `sql/ddl/trusted/ddl_liquidacao_usina_mensal.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_liquidacao_usina_mensal.sql`
