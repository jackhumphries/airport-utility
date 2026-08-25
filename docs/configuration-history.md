# Configuration snapshots, history, and reviewed rollback

Before a normal settings write, AirPort Utility saves the currently loaded
configuration locally. If the snapshot cannot be written, the configuration
change is blocked. The history then records whether the write completed and
whether the AirPort became reachable and returned readable settings afterward.

Snapshots are stored under:

```text
~/Library/Application Support/AirPort Utility Powerhouse/Configuration History/
```

The newest 50 records are retained. Passwords, RADIUS secrets, and opaque
advanced ACP data are omitted before the snapshot reaches disk. History is
local and is not included automatically in support bundles.

## Rollback safety

**Prepare Rollback** loads the selected pre-change snapshot into the normal
configuration editor. Sensitive fields are preserved from the currently loaded
configuration because they are not present in history. The user must review the
result, run the existing preview, and explicitly apply it. Nothing is rolled
back automatically.

After the AirPort becomes reachable, the app compares the settings returned by
the device with the scope that was applied. Passwords, secrets, and unrelated
panes are excluded. History distinguishes a verified match from a reachable
AirPort that returned different values and from an AirPort that could not be
reached. Older firmware may normalize or omit values, so a mismatch is a prompt
to review the live settings rather than proof that the write failed.
