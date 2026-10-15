/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define VERSION "1.0.0"
#define CAP 256
struct field { const char *key; char value[CAP]; };
static struct field fields[32];
static size_t count;

/* Environment and repository text must never inject terminal control codes. */
static void add(const char *key, const char *value) {
    if (!value || !*value || count == sizeof(fields) / sizeof(fields[0])) return;
    struct field *f = &fields[count++];
    f->key = key;
    size_t n = 0;
    for (; *value && n < CAP - 1; value++) {
        unsigned char c = (unsigned char)*value;
        f->value[n++] = (c < 32 || c >= 127) ? '?' : (char)c;
    }
    f->value[n] = 0;
}

static const char *env_or(const char *key, const char *fallback) {
    const char *value = getenv(key);
    return value && *value ? value : fallback;
}

static void collect(void) {
    add("Session", "terminalOS");
    add("Runtime", "WebAssembly / WASI preview 1");
    add("User", env_or("USER", getenv("LOGNAME")));
    add("Host", getenv("HOSTNAME"));
    add("OS", getenv("TERMFETCH_OS"));
    add("Kernel", getenv("TERMFETCH_KERNEL"));
    add("Device", getenv("TERMFETCH_DEVICE"));
    add("CPU", getenv("TERMFETCH_CPU"));
    add("Memory", getenv("TERMFETCH_MEMORY"));
    add("App memory", getenv("TERMFETCH_APP_MEMORY"));
    add("Uptime", getenv("TERMFETCH_UPTIME"));
    add("Disk", getenv("TERMFETCH_DISK"));
    add("Display", getenv("TERMFETCH_DISPLAY"));
    add("Battery", getenv("TERMFETCH_BATTERY"));
    add("Thermal", getenv("TERMFETCH_THERMAL"));
    add("Packages", getenv("TERMFETCH_PACKAGES"));
    add("App", getenv("TERMFETCH_APP"));
    add("Shell", getenv("SHELL"));
    add("Terminal", getenv("TERM"));
    const char *cols = getenv("COLUMNS"), *lines = getenv("LINES");
    if (cols && *cols && lines && *lines) {
        char size[CAP];
        snprintf(size, sizeof(size), "%.32s x %.32s", cols, lines);
        add("Size", size);
    }
    add("Directory", getenv("PWD"));
    /* Only cwd is preopened by terminalOS. Do not walk above that boundary. */
    FILE *head = fopen(".git/HEAD", "r");
    if (head) {
        char line[CAP];
        if (fgets(line, sizeof(line), head)) {
            line[strcspn(line, "\r\n")] = 0;
            if (!strncmp(line, "ref: refs/heads/", 16)) add("Git", line + 16);
            else if (strlen(line) >= 7 && strspn(line, "0123456789abcdef") == strlen(line)) {
                char detached[40];
                snprintf(detached, sizeof(detached), "%.12s (detached)", line);
                add("Git", detached);
            }
        }
        fclose(head);
    }
}

static void json_string(const char *s) {
    putchar('"');
    for (; *s; s++) {
        if (*s == '"' || *s == '\\') putchar('\\');
        putchar((unsigned char)*s);
    }
    putchar('"');
}

int main(int argc, char **argv) {
    int json = 0, logo = 1;
    int color = isatty(STDOUT_FILENO) && !getenv("NO_COLOR") &&
                strcmp(env_or("TERM", "dumb"), "dumb");
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--json")) json = 1;
        else if (!strcmp(argv[i], "--no-logo")) logo = 0;
        else if (!strcmp(argv[i], "--no-color")) color = 0;
        else if (!strcmp(argv[i], "--color")) color = 1;
        else if (!strcmp(argv[i], "--version")) { puts("termfetch " VERSION); return 0; }
        else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            puts("termfetch " VERSION " - a fetch-style overview for terminalOS\n"
                 "Usage: termfetch [--json] [--no-logo] [--no-color | --color]\n"
                 "       termfetch --help | --version\n\n"
                 "Host details are supplied by terminalOS via TERMFETCH_* variables.\n"
                 "Older app versions show session information only.\n"
                 "Git branch detection requires a .git directory in the current directory.\n"
                 "NO_COLOR disables automatic color; --color explicitly enables it.");
            return 0;
        } else { fputs("termfetch: unknown option; use --help\n", stderr); return 2; }
    }
    collect();
    if (json) {
        puts("{");
        for (size_t i = 0; i < count; i++) {
            fputs("  ", stdout); json_string(fields[i].key); fputs(": ", stdout);
            json_string(fields[i].value); puts(i + 1 < count ? "," : "");
        }
        puts("}");
    } else {
        const char *cyan = color ? "\033[1;36m" : "";
        const char *reset = color ? "\033[0m" : "";
        static const char *art[] = {
            "  .------------.", "  |            |", "  |  >_        |",
            "  |            |", "  '------------'", "    terminalOS"
        };
        /* Stack the small logo so phone-width terminals stay readable. */
        if (logo) {
            for (size_t i = 0; i < sizeof(art) / sizeof(art[0]); i++)
                printf("%s%s%s\n", cyan, art[i], reset);
            putchar('\n');
        }
        for (size_t i = 0; i < count; i++)
            printf("%s%s%s: %s\n", cyan, fields[i].key, reset, fields[i].value);
        if (color && logo) {
            putchar('\n');
            for (int i = 0; i < 8; i++) printf("\033[%dm   ", 40 + i);
            printf("%s\n", reset);
        }
    }
    return fflush(stdout) == EOF || ferror(stdout) ? 1 : 0;
}
