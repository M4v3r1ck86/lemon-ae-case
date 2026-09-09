# Generator Report — Engenharia reversa

## Objetivo

Esta pasta documenta a engenharia reversa da view `generator_report`, desde a extração do SQL original no SQLite até a construção de uma versão candidata refatorada no BigQuery.

O material preserva três momentos distintos do trabalho:

1. **Fonte original:** definição da view extraída do arquivo `.db` sem alteração de lógica.
2. **Paridade inspecionável:** tradução da lógica original para GoogleSQL, desmembrada em tabelas temporárias para depuração.
3. **Candidato refatorado:** proposta tecnicamente corrigida, ainda sujeita à reconciliação e à validação das regras de negócio.

---

## Como o SQL original foi obtido

A definição da view foi extraída no SQLite pelo DBeaver com:

```sql
SELECT sql
FROM sqlite_master
WHERE type = 'view'
  AND name = 'generator_report';
```

O resultado está preservado sem adaptação para o BigQuery em:

[`../../sql/generator_report/01_generator_report_original_sqlite.sql`](../../sql/generator_report/01_generator_report_original_sqlite.sql)

Esse arquivo é a evidência primária da implementação existente. Ele não deve ser executado diretamente no BigQuery porque contém sintaxe e comportamentos próprios do SQLite.

---

## Sequência dos scripts

### 01 — SQL original do SQLite

Arquivo:

[`01_generator_report_original_sqlite.sql`](../../sql/generator_report/01_generator_report_original_sqlite.sql)

Função:

- preservar o código `AS IS` encontrado no banco de origem;
- permitir rastrear cada regra até a implementação original;
- servir como baseline para a engenharia reversa;
- impedir que a análise substitua silenciosamente o comportamento observado por uma interpretação nova.

Dialeto: **SQLite**.

### 02 — Lógica original em tabelas temporárias

Arquivo:

[`02_generator_report_legacy_temp_tables.sql`](../../sql/generator_report/02_generator_report_legacy_temp_tables.sql)

Função:

- reproduzir a lógica original em GoogleSQL;
- substituir CTEs por tabelas temporárias inspecionáveis;
- permitir a execução de cada transformação por etapa;
- conferir grain, cardinalidade, filtros e joins;
- localizar o primeiro ponto em que um valor é alterado ou multiplicado;
- reconciliar `tmp_final_result` com a saída original da view.

Dialeto: **GoogleSQL / BigQuery**.

Esse script deve ser executado como uma única sessão no BigQuery, pois as tabelas temporárias deixam de existir ao final da execução.

### 03 — Candidato refatorado

Arquivo:

[`03_generator_report_refactored_candidate.sql`](../../sql/generator_report/03_generator_report_refactored_candidate.sql)

Função:

- criar `validation.generator_report_refactored_candidate`;
- eliminar o fanout acidental de instrumentos financeiros;
- preservar centavos com tipos numéricos adequados;
- utilizar o valor proporcionalmente liquidado no cálculo do GMV reconhecido;
- corrigir coerções e divisões numéricas;
- tornar datas, filtros e escolhas de instrumento explícitos.

Dialeto: **GoogleSQL / BigQuery**.

Importante:

> O termo `candidate` é intencional. O script contém correções técnicas e interpretações plausíveis das regras, mas não deve substituir o relatório atual antes da reconciliação completa e da validação com o negócio.

### 04 — Candidato corrigido em tabelas temporárias

Arquivo:

[`04_generator_report_corrected_temp_tables.sql`](../../sql/generator_report/04_generator_report_corrected_temp_tables.sql)

Função:

- expressar as correções da versão candidata em etapas temporárias inspecionáveis;
- manter o contrato das 22 colunas finais;
- selecionar no máximo um instrumento de pagamento por billing;
- preservar centavos com `NUMERIC` e divisão decimal;
- reconhecer o GMV proporcionalmente ao valor líquido pago;
- recalcular créditos pagos, desempenho, take rate e repasses sem o fanout;
- disponibilizar controles de cardinalidade e consultas de reconciliação.

Dialeto: **GoogleSQL / BigQuery**.

O resultado é materializado em `validation.generator_report_corrected_temp_tables`. Assim como o script 03, esta implementação permanece candidata até a validação das regras de seleção do instrumento e de liquidação proporcional com o negócio.

---

## Documentação complementar

### Construção por coluna

[`generator_report_column_discovery.md`](generator_report_column_discovery.md)

Documenta as 22 colunas finais da view, incluindo:

- conceito funcional;
- campo e tabela de origem;
- tipo de atribuição;
- regra SQL;
- dependências intermediárias;
- riscos observados na implementação original.

### Findings críticos

[`generator_report_critical_findings.md`](generator_report_critical_findings.md)

Consolida os quatro pontos upstream mais relevantes encontrados na análise:

1. fanout entre billing, boleto e PIX;
2. valor proporcional calculado e ignorado pelo legado;
3. perda de centavos por divisão inteira;
4. divergência no cálculo do desempenho Lemon.

O documento também mostra quais métricas apenas propagam valores divergentes apesar de suas fórmulas finais estarem matematicamente consistentes.

---

## Diagramas

| Etapa | SQL correspondente | Diagrama | Papel no trabalho |
| --- | --- | --- | --- |
| SQL original da view | [`01_generator_report_original_sqlite.sql`](../../sql/generator_report/01_generator_report_original_sqlite.sql) | [`generator_report_original_sqlite.svg`](diagrams/generator_report_original_sqlite.svg) | Mostra a composição `AS IS` da view extraída do SQLite. |
| Paridade com tabelas temporárias | [`02_generator_report_legacy_temp_tables.sql`](../../sql/generator_report/02_generator_report_legacy_temp_tables.sql) | [`generator_report_legacy_temp_tables.svg`](diagrams/generator_report_legacy_temp_tables.svg) | Expõe as etapas intermediárias, os relacionamentos, o fanout, o diagnóstico e a reconciliação com o resultado original. |
| Candidato refatorado e corrigido | [`03_generator_report_refactored_candidate.sql`](../../sql/generator_report/03_generator_report_refactored_candidate.sql) | [`generator_report_refactored_candidate.svg`](diagrams/generator_report_refactored_candidate.svg) | Representa o fluxo proposto após as correções técnicas identificadas na engenharia reversa. |

Os arquivos SVG são as referências visuais exportadas. Caso os respectivos arquivos-fonte editáveis sejam adicionados futuramente, devem manter os mesmos nomes-base e usar a extensão da ferramenta de origem, como `.mmd` ou `.excalidraw`.

---

## Fluxo consolidado da análise

```text
SQLite / DBeaver
        │
        ▼
01_generator_report_original_sqlite.sql
        │
        │ tradução com preservação da lógica
        ▼
02_generator_report_legacy_temp_tables.sql
        │
        ├── inspeção etapa a etapa
        ├── diagnóstico de fanout
        ├── reconciliação com o SQLite
        └── identificação dos findings críticos
                    │
                    ▼
03_generator_report_refactored_candidate.sql
        ├───────────┴───────────┐
        ▼                       ▼
view candidata          04_corrected_temp_tables.sql
        │                       │
        └───────────┬───────────┘
                    ▼
       reconciliação das implementações
                    │
                    ▼
reconciliação legado × candidato
                    │
                    ▼
validação das regras de negócio
```

---

## Estrutura de arquivos

```text
docs/
└── generator_report/
    ├── README.md
    ├── generator_report_column_discovery.md
    ├── generator_report_critical_findings.md
    └── diagrams/
        ├── generator_report_original_sqlite.svg
        ├── generator_report_legacy_temp_tables.svg
        └── generator_report_refactored_candidate.svg

sql/
└── generator_report/
    ├── 01_generator_report_original_sqlite.sql
    ├── 02_generator_report_legacy_temp_tables.sql
    ├── 03_generator_report_refactored_candidate.sql
    └── 04_generator_report_corrected_temp_tables.sql
```

---

## Regra de interpretação

Durante a leitura da documentação:

- **FATO** significa comportamento comprovado pelo schema, pelos dados ou pelo SQL original;
- **HIPÓTESE** significa interpretação plausível ainda não confirmada pelo negócio;
- **DESCONHECIDO** significa que não existe evidência suficiente para concluir.

A versão original é a referência de paridade técnica, mas não representa automaticamente a regra de negócio correta. A versão candidata representa uma proposta de correção, mas também não deve ser tratada automaticamente como verdade sem validação.
