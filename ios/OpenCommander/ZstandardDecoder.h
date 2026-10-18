#ifndef OPENCOMMANDER_ZSTANDARD_DECODER_H
#define OPENCOMMANDER_ZSTANDARD_DECODER_H
#include <stddef.h>

/* Bounded streaming decoder; no filesystem, subprocess or network access. */
void *oc_zstd_create(void);
int oc_zstd_step(void *context, const void *source, size_t source_size,
                 size_t *consumed, void *destination, size_t destination_size,
                 size_t *produced);
void oc_zstd_free(void *context);
#endif
