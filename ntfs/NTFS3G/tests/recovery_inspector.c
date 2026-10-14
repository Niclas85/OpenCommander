/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Laboratory-only entry point to pinned upstream ntfsrecover. Always a dry run.
 * No caller-supplied recovery options, device nodes, symlinks or writable fd.
 * Not a repair command and not installed/bundled in the production app. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#include "ntfs_bridge.h"

extern int nk_upstream_recovery_main(int argc, char **argv);
static long long read_image(void *ctx, void *buffer, long long count, long long offset) {
    return pread(*(int *)ctx, buffer, (size_t)count, offset);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: recovery-inspector NEW-TEST-IMAGE (regular image only; always --no-action --sync)\n");
        return 64;
    }
    struct stat path, opened;
    if (lstat(argv[1], &path) || !S_ISREG(path.st_mode) || path.st_nlink != 1 ||
        path.st_uid != getuid() || path.st_size < 512 || path.st_size > 1024LL * 1024 * 1024) {
        fprintf(stderr, "Refusing a device, symlink, shared/oversized file or non-owned image.\n");
        return 65;
    }
    int descriptor = open(argv[1], O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0 || fstat(descriptor, &opened) || opened.st_dev != path.st_dev ||
        opened.st_ino != path.st_ino || !S_ISREG(opened.st_mode)) {
        fprintf(stderr, "Image identity/open check failed.\n");
        if (descriptor >= 0) close(descriptor);
        return 66;
    }
    char pinned[64];
    snprintf(pinned, sizeof(pinned), "/dev/fd/%d", descriptor);
    nk_io io = {.ctx = &descriptor, .pread = read_image, .size = opened.st_size, .readonly = 1};
    nk_safety_report report;
    char reason[512];
    if (nk_inspect_io(&io, &report, reason, sizeof(reason))) {
        fprintf(stderr, "Inspection failed: %s\n", reason);
        close(descriptor); return 2;
    }
    if (!report.blockers) {
        puts("ALREADY_CLEAN: no journal recovery needed; no writes performed");
        close(descriptor); return 0;
    }
    if (report.blockers != NK_BLOCK_REPLAY_REQUIRED) {
        fprintf(stderr, "RECOVERY_NOT_ATTEMPTED: %s\n", reason);
        close(descriptor); return 2;
    }
    char *arguments[] = {"recovery-inspector", "--no-action", "--sync", pinned, NULL};
    puts("LABORATORY READ-ONLY RECOVERY SIMULATION; no repair or journal reset will run");
    fflush(stdout);
    int status = nk_upstream_recovery_main(4, arguments);
    puts("Simulation only: this result does not authorize applying changes or mounting for writing");
    close(descriptor);
    return status;
}
