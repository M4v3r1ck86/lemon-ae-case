# Trusted — `faturamento_cliente_mensal`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `trusted.faturamento_cliente_mensal` |
| Origem(ns) | `trusted.cliente_energia_mensal`, `trusted.cobranca`, `trusted.faturamento`, `trusted.instrumento_pagamento` |
| Grain | uma linha por `id_instalacao + dt_mes_referencia` |
| Estratégia de carga | Full refresh transacional com deduplicação defensiva |
| Particionamento | `dt_mes_referencia` |
| Clusterização | `gerador, usina, cod_distribuidora, status_faturamento` |

## Descrição funcional

Integra energia, cobrança, faturamento e instrumentos no grão mensal da
instalação, evitando multiplicação de valores por instrumentos. A tabela mantém
separados o mês da competência e o mês do pagamento e classifica a liquidação
pela janela de 60 dias corridos após o vencimento vigente.

A procedure preserva o registro mais recente segundo `ingerido_em` no grain da tabela. Conversões com `SAFE_CAST` produzem `NULL` quando o valor de origem é inválido; campos textuais normalizados com `NULLIF(TRIM(...), '')` convertem texto vazio em `NULL`.

## Schema e dicionário individual dos campos

| Campo de origem | Campo Trusted | Tipo na origem | Tipo Trusted | Obrigatório | Natureza | Definição | Transformação ou cálculo |
|---|---|---|---|---:|---|---|---|
| `trusted.cliente_energia_mensal.id_instalacao` | `id_instalacao` | `STRING` | `STRING` | Sim | Herdado/integrado | Identificador da instalação ou unidade consumidora de energia. | `trusted.cliente_energia_mensal.id_instalacao` |
| `trusted.cliente_energia_mensal.dt_mes_referencia` | `dt_mes_referencia` | `DATE` | `DATE` | Sim | Herdado/integrado | Mês de competência energética e financeira da instalação. | `trusted.cliente_energia_mensal.dt_mes_referencia` |
| `trusted.cliente_energia_mensal.gerador` | `gerador` | `STRING` | `STRING` | Não | Herdado/integrado | Nome ou identificador funcional do gerador associado à instalação. | `trusted.cliente_energia_mensal.gerador` |
| `trusted.cliente_energia_mensal.usina` | `usina` | `STRING` | `STRING` | Não | Herdado/integrado | Nome ou identificador funcional da usina associada à instalação. | `trusted.cliente_energia_mensal.usina` |
| `trusted.cliente_energia_mensal.cod_distribuidora` | `cod_distribuidora` | `STRING` | `STRING` | Não | Herdado/integrado | Código ou nome padronizado da distribuidora de energia. | `trusted.cliente_energia_mensal.cod_distribuidora` |
| `trusted.cobranca.id_cobranca` | `id_cobranca` | `STRING` | `STRING` | Não | Herdado/integrado | Identificador da cobrança associada à instalação e competência. | `trusted.cobranca.id_cobranca` |
| `trusted.cobranca.id_faturamento` | `id_faturamento` | `STRING` | `STRING` | Não | Herdado/integrado | Identificador do faturamento associado à cobrança. | `trusted.cobranca.id_faturamento` |
| `trusted.cobranca.id_local` | `id_local` | `STRING` | `STRING` | Não | Herdado/integrado | Identificador do local ou estabelecimento associado ao faturamento. | `trusted.cobranca.id_local` |
| `trusted.cobranca.status_cobranca` | `status_cobranca` | `STRING` | `STRING` | Não | Herdado/integrado | Status operacional da cobrança. | `trusted.cobranca.status_cobranca` |
| `trusted.faturamento.status_faturamento` | `status_faturamento` | `STRING` | `STRING` | Não | Herdado/integrado | Status operacional do faturamento. | `trusted.faturamento.status_faturamento` |
| `cobranca.ts_criado_em` | `ts_criacao_cobranca` | `TIMESTAMP` | `TIMESTAMP` | Não | Herdado/integrado | Data e hora de criação da cobrança. | `cobranca.ts_criado_em` |
| `faturamento.ts_criado_em` | `ts_criacao_faturamento` | `TIMESTAMP` | `TIMESTAMP` | Não | Herdado/integrado | Data e hora de criação do faturamento. | `faturamento.ts_criado_em` |
| `trusted.faturamento.dt_vencimento` | `dt_vencimento` | `DATE` | `DATE` | Não | Herdado/integrado | Data de vencimento vigente do faturamento. | `trusted.faturamento.dt_vencimento` |
| `trusted.faturamento.dt_vencimento_original` | `dt_vencimento_original` | `DATE` | `DATE` | Não | Herdado/integrado | Data de vencimento original do faturamento. | `trusted.faturamento.dt_vencimento_original` |
| `DATE(trusted.faturamento.ts_pagamento)` | `dt_pagamento` | `—` | `DATE` | Não | Calculado/derivado | Data em que o pagamento foi registrado no faturamento. | `DATE(trusted.faturamento.ts_pagamento)` |
| `DATE_TRUNC(DATE(trusted.faturamento.ts_pagamento), MONTH)` | `dt_mes_pagamento` | `—` | `DATE` | Não | Calculado/derivado | Primeiro dia do mês em que o pagamento foi registrado, utilizado para análises por competência de liquidação. | `DATE_TRUNC(DATE(trusted.faturamento.ts_pagamento), MONTH)` |
| vencimento vigente ou original | `dt_vencimento_base_d60` | `—` | `DATE` | Não | Calculado/derivado | Vencimento contratual usado como início da maturação. | `COALESCE(dt_vencimento, dt_vencimento_original)` |
| `dt_vencimento_base_d60` | `dt_limite_pagamento_d60` | `—` | `DATE` | Não | Calculado/derivado | Último dia elegível para reconhecimento na competência. | `DATE_ADD(dt_vencimento_base_d60, INTERVAL 60 DAY)` |
| vencimento e pagamento | `qtd_dias_para_pagamento` | `—` | `INT64` | Não | Calculado/derivado | Dias entre vencimento e pagamento. | `DATE_DIFF(dt_pagamento, dt_vencimento_base_d60, DAY)` |
| dias para pagamento | `faixa_atraso` | `—` | `STRING` | Não | Calculado/derivado | Faixa de pontualidade ou atraso. | em dia, 1–30, 31–60, acima de 60, pendente ou vencimento ausente |
| `trusted.cliente_energia_mensal.vlr_gmv_real_oficial_brl` | `vlr_gmv_real_oficial_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor oficial do GMV da instalação na competência, em reais. | `trusted.cliente_energia_mensal.vlr_gmv_real_oficial_brl` |
| `trusted.cliente_energia_mensal.vlr_gmv_gerador_brl` | `vlr_gmv_gerador_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Parcela do GMV atribuída ao gerador na competência, em reais. | `trusted.cliente_energia_mensal.vlr_gmv_gerador_brl` |
| `trusted.cobranca.vlr_cobranca_brl` | `vlr_cobranca_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor nominal da cobrança associada à instalação, em reais. | `trusted.cobranca.vlr_cobranca_brl` |
| `trusted.faturamento.vlr_faturamento_brl` | `vlr_faturamento_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor nominal registrado no faturamento, em reais. | `trusted.faturamento.vlr_faturamento_brl` |
| `trusted.faturamento.vlr_total_pago_brl` | `vlr_total_pago_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor total pago registrado no faturamento, incluindo multa e juros, em reais. | `trusted.faturamento.vlr_total_pago_brl` |
| `vlr_total_pago_brl - COALESCE(vlr_juros_pago_brl, 0) - COALESCE(vlr_multa_paga_brl, 0); nulo sem pagamento` | `vlr_principal_pago_brl` | `—` | `NUMERIC` | Não | Calculado/derivado | Valor pago excluindo multa e juros, calculado a partir dos valores do faturamento, em reais. | `vlr_total_pago_brl - COALESCE(vlr_juros_pago_brl, 0) - COALESCE(vlr_multa_paga_brl, 0)`; nulo sem pagamento |
| principal, faturamento e GMV | `vlr_liquidado_gerador_brl` | `—` | `NUMERIC` | Não | Calculado/derivado | Parcela proporcional do principal recebido atribuída ao gerador. | `principal pago / faturamento × GMV do gerador` |
| valor liquidado e flag D+60 | `vlr_liquidado_gerador_d60_brl` | `—` | `NUMERIC` | Não | Calculado/derivado | Parcela reconhecida no fechamento da competência. | valor liquidado quando pago até D+60 |
| valor liquidado e flag após D+60 | `vlr_liquidado_gerador_apos_d60_brl` | `—` | `NUMERIC` | Não | Calculado/derivado | Recuperação financeira posterior ao fechamento. | valor liquidado quando pago depois de D+60 |
| `trusted.faturamento.vlr_juros_pago_brl` | `vlr_juros_pago_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de juros pago registrado no faturamento, em reais. | `trusted.faturamento.vlr_juros_pago_brl` |
| `trusted.faturamento.vlr_multa_paga_brl` | `vlr_multa_paga_brl` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Valor de multa paga registrado no faturamento, em reais. | `trusted.faturamento.vlr_multa_paga_brl` |
| `trusted.cliente_energia_mensal.qtd_creditos_faturados_kwh` | `qtd_creditos_faturados_kwh` | `NUMERIC` | `NUMERIC` | Não | Herdado/integrado | Quantidade de créditos de energia faturados para a instalação na competência, em kWh. | `trusted.cliente_energia_mensal.qtd_creditos_faturados_kwh` |
| `Créditos faturados quando o faturamento está pago ou possui data de pagamento; caso contrário, zero` | `qtd_creditos_faturados_pagos_kwh` | `—` | `NUMERIC` | Não | Calculado/derivado | Quantidade de créditos faturados associada a faturamento pago; zero quando o faturamento não está pago. | Créditos faturados quando o faturamento está pago ou possui data de pagamento; caso contrário, zero |
| créditos e flag D+60 | `qtd_creditos_faturados_pagos_d60_kwh` | `—` | `NUMERIC` | Não | Calculado/derivado | Créditos usados no desempenho Lemon do fechamento. | créditos faturados quando pagos até D+60 |
| `COUNT(*) por faturamento em trusted.instrumento_pagamento` | `qtd_instrumentos` | `—` | `INT64` | Não | Calculado/derivado | Quantidade total de boletos e PIX vinculados ao faturamento. | `COUNT(*)` por faturamento em `trusted.instrumento_pagamento` |
| `COUNTIF(tipo_instrumento = 'boleto') por faturamento` | `qtd_boletos` | `—` | `INT64` | Não | Calculado/derivado | Quantidade de boletos vinculados ao faturamento. | `COUNTIF(tipo_instrumento = 'boleto')` por faturamento |
| `COUNTIF(tipo_instrumento = 'pix') por faturamento` | `qtd_pixs` | `—` | `INT64` | Não | Calculado/derivado | Quantidade de instrumentos PIX vinculados ao faturamento. | `COUNTIF(tipo_instrumento = 'pix')` por faturamento |
| `COUNTIF(LOWER(status_instrumento) = 'paid') por faturamento` | `qtd_instrumentos_pagos` | `—` | `INT64` | Não | Calculado/derivado | Quantidade de instrumentos vinculados ao faturamento com status pago. | `COUNTIF(LOWER(status_instrumento) = 'paid')` por faturamento |
| `trusted.faturamento.ts_criado_em IS NOT NULL` | `flg_emitido` | `—` | `BOOL` | Não | Calculado/derivado | Indica que existe faturamento emitido para a instalação e competência. | `trusted.faturamento.ts_criado_em IS NOT NULL` |
| `Status do faturamento igual a paid ou timestamp de pagamento preenchido` | `flg_pago` | `—` | `BOOL` | Não | Calculado/derivado | Indica que o faturamento está pago ou possui data de pagamento registrada. | Status do faturamento igual a `paid` ou timestamp de pagamento preenchido |
| pagamento e limite D+60 | `flg_pago_ate_d60` | `—` | `BOOL` | Não | Calculado/derivado | Pagamento elegível para o fechamento da competência. | `dt_pagamento <= dt_limite_pagamento_d60` |
| pagamento e limite D+60 | `flg_pago_apos_d60` | `—` | `BOOL` | Não | Calculado/derivado | Pagamento classificado como recuperação posterior. | `dt_pagamento > dt_limite_pagamento_d60` |
| inverso da elegibilidade D+60 | `flg_pendente_d60` | `—` | `BOOL` | Não | Calculado/derivado | Faturamento não liquidado dentro da janela. | `NOT flg_pago_ate_d60` |
| `Quantidade de instrumentos pagos maior que 1` | `flg_multiplos_instrumentos_pagos` | `—` | `BOOL` | Não | Calculado/derivado | Indica que mais de um instrumento está marcado como pago para o mesmo faturamento. | Quantidade de instrumentos pagos maior que 1 |
| `Maior timestamp de ingestão entre cliente, cobrança, faturamento e instrumentos` | `ingerido_em` | `—` | `TIMESTAMP` | Não | Calculado/derivado | Data e hora mais recente de ingestão entre os registros utilizados na composição da linha. | Maior timestamp de ingestão entre cliente, cobrança, faturamento e instrumentos |

## Regras de carga e qualidade

- Chave/grain usado na deduplicação: uma linha por `id_instalacao + dt_mes_referencia`.
- Em caso de duplicidade, vence o registro com `ingerido_em` mais recente.
- A substituição ocorre dentro de transação: exclusão e inserção são confirmadas juntas.
- A documentação descreve a transformação implementada; não substitui validações de conteúdo no BigQuery.

## Artefatos de implementação

- DDL: `sql/ddl/trusted/ddl_faturamento_cliente_mensal.sql`
- Procedure: `sql/procedures/trusted/sp_carregar_faturamento_cliente_mensal.sql`
