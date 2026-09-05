import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODULE_DIRECTORY))

from ingestion_core import (  # noqa: E402
    InvalidDatabaseError,
    build_object_name,
    calculate_sha256,
    validate_sqlite_database,
)


class IngestionFunctionTest(unittest.TestCase):
    def test_valid_sqlite_database_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            database_path = Path(directory) / "source.db"
            connection = sqlite3.connect(database_path)
            connection.execute("CREATE TABLE example (id INTEGER)")
            connection.commit()
            connection.close()

            validate_sqlite_database(database_path)

    def test_non_sqlite_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            file_path = Path(directory) / "source.db"
            file_path.write_text("not a database", encoding="utf-8")

            with self.assertRaises(InvalidDatabaseError):
                validate_sqlite_database(file_path)

    def test_hash_and_object_name_are_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            file_path = Path(directory) / "source.db"
            file_path.write_bytes(b"same-content")

            first_hash = calculate_sha256(file_path)
            second_hash = calculate_sha256(file_path)
            object_name = build_object_name("generator-report/sqlite", first_hash)

            self.assertEqual(first_hash, second_hash)
            self.assertEqual(
                object_name,
                "generator-report/sqlite/"
                f"sha256={first_hash}/Lemon_Case_Tecnico_AE.db",
            )


if __name__ == "__main__":
    unittest.main()
