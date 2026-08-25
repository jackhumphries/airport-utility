# Time Machine backup-history analysis

AirPort Utility records aggregate observations from Time Machine sparsebundles
that are visible on mounted Time Capsule shares. The feature is monitoring-only:
it does not mount shares, open backup images, alter Time Machine settings, or
write into a sparsebundle.

## Data source

During the existing backup scan, the app lists each discovered sparsebundle's
`bands` directory. It uses the bands' allocated file sizes for the current
allocation total and their latest modification date for backup freshness. A
missing or unreadable value remains unknown; the app does not estimate it from
Time Capsule capacity or the apparent sparsebundle size.

The Dashboard health-history chart displays the combined allocation of all
readable sparsebundles for the selected AirPort. Once two sized samples exist,
the caption compares the latest two observations and reports whether allocated
data grew, remained unchanged, or decreased.

## Interpreting the result

- **Growth** means that the combined allocated band data increased between the
  latest two samples. It is not a measurement of network throughput or a promise
  that a backup completed successfully.
- **Unchanged** means that two observations reported the same allocation. This
  can be normal when no backup ran during the interval; freshness remains the
  primary signal for overdue backups.
- **Decrease** can follow Time Machine thinning old backups, removing a backup,
  or a change in which mounted shares were visible. It is informational rather
  than an automatic fault.

Because the scan can only see mounted shares, a missing mount can change the
aggregate total. Compare the chart with the current backup count and freshness
rows before drawing conclusions.

## Sampling, retention, and privacy

Backup allocation uses the same health-history policy as the other Dashboard
charts: observations are consolidated into 15-minute windows, displayed for the
latest 30 days, retained for up to 90 days, and bounded to 2,000 total samples.
Clearing Health History removes these observations.

Only the aggregate allocated byte total, current-backup count, overall backup
count, and stale-backup count are stored. Computer names, sparsebundle names,
paths, network names, client identities, and credentials are not written to the
health-history archive.
