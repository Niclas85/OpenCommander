/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Exercise the actual patched parser, including under address sanitization. */
#define main nk_unused_recovery_main
#include "ntfsrecover.c"
#undef main
#include <assert.h>

static struct BUFFER *page(unsigned number) {
    struct BUFFER *buffer = calloc(1, sizeof(*buffer) + 4096);
    assert(buffer);
    buffer->num = buffer->rnum = number;
    buffer->size = 4096; buffer->headsz = 64;
    buffer->block.record.magic = magic_RCRD;
    return buffer;
}
int main(void) {
    blocksz = 4096; blockbits = 12; log_major = 1;
    logfilesz = 64 * 1024 * 1024; opts = 1;
    struct BUFFER *current = page(3), *previous = page(4);
    current->block.record.copy.file_offset = cpu_to_sle64(6 * 4096);
    current->block.record.next_record_offset = cpu_to_le16(2720);
    previous->block.record.next_record_offset = cpu_to_le16(3984);
    LOG_RECORD *start = (LOG_RECORD *)(previous->block.data + 3984);
    start->client_data_length = cpu_to_le32(6592); /* 6640 bytes over 3 pages */
    LOG_RECORD *checkpoint = (LOG_RECORD *)(current->block.data + 2560);
    checkpoint->record_type = LOG_CHECKPOINT;
    checkpoint->client_data_length = cpu_to_le32(112);
    assert(initial_skipped(current, previous) == 1);
    /* Old code used 0 here and dereferenced offset 6592, outside a 4096 page. */
    assert(firstrecord(0, current, previous) == 6592);
    assert(firstrecord(initial_skipped(current, previous), current, previous) == 2560);
    current->num = 6;
    assert(initial_skipped(current, previous) == 1);
    previous->num = 5;
    assert(initial_skipped(current, previous) == 0);
    current->num = 4; previous->num = (logfilesz >> blockbits) - 1;
    assert(initial_skipped(current, previous) == 0);
    current->num = 3;
    current->block.record.copy.file_offset = cpu_to_sle64(6 * 4096 + 1);
    assert(initial_skipped(current, previous) == -1);
    current->block.record.copy.file_offset = cpu_to_sle64(logfilesz);
    assert(initial_skipped(current, previous) == -1);
    current->num = 6; previous->num = 6;
    assert(initial_skipped(current, previous) == -1);
    log_major = 2; current->num = 36; previous->num = 34;
    assert(initial_skipped(current, previous) == 1);
    previous->num = 33;
    assert(initial_skipped(current, previous) == -1);
    assert(initial_skipped(current, NULL) == 0);
    free(current); free(previous);
    puts("PASS parser: initial multi-page continuations, tail-copy logical offset, wraparound, invalid geometry, page bounds");
    return 0;
}
