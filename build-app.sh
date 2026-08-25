#!/bin/sh

set -eu

SMOKE_TEST=0
if [ "${1:-}" = "--smoke-test" ]; then
  SMOKE_TEST=1
  shift
fi
if [ "$#" -ne 0 ]; then
  echo "usage: ./build-app.sh [--smoke-test]" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

VERSION=${VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || printf '1')}
OUTPUT_DIR=${OUTPUT_DIR:-$SCRIPT_DIR/.build/release-app}
APP_PATH="$OUTPUT_DIR/AirPort Utility.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"

case "$OUTPUT_DIR" in
  "$SCRIPT_DIR"/.build/*) ;;
  *)
    echo "OUTPUT_DIR must be inside $SCRIPT_DIR/.build" >&2
    exit 2
    ;;
esac

swift build -c release --product "AirPort Utility"
BIN_PATH=$(swift build -c release --show-bin-path)

rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH/backend"

install -m 755 "$BIN_PATH/AirPort Utility" "$MACOS_PATH/AirPort Utility"
# Debug symbols otherwise leave this build machine's absolute .o/source
# paths in the binary's DWARF debug-info sections (caught by
# check-path-leakage.sh below); -S removes exactly that, before signing.
strip -S "$MACOS_PATH/AirPort Utility"
install -m 644 Packaging/Info.plist "$CONTENTS_PATH/Info.plist"

# SwiftPM's own build system emits this as a flat bundle (files directly at
# the bundle root); Xcode's build system (XCBuild, used when a newer Xcode
# toolchain drives `swift build`) emits it as a versioned bundle
# (Contents/Resources/*) instead. Handle both: flatten whichever one actually
# holds the resource files directly into Contents/Resources (for this app's
# own Bundle.main.url(forResource:) calls), and separately preserve the
# bundle intact and nested at its normal name (for SwiftPM's generated
# Bundle.module accessor, which expects to find it there as its own bundle
# — Foundation's Bundle(url:) reads both the flat and versioned layouts).
SOURCE_BUNDLE="$BIN_PATH/AirPortUtility_AirPortUtilityCore.bundle"
if [ -d "$SOURCE_BUNDLE/Contents/Resources" ]; then
  FLATTEN_SOURCE="$SOURCE_BUNDLE/Contents/Resources"
else
  FLATTEN_SOURCE="$SOURCE_BUNDLE"
fi
ditto "$FLATTEN_SOURCE" "$RESOURCES_PATH"
ditto "$SOURCE_BUNDLE" "$RESOURCES_PATH/AirPortUtility_AirPortUtilityCore.bundle"

# Freeze the backend into a self-contained executable (ADR-0001) instead of
# shipping backend/*.py + relying on a system python3 at runtime. Built with
# Apple's own Command Line Tools Python specifically, not whatever `python3`
# resolves to on PATH: it links macOS's system libssl/liblzma instead of
# vendoring copies, which keeps the nested-signing surface small (see
# docs/architecture/nested-code-signing-inventory.md). Requires network
# access at build time to install PyInstaller into a disposable venv; this is
# a build-time cost only; the packaged app itself needs no interpreter or
# network access to run the backend.
FREEZE_VENV="$OUTPUT_DIR/freezer-venv"
rm -rf "$FREEZE_VENV" "$OUTPUT_DIR/freezer-build"
/usr/bin/python3 -m venv "$FREEZE_VENV"
"$FREEZE_VENV/bin/pip" install --upgrade pip -q
"$FREEZE_VENV/bin/pip" install "pyinstaller==6.22.2" -q
"$FREEZE_VENV/bin/python3" -m PyInstaller \
  --onedir --name airportbackend \
  --distpath "$RESOURCES_PATH/backend" \
  --workpath "$OUTPUT_DIR/freezer-build" \
  --specpath "$OUTPUT_DIR" \
  --paths "$SCRIPT_DIR" \
  --clean --noconfirm \
  "$SCRIPT_DIR/backend/airport_backend.py"
FROZEN_BACKEND="$RESOURCES_PATH/backend/airportbackend/airportbackend"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_PATH/Info.plist"
plutil -lint "$CONTENTS_PATH/Info.plist"

env -i PATH=/nonexistent HOME="$HOME" "$FROZEN_BACKEND" --help >/dev/null
"$SCRIPT_DIR/Scripts/check-path-leakage.sh" "$APP_PATH"

codesign --force --sign - --identifier com.pepperstm.airport-utility "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

if [ "$SMOKE_TEST" -eq 1 ]; then
  SMOKE_OUTPUT="$OUTPUT_DIR/smoke-snapshots"
  mkdir -p "$SMOKE_OUTPUT"
  (
    cd /tmp
    AIRPORT_UTILITY_SNAPSHOT=1 AIRPORT_UTILITY_SNAPSHOT_DIR="$SMOKE_OUTPUT" \
      "$MACOS_PATH/AirPort Utility" >/dev/null
  )
  test -f "$SMOKE_OUTPUT/main.png"
  test -f "$SMOKE_OUTPUT/diagnostics.png"
  echo "Packaged-app smoke test passed."
fi

echo "$APP_PATH"
