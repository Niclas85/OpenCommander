#include "ZstandardDecoder.h"
#define ZSTDLIB_VISIBILITY __attribute__((visibility("hidden")))
#include "../Vendor/Zstandard/zstddeclib.c"

void *oc_zstd_create(void) {
    ZSTD_DCtx *context = ZSTD_createDCtx();
    /* Reject frames requiring more than 64 MiB of history. */
    if (context && ZSTD_isError(ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, 26))) {
        ZSTD_freeDCtx(context);
        return NULL;
    }
    return context;
}

int oc_zstd_step(void *context, const void *source, size_t source_size,
                 size_t *consumed, void *destination, size_t destination_size,
                 size_t *produced) {
    ZSTD_inBuffer input = {source, source_size, 0};
    ZSTD_outBuffer output = {destination, destination_size, 0};
    size_t result = ZSTD_decompressStream(context, &output, &input);
    *consumed = input.pos;
    *produced = output.pos;
    return ZSTD_isError(result) ? -1 : result == 0 ? 0 : 1;
}

void oc_zstd_free(void *context) { ZSTD_freeDCtx(context); }
