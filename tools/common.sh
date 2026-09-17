# Shared helpers for the package build scripts. Sourced, not executed.
# Every package is built from a pristine upstream tarball plus the patches in
# its patches/ directory, so a build is reproducible from what this repo ships.

set -e

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$REPO/build"
BIN="$REPO/bin"
DIST="$REPO"

# zig is the C -> wasm32-wasi cross compiler; it carries its own wasi-libc.
ZIG="${ZIG:-zig}"
WASI_CFLAGS="-target wasm32-wasi -Oz -flto -Wl,--strip-all"

die() { echo "error: $*" >&2; exit 1; }

# Build scripts are run from anywhere and then cd into the source tree, so
# every path handed to a helper is resolved first.
abspath() { ( cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")" ); }
say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

require_tools() {
  command -v "$ZIG" >/dev/null || die "zig not found (brew install zig)"
  command -v python3 >/dev/null || die "python3 not found"
}

# unpack NAME TARBALL: extracts into $BUILD and echoes the source directory.
unpack() {
  local name="$1" tarball dir
  tarball="$(abspath "$2")"
  rm -rf "$BUILD/$name"
  mkdir -p "$BUILD/$name"
  case "$tarball" in
    *.tar.gz|*.tgz) tar xzf "$tarball" -C "$BUILD/$name" ;;
    *.tar.lz)       lzip -dc "$tarball" | tar xf - -C "$BUILD/$name" ;;
    *.tar.xz)       tar xJf "$tarball" -C "$BUILD/$name" ;;
    *) die "unpack: unknown archive type $tarball" ;;
  esac
  dir="$(find "$BUILD/$name" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [ -n "$dir" ] || die "unpack: nothing extracted from $tarball"
  echo "$dir"
}

# apply_patches SRCDIR PATCHDIR
apply_patches() {
  local src="$1" patches p
  [ -d "$2" ] || return 0
  patches="$(abspath "$2")"
  for p in "$patches"/*.patch; do
    [ -e "$p" ] || continue
    say "patch $(basename "$p")"
    ( cd "$src" && patch -p1 -s < "$p" ) || die "failed to apply $p"
  done
}

# Builds tools/wasi_compat.c into $BUILD/wasi_compat.o and echoes its path.
# Pass it as LIBS to configure so the functions it supplies are visible to the
# link tests too, and force-include tools/wasi_compat.h so calls to them
# compile.
wasi_compat_object() {
  mkdir -p "$BUILD"
  $ZIG cc -target wasm32-wasi -Oz -I"$REPO/tools" \
    -c "$REPO/tools/wasi_compat.c" -o "$BUILD/wasi_compat.o" >&2
  echo "$BUILD/wasi_compat.o"
}

# edit_in_place FILE SCRIPT: sed -i, spelled so it works either way.
# "sed -i ''" is the BSD form and is a syntax error to GNU sed, which reads the
# empty argument as the script and then the script as a filename; "sed -i" with
# no argument is the GNU form and makes BSD sed eat the script as a backup
# suffix. Homebrew's gnu-sed shadows /usr/bin/sed on a lot of Macs, so which
# one a build gets is not something this repo can assume. Writing to a
# temporary file and moving it back needs neither.
edit_in_place() {
  local file="$1" script="$2" tmp
  tmp="$(mktemp)"
  sed "$script" "$file" > "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

# gnulib's configure builds GL_CFLAG_GNULIB_WARNINGS by preprocessing a file
# and keeping every surviving word, which swallows the declarations from a
# force-included header and pastes them into the compiler command line. The
# variable only ever holds -Wno-* flags, so emptying it in the generated
# Makefiles costs nothing.
#
# config.status writes the variable into every Makefile it generates, one per
# directory, and a recursive package compiles gnulib from a subdirectory: nano
# has six. Clearing only the top one leaves the sub-make to paste a C
# declaration into argv and fail with a shell syntax error, so every generated
# Makefile in the tree is cleared.
clear_gnulib_warning_flags() {
  local makefile
  find "$1" -name Makefile -type f | while IFS= read -r makefile; do
    edit_in_place "$makefile" 's/^GL_CFLAG_GNULIB_WARNINGS = .*/GL_CFLAG_GNULIB_WARNINGS =/'
  done
}

# package NAME FILE...: installs the binaries into bin/ and builds the
# archive terminalOS downloads, at the repo root where `package install`
# looks for <name>.zip. It untars straight into ~/Library/bin, so the archive
# must be flat and the .wasm files must carry their executable bit (the shell
# only runs a file that has one).
package() {
  local name="$1"; shift
  local staged="$BUILD/stage-$name" f
  rm -rf "$staged"; mkdir -p "$staged" "$BIN" "$DIST"
  for f in "$@"; do
    install -m 755 "$f" "$staged/$(basename "$f")"
    install -m 755 "$f" "$BIN/$(basename "$f")"
  done
  ( cd "$staged" && tar -cf "$DIST/$name.zip" * )
  say "$name -> $name.zip ($(du -h "$DIST/$name.zip" | cut -f1))"
}
