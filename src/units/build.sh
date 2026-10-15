#!/bin/bash
# GNU units 2.23 -> wasm32-wasi, for terminalOS.
#
# The unit database (definitions.units and the files it includes) is compiled
# into the binary: wasm3 only preopens the shell's working directory, so there
# is no install prefix a wasm module could read its data from. The result is a
# single self-contained units.wasm.
source "$(dirname "$0")/../../tools/common.sh"
require_tools

VERSION=2.23
SRC="$(unpack units "$(dirname "$0")/upstream/units-$VERSION.tar.gz")"
apply_patches "$SRC" "$(dirname "$0")/patches"

say "embedding unit database"
cp "$REPO/tools/wasi_embed.h" "$SRC/"
python3 "$REPO/tools/embed.py" "$SRC/wasi_embed.c" \
  "$SRC/definitions.units" "$SRC/currency.units" "$SRC/locale_map.txt" \
  "$SRC/cpi.units" "$SRC/elements.units"

say "compiling units.wasm"
( cd "$SRC" && $ZIG cc $WASI_CFLAGS \
    -DUNITSFILE='"/usr/share/units/definitions.units"' \
    -DLOCALEMAP='"/usr/share/units/locale_map.txt"' \
    -DDATADIR='"/usr/share/units"' \
    -DSUPPORT_UTF8 -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS \
    -o units.wasm \
    units.c parse.tab.c strfunc.c wasi_embed.c \
    -lwasi-emulated-signal -lwasi-emulated-process-clocks )

package units "$SRC/units.wasm"
