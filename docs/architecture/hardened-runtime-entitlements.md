# Hardened runtime entitlements — draft rationale

This documents the reasoning behind `Packaging/entitlements-draft.plist`,
prepared as part of the notarisation-readiness spike (see
`docs/architecture/ADR-0001-self-contained-backend-runtime.md` and
`docs/architecture/nested-code-signing-inventory.md`). It has not been applied
to `build-app.sh` yet and has not been verified against a real Developer ID
signing identity — that verification needs a Mac and an enrolled Apple
Developer account, neither of which is available in this environment.

## Scope: hardened runtime, not App Sandbox

Apple's notary service requires the **hardened runtime** capability, which is
independent of **App Sandbox**. Hardened runtime restricts what the process
itself is allowed to do at the code level (load unsigned code, use
unsigned/writable executable memory, be debugged, use certain DYLD
environment variables); App Sandbox restricts what *resources* the process
can access (files, network, devices) and requires the user to grant access
either implicitly (open/save panels) or via security-scoped bookmarks.

**Recommendation: enable hardened runtime, do not enable App Sandbox in this
phase.** Sandboxing this app would require reworking several things that are
currently ordinary file/process access:

- `AirPortCommandRunner` spawning the backend as a child process (sandboxed
  apps can still spawn processes, but the child inherits severe restrictions
  unless explicitly exempted, and the frozen backend would need its own
  sandbox profile).
- Disk actions, configuration import/export, and log/support-bundle export,
  which currently use ordinary `FileManager` access to
  `~/Library/Application Support/...` and user-chosen paths, and would need
  security-scoped bookmarks under App Sandbox.
- Local network access to arbitrary AirPort IP addresses/hostnames the user
  enters, which is unrestricted today and would need the
  `com.apple.security.network.client` sandbox entitlement plus, potentially,
  temporary-exception entitlements for arbitrary local IPs.

None of that is required for Developer ID notarisation. It's a legitimate
future hardening step (and would let the app eventually go through the Mac
App Store if that were ever desired), but it is a separate decision with real
product-behaviour trade-offs and should not be bundled into this packaging
fix.

## Entries in the draft entitlements file

| Entitlement | Value | Why |
| --- | --- | --- |
| `com.apple.security.get-task-allow` | `false` | Required to be false (or absent) for notarisation — `true` allows a debugger to attach and is only appropriate for local development builds signed with a different (non-Developer-ID) identity. Included explicitly so the release/debug distinction is visible in the repo rather than relying on an implicit default. |

## Entitlements deliberately NOT included, and why

| Entitlement | Why it's not needed here |
| --- | --- |
| `com.apple.security.cs.disable-library-validation` | This entitlement matters when a hardened-runtime process `dlopen`s a dynamic library signed with a *different* Team ID than the process itself. Once the nested-signing inventory is followed (every `.dylib` inside the frozen backend signed under the same Developer ID, same build), the app's own dylibs pass library validation without needing this exception. The backend's `ctypes.CDLL` call only ever loads `libSystem.B.dylib`, which is a first-party Apple platform binary and is always trusted. Do not add this entitlement speculatively — it measurably weakens hardened runtime protection and Apple's own guidance is to avoid it unless a specific, verified failure requires it. |
| `com.apple.security.cs.allow-unsigned-executable-memory` | Nothing in this codebase (Swift or the frozen Python backend) needs JIT-style unsigned/writable+executable memory. |
| `com.apple.security.cs.allow-jit` | Same as above. |
| `com.apple.security.cs.allow-dyld-environment-variables` | Not needed; the app does not rely on `DYLD_*` variables to locate its own code. (Note: `AirPortCommandRunner` does pass through the *inherited process environment* to the backend subprocess today — see the follow-up item below — but that is a different concern from the app's own dyld environment.) |
| `com.apple.security.network.client` / `.server` | These are App Sandbox entitlements. They have no effect on a non-sandboxed, hardened-runtime-only app and would be silently ignored; including them here would be misleading. If App Sandbox is adopted later, revisit this file and add `network.client` then. |
| `com.apple.security.files.user-selected.read-write` and similar | Same reasoning — sandboxed-file-access entitlements, irrelevant without App Sandbox. |

## A related, smaller finding worth a follow-up ticket

While reviewing `AirPortCommandRunner.run` for this entitlements pass, note
that it currently does `var environment = ProcessInfo.processInfo.environment`
and passes the **entire inherited environment** through to the backend
subprocess (adding only `PYTHONDONTWRITEBYTECODE`). That's unrelated to
hardened runtime entitlements, but once the backend is invoked as a specific
frozen executable rather than a `python3`-shebang script (ADR-0001), it's
worth reviewing whether the subprocess needs the full parent environment at
all, versus an explicit minimal environment — smaller attack surface, and
avoids ambient environment variables (proxy settings, `PYTHONPATH` overrides
a user may have set globally, etc.) changing backend behaviour unexpectedly.
Flagging here rather than changing it in this branch, since it's an
independent behavioural change outside this spike's scope.

## Still required before this can be trusted

- Apply `--options runtime --entitlements Packaging/entitlements-draft.plist`
  to the final `codesign` invocation for the outer app in `build-app.sh`
  (after the nested-signing loop from
  `nested-code-signing-inventory.md` is implemented).
- Run `codesign --verify --strict` and `spctl -a -vvv --type execute` on the
  result.
- Submit a real build to `notarytool` and read the actual notarisation log —
  Apple's notarisation service sometimes flags specific nested binaries (e.g.
  a vendored OpenSSL) for reasons not fully predictable from static analysis,
  and the log is the authoritative source of what, if anything, needs to
  change here.
