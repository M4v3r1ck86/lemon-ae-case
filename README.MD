# Lemon Generator Report

Solução do case de Analytics Engineering da Lemon Energia para a construção de
um produto de dados a partir da engenharia reversa da view
`generator_report`.

Este primeiro incremento implementa a ingestão e a preservação imutável do
arquivo SQLite fornecido no case. As transformações analíticas das camadas
`raw`, `trusted` e `refined` serão implementadas posteriormente no BigQuery,
exclusivamente em SQL e seguindo a arquitetura lakehouse medallion solicitada.

## Fluxo implementado

```text
URL HTTPS armazenada no Secret Manager
        |
        v
Cloud Run function HTTP autenticada
        |
        +--> download para o filesystem temporário da instância
        +--> validação do cabeçalho e da integridade do SQLite
        +--> cálculo do SHA-256 do conteúdo
        +--> geração de um caminho determinístico
        |
        v
Cloud Storage — cópia original para auditoria e replay
```

O download temporário existe porque a validação de integridade abre o arquivo
localmente com o módulo `sqlite3`. O código utiliza
`tempfile.TemporaryDirectory`, que seleciona o diretório temporário do runtime
(normalmente `/tmp` no Cloud Run) e remove o arquivo ao concluir a requisição.
Esse armazenamento é efêmero e não representa uma camada de dados.

O bucket também não representa a camada `raw`: ele funciona somente como
landing/source archive do arquivo original recebido.

## Estrutura do repositório

```text
./
├── functions/
│   └── source_ingestion/
│       ├── main.py             # endpoint HTTP e integração com o GCS
│       ├── ingestion_core.py   # configuração, download, validação e hash
│       ├── requirements.txt
│       └── tests/
│           └── test_main.py
├── .gitignore
└── README.md
```

A separação mantém as regras de ingestão testáveis sem depender do Google
Cloud, mas evita camadas desnecessárias para um MVP pequeno.

## Configuração

| Variável | Obrigatória | Descrição |
|---|---:|---|
| `SOURCE_DB_URL` | Sim | URL HTTPS injetada a partir do Secret Manager |
| `LANDING_BUCKET` | Sim | Bucket de destino; neste case, `lemon-ae-case-ingestion-landing` |
| `OBJECT_PREFIX` | Não | Prefixo do objeto; padrão: `generator-report/sqlite` |
| `MAX_FILE_SIZE_BYTES` | Não | Limite do download; padrão: `52428800` (50 MiB) |

A URL da origem não deve ser commitada, registrada nos logs ou devolvida pela
API. Como ela pode expirar, deve ser atualizada no Secret Manager quando
necessário.

## Idempotência e rastreabilidade

Depois da validação, o SHA-256 é calculado a partir dos bytes do arquivo. O hash
passa a identificar o conteúdo e compõe o caminho do objeto:

```text
gs://lemon-ae-case-ingestion-landing/
└── generator-report/sqlite/
    └── sha256=<hash>/
        └── Lemon_Case_Tecnico_AE.db
```

O upload utiliza a precondição `if_generation_match=0`, que permite criar o
objeto somente quando ele ainda não existe. Uma nova chamada com o mesmo
conteúdo produz o mesmo hash e o mesmo caminho; nesse caso, a função responde
`already_exists` e não sobrescreve a cópia preservada.

## Cloud Run function

Configuração de referência para reproduzir o MVP:

| Campo | Valor |
|---|---|
| Nome | `lemon-source-ingestion` |
| Região | `southamerica-east1` |
| Runtime | Python 3.14 com stack `google-24-full` |
| Entry point | `ingest_source_database` |
| Autenticação | Obrigatória |
| Instâncias mínimas | `0` |
| Instâncias máximas | `1` |
| Memória | `512 MiB` |
| Timeout | `300 segundos` |
| Concorrência | `1` |

A identidade de execução da função recebe somente:

- `roles/storage.objectCreator` no bucket de landing;
- `roles/secretmanager.secretAccessor` no segredo que contém a URL da origem.

A identidade que chama o endpoint precisa de permissão para invocar o serviço.
A função não precisa de acesso ao BigQuery neste incremento.

O stack `google-24-full` é utilizado porque a validação depende do módulo
`sqlite3` e da biblioteca de sistema `libsqlite3.so.0`. O stack mínimo usado na
primeira implantação não continha essa biblioteca.

## Testes unitários

Os testes cobrem:

- aceitação de um banco SQLite íntegro;
- rejeição de um arquivo que não seja SQLite;
- geração determinística do hash e do caminho no GCS.

Para isolar as dependências do projeto, crie um ambiente virtual na raiz do
repositório. No PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r functions/source_ingestion/requirements.txt
python -m unittest discover -s functions/source_ingestion/tests -v
```

Depois da ativação, o VS Code deve utilizar o interpretador
`.venv\Scripts\python.exe`. Caso ele não seja selecionado automaticamente, use
`Python: Select Interpreter` na paleta de comandos do VS Code.

Se a política do PowerShell impedir a ativação do script, não é necessário
alterar a política do sistema. Use diretamente o executável do ambiente:

```powershell
.\.venv\Scripts\python.exe -m pip install -r functions/source_ingestion/requirements.txt
.\.venv\Scripts\python.exe -m unittest discover -s functions/source_ingestion/tests -v
```

O resultado esperado é:

```text
Ran 3 tests

OK
```

Para encerrar o ambiente ativado, execute `deactivate`. A pasta `.venv` é apenas
local, está coberta pelo `.gitignore` e não deve ser enviada ao repositório. O
Cloud Run recria o ambiente durante o build usando o `requirements.txt`.

Se o terminal não reconhecer `python` antes da criação da `.venv`, selecione ou
instale um interpretador Python no VS Code. Em instalações do Windows que
disponibilizam o Python Launcher, crie o ambiente com `py -m venv .venv`.

## Teste de integração

Com a função implantada e o usuário autenticado no Google Cloud, uma chamada
manual pode ser feita pelo Cloud Shell:

```bash
curl -X POST "<CLOUD_RUN_URL>" \
  -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Na primeira execução de um conteúdo, o retorno deve informar `created`. A
repetição com o mesmo arquivo deve informar `already_exists`, com o mesmo
`gcs_uri` e SHA-256.

## Critérios de aceite do incremento

- a chamada HTTP aceita somente `POST`;
- o download respeita o limite máximo configurado;
- o arquivo recebido possui formato SQLite e passa no `PRAGMA integrity_check`;
- o objeto preservado possui o SHA-256 do arquivo validado;
- a URL assinada não aparece nos logs nem no retorno;
- a repetição da execução não duplica nem sobrescreve o conteúdo;
- a cópia preservada fica disponível para auditoria e replay.
