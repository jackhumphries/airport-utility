# Automatic configuration backups

Configuration History (see [configuration-history.md](configuration-history.md))
only snapshots settings immediately before a write you make through the app.
Automatic backups are separate: a credential-free settings snapshot is saved
about once a day while connected to a base station, whether or not you ever
change anything, so a recent backup exists before a firmware upgrade, factory
reset, or hardware failure — not only before an in-app edit.

## When a backup is saved

After the app successfully loads a base station's settings, it checks whether
at least 24 hours have passed since the last automatic backup for that host
(switching to a different host always counts as due). If so, it saves one.
This only happens while the app is open and connected with real credentials;
there is no background process and nothing runs while the app is closed.

## Storage and retention

Snapshots are stored separately from Configuration History, under:

```text
~/Library/Application Support/AirPort Utility Powerhouse/Automatic Backups/
```

The newest 14 backups are retained (roughly two weeks at the daily cadence).
Passwords, RADIUS secrets, and opaque advanced ACP data are omitted before
the snapshot reaches disk, using the same sanitization as Configuration
History. Automatic backups are local and are not included in support bundles.

## Restoring

The Dashboard's **Automatic Backups** section lists recent backups with a
**Restore** button, available only while connected to the matching host.
Restoring loads the backup into the normal configuration editor for review;
current credentials are preserved since they were never part of the
snapshot. Nothing is written to the base station until you explicitly
preview and apply the change, exactly as with a Configuration History
rollback.
