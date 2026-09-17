/* Lookup table for data files compiled into a WASI binary. See tools/embed.py. */
#ifndef WASI_EMBED_H
#define WASI_EMBED_H

typedef struct {
  const char *name;            /* basename, e.g. "definitions.units" */
  const unsigned char *data;
  unsigned long size;
} embedded_file;

/* Returns the entry whose basename matches PATH, or NULL. */
const embedded_file *embedded_lookup(const char *path);

#endif
