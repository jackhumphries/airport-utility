# Health history and trend charts

AirPort Utility records a small, local history of health measurements so the
Dashboard can show changes over time instead of only the latest reading. The
history is observational: recording it does not change the configuration of an
AirPort, its disks, or any connected client.

## What is recorded

Each sample belongs to the currently connected base-station address and contains
only aggregate measurements the app has already obtained during normal refreshes:

- Time Capsule free and total capacity, when the AirPort reports both values.
- The assessed disk condition and the result of the SMB reachability check.
- The number of discovered Time Machine backups and how many are stale.
- The number of connected wireless clients and how many have a weak signal.
- The number of warnings currently reported for the selected AirPort.

A wireless client is counted as weak when its normalized RSSI is below -82 dBm,
the same threshold used by the Dashboard's current client-health summary. Missing
measurements remain missing; the app does not estimate or invent points.

## When samples are taken

The app offers a new combined sample after a successful client refresh, storage
health check, or Time Machine backup scan. These operations finish at different
times, so all observations for the same base station within a 15-minute window
replace that window's current sample. This produces one increasingly complete
snapshot rather than a burst of partial points. After 15 minutes, the next
observation starts a new point even if its values have not changed.

Consequently, chart intervals are not guaranteed to be evenly spaced. Gaps mean
the app was closed, the Dashboard was not active, credentials were unavailable,
or a measurement could not be completed. A gap does not mean that the network was
down.

## Retention and storage location

History is bounded in two ways:

- Samples older than 90 days are discarded when a new sample is recorded.
- No more than 2,000 samples are retained across all base stations.

The Dashboard displays the last 30 days for the selected base station. The JSON
archive is stored separately from exported AirPort configurations at:

```text
~/Library/Application Support/AirPort Utility Powerhouse/Health/health-history.json
```

Writes use an atomic file replacement so an interrupted write does not leave a
partially updated archive. If the archive is absent or unreadable, the app starts
with an empty history; this never prevents connection to an AirPort.

## Privacy

Health history stays on the Mac and is not uploaded by the app. It deliberately
does **not** contain client names, advertised hostnames, MAC addresses, client IP
addresses, Wi-Fi network names, passwords, backup names, sparsebundle paths, or
log messages. The base-station address is retained only to keep measurements from
different AirPorts separate.

For mounted Time Capsule shares, a sample may also contain the combined number
of bytes allocated by all discovered sparsebundles and the number of backups
whose latest activity is current. These are aggregate values: the archive never
stores an individual computer name, bundle name, or filesystem path. See
[Time Machine backup-history analysis](backup-history.md) for interpretation and
limitations.

The history file is not an AirPort configuration backup and should not be used to
restore settings. Standard macOS user-account file permissions still apply; a
person or process able to read the user's Application Support directory may read
the aggregate history.

## Reading the charts

The free-space chart uses decimal gigabytes (1 GB = 1,000,000,000 bytes), matching
the scale commonly shown for storage devices. A downward line normally represents
new backup data. A sudden large change may also mean a volume appeared or
disappeared from the AirPort's reported inventory.

The client chart separates all connected clients from the subset below the weak
signal threshold. It is a sequence of observations, not a continuous traffic or
radio monitor. A zero can mean that a successful refresh reported no clients; an
unavailable refresh creates no new measurement.

Disk, SMB, backup, and warning states are retained in every sample for future
analysis, even where the current Dashboard visualizes only capacity and client
counts. The current Storage and Current Warnings sections remain the authoritative
place for detailed status text.

## Clearing history

Choose **Clear History** in the Dashboard's Health History section. This removes
all saved samples for every base station and deletes the local JSON archive. The
operation does not remove logs, notification preferences, saved passwords, or
AirPort configuration exports. New history begins with the next completed health
observation.
