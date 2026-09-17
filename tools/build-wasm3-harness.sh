#!/bin/bash
# Builds the wasm3 that terminalOS ships, as a macOS binary, so packages can be
# tested against the exact runtime they will run on, not against wasmtime,
# which is more forgiving (it accepts POSIX file locking and absolute paths
# that wasm3 rejects).
#
# The source is the copy vendored in the terminalOS app repo, iOS code paths
# and all; the few symbols ios_system would normally provide are stubbed here.
#
#   ./build-wasm3-harness.sh [path-to-wasm3-source]
set -e

TOOLS="$(cd "$(dirname "$0")" && pwd)"
W="${1:-${WASM3_SRC:-${TERMINALOS_APP:-}}}"
if [ -n "$W" ] && [ ! -d "$W/source" ]; then
  find_w="$(find "$W" -maxdepth 3 -type d -name source 2>/dev/null | grep wasm3 | head -1 || true)"
  [ -n "$find_w" ] && W="$(dirname "$find_w")"
fi
[ -n "$W" ] && [ -d "$W/source" ] || { echo "usage: build-wasm3-harness.sh <path-to-wasm3-source>" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/shim.h" <<'HDR'
#define _DARWIN_C_SOURCE 1
#include <stdio.h>
#include <sys/uio.h>
#include <dirent.h>
#include <Security/SecRandom.h>
extern FILE* thread_stdin; extern FILE* thread_stdout; extern FILE* thread_stderr;
char** environmentVariables(int pid);
int ios_currentPid(void);
int ios_isatty(int fd);
int ios_fork(void); int ios_system(const char*); void ios_waitpid(int); void ios_releaseThreadId(int);
int ios_getCommandStatus(void); char* ios_getenv(const char*);
int ios_setenv(const char*, const char*, int); int ios_unsetenv(const char*);
HDR
cp "$WORK/shim.h" "$WORK/ios_error.h"
echo '#define ios_error(...) fprintf(thread_stderr, __VA_ARGS__)' >> "$WORK/ios_error.h"

cat > "$WORK/shim.c" <<'SRC'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
extern char** environ;
FILE* thread_stdin; FILE* thread_stdout; FILE* thread_stderr;
char** environmentVariables(int pid) { (void)pid; return environ; }
int ios_currentPid(void) { return 0; }
int ios_isatty(int fd) { return isatty(fd); }
int ios_fork(void) { return 0; }
int ios_system(const char* c) { return system(c); }
void ios_waitpid(int p) { (void)p; }
void ios_releaseThreadId(int p) { (void)p; }
int ios_getCommandStatus(void) { return 0; }
char* ios_getenv(const char* n) { return getenv(n); }
int ios_setenv(const char* n, const char* v, int o) { return setenv(n, v, o); }
int ios_unsetenv(const char* n) { return unsetenv(n); }
__attribute__((constructor)) static void initshim(void) {
  thread_stdin = stdin; thread_stdout = stdout; thread_stderr = stderr;
}
SRC

# TARGET_OS_IPHONE=1 selects the same code paths the app builds.
clang -O2 -Dd_m3HasWASI -DTARGET_OS_IPHONE=1 \
  -I"$WORK" -I"$W/source" -include "$WORK/shim.h" \
  -framework Security \
  -o "$TOOLS/wasm3-harness" \
  "$WORK/shim.c" "$W/platforms/app/main.c" \
  $(ls "$W"/source/*.c | grep -v uvwasi)

echo "built $TOOLS/wasm3-harness"
