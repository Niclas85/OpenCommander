/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Laboratory recovery sandbox. The backing descriptor is ALWAYS O_RDONLY.
 * Upstream repair writes go only to bounded, disposable shared-memory pages.
 * The default binary has no apply operation. Only the separately compiled
 * opt-in checkpoint laboratory tool includes the narrow two-page writer. */
#include "../bridge/ntfs_bridge.c"
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/disk.h>
#include <sys/ioctl.h>
#include <signal.h>

#define PAGE_BYTES 4096
#define MAX_PAGES 4096
#define VIRTUAL_NAME "/__opencommander_virtual_recovery__"
struct page { long long offset; unsigned char original[PAGE_BYTES], bytes[PAGE_BYTES]; };
struct overlay { unsigned count, limit, failed, writes; struct page pages[MAX_PAGES]; };
struct backing { int fd, sector; long long size; struct overlay *overlay; };
static struct backing *active;
extern int nk_overlay_recovery_main(int argc, char **argv);

static long long backing_read(struct backing *backing, void *buffer, long long count, long long offset) {
    if (offset < 0 || count < 0 || offset > backing->size || count > backing->size - offset) {
        backing->overlay->failed = 1; return -1;
    }
    unsigned char *target = buffer;
    for (long long done = 0; done < count;) {
        long long cursor = offset + done, start = cursor - cursor % backing->sector;
        size_t prefix = (size_t)(cursor - start);
        long long wanted = count - done;
        if (wanted > 1024 * 1024 - (long long)prefix) wanted = 1024 * 1024 - (long long)prefix;
        size_t transfer = (prefix + (size_t)wanted + backing->sector - 1) / backing->sector * backing->sector;
        if ((long long)transfer > backing->size - start) { backing->overlay->failed = 1; return -1; }
        void *scratch = malloc(transfer);
        if (!scratch) { backing->overlay->failed = 1; return -1; }
        ssize_t n;
        do { n = pread(backing->fd, scratch, transfer, start); } while (n < 0 && errno == EINTR);
        if (n != (ssize_t)transfer) { free(scratch); backing->overlay->failed = 1; return -1; }
        memcpy(target + done, (unsigned char *)scratch + prefix, (size_t)wanted);
        free(scratch);
        done += wanted;
    }
    return count;
}
static struct page *find_page(struct overlay *overlay, long long offset) {
    if (overlay->count > MAX_PAGES || overlay->limit > MAX_PAGES) { overlay->failed = 1; return NULL; }
    for (unsigned i = 0; i < overlay->count; i++) if (overlay->pages[i].offset == offset) return &overlay->pages[i];
    return NULL;
}
static long long virtual_read(void *context, void *buffer, long long count, long long offset) {
    struct backing *backing = context;
    if (backing->overlay->failed) return -1;
    if (offset < 0 || count < 0 || offset > backing->size || count > backing->size - offset) return -1;
    for (long long done = 0; done < count;) {
        long long cursor = offset + done, start = cursor - cursor % PAGE_BYTES;
        size_t prefix = (size_t)(cursor - start), length = PAGE_BYTES - prefix;
        if ((long long)length > count - done) length = (size_t)(count - done);
        struct page *page = find_page(backing->overlay, start);
        if (backing->overlay->failed) return -1;
        if (page) memcpy((unsigned char *)buffer + done, page->bytes + prefix, length);
        else if (backing_read(backing, (unsigned char *)buffer + done, length, cursor) != (long long)length) return -1;
        done += length;
    }
    return count;
}
static long long virtual_write(void *context, const void *buffer, long long count, long long offset) {
    struct backing *backing = context;
    struct overlay *overlay = backing->overlay;
    if (overlay->failed || overlay->count > MAX_PAGES || overlay->limit > MAX_PAGES || offset < 0 || count < 0 || offset > backing->size || count > backing->size - offset) {
        overlay->failed = 1; errno = EIO; return -1;
    }
    overlay->writes++;
    for (long long done = 0; done < count;) {
        long long cursor = offset + done, start = cursor - cursor % PAGE_BYTES;
        size_t prefix = (size_t)(cursor - start), length = PAGE_BYTES - prefix;
        if ((long long)length > count - done) length = (size_t)(count - done);
        struct page *page = find_page(overlay, start);
        if (!page) {
            if (overlay->count >= overlay->limit) { overlay->failed = 1; errno = ENOSPC; return -1; }
            page = &overlay->pages[overlay->count];
            size_t bytes = backing->size - start < PAGE_BYTES ? (size_t)(backing->size - start) : PAGE_BYTES;
            if (backing_read(backing, page->original, bytes, start) != (long long)bytes) {
                overlay->failed = 1; errno = EIO; return -1;
            }
            page->offset = start;
            memcpy(page->bytes, page->original, bytes);
            overlay->count++;
        }
        memcpy(page->bytes + prefix, (const unsigned char *)buffer + done, length);
        done += length;
    }
    return count;
}
static int virtual_sync(void *context) {
    // This flush is virtual only. No durability/repair promise is made.
    return ((struct backing *)context)->overlay->failed ? -1 : 0;
}
static nk_io virtual_io(struct backing *backing) {
    return (nk_io){.ctx = backing, .pread = virtual_read, .pwrite = virtual_write,
        .sync = virtual_sync, .size = backing->size, .readonly = 0};
}
static long long source_read(void *context, void *buffer, long long count, long long offset) {
    return backing_read(context, buffer, count, offset);
}
static int source_unchanged(struct backing *backing) {
    if (backing->overlay->count > MAX_PAGES) return 0;
    unsigned char bytes[PAGE_BYTES];
    for (unsigned i = 0; i < backing->overlay->count; i++) {
        struct page *page = &backing->overlay->pages[i];
        size_t count = backing->size - page->offset < PAGE_BYTES ? (size_t)(backing->size - page->offset) : PAGE_BYTES;
        if (backing_read(backing, bytes, count, page->offset) != (long long)count || memcmp(bytes, page->original, count)) return 0;
    }
    return 1;
}
// Only the compiled upstream ntfsrecover entry point uses these two overrides.
// It cannot open a physical path or create its ordinary writable device.
FILE *nk_overlay_fopen(const char *path, const char *mode) __asm__("_nk_overlay_fopen$DARWIN_EXTSN");
FILE *nk_overlay_fopen(const char *path, const char *mode) {
    static unsigned char boot[1024];
    if (!active || strcmp(path, VIRTUAL_NAME) || strcmp(mode, "rb") ||
        backing_read(active, boot, sizeof(boot), 0) != sizeof(boot)) { errno = EIO; return NULL; }
    // Upstream first reads the boot sector through stdio, then invokes mount.
    // Returning NULL would leave its stack boot buffer uninitialized, producing
    // bogus geometry even though our callback mount itself is correct.
    return fmemopen(boot, sizeof(boot), "rb");
}
static s64 checked_pread(struct ntfs_device *device, void *buffer, s64 count, s64 offset) {
    s64 result = nkdev_pread(device, buffer, count, offset);
    if (result != count) active->overlay->failed = 1;
    return result;
}
static s64 checked_pwrite(struct ntfs_device *device, const void *buffer, s64 count, s64 offset) {
    s64 result = nkdev_pwrite(device, buffer, count, offset);
    if (result != count) active->overlay->failed = 1;
    return result;
}
static s64 checked_read(struct ntfs_device *device, void *buffer, s64 count) {
    s64 result = nkdev_read(device, buffer, count);
    if (result != count) active->overlay->failed = 1;
    return result;
}
static s64 checked_write(struct ntfs_device *device, const void *buffer, s64 count) {
    s64 result = nkdev_write(device, buffer, count);
    if (result != count) active->overlay->failed = 1;
    return result;
}
ntfs_volume *nk_overlay_mount(const char *name, ntfs_mount_flags flags) {
    if (!active || strcmp(name, VIRTUAL_NAME) || flags != NTFS_MNT_FORENSIC) { errno = EPERM; return NULL; }
    struct nk_devctx *context = calloc(1, sizeof(*context));
    if (!context) return NULL;
    context->io = virtual_io(active);
    static struct ntfs_device_operations checked_ops;
    checked_ops = nk_dev_ops;
    checked_ops.pread = checked_pread; checked_ops.pwrite = checked_pwrite;
    checked_ops.read = checked_read; checked_ops.write = checked_write;
    struct ntfs_device *device = ntfs_device_alloc("memory-recovery-overlay", 0, &checked_ops, context);
    if (!device) { free(context); return NULL; }
    // FORENSIC applies only to the virtual writable device, never to the source.
    ntfs_volume *volume = ntfs_device_mount(device, flags);
    if (!volume) { ntfs_device_free(device); free(context); }
    return volume;
}
static struct overlay *new_overlay(void) {
    struct overlay *overlay = mmap(NULL, sizeof(*overlay), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANON, -1, 0);
    if (overlay == MAP_FAILED) return NULL;
    overlay->limit = MAX_PAGES;
    return overlay;
}
static int self_test(void) {
    char path[] = "/private/tmp/OpenCommander-Recovery-Overlay-XXXXXX";
    int created = mkstemp(path);
    unsigned char original[PAGE_BYTES * 3], after[sizeof(original)];
    memset(original, 0x5a, sizeof(original));
    if (created < 0 || write(created, original, sizeof(original)) != sizeof(original)) return 10;
    close(created);
    int fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    unlink(path); /* exclusively created disposable test fixture */
    struct overlay *overlay = new_overlay();
    if (fd < 0 || !overlay) return 11;
    struct backing backing = {.fd = fd, .sector = 512, .size = sizeof(original), .overlay = overlay};
    active = &backing;
    FILE *boot = nk_overlay_fopen(VIRTUAL_NAME, "rb");
    if (!boot || fread(after, 1, 1024, boot) != 1024 || memcmp(after, original, 1024)) return 21;
    fclose(boot);
    if (nk_overlay_fopen("/dev/rdisk6s1", "rb") != NULL) return 22;
    overlay->failed = 0;
    unsigned char change[32]; memset(change, 0x31, sizeof(change));
    if (virtual_write(&backing, change, sizeof(change), PAGE_BYTES - 7) != sizeof(change) || overlay->count != 2) return 12;
    if (virtual_read(&backing, after, sizeof(after), 0) != sizeof(after)) return 13;
    memcpy(original + PAGE_BYTES - 7, change, sizeof(change));
    if (memcmp(original, after, sizeof(after)) || !source_unchanged(&backing)) return 14;
    pid_t child = fork(); if (child < 0) return 15;
    if (!child) _exit(virtual_write(&backing, "fork", 4, 0) == 4 ? 0 : 1);
    int status;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) return 16;
    if (virtual_read(&backing, after, 4, 0) != 4 || memcmp(after, "fork", 4)) return 17;
    overlay->limit = 2;
    if (virtual_write(&backing, change, sizeof(change), PAGE_BYTES * 2) != -1 || !overlay->failed || !source_unchanged(&backing)) return 18;
    if (virtual_write(&backing, change, 1, 0) != -1) return 19;
    errno = 0;
    if (pwrite(fd, "x", 1, 0) != -1 || errno != EBADF) return 20;
    munmap(overlay, sizeof(*overlay)); close(fd);
    puts("PASS overlay: cross-page/overlapping reads, shared child writes, bounded fail-closed memory, read-only source unchanged");
    return 0;
}
static int virtual_write_proof(struct backing *candidate) {
    // Separate disposable copy: validation must not add test-file changes to
    // the replay candidate, let alone to the physical source.
    struct backing test = *candidate;
    test.overlay = new_overlay();
    if (!test.overlay) return 0;
    memcpy(test.overlay, candidate->overlay, offsetof(struct overlay, pages) + candidate->overlay->count * sizeof(struct page));
    nk_io io = virtual_io(&test);
    char reason[512];
    nk_volume *volume = nk_mount_io(&io, reason, sizeof(reason));
    int success = 0;
    if (volume) {
        char name[96], path[100], readback[64];
        snprintf(name, sizeof(name), "OpenCommander-Sandbox-%08x.txt", arc4random());
        snprintf(path, sizeof(path), "/%s", name);
        static const char payload[] = "OpenCommander recovery write/read proof\n";
        success = !nk_create(volume, "/", name) &&
            nk_write(volume, path, 0, sizeof(payload), payload) == sizeof(payload) &&
            nk_read(volume, path, 0, sizeof(payload), readback) == sizeof(payload) &&
            !memcmp(payload, readback, sizeof(payload)) && !nk_sync(volume) && !nk_delete(volume, path);
        if (nk_umount(volume) || test.overlay->failed || !source_unchanged(&test)) success = 0;
    }
    munmap(test.overlay, sizeof(*test.overlay));
    return success;
}
#ifdef NK_ENABLE_CHECKPOINT_APPLY
#include "recovery_checkpoint_apply.c"
#endif
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    int fd = -1;
    int apply_fd = -1;
    const char *backup_path = NULL;
    struct stat info;
#ifdef NK_ENABLE_CHECKPOINT_APPLY
    if (argc == 5 && !strcmp(argv[1], "--checkpoint-apply-fds") && !strcmp(argv[2], "0") && !strcmp(argv[3], "3")) {
        fd = dup(STDIN_FILENO); apply_fd = dup(3); backup_path = argv[4];
        close(3); /* No writable descriptor may reach the replay worker. */
        if (apply_fd < 0) return 66;
    } else
#endif
    if (argc == 3 && !strcmp(argv[1], "--source-fd") && !strcmp(argv[2], "0")) {
        fd = dup(STDIN_FILENO);
    } else if (argc == 2) {
        struct stat path;
        if (lstat(argv[1], &path) || !S_ISREG(path.st_mode) || path.st_nlink != 1 || path.st_uid != getuid()) return 65;
        fd = open(argv[1], O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        if (fd >= 0 && (fstat(fd, &info) || info.st_dev != path.st_dev || info.st_ino != path.st_ino)) { close(fd); return 65; }
    } else { fprintf(stderr, "Usage: recovery-overlay IMAGE | --source-fd 0 | --self-test (no apply operation exists)\n"); return 64; }
    if (fd < 0 || fstat(fd, &info) || (fcntl(fd, F_GETFL) & O_ACCMODE) != O_RDONLY) return 66;
    struct backing backing = {.fd = fd, .sector = 512, .size = info.st_size, .overlay = new_overlay()};
    if (!backing.overlay) return 67;
    if (S_ISCHR(info.st_mode)) {
        uint32_t sector = 0; uint64_t blocks = 0;
        if (ioctl(fd, DKIOCGETBLOCKSIZE, &sector) || ioctl(fd, DKIOCGETBLOCKCOUNT, &blocks) ||
            !sector || sector > PAGE_BYTES || sector < 512 || sector & (sector - 1) || blocks > LLONG_MAX / sector) return 68;
        backing.sector = sector; backing.size = (long long)(blocks * sector);
    } else if (!S_ISREG(info.st_mode)) return 65;
    if (backing.size < 512 || backing.size % backing.sector) return 68;
    nk_io io = virtual_io(&backing);
    nk_safety_report before, after;
    char reason[512];
    int result = 2;
    if (nk_inspect_io(&io, &before, reason, sizeof(reason))) { fprintf(stderr, "SOURCE_INSPECTION_FAILED %s\n", reason); goto done; }
    if (!before.blockers) { puts("ALREADY_CLEAN: no repair needed; source opened read-only"); result = 0; goto done; }
    if (before.blockers != NK_BLOCK_REPLAY_REQUIRED) { fprintf(stderr, "STAGING_REFUSED %s\n", reason); goto done; }
    puts("STAGING_ONLY: journal replay writes redirected to disposable memory; backing descriptor O_RDONLY"); fflush(stdout);
    active = &backing;
    pid_t child = fork();
    if (child < 0) goto done;
    if (!child) {
        if (apply_fd >= 0) close(apply_fd);
        char *arguments[] = {"recovery-overlay", "--sync", VIRTUAL_NAME, NULL};
        exit(nk_overlay_recovery_main(3, arguments));
    }
    int status;
    pid_t waited;
    struct timespec start, now;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (;;) {
        waited = waitpid(child, &status, WNOHANG);
        if (waited == child || (waited < 0 && errno != EINTR)) break;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (now.tv_sec - start.tv_sec >= 120) {
            kill(child, SIGKILL); /* Only this sandbox's disposable child, never a driver/daemon. */
            do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
            backing.overlay->failed = 1;
            puts("STAGING_TIMEOUT: disposable worker stopped; candidate discarded");
            break;
        }
        usleep(100000);
    }
    if (waited != child || !WIFEXITED(status) || WEXITSTATUS(status) || backing.overlay->failed ||
        backing.overlay->count > MAX_PAGES || backing.overlay->limit != MAX_PAGES) {
        puts("STAGING_FAILED: candidate discarded; no source changes applied"); goto done;
    }
    if (nk_inspect_io(&io, &after, reason, sizeof(reason)) || after.blockers) {
        puts("STAGING_FAILED: resulting virtual filesystem failed safety checks; nothing applied"); goto done;
    }
    if (!virtual_write_proof(&backing)) {
        puts("STAGING_FAILED: virtual write/read validation failed; nothing applied"); goto done;
    }
    puts("VIRTUAL_WRITE_READ_PROOF PASS: separate RAM-only copy, original candidate/source untouched");
    puts("STAGING_VALIDATED: virtual journal is clean; this is NOT a committed repair or write-mount approval");
    result = 0;
done:
    if (result == 0 && backing.overlay->count) {
        nk_io original = {.ctx = &backing, .pread = source_read, .size = backing.size, .readonly = 1};
        nk_safety_report unchanged;
        if (nk_inspect_io(&original, &unchanged, reason, sizeof(reason)) || memcmp(&before, &unchanged, sizeof(before))) {
            puts("SOURCE_METADATA_CHANGED_EXTERNALLY: candidate invalidated"); result = 3;
        }
    }
    if (!source_unchanged(&backing)) { puts("SOURCE_CHANGED_EXTERNALLY: candidate invalidated"); result = 3; }
#ifdef NK_ENABLE_CHECKPOINT_APPLY
#ifdef NK_CHECKPOINT_TESTS
    if (apply_fd >= 0 && !result && getenv("NK_TEST_CHECKPOINT_EXTRA_PAGE")) {
        unsigned char value = 0x5a;
        if (virtual_write(&backing, &value, 1, 0) != 1) result = 4;
    }
#endif
    if (apply_fd >= 0 && !result && backing.overlay->count) result = checkpoint_apply(&backing, apply_fd, backup_path);
#endif
    if (apply_fd < 0) {
        printf("SOURCE_READ_ONLY: staged_pages=%u staged_write_calls=%u source_write_callbacks=0 applied=NO\n",
            backing.overlay->count, backing.overlay->writes);
    } else close(apply_fd);
    munmap(backing.overlay, sizeof(*backing.overlay)); close(fd);
    return result;
}
