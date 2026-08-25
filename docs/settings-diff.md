# Compare to Current

Configuration History and Automatic Backups let you restore an earlier
snapshot, but restoring is a leap of faith without knowing what it would
actually change. **Compare to...**, next to each entry's restore button,
shows exactly that first — against the current live settings, or against
any other visible entry from either store.

## What it shows

Every field that differs between the two snapshots being compared, grouped
by pane (Wireless, Network, Internet, and so on), before and after. If
nothing differs, it says so plainly instead of showing an empty list.

Values shown are the stored setting values themselves — e.g. a router mode
appears as its underlying setting value, not the friendlier label used
elsewhere in the app — since generating a comparison across every field in
every pane, generically, was preferred over hand-labeling each one and
risking a stale or incorrect label down the line.

## Comparing two entries, not just to current

The **Compare to...** menu on each entry lists **Current** first, followed
by the other entries currently visible in Configuration History and
Automatic Backups (the same ones shown on screen — not the full,
potentially much longer history in either store). Picking one compares
that entry against the one you started from, in either direction.

## What it never shows

Passwords and other secrets are excluded from both sides before comparing,
the same way they're excluded from the stored snapshot itself — never
partially redacted or guessed at, simply never part of the comparison.

## What it doesn't do

This is read-only and informational. It doesn't change anything, and it's
a separate action from **Prepare Rollback**/**Restore** — comparing first
doesn't restore, and restoring doesn't require comparing first.
