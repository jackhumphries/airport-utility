# Clean-Mac verification procedure

This is the procedure to confirm the packaged app actually works on a Mac
that has none of a developer's usual tooling installed — no Xcode, no
Command Line Tools, no Homebrew, and (once ADR-0001 lands) no system
`python3`. It exists because every automated check in this repository today
(`swift test`, `build-app.sh`) runs on a machine that already has the full
developer toolchain, which can hide a packaging mistake that only shows up on
an ordinary user's Mac.

This procedure could not be executed as part of this branch — it was
prepared from a Linux cloud environment with no Mac available. Run it for
real before the next public beta, and before any 1.0 release.

## What "clean" means here

The fastest reliable way to get a genuinely clean Mac is a fresh macOS VM (via
Apple's `virtualization.framework`-based tools, e.g. UTM, or a fresh
Apple Silicon VM in a CI provider that offers one) or a spare/loaner Mac that
has never had Xcode or Homebrew installed. Do not "simulate" clean by
uninstalling Xcode from a dev machine — Homebrew, `/usr/local` leftovers, and
cached notarisation/Gatekeeper state tend to linger and produce false
negatives.

Minimum bar for "clean" for this checklist:

- Xcode and Xcode Command Line Tools not installed (`xcode-select -p` should
  fail).
- Homebrew not installed (`/opt/homebrew` and `/usr/local/Homebrew` absent).
- No developer-mode Gatekeeper overrides (`spctl --status` should report
  assessments enabled, i.e. default Gatekeeper is active).
- Signed in with a standard (non-admin, if practical) user account, to catch
  any accidental reliance on admin/root behaviour.

## Procedure

1. **Transfer the artifact out-of-band.** Copy the release ZIP/DMG to the
   clean Mac via AirDrop, a USB drive, or download from the actual release
   URL — not via a mechanism (like a shared dev folder) a real user wouldn't
   have.
2. **Check quarantine attributes are present**, confirming macOS treats this
   like a real downloaded file:
   ```sh
   xattr -p com.apple.quarantine "AirPort Utility.app"
   ```
   (If this errors because the transfer method stripped quarantine — e.g. some
   USB/network-share transfers do — re-download via an actual browser
   download instead; the whole point of this test is to see what a user
   sees.)
3. **Open it the way a user would**: double-click in Finder, not `open` from
   a Terminal that might carry over developer environment state.
   - For the current ad-hoc-signed beta: confirm the expected Gatekeeper
     prompt appears, and that Control-click → Open works as documented in the
     README.
   - For a future notarised build: confirm it opens with a plain double-click
     and no warning beyond the standard "downloaded from the internet" First
     Launch dialog, and that `spctl -a -vvv --type execute "AirPort Utility.app"`
     reports `accepted`, `source=Notarized Developer ID`.
4. **Exercise the backend without a system Python present.** Before
   ADR-0001 lands, this step is expected to fail (documenting the current
   gap); after it lands, it's the core regression test:
   ```sh
   which python3   # confirm it's actually absent or intentionally ignored
   ```
   Then use the app normally — connect to (or mock-discover) an AirPort,
   open the Dashboard, and confirm data loads. Any "backend script not
   found" / launch failure here means the self-contained packaging didn't
   actually remove the runtime dependency.
5. **Run the packaged-app smoke test equivalent by hand**, since
   `build-app.sh --smoke-test` requires a source checkout: open the app, let
   it load the Dashboard and Diagnostics views, and visually compare against
   the smoke-test's own reference screenshots
   (`.build/release-app/smoke-snapshots/main.png` and `diagnostics.png` from
   a normal dev-machine build) if you have them on hand.
6. **Confirm no absolute developer paths are user-visible.** Open Diagnostics
   → export a support bundle, and check it doesn't contain the *original
   packager's* home directory path anywhere (this is the user-facing half of
   what `Scripts/check-path-leakage.sh` checks build-time; this step confirms
   nothing slipped through at runtime, e.g. via an error message that embeds
   a hardcoded fallback path).
7. **Record the result** (macOS version, Apple Silicon vs Intel if both are
   released, what succeeded/failed) in the release notes or an issue, so the
   next release has a paper trail of what "clean Mac" coverage actually
   existed.

## When to run this

- Every beta and stable release, at least once per supported architecture.
- Any time `build-app.sh`, `Packaging/Info.plist`, the entitlements file, or
  the backend-packaging step changes.
