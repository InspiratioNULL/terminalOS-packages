#!/bin/bash
# GNU datamash 1.9 -> wasm32-wasi, for terminalOS.
#
# Built the ordinary way (./configure && make) but with tools/wasi-cc as
# the compiler, so configure can run its test programs under wasm3 and answer
# from the runtime the result will actually run on.
#
# Build details:
#   * 'decorate', the second program in this tarball, pipes data through a real
#     sort(1) process. WASI has no fork/exec, so only datamash is built.
#   * A handful of gnulib probes are answered by hand (see CACHE below): every
#     one of them is a function tools/wasi_compat.c supplies, which the probe
#     cannot see because the declaration in wasi_compat.h clashes with the
#     bare 'char f();' autoconf compiles to test with.
#   * macOS ar silently writes an empty archive from wasm objects, hence
#     AR="zig ar".
source "$(dirname "$0")/../../tools/common.sh"
require_tools

VERSION=1.9
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(unpack datamash "$HERE/upstream/datamash-$VERSION.tar.gz")"
apply_patches "$SRC" "$HERE/patches"
COMPAT="$(wasi_compat_object)"

CACHE="
  ac_cv_func_getrandom=yes          # wasi_compat.c, over WASI random_get
  ac_cv_func_popen=yes              # wasi_compat.c, always fails
  ac_cv_func_pclose=yes             # wasi_compat.c, always fails
  ac_cv_func_getdtablesize=yes      # wasi_compat.c, a constant
  gl_cv_func_getdtablesize_works=yes
  gl_cv_func_dup2_works=yes         # wasi_compat.c, over WASI fd_renumber
  gl_cv_func_fcntl_f_dupfd_cloexec=yes
  gl_cv_func_fcntl_f_dupfd_works=yes
"

say "configuring"
( cd "$SRC" && ./configure \
    CC="$REPO/tools/wasi-cc" \
    CFLAGS="-Oz -include $REPO/tools/wasi_compat.h" \
    LIBS="$COMPAT" \
    AR="$ZIG ar" RANLIB="$ZIG ranlib" \
    --disable-nls \
    $(echo "$CACHE" | sed 's/#.*//') > "$BUILD/datamash-configure.log" 2>&1 ) \
  || { tail -20 "$BUILD/datamash-configure.log"; die "configure failed"; }

clear_gnulib_warning_flags "$SRC"
edit_in_place "$SRC/Makefile" 's/ decorate$(EXEEXT)//'  # needs fork/exec; see above

say "compiling datamash.wasm"
( cd "$SRC" && make AR="$ZIG ar" RANLIB="$ZIG ranlib" -j8 > "$BUILD/datamash-make.log" 2>&1 ) \
  || { grep -E ": error:|undefined symbol" "$BUILD/datamash-make.log" | head; die "make failed"; }

package datamash "$SRC/datamash.wasm"
