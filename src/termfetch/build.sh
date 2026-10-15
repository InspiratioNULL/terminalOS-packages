#!/bin/bash
# Original source lives alongside this script; no upstream download is needed.
source "$(dirname "$0")/../../tools/common.sh"
require_tools
mkdir -p "$BUILD/termfetch"
say "compiling termfetch.wasm"
$ZIG cc $WASI_CFLAGS -Wall -Wextra -Werror \
  "$REPO/src/termfetch/termfetch.c" -o "$BUILD/termfetch/termfetch.wasm"
package termfetch "$BUILD/termfetch/termfetch.wasm"
