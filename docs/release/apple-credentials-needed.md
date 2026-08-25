# Apple credentials required before Phase C (notarised distribution)

**Decision (2026-08-22): not pursuing this.** The $99/£79-per-year Apple
Developer Program fee isn't worth it for a hobby project at this project's
current scale. The app stays ad-hoc signed (`codesign --sign -`, as it is
today) for the foreseeable future — the ad-hoc-signed beta experience
(Control-click → Open on first launch) documented in `README.md` is the
expected steady state, not a temporary gap. This document is kept as-is in
case that calculus changes later (a paying user base, a co-maintainer
willing to cover the fee, etc.), but nothing below should be treated as an
active blocker to chase.

This lists exactly what the project owner needs to provide or set up before
signing/notarisation work can proceed past the preparation done in this
branch. Nothing in this list is requested, collected, or committed by this
branch — this document exists so the owner can see the full checklist in one
place and decide when to act on it. None of these should ever be committed to
the repository; the "where it lives" column says so explicitly for each item.

| Requirement | What it is | Where it lives |
| --- | --- | --- |
| Apple Developer Program membership | An active (paid) enrollment, individual or organisation, under the account that should own this app's identity going forward | Apple ID / developer.apple.com account — owner-controlled, not shared with this repo |
| Developer ID Application certificate | The code-signing identity used to sign the outer app and every nested executable/dylib listed in `nested-code-signing-inventory.md` | Generated via Xcode or `developer.apple.com` → Certificates; private key lives in the signer's login Keychain or a CI secrets store, never in git |
| Developer ID Installer certificate (only if distributing a `.pkg` instead of a signed ZIP/DMG) | Separate identity for signing installer packages | Same as above — only needed if the release format changes from ZIP/DMG to `.pkg` |
| App-specific password or API key for `notarytool` | Credential `notarytool submit` uses to talk to Apple's notary service. Apple's current recommended method is an **App Store Connect API key** (a `.p8` key file + Key ID + Issuer ID) rather than an Apple ID app-specific password, since API keys can be scoped and revoked independently | API key file stored outside the repo (e.g. CI secret storage); referenced by path/ID in scripts, never committed |
| Team ID | The 10-character identifier tied to the Developer Program membership; used in the `CFBundleIdentifier`/codesign `--identifier` and in notarisation calls | Visible on developer.apple.com; safe to reference in scripts/docs (it's not secret), but confirm it matches the certificate actually used |
| Decision: which Apple ID/organisation owns this going forward | This project is currently ad-hoc signed under no persistent identity. Someone needs to decide whether releases are signed under Graham's personal Apple Developer account or an organisation account, since that choice is hard to change later without re-training users' Gatekeeper trust and potentially breaking update continuity | Product/ownership decision — not a technical blocker, but blocks everything else in this table until made |

## What this branch prepared without needing any of the above

- The nested-signing inventory (`docs/architecture/nested-code-signing-inventory.md`),
  so signing can be scripted mechanically once a certificate exists.
- A draft entitlements file (`Packaging/entitlements-draft.plist`) and its
  rationale (`docs/architecture/hardened-runtime-entitlements.md`).
- The path-leakage check (`Scripts/check-path-leakage.sh`), wired into
  `build-app.sh`, which catches one common class of packaging mistake that
  would otherwise only surface after a wasted notarisation submission.
- The self-contained-runtime ADR and prototype, which remove the other major
  blocker (the external `python3` requirement) without touching signing at
  all.

## What still cannot proceed without owner action

- Actually signing a build with `--options runtime --entitlements ...` end to
  end.
- Submitting to `notarytool` and reading a real notarisation log (some
  failures, e.g. specific vendored-library complaints, only surface here).
- Stapling (`xcrun stapler staple`) and verifying the stapled ticket.
- Setting up CI secrets for automated release signing (GitHub Actions
  encrypted secrets, or an equivalent), and deciding who besides Graham can
  trigger a signed release.

## CI secrets scoping note (once credentials exist)

When these are added to GitHub Actions secrets, scope them to a dedicated
release workflow that only runs on tag pushes or manual dispatch by a
maintainer — not on every `pull_request` build — so a malicious or accidental
PR from a fork can never see the signing key material. `ci.yml` today runs on
every PR; the future release workflow should be a separate file with a
narrower trigger.
