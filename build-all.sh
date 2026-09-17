#!/bin/bash
# Builds every package from its upstream tarball, refreshes index.json, and
# runs the smoke tests against terminalOS's own wasm3.
set -e
cd "$(dirname "$0")"

[ -x tools/wasm3-harness ] || tools/build-wasm3-harness.sh "${TERMINALOS_APP:-../terminalOS}" || {
  echo "note: no wasm3 harness,  packages will build but not be tested" >&2; }

PACKAGES=("$@")
[ ${#PACKAGES[@]} -eq 0 ] && PACKAGES=(units jq sqlite datamash ed nano)

for pkg in "${PACKAGES[@]}"; do
  echo
  printf '\033[1m=== %s ===\033[0m\n' "$pkg"
  "src/$pkg/build.sh"
done

echo
python3 tools/make-index.py
[ -x tools/wasm3-harness ] && { echo; tools/test-packages.sh; }
