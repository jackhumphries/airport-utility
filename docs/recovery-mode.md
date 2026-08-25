# Recovery mode

This project is a reverse-engineered client with no access to a real
recovery protocol — there's no TFTP or serial console this app can reach for
a genuinely bricked base station. "Recovery mode" is not a new networking
capability; it's a guided reaction to three failures the app already
detects, replacing a bare status message with a clear next step.

## When it appears

A "Recovery" card appears on the Dashboard, only for the base station
you're currently connected to, when one of these happens:

- **Restart did not complete** — you restarted the base station and it
  didn't come back reachable within the normal wait window.
- **Firmware verification failed** — after a firmware install, the base
  station didn't come back reporting the expected version.
- **Configuration write failed or could not be verified** — a settings
  write failed outright, or the base station came back with different
  settings than expected, or didn't come back at all.

It clears automatically once the corresponding action actually succeeds
(the restart completes, the firmware verifies, or a later write verifies
cleanly), or when you dismiss it yourself.

## What it offers

- What happened and when, in the same wording already used in the status
  line and logs — no separate, invented error vocabulary.
- **Restore Last Known-Good Settings**, if one exists: the most recent
  snapshot from either Configuration History (only ones actually verified
  against the device) or Automatic Backups (which are inherently "good"
  simply by having been taken from a live, successfully connected session).
  Whichever is newer wins. This reuses the exact same reviewed-restore flow
  as Configuration History and Automatic Backups — it loads into the editor
  for review and never applies on its own.
- If no known-good snapshot exists yet, that's stated plainly instead of
  showing a restore option that would do nothing useful.
- A factual description of the physical hard-reset procedure as a last
  resort. The app never attempts this itself — it can only be done at the
  device, by holding its reset button.
