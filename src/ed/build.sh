#!/bin/bash
# GNU ed 1.21 -> wasm32-wasi, for terminalOS.
#
# Two things do not exist in WASI and are patched out (see patches/):
#   * signals and setjmp/longjmp: nothing can interrupt the main loop;
#   * subprocesses: '!command', 'r !command' and 'w !command' report an
#     error instead of running a shell.
# ed keeps its edit buffer in a temporary file, which wasi-libc cannot create,
# so tools/wasi_compat.c supplies one in the working directory.
source "$(dirname "$0")/../../tools/common.sh"
require_tools
command -v lzip >/dev/null || die "lzip not found (brew install lzip)"

VERSION=1.21
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(unpack ed "$HERE/upstream/ed-$VERSION.tar.lz")"
apply_patches "$SRC" "$HERE/patches"
COMPAT="$(wasi_compat_object)"

say "compiling ed.wasm"
( cd "$SRC" && $ZIG cc $WASI_CFLAGS \
    -DPROGVERSION="\"$VERSION\"" -D_WASI_EMULATED_SIGNAL \
    -o ed.wasm *.c "$COMPAT" -lwasi-emulated-signal )

package ed "$SRC/ed.wasm"

# The upstream testsuite, run against the wasm build through wasm3. Every
# script that uses a '!command' shell escape is expected to fail.
if [ -x "$REPO/tools/wasm3-harness" ]; then
  say "running upstream testsuite"
  printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$REPO/tools/wasm3-harness" "$SRC/ed.wasm" > "$SRC/ed"
  chmod +x "$SRC/ed"
  ( cd "$SRC" && sh testsuite/check.sh testsuite "$VERSION" 2>&1 | grep -v "shell escape" ) || true
fi
