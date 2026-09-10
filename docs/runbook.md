# Runbook operacional

Este documento descreve como implantar, executar e verificar o fluxo atual. A
URL da fonte e credenciais não devem aparecer em comandos, logs ou commits.

## Inventário

| Recurso | Valor atual |
|---|---|
| Projeto / região | `lemon-ae-case` / `southamerica-east1` |
| Função de ingestão | `lemon-source-ingestion` |
| Job SQLite → Raw | `lemon-sqlite-to-raw` |
| Landing / segredo | `lemon-ae-case-ingestion-landing` / `lemon-source-db-url` |
| Artifact Registry | `lemon-data-pipelines` |
| Datasets | `raw`, `trusted`, `refined`, `validation` |
| Raw | 8 tabelas |
| Trusted | 11 tabelas e 11 procedures |
| Refined | 1 tabela, 1 procedure e 1 view versionada |
| Validation | Scripts de paridade, candidatos e diagnóstico executados sob demanda |

## Preparação

```bash
gcloud auth list
gcloud config set account "<USER_EMAIL>"
gcloud config set project "lemon-ae-case"
```

Confirme que o segredo, o bucket, os datasets e as contas de serviço existem.
A região dos jobs e a localização do BigQuery devem ser compatíveis.

## Pipelines do Cloud Build

| Arquivo | Ações | Executa carga? |
|---|---|---:|
| `cloudbuild.yaml` | Testa e implanta `lemon-source-ingestion` com variáveis, segredo e contas de runtime/build | Não |
| `cloudbuild-sqlite-to-raw.yaml` | Testa o loader, constrói e publica a imagem `${SHORT_SHA}` e implanta `lemon-sqlite-to-raw` | Não |
| `cloudbuild-ddl-trusted.yaml` | Ordena e executa `sql/ddl/trusted/ddl_*.sql` | Não |
| `cloudbuild-procedures-trusted.yaml` | Cria ou substitui as procedures de `sql/procedures/trusted` | Não |
| `cloudbuild-ddl-refined.yaml` | Executa os DDLs de `sql/ddl/refined` | Não |
| `cloudbuild-procedures-refined.yaml` | Cria ou substitui as procedures de `sql/procedures/refined` | Não |

Os gatilhos acompanham os pushes e caminhos configurados no GitHub. Um build
verde confirma que o artefato foi publicado; não significa que os dados foram
recarregados. Os pipelines de procedures não executam `CALL`, e o pipeline do
job não usa `--execute-now`.

Os DDLs usam `CREATE TABLE IF NOT EXISTS`. Alterar um DDL não modifica uma
tabela já existente; mudanças de schema exigem uma migração SQL explícita.

### View de apresentação

`sql/view/refined/vw_relatorio_gerador_apresentacao.sql` não é incluído pelos
pipelines SQL atuais. Enquanto não houver um pipeline de views:

```bash
bq query \
  --project_id="lemon-ae-case" \
  --location="southamerica-east1" \
  --use_legacy_sql=false \
  < sql/view/refined/vw_relatorio_gerador_apresentacao.sql
```

## Execução ponta a ponta

### 1. Preservar a origem

A função lê no Secret Manager o endpoint fornecido pela página do case em
Notion. Para acioná-la:

```bash
curl -X POST \
  "https://lemon-source-ingestion-658804472867.southamerica-east1.run.app" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{}'
```

`created` indica novo conteúdo; `already_exists` indica que os mesmos bytes já
estavam preservados. Se o hash mudar, atualize conscientemente `_SOURCE_OBJECT`
em `cloudbuild-sqlite-to-raw.yaml` antes do deploy do job.

### 2. Carregar a Raw

```bash
gcloud run jobs execute "lemon-sqlite-to-raw" \
  --region="southamerica-east1" \
  --project="lemon-ae-case" \
  --wait
```

O resultado esperado é a carga integral das oito tabelas e a igualdade entre
as contagens exportadas do SQLite e carregadas no BigQuery.

### 3. Carregar a Trusted

Execute os `CALL` na ordem abaixo. As oito primeiras entidades dependem apenas
da Raw e podem ser paralelizadas no futuro; a ordem sequencial facilita a
auditoria manual.

```sql
CALL `lemon-ae-case.trusted.sp_carregar_boleto`();
CALL `lemon-ae-case.trusted.sp_carregar_pix`();
CALL `lemon-ae-case.trusted.sp_carregar_relacao_financeira`();
CALL `lemon-ae-case.trusted.sp_carregar_cobranca`();
CALL `lemon-ae-case.trusted.sp_carregar_faturamento`();
CALL `lemon-ae-case.trusted.sp_carregar_cliente_energia_mensal`();
CALL `lemon-ae-case.trusted.sp_carregar_usina_energia_mensal`();
CALL `lemon-ae-case.trusted.sp_carregar_faixa_take_rate_gerador`();

CALL `lemon-ae-case.trusted.sp_carregar_instrumento_pagamento`();
CALL `lemon-ae-case.trusted.sp_carregar_faturamento_cliente_mensal`();
CALL `lemon-ae-case.trusted.sp_carregar_desempenho_usina_mensal`();
```

```text
boleto + pix + relacao_financeira
  → instrumento_pagamento

cliente_energia_mensal + cobranca + faturamento + instrumento_pagamento
  → faturamento_cliente_mensal

usina_energia_mensal + cliente_energia_mensal + faturamento_cliente_mensal
  → desempenho_usina_mensal
```

### 4. Carregar a Refined

Depois de `desempenho_usina_mensal` e `faixa_take_rate_gerador`:

```sql
CALL `lemon-ae-case.refined.sp_carregar_relatorio_gerador_mensal`();
```

A procedure usa `INNER JOIN` com vigência e faixa de desempenho. Linhas sem
faixa aplicável não chegam ao relatório; faixas sobrepostas podem duplicar
linhas. Valide esse contrato após a carga.

## Verificações pós-carga

### Inventário

```sql
SELECT table_schema, table_name, table_type
FROM `lemon-ae-case`.`region-southamerica-east1`.INFORMATION_SCHEMA.TABLES
WHERE table_schema IN ('raw', 'trusted', 'refined')
ORDER BY table_schema, table_name;
```

```sql
SELECT routine_schema, routine_name, routine_type
FROM `lemon-ae-case`.`region-southamerica-east1`.INFORMATION_SCHEMA.ROUTINES
WHERE routine_schema IN ('trusted', 'refined')
ORDER BY routine_schema, routine_name;
```

### Metadado e volumes

```sql
SELECT table_name, column_name, data_type
FROM `lemon-ae-case`.raw.INFORMATION_SCHEMA.COLUMNS
WHERE column_name = '_ingested_at'
ORDER BY table_name;
```

```sql
SELECT 'cliente_energia_mensal' AS tabela, COUNT(*) AS linhas
FROM `lemon-ae-case.trusted.cliente_energia_mensal`
UNION ALL
SELECT 'desempenho_usina_mensal', COUNT(*)
FROM `lemon-ae-case.trusted.desempenho_usina_mensal`
UNION ALL
SELECT 'relatorio_gerador_mensal', COUNT(*)
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`;
```

### Unicidade

```sql
SELECT id_instalacao, dt_mes_referencia, COUNT(*) AS quantidade
FROM `lemon-ae-case.trusted.cliente_energia_mensal`
GROUP BY 1, 2
HAVING COUNT(*) > 1;

SELECT gerador, usina, cod_distribuidora, dt_mes_referencia, COUNT(*) AS quantidade
FROM `lemon-ae-case.refined.relatorio_gerador_mensal`
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) > 1;
```

Resultado esperado: zero linhas nas duas consultas.

### Cobertura de take rate

```sql
SELECT
  d.gerador, d.usina, d.cod_distribuidora, d.dt_mes_referencia,
  COUNT(f.id_take_rate) AS faixas_aplicaveis
FROM `lemon-ae-case.trusted.desempenho_usina_mensal` AS d
LEFT JOIN `lemon-ae-case.trusted.faixa_take_rate_gerador` AS f
  ON f.gerador = d.gerador
 AND f.cod_distribuidora = d.cod_distribuidora
 AND d.dt_mes_referencia BETWEEN f.dt_inicio_vigencia AND f.dt_fim_vigencia
 AND COALESCE(d.perc_desempenho_lemon, 0) >= f.perc_desempenho_min
 AND COALESCE(d.perc_desempenho_lemon, 0) < f.perc_desempenho_max
GROUP BY 1, 2, 3, 4
HAVING faixas_aplicaveis != 1;
```

Resultado esperado: zero linhas.

## Testes locais

No PowerShell, a partir da raiz:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip

python -m pip install -r functions/source_ingestion/requirements.txt
python -m unittest discover -s functions/source_ingestion/tests -v

python -m pip install -r jobs/sqlite_to_raw/requirements.txt
python -m unittest discover -s jobs/sqlite_to_raw/tests -v
```

## Auditoria do Cloud Build

```bash
gcloud builds triggers list \
  --region="southamerica-east1" \
  --project="lemon-ae-case"

gcloud builds triggers describe "<TRIGGER_NAME>" \
  --region="southamerica-east1" \
  --project="lemon-ae-case" \
  --format="yaml(name,serviceAccount,filename,includedFiles,ignoredFiles)"

gcloud builds list \
  --region="southamerica-east1" \
  --project="lemon-ae-case" \
  --limit=20
```

## Troubleshooting

### Build verde, mas dados antigos

O pipeline implantou o artefato, mas não executou a carga. Execute o Cloud Run
Job e os `CALL` na ordem deste runbook.

### Tabela não mudou após alteração no DDL

`CREATE TABLE IF NOT EXISTS` não altera tabelas existentes. Versione uma
migração compatível, como `ALTER TABLE` ou criação e promoção de nova tabela.

### Procedure falha por tabela ausente

Verifique a publicação do DDL, o dataset e a ordem das dependências.

### Refined possui menos linhas que a Trusted de desempenho

Execute a validação de cobertura de take rate. Provavelmente existe uma linha
sem faixa válida para gerador, distribuidora, competência e desempenho.

### `ImportError: libsqlite3.so.0`

A função usa `google-24-full/python314`; o Dockerfile do job instala
`libsqlite3-0`. Preserve essas configurações.

### Deploy por source tenta usar a conta padrão

O deploy deve informar `--build-service-account`, e a identidade precisa da
permissão `roles/iam.serviceAccountUser` aplicável.

### Cloud Shell sem conta ativa ou IAM solicita condição

Configure novamente conta/projeto. Para um binding incondicional, informe
`--condition=None`.

### Retry cria outro build ID

É esperado: cada retry é uma nova execução e o build anterior permanece no
histórico.

## Segurança operacional

- nunca registrar ou commitar a URL do endpoint;
- não criar chaves JSON de contas de serviço;
- manter o endpoint autenticado e os acessos no menor escopo;
- usar tags de imagem ligadas ao commit;
- conferir o objeto de origem antes de truncar e recarregar a Raw;
- validar cada camada antes de executar a próxima.

## Evolução para Airflow

O DAG futuro deverá representar cada fronteira como uma task observável:
ingestão, Raw Loader, procedures base Trusted, integrações Trusted, Refined e
validações. Ele deverá respeitar as dependências acima, paralelizar somente
entidades independentes e oferecer retries, alertas e histórico de execução.
