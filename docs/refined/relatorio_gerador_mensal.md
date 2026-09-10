# Refined — `relatorio_gerador_mensal`

## Visão geral

| Atributo | Definição |
|---|---|
| Tabela | `refined.relatorio_gerador_mensal` |
| Grain | Uma linha por gerador, usina, distribuidora e mês |
| Origem principal | `trusted.desempenho_usina_mensal` |
| Configuração | `trusted.faixa_take_rate_gerador` |
| Particionamento | `dt_mes_referencia` |
| Clusterização | `gerador`, `usina`, `cod_distribuidora` |
| Estratégia | Full refresh transacional |

## Descrição funcional

A tabela é o produto de dados mensal do Relatório do Gerador. Ela combina o
desempenho energético e financeiro da usina com a faixa de take rate vigente e
calcula as parcelas finais da Lemon e do gerador.

A associação da faixa exige simultaneamente gerador, distribuidora, vigência e
desempenho dentro do intervalo `[mínimo, máximo)`. A carga pressupõe exatamente
uma faixa aplicável por linha de desempenho.

## Dicionário de campos

| Campo | Tipo | Origem ou cálculo | Definição |
|---|---|---|---|
| `gerador` | `STRING` | `desempenho.gerador` | Identificador funcional do gerador |
| `id_gerador` | `INT64` | Sufixo numérico de `gerador` | Identificador numérico para apresentação |
| `usina` | `STRING` | `desempenho.usina` | Identificador funcional da usina |
| `id_usina` | `INT64` | Sufixo numérico de `usina` | Identificador numérico para apresentação |
| `cod_distribuidora` | `STRING` | `desempenho.cod_distribuidora` | Distribuidora associada à usina |
| `dt_mes_referencia` | `DATE` | `desempenho.dt_mes_referencia` | Competência do relatório |
| `qtd_instalacoes` | `INT64` | `desempenho.qtd_instalacoes` | Instalações associadas à usina |
| `qtd_creditos_injetados_kwh` | `NUMERIC` | `desempenho.qtd_creditos_injetados_kwh` | Créditos injetados pela usina |
| `qtd_creditos_faturados_kwh` | `NUMERIC` | `desempenho.qtd_creditos_faturados_kwh` | Créditos faturados aos clientes |
| `qtd_creditos_faturados_pagos_kwh` | `NUMERIC` | `desempenho.qtd_creditos_faturados_pagos_kwh` | Créditos associados a faturamentos pagos |
| `qtd_minima_injecao_kwh` | `NUMERIC` | Menor valor entre injeção e geração prevista | Base energética do desempenho |
| `perc_desempenho_lemon` | `NUMERIC` | Créditos faturados pagos ÷ quantidade mínima | Desempenho em escala decimal |
| `id_take_rate` | `STRING` | `faixa.id_take_rate` | Configuração selecionada |
| `perc_desempenho_min` | `NUMERIC` | `faixa.perc_desempenho_min` | Limite inferior inclusivo da faixa |
| `perc_desempenho_max` | `NUMERIC` | `faixa.perc_desempenho_max` | Limite superior exclusivo da faixa |
| `perc_take_rate_aplicado` | `NUMERIC` | `faixa.perc_take_rate` | Participação da Lemon em escala decimal |
| `vlr_cobranca_gerador_brl` | `NUMERIC` | `desempenho.vlr_cobranca_gerador_brl` | GMV do gerador com faturamento emitido |
| `vlr_liquidado_gerador_brl` | `NUMERIC` | `desempenho.vlr_liquidado_gerador_brl` | Principal liquidado atribuído ao gerador |
| `vlr_receita_bruta_gerador_brl` | `NUMERIC` | Igual a `vlr_liquidado_gerador_brl` | Receita bruta usada nos repasses |
| `vlr_receita_multas_brl` | `NUMERIC` | Juros pagos + multas pagas | Encargos recebidos na competência |
| `vlr_repasse_pre_tusd_gerador_brl` | `NUMERIC` | Receita bruta × `(1 - take rate)` | Repasse principal antes da TUSD |
| `dt_mes_desconto_tusd_gerador` | `DATE` | Trusted de desempenho | Competência informada para desconto da TUSD |
| `vlr_tusd_descontada_gerador_brl` | `NUMERIC` | Trusted de desempenho, com nulo convertido em zero | TUSD deduzida do gerador |
| `vlr_repasse_gerador_brl` | `NUMERIC` | Repasse pré-TUSD − TUSD | Repasse principal após TUSD |
| `vlr_repasse_multas_lemon_brl` | `NUMERIC` | Encargos × take rate | Parcela dos encargos pertencente à Lemon |
| `vlr_repasse_multas_gerador_brl` | `NUMERIC` | Encargos × `(1 - take rate)` | Parcela dos encargos pertencente ao gerador |
| `vlr_repasse_lemon_brl` | `NUMERIC` | Receita bruta × take rate | Parcela principal pertencente à Lemon |
| `processado_em` | `TIMESTAMP` | `CURRENT_TIMESTAMP()` | Momento de processamento da linha |

## View de apresentação

`refined.vw_relatorio_gerador_apresentacao` reduz o contrato para 13 campos,
transforma os percentuais para a escala de 0 a 100 e publica:

```text
vlr_repasse_total_gerador_brl
  = vlr_repasse_gerador_brl + vlr_repasse_multas_gerador_brl

vlr_repasse_total_lemon_brl
  = vlr_repasse_lemon_brl + vlr_repasse_multas_lemon_brl
```

## Controles recomendados

- unicidade no grain do relatório;
- exatamente uma faixa de take rate por linha;
- ausência de chaves obrigatórias nulas;
- soma das parcelas igual à receita que lhes deu origem;
- rastreabilidade entre a tabela Refined e o desempenho Trusted.

## Implementação

- DDL: `sql/ddl/refined/ddl_relatorio_gerador_mensal.sql`
- carga: `sql/procedures/refined/sp_carregar_relatorio_gerador_mensal.sql`
- apresentação: `sql/view/refined/vw_relatorio_gerador_apresentacao.sql`
