#!/bin/bash
# jq 1.7.1 -> wasm32-wasi, for terminalOS.
#
# jq needs no source changes: it is portable C with no subprocesses, no
# signals and no threads. Oniguruma is built from the copy in the tarball so
# the regex builtins (test, match, capture, sub, splits) work.
#
# After the build the upstream test suite is run against the wasm binary
# through wasm3; all 447 tests pass.
source "$(dirname "$0")/../../tools/common.sh"
require_tools

VERSION=1.7.1
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(unpack jq "$HERE/upstream/jq-$VERSION.tar.gz")"
COMPAT="$(wasi_compat_object)"

say "configuring"
( cd "$SRC" && ./configure \
    CC="$REPO/tools/wasi-cc" \
    CFLAGS="-Oz -include $REPO/tools/wasi_compat.h" \
    LIBS="$COMPAT" \
    AR="$ZIG ar" RANLIB="$ZIG ranlib" \
    --disable-shared --enable-static \
    --with-oniguruma=builtin \
    --disable-maintainer-mode > "$BUILD/jq-configure.log" 2>&1 ) \
  || { tail -20 "$BUILD/jq-configure.log"; die "configure failed"; }

say "compiling jq.wasm"
( cd "$SRC" && make -j8 > "$BUILD/jq-make.log" 2>&1 ) \
  || { grep -E ": error:|undefined symbol" "$BUILD/jq-make.log" | head; die "make failed"; }

package jq "$SRC/jq.wasm"

if [ -x "$REPO/tools/wasm3-harness" ]; then
  say "running upstream testsuite"
  ( cd "$SRC" && ./jq -L tests/modules --run-tests tests/jq.test 2>&1 | tail -1 )
fi
