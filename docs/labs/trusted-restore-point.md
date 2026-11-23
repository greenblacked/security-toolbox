# Choose a trusted restore point

A backup can open successfully and still contain incorrect business data. Practice choosing a recovery point by checking both file integrity and business records. Allow 30 minutes. Use Python 3.11 or later and the [lab kit](/labs/#get-the-lab-kit).

## Compare the candidate backups

```bash
python3 labs/trusted-restore-point.py
python3 labs/trusted-restore-point.py --no-verified-copy
```

| Candidate | Evidence | Decision |
| --- | --- | --- |
| Newest, second 110 | Digest and SQLite checks pass, but order 3 has a total that disagrees with the independent ledger | Reject |
| Middle, second 95 | Bytes disagree with the expected digest | Reject before opening |
| Oldest, second 60 | Digest and ledger match, and the restored copy returns the expected orders | Restore for validation, hold promotion |

At incident second 120, the oldest verified copy is 60 seconds behind and misses the 30-second recovery point objective. Order 3 is missing. Record the verified point, the missing order, and the decision owner. In the second run, none of the copies can be verified, so the result is `UNKNOWN` and promotion is held.

## What the evidence establishes

The exercise simulates a protected backup catalog and a ledger from outside the backup system. In a real incident, establish the provenance of both before trusting their records. Check the restored service and its dependencies in isolation, document known data loss, and get the recovery owner’s approval before restoring customer traffic. A successful run completes the exercise. Use the reported decision to determine whether a copy was verified.

The scripts use disposable SQLite files. No cloud account or network access is required. For timing and restoring a verified backup, see [Service restore and recovery objectives](/labs/service-restore/). For recovery assurance, see [NIST SP 1800-11](https://csrc.nist.gov/pubs/sp/1800/11/final).
