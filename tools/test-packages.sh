#!/bin/bash
# Runs every built package through the wasm3 build terminalOS ships and checks
# what it prints. Build the runner first with tools/build-wasm3-harness.sh.
set -u

TOOLS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$TOOLS")"
WASM3="$TOOLS/wasm3-harness"
[ -x "$WASM3" ] || { echo "no wasm3 harness: run tools/build-wasm3-harness.sh" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# check runs on the right-hand side of a pipe, i.e. in a subshell, so the
# tally lives in a file rather than in a variable.
TALLY="$WORK/.tally"
: > "$TALLY"

# check NAME EXPECTED: the command's output arrives on stdin.
check() {
  local name="$1" expected="$2" got
  got="$(cat)"
  if [ "$got" = "$expected" ]; then
    printf '  ok   %s\n' "$name"; echo ok >> "$TALLY"
  else
    printf '  FAIL %s\n       expected: %s\n       got:      %s\n' \
      "$name" "$expected" "$got"; echo fail >> "$TALLY"
  fi
}

run() { "$WASM3" "$REPO/bin/$1" "${@:2}"; }

echo "units"
run units.wasm ft m | tr -d '\t' | head -1 | check "ft -> m" "* 0.3048"
run units.wasm 'tempF(212)' tempC | tr -d '\t' | check "nonlinear tempF" "100"
run units.wasm '2 cups' tablespoons | tr -d '\t' | head -1 | check "cooking units" "* 32"

echo "jq"
echo '{"a":[1,2,3]}' | run jq.wasm -c '.a | add' | check "arithmetic" "6"
echo '{"s":"hello"}' | run jq.wasm -r '.s | ascii_upcase' | check "string builtin" "HELLO"
echo '{"s":"hello"}' | run jq.wasm -r '.s | test("ell")' | check "regex (oniguruma)" "true"

echo "sqlite3"
printf 'create table t(a,b);\ninsert into t values(1,%s);\nselect a || "-" || b from t;\n' '"x"' \
  | run sqlite3.wasm smoke.db | check "create/insert/select on a file" "1-x"
printf 'select json_extract(\x27{"k":42}\x27, "$.k");\n' | run sqlite3.wasm :memory: | check "json1" "42"

echo "datamash"
printf 'a 1\na 2\nb 5\nb 7\n' | run datamash.wasm -W -g 1 sum 2 \
  | tr '\t' ' ' | tr '\n' ';' | check "group-by sum" "a 3;b 12;"
printf '1\n2\n3\n4\n' | run datamash.wasm mean 1 median 1 | tr '\t' ' ' | check "mean/median" "2.5 2.5"

echo "ed"
printf 'one\ntwo\n' > ed.txt
printf 's/two/TWO/\nw\nq\n' | run ed.wasm -s ed.txt > /dev/null 2>&1
cat ed.txt | tr '\n' ' ' | check "substitute and write" "one TWO "

echo "nano"
run nano.wasm --version | head -1 | check "version" " GNU nano, version 9.2"
run pico.wasm --version | head -1 | check "pico is the same binary" " GNU nano, version 9.2"
# The syntax definitions are compiled in; there is no /usr/local/share/nano to
# read them from, so a full list proves the embedded table was found.
run nano.wasm --listsyntaxes | tail -n +2 | tr -s ' \n' '\n' | grep -c . \
  | check "syntaxes compiled in" "39"

# A real editing session, on a pty because nano will not start without one --
# and on device it always has one, since wasm3 answers isatty through
# ios_isatty and terminalOS's fds 0-2 are the terminal.
# Down arrow (in the application-cursor mode curses switches the terminal to),
# ^E to end of line, type, ^O write, Enter to confirm, ^X exit.
printf 'alpha\nbeta\ngamma\n' > nano.txt
printf '\033OB\0\005\0 EDITED\0\017\0\r\0\030' \
  | "$TOOLS/pty-run.py" "$WASM3" "$REPO/bin/nano.wasm" nano.txt > /dev/null 2>&1
tr '\n' ' ' < nano.txt | check "arrow, end-of-line, insert, ^O write, ^X exit" \
  "alpha beta EDITED gamma "

# Colour with no nanorc anywhere on disk: the sh syntax came from the binary.
printf '#!/bin/sh\nfor i in 1 2; do echo "$i"; done\n' > nano.sh
if printf '\030' | "$TOOLS/pty-run.py" "$WASM3" "$REPO/bin/nano.wasm" nano.sh 2>/dev/null \
     | grep -q $'\033\[3[0-9]m'; then echo yes; else echo no; fi \
  | check "syntax colouring, unconfigured" "yes"

echo
pass=$(grep -c '^ok$'   "$TALLY" || true)
fail=$(grep -c '^fail$' "$TALLY" || true)
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
