"""Cloud Run Job entry point for loading an immutable SQLite snapshot into raw."""

from __future__ import annotations

import logging
import os
import sqlite3
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from google.cloud import bigquery, storage

from sqlite_loader import (
    INGESTED_AT_COLUMN,
    TableExport,
    export_table_to_ndjson,
    list_user_tables,
    validate_expected_table_count,
    validate_sqlite_database,
)


logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s",
)
LOGGER = logging.getLogger(__name__)


def required_environment(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Required environment variable {name} is not set")
    return value


def prepare_exports(
    sqlite_path: Path,
    export_directory: Path,
    expected_table_count: int,
    ingested_at: datetime,
) -> list[TableExport]:
    connection = sqlite3.connect(f"{sqlite_path.resolve().as_uri()}?mode=ro", uri=True)
    try:
        validate_sqlite_database(connection)
        table_names = list_user_tables(connection)
        validate_expected_table_count(table_names, expected_table_count)
        LOGGER.info("Validated SQLite snapshot with tables: %s", ", ".join(table_names))
        return [
            export_table_to_ndjson(
                connection,
                table_name,
                export_directory / f"{table_name}.ndjson",
                ingested_at,
            )
            for table_name in table_names
        ]
    finally:
        connection.close()


def load_export(
    client: bigquery.Client,
    project_id: str,
    dataset_id: str,
    location: str,
    export: TableExport,
) -> None:
    table_id = f"{project_id}.{dataset_id}.{export.table_name}"
    schema = [
        bigquery.SchemaField(column.name, column.bigquery_type, mode="NULLABLE")
        for column in export.columns
    ]
    schema.append(bigquery.SchemaField(INGESTED_AT_COLUMN, "TIMESTAMP", mode="REQUIRED"))
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )

    with export.ndjson_path.open("rb") as source_file:
        load_job = client.load_table_from_file(
            source_file,
            table_id,
            location=location,
            job_config=job_config,
            rewind=True,
        )
        load_job.result()

    destination = client.get_table(table_id)
    if destination.num_rows != export.row_count:
        raise RuntimeError(
            f"Row-count mismatch for {table_id}: exported {export.row_count}, "
            f"loaded {destination.num_rows}"
        )
    LOGGER.info("Loaded %s rows into %s", export.row_count, table_id)


def main() -> None:
    project_id = required_environment("GCP_PROJECT_ID")
    source_bucket = required_environment("SOURCE_BUCKET")
    source_object = required_environment("SOURCE_OBJECT")
    dataset_id = os.getenv("BIGQUERY_DATASET", "raw")
    location = os.getenv("BIGQUERY_LOCATION", "southamerica-east1")
    expected_table_count = int(os.getenv("EXPECTED_TABLE_COUNT", "8"))
    ingested_at = datetime.now(UTC)

    LOGGER.info("Starting raw load from gs://%s/%s", source_bucket, source_object)
    with tempfile.TemporaryDirectory(prefix="sqlite-to-raw-") as temporary_directory:
        work_directory = Path(temporary_directory)
        sqlite_path = work_directory / "source.db"
        storage_client = storage.Client(project=project_id)
        storage_client.bucket(source_bucket).blob(source_object).download_to_filename(
            sqlite_path
        )
        LOGGER.info("Downloaded SQLite snapshot to temporary storage")

        exports = prepare_exports(
            sqlite_path,
            work_directory,
            expected_table_count,
            ingested_at,
        )
        bigquery_client = bigquery.Client(project=project_id, location=location)
        for export in exports:
            load_export(
                bigquery_client,
                project_id,
                dataset_id,
                location,
                export,
            )

    LOGGER.info("Raw load completed successfully for %s tables", len(exports))


if __name__ == "__main__":
    main()
