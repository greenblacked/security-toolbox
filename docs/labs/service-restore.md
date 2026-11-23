# Service restore and recovery objectives

Restore a temporary SQLite order store and prove what data the service can read. Allow 30 minutes. Use Python 3.8 or later with its standard SQLite module and the [offline lab kit](/labs/#get-the-lab-kit). For this exercise, assume the incident lead has authorized recovery and the supplied backup is trusted.

## Run the restore

From the extracted kit, run:

```bash
python3 labs/service-restore.py
```

The fixture commits orders at logical seconds 30, 60 and 100. The backup contains the first two orders. An outage is declared at logical second 120. The script restores to a new file, runs SQLite's integrity check, and reads the restored orders through a sample application query. It measures elapsed time from the start of the restore through that successful read.

## Decide whether the exercise met its targets

The restored order IDs are 1 and 2, and order 3 is missing. The latest restored write is at second 60. The observed recovery point gap is 60 seconds, which misses the 30-second recovery point objective (RPO). Compare the measured local restore time with the five-second exercise recovery time objective (RTO). That timer covers this local drill. A service recovery timer in production should reflect the agreed outage start and include dependencies, verification, and restoration to users.

Record both results even if the backup restores successfully. Propose one change to reduce data loss and retest it with the same write schedule. Remove any saved result files you no longer need. The script cleans up its temporary databases.

Related reading: [NIST cybersecurity event recovery](https://csrc.nist.gov/pubs/sp/800/184/final), [SQLite Backup API](https://www.sqlite.org/backup.html), and the [security operations flow](/start/#5-respond-and-recover).
