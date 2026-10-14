/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Private fixture construction uses engine internals; never compiled into the app.
 * Every target is a newly created regular image, never a device or existing file. */
#include "../bridge/ntfs_bridge.c"
#include <ntfs-3g/mst.h>
#include <copyfile.h>
#include <sys/wait.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s (errno=%d)\n", __LINE__, #x, errno); exit(1); } } while (0)
#define CAPACITY (64LL * 1024 * 1024)
struct image { int fd; unsigned writes, flushes; int fail_reads; };
static long long read_image(void *ctx, void *buf, long long count, long long offset) {
    struct image *im = ctx;
    if (im->fail_reads) { errno = EIO; return -1; }
    return pread(im->fd, buf, (size_t)count, offset);
}
static long long write_image(void *ctx, const void *buf, long long count, long long offset) {
    struct image *im = ctx; im->writes++;
    return pwrite(im->fd, buf, (size_t)count, offset);
}
static int sync_image(void *ctx) {
    struct image *im = ctx; im->flushes++;
    return fsync(im->fd);
}
static nk_io image_io(struct image *im) {
    return (nk_io){.ctx = im, .pread = read_image, .pwrite = write_image,
        .sync = sync_image, .size = CAPACITY, .readonly = 0};
}
static nk_volume *open_image(nk_io *io) {
    char error[512];
    nk_volume *v = nk_mount_io(io, error, sizeof(error));
    if (!v) fprintf(stderr, "%s\n", error);
    CHECK(v); return v;
}
static void clone_image(const char *base, const char *directory, const char *name, struct image *im) {
    char path[4096];
    CHECK(snprintf(path, sizeof(path), "%s/%s.ntfs", directory, name) < (int)sizeof(path));
    CHECK(!copyfile(base, path, NULL, COPYFILE_DATA | COPYFILE_EXCL | COPYFILE_NOFOLLOW));
    *im = (struct image){.fd = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)};
    struct stat info;
    CHECK(im->fd >= 0 && !fstat(im->fd, &info) && S_ISREG(info.st_mode) && info.st_nlink == 1 && info.st_size == CAPACITY);
}
static void journal_fixture(nk_volume *v, int mode) {
    ntfs_inode *inode = ntfs_inode_open(v->vol, FILE_LogFile);
    CHECK(inode);
    ntfs_attr *attribute = ntfs_attr_open(inode, AT_DATA, AT_UNNAMED, 0);
    CHECK(attribute && attribute->data_size >= 4096 * 50);
    unsigned char page[4096] = {0};
    if (mode != 3) {
        RESTART_PAGE_HEADER *header = (RESTART_PAGE_HEADER *)page;
        header->magic = magic_RSTR;
        header->usa_ofs = cpu_to_le16(30);
        header->usa_count = cpu_to_le16(9);
        header->system_page_size = cpu_to_le32(4096);
        header->log_page_size = cpu_to_le32(4096);
        header->restart_area_offset = cpu_to_le16(48);
        header->major_ver = cpu_to_sle16(mode == 2 ? 2 : 1);
        header->minor_ver = cpu_to_sle16(mode == 2 ? 0 : 1);
        RESTART_AREA *area = (RESTART_AREA *)(page + 48);
        area->log_clients = cpu_to_le16(1);
        area->client_free_list = LOGFILE_NO_CLIENT;
        area->client_in_use_list = cpu_to_le16(0);
        area->flags = mode == 1 || mode == 4 ? 0 : RESTART_VOLUME_IS_CLEAN;
        unsigned bits = 0;
        for (uint64_t size = attribute->data_size; size; size >>= 1) bits++;
        area->seq_number_bits = cpu_to_le32(67 - bits);
        area->client_array_offset = cpu_to_le16(64);
        area->restart_area_length = cpu_to_le16(64 + sizeof(LOG_CLIENT_RECORD));
        area->file_size = cpu_to_sle64(attribute->data_size);
        area->log_record_header_length = cpu_to_le16(48);
        area->log_page_data_offset = cpu_to_le16(64);
        LOG_CLIENT_RECORD *client = (LOG_CLIENT_RECORD *)((unsigned char *)area + 64);
        client->prev_client = LOGFILE_NO_CLIENT;
        client->next_client = LOGFILE_NO_CLIENT;
        if (mode == 4) {
            uint64_t checkpoint = (1ULL << (bits - 3)) + ((4 * 4096 + 3984) >> 3);
            area->current_lsn = cpu_to_sle64(checkpoint);
            client->oldest_lsn = cpu_to_sle64(checkpoint);
            client->client_restart_lsn = cpu_to_sle64(checkpoint);
        }
        CHECK(!ntfs_mst_pre_write_fixup((NTFS_RECORD *)page, sizeof(page)));
    }
    CHECK(ntfs_attr_pwrite(attribute, 0, sizeof(page), page) == sizeof(page));
    CHECK(ntfs_attr_pwrite(attribute, sizeof(page), sizeof(page), page) == sizeof(page));
    if (mode == 4) {
        // Full valid record pages, with a checkpoint at the last no-op record.
        // There is no user-data update to redo; this exercises legitimate
        // checkpoint completion, not replay of a committed data transaction.
        unsigned bits = 0;
        for (uint64_t size = attribute->data_size; size; size >>= 1) bits++;
        long long blocks[] = {2, 3, 4, attribute->data_size / 4096 - 1};
        for (unsigned index = 0; index < sizeof(blocks) / sizeof(blocks[0]); index++) {
            memset(page, 0, sizeof(page));
            RECORD_PAGE_HEADER *header = (RECORD_PAGE_HEADER *)page;
            header->magic = magic_RCRD;
            header->usa_ofs = cpu_to_le16(40);
            header->usa_count = cpu_to_le16(9);
            header->flags = cpu_to_le32(1);
            header->page_count = cpu_to_le16(1);
            header->page_position = cpu_to_le16(1);
            header->next_record_offset = cpu_to_le16(4096);
            uint64_t block = blocks[index] < 4 ? 4 : (uint64_t)blocks[index];
            uint64_t sequence = blocks[index] == blocks[3] ? 0 : 1ULL << (bits - 3);
            uint64_t latest = sequence + ((block * 4096 + 3984) >> 3);
            header->copy.last_lsn = cpu_to_sle64(latest);
            if (blocks[index] < 4) header->copy.file_offset = cpu_to_sle64(4 * 4096);
            header->last_end_lsn = cpu_to_sle64(latest);
            for (int offset = 64; offset <= 3984; offset += 112) {
                LOG_RECORD *record = (LOG_RECORD *)(page + offset);
                record->this_lsn = cpu_to_sle64(sequence + ((block * 4096 + offset) >> 3));
                record->client_data_length = cpu_to_le32(64);
                record->record_type = LOG_STANDARD;
                record->transaction_id = cpu_to_le32(1);
            }
            CHECK(!ntfs_mst_pre_write_fixup((NTFS_RECORD *)page, sizeof(page)));
            CHECK(ntfs_attr_pwrite(attribute, blocks[index] * 4096, sizeof(page), page) == sizeof(page));
        }
    }
    ntfs_attr_close(attribute);
    CHECK(!ntfs_inode_close(inode));
}
static void blocked_unchanged(struct image *im, uint32_t expected, int journal) {
    unsigned char *before = malloc(CAPACITY), *after = malloc(CAPACITY);
    CHECK(before && after && pread(im->fd, before, CAPACITY, 0) == CAPACITY);
    unsigned writes = im->writes, flushes = im->flushes;
    nk_io io = image_io(im);
    nk_safety_report report;
    char error[512];
    CHECK(!nk_inspect_io(&io, &report, error, sizeof(error)));
    CHECK(report.blockers == expected && report.journal_state == journal);
    CHECK(*error && !nk_mount_io(&io, error, sizeof(error)) && errno == EROFS);
    CHECK(im->writes == writes && im->flushes == flushes);
    io.readonly = 1;
    nk_volume *v = open_image(&io);
    char payload[4];
    CHECK(nk_read(v, "/proof.txt", 0, sizeof(payload), payload) == sizeof(payload) && !memcmp(payload, "SAFE", 4));
    CHECK(nk_create(v, "/", "forbidden.txt") == -1 && errno == EROFS);
    CHECK(!nk_umount(v));
    CHECK(im->writes == writes && im->flushes == flushes);
    CHECK(pread(im->fd, after, CAPACITY, 0) == CAPACITY && !memcmp(before, after, CAPACITY));
    free(before); free(after);
}

static void continuation_fixture(nk_volume *v, int invalid_offset) {
    journal_fixture(v, 4);
    ntfs_inode *inode = ntfs_inode_open(v->vol, FILE_LogFile);
    CHECK(inode);
    ntfs_attr *attribute = ntfs_attr_open(inode, AT_DATA, AT_UNNAMED, 0);
    CHECK(attribute);
    unsigned bits = 0;
    for (uint64_t size = attribute->data_size; size; size >>= 1) bits++;
    uint64_t sequence = 1ULL << (bits - 3);
    uint64_t latest = sequence + ((6 * 4096 + 2560) >> 3);
    unsigned char bytes[4096];
    for (int index = 0; index < 2; index++) {
        CHECK(ntfs_attr_pread(attribute, index * 4096, sizeof(bytes), bytes) == sizeof(bytes));
        CHECK(!ntfs_mst_post_read_fixup((NTFS_RECORD *)bytes, sizeof(bytes)));
        RESTART_AREA *area = (RESTART_AREA *)(bytes + 48);
        LOG_CLIENT_RECORD *client = (LOG_CLIENT_RECORD *)((unsigned char *)area + 64);
        area->current_lsn = cpu_to_sle64(latest);
        client->oldest_lsn = client->client_restart_lsn = cpu_to_sle64(latest);
        CHECK(!ntfs_mst_pre_write_fixup((NTFS_RECORD *)bytes, sizeof(bytes)));
        CHECK(ntfs_attr_pwrite(attribute, index * 4096, sizeof(bytes), bytes) == sizeof(bytes));
    }
    for (int index = 2; index <= 6; index++) {
        memset(bytes, 0, sizeof(bytes));
        RECORD_PAGE_HEADER *header = (RECORD_PAGE_HEADER *)bytes;
        header->magic = magic_RCRD;
        header->usa_ofs = cpu_to_le16(40); header->usa_count = cpu_to_le16(9);
        header->flags = cpu_to_le32(index != 5);
        header->page_count = cpu_to_le16(1); header->page_position = cpu_to_le16(1);
        if (index < 4 || index == 6) {
            header->copy.last_lsn = header->last_end_lsn = cpu_to_sle64(latest);
            if (index < 4) header->copy.file_offset = cpu_to_sle64(6 * 4096 + invalid_offset);
            header->next_record_offset = cpu_to_le16(2672);
            LOG_RECORD *record = (LOG_RECORD *)(bytes + 2560);
            record->this_lsn = cpu_to_sle64(latest);
            record->client_data_length = cpu_to_le32(64);
            record->record_type = LOG_STANDARD; record->transaction_id = cpu_to_le32(1);
        } else if (index == 4) {
            header->copy.last_lsn = header->last_end_lsn = cpu_to_sle64(sequence + ((4 * 4096 + 64) >> 3));
            header->next_record_offset = cpu_to_le16(3984);
            for (int offset = 64; offset <= 3984; offset += 112) {
                LOG_RECORD *record = (LOG_RECORD *)(bytes + offset);
                record->this_lsn = cpu_to_sle64(sequence + ((4 * 4096 + offset) >> 3));
                /* Last record spans the end of 4, all of 5, and part of 6. */
                record->client_data_length = cpu_to_le32(offset == 3984 ? 6592 : 64);
                record->record_type = LOG_STANDARD; record->transaction_id = cpu_to_le32(1);
            }
        }
        CHECK(!ntfs_mst_pre_write_fixup((NTFS_RECORD *)bytes, sizeof(bytes)));
        CHECK(ntfs_attr_pwrite(attribute, index * 4096, sizeof(bytes), bytes) == sizeof(bytes));
    }
    ntfs_attr_close(attribute); CHECK(!ntfs_inode_close(inode));
}

int main(int argc, char **argv) {
    CHECK(argc == 3); /* private new fixture directory, pinned mkntfs */
    char base[4096];
    CHECK(snprintf(base, sizeof(base), "%s/base.ntfs", argv[1]) < (int)sizeof(base));
    struct image im = {.fd = open(base, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600)};
    CHECK(im.fd >= 0 && !ftruncate(im.fd, CAPACITY));
    struct stat info;
    CHECK(!fstat(im.fd, &info) && S_ISREG(info.st_mode) && info.st_nlink == 1);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) { execl(argv[2], argv[2], "-F", "-Q", "-L", "OC-SAFETY", base, (char *)NULL); _exit(127); }
    int status;
    CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status));
    nk_io io = image_io(&im);
    nk_volume *v = open_image(&io);
    CHECK(!nk_create(v, "/", "proof.txt") && nk_write(v, "/proof.txt", 0, 4, "SAFE") == 4 && !nk_umount(v));
    unsigned writes = im.writes, flushes = im.flushes;
    nk_safety_report report;
    char error[512];
    CHECK(!nk_inspect_io(&io, &report, error, sizeof(error)) && !report.blockers && !*error && report.journal_state == NK_JOURNAL_CLEAN);
    CHECK(im.writes == writes && im.flushes == flushes);
    nk_io only_reads = io; only_reads.pwrite = NULL; only_reads.sync = NULL;
    CHECK(!nk_inspect_io(&only_reads, &report, NULL, 0) && !report.blockers);
    CHECK(nk_inspect_io(NULL, &report, error, sizeof(error)) == -1 && report.blockers == NK_BLOCK_IO);
    CHECK(nk_inspect_io(&io, NULL, error, sizeof(error)) == -1 && errno == EINVAL);
    CHECK(!close(im.fd));
    puts("PASS clean inspection, read-only callback isolation, invalid API arguments");

    clone_image(base, argv[1], "dirty", &im); io = image_io(&im); v = open_image(&io);
    CHECK(!ntfs_volume_write_flags(v->vol, VOLUME_IS_DIRTY) && !nk_umount(v));
    blocked_unchanged(&im, NK_BLOCK_DIRTY, NK_JOURNAL_CLEAN); CHECK(!close(im.fd));
    puts("PASS dirty flag: exact diagnosis, readable fallback, byte-identical image, zero writes/flushes");

    const char *names[] = {"checkpoint-clean", "unclean", "windows-cache", "corrupt"};
    for (int mode = 0; mode < 4; mode++) {
        clone_image(base, argv[1], names[mode], &im); io = image_io(&im); v = open_image(&io);
        journal_fixture(v, mode); CHECK(!nk_umount(v));
        if (!mode) {
            writes = im.writes; flushes = im.flushes;
            CHECK(!nk_inspect_io(&io, &report, error, sizeof(error)) && !report.blockers && report.journal_state == NK_JOURNAL_CLEAN);
            CHECK(im.writes == writes && im.flushes == flushes);
            v = open_image(&io); CHECK(!nk_umount(v));
        } else {
            blocked_unchanged(&im, mode == 1 ? NK_BLOCK_REPLAY_REQUIRED : mode == 2 ? NK_BLOCK_WINDOWS_CACHE : NK_BLOCK_JOURNAL_INVALID,
                mode == 1 ? NK_JOURNAL_REPLAY_REQUIRED : mode == 2 ? NK_JOURNAL_WINDOWS_CACHE : NK_JOURNAL_INVALID);
        }
        CHECK(!close(im.fd));
        printf("PASS %s journal: expected state, no forced recovery\n", names[mode]);
    }
    clone_image(base, argv[1], "checkpoint-recoverable", &im); io = image_io(&im); v = open_image(&io);
    journal_fixture(v, 4); CHECK(!nk_umount(v));
    blocked_unchanged(&im, NK_BLOCK_REPLAY_REQUIRED, NK_JOURNAL_REPLAY_REQUIRED); CHECK(!close(im.fd));
    puts("PASS recoverable checkpoint fixture remains source-read-only until sandboxed replay");
    const char *continuations[] = {"checkpoint-continuation", "continuation-invalid"};
    for (int invalid = 0; invalid < 2; invalid++) {
        clone_image(base, argv[1], continuations[invalid], &im); io = image_io(&im); v = open_image(&io);
        continuation_fixture(v, invalid); CHECK(!nk_umount(v));
        blocked_unchanged(&im, NK_BLOCK_REPLAY_REQUIRED, NK_JOURNAL_REPLAY_REQUIRED); CHECK(!close(im.fd));
    }
    puts("PASS initial multi-page continuation and invalid tail offset remain unchanged before replay");
    clone_image(base, argv[1], "hibernated", &im); io = image_io(&im); v = open_image(&io);
    unsigned char hiber[4096] = {'h', 'i', 'b', 'r'};
    CHECK(!nk_create(v, "/", "hiberfil.sys") && nk_write(v, "/hiberfil.sys", 0, sizeof(hiber), hiber) == sizeof(hiber));
    CHECK(!nk_umount(v));
    blocked_unchanged(&im, NK_BLOCK_HIBERNATED, NK_JOURNAL_CLEAN); CHECK(!close(im.fd));
    puts("PASS hibernation: exact diagnosis, original bytes intact");
    clone_image(base, argv[1], "unreadable", &im); io = image_io(&im); im.fail_reads = 1;
    CHECK(nk_inspect_io(&io, &report, error, sizeof(error)) == -1 && report.blockers & NK_BLOCK_IO);
    CHECK(!nk_mount_io(&io, error, sizeof(error)) && !im.writes && !im.flushes);
    CHECK(!close(im.fd));
    puts("PASS unreadable metadata: refused before any device write");
    printf("RETAINED_FIXTURES %s\n", argv[1]);
    return 0;
}
