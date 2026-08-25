#!/bin/sh
# Fails if any file under the given path(s) contains an absolute path that
# only makes sense on the machine that built it. Intended to run against the
# *shipped* output of a build (a packaged .app, or a frozen backend's dist/
# directory) — never against intermediate build/ bookkeeping, which is
# expected to contain build-machine paths and is discarded before packaging.
#
# Usage:
#   Scripts/check-path-leakage.sh "<path-to-app-or-dist>" [more paths...]
#
# Exit status is 0 if clean, 1 if any leak is found (with the matching files
# and lines printed to stderr), 2 on usage error.
#
# Confirmed on a real macOS release build (2026-08-22, not just a theoretical
# caveat): release-mode Mach-O binaries do carry absolute source/object paths
# in their DWARF debug-info sections. If this check ever fails against
# Sources/AirPortUtilityApp's compiled binary rather than the Python/backend
# payload, first confirm the match is debug info (e.g. via `dwarfdump` or
# `nm`) before treating it as a real leak — the fix is `strip -S` on the
# release binary before signing (build-app.sh does this), not relaxing this
# script's patterns. That build also turned up two related but distinct
# cases, both handled below rather than by loosening the patterns further:
# a literal `#filePath`-embedded string (not debug info — excluded from
# release builds entirely at the source, see AirPortModels.swift's `#if
# DEBUG` guard) and a per-checkout-varying SwiftPM-generated fallback path
# (excluded by suffix below, see SUFFIX_ALLOWLIST).

set -eu

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <path-to-app-or-dist> [more paths...]" >&2
  exit 2
fi

# Patterns that indicate a developer- or build-machine-specific absolute
# path baked into a shipped artifact. Extend this list as new build hosts or
# home-directory conventions are used (e.g. CI runner home directories).
# The character classes include `/` so a match captures the whole absolute
# path rather than stopping at the first path segment (e.g. the full
# .../Foo.bundle a match ends with, not just /Users/name) — this is what
# makes the suffix-based allowlist below possible.
PATTERNS='/Users/[A-Za-z0-9_./-]+|/home/[A-Za-z0-9_./-]+|/root/[A-Za-z0-9_./-]+|/private/var/folders/[A-Za-z0-9_./-]*'

# Known-benign matches: strings CPython's own standard library ships that
# happen to match the patterns above but are not build-machine paths at all.
# Confirmed on a real macOS PyInstaller build (2026-08-22): frozen backends
# built with CPython 3.12+ always bundle ntpath.py (part of `os`'s
# cross-platform support, pulled in unconditionally regardless of target
# OS), whose `splitroot()` docstring contains the fictional Windows example
# path `C:/Users/Barney` — this is CPython's own stdlib source, not this
# project's code or this build's machine, and is identical on every build.
# Allowlisted by exact string rather than by loosening the regex above
# (e.g. "not preceded by a colon"), because a real leak can legitimately sit
# right after a colon too (a colon-separated $PATH entry baked into an error
# message, for example) — a positional heuristic would silently reopen that
# case.
ALLOWLIST='/Users/Barney'

# Known-benign matches, by suffix rather than exact string: the leading
# portion legitimately varies (it's the build machine's own checkout path),
# but the match always ends the same specific way. Confirmed on a real
# macOS release build (2026-08-22): SwiftPM auto-generates
# resource_bundle_accessor.swift for any resource-bearing target, which
# always embeds an absolute build-time fallback path ending in
# ".../AirPortUtility_AirPortUtilityCore.bundle" (used only if Bundle.main's
# own resource lookup fails first). Verified this is dead code for a
# properly packaged .app two ways: (1) every call site
# (ContentView.swift, SetupProfileTemplates.swift) tries Bundle.main first
# and only falls through to Bundle.module if that fails; (2) a clean-room
# test — running the packaged app with the original build machine's .build
# directory (the embedded fallback's target) renamed out of the way —
# rendered every snapshot correctly, proving Bundle.main's own lookup
# (which correctly finds Contents/Resources/) is what actually succeeds.
# This one can't be an exact-string allowlist entry like Barney above, since
# the leading absolute path varies per checkout; matched by suffix instead.
SUFFIX_ALLOWLIST='/AirPortUtility_AirPortUtilityCore\.bundle$'

REPORT=$(mktemp)
trap 'rm -f "$REPORT"' EXIT

FOUND=0
for TARGET in "$@"; do
  if [ ! -e "$TARGET" ]; then
    echo "warning: $TARGET does not exist, skipping" >&2
    continue
  fi
  : > "$REPORT"
  MATCHES=$(grep -rlaE "$PATTERNS" "$TARGET" 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    printf '%s\n' "$MATCHES" | while IFS= read -r FILE; do
      REAL=$(grep -aoE "$PATTERNS" "$FILE" 2>/dev/null | sort -u \
        | grep -vxF "$ALLOWLIST" | grep -vE "$SUFFIX_ALLOWLIST" || true)
      if [ -n "$REAL" ]; then
        echo "  $FILE" >> "$REPORT"
        printf '%s\n' "$REAL" | sed 's/^/    -> /' >> "$REPORT"
      fi
    done
  fi
  if [ -s "$REPORT" ]; then
    FOUND=1
    echo "Absolute build-machine paths found under $TARGET:" >&2
    cat "$REPORT" >&2
  fi
done

if [ "$FOUND" -ne 0 ]; then
  echo "" >&2
  echo "FAIL: shipped artifact leaks an absolute developer/build-machine path." >&2
  echo "This can break on another machine and can reveal the packager's" >&2
  echo "username. Check for hardcoded paths, unresolved template variables," >&2
  echo "or a freezer/bundler emitting debug metadata into the shipped tree" >&2
  echo "instead of its intermediate build directory." >&2
  exit 1
fi

echo "OK: no absolute build-machine paths found under: $*"
