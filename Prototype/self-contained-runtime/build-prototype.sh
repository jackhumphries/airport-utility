#!/bin/sh
# Runtime-packaging spike for ADR-0001 (docs/architecture/ADR-0001-self-contained-backend-runtime.md).
#
# Freezes backend/airport_backend.py into a self-contained onedir executable
# with PyInstaller and proves it runs --help without any python3 reachable on
# PATH. This is NOT the release build: PyInstaller does not cross-compile, so
# the artifact this script produces matches the OS/architecture it runs on.
# Building the real macOS/universal2 artifact requires running this (or its
# eventual build-app.sh integration) on a Mac in CI. See NOTES.md.
#
# Usage:
#   pip install pyinstaller --break-system-packages   # or in a venv
#   ./Prototype/self-contained-runtime/build-prototype.sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
cd "$SCRIPT_DIR"

python3 -m PyInstaller \
  --onedir \
  --name airportbackend \
  --distpath dist \
  --workpath build \
  --specpath . \
  --paths "$REPO_ROOT" \
  --clean \
  --noconfirm \
  "$REPO_ROOT/backend/airport_backend.py"

EXE="dist/airportbackend/airportbackend"

echo "--- verifying --help works with PATH stripped of any python3 ---"
env -i PATH=/nonexistent HOME="$HOME" "$EXE" --help >/dev/null
echo "OK: $EXE ran --help with no python3 reachable on PATH."

echo "--- checking shipped dist/ output for build-machine absolute paths ---"
"$REPO_ROOT/Scripts/check-path-leakage.sh" "$SCRIPT_DIR/dist"

echo "Prototype artifact: $SCRIPT_DIR/$EXE"
echo "This is a $(uname -s)/$(uname -m) build. It demonstrates the packaging"
echo "technique only; it is not a macOS release artifact."
