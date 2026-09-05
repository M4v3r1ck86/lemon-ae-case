"""Adaptador HTTP e integração com o Cloud Storage."""

from __future__ import annotations

import json
import logging
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import functions_framework
from google.api_core.exceptions import PreconditionFailed
from google.cloud import storage

from ingestion_core import (
    DEFAULT_FILE_NAME,
    InvalidDatabaseError,
    Settings,
    SourceDownloadError,
    build_object_name,
    calculate_sha256,
    download_database,
    validate_sqlite_database,
)


LOGGER = logging.getLogger(__name__)


def upload_if_absent(
    storage_client: storage.Client,
    bucket_name: str,
    database_path: Path,
    object_name: str,
    source_sha256: str,
) -> bool:
    """Envia o arquivo ao GCS sem sobrescrever uma cópia existente."""
    blob = storage_client.bucket(bucket_name).blob(object_name)
    blob.metadata = {
        "sha256": source_sha256,
        "source_format": "sqlite3",
        "ingested_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        blob.upload_from_filename(
            str(database_path),
            content_type="application/vnd.sqlite3",
            if_generation_match=0,
            timeout=120,
        )
        return True
    except PreconditionFailed:
        # A precondição falha quando o objeto já existe: o retry continua seguro.
        return False


def execute_ingestion(
    settings: Settings,
    storage_client: storage.Client,
) -> dict[str, object]:
    """Orquestra download, validação, identificação e persistência."""
    with tempfile.TemporaryDirectory(prefix="lemon_ingestion_") as directory:
        database_path = Path(directory) / DEFAULT_FILE_NAME
        file_size_bytes = download_database(
            settings.source_url,
            database_path,
            settings.max_file_size_bytes,
        )
        validate_sqlite_database(database_path)
        source_sha256 = calculate_sha256(database_path)
        object_name = build_object_name(settings.object_prefix, source_sha256)
        object_created = upload_if_absent(
            storage_client,
            settings.bucket_name,
            database_path,
            object_name,
            source_sha256,
        )

    return {
        "status": "created" if object_created else "already_exists",
        "bucket": settings.bucket_name,
        "object": object_name,
        "gcs_uri": f"gs://{settings.bucket_name}/{object_name}",
        "sha256": source_sha256,
        "size_bytes": file_size_bytes,
    }


def json_response(payload: dict[str, object], status_code: int):
    """Padroniza as respostas HTTP da função."""
    return (
        json.dumps(payload, ensure_ascii=False),
        status_code,
        {"Content-Type": "application/json; charset=utf-8"},
    )


@functions_framework.http
def ingest_source_database(request):
    """Endpoint autenticado que inicia a ingestão do SQLite para o GCS."""
    if request.method != "POST":
        return json_response({"error": "Only POST is allowed"}, 405)

    try:
        result = execute_ingestion(Settings.from_environment(), storage.Client())
        LOGGER.info(
            "ingestion_finished status=%s object=%s size_bytes=%s",
            result["status"],
            result["object"],
            result["size_bytes"],
        )
        return json_response(result, 200)
    except (InvalidDatabaseError, SourceDownloadError) as error:
        LOGGER.warning("ingestion_rejected error_type=%s", type(error).__name__)
        return json_response({"status": "failed", "error": str(error)}, 422)
    except ValueError as error:
        LOGGER.error("invalid_configuration error=%s", error)
        return json_response({"status": "failed", "error": str(error)}, 500)
    except Exception as error:  # noqa: BLE001 - fronteira HTTP da aplicação
        # Evita devolver detalhes internos ou a URL assinada para o cliente.
        LOGGER.error("ingestion_failed error_type=%s", type(error).__name__)
        return json_response(
            {"status": "failed", "error": "Unexpected ingestion error"},
            500,
        )
