#!/bin/bash
# GNU nano 9.2 -> wasm32-wasi, for terminalOS.
#
# nano is the first package here that needs a library built the same way, so
# this script builds two: ncurses first, into a prefix under build/, then nano
# against it. Both are configured with tools/wasi-cc, so their configure
# scripts run their test programs under the wasm3 that terminalOS ships.
#
# What a curses program needs that WASI does not have, and where it comes from:
#
#   * raw mode. wasi-libc declares <termios.h> and implements none of it.
#     tools/wasi_compat.c keeps a struct termios and hands it back and forth,
#     which is all curses depends on; the app has already put the terminal in
#     character-at-a-time mode by the time nano runs.
#   * poll. wasm3 does not link poll_oneoff and refuses to load a module that
#     imports one, so wasi-libc's poll, select and every sleep are replaced in
#     wasi_compat.c. The final binary is checked for the import below, because
#     the failure is at load time and would otherwise reach a user.
#   * signals. No signal can ever be delivered: no SIGWINCH on rotate, no
#     SIGINT, no SIGTSTP for ^Z. wasi_compat.c records handlers that are never
#     called, which lets nano's 44 signal call sites compile untouched.
#   * the terminal size. TIOCGWINSZ is not defined, so ncurses reads COLUMNS
#     and LINES, which terminalOS exports and keeps current.
#   * the terminfo database. There is no /usr/share/terminfo to open, so the
#     descriptions are compiled into the library instead (--with-fallbacks),
#     led by xterm-color, which is the TERM terminalOS sets.
#
# Three things are patched in nano itself; see patches/ for one file each.
source "$(dirname "$0")/../../tools/common.sh"
require_tools

NANO_VERSION=9.2
NCURSES_VERSION=6.6
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$BUILD/ncurses-wasi"
COMPAT="$(wasi_compat_object)"

# wasi_compat.h is force-included into ncurses too, not just nano. The compat
# object is on the link line for configure's probes, so ncurses finds sigaction
# and compiles lib_tstp.c against it; without the header in front of that, the
# struct it needs is only ever forward-declared and every use is an incomplete
# type. The library and the program have to agree on the definition anyway.

# --with-fallbacks compiles terminal descriptions into the library by dumping
# them from the build machine's terminfo with infocmp. macOS ships ncurses
# 5.7, whose infocmp predates the flags MKfallback.sh uses; the result is a
# library with no terminal descriptions at all, which fails at initscr on
# device rather than here. Hence the version check, and the assertion after
# the build that something actually landed in fallback.c.
command -v infocmp >/dev/null || die "infocmp not found (brew install ncurses)"
case "$(infocmp -V 2>/dev/null)" in
  "ncurses 6."*) ;;
  *) die "infocmp is $(infocmp -V 2>&1 | head -1), need ncurses 6.x
   brew install ncurses, then put its bin on PATH ahead of /usr/bin" ;;
esac

# ---------------------------------------------------------------- ncurses

NCURSES_SRC="$(unpack ncurses "$HERE/upstream/ncurses-$NCURSES_VERSION.tar.gz")"
rm -rf "$PREFIX"

# Setting --build and --host to wasm32-wasi ensures configure does not think
# it is cross compiling, so it runs its test programs (through wasi-cc, so
# they run under wasm3), while host_os = wasi keeps it off the Darwin code paths
# it would otherwise select from config.guess.
say "configuring ncurses $NCURSES_VERSION"
( cd "$NCURSES_SRC" && ./configure \
    --build=wasm32-wasi --host=wasm32-wasi --prefix="$PREFIX" \
    CC="$REPO/tools/wasi-cc" \
    CFLAGS="-Oz -include $REPO/tools/wasi_compat.h" LIBS="$COMPAT" \
    AR="$ZIG ar" RANLIB="$ZIG ranlib" \
    --without-shared --with-normal --without-debug --without-profile \
    --without-cxx --without-cxx-binding --without-ada \
    --without-progs --without-tests --without-manpages --without-tack \
    --disable-database --disable-db-install --disable-home-terminfo \
    --with-fallbacks=xterm-color,xterm-256color,xterm,vt100,ansi,dumb \
    --disable-termcap --enable-widec --disable-rpath \
    --without-pkg-config --without-dlsym \
    cf_cv_working_poll=yes \
    > "$BUILD/ncurses-configure.log" 2>&1 ) \
  || { tail -20 "$BUILD/ncurses-configure.log"; die "ncurses configure failed"; }

# The probe for a working poll opens /dev/null and then /dev/tty, neither of
# which exists under WASI, and reports the absent devices as a broken poll.
# Left at "no", ncurses falls back to select(), which is the one path that
# would put poll_oneoff back into the binary. (cf_cv_working_poll above.)

say "compiling ncurses"
( cd "$NCURSES_SRC" && make -j8 > "$BUILD/ncurses-make.log" 2>&1 ) \
  || { grep -E ": error:|undefined symbol" "$BUILD/ncurses-make.log" | head; die "ncurses make failed"; }
( cd "$NCURSES_SRC" && make install > "$BUILD/ncurses-install.log" 2>&1 ) \
  || { tail -20 "$BUILD/ncurses-install.log"; die "ncurses install failed"; }

grep -q "xterm-color" "$NCURSES_SRC/ncurses/fallback.c" \
  || die "ncurses built with no compiled-in terminal descriptions:
   fallback.c is empty, so initscr would fail on device. Check that infocmp
   can dump xterm-color: infocmp -x xterm-color"

# ------------------------------------------------------------------- nano

NANO_SRC="$(unpack nano "$HERE/upstream/nano-$NANO_VERSION.tar.xz")"
apply_patches "$NANO_SRC" "$HERE/patches"

# The 39 syntax definitions nano ships install into /usr/local/share/nano and
# its system rcfile into /usr/local/etc, neither of which a WASI program can
# open. Compiled in, they are found by basename: the generated file below
# stands in for SYSCONFDIR/nanorc, and each line in it names one syntax file
# that the same table also holds. See patches/0004.
say "embedding syntax definitions"
cp "$REPO/tools/wasi_embed.h" "$NANO_SRC/src/"
mkdir -p "$BUILD/nano-embed"
{
  echo "## Generated by src/nano/build.sh. This is the nanorc compiled into"
  echo "## nano.wasm, standing in for the one that would be installed at"
  echo "## $(: )SYSCONFDIR/nanorc. The includes name files compiled in beside it."
  echo "## A nanorc in the working directory, or one named with -f, wins."
  for syntax in "$NANO_SRC"/syntax/*.nanorc; do
    echo "include \"$(basename "$syntax")\""
  done
} > "$BUILD/nano-embed/nanorc"

python3 "$REPO/tools/embed.py" "$BUILD/nano-embed/table.c" \
  "$BUILD/nano-embed/nanorc" "$NANO_SRC"/syntax/*.nanorc
EMBED="$BUILD/nano-embed/table.o"
$ZIG cc -target wasm32-wasi -Oz -I"$REPO/tools" \
  -c "$BUILD/nano-embed/table.c" -o "$EMBED"

# Answered by hand, one line each:
#
#   the gnulib block   every one of these is a function wasi_compat.c supplies
#                      and the probe cannot see, because the declaration in
#                      wasi_compat.h clashes with the bare 'char f();'
#                      autoconf compiles to test with. Same list as datamash,
#                      plus the signal API.
#   sigset_t/sigaction with both answered yes, gnulib leaves its own signal
#                      emulation out. It would not build anyway: it supports
#                      32 signals and wasi-libc reports NSIG as 65.
CACHE="
  gl_cv_func_dup2_works=yes
  ac_cv_func_getdtablesize=yes
  gl_cv_func_getdtablesize_works=yes
  gl_cv_func_fcntl_f_dupfd_cloexec=yes
  gl_cv_func_fcntl_f_dupfd_works=yes
  ac_cv_func_getrandom=yes
  ac_cv_func_popen=yes
  ac_cv_func_pclose=yes
  ac_cv_func_mkstemp=yes
  ac_cv_func_mkstemps=yes
  gl_cv_type_sigset_t=yes
  ac_cv_type_sigset_t=yes
  ac_cv_func_sigaction=yes
  ac_cv_func_sigprocmask=yes
"

# PKG_CONFIG=false is required because macOS ships an ncursesw.pc that
# reports '-lncurses -D_DARWIN_C_SOURCE', and nano's configure consults
# pkg-config before it looks at anything else: it would link the host's native
# ncurses into a wasm binary, and quietly turn off default colors, set_escdelay
# and key_defined when the probes for them failed against the wrong library.
# With pkg-config out of the way the checks fall through to -lncursesw and find
# the one just built.
say "configuring nano $NANO_VERSION"
( cd "$NANO_SRC" && PKG_CONFIG=false ./configure \
    --build=wasm32-wasi --host=wasm32-wasi \
    CC="$REPO/tools/wasi-cc" \
    CFLAGS="-Oz -include $REPO/tools/wasi_compat.h" \
    CPPFLAGS="-I$PREFIX/include -I$PREFIX/include/ncursesw" \
    LDFLAGS="-L$PREFIX/lib" LIBS="$COMPAT $EMBED" \
    AR="$ZIG ar" RANLIB="$ZIG ranlib" \
    --disable-nls --disable-libmagic \
    --disable-speller --disable-formatter --disable-linter \
    --enable-utf8 \
    $(echo "$CACHE" | sed 's/#.*//') \
    > "$BUILD/nano-configure.log" 2>&1 ) \
  || { tail -20 "$BUILD/nano-configure.log"; die "nano configure failed"; }

grep -q "curses library to be used is: ncursesw" "$BUILD/nano-configure.log" \
  || die "nano did not pick up the ncursesw just built; see $BUILD/nano-configure.log"

clear_gnulib_warning_flags "$NANO_SRC"

say "compiling nano.wasm"
( cd "$NANO_SRC" && make -j8 > "$BUILD/nano-make.log" 2>&1 ) \
  || { grep -E ": error:|undefined symbol" "$BUILD/nano-make.log" | head; die "nano make failed"; }

# wasm3 rejects a module importing a function it does not provide, before main
# runs and with no hint of which call pulled it in. Catching it here beats
# shipping a binary that cannot start.
if grep -q "poll_oneoff" "$NANO_SRC/src/nano.wasm"; then
  die "nano.wasm imports poll_oneoff and will not load under wasm3:
   something reached wasi-libc's poll, select or sleep instead of the
   replacements in tools/wasi_compat.c"
fi

# pico is the name the editor answers to for anyone who came from pine, and
# nano installs itself under both. Upstream makes the second one a symlink;
# terminalOS's brew takes a flat archive of regular files and refuses anything
# else, so this is a copy, and the package carries the binary twice.
cp "$NANO_SRC/src/nano.wasm" "$NANO_SRC/src/pico.wasm"

package nano "$NANO_SRC/src/nano.wasm" "$NANO_SRC/src/pico.wasm"
