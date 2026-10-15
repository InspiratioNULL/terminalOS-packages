/* Small pieces of POSIX that wasi-libc leaves out, implemented on top of what
 * WASI preview 1 (and therefore wasm3, and therefore terminalOS) does provide.
 *
 * Link this object into a package that needs any of them; on a non-WASI target
 * the whole file compiles to nothing.
 *
 * Copyright (C) 2026 terminalOS packages. Distributed under the same terms as
 * the program it is linked into.
 */
#ifdef __wasi__

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#include <wasi/api.h>

#include "wasi_compat.h"

/* tmpfile: wasi-libc omits it because a WASI program has no global temp
 * directory: it can only reach the directories the host preopened. wasm3
 * preopens the shell's working directory, so the file goes there and is
 * unlinked at once: the descriptor keeps it alive and nothing is left behind
 * if the program exits or crashes. */
FILE *tmpfile(void)
{
  static unsigned counter;
  unsigned seed = (unsigned) time(NULL);
  int attempt;

  for (attempt = 0; attempt < 64; attempt++) {
    char name[32];
    int fd;
    FILE *fp;

    snprintf(name, sizeof name, ".wasitmp.%08x.%u",
             seed ^ (unsigned) (attempt * 2654435761u), counter++);
    fd = open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (fd < 0)
      continue;
    fp = fdopen(fd, "w+b");
    if (!fp) {
      close(fd);
      unlink(name);
      return NULL;
    }
    unlink(name);                       /* anonymous from here on */
    return fp;
  }
  return NULL;
}

/* dup2: WASI has fd_renumber, which is the same operation: it closes
 * DESIRED_FD and makes it refer to FD. Unlike dup2 it also closes FD, so the
 * descriptor is not shared afterwards; callers that only redirect a stream
 * (the reason gnulib pulls dup2 in) do not notice the difference. */
int dup2(int fd, int desired_fd)
{
  __wasi_errno_t error;

  if (fd < 0 || desired_fd < 0) {
    errno = EBADF;
    return -1;
  }
  if (fd == desired_fd)
    return fcntl(fd, F_GETFL) == -1 ? -1 : fd;

  error = __wasi_fd_renumber((__wasi_fd_t) fd, (__wasi_fd_t) desired_fd);
  if (error != 0) {
    errno = (int) error;
    return -1;
  }
  return desired_fd;
}

/* getdtablesize: WASI has no descriptor-table limit to query. Report a value
 * large enough for any program that asks before opening files. */
int getdtablesize(void)
{
  return 1024;
}

/* getrandom: WASI's random_get is a cryptographically secure source and
 * cannot fail for a reasonable length, so the flags (GRND_RANDOM,
 * GRND_NONBLOCK) have nothing to select between. */
ssize_t getrandom(void *buffer, size_t length, unsigned int flags)
{
  __wasi_errno_t error;

  (void) flags;
  error = __wasi_random_get(buffer, length);
  if (error != 0) {
    errno = (int) error;
    return -1;
  }
  return (ssize_t) length;
}

/* Single-threaded: nothing to lock. */
void flockfile(FILE *stream) { (void) stream; }
void funlockfile(FILE *stream) { (void) stream; }
int ftrylockfile(FILE *stream) { (void) stream; return 0; }

/* No subprocesses under WASI. */
FILE *popen(const char *command, const char *mode)
{
  (void) command;
  (void) mode;
  errno = ENOSYS;
  return NULL;
}

int pclose(FILE *stream)
{
  (void) stream;
  errno = EBADF;
  return -1;
}

/* system(NULL) asking "is a shell available?" is answered honestly with 0;
 * an actual command cannot be run. */
int system(const char *command)
{
  if (command == NULL)
    return 0;
  errno = ENOSYS;
  return -1;
}

/* ------------------------------------------------------------------ *
 * Terminal control.
 *
 * wasi-libc ships a complete <termios.h> (the generic musl one: struct
 * termios, every flag, every V* index) but implements none of the functions,
 * so anything that calls tcgetattr fails to link. There is no WASI call
 * underneath to implement them with either: the terminal belongs to the host.
 *
 * The host app owns the terminal and switches to forwarding keystrokes one
 * at a time for commands that need it. A curses program does not need to put
 * the terminal into raw mode, because the terminal is already configured for
 * raw input; it only needs to read back consistent state.
 *
 * So these keep one struct termios per session and hand it back and forth.
 * tcsetattr changes nothing on the host, but the state a program reads back
 * is the state it last wrote, which is all curses actually depends on: it
 * saves the settings at startup, clears ICANON/ECHO/ONLCR, and from then on
 * decides whether to emit its own carriage returns by looking at that copy.
 * Answering honestly there matters more than driving a line discipline that
 * is not there.
 *
 * Only descriptors 0, 1 and 2 are treated as the terminal. Everything else
 * gets ENOTTY, so a program that probes a regular file still learns the truth.
 */
static struct termios wasi_tty_state = {
  .c_iflag = ICRNL | IXON,
  .c_oflag = OPOST | ONLCR,
  .c_cflag = CREAD | CS8 | B38400,
  .c_lflag = ISIG | ICANON | ECHO | ECHOE | ECHOK | IEXTEN,
  .c_cc = {
    [VINTR] = 3, [VQUIT] = 28, [VERASE] = 127, [VKILL] = 21, [VEOF] = 4,
    [VSTART] = 17, [VSTOP] = 19, [VSUSP] = 26, [VREPRINT] = 18,
    [VDISCARD] = 15, [VWERASE] = 23, [VLNEXT] = 22, [VMIN] = 1, [VTIME] = 0,
  },
  .__c_ispeed = B38400,
  .__c_ospeed = B38400,
};

static int wasi_is_terminal(int fd)
{
  if (fd == 0 || fd == 1 || fd == 2)
    return 1;
  errno = ENOTTY;
  return 0;
}

int tcgetattr(int fd, struct termios *state)
{
  if (!wasi_is_terminal(fd))
    return -1;
  *state = wasi_tty_state;
  return 0;
}

int tcsetattr(int fd, int when, const struct termios *state)
{
  (void) when;                          /* nothing is buffered to drain */
  if (!wasi_is_terminal(fd))
    return -1;
  wasi_tty_state = *state;
  return 0;
}

/* The baud rate curses multiplies its padding delays by. The terminal is a
 * view in the same process, so report the fastest rate the type can hold and
 * let it compute delays of zero. */
speed_t cfgetospeed(const struct termios *state) { return state->__c_ospeed; }
speed_t cfgetispeed(const struct termios *state) { return state->__c_ispeed; }

int cfsetospeed(struct termios *state, speed_t speed)
{
  state->__c_ospeed = speed;
  return 0;
}

int cfsetispeed(struct termios *state, speed_t speed)
{
  state->__c_ispeed = speed;
  return 0;
}

/* Nothing is queued on either side: a write has already reached the host by
 * the time fd_write returns, and unread input lives in the host's pipe, which
 * a WASI program has no call to discard. */
int tcdrain(int fd) { return wasi_is_terminal(fd) ? 0 : -1; }
int tcflush(int fd, int queue) { (void) queue; return wasi_is_terminal(fd) ? 0 : -1; }
int tcflow(int fd, int action) { (void) action; return wasi_is_terminal(fd) ? 0 : -1; }

/* ------------------------------------------------------------------ *
 * Waiting.
 *
 * wasm3 does not link poll_oneoff, and it rejects a module that imports one
 * it does not have: the failure is 'missing imported function' at load time,
 * before main runs. That makes poll_oneoff worse than a call that fails,
 * because wasi-libc reaches it from poll, select and every sleep, so a single
 * unreachable usleep anywhere in a program stops the whole binary from
 * loading. Each of them is defined here instead, which keeps the import out
 * of the module entirely.
 */

/* A timed wait for input, with no way to time one. The distinction that
 * matters to curses is between the two kinds of call it makes:
 *
 *   timeout == 0   a poll, from nodelay mode: 'is there a key already?'
 *                  Answering yes would send curses into a read that blocks,
 *                  and nano polls like this while it waits for a paste burst
 *                  to end, so the honest and safe answer is no.
 *
 *   timeout != 0   a wait, from a blocking getch or from the pause that
 *                  disambiguates a lone ESC from an escape sequence.
 *                  Answering ready sends curses into a read, which blocks
 *                  until the host has a byte, which is the wait it asked for.
 *
 * The cost is the ESC disambiguation: the bytes of an escape sequence are
 * already in flight, so arrow and function keys assemble correctly, but ESC
 * pressed on its own cannot be recognised as final until another key follows
 * it. See the note in the README.
 */
int poll(struct pollfd *fds, nfds_t count, int timeout)
{
  nfds_t i;
  int ready = 0;

  if (timeout == 0) {
    for (i = 0; i < count; i++)
      fds[i].revents = 0;
    return 0;
  }

  for (i = 0; i < count; i++) {
    fds[i].revents = (short) (fds[i].events & (POLLIN | POLLOUT));
    if (fds[i].revents != 0)
      ready++;
  }
  return ready;
}

/* Sleeping is implemented by reading the clock in a loop. There is no yield
 * mechanism and no other thread to yield to, so waiting consumes CPU.
 * Millisecond delays in curses are negligible, but multi-second pauses
 * (e.g. status messages) would consume unnecessary CPU. Waits are therefore
 * served in full up to WASI_MAX_SPIN_NS and capped after that. */
#define WASI_MAX_SPIN_NS 250000000ULL   /* 250 ms */

static void wasi_spin(unsigned long long nanoseconds)
{
  __wasi_timestamp_t now, deadline;

  if (nanoseconds > WASI_MAX_SPIN_NS)
    nanoseconds = WASI_MAX_SPIN_NS;
  if (__wasi_clock_time_get(__WASI_CLOCKID_MONOTONIC, 1000, &now) != 0)
    return;

  deadline = now + nanoseconds;
  while (now < deadline) {
    if (__wasi_clock_time_get(__WASI_CLOCKID_MONOTONIC, 1000, &now) != 0)
      return;
  }
}

int nanosleep(const struct timespec *requested, struct timespec *remaining)
{
  if (requested->tv_nsec < 0 || requested->tv_nsec >= 1000000000L ||
      requested->tv_sec < 0) {
    errno = EINVAL;
    return -1;
  }
  wasi_spin((unsigned long long) requested->tv_sec * 1000000000ULL +
            (unsigned long long) requested->tv_nsec);
  if (remaining) {
    remaining->tv_sec = 0;
    remaining->tv_nsec = 0;
  }
  return 0;
}

int usleep(unsigned useconds)
{
  wasi_spin((unsigned long long) useconds * 1000ULL);
  return 0;
}

unsigned sleep(unsigned seconds)
{
  wasi_spin((unsigned long long) seconds * 1000000000ULL);
  return 0;
}

/* mkstemp and mkstemps, left out for the same reason as tmpfile: a WASI
 * program has no global temp directory, only the directories the host
 * preopened. Unlike tmpfile these keep the name -- the caller chose it and
 * will use it again -- so the file stays where the template puts it, which
 * under wasm3 means it has to be a relative path inside the working
 * directory. The template's trailing XXXXXX is replaced in place, as POSIX
 * requires, and O_EXCL makes the choice a claim rather than a guess. */
static int wasi_mkstemp(char *template, int suffixlen)
{
  static const char alphabet[] =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  size_t length = strlen(template);
  char *slot;
  int attempt;

  if (suffixlen < 0 || (size_t) suffixlen + 6 > length) {
    errno = EINVAL;
    return -1;
  }
  slot = template + length - (size_t) suffixlen - 6;
  if (memcmp(slot, "XXXXXX", 6) != 0) {
    errno = EINVAL;
    return -1;
  }

  for (attempt = 0; attempt < 256; attempt++) {
    unsigned char randomness[6];
    int i, fd;

    if (__wasi_random_get(randomness, sizeof randomness) != 0) {
      errno = EIO;
      return -1;
    }
    for (i = 0; i < 6; i++)
      slot[i] = alphabet[randomness[i] % (sizeof alphabet - 1)];

    fd = open(template, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (fd >= 0)
      return fd;
    if (errno != EEXIST)
      return -1;
  }

  memcpy(slot, "XXXXXX", 6);
  errno = EEXIST;
  return -1;
}

int mkstemp(char *template) { return wasi_mkstemp(template, 0); }
int mkstemps(char *template, int suffixlen) { return wasi_mkstemp(template, suffixlen); }

/* ------------------------------------------------------------------ *
 * A password database with nobody in it.
 *
 * wasi-libc declares all of <pwd.h> and implements none of it, so a program
 * that offers to complete a ~user name, or asks who it is running as, fails
 * to link. terminalOS has no user accounts to answer with -- one person, one
 * app, no uids -- so the database here is real and empty: every lookup
 * reports no such entry, and iterating it ends immediately.
 *
 * A synthesised entry built from $HOME and $USER would make ~someuser expand
 * to a directory that has nothing to do with someuser. A bare ~ is unaffected:
 * programs take that from $HOME, which the shell sets.
 */
void setpwent(void) { }
void endpwent(void) { }
struct passwd *getpwent(void) { return NULL; }

struct passwd *getpwuid(uid_t uid)
{
  (void) uid;
  errno = ENOENT;
  return NULL;
}

struct passwd *getpwnam(const char *name)
{
  (void) name;
  errno = ENOENT;
  return NULL;
}

/* No controlling terminal in the POSIX sense, and no login to have happened:
 * the shell started this program directly. */
char *getlogin(void)
{
  errno = ENXIO;
  return NULL;
}

/* ------------------------------------------------------------------ *
 * Signals that are never delivered.
 *
 * See the note in wasi_compat.h. Handlers are recorded so a program can
 * install one, read it back, and restore it; the mask is kept for the same
 * reason. Nothing consults either, because there is no path in wasm3 by which
 * a signal could arrive: no other thread, no kernel, no timer, and ^C reaches
 * a program as the byte 0x03 on stdin rather than as SIGINT.
 */
#define WASI_NSIG 64

static struct sigaction wasi_handlers[WASI_NSIG];
static sigset_t wasi_blocked;

static int wasi_signal_in_range(int signum)
{
  if (signum > 0 && signum < WASI_NSIG)
    return 1;
  errno = EINVAL;
  return 0;
}

int sigaction(int signum, const struct sigaction *action,
              struct sigaction *previous)
{
  if (!wasi_signal_in_range(signum))
    return -1;
  if (previous)
    *previous = wasi_handlers[signum];
  if (action)
    wasi_handlers[signum] = *action;
  return 0;
}

int sigprocmask(int how, const sigset_t *set, sigset_t *previous)
{
  if (previous)
    *previous = wasi_blocked;
  if (!set)
    return 0;
  switch (how) {
    case SIG_BLOCK:   wasi_blocked |= *set;  break;
    case SIG_UNBLOCK: wasi_blocked &= ~*set; break;
    case SIG_SETMASK: wasi_blocked = *set;   break;
    default: errno = EINVAL; return -1;
  }
  return 0;
}

int sigemptyset(sigset_t *set) { *set = 0; return 0; }
int sigfillset(sigset_t *set) { *set = (sigset_t) ~0u; return 0; }

/* wasi-libc's sigset_t is an unsigned char, so only the first eight signal
 * numbers have a bit to live in, while the numbers themselves run to 64. The
 * signals typically blocked (e.g. SIGTSTP at 20, SIGWINCH at 28) are outside
 * this range. Adding such a signal to a set succeeds as a no-op because signal
 * delivery is never triggered by the runtime. */
#define WASI_SIGSET_BITS (8 * (int) sizeof(sigset_t))

int sigaddset(sigset_t *set, int signum)
{
  if (!wasi_signal_in_range(signum))
    return -1;
  if (signum < WASI_SIGSET_BITS)
    *set |= (sigset_t) (1u << signum);
  return 0;
}

int sigdelset(sigset_t *set, int signum)
{
  if (!wasi_signal_in_range(signum))
    return -1;
  if (signum < WASI_SIGSET_BITS)
    *set &= (sigset_t) ~(1u << signum);
  return 0;
}

int sigismember(const sigset_t *set, int signum)
{
  if (!wasi_signal_in_range(signum))
    return -1;
  if (signum >= WASI_SIGSET_BITS)
    return 0;
  return (*set & (sigset_t) (1u << signum)) != 0;
}

/* There is one process and no way to signal it. A program that suspends
 * itself with kill(0, SIGSTOP) gets the failure instead and stays running,
 * which is the only outcome available under a shell that has no job
 * control. */
int kill(int pid, int signum)
{
  (void) pid;
  (void) signum;
  errno = ENOSYS;
  return -1;
}

#endif /* __wasi__ */
