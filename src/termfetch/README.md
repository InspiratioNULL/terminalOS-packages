# termfetch

A small fetch-style overview for terminalOS, licensed GPL-3.0-or-later
(see the repository's `COPYING`). It is original C source, not a port of neofetch.

```
brew update
brew install termfetch
termfetch
termfetch --json
termfetch --no-logo --no-color
```

The archive and refreshed index must be published to the configured package
repository before those install commands can discover this new package.

## Native host bridge

The companion app's `TerminalFetchInfo` collector refreshes host information
when its shell launches `wasm`/`wasm3` or `termfetch`, using the existing WASI
environment forwarding. It restores the caller's values when the command
returns. No new WASM imports, private APIs, subprocesses or network requests
are needed. A new native app build is required for automatic host readings.

All values below are optional, display-ready UTF-8 strings. The command currently
renders printable ASCII and replaces other bytes with `?` to prevent terminal
control sequences from environment values or Git refs. Each value is capped at
255 bytes. JSON uses the same sanitized values and never contains ANSI styling.

| Environment variable | Meaning |
|---|---|
| `TERMFETCH_OS` | Platform and OS version |
| `TERMFETCH_KERNEL` | Kernel name and release |
| `TERMFETCH_DEVICE` | Hardware model identifier, or simulator model with an explicit Simulator label |
| `TERMFETCH_CPU` | CPU brand if exposed; otherwise architecture, with total/active core counts |
| `TERMFETCH_MEMORY` | Total physical device memory |
| `TERMFETCH_APP_MEMORY` | App resident memory; not device-wide used memory |
| `TERMFETCH_UPTIME` | System awake time since restart |
| `TERMFETCH_DISK` | Available and total capacity of the home directory's volume |
| `TERMFETCH_DISPLAY` | Main display native pixel dimensions |
| `TERMFETCH_BATTERY` | Charge percentage and state, when available on iOS |
| `TERMFETCH_THERMAL` | Nominal, fair, serious or critical thermal state |
| `TERMFETCH_PACKAGES` | Installed brew receipt count, not number of command aliases |
| `TERMFETCH_APP` | App version/build |

The package also reads `USER`/`LOGNAME`, `HOSTNAME`, `SHELL`, `TERM`, `COLUMNS`,
`LINES`, and `PWD` when present. Unknown values are omitted, never guessed.
`Session` and `Runtime` describe the package's terminalOS/WASI execution context.

The native bridge supplies snapshots at the app shell's launch boundary. A
long-running nested shell or another execution path that bypasses `OSShell`
does not refresh that snapshot for each of its child commands. Simulator RAM
and CPU readings describe the simulator host, not simulated iPhone hardware.
Battery readings are omitted on tvOS and when the iOS API reports unknown.
The model identifier is not a maintained marketing-name lookup database.

Git detection is intentionally local: run at a repository root containing a
`.git` directory. Worktree `.git` files and searching parent directories are
not supported. Both branch refs and detached HEADs are recognized.

## Options

- `--json`: machine-readable object, without a logo, colors or palette.
- `--no-logo`: omit the logo and palette.
- `--no-color`: disable ANSI color.
- `--color`: explicitly enable color, including redirected output.
- `--help`, `-h`, `--version`.

Automatic color requires a terminal, a `TERM` other than `dumb`, and no
`NO_COLOR` variable. Explicit color options are processed from left to right.
The logo is stacked above the fields so it fits phone-width terminals.

## Build and test

```
src/termfetch/build.sh
python3 tools/make-index.py
python3 tools/test-termfetch.py tools/wasm3-harness bin/termfetch.wasm
```

The tests run the actual WASI binary, including sparse environments, host data,
Git refs, JSON escaping, control-code filtering, CLI errors, archive contents,
permissions and the index checksum. `tools/test-packages.sh` includes this test.
