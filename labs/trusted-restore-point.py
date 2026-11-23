"""Choose a restore candidate using a protected digest and an independent order ledger."""

import argparse
import hashlib
import json
import sqlite3
from contextlib import closing
from pathlib import Path
from tempfile import TemporaryDirectory

# Synthetic business evidence from outside the backup system.
LEDGER = [(1, 30, 1200), (2, 60, 2500), (3, 100, 3100)]
INCIDENT = 120
RPO = 30


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_orders(db):
    return db.execute("SELECT id, committed_at, total_cents FROM orders ORDER BY id").fetchall()


def create_snapshot(path, rows):
    with closing(sqlite3.connect(path)) as db:
        db.execute(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, "
            "committed_at INTEGER, total_cents INTEGER)"
        )
        db.executemany("INSERT INTO orders VALUES (?, ?, ?)", rows)
        db.commit()


def exercise(directory, no_verified_copy):
    results = []
    selected = None
    for captured_at, name, rows in (
        (110, "newest", [*LEDGER[:2], (3, 100, 0)]),
        (95, "middle", LEDGER[:2]),
        (60, "oldest", LEDGER[:2]),
    ):
        path = directory / f"{name}.db"
        create_snapshot(path, rows)
        # The exercise simulates this digest being held in a separate, trusted catalog.
        expected_digest = digest(path)
        if name == "middle" or (name == "oldest" and no_verified_copy):
            with path.open("ab") as stream:
                stream.write(b"fixture variation")

        if digest(path) != expected_digest:
            results.append({"copy": name, "outcome": "digest mismatch"})
            continue

        with closing(sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)) as db:
            if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                results.append({"copy": name, "outcome": "SQLite integrity check failed"})
                continue
            expected_rows = [row for row in LEDGER if row[1] <= captured_at]
            ordered = read_orders(db)
            if ordered != expected_rows:
                results.append({"copy": name, "outcome": "business ledger mismatch"})
                continue
            with closing(sqlite3.connect(directory / "restore.db")) as restored:
                db.backup(restored)
                if read_orders(restored) != expected_rows:
                    raise RuntimeError("restored order read did not match verified evidence")
        results.append({"copy": name, "outcome": "verified"})
        selected = (name, captured_at, [row[0] for row in ordered])
        break

    result = {"candidates": results, "promotion": "held"}
    if selected is None:
        return {**result, "decision": "UNKNOWN: no verified copy"}
    name, captured_at, restored_ids = selected
    gap = INCIDENT - captured_at
    return {
        **result,
        "decision": "verified restore point",
        "selected_copy": name,
        "restored_order_ids": restored_ids,
        "unrecovered_order_ids": [row[0] for row in LEDGER if row[0] not in restored_ids],
        "recovery_point_gap_seconds": gap,
        "recovery_point_target_seconds": RPO,
        "recovery_point_target_met": gap <= RPO,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-verified-copy", action="store_true")
    args = parser.parse_args()
    with TemporaryDirectory(prefix="security-toolbox-restore-point-") as temporary:
        result = exercise(Path(temporary), args.no_verified_copy)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
