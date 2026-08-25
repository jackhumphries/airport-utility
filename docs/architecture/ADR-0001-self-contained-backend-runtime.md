# ADR-0001: Removing the external `python3` dependency

**Status:** Proposed
**Date:** 2026-08-22
**Related:** `docs/architecture/FOUNDATION.md`, Phase B of the release plan (self-contained
runtime), Phase C (notarised distribution)

## Context

The packaged app currently bundles the Python backend as source
(`Resources/backend/*.py`) but does not bundle an interpreter. At launch,
`AirPortCommandRunner` executes `backend/airport_backend.py` directly as a
process; the script relies on its own `#!/usr/bin/env python3` shebang to
resolve an interpreter from the user's `PATH`. `build-app.sh` bakes the same
assumption in at package time, locating `python3` with `command -v python3`
and using it to smoke-test the bundled script.

This means every install currently requires the user to have Python 3.10+
already present as `python3`. That is not guaranteed on a clean, modern Mac,
and it is a blocker for both a good out-of-box experience and for
notarisation/App Review expectations around self-contained `.app` bundles.

Investigation for this ADR confirmed two facts that materially simplify the
decision:

1. **The backend has zero third-party Python dependencies.** Every import
   across `backend/*.py` (6,977 lines) resolves to the standard library
   (`argparse`, `dataclasses`, `ipaddress`, `socket`, `struct`, `subprocess`,
   `ctypes`, etc.). There is no `requirements.txt` and none is needed.
2. **The one native dependency is already defensive.** `backend/acp.py` loads
   AES support via `ctypes.CDLL(ctypes.util.find_library("System") or
   "/usr/lib/libSystem.B.dylib")` — i.e. it already falls back to a hardcoded
   path if dynamic library resolution fails, which is exactly the kind of
   resolution that can behave differently inside a frozen interpreter.

Only one backend module (`airport_backend.py`) is invoked directly as a
subprocess by the Swift app today (confirmed via `AirPortCommand.backendScript`
and a grep across `Sources/` for script paths); the rest are imported by it.
That gives us a single entry point to freeze.

## Options considered

### Option 1 — Bundle a redistributable CPython framework

Ship a full relocatable CPython build (e.g. the python-build-standalone /
`python.org` framework builds) inside `Contents/Frameworks/`, and re-point the
shebang-driven invocation at the bundled interpreter instead of `env python3`.

- Licence/redistribution: PSF licence, redistribution is explicitly permitted.
- Universal binary: python.org and python-build-standalone both publish
  universal2 framework builds, so this is achievable.
- Code-signing/notarisation: every `.so`/`.dylib` inside the framework needs
  its own Developer ID signature and hardened-runtime flags; this is the
  largest nested-signing surface of the four options (a stock CPython
  framework carries dozens of extension modules we do not use).
- Package size: **large** — a full framework build is 60-100MB+ before our
  code is added, most of which (stdlib extension modules for things like
  `tkinter`, `sqlite3`, `curses`) is dead weight for this app.
- Launch time: fast once resolved (no unpacking step at launch, unlike
  PyInstaller's `--onefile` mode).
- Subprocess security: the app would still `Process()`-launch an interpreter
  and hand it a script path, so process-argv/PATH hygiene work is unchanged
  from today.
- Debugging/test reuse: best of all options — it is a completely normal
  CPython, so `python3 -m unittest Tests/BackendPythonTests/...` keeps working
  unmodified against the bundled interpreter.
- Legacy protocol parity: unaffected; the backend code doesn't change.

### Option 2 — Freeze the backend into a self-contained executable (PyInstaller or similar)

Compile `backend/airport_backend.py` and its closure of stdlib imports into a
single native executable (or a `--onedir` bundle) using PyInstaller, Nuitka, or
a comparable freezer, and have Swift launch that executable instead of a
`.py` file.

A working prototype was built for this ADR (Linux analogue — see
`Prototype/self-contained-runtime/` in this branch; the real artifact must be
built on macOS, PyInstaller does not cross-compile):

```sh
python3 -m PyInstaller --onedir --name airportbackend backend/airport_backend.py
```

Findings from the prototype:

- The resulting `dist/airportbackend/` bundle is self-contained: run with
  `PATH` stripped of every directory that could contain `python3` (`env -i
  PATH=/nonexistent ...`), `airportbackend --help` still produces the correct
  `argparse` usage text and exits 0.
- Bundle size for this backend (no third-party deps, so PyInstaller only
  pulls in the stdlib modules actually imported) is **~20MB per architecture**
  on Linux; a macOS build should land in a comparable range, well under the
  full-framework option.
- No developer-machine absolute paths leak into the shipped `dist/` output.
  PyInstaller's own intermediate bookkeeping (`build/*/*.toc`,
  `xref-*.html`) does embed the build path, but those files are build-time
  artifacts that are never copied into `Resources/` — confirmed by grepping
  the actual `dist/` tree, which was clean. This distinction (check `dist/`,
  not `build/`) is captured directly in the path-leakage script added by this
  branch (`Scripts/check-path-leakage.sh`).
- `ctypes.CDLL("/usr/lib/libSystem.B.dylib")` is unaffected by freezing: it is
  loaded by absolute path, not searched for, so PyInstaller's binary analysis
  does not need to (and should not) bundle it.

Trade-offs:

- Licence/redistribution: PyInstaller is GPL-licensed **for its own
  bootloader**, but explicitly permits distributing the *frozen application*
  under any licence (its FAQ addresses this directly) — it does not create a
  copyleft obligation for this MIT project. Nuitka's generated code has a
  similar carve-out; its own licence is Apache 2.0.
- Universal binary: requires either two separate builds (arm64 + x86_64)
  glued together the same way `build-app.sh` would need to glue any other
  per-arch binary, or a universal2 Python installation feeding PyInstaller's
  `--target-arch universal2` (works, but is the fussiest part of this option
  and needs a real macOS CI spike, not just this Linux prototype).
- Code-signing/notarisation: single executable (`--onefile`) minimizes the
  signing surface but unpacks to a temp directory at every launch, which
  Gatekeeper/notarisation tooling and some antivirus software treat with
  suspicion, and adds real startup latency; `--onedir` avoids the unpack step
  and signs as one directory of files, at the cost of more files to sign
  individually. **Recommendation: `--onedir`.**
- Package size: smallest of the three "keep it Python" options, because only
  the modules actually reachable from `airport_backend.py` are pulled in.
- Launch time: `--onedir` avoids PyInstaller's `--onefile` unpack-at-launch
  tax; comparable to a normal interpreter launch.
- Subprocess security: same shape as today (`Process()` launches a single
  executable with an argument list); the executable no longer depends on
  shebang/`PATH` resolution at all, which is a small hardening improvement.
- Debugging/test reuse: the source tree is untouched — `python3 -m unittest
  Tests/BackendPythonTests/test_backend_modules.py` keeps running exactly as
  it does today against the source modules. Only packaging changes.
- Legacy protocol parity: unaffected; no backend code changes are required by
  this option itself.

### Option 3 — Progressively replace Python process calls with native Swift adapters

Rewrite ACP/SRP/settings/etc. in Swift over time, eliminating the Python
process boundary entirely.

- Removes the interpreter dependency permanently and removes an entire class
  of subprocess-security concerns.
- Directly contradicts the project's own stated principle (§ handoff "Do not
  rewrite the backend in Swift merely for visual cleanliness. Preserve the
  tested reverse-engineered behavior unless the replacement has fixture and
  hardware parity"). The backend encodes hard-won, reverse-engineered
  protocol behaviour across ACP v1/v2, SRP auth, legacy framing, and
  firmware/disk RPC; a rewrite would need full fixture and hardware parity
  before it could be trusted, which is a multi-month effort on its own and
  is explicitly out of scope for a packaging fix.
- Rejected **for this ADR's purpose** (removing the interpreter dependency
  now). It remains the right long-term direction for isolated pieces of
  functionality where parity can be established incrementally and cheaply,
  and is compatible with adopting Option 2 first.

### Option 4 — Small signed helper executable with a stable JSON protocol

Wrap the Python backend behind a long-lived helper process that speaks a
documented JSON protocol over stdio, rather than one-shot CLI invocations per
`AirportCommandRunner.run` call.

- This is an architecture change (protocol + process-lifecycle design), not a
  packaging change. It's a superset of Option 2 in effort: you still have to
  decide how the helper itself is distributed (interpreter dependency again,
  unless combined with Option 1 or 2 for the helper's own runtime), and it
  adds long-lived-process lifecycle management (crash recovery, versioning,
  concurrent-call handling) that the current one-shot-process model avoids.
- Its real value is architectural, matching § "Architecture goals" in the
  handoff (typed provider protocols, structured output schema, credential
  requirements, cancellation/recovery behaviour) — the kind of interface a
  future TimeCapsuleSMB or native-Swift provider would also implement. That
  is a Phase 13-style modernisation concern, not a blocker for this beta.
- Rejected **as the mechanism for this ADR**, but the JSON-protocol shape it
  describes is worth keeping in mind when Option 2's `airportbackend`
  executable's CLI surface is finalized, so today's one-shot CLI naturally
  slots into a "provider" abstraction later without a rewrite.

## Decision

Adopt **Option 2: freeze `backend/airport_backend.py` into a self-contained
`--onedir` executable** (PyInstaller, pending a short macOS-side bake-off
against Nuitka using the criteria above — the Linux prototype in this branch
validates the approach's feasibility and packaging characteristics, not the
specific tool). Package the frozen `airportbackend/` directory inside
`Contents/Resources/backend/`, and change `AirPortCommandRunner` and
`build-app.sh` to launch that executable directly instead of relying on
`env python3` shebang resolution.

This is the smallest change that removes the external interpreter dependency:
it keeps the backend's source untouched (preserving every existing Python
test), avoids the multi-dozen-megabyte tax and full nested-signing surface of
bundling an entire CPython framework, and does not require redesigning the
process/protocol boundary. Option 4's JSON-protocol idea and Option 3's
incremental native replacement both remain open for the later modernisation
programme (§13.2) and are not precluded by this decision — a future provider
abstraction can wrap the same frozen executable.

## Consequences

- `build-app.sh` needs a new build stage that invokes the freezer (on macOS,
  as part of a macOS CI job — this cannot be validated end-to-end outside a
  real Mac; see `Prototype/self-contained-runtime/NOTES.md` for what was and
  was not validated in this Linux spike) before `codesign`, and needs to sign
  and verify the frozen executable and every file inside its `_internal/`
  support directory (see the nested-signing inventory added by this branch).
- `AirportCommandRunner.run` needs to accept "launch this executable
  directly" rather than assuming a `.py` script with a shebang; this is a
  small, mechanical change (it already takes an executable `scriptURL` — only
  the resolution of that URL changes).
- The frozen executable needs to become the object of the smoke test in
  `build-app.sh` (still `--help`, unchanged assertion), and a new automated
  check for baked-in build-machine paths should run against `dist/` (or the
  packaged `Resources/backend/` equivalent) on every release build — see
  `Scripts/check-path-leakage.sh`.
- README's "Requirements" and "Build from source" sections will need
  `python3` reframed as a *build-time* requirement (for `swift test`'s Python
  suite and for running the freezer) rather than a *runtime* requirement of
  the packaged app. Source/dev builds (`./run.sh`) keep using a system
  `python3` unchanged; only the packaged `.app` gains the frozen executable.
- A follow-up spike must happen on an actual Mac to validate: universal2
  freezing (or a two-arch build + lipo/dual-binary packaging), signing every
  nested file with Developer ID, and hardened-runtime compatibility. This ADR
  provides the technical direction; it does not replace that macOS-side
  validation, which this cloud/Linux environment cannot perform.
