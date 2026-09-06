"""Pure SQLite extraction helpers for the SQLite-to-BigQuery raw job."""

from __future__ import annotations

import base64
import json
import math
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


INGESTED_AT_COLUMN = "_ingested_at"
_BIGQUERY_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_MAX_SAFE_JSON_INTEGER = 9_007_199_254_740_991


@dataclass(frozen=True)
class Column:
    """A source column and its destination BigQuery type."""

    name: str
    bigquery_type: str


@dataclass(frozen=True)
class TableExport:
    """Metadata for one table serialized as newline-delimited JSON."""

    table_name: str
    columns: tuple[Column, ...]
    ndjson_path: Path
    row_count: int


def validate_sqlite_database(connection: sqlite3.Connection) -> None:
    """Fail when SQLite reports structural corruption."""

    result = connection.execute("PRAGMA quick_check").fetchone()
    if result is None or result[0] != "ok":
        details = result[0] if result else "no result"
        raise ValueError(f"SQLite integrity check failed: {details}")


def list_user_tables(connection: sqlite3.Connection) -> list[str]:
    """Return deterministic user-table names, excluding views and internals."""

    rows = connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """
    ).fetchall()
    return [row[0] for row in rows]


def validate_expected_table_count(table_names: list[str], expected_count: int) -> None:
    if len(table_names) != expected_count:
        raise ValueError(
            f"Expected {expected_count} SQLite tables, found {len(table_names)}: "
            f"{', '.join(table_names) or 'none'}"
        )


def validate_bigquery_identifier(identifier: str, kind: str) -> None:
    """Reject names we cannot preserve safely in BigQuery."""

    if not _BIGQUERY_IDENTIFIER.fullmatch(identifier):
        raise ValueError(
            f"Invalid BigQuery {kind} identifier {identifier!r}; "
            "only letters, numbers and underscores are supported, and the "
            "first character cannot be a number."
        )


def quote_sqlite_identifier(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def sqlite_type_to_bigquery(declared_type: str | None) -> str:
    """Map the relevant SQLite declared types to stable raw-layer types."""

    normalized = (declared_type or "").strip().upper()
    if "INT" in normalized:
        return "INTEGER"
    if any(token in normalized for token in ("REAL", "FLOA", "DOUB")):
        return "FLOAT"
    if "BOOL" in normalized:
        return "BOOLEAN"
    if any(token in normalized for token in ("NUMERIC", "DECIMAL")):
        return "NUMERIC"
    if "BLOB" in normalized:
        return "BYTES"
    return "STRING"


def get_table_columns(connection: sqlite3.Connection, table_name: str) -> tuple[Column, ...]:
    validate_bigquery_identifier(table_name, "table")
    rows = connection.execute(
        f"PRAGMA table_info({quote_sqlite_identifier(table_name)})"
    ).fetchall()
    if not rows:
        raise ValueError(f"SQLite table {table_name!r} has no columns")

    columns = tuple(Column(row[1], sqlite_type_to_bigquery(row[2])) for row in rows)
    normalized_names: set[str] = set()
    for column in columns:
        validate_bigquery_identifier(column.name, "column")
        normalized_name = column.name.casefold()
        if normalized_name == INGESTED_AT_COLUMN.casefold():
            raise ValueError(
                f"SQLite table {table_name!r} already contains reserved column "
                f"{INGESTED_AT_COLUMN!r}"
            )
        if normalized_name in normalized_names:
            raise ValueError(
                f"SQLite table {table_name!r} contains duplicate column "
                f"{column.name!r} for BigQuery"
            )
        normalized_names.add(normalized_name)
    return columns


def _normalize_value(value: Any, bigquery_type: str) -> Any:
    if value is None:
        return None
    if bigquery_type == "INTEGER":
        integer = int(value)
        return str(integer) if abs(integer) > _MAX_SAFE_JSON_INTEGER else integer
    if bigquery_type == "FLOAT":
        number = float(value)
        if math.isnan(number):
            return "NaN"
        if math.isinf(number):
            return "Infinity" if number > 0 else "-Infinity"
        return number
    if bigquery_type == "NUMERIC":
        return str(value)
    if bigquery_type == "BOOLEAN":
        if isinstance(value, str):
            normalized = value.strip().casefold()
            if normalized in {"1", "true", "t", "yes", "y"}:
                return True
            if normalized in {"0", "false", "f", "no", "n"}:
                return False
            raise ValueError(f"Cannot convert {value!r} to BOOLEAN")
        return bool(value)
    if bigquery_type == "BYTES":
        raw_value = value if isinstance(value, bytes) else str(value).encode("utf-8")
        return base64.b64encode(raw_value).decode("ascii")
    return value if isinstance(value, str) else str(value)


def export_table_to_ndjson(
    connection: sqlite3.Connection,
    table_name: str,
    destination: Path,
    ingested_at: datetime,
    batch_size: int = 1_000,
) -> TableExport:
    """Stream one SQLite table to a local NDJSON file."""

    columns = get_table_columns(connection, table_name)
    selected_columns = ", ".join(quote_sqlite_identifier(column.name) for column in columns)
    cursor = connection.execute(
        f"SELECT {selected_columns} FROM {quote_sqlite_identifier(table_name)}"
    )
    ingestion_timestamp = ingested_at.isoformat().replace("+00:00", "Z")
    row_count = 0

    with destination.open("w", encoding="utf-8", newline="\n") as output:
        while rows := cursor.fetchmany(batch_size):
            for row in rows:
                record = {
                    column.name: _normalize_value(value, column.bigquery_type)
                    for column, value in zip(columns, row, strict=True)
                }
                record[INGESTED_AT_COLUMN] = ingestion_timestamp
                output.write(
                    json.dumps(
                        record,
                        ensure_ascii=False,
                        separators=(",", ":"),
                        allow_nan=False,
                    )
                )
                output.write("\n")
                row_count += 1

    return TableExport(table_name, columns, destination, row_count)
