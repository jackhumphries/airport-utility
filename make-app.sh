#!/bin/bash
#
# Assemble "AirPort Utility.app" from the SwiftPM build product.
#
# SwiftPM has no .app product type, so this script wraps the executable it
# produces into a real application bundle: Info.plist, icon, the SwiftPM
# resource bundle, and the Python backend.
#
#   ./make-app.sh                              unsigned local build
#   ./make-app.sh --sign                       + Developer ID signature
#   ./make-app.sh --sign --notarize            + notarize and staple
#   ./make-app.sh --sign --notarize --zip      + distributable .zip
#
# Configuration (environment variables):
#   BUNDLE_ID                 default io.github.jackhumphries.airport-utility
#   MARKETING_VERSION         default 0.1.0
#   CURRENT_PROJECT_VERSION   default 1
#   SIGN_IDENTITY             default "Developer ID Application" (first match)
#   NOTARY_PROFILE            notarytool keychain profile name, or supply
#                             NOTARY_APPLE_ID + NOTARY_TEAM_ID + NOTARY_PASSWORD
#   OUTPUT_DIR                default dist
#   ARCHS                     default "arm64 x86_64" (universal).
#                             Set ARCHS=arm64 for a faster host-only dev build.
#
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

APP_NAME="AirPort Utility"
EXECUTABLE_NAME="AirPort Utility"
BUNDLE_ID=${BUNDLE_ID:-io.github.jackhumphries.airport-utility}
MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
CURRENT_PROJECT_VERSION=${CURRENT_PROJECT_VERSION:-1}
OUTPUT_DIR=${OUTPUT_DIR:-dist}
SIGN_IDENTITY=${SIGN_IDENTITY:-}
ARCHS=${ARCHS:-"arm64 x86_64"}
NOTARY_PROFILE=${NOTARY_PROFILE:-}

DO_SIGN=0
DO_NOTARIZE=0
DO_ZIP=0
for arg in "$@"; do
  case "$arg" in
    --sign) DO_SIGN=1 ;;
    --notarize) DO_SIGN=1; DO_NOTARIZE=1 ;;
    --zip) DO_ZIP=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
# Build universal by default. Xcode's Release build is universal
# (x86_64 + arm64); matching that here keeps the two build paths equivalent and
# is what a distributed, notarized app should ship so it runs on Intel Macs too.
ARCH_FLAGS=""
for a in $ARCHS; do
  ARCH_FLAGS="$ARCH_FLAGS --arch $a"
done

say "Building release executable ($ARCHS)"
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN_DIR=$(swift build -c release $ARCH_FLAGS --show-bin-path)

if [ ! -x "$BIN_DIR/$EXECUTABLE_NAME" ]; then
  echo "error: executable not found at $BIN_DIR/$EXECUTABLE_NAME" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Assemble the bundle
# ---------------------------------------------------------------------------
APP="$OUTPUT_DIR/$APP_NAME.app"
say "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP/Contents/MacOS/$EXECUTABLE_NAME"

# SwiftPM resource bundles must sit in Contents/Resources so that
# Bundle.module resolves them through Bundle.main.resourceURL.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# The Python backend ships inside the bundle so the app is self-contained.
# It must live in Contents/Resources, NOT Contents/MacOS: codesign treats
# everything in Contents/MacOS as code and rejects non-Mach-O files there with
# "code object is not signed at all". AirportConnection.defaultRepoPath()
# resolves it via Bundle.main.resourceURL.
# __pycache__ is excluded: stale bytecode would be sealed into the signature.
say "Embedding Python backend"
mkdir -p "$APP/Contents/Resources/backend"
for f in backend/*.py; do
  cp "$f" "$APP/Contents/Resources/backend/"
done
chmod +x "$APP/Contents/Resources/backend/airport_backend.py"

# Info.plist: resolve the same $(VAR) placeholders Xcode substitutes natively,
# so one plist serves both build paths.
sed -e "s|\$(EXECUTABLE_NAME)|$EXECUTABLE_NAME|g" \
    -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$BUNDLE_ID|g" \
    -e "s|\$(MARKETING_VERSION)|$MARKETING_VERSION|g" \
    -e "s|\$(CURRENT_PROJECT_VERSION)|$CURRENT_PROJECT_VERSION|g" \
    Packaging/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

printf 'APPL????' > "$APP/Contents/PkgInfo"

# ---------------------------------------------------------------------------
# Sign
# ---------------------------------------------------------------------------
if [ "$DO_SIGN" -eq 1 ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
      | grep "Developer ID Application" | head -1 \
      | sed -E 's/.*"(.*)"/\1/')
  fi
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "error: no Developer ID Application identity found" >&2
    exit 1
  fi
  say "Signing as: $SIGN_IDENTITY"

  # Nested bundles must be signed before the enclosing app. --deep is
  # deprecated and signs nested code with the wrong entitlements, so sign
  # explicitly, inside out.
  #
  # SwiftPM resource bundles are flat directories with no Info.plist and no
  # executable. codesign rejects those as bundles ("bundle format unrecognized"),
  # and they need no signature of their own -- carrying no code, they are sealed
  # as ordinary resources by the enclosing app signature. So sign only real
  # nested bundles, identified by the presence of an Info.plist.
  shopt -s nullglob
  for bundle in "$APP/Contents/Resources"/*.bundle; do
    if [ -f "$bundle/Contents/Info.plist" ] || [ -f "$bundle/Info.plist" ]; then
      codesign --force --timestamp --options runtime \
        --sign "$SIGN_IDENTITY" "$bundle"
    else
      say "Skipping code-free resource bundle: $(basename "$bundle")"
    fi
  done
  shopt -u nullglob

  codesign --force --timestamp --options runtime \
    --entitlements Packaging/AirPortUtility.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"

  say "Verifying signature"
  codesign --verify --strict --verbose=2 "$APP"
fi

# ---------------------------------------------------------------------------
# Notarize
# ---------------------------------------------------------------------------
if [ "$DO_NOTARIZE" -eq 1 ]; then
  # Credentials come either from a stored keychain profile (convenient locally)
  # or from Apple ID + team + app-specific password (what CI can supply).
  NOTARY_ARGS=()
  if [ -n "$NOTARY_PROFILE" ]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] \
    && [ -n "${NOTARY_PASSWORD:-}" ]; then
    NOTARY_ARGS=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_PASSWORD")
  else
    cat >&2 <<'MSG'
error: no notarization credentials.

Either store a keychain profile once:

  xcrun notarytool store-credentials "airport-utility" \
    --apple-id "you@example.com" \
    --team-id "YOURTEAMID" \
    --password "app-specific-password"

  NOTARY_PROFILE=airport-utility ./make-app.sh --sign --notarize

or supply credentials directly (used by CI):

  NOTARY_APPLE_ID=... NOTARY_TEAM_ID=... NOTARY_PASSWORD=... \
    ./make-app.sh --sign --notarize
MSG
    exit 1
  fi

  NOTARY_ZIP="$OUTPUT_DIR/notarize.zip"
  say "Submitting to Apple for notarization (this can take a few minutes)"
  ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" "${NOTARY_ARGS[@]}" --wait
  rm -f "$NOTARY_ZIP"

  say "Stapling ticket"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"

  say "Gatekeeper assessment"
  spctl --assess --type exec --verbose=2 "$APP"
fi

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
if [ "$DO_ZIP" -eq 1 ]; then
  ZIP="$OUTPUT_DIR/$APP_NAME $MARKETING_VERSION.zip"
  say "Creating $ZIP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

# Bump the bundle mtime so Finder and LaunchServices re-read it instead of
# serving a stale cached icon. Safe after signing: mtime is not sealed.
touch "$APP"

say "Done: $APP ($(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE_NAME"))"
