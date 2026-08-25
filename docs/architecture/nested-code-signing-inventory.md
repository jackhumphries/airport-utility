# Nested code-signing inventory (Developer ID / hardened runtime)

This inventory supports Phase C (notarised distribution) and assumes
ADR-0001's decision (freeze the backend into a self-contained `--onedir`
executable) has been implemented. It lists every category of file that will
exist inside `AirPort Utility.app` once that lands, and what signing each one
needs.

**Updated 2026-08-22 with a real macOS run.** The original version of this
document was produced without access to a Mac, using a Linux prototype build
as a structural proxy; that version's caveats about macOS-specific filenames
have now been confirmed and superseded by running
`Prototype/self-contained-runtime/build-prototype.sh` for real, on both
arm64 and x86_64. The two architectures produced **meaningfully different
signing surfaces** depending on which CPython built the freezer — see
"Open question, now answered" below before picking a build toolchain for
release. Signing itself (`codesign`, entitlements, notarisation) was still
not exercised in this pass — that remains blocked on a Developer ID per
`docs/release/apple-credentials-needed.md`.

**Also updated 2026-08-22, later the same day: this project now targets
arm64 only** (Apple deprecated x86_64 as of OS 26, dropping it entirely in
OS 28 — see `Prototype/self-contained-runtime/NOTES.md`). The x86_64
inventory and the correctness finding below are kept for the record, since
the underlying Rosetta/`libcrypto` bug would matter again if x86_64 support
were ever reconsidered, but the arm64 (Apple CLT Python) inventory is the
one that actually matters for this app's signing work going forward.

## Current app (before ADR-0001)

| Item | Path (inside .app) | Needs Developer ID signature? |
| --- | --- | --- |
| Main app binary | `Contents/MacOS/AirPort Utility` | Yes (already ad-hoc signed today) |
| SwiftPM resource bundle | `Contents/Resources/AirPortUtility_AirPortUtilityCore.bundle` | No — data only (images, strings) |
| Python backend source | `Contents/Resources/backend/*.py` | No — plain text, not a Mach-O; not independently signed (it is covered by the outer app's seal, but adds no signature of its own) |

Today's signing surface is small: one signature covers everything, because
there is no bundled interpreter or nested executable.

## After ADR-0001 (frozen backend) — real macOS file lists

The two real builds below differ because they were frozen with different
CPython builds, not because of anything about `--onedir` itself — see "Open
question, now answered" for why that choice matters. Both were produced by
running `Prototype/self-contained-runtime/build-prototype.sh` unmodified
against `backend/airport_backend.py`.

### Built with Apple's Xcode Command Line Tools Python (3.9.6, arm64-native)

| Item | Path (inside .app) | Needs its own Developer ID signature? | Notes |
| --- | --- | --- | --- |
| Frozen backend executable | `.../backend/airportbackend/airportbackend` | **Yes** | Mach-O executable; sign with hardened runtime flag before the outer app. |
| `Python3.framework` | `.../airportbackend/_internal/Python3.framework/Versions/3.9/Python3` | **Yes** | The interpreter itself, shipped as a **framework**, not a flat `.dylib` — framework signing has its own shape (sign the versioned framework bundle, not just the Mach-O inside it) and needs its own line item in the signing script, not just a loop over `*.dylib`. Has an `Info.plist` alongside it (`Resources/Info.plist`) — data, not separately signed. |
| C-extension modules | `.../_internal/python3.9/lib-dynload/*.cpython-39-darwin.so` — **47 files** | **Yes**, one signature per file | Full list captured in this build; typical entries: `_ssl`, `_hashlib`, `_lzma`, `_bz2`, `_ctypes`, `_socket`, `_struct`, `pyexpat`, `unicodedata`, etc. |
| `base_library.zip` | `.../_internal/base_library.zip` | No | Data (zipped `.pyc`), not a Mach-O. |
| **Vendored OpenSSL/lzma/compression libraries** | — | **N/A — none present** | Confirmed via `otool -L`: `_ssl.cpython-39-darwin.so` links `/usr/lib/libssl.46.dylib` and `/usr/lib/libcrypto.44.dylib`; `_lzma...so` links `/usr/lib/liblzma.5.dylib`. All system paths — nothing vendored into `_internal/` for these. |
| **Total signable items** | | | 1 executable + 1 framework binary + 47 `.so` = **49** |

### Built with Homebrew Python (3.12.4, x86_64, running under Rosetta on this arm64 test machine)

| Item | Path (inside .app) | Needs its own Developer ID signature? | Notes |
| --- | --- | --- | --- |
| Frozen backend executable | `.../backend/airportbackend/airportbackend` | **Yes** | Same as above. |
| `Python.framework` | `.../airportbackend/_internal/Python.framework/Versions/3.12/Python` | **Yes** | Same framework-signing shape as above. |
| **Vendored OpenSSL (`libssl`, `libcrypto`)** | `.../_internal/libssl.3.dylib`, `libcrypto.3.dylib` | **Yes** | Confirmed present: `_ssl.cpython-312-darwin.so` links `@rpath/libssl.3.dylib` / `@rpath/libcrypto.3.dylib`, both shipped in `_internal/` — Homebrew's Python links its *own* OpenSSL rather than the system one. Each needs its own signature and needs to stay notarisation-clean version-wise. |
| **Vendored `liblzma`, `libmpdec`** | `.../_internal/liblzma.5.dylib`, `libmpdec.4.dylib` | **Yes** | Same story — Homebrew's Python vendors these too, where Apple's does not. |
| C-extension modules | `.../_internal/python3.12/lib-dynload/*.cpython-312-darwin.so` — **47 files** | **Yes**, one signature per file | Same module set as the arm64 build, different filenames (`cpython-312` vs `cpython-39`). |
| `base_library.zip` | `.../_internal/base_library.zip` | No | Data, not a Mach-O. |
| **Total signable items** | | | 1 executable + 1 framework binary + 4 vendored dylibs + 47 `.so` = **53** |

### Unchanged from before

| Item | Path (inside .app) | Needs its own Developer ID signature? | Notes |
| --- | --- | --- | --- |
| SwiftPM resource bundle | `Contents/Resources/AirPortUtility_AirPortUtilityCore.bundle` | No | Unchanged from today. |
| Main app binary | `Contents/MacOS/AirPort Utility` | **Yes** | Must be signed *last*, after every nested item above, per Apple's inside-out signing requirement. |

## Signing order

Apple's codesign tooling requires nested code to be signed before the code
that contains it. The rough order for the post-ADR-0001 bundle is:

1. Every `.dylib` / `.so` under `_internal/`, **and the `Python3.framework`
   (or `Python.framework`) bundle** — confirmed present in both real builds
   as a *framework*, not a flat dylib. Framework signing targets the
   versioned framework directory (`codesign ... Python3.framework/Versions/3.9`
   or the framework root, per Apple's usual framework-signing convention),
   not just the `Python3`/`Python` Mach-O inside it directly — this needs its
   own step in the signing script, separate from a simple `find ... -name
   '*.dylib'` loop. (Order among all of these doesn't matter, they don't nest
   each other.)
2. The `airportbackend` executable itself (it links against the above).
3. `codesign` currently runs once on the whole app in `build-app.sh`; this
   will need to become an explicit loop over the frozen backend's nested
   files (`codesign --deep` can do this automatically for simple cases, but
   Apple's own guidance is to avoid `--deep` for anything going through
   notarisation and instead sign each nested item explicitly, because
   `--deep`'s automatic discovery has known gaps).
4. `Contents/MacOS/AirPort Utility` (the outer app), signed last, with
   `--options runtime` (hardened runtime) and the entitlements file (see
   `Packaging/entitlements-draft.plist`).

## Verification

`codesign --verify --strict --verbose=4 "AirPort Utility.app"` after the full
signing pass should report all nested code as valid. `spctl -a -vvv --type
execute "AirPort Utility.app"` is the closer approximation to what Gatekeeper
will actually check on a clean Mac, and should be run before every release
once a Developer ID and notarisation profile exist.

## Open question, now answered

The prior version of this document asked: can PyInstaller's macOS output be
built to link the compression and crypto libraries dynamically against the
ones macOS already ships, instead of vendoring its own copies, to reduce the
signing surface and bundle size?

**Yes — and it's determined entirely by which CPython builds the freezer,
not by any PyInstaller flag.** Confirmed directly with two real builds from
the same source tree (see the file lists above):

- **Apple's own Python** (Xcode Command Line Tools' `Python3.framework`, and
  very likely python.org's official installer too, since both are
  Apple-style framework builds) links `_ssl`/`_lzma` against `/usr/lib/
  libssl.dylib` / `/usr/lib/liblzma.5.dylib` — system paths, zero vendored
  crypto/compression libraries. **49 total signable items.**
- **Homebrew's Python** vendors its own `libssl.3.dylib`, `libcrypto.3.dylib`,
  `liblzma.5.dylib`, and `libmpdec.4.dylib` directly into `_internal/`,
  because Homebrew's own Python build links against Homebrew's own OpenSSL/
  xz/mpdecimal formulae rather than the system ones. **53 total signable
  items**, plus the extra work of keeping 4 more third-party library versions
  notarisation-clean over time.

**This recommendation is now superseded — see the correctness finding below,
found the same day while setting up CI around this build.** The smaller
signing surface from linking system libraries turns out to come with a
serious correctness cost for exactly the crypto path this app depends on
most.

## Correctness finding that overrides the recommendation above (2026-08-22)

**Apple's system `libcrypto.44.dylib` crashes (`SIGSEGV`) when its
PBKDF2/HMAC entry points are called from x86_64 code running under Rosetta 2
translation on Apple Silicon.** Minimal reproduction, isolated from
everything else:

```sh
arch -x86_64 /usr/bin/python3 -c "
import hashlib
hashlib.pbkdf2_hmac('sha1', b'password', b'salt', 1000, dklen=32)
"
# crashes with SIGSEGV inside libcrypto.44.dylib's PKCS5_PBKDF2_HMAC /
# HMAC_CTX_copy, called from CPython's _hashlib module
```

The same call under Homebrew's x86_64 Python (which vendors its own
`libcrypto.3.dylib` instead of linking the system one), under identical
Rosetta translation on the same machine, **does not crash** and returns the
correct result — as does the same call run natively (arm64, no Rosetta
involved). This isolates the bug precisely to Rosetta's translation of calls
into *this specific system library*, not to Rosetta or PBKDF2/HMAC in
general.

**Why this matters for this app specifically:** `backend/srp.py:197-198`
calls `hashlib.pbkdf2_hmac` directly to derive the ACP request/response
encryption keys from the SRP session key — this runs on **every** encrypted
session with a real base station, not an edge case. If a released x86_64
build is frozen against a Python that links the system `libcrypto` (Apple's
Command Line Tools Python, and very likely python.org's official installer
too, since both are described the same way in Apple/CPython release notes
as linking platform libraries where available) and that build ever runs
under Rosetta on an Apple Silicon Mac — a common, fully-supported scenario
for any x86_64-only or non-preferred-arch launch — every attempt to open an
encrypted session would crash the app.

**Revised recommendation:** for any x86_64 build that might run under
Rosetta (which is any x86_64 build shipped today, since Apple Silicon
Macs are now the majority), **build with a Python that vendors its own
OpenSSL rather than linking the system one** — confirmed safe with Homebrew
Python in this session. This reverses the smaller-signing-surface
recommendation above for the x86_64 architecture specifically: accept the
larger vendored-library signing surface (4 extra dylibs, see the file
inventory above) in exchange for not crashing on the app's core
authentication path. The arm64 build is unaffected either way — it never
goes through Rosetta on Apple Silicon hardware, so Apple's CLT Python remains
the right (smaller-surface, no-crash) choice there. python.org's installer
was not tested directly this session and needs the same check before being
trusted for the x86_64 build — it may or may not have the same system-link
behavior as Apple's CLT Python; don't assume either way without testing it
the same way.

A second, independent finding from this same real-macOS run:
`Scripts/check-path-leakage.sh` had a false-positive bug (unrelated to which
Python is used) — CPython 3.12+'s own `ntpath.splitroot()` docstring embeds
the fictional Windows path `C:/Users/Barney`, which the leak-check's regex
matched as if it were a real build-machine path. This has been fixed in the
script (narrow exact-string allowlist, regression-tested against a planted
real leak) — see `Prototype/self-contained-runtime/NOTES.md` for detail.
