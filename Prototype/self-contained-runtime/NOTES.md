# Self-contained runtime prototype — what this does and does not prove

This directory holds a runtime-packaging spike for
[ADR-0001](../../docs/architecture/ADR-0001-self-contained-backend-runtime.md).
It was originally built and run inside a Linux cloud container (no Xcode/
Swift available), which could validate the packaging *technique* but not any
macOS-specific mechanics. It has since been rebuilt for real on macOS — see
"What was validated on real macOS" below, which supersedes the Linux-only
findings for anything the two sections disagree on.

**Project decision (2026-08-22): CI and packaging going forward target
arm64 only.** Apple deprecated x86_64 as of OS 26 and is dropping it
entirely in OS 28, so an x86_64 build isn't worth chasing for this app's
remaining lifetime. Everything below that discusses x86_64 or universal2 is
kept as-is for the record — in particular the Rosetta/`libcrypto` crash
finding remains real and load-bearing if x86_64 support is ever
reconsidered before it's fully dropped — but it's no longer the direction
this project is building toward. See "Recommended next step" at the bottom
for what's actually next.

## What was validated on real macOS (2026-08-22, Apple Silicon, macOS 27)

Rebuilt via `build-prototype.sh`, unmodified, run for real (not simulated)
using `backend/airport_backend.py` on this machine. Two separate builds were
produced, one per architecture available on this machine, since no
universal2 CPython is installed here (see "Universal binary" below):

- **arm64**, using the arm64-native Python 3.9.6 that ships with Xcode
  Command Line Tools (`/usr/bin/python3`, a `Python3.framework` build).
- **x86_64**, using Homebrew's Python 3.12.4 (`/usr/local/bin/python3`,
  which itself runs under Rosetta 2 on this arm64 machine — Homebrew has no
  arm64-native install here).

Both were built in isolated venvs (`pip install pyinstaller` — no
`--break-system-packages` needed since each venv is disposable) to avoid
touching system site-packages.

Findings:

- **`--help` with `PATH` stripped of `python3` passes on real macOS, both
  architectures.** This was the core open question from the Linux spike and
  it's now confirmed for real: `env -i PATH=/nonexistent HOME="$HOME"
  dist/airportbackend/airportbackend --help` exits 0 with correct usage text,
  on both the arm64 and x86_64 builds. `build-prototype.sh`'s own smoke test
  (identical assertion) passes unmodified.
- **Universal binary: no universal2 CPython was available to test, but the
  "two arch-specific builds" path (ADR-0001's stated fallback) is now
  concretely validated** — both architectures freeze cleanly and independently
  from the same source tree with no spec-file changes, confirming that path
  works if a universal2 CPython build (e.g. python.org's official installer)
  isn't adopted. Installing python.org's universal2 build was not attempted
  in this session (installing new system-level software felt like something
  to check with the project owner first, rather than a given for a spike);
  that remains the fastest way to get a true single-binary universal2 build
  and should be the first thing tried in CI.
- **Which Python builds the freezer matters a lot for the nested-signing
  surface — more than expected.** The arm64 build (Apple's own
  `Python3.framework`) has almost no vendored dylibs: `_ssl`/`_lzma` link
  against `/usr/lib/libssl.dylib` / `/usr/lib/liblzma.5.dylib` (system
  paths, confirmed via `otool -L`), not bundled copies. The x86_64 build
  (Homebrew Python) vendors its own `libssl.3.dylib`, `libcrypto.3.dylib`,
  `liblzma.5.dylib`, and `libmpdec.4.dylib` directly inside `_internal/`,
  each needing its own Developer ID signature. This resolves the open
  question in `nested-code-signing-inventory.md` — see that doc for the
  updated recommendation and the real (not Linux-proxy) file inventory for
  both architectures.
- **`Scripts/check-path-leakage.sh` had a false positive, now fixed.** The
  x86_64 build initially failed the check: it flagged `/Users/Barney` inside
  `base_library.zip` and the vendored `Python.framework` binary. That string
  is not a real build-machine path — it's CPython 3.12's own
  `ntpath.splitroot()` docstring (`'C:/Users/Barney'`, a fictional Windows
  example path), which PyInstaller always bundles as part of `os`'s
  cross-platform support regardless of target OS. Confirmed via `otool`/
  `strings` and by checking CPython's own `ntpath.py` source. The arm64
  build didn't trigger this because Python 3.9 doesn't have
  `ntpath.splitroot` (added in 3.12). Fixed with a narrow, exact-string
  allowlist in the script (not a positional/regex relaxation, since a real
  leak can legitimately sit right after a colon too — e.g. a baked-in
  colon-separated `$PATH`). Verified the fix still catches a planted
  colon-adjacent leak.
- Confirmed directly (`grep` across `backend/*.py`) that only `hashlib` is
  imported by this project's own code (via `legacy.py`, `settings.py`,
  `srp.py`); `bz2`/`lzma`/`xml` are pulled in transitively by other stdlib
  hooks, not by anything this app needs — consistent with the inventory
  doc's existing note that `--exclude-module` may be able to drop them.
- Confirmed `backend/*.py` runs correctly under Python 3.9 (older than the
  README's stated 3.10+ requirement) because every module using `X | Y`
  union-type syntax has `from __future__ import annotations` — so freezing
  with an older interpreter than the dev-flow minimum isn't itself a
  correctness risk, though it's not a reason to standardize on one.
- Bundle sizes on real macOS: arm64 ~10MB, x86_64 ~18MB (larger mainly due to
  the vendored OpenSSL/lzma/mpdecimal libraries above) — both still well
  under the full-framework option from ADR-0001.

## What was validated on the original Linux spike (x86_64, superseded above where overlapping)

- `backend/airport_backend.py` and its full import closure freeze cleanly
  with PyInstaller `--onedir`, with no spec-file customisation beyond adding
  the repo root to `--paths` so `from backend.acp import ...` resolves.
- The frozen executable runs `--help` correctly with `PATH` reduced to a
  nonexistent directory (`env -i PATH=/nonexistent ...`), i.e. with no
  `python3` reachable anywhere — proving the packaging technique removes the
  interpreter dependency in principle.
- The shipped `dist/airportbackend/` tree contains no absolute build-machine
  paths (verified with `Scripts/check-path-leakage.sh`). PyInstaller's
  intermediate `build/` bookkeeping (`.toc` files, `xref-*.html`) does
  contain the build path, but those files are never copied into `dist/` and
  would never ship inside `Resources/`.
- Bundle size for this backend (no third-party dependencies at all — see
  ADR-0001) is ~20MB for one architecture. A macOS build should be in a
  comparable range per architecture.
- `ctypes.CDLL(ctypes.util.find_library("System") or
  "/usr/lib/libSystem.B.dylib")` in `backend/acp.py` is unaffected by
  freezing, since it resolves by absolute fallback path rather than search.

## Behavioural parity — now checked (2026-08-22, same macOS session as above)

Three additional checks closed most of the parity gap the earlier version of
this section flagged:

- **`Tests/BackendPythonTests/test_backend_modules.py` (the suite
  `README.md` documents running) passes in full — 76/76 — under both
  interpreter versions used to freeze the two real builds**: Python 3.9.6
  (arm64/CLT) and Python 3.12.4 (x86_64/Homebrew). This doesn't run through
  the frozen bootloader itself (`unittest` imports the modules directly), but
  it does confirm the source behaves correctly under the exact interpreter
  version each frozen build embeds — including the older-than-README's-3.10+
  CLT Python.
- **The frozen executables were exercised directly (as a subprocess, not
  imported) via `--dry-run-json`**, which is a genuine offline code path
  (`modern_write_main` skips `open_encrypted_transport` entirely when
  `--dry-run-json` is set) — the one CLI surface on `airport_backend.py` that
  doesn't need a live base station. Output was **byte-identical** between:
  the frozen executable and the unfrozen source run under the same
  interpreter (both architectures), and the frozen arm64 output vs. the
  frozen x86_64 output (both architectures agree with each other too). Also
  ran with a deliberately malformed setting name as an edge case — same
  output on frozen and unfrozen, so nothing about freezing changed error/edge
  handling either. This is a real, if narrow, confirmation that PyInstaller's
  import analysis didn't silently change behaviour for this app's own code.
- **`ctypes.CDLL` resolution for `CommonCryptoAES` (`backend/acp.py:123`)
  works correctly on real macOS**, verified against the FIPS-197 Appendix B
  AES-128 ECB known-answer test vector (not just "does it load" — the
  produced ciphertext matches the published expected value exactly), on both
  Python versions. This is the lazy call the earlier version of this section
  flagged as unexercised by `--help`.

**Caveat that keeps this from being a full closure:** the AES/`ctypes` check
above ran through the venv interpreters directly (`from backend.acp import
CommonCryptoAES`), not through the frozen bootloader — there's no CLI path to
`CommonCryptoAES` without opening a real encrypted session against a live
base station, and inventing a fake device or local mock server to reach it
wasn't attempted (no such mock server exists in this repo currently — see
below). So "the frozen bootloader's dlopen behaves identically to the
unfrozen one" for this specific lazy ctypes call is a reasonable inference
from the `--dry-run-json` parity result and the general CPython-freezing
model, not something exercised bit-for-bit through the frozen binary itself.

**Aside, unrelated to this spike:** `Tests/BackendPythonTests/test_trace_replay.py`
currently fails to import — it references `tools/replay_airport_trace_contract.py`
and `tools/replay_airport_trace_app.py`, neither of which exist anywhere in
this repository (confirmed via `git log --all`). This predates this branch
and is orthogonal to the runtime-packaging work here, but is worth a
follow-up ticket since `README.md`'s test instructions would otherwise lead
someone to a confusing import error.

## What this still does NOT prove

- **A true single-binary universal2 artifact.** Two independent arch-specific
  builds are now confirmed to work (see above), which is one of ADR-0001's
  two accepted paths, but no universal2 CPython was available on this machine
  to test PyInstaller's `--target-arch universal2` directly, and gluing two
  `--onedir` trees into one Gatekeeper-friendly bundle (via `lipo` for the
  single executable, plus reconciling the many single-arch `.so` files under
  `_internal/`) was not attempted. Installing python.org's universal2
  installer is the more direct route and should be tried first in CI, per
  ADR-0001.
- **Code signing and hardened runtime.** Deliberately out of scope for this
  pass (per ADR-0001, this is deferred until a Developer ID exists — see
  `docs/release/apple-credentials-needed.md`). `codesign`, entitlements, and
  Gatekeeper/notarisation behaviour still need verification with a real
  Developer ID. The nested-signing inventory now reflects the real macOS
  file lists for both architectures instead of the earlier Linux proxy — see
  `docs/architecture/nested-code-signing-inventory.md`.
- **Launch time on macOS**, antivirus/Gatekeeper heuristics for `--onedir`
  vs `--onefile`, and interaction with System Integrity Protection.
- **A live encrypted ACP session run through the frozen bootloader itself**
  (as opposed to through the venv interpreter directly, or the fully-offline
  `--dry-run-json` path) — needs either real hardware or a local mock ACP
  server, neither available in this session.

## Reproducing this spike

```sh
pip install pyinstaller   # in a venv; add --break-system-packages otherwise
./Prototype/self-contained-runtime/build-prototype.sh
```

Confirmed working end-to-end on real macOS with this exact invocation
(2026-08-22) — no changes to the script were needed to reproduce it for real.

## Critical correctness finding, found while setting up CI (2026-08-22)

While building the x86_64 CI job (see `.github/workflows/runtime-packaging.yml`),
tried using Apple's CLT Python forced to x86_64 via `arch -x86_64` (Rosetta 2)
as a way to get a minimal-signing-surface x86_64 build without needing
Homebrew. **This crashes.** Minimal repro:

```sh
arch -x86_64 /usr/bin/python3 -c "
import hashlib
hashlib.pbkdf2_hmac('sha1', b'password', b'salt', 1000, dklen=32)
"
# SIGSEGV inside libcrypto.44.dylib's PKCS5_PBKDF2_HMAC, called from _hashlib
```

Apple's system `libcrypto.44.dylib` crashes when its PBKDF2/HMAC entry
points are called from x86_64 code translated by Rosetta 2 on Apple Silicon.
The same call under Homebrew's x86_64 Python (vendors its own
`libcrypto.3.dylib`) does not crash, translated on the same machine — and
neither does the same call run natively (arm64, no Rosetta). This isolates
the bug to Rosetta's translation of calls into this specific system library.

**This is not a hypothetical edge case for this app**: `backend/srp.py:197-198`
calls `hashlib.pbkdf2_hmac` directly to derive the ACP encryption keys for
*every* encrypted session with a real base station. A released x86_64 build
frozen against a system-libcrypto-linked Python, run under Rosetta on an
Apple Silicon Mac (a common, fully-supported scenario), would crash on every
attempt to talk to real hardware. Full detail and the revised
recommendation are in `docs/architecture/nested-code-signing-inventory.md`
("Correctness finding that overrides the recommendation above") — short
version: **build the x86_64 artifact with a Python that vendors its own
OpenSSL** (Homebrew confirmed safe; python.org untested, don't assume it's
safe without checking) rather than one that links the system library. The
arm64 build is unaffected — it's never translated by Rosetta on Apple
Silicon hardware, so Apple's CLT Python remains the right choice there.

## Recommended next step

The `--onedir` build, the `--help`-with-no-`python3` regression test, the
backend unit test suite, and the `--dry-run-json` frozen-vs-source parity
check are now wired into `.github/workflows/runtime-packaging.yml`, running
on `macos-latest`, arm64 only — see the project decision at the top of this
file. The x86_64 job that ran during this same session is removed from the
workflow, but its result is kept above since the underlying
Rosetta/`libcrypto` bug is real and would matter again if x86_64 support
were ever reconsidered.

## `build-app.sh` now uses this for real (2026-08-22, same session)

`build-app.sh` freezes `backend/airport_backend.py` with PyInstaller (Apple's
CLT Python, matching the arm64 CI job) directly into
`Contents/Resources/backend/airportbackend/`, in place of the old
`backend/*.py` copy + `chmod 755`. `AirportCommandRunner` (Swift) resolves
the frozen executable automatically — it checks for
`backend/airportbackend/airportbackend` next to whatever `.py` script path
it was asked to run, and uses that if present, falling back to the `.py`
path unchanged for source/dev builds (`./run.sh`). No call site needed to
change.

Two real bugs surfaced wiring this in for real, both now fixed:

- **A literal absolute-path leak, not just debug info.**
  `AirportConnection.defaultRepoPath()`'s "Xcode development fallback" used
  `#filePath`, which embeds this machine's checkout path as a runtime string
  constant (not DWARF debug info — `strip` wouldn't have touched it). Fixed
  by wrapping that fallback in `#if DEBUG`, since it only exists for running
  directly from Xcode rather than via `run.sh` (which cwd-detection already
  handles) — release builds no longer compile that branch at all.
- **Genuine DWARF debug info** (absolute `.o`/source paths) was still present
  in the release binary once `check-path-leakage.sh`'s patterns were
  widened to capture full paths (needed to distinguish a real leak from a
  third, different false positive below) — fixed with `strip -S` on the
  release binary in `build-app.sh`, before signing, exactly as the script's
  own header comment anticipated.

A third, genuinely benign match also surfaced: SwiftPM's auto-generated
`resource_bundle_accessor.swift` always embeds an absolute build-time
fallback path for the resource bundle (`Bundle.module`). Verified as dead
code for the packaged app two ways — every call site tries `Bundle.main`
first and only falls through to `Bundle.module` if that fails, and a
clean-room test (packaged app launched with the original build machine's
`.build` directory renamed away, so the embedded fallback path can't
possibly resolve) still rendered every snapshot correctly. Unlike the
CPython `ntpath` false positive, this path varies per checkout, so it's
excluded by suffix rather than exact string — see
`Scripts/check-path-leakage.sh`.

Verified end to end on real macOS: clean `swift build` + `build-app.sh
--smoke-test` passes fully — freeze, `--help` with `PATH` stripped, the
(now fixed) path-leakage check, `codesign --verify`, and the full GUI
smoke test (all snapshot views render, including a clean-room run with the
dev build directory hidden). Signing itself is still ad-hoc
(`codesign --sign -`), unchanged from before — real Developer ID signing
remains blocked on `docs/release/apple-credentials-needed.md`.

## Toolchain-shape bug, found switching to Xcode-beta 27 (2026-08-22, same session)

CI (GitHub's `macos-latest`, stable Xcode) had already validated all of the
above, but re-running locally after switching `xcode-select` to
Xcode-beta 27 (Swift 6.4, this machine runs macOS 27 beta, where the
current stable Xcode won't launch) hit a real, toolchain-shape bug in
`build-app.sh` — unrelated to the Python/backend work, in the Swift
resource-bundle packaging step.

Newer Xcode toolchains drive `swift build` through XCBuild rather than
SwiftPM's own build system, which changes two things at once: `swift build
--show-bin-path` now resolves to `.build/out/Products/Release` instead of
`.build/arm64-apple-macosx/release`, and the generated
`AirPortUtility_AirPortUtilityCore.bundle` is a classic macOS *versioned*
bundle (`Contents/Resources/*`, `Contents/Info.plist`) instead of SwiftPM's
flat bundle (files directly at the bundle root). `build-app.sh`'s single
`ditto` line assumed the flat shape — under XCBuild's shape it flattened
the wrong directory level, and the newer SwiftPM-generated
`resource_bundle_accessor.swift` (which no longer has the old
build-machine-path fallback at all — a strict improvement, see the finding
above) crashed at launch with `unable to find bundle named
AirPortUtility_AirPortUtilityCore`.

Fixed by detecting which shape is present (`Contents/Resources` exists or
it doesn't) and doing both jobs explicitly: flatten whichever directory
actually holds the resource files into `Contents/Resources` (for this app's
own direct `Bundle.main.url(forResource:)` calls), and separately preserve
the bundle intact and nested at its own name under `Contents/Resources/`
(for `Bundle.module`'s accessor — `Foundation.Bundle(url:)` transparently
reads both flat and versioned layouts). Verified working under Xcode-beta
27; the stable-Xcode/flat-bundle path is unchanged from what CI already
validated, since the fix falls through to the exact same single `ditto`
call when `Contents/Resources` isn't present.
