/* SPDX-License-Identifier: GPL-2.0-or-later */
/* This executable only creates a NEW regular image with O_EXCL. No device nodes. */
#include "ntfs_bridge.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s (errno=%d %s)\n", __LINE__, #x, errno, strerror(errno)); exit(1); } } while (0)
struct image { int fd; unsigned reads, writes, flushes; int fail_flush, fail_writes, fail_reads; };
extern int nk_test_fail_move_after_backup;
extern long long nk_test_recount_free(nk_volume *v);
static long long image_read(void *ctx, void *buf, long long count, long long offset) {
    struct image *im = ctx; im->reads++;
    if (im->fail_reads) { errno = EIO; return -1; }
    return pread(im->fd, buf, (size_t)count, offset);
}
static long long image_write(void *ctx, const void *buf, long long count, long long offset) {
    struct image *im = ctx; im->writes++;
    if (im->fail_writes) { errno = EIO; return -1; }
    return pwrite(im->fd, buf, (size_t)count, offset);
}
static int image_sync(void *ctx) {
    struct image *im = ctx; im->flushes++;
    if (im->fail_flush) { errno = EIO; return -1; }
    return fsync(im->fd);
}
static int count_entry(void *ctx, const nk_dirent *entry) {
    CHECK(entry->name && *entry->name);
    CHECK(!strncmp(entry->name, "Entry-", 6) && strstr(entry->name, ".TxT"));
    (*(unsigned *)ctx)++;
    return 0;
}
struct page_entries { unsigned seen[200]; unsigned total, count, limit; uint64_t cookie; };
static int page_entry(void *ctx, const nk_dirent *entry) {
    struct page_entries *page = ctx;
    int index = -1;
    CHECK(sscanf(entry->name, "Entry-%d.TxT", &index) == 1 && index >= 0 && index < 200);
    CHECK(!page->seen[index] && entry->next_cookie > page->cookie);
    page->seen[index] = 1; page->total++; page->count++; page->cookie = entry->next_cookie;
    return page->count == page->limit;
}
static void verify_pages(nk_volume *v) {
    const unsigned limits[] = {1, 2, 7, 13, 31};
    for (unsigned variant = 0; variant < sizeof(limits) / sizeof(limits[0]); variant++) {
        struct page_entries page = {.limit = limits[variant]};
        for (unsigned iteration = 0; iteration < 201; iteration++) {
            page.count = 0;
            int result = nk_list_from(v, "/many", page.cookie, page_entry, &page);
            if (result) fprintf(stderr, "Pagination failed: limit=%u iteration=%u cookie=%llu total=%u count=%u\n", page.limit, iteration, (unsigned long long)page.cookie, page.total, page.count);
            CHECK(!result);
            if (!page.count) break;
        }
        CHECK(page.total == 200 && page.count == 0);
    }
}
struct expected_names { const char **names; unsigned count, seen; int stop; nk_volume *volume; };
static int exact_entry(void *ctx, const nk_dirent *entry) {
    struct expected_names *expected = ctx;
    CHECK(expected->count < 32);
    unsigned i;
    for (i = 0; i < expected->count; i++)
        if (!strcmp(entry->name, expected->names[i])) break;
    if (i == expected->count) fprintf(stderr, "Unexpected directory spelling: %s\n", entry->name);
    CHECK(i < expected->count && !(expected->seen & (1u << i)));
    expected->seen |= 1u << i;
    /* Case-insensitive lookups must work even inside an enumeration callback. */
    nk_stat st;
    CHECK(!nk_stat_path(expected->volume, "/CASE-PROOF/mIxEd.TxT", &st));
    return expected->stop;
}
static void verify_case_listing(nk_volume *v) {
    /* NTFS-3G's macOS UTF-8 conversion returns decomposed Unicode. */
    const char *names[] = { "MiXeD.txt", "Gru\xcc\x88sse-文件.TXT", "NestedFolder" };
    struct expected_names expected = { names, 3, 0, 0, v };
    CHECK(!nk_list(v, "/CASE-PROOF", exact_entry, &expected));
    CHECK(expected.seen == 7);
    expected.seen = 0; expected.stop = 1;
    CHECK(!nk_list(v, "/case-proof", exact_entry, &expected));
    CHECK(expected.seen && !(expected.seen & (expected.seen - 1)));
    CHECK(nk_list(v, "/case-proof/mixed.txt", exact_entry, &expected) == -1);
    nk_stat st;
    CHECK(!nk_stat_path(v, "/CASE-PROOF/MIXED.TXT", &st));
}
static nk_volume *mount_image(nk_io *io) {
    char error[512] = {0};
    nk_volume *v = nk_mount_io(io, error, sizeof(error));
    if (!v) fprintf(stderr, "%s\n", error);
    CHECK(v);
    return v;
}
static void verify(nk_volume *v, const char *path, const void *expected, size_t length) {
    char *readback = malloc(length ? length : 1);
    CHECK(readback);
    CHECK(nk_read(v, path, 0, length, readback) == (long long)length);
    CHECK(!memcmp(readback, expected, length));
    free(readback);
}

int main(int argc, char **argv) {
    CHECK(argc == 3 || (argc == 4 && !strcmp(argv[3], "--clean"))); /* new image path, mkntfs executable */
    struct image im = { .fd = open(argv[1], O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600) };
    CHECK(im.fd >= 0);
    struct stat st;
    CHECK(!fstat(im.fd, &st) && S_ISREG(st.st_mode) && st.st_nlink == 1);
    const long long capacity = 64LL * 1024 * 1024;
    CHECK(!ftruncate(im.fd, capacity));
    pid_t child = fork();
    CHECK(child >= 0);
    if (!child) {
        execl(argv[2], argv[2], "-F", "-Q", "-L", "OC-NTFS-TEST", argv[1], (char *)NULL);
        _exit(127);
    }
    int status = 0;
    CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    nk_io io = { .ctx = &im, .pread = image_read, .pwrite = image_write,
                 .sync = image_sync, .size = capacity, .readonly = 0 };
    nk_volume *v = mount_image(&io);
    long long stat_total, stat_free, stat_after; int stat_cluster;
    CHECK(!nk_statvfs(v, &stat_total, &stat_free, &stat_cluster) && stat_total > 0 && stat_free > 0 && stat_cluster > 0);
    unsigned stat_reads = im.reads;
    for (int i = 0; i < 100; i++) CHECK(!nk_statvfs(v, NULL, NULL, NULL));
    CHECK(im.reads == stat_reads);
    CHECK(!nk_create(v, "/", "statfs-proof.bin"));
    unsigned char *stat_payload = malloc(1024 * 1024);
    CHECK(stat_payload); memset(stat_payload, 0x35, 1024 * 1024);
    CHECK(nk_write(v, "/statfs-proof.bin", 0, 1024 * 1024, stat_payload) == 1024 * 1024);
    free(stat_payload);
    CHECK(!nk_statvfs(v, NULL, &stat_after, NULL) && stat_after <= stat_free - 1024 * 1024);
    CHECK(stat_after == nk_test_recount_free(v));
    CHECK(!nk_delete(v, "/statfs-proof.bin"));
    CHECK(!nk_statvfs(v, NULL, &stat_after, NULL) && stat_after == nk_test_recount_free(v));
    puts("PASS statfs: repeated queries avoid bitmap reads; allocation/delete keep cached free space accurate");
    CHECK(!nk_create(v, "/", "hello.txt"));
    CHECK(nk_write(v, "/hello.txt", 0, 13, "Hello NTFS!\r\n") == 13);
    verify(v, "/hello.txt", "Hello NTFS!\r\n", 13);
    puts("PASS create, write, read small file");

    CHECK(!nk_create(v, "/", "timestamps.txt"));
    nk_times dates = { .valid = NK_TIME_ACCESS | NK_TIME_MODIFY | NK_TIME_CHANGE | NK_TIME_BIRTH,
        .access = {1600000000, 123456789}, .modify = {1500000000, 987654321},
        .change = {1700000000, 765432100}, .birth = {1234567890, 234567890} };
    CHECK(!nk_set_times(v, "/timestamps.txt", &dates));
    nk_stat dated;
    CHECK(!nk_stat_path(v, "/timestamps.txt", &dated));
    CHECK(dated.atime == 1600000000 && dated.atime_nsec == 123456700);
    CHECK(dated.mtime == 1500000000 && dated.mtime_nsec == 987654300);
    CHECK(dated.ctime == 1700000000 && dated.ctime_nsec == 765432100);
    CHECK(dated.btime == 1234567890 && dated.btime_nsec == 234567800);
    CHECK(!nk_create(v, "/", "pre-1970.txt"));
    nk_times historical = {.valid = NK_TIME_BIRTH, .birth = {-1, 234567890}};
    CHECK(!nk_set_times(v, "/pre-1970.txt", &historical));
    CHECK(!nk_stat_path(v, "/pre-1970.txt", &dated));
    CHECK(dated.btime == -1 && dated.btime_nsec == 234567800);
    dates.valid = NK_TIME_MODIFY; dates.modify = (nk_timestamp){1500000001, 456789123};
    CHECK(!nk_set_times(v, "/timestamps.txt", &dates));
    CHECK(!nk_stat_path(v, "/timestamps.txt", &dated));
    CHECK(dated.atime == 1600000000 && dated.atime_nsec == 123456700);
    CHECK(dated.btime == 1234567890 && dated.btime_nsec == 234567800);
    CHECK(dated.mtime == 1500000001 && dated.mtime_nsec == 456789100);
    CHECK(dated.ctime > 1700000000);
    unsigned time_writes = im.writes;
    dates.valid = 1u << 31;
    CHECK(nk_set_times(v, "/timestamps.txt", &dates) == -1 && errno == EINVAL);
    dates.valid = NK_TIME_MODIFY; dates.modify.nanoseconds = -1;
    CHECK(nk_set_times(v, "/timestamps.txt", &dates) == -1 && errno == EINVAL);
    dates.modify.nanoseconds = 1000000000;
    CHECK(nk_set_times(v, "/timestamps.txt", &dates) == -1 && errno == EINVAL);
    dates.modify = (nk_timestamp){INT64_MAX, 0};
    CHECK(nk_set_times(v, "/timestamps.txt", &dates) == -1 && errno == EOVERFLOW);
    dates.modify = (nk_timestamp){-11644473601LL, 0};
    CHECK(nk_set_times(v, "/timestamps.txt", &dates) == -1 && errno == EOVERFLOW);
    dates.modify = (nk_timestamp){1500000001, 456789100};
    CHECK(nk_set_times(v, "/$MFT", &dates) == -1 && errno == EPERM);
    CHECK(nk_set_times(v, "/timestamps.txt", NULL) == -1 && errno == EINVAL);
    CHECK(nk_set_times(NULL, "/timestamps.txt", &dates) == -1 && errno == EINVAL);
    CHECK(im.writes == time_writes);
    puts("PASS timestamps: 100ns precision, pre-1970 fractions, partial updates, overflow/invalid/system-file refusal without writes");
    im.fail_writes = 1; dates.modify.seconds++;
    CHECK(nk_set_times(v, "/timestamps.txt", &dates) == -1);
    im.fail_writes = 0; dates.modify.seconds--;
    CHECK(!nk_set_times(v, "/timestamps.txt", &dates));
    puts("PASS timestamp metadata write failure propagates; subsequent explicit update succeeds");

    CHECK(!nk_mkdir(v, "/", "Grüsse-文件"));
    CHECK(!nk_create(v, "/Grüsse-文件", "données.txt"));
    CHECK(nk_write(v, "/Grüsse-文件/données.txt", 0, 7, "Unicode") == 7);
    verify(v, "/Grüsse-文件/données.txt", "Unicode", 7);
    CHECK(nk_create(v, "/", "HELLO.TXT") == -1 && errno == EEXIST);
    CHECK(nk_create(v, "/", "../escape") == -1);
    CHECK(nk_create(v, "/", "bad:name") == -1);
    puts("PASS Unicode, case-insensitive collision, invalid names");

    CHECK(!nk_mkdir(v, "/", "case-proof"));
    CHECK(!nk_create(v, "/case-proof", "MiXeD.txt"));
    CHECK(!nk_create(v, "/case-proof", "Grüsse-文件.TXT"));
    CHECK(!nk_mkdir(v, "/case-proof", "NestedFolder"));
    verify_case_listing(v);
    CHECK(nk_create(v, "/CASE-PROOF", "MIXED.TXT") == -1 && errno == EEXIST);
    puts("PASS exact mixed-case/Unicode listing, early stop, error path, callback lookup and collision protection");

    const size_t large_size = 2 * 1024 * 1024 + 37;
    unsigned char *large = malloc(large_size);
    CHECK(large);
    for (size_t i = 0; i < large_size; i++) large[i] = (unsigned char)(i * 17);
    CHECK(!nk_create(v, "/", "large.bin"));
    CHECK(nk_write(v, "/large.bin", 0, large_size, large) == (long long)large_size);
    verify(v, "/large.bin", large, large_size);
    CHECK(!nk_truncate(v, "/large.bin", 500));
    CHECK(!nk_truncate(v, "/large.bin", 8192));
    unsigned char extended[8192] = {0};
    memcpy(extended, large, 500);
    verify(v, "/large.bin", extended, sizeof(extended));
    puts("PASS nonresident data, shrink, grow with zero-filled extension");

    CHECK(!nk_rename(v, "/Grüsse-文件", "/", "Moved"));
    verify(v, "/Moved/données.txt", "Unicode", 7);
    CHECK(nk_delete(v, "/Moved") == -1 && errno == ENOTEMPTY);
    CHECK(nk_rename(v, "/Moved", "/Moved", "cycle") == -1);
    CHECK(nk_rename(v, "/hello.txt", "/", "large.bin") == -1 && errno == EEXIST);
    verify(v, "/hello.txt", "Hello NTFS!\r\n", 13);
    verify(v, "/large.bin", extended, sizeof(extended));
    CHECK(!nk_create(v, "/", "delete-me"));
    CHECK(!nk_delete(v, "/delete-me"));
    puts("PASS directory rename, delete, nonempty/cycle/collision protection");

    CHECK(!nk_create(v, "/", "replacement.txt"));
    CHECK(nk_write(v, "/replacement.txt", 0, 3, "new") == 3);
    char recovery[4096];
    nk_test_fail_move_after_backup = 1;
    CHECK(nk_move(v, "/replacement.txt", "/", "hello.txt", 1, recovery, sizeof(recovery)) == -1);
    CHECK(errno == ENOSPC && !recovery[0]);
    verify(v, "/hello.txt", "Hello NTFS!\r\n", 13);
    verify(v, "/replacement.txt", "new", 3);
    puts("PASS failed replacement restores old destination and preserves source");
    CHECK(!nk_move(v, "/replacement.txt", "/", "hello.txt", 1, recovery, sizeof(recovery)));
    verify(v, "/hello.txt", "new", 3);
    CHECK(!nk_move(v, "/hello.txt", "/", "HELLO.TXT", 0, recovery, sizeof(recovery)));
    verify(v, "/HELLO.TXT", "new", 3);
    CHECK(nk_write(v, "/HELLO.TXT", 0, 13, "Hello NTFS!\r\n") == 13);
    puts("PASS replace existing file and case-only rename");

    CHECK(!nk_create(v, "/", "fill.bin"));
    long long filled = 0;
    int reached_full = 0;
    while (filled < capacity * 2) {
        long long written = nk_write(v, "/fill.bin", filled, large_size, large);
        if (written != (long long)large_size) { reached_full = 1; break; }
        filled += written;
    }
    CHECK(reached_full);
    verify(v, "/HELLO.TXT", "Hello NTFS!\r\n", 13);
    CHECK(!nk_delete(v, "/fill.bin"));
    CHECK(!nk_create(v, "/", "after-full.txt"));
    CHECK(nk_write(v, "/after-full.txt", 0, 2, "OK") == 2);
    puts("PASS disk full, existing content intact, free space reusable");

    im.fail_flush = 1;
    CHECK(nk_sync(v) == -1);
    im.fail_flush = 0;
    CHECK(!nk_sync(v));
    puts("PASS flush failure is reported, subsequent flush succeeds");

    // A failed block write must not become a positive byte count in the facade.
    im.fail_writes = 1;
    CHECK(nk_write(v, "/HELLO.TXT", 0, 13, "XXXXXXXXXXXXX") == -1);
    im.fail_writes = 0;
    // An I/O failure is not an atomic-write promise: explicitly restore fixture.
    CHECK(nk_write(v, "/HELLO.TXT", 0, 13, "Hello NTFS!\r\n") == 13);
    puts("PASS device write failure propagates to caller");

    // Force an index root to grow into allocation-backed directory index blocks.
    CHECK(!nk_mkdir(v, "/", "many"));
    for (int i = 0; i < 200; i++) {
        char name[32]; snprintf(name, sizeof(name), "Entry-%03d.TxT", i);
        CHECK(!nk_create(v, "/many", name));
    }
    unsigned count = 0;
    CHECK(!nk_list(v, "/many", count_entry, &count) && count == 200);
    verify_pages(v);
    struct page_entries page = {.limit = 7};
    unsigned cookie_reads = im.reads;
    CHECK(nk_list_from(v, "/many", UINT64_MAX, page_entry, &page) == -1 && errno == EINVAL);
    CHECK(im.reads == cookie_reads);
    unsigned before_bad_read = im.writes;
    im.fail_reads = 1;
    CHECK(nk_list_from(v, "/many", 0, page_entry, &page) == -1 && errno == EIO);
    im.fail_reads = 0;
    CHECK(im.writes == before_bad_read);
    verify_pages(v);
    puts("PASS directory pagination: native cookies, 1/2/7/13/31-entry pages, 200 unique names, EOF, invalid-cookie and read-error refusal");
    CHECK(!nk_sync(v) && im.flushes > 0);
    CHECK(!nk_umount(v));
    puts("PASS directory index growth (200 files), flush and close");

    io.readonly = 1;
    unsigned before = im.writes;
    v = mount_image(&io);
    verify(v, "/hello.txt", "Hello NTFS!\r\n", 13);
    verify_case_listing(v);
    verify(v, "/Moved/données.txt", "Unicode", 7);
    verify(v, "/large.bin", extended, sizeof(extended));
    count = 0;
    CHECK(!nk_list(v, "/many", count_entry, &count) && count == 200);
    verify_pages(v);
    CHECK(nk_write(v, "/hello.txt", 0, 1, "X") == -1 && errno == EROFS);
    CHECK(nk_create(v, "/", "forbidden") == -1 && errno == EROFS);
    CHECK(nk_delete(v, "/hello.txt") == -1 && errno == EROFS);
    CHECK(!nk_stat_path(v, "/timestamps.txt", &dated));
    CHECK(dated.mtime == 1500000001 && dated.mtime_nsec == 456789100);
    CHECK(dated.btime == 1234567890 && dated.btime_nsec == 234567800);
    CHECK(!nk_stat_path(v, "/pre-1970.txt", &dated));
    CHECK(dated.btime == -1 && dated.btime_nsec == 234567800);
    CHECK(nk_set_times(v, "/timestamps.txt", &dates) == -1 && errno == EROFS);
    CHECK(!nk_umount(v));
    CHECK(before == im.writes);
    puts("PASS persistence after reopen, readonly causes zero writes");

    io.readonly = 0;
    v = mount_image(&io);
    if (argc == 4) {
        CHECK(!nk_umount(v));
        CHECK(!close(im.fd));
        free(large);
        printf("CLEAN_IMAGE %s\n", argv[1]);
        return 0;
    }
    CHECK(!nk_create(v, "/", "hiberfil.sys"));
    unsigned char hiber[4096] = {'h','i','b','r'};
    CHECK(nk_write(v, "/hiberfil.sys", 0, sizeof(hiber), hiber) == sizeof(hiber));
    CHECK(!nk_umount(v));
    before = im.writes;
    char error[512] = {0};
    CHECK(nk_mount_io(&io, error, sizeof(error)) == NULL);
    CHECK(before == im.writes);
    puts("PASS hibernation blocks write mount before any device write");
    // Keep this fixture: independent OS/Windows verification can read it.
    CHECK(!close(im.fd));
    free(large);
    printf("IMAGE %s\n", argv[1]);
    return 0;
}
