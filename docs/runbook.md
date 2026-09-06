# Runbook, verificações e troubleshooting

Este documento registra como reproduzir e operar o incremento atual. Os
comandos não contêm a URL assinada da fonte nem credenciais persistentes.

## Inventário

| Recurso | Valor |
|---|---|
| Projeto | `lemon-ae-case` |
| Região | `southamerica-east1` |
| Função/serviço | `lemon-source-ingestion` |
| Job | `lemon-sqlite-to-raw` |
| Bucket | `lemon-ae-case-ingestion-landing` |
| Dataset | `raw` |
| Segredo | `lemon-source-db-url` |
| Artifact Registry do job | `lemon-data-pipelines` |

## Preparação do Cloud Shell

Confirme a conta e o projeto ativos antes de executar comandos administrativos:

```bash
gcloud auth list
gcloud config set account "<USER_EMAIL>"
gcloud config set project "lemon-ae-case"
```

## Testes locais

No PowerShell, a partir da raiz do repositório:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
```

### Source ingestion

```powershell
python -m pip install -r functions/source_ingestion/requirements.txt
python -m unittest discover -s functions/source_ingestion/tests -v
```

Resultado esperado:

```text
Ran 3 tests
OK
```

### SQLite to raw

```powershell
python -m pip install -r jobs/sqlite_to_raw/requirements.txt
python -m unittest discover -s jobs/sqlite_to_raw/tests -v
```

Resultado esperado:

```text
Ran 4 tests
OK
```

## Source ingestion

### Configuração do runtime

| Campo | Valor |
|---|---|
| Nome | `lemon-source-ingestion` |
| Runtime | Python 3.14 |
| Base | `google-24-full/python314` |
| Entry point | `ingest_source_database` |
| Runtime SA | `sa-lemon-source-ingestion@lemon-ae-case.iam.gserviceaccount.com` |
| Memória | 512 MiB |
| Timeout | 300 s |
| Concorrência | 1 |
| Instâncias | 0–1 |
| Autenticação | Obrigatória |

Variáveis não sensíveis:

```text
LANDING_BUCKET=lemon-ae-case-ingestion-landing
OBJECT_PREFIX=generator-report/sqlite
MAX_FILE_SIZE_BYTES=52428800
```

Variável proveniente do Secret Manager:

```text
SOURCE_DB_URL=lemon-source-db-url:latest
```

### Teste de integração

```bash
curl -X POST \
  "https://lemon-source-ingestion-658804472867.southamerica-east1.run.app" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Na primeira ingestão do conteúdo, a resposta é `created`. Nas repetições, a
resposta é `already_exists`, mantendo o mesmo SHA-256 e URI.

### Objeto validado

```text
gs://lemon-ae-case-ingestion-landing/generator-report/sqlite/sha256=e42e7355e0783525cfb40364f698e8bef86f4b26925178a9316570fb4982dc1b/Lemon_Case_Tecnico_AE.db
```

Tamanho observado: `5169152` bytes.

## Raw Loader

### Dataset e identidade

O dataset `raw` deve estar em `southamerica-east1`.

Identidade de runtime:

```text
sa-lemon-raw-loader@lemon-ae-case.iam.gserviceaccount.com
```

Acessos necessários:

- `roles/storage.objectViewer` somente no bucket de landing;
- `roles/bigquery.jobUser` no projeto;
- `roles/bigquery.dataEditor` somente no dataset `raw`.

### Permitir que o deployer use a identidade do job

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "sa-lemon-raw-loader@lemon-ae-case.iam.gserviceaccount.com" \
  --member="serviceAccount:sa-lemon-cloud-build-deployer@lemon-ae-case.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser" \
  --project="lemon-ae-case" \
  --condition=None
```

Verificação:

```bash
gcloud iam service-accounts get-iam-policy \
  "sa-lemon-raw-loader@lemon-ae-case.iam.gserviceaccount.com" \
  --project="lemon-ae-case" \
  --format="yaml(bindings)"
```

### Artifact Registry

Criação do repositório dedicado:

```bash
gcloud artifacts repositories create "lemon-data-pipelines" \
  --repository-format="docker" \
  --location="southamerica-east1" \
  --description="Armazena as imagens Docker dos pipelines de dados do case Lemon." \
  --project="lemon-ae-case"
```

Permissão de escrita para o pipeline:

```bash
gcloud artifacts repositories add-iam-policy-binding \
  "lemon-data-pipelines" \
  --location="southamerica-east1" \
  --project="lemon-ae-case" \
  --member="serviceAccount:sa-lemon-cloud-build-deployer@lemon-ae-case.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer" \
  --condition=None
```

### Pipeline do job

Arquivo de configuração:

```text
cloudbuild-sqlite-to-raw.yaml
```

O gatilho deve usar:

| Campo | Valor |
|---|---|
| Nome | `deploy-lemon-sqlite-to-raw` |
| Região | `southamerica-east1` |
| Evento | Push para branch |
| Branch | `^main$` |
| Configuração | Arquivo YAML do repositório |
| Caminho | `cloudbuild-sqlite-to-raw.yaml` |
| Conta de serviço | `sa-lemon-cloud-build-deployer@lemon-ae-case.iam.gserviceaccount.com` |

Filtros recomendados:

```text
Incluídos: jobs/sqlite_to_raw/**,cloudbuild-sqlite-to-raw.yaml
Ignorados: nenhum
```

O pipeline usa a imagem:

```text
southamerica-east1-docker.pkg.dev/lemon-ae-case/lemon-data-pipelines/sqlite-to-raw:<SHORT_SHA>
```

Ele cria ou atualiza o job, mas não usa `--execute-now`.

### Executar o job manualmente

Somente depois que o pipeline de implantação estiver verde:

```bash
gcloud run jobs execute "lemon-sqlite-to-raw" \
  --region="southamerica-east1" \
  --project="lemon-ae-case" \
  --wait
```

### Verificar as tabelas

No BigQuery:

```sql
SELECT
  table_name,
  total_rows
FROM `lemon-ae-case`.`region-southamerica-east1`.INFORMATION_SCHEMA.TABLE_STORAGE
WHERE table_schema = 'raw'
ORDER BY table_name;
```

Resultado esperado: oito tabelas.

Confirme o metadado técnico:

```sql
SELECT
  table_name,
  column_name,
  data_type
FROM `lemon-ae-case`.raw.INFORMATION_SCHEMA.COLUMNS
WHERE column_name = '_ingested_at'
ORDER BY table_name;
```

Resultado esperado: uma coluna `TIMESTAMP` em cada tabela.

## Auditoria do Cloud Build

Verifique qual identidade e arquivo estão configurados no gatilho da ingestão:

```bash
gcloud builds triggers describe "deploy-lemon-source-ingestion" \
  --region="southamerica-east1" \
  --project="lemon-ae-case" \
  --format="yaml(name,serviceAccount,filename)"
```

Liste as contas de serviço e seus identificadores:

```bash
gcloud iam service-accounts list \
  --project="lemon-ae-case" \
  --format="table(displayName,email,uniqueId,disabled)"
```

## Problemas encontrados e correções

### `ImportError: libsqlite3.so.0`

**Sintoma:** a função encerrava antes de abrir a porta 8080 e o startup probe
falhava.

**Causa:** a stack mínima do runtime Python 3.14 não incluía a biblioteca
dinâmica necessária ao módulo `_sqlite3`.

**Correção:** usar `google-24-full/python314` na função. No job, o
`Dockerfile` instala explicitamente `libsqlite3-0`.

### Deploy por source usava a Default Compute Service Account

**Sintoma:** `caller does not have permission to act as service account`, com o
identificador da Default Compute Service Account.

**Causa:** `gcloud run deploy --source` inicia um segundo build interno. A
identidade do gatilho estava correta, mas a identidade desse build não havia
sido informada explicitamente.

**Correção:** adicionar `--build-service-account` ao deploy da função e conceder
à identidade escolhida os papéis de build e a permissão
`roles/iam.serviceAccountUser` necessária.

### Repositório `cloud-run-source-deploy` apareceu sem criação manual

**Explicação:** o deploy por código-fonte do Cloud Run cria automaticamente
esse repositório regional para guardar as imagens produzidas por
Cloud Build/Buildpacks.

**Decisão:** manter esse repositório para a função e criar
`lemon-data-pipelines` para os containers explícitos dos jobs.

### Cloud Shell sem conta ativa

**Sintoma:** `You do not currently have an active account selected`.

**Correção:** conferir `gcloud auth list` e definir novamente `core/account` e
`core/project` com os comandos da seção de preparação.

### IAM solicitou uma condição

**Sintoma:** ao adicionar um binding, o CLI informou que a policy já continha
bindings condicionais e solicitou uma escolha.

**Correção:** declarar `--condition=None` quando o novo acesso deve ser
incondicional. Isso evita seleção interativa ambígua.

### `unittest` não encontrou o diretório inicial

**Sintoma:** `Start directory is not importable`.

**Causa observada:** divergência entre o nome real da pasta e o caminho passado
ao comando.

**Correção:** padronizar a pasta como `tests` e executar o discovery a partir da
raiz do repositório.

### Um retry gerou outro identificador de build

Esse comportamento é esperado. `Tentar novamente` cria uma nova execução com
outro build ID, normalmente para o mesmo commit. A execução anterior permanece
vermelha para preservar o histórico. Um push monitorado também inicia uma nova
execução automaticamente.

### Aviso LF/CRLF no GitHub Desktop

O Windows pode converter finais de linha no checkout. O arquivo
`.gitattributes` fixa LF para Python, YAML, Dockerfile, shell e Markdown,
mantendo os arquivos consistentes com os containers Linux.

## Segurança operacional

- nunca registrar ou commitar a URL assinada;
- não criar chaves JSON para as contas de serviço;
- conceder papéis de dados no bucket/dataset, não no projeto inteiro, quando o
  produto permitir;
- manter o endpoint autenticado;
- revisar IAM após cada novo componente;
- usar tags de imagem vinculadas ao commit;
- não executar o Raw Loader automaticamente até validar o primeiro deploy.
