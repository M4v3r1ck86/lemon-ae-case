"""Regras independentes de Google Cloud para a ingestão do arquivo SQLite."""

from __future__ import annotations

import hashlib
import os
import sqlite3
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path


SQLITE_HEADER = b"SQLite format 3\x00"
DEFAULT_FILE_NAME = "Lemon_Case_Tecnico_AE.db"
DEFAULT_OBJECT_PREFIX = "generator-report/sqlite"
DEFAULT_MAX_FILE_SIZE_BYTES = 50 * 1024 * 1024


class SourceDownloadError(RuntimeError):
    """Indica que o arquivo não pôde ser obtido na origem."""


class InvalidDatabaseError(ValueError):
    """Indica que o arquivo recebido não é um banco SQLite íntegro."""


@dataclass(frozen=True)
class Settings:
    """Centraliza e valida as configurações externas da função."""

    source_url: str
    bucket_name: str
    object_prefix: str
    max_file_size_bytes: int

    @classmethod
    def from_environment(cls) -> "Settings":
        """Cria a configuração a partir das variáveis do Cloud Run."""
        source_url = os.environ.get("SOURCE_DB_URL", "").strip()
        bucket_name = os.environ.get("LANDING_BUCKET", "").strip()
        object_prefix = os.environ.get(
            "OBJECT_PREFIX", DEFAULT_OBJECT_PREFIX
        ).strip("/")

        if not source_url or not bucket_name:
            raise ValueError(
                "SOURCE_DB_URL and LANDING_BUCKET environment variables are required"
            )

        parsed_url = urllib.parse.urlparse(source_url)
        if parsed_url.scheme != "https" or not parsed_url.netloc:
            raise ValueError("SOURCE_DB_URL must be a valid HTTPS URL")

        max_file_size_bytes = int(
            os.environ.get(
                "MAX_FILE_SIZE_BYTES", str(DEFAULT_MAX_FILE_SIZE_BYTES)
            )
        )
        if max_file_size_bytes <= 0:
            raise ValueError("MAX_FILE_SIZE_BYTES must be greater than zero")

        return cls(
            source_url=source_url,
            bucket_name=bucket_name,
            object_prefix=object_prefix,
            max_file_size_bytes=max_file_size_bytes,
        )


def download_database(
    source_url: str,
    destination: Path,
    max_file_size_bytes: int,
) -> int:
    """Baixa o arquivo por streaming e interrompe cargas acima do limite."""
    request = urllib.request.Request(
        source_url,
        headers={"User-Agent": "lemon-generator-report-ingestion/1.0"},
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            declared_size = int(response.headers.get("Content-Length", 0))
            if declared_size > max_file_size_bytes:
                raise InvalidDatabaseError("Source file exceeds the configured limit")

            downloaded_size = 0
            with destination.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    downloaded_size += len(chunk)
                    if downloaded_size > max_file_size_bytes:
                        raise InvalidDatabaseError(
                            "Source file exceeds the configured limit"
                        )
                    output.write(chunk)
    except InvalidDatabaseError:
        raise
    except urllib.error.HTTPError as error:
        # A mensagem não inclui a URL assinada, que é uma configuração sensível.
        raise SourceDownloadError(
            f"Source returned HTTP {error.code}"
        ) from None
    except urllib.error.URLError:
        raise SourceDownloadError("Could not connect to the source") from None

    if downloaded_size == 0:
        raise InvalidDatabaseError("Downloaded file is empty")
    return downloaded_size


def validate_sqlite_database(database_path: Path) -> None:
    """Confirma o formato SQLite e executa a verificação de integridade."""
    with database_path.open("rb") as source:
        if source.read(len(SQLITE_HEADER)) != SQLITE_HEADER:
            raise InvalidDatabaseError("Downloaded file is not a SQLite 3 database")

    connection = sqlite3.connect(
        f"file:{database_path.as_posix()}?mode=ro",
        uri=True,
    )
    try:
        integrity_result = connection.execute("PRAGMA integrity_check").fetchone()
        if not integrity_result or integrity_result[0] != "ok":
            raise InvalidDatabaseError("SQLite integrity check failed")
    finally:
        connection.close()


def calculate_sha256(file_path: Path) -> str:
    """Calcula o hash usado para rastreabilidade e idempotência."""
    digest = hashlib.sha256()
    with file_path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_object_name(object_prefix: str, source_sha256: str) -> str:
    """Gera um caminho determinístico para que o mesmo arquivo não seja duplicado."""
    return f"{object_prefix}/sha256={source_sha256}/{DEFAULT_FILE_NAME}"
