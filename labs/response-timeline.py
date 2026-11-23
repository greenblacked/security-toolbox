"""Normalize synthetic incident telemetry and report source health at a fixed cutoff."""

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

CUT_OFF = datetime.fromisoformat("2026-01-01T12:10:00+00:00")
FRESHNESS_SECONDS = 180
INGEST_DELAY_SECONDS = 60
SOURCES = {"identity", "audit", "service"}


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("timestamp must be a string")
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise ValueError("timestamps must include a UTC offset")
    return parsed.astimezone(UTC)


def analyze(records):
    if not isinstance(records, list):
        raise ValueError("expected a JSON array")
    by_id = {}
    for row in records:
        source, event_id = row["source"], row["event_id"]
        if source not in SOURCES or not isinstance(event_id, str) or not event_id:
            raise ValueError("expected a known source and nonempty event ID")
        if not isinstance(row["summary"], str) or not row["summary"]:
            raise ValueError("expected a nonempty summary")
        occurred, ingested = timestamp(row["occurred_at"]), timestamp(row["ingested_at"])
        if occurred > ingested:
            raise ValueError(f"{source}/{event_id} has a negative ingestion delay")
        if ingested > CUT_OFF:
            continue
        key = (source, event_id)
        # Preserve the first delivery of an otherwise identical event.
        if key in by_id:
            first = by_id[key]
            if (occurred, row["summary"]) != (first[0], first[2]):
                raise ValueError(f"conflicting duplicates for {source}/{event_id}")
            ingested = min(ingested, first[1])
        by_id[key] = (occurred, ingested, row["summary"])

    health = []
    for source in sorted(SOURCES):
        events = [entry for key, entry in by_id.items() if key[0] == source]
        if not events:
            health.append({"source": source, "status": "missing"})
            continue
        age = (CUT_OFF - max(event[0] for event in events)).total_seconds()
        delay = max((event[1] - event[0]).total_seconds() for event in events)
        issues = []
        if age > FRESHNESS_SECONDS:
            issues.append("stale")
        if delay > INGEST_DELAY_SECONDS:
            issues.append("late")
        status = "degraded" if issues else "healthy"
        health.append({"source": source, "status": status, "issues": issues})

    timeline = [
        {
            "source": source,
            "event_id": event_id,
            "occurred_at": occurred.isoformat(),
            "ingested_at": ingested.isoformat(),
            "summary": summary,
        }
        for (source, event_id), (occurred, ingested, summary) in sorted(
            by_id.items(), key=lambda item: (item[1][0], item[0])
        )
    ]
    return {"cutoff": CUT_OFF.isoformat(), "source_health": health, "timeline": timeline}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("events", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(analyze(json.loads(args.events.read_text(encoding="utf-8"))), indent=2))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Timeline input error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
