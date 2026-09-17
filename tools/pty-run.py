#!/usr/bin/env python3
"""Run a command on a pty and type at it, for testing a full-screen program.

    printf 'hi\\0\\017\\0\\r\\0\\030' | pty-run.py tools/wasm3-harness bin/nano.wasm f

Keystrokes arrive on stdin, split into chunks on NUL. A chunk is sent each
time the program stops drawing, so the steps of a session land in order
instead of all at once; what the program wrote to the screen comes back on
stdout, escape sequences and all.

A pty is required because nano refuses to start when stdout is not a
terminal. On device, wasm3 answers isatty through ios_isatty, and terminalOS's
fds 0, 1 and 2 are connected to the terminal.

The pty is put in raw mode in the child. Left cooked, the line discipline
echoes every keystroke back into the captured screen and turns CR into NL,
which nano reads as ^J and justifies the paragraph with.

TERM, COLUMNS and LINES are set unless the caller set them: WASI has no
TIOCGWINSZ, so curses has nothing but the environment to size the screen
from, which is why terminalOS exports them.
"""
import os, pty, select, signal, sys, time, tty

USAGE = "usage: pty-run.py PROGRAM [ARG...] < keystrokes-separated-by-NUL"

QUIET = 0.4        # seconds of no output before the next chunk is sent
TIMEOUT = 30       # seconds before the program is declared stuck


def main(argv):
    if not argv:
        sys.exit(USAGE)

    chunks = [c for c in sys.stdin.buffer.read().split(b"\0") if c]
    env = dict(os.environ)
    env.setdefault("TERM", "xterm-color")
    env.setdefault("COLUMNS", "80")
    env.setdefault("LINES", "24")

    pid, fd = pty.fork()
    if pid == 0:
        tty.setraw(0)
        os.execvpe(argv[0], argv, env)

    screen = bytearray()
    last_output = time.time()
    deadline = time.time() + TIMEOUT
    exited = False

    while time.time() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.1)
        if readable:
            try:
                data = os.read(fd, 65536)
            except OSError:          # the pty closed under us: the child left
                data = b""
            if not data:
                exited = True
                break
            screen += data
            last_output = time.time()
            continue
        if os.waitpid(pid, os.WNOHANG)[0]:
            exited = True
            break
        if chunks and time.time() - last_output >= QUIET:
            os.write(fd, chunks.pop(0))
            last_output = time.time()

    if not exited:
        os.kill(pid, signal.SIGKILL)
    try:
        status = os.waitpid(pid, 0)[1]
    except ChildProcessError:
        status = 0
    os.close(fd)

    sys.stdout.buffer.write(bytes(screen))
    sys.stdout.buffer.flush()
    if not exited:
        sys.stderr.write("pty-run.py: %s did not exit within %ds\n"
                         % (argv[0], TIMEOUT))
        return 1
    if chunks:
        sys.stderr.write("pty-run.py: %s exited with %d chunks unsent\n"
                         % (argv[0], len(chunks)))
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
