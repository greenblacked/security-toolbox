"""Restore a disposable SQLite order store and measure recovery outcomes."""

import json
import sqlite3
import sys
from contextlib import closing
from pathlib import Path
from tempfile import TemporaryDirectory
from time import monotonic

INCIDENT_TIME = 120
WRITES = [(1, 30), (2, 60), (3, 100)]


def exercise(directory):
    recovery_dir = Path(directory)
    with closing(sqlite3.connect(recovery_dir / "source.db")) as source:
        source.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, committed_at INTEGER NOT NULL)")
        source.executemany("INSERT INTO orders VALUES (?, ?)", WRITES[:2])
        source.commit()
        with closing(sqlite3.connect(recovery_dir / "backup.db")) as backup:
            source.backup(backup)
            source.execute("INSERT INTO orders VALUES (?, ?)", WRITES[2])
            source.commit()

            start = monotonic()
            with closing(sqlite3.connect(recovery_dir / "restored.db")) as restored:
                backup.backup(restored)
                if restored.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                    raise RuntimeError("restored database failed its integrity check")
                # Read through the same query the sample order service uses.
                rows = restored.execute("SELECT id, committed_at FROM orders ORDER BY id").fetchall()
                if rows != WRITES[:2]:
                    raise RuntimeError("order read returned unexpected data")
                elapsed = monotonic() - start
            missing = [
                order for (order,) in source.execute("SELECT id FROM orders ORDER BY id")
                if order not in {order_id for order_id, _ in rows}
            ]

    gap = INCIDENT_TIME - rows[-1][1]
    return {
        "restored_order_ids": [order_id for order_id, _ in rows],
        "missing_order_ids": missing,
        "recovery_point_gap_seconds": gap,
        "recovery_point_target_seconds": 30,
        "recovery_point_target_met": gap <= 30,
        "local_restore_elapsed_seconds": round(elapsed, 6),
        "local_restore_target_seconds": 5,
        "local_restore_target_met": elapsed <= 5,
    }


def main():
    try:
        with TemporaryDirectory(prefix="security-toolbox-restore-") as directory:
            result = exercise(directory)
    except (OSError, RuntimeError, sqlite3.Error) as error:
        print(f"Restore verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
