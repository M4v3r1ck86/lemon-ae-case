import base64
import json
import sqlite3
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path

MODULE_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODULE_DIRECTORY))

from sqlite_loader import (
    export_table_to_ndjson,
    list_user_tables,
    sqlite_type_to_bigquery,
    validate_expected_table_count,
    validate_sqlite_database,
)


class SQLiteLoaderTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.database_path = Path(self.temporary_directory.name) / "source.db"
        self.connection = sqlite3.connect(self.database_path)

    def tearDown(self):
        self.connection.close()
        self.temporary_directory.cleanup()

    def test_discovers_only_user_tables_in_deterministic_order(self):
        self.connection.execute(
            "CREATE TABLE publishers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)"
        )
        self.connection.execute("CREATE TABLE authors (id INTEGER, name TEXT)")
        self.connection.execute("CREATE VIEW author_names AS SELECT name FROM authors")

        self.assertEqual(
            list_user_tables(self.connection),
            ["authors", "publishers"],
        )

    def test_validates_integrity_and_expected_table_count(self):
        for index in range(8):
            self.connection.execute(f"CREATE TABLE table_{index} (id INTEGER)")

        validate_sqlite_database(self.connection)
        validate_expected_table_count(list_user_tables(self.connection), 8)

        with self.assertRaisesRegex(ValueError, "Expected 7 SQLite tables, found 8"):
            validate_expected_table_count(list_user_tables(self.connection), 7)

    def test_maps_sqlite_declared_types(self):
        self.assertEqual(sqlite_type_to_bigquery("INTEGER"), "INTEGER")
        self.assertEqual(sqlite_type_to_bigquery("DOUBLE"), "FLOAT")
        self.assertEqual(sqlite_type_to_bigquery("BOOLEAN"), "BOOLEAN")
        self.assertEqual(sqlite_type_to_bigquery("DECIMAL(10, 2)"), "NUMERIC")
        self.assertEqual(sqlite_type_to_bigquery("BLOB"), "BYTES")
        self.assertEqual(sqlite_type_to_bigquery("VARCHAR(100)"), "STRING")
        self.assertEqual(sqlite_type_to_bigquery("DATETIME"), "STRING")

    def test_exports_source_columns_and_ingestion_timestamp(self):
        self.connection.execute(
            """
            CREATE TABLE books (
                id INTEGER,
                title TEXT,
                rating REAL,
                active BOOLEAN,
                price DECIMAL(10, 2),
                cover BLOB
            )
            """
        )
        self.connection.execute(
            "INSERT INTO books VALUES (?, ?, ?, ?, ?, ?)",
            (1, "Data & Energia", 4.5, 1, "39.90", b"cover"),
        )
        self.connection.commit()
        destination = Path(self.temporary_directory.name) / "books.ndjson"
        ingested_at = datetime(2026, 9, 5, 12, 30, tzinfo=UTC)

        exported = export_table_to_ndjson(
            self.connection,
            "books",
            destination,
            ingested_at,
        )
        record = json.loads(destination.read_text(encoding="utf-8"))

        self.assertEqual(exported.row_count, 1)
        self.assertEqual(record["id"], 1)
        self.assertEqual(record["title"], "Data & Energia")
        self.assertEqual(record["rating"], 4.5)
        self.assertIs(record["active"], True)
        self.assertEqual(record["price"], "39.9")
        self.assertEqual(record["cover"], base64.b64encode(b"cover").decode("ascii"))
        self.assertEqual(record["_ingested_at"], "2026-09-05T12:30:00Z")


if __name__ == "__main__":
    unittest.main()
