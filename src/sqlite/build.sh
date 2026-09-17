#!/bin/bash
# SQLite 3.50.4 (the command-line shell) -> wasm32-wasi, for terminalOS.
#
# Built from the public-domain amalgamation with SQLite's own WASI mode, which
# stubs the calls WASI lacks (fchmod, fchown, mremap). SQLITE_DEFAULT_UNIX_VFS
# must be set to "unix-none": the default "unix" VFS takes POSIX advisory locks
# through fcntl, which WASI does not have, causing writes to fail with
# SQLITE_IOERR without it. Nothing else in SQLite needs changing.
source "$(dirname "$0")/../../tools/common.sh"
require_tools

VERSION=3500400
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$BUILD/sqlite"
rm -rf "$SRC"; mkdir -p "$SRC"
unzip -oq "$HERE/upstream/sqlite-amalgamation-$VERSION.zip" -d "$SRC"
SRC="$SRC/sqlite-amalgamation-$VERSION"

say "compiling sqlite3.wasm"
( cd "$SRC" && $ZIG cc $WASI_CFLAGS -I. -I"$REPO/tools" \
    -include "$REPO/tools/wasi_compat.h" \
    -DSQLITE_WASI \
    -DSQLITE_DEFAULT_UNIX_VFS='"unix-none"' \
    -DSQLITE_THREADSAFE=0 \
    -DSQLITE_OMIT_LOAD_EXTENSION \
    -DSQLITE_OMIT_POPEN \
    -DSQLITE_OMIT_WAL \
    -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_RTREE \
    -DSQLITE_ENABLE_MATH_FUNCTIONS \
    -DSQLITE_SHELL_IS_UTF8 \
    -DHAVE_READLINE=0 \
    -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID \
    -o sqlite3.wasm sqlite3.c shell.c "$REPO/tools/wasi_compat.c" \
    -lwasi-emulated-signal -lwasi-emulated-process-clocks -lwasi-emulated-getpid )

package sqlite3 "$SRC/sqlite3.wasm"
