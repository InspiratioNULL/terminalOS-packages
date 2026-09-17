/* Declarations for the POSIX bits wasi-libc leaves out; see wasi_compat.c.
 *
 * Force-include this header (cc -include wasi_compat.h) when building a
 * package whose sources (or whose gnulib copy) call these functions, so
 * the calls compile; link wasi_compat.c to supply them.
 */
#ifndef WASI_COMPAT_H
#define WASI_COMPAT_H
#ifdef __wasi__

/* F_DUPFD. WASI has no way to duplicate a descriptor onto a chosen number
   except fd_renumber, which is dup2, so wasi-libc defines no F_DUPFD at all.
   gnulib notices it missing and fills in 1 -- the number wasi-libc already
   uses for F_GETFD. Any gnulib program then fails to compile the moment
   rpl_fcntl switches on both: "duplicate case value". Claiming the number
   first, out of the range wasi-libc assigns from, leaves gnulib's #ifndef
   satisfied and the two constants distinct. Nothing can service the request;
   wasi-libc's fcntl answers an unknown command with EINVAL.  */
#ifndef F_DUPFD
#define F_DUPFD 0x40000001
#endif

/* No #include <stdio.h> here. This header is force-included ahead of every
   other one, and gnulib's replacement headers refuse to be included before
   config.h. Repeating wasi-libc's FILE typedef is valid C11 and keeps this
   header free-standing. */
typedef struct _IO_FILE FILE;

FILE *tmpfile(void);
int dup2(int fd, int desired_fd);
int getdtablesize(void);

/* WebAssembly under wasm3 is single threaded: the stdio locks are no-ops. */
void flockfile(FILE *stream);
void funlockfile(FILE *stream);
int ftrylockfile(FILE *stream);

/* getrandom over the WASI random_get call. wasi-libc does not declare it, so
   gnulib substitutes a version that has no way to get entropy and fails with
   ENOSYS on every call. The builtin types keep this header free-standing:
   on wasm32 they are exactly ssize_t and size_t. */
__PTRDIFF_TYPE__ getrandom(void *buffer, __SIZE_TYPE__ length,
                           unsigned int flags);

/* There are no subprocesses: popen always fails, and pclose reports an
   invalid stream. Programs that check the return value degrade cleanly. */
FILE *popen(const char *command, const char *mode);
int pclose(FILE *stream);
int system(const char *command);


/* Temporary files with a name the caller keeps; see wasi_compat.c. Both are
   relative to the working directory, the only place wasm3 preopens. */
int mkstemp(char *template);
int mkstemps(char *template, int suffixlen);

/* POSIX signals, as types and nothing else.
 *
 * wasi-libc's <signal.h> keeps the signal numbers (SIGINT, SIGWINCH and the
 * rest, NSIG = 65, inherited from musl's Linux table) but hides sigset_t,
 * struct sigaction and functions that take them behind
 * __wasilibc_unmodified_upstream, because WASI cannot deliver a signal.
 * Providing signal numbers without the corresponding API prevents programs
 * that install signal handlers from compiling.
 *
 * Declaring the API here and defining it in wasi_compat.c lets such programs
 * build and run unmodified: calls succeed and handlers are stored, but
 * handlers are never invoked because the runtime cannot raise signals. A
 * terminal resize, interrupt, or hangup will not be received.
 *
 * The layout is musl's, so sa_handler and sa_sigaction alias as POSIX says
 * they may. Which member a program assigns cannot matter here; neither is
 * ever read back to be called.
 *
 * sigset_t is one thing wasi-libc does define, as an unsigned char, and it is
 * taken from the one header that declares it rather than repeated here: a
 * second typedef of a different width would be an error the moment any system
 * header is included. Eight bits is narrower than the signal numbers go, so
 * the mask cannot represent SIGWINCH or SIGTSTP at all -- see the note on
 * sigaddset in wasi_compat.c for why that costs nothing.  */
#include <__typedef_sigset_t.h>

struct sigaction {
  union {
    void (*sa_handler)(int);
    void (*sa_sigaction)(int, void *, void *);
  } __sa_handler;
  sigset_t sa_mask;
  int sa_flags;
};
#define sa_handler   __sa_handler.sa_handler
#define sa_sigaction __sa_handler.sa_sigaction

#ifndef SIG_BLOCK
#define SIG_BLOCK   0
#define SIG_UNBLOCK 1
#define SIG_SETMASK 2
#endif
#ifndef SA_NOCLDSTOP
#define SA_NOCLDSTOP 1
#endif
#ifndef SA_RESETHAND
#define SA_RESETHAND 0x80000000
#endif
#ifndef SA_RESTART
#define SA_RESTART 0x10000000
#endif
#ifndef SA_SIGINFO
#define SA_SIGINFO 4
#endif

int sigaction(int signum, const struct sigaction *action,
              struct sigaction *previous);
int sigprocmask(int how, const sigset_t *set, sigset_t *previous);
int sigemptyset(sigset_t *set);
int sigfillset(sigset_t *set);
int sigaddset(sigset_t *set, int signum);
int sigdelset(sigset_t *set, int signum);
int sigismember(const sigset_t *set, int signum);
int kill(int pid, int signum);

#endif /* __wasi__ */
#endif /* WASI_COMPAT_H */
