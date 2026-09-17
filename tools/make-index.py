#!/usr/bin/env python3
"""Regenerates index.json from the built archives at the repo root.

The index is what a package client reads to know what exists, what to
download, and what to check it against. Keep PACKAGES below in step with
src/*/build.sh; everything else here is derived from the files on disk."""
import hashlib, json, os, subprocess, sys
from datetime import date

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PACKAGES = [
    {
        "name": "units",
        "version": "2.23",
        "description": "GNU unit conversion calculator, with the unit database built in",
        "homepage": "https://www.gnu.org/software/units/",
        "license": "GPL-3.0-or-later",
        "commands": ["units"],
        "notes": "Interactive when run with no arguments. The database "
                 "(definitions, currency, elements, CPI) is compiled into the "
                 "binary; currency rates are a snapshot from 2024-02-18.",
    },
    {
        "name": "jq",
        "version": "1.7.1",
        "description": "Command-line JSON processor",
        "homepage": "https://jqlang.github.io/jq/",
        "license": "MIT",
        "commands": ["jq"],
        "notes": "Includes the Oniguruma regex builtins (test, match, capture, "
                 "sub, splits). Passes all 447 upstream tests under wasm3.",
    },
    {
        "name": "sqlite3",
        "version": "3.50.4",
        "description": "SQLite command-line shell, with FTS5, R*Tree and JSON",
        "homepage": "https://sqlite.org/cli.html",
        "license": "blessing",      # SPDX id for SQLite's public-domain blessing
        "commands": ["sqlite3"],
        "notes": "Databases open lock-free (the unix-none VFS): safe for one "
                 "process at a time, which is what a terminal does. No WAL, no "
                 "loadable extensions, no .shell/.excel.",
    },
    {
        "name": "datamash",
        "version": "1.9",
        "description": "GNU command-line statistics: group-by, mean, median, sum, crosstab",
        "homepage": "https://www.gnu.org/software/datamash/",
        "license": "GPL-3.0-or-later",
        "commands": ["datamash"],
        "notes": "The companion 'decorate' program is not included: it needs to "
                 "pipe through a real sort(1) process.",
    },
    {
        "name": "nano",
        "version": "9.2",
        "description": "GNU nano, the full-screen editor, with syntax highlighting built in",
        "homepage": "https://www.nano-editor.org/",
        "license": "GPL-3.0-or-later",
        "commands": ["nano", "pico"],
        "notes": "Requires direct keystroke input enabled in the host app. "
                 "The 39 syntax definitions are compiled into the binary, so "
                 "colouring works with nothing on disk; a nanorc in the "
                 "working directory, or one named with -f, still overrides it. "
                 "No subprocesses: ^T reports an error, and the spell checker, "
                 "formatter and linter are not built. ^Z cannot suspend, "
                 "nothing can deliver SIGWINCH so a rotate needs ^L to redraw, "
                 "and ESC pressed on its own is not seen until the next key "
                 "(Meta combinations are unaffected). pico is a second copy "
                 "of the same binary, which is why the archive is twice its size.",
    },
    {
        "name": "ed",
        "version": "1.21",
        "description": "GNU ed, the standard line editor: scriptable, no cursor addressing",
        "homepage": "https://www.gnu.org/software/ed/",
        "license": "GPL-2.0-or-later",
        "commands": ["ed"],
        "notes": "Shell escapes (!command, r !command, w !command) report an "
                 "error: WASI has no subprocesses. Everything else passes the "
                 "upstream testsuite. Needs a writable working directory for "
                 "its buffer file.",
    },
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    base = os.environ.get(
        "TERMINALOS_PACKAGES_URL",
        "https://github.com/InspiratioNULL/terminalOS-packages/raw/main")
    entries = []
    for pkg in PACKAGES:
        archive = os.path.join(REPO, pkg["name"] + ".zip")
        if not os.path.exists(archive):
            sys.exit("missing %s: run src/%s/build.sh first"
                     % (archive, pkg["name"]))
        # One .wasm per command, named for it: that is how the shell finds a
        # package on PATH, and nano installs two (pico is the same editor).
        files = [command + ".wasm" for command in pkg["commands"]]
        for name in files:
            if not os.path.exists(os.path.join(REPO, "bin", name)):
                sys.exit("missing bin/%s: run src/%s/build.sh first"
                         % (name, pkg["name"]))
        entry = dict(pkg)
        entry["files"] = files
        entry["archive"] = "%s.zip" % pkg["name"]
        entry["url"] = "%s/%s.zip" % (base, pkg["name"])
        entry["sha256"] = sha256(archive)
        entry["size"] = os.path.getsize(archive)
        entry["source"] = "src/%s" % pkg["name"]
        entries.append(entry)

    index = {
        "schema": 1,
        "generated": date.today().isoformat(),
        "runtime": {
            "abi": "wasm32-wasip1",
            "engine": "wasm3",
            "installs_to": "~/Library/bin",
        },
        "packages": entries,
    }
    out = os.path.join(REPO, "index.json")
    with open(out, "w") as f:
        json.dump(index, f, indent=2)
        f.write("\n")
    print("wrote %s (%d packages)" % (out, len(entries)))


if __name__ == "__main__":
    main()
