# Documentação da camada Trusted

Documentos gerados a partir dos DDLs e procedures versionados no repositório. A implementação SQL é a fonte de verdade técnica.

| Tabela | Origem | Grain |
|---|---|---|
| [`trusted.boleto`](boleto.md) | `raw.finance_boletos` | uma linha por `id_boleto` |
| [`trusted.cliente_energia_mensal`](cliente_energia_mensal.md) | `raw.energy_clients` | uma linha por `id_instalacao + dt_mes_referencia` |
| [`trusted.cobranca`](cobranca.md) | `raw.finance_charges` | uma linha por `id_cobranca` |
| [`trusted.desempenho_usina_mensal`](desempenho_usina_mensal.md) | `trusted.usina_energia_mensal`, `trusted.cliente_energia_mensal`, `trusted.faturamento_cliente_mensal` | uma linha por `gerador + usina + cod_distribuidora + dt_mes_referencia` |
| [`trusted.faixa_take_rate_gerador`](faixa_take_rate_gerador.md) | `raw.energy_generator_take_rates` | uma faixa por `id_take_rate + perc_desempenho_min` |
| [`trusted.faturamento`](faturamento.md) | `raw.finance_billings` | uma linha por `id_faturamento` |
| [`trusted.faturamento_cliente_mensal`](faturamento_cliente_mensal.md) | `trusted.cliente_energia_mensal`, `trusted.cobranca`, `trusted.faturamento`, `trusted.instrumento_pagamento` | uma linha por `id_instalacao + dt_mes_referencia` |
| [`trusted.instrumento_pagamento`](instrumento_pagamento.md) | `trusted.boleto`, `trusted.pix`, `trusted.relacao_financeira` | uma linha por `tipo_instrumento + id_instrumento` |
| [`trusted.pix`](pix.md) | `raw.finance_pixs` | uma linha por `id_pix` |
| [`trusted.relacao_financeira`](relacao_financeira.md) | `raw.finance_relations` | uma aresta por `id_grafo_origem + id_grafo_destino` |
| [`trusted.usina_energia_mensal`](usina_energia_mensal.md) | `raw.energy_farms` | uma linha por `usina + dt_mes_referencia` |
