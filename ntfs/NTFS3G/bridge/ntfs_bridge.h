/*
 * ntfs_bridge — thin C facade over libntfs-3g for the ntfskit FSKit module.
 *
 * UTF-8 path-based operations: mount, stat, list, read, write, create, mkdir,
 * delete, rename, truncate. One nk_volume* per mounted NTFS volume. Not
 * thread-safe — callers must serialize (the Swift side uses one queue).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#ifndef NTFS_BRIDGE_H
#define NTFS_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct nk_volume nk_volume;

typedef struct {
    const char *name;      /* UTF-8, valid only during the callback */
    int         is_dir;
    long long   size;      /* bytes, 0 for directories */
    uint64_t    inode;     /* MFT record number — stable item id */
    uint64_t    next_cookie; /* opaque byte-position cookie, not an entry count */
} nk_dirent;

/* Return 0 to continue, non-zero to stop enumeration early. */
typedef int (*nk_dirent_cb)(void *ctx, const nk_dirent *entry);

typedef struct {
    int       is_dir;
    long long size;        /* data size in bytes */
    long long alloc_size;  /* allocated bytes on disk */
    uint64_t  inode;       /* MFT record number */
    long long atime, mtime, ctime, btime;  /* unix epoch seconds */
    int32_t   atime_nsec, mtime_nsec, ctime_nsec, btime_nsec;
    int       is_symlink;  /* NTFS reparse point (Interix symlink style) */
    int       koio_ok;     /* 1 = data is plain non-resident: kernel may map it */
    int       is_resident; /* data lives in the MFT record (small/new file) */
} nk_stat;


/* Callback-backed block I/O — lets the FSKit host route every device access
 * through FSBlockDeviceResource (the sandbox forbids opening /dev directly).
 * Callbacks return bytes transferred, or -1 on error. */
typedef long long (*nk_pread_cb)(void *ctx, void *buf, long long count,
                                 long long offset);
typedef long long (*nk_pwrite_cb)(void *ctx, const void *buf, long long count,
                                  long long offset);
typedef int (*nk_sync_cb)(void *ctx);

typedef struct {
    void        *ctx;
    nk_pread_cb  pread;
    nk_pwrite_cb pwrite;
    nk_sync_cb   sync;      /* required for writes; return 0 only after durable flush */
    long long    size;      /* device size in bytes */
    int          readonly;
} nk_io;

/* Inspection never enables writes, clears a flag, resets or replays a journal.
 * A replay-required result is NOT a promise that replay is supported or safe. */
enum {
    NK_BLOCK_DIRTY = 1u << 0,
    NK_BLOCK_HIBERNATED = 1u << 1,
    NK_BLOCK_REPLAY_REQUIRED = 1u << 2,
    NK_BLOCK_JOURNAL_INVALID = 1u << 3,
    NK_BLOCK_WINDOWS_CACHE = 1u << 4,
    NK_BLOCK_VERSION = 1u << 5,
    NK_BLOCK_IO = 1u << 6
};
enum {
    NK_JOURNAL_UNKNOWN = 0,
    NK_JOURNAL_CLEAN = 1,
    NK_JOURNAL_REPLAY_REQUIRED = 2,
    NK_JOURNAL_INVALID = 3,
    NK_JOURNAL_WINDOWS_CACHE = 4
};
typedef struct {
    uint32_t blockers;
    uint16_t volume_flags;
    uint8_t major_version, minor_version;
    int journal_state;
    int hibernation_state; /* 0 inactive, 1 active, 2 unreadable/unknown */
    int error_code;
} nk_safety_report;

/* Returns 0 when a report was produced (possibly containing blockers), -1 on
 * an inspection/open/close failure. In both cases writes remain disabled. */
int nk_inspect_io(const nk_io *io, nk_safety_report *report,
                  char *errbuf, size_t errlen);

/* Mount through the callback device. `io` is copied; `io->ctx` must stay
 * valid until nk_umount. */
nk_volume *nk_mount_io(const nk_io *io, char *errbuf, size_t errlen);

/* Flush and release. Returns 0 on success. */
int nk_umount(nk_volume *v);

/* Volume totals for statfs. Any out-pointer may be NULL. */
int nk_statvfs(nk_volume *v, long long *total_bytes, long long *free_bytes,
               int *cluster_size);

/* Volume label (UTF-8) into buf. Returns 0 on success. */
int nk_label(nk_volume *v, char *buf, size_t buflen);

int nk_stat_path(nk_volume *v, const char *path, nk_stat *st);
int nk_list(nk_volume *v, const char *dir_path, nk_dirent_cb cb, void *ctx);
/* Start at 0, then resume only a next_cookie returned by this directory in
 * the same mutation generation. Non-zero callbacks stop promptly, not as errors. */
int nk_list_from(nk_volume *v, const char *dir_path, uint64_t cookie,
                 nk_dirent_cb cb, void *ctx);

long long nk_read(nk_volume *v, const char *path, long long offset,
                  long long count, void *buf);
long long nk_write(nk_volume *v, const char *path, long long offset,
                   long long count, const void *buf);

int nk_create(nk_volume *v, const char *dir_path, const char *name);  /* file */
int nk_mkdir(nk_volume *v, const char *dir_path, const char *name);
int nk_delete(nk_volume *v, const char *path);   /* file or empty dir */
int nk_rename(nk_volume *v, const char *old_path, const char *new_dir,
              const char *new_name);
int nk_truncate(nk_volume *v, const char *path, long long size);
enum {
    NK_TIME_ACCESS = 1u << 0,
    NK_TIME_MODIFY = 1u << 1,
    NK_TIME_CHANGE = 1u << 2,
    NK_TIME_BIRTH = 1u << 3
};
typedef struct { int64_t seconds; int32_t nanoseconds; } nk_timestamp;
typedef struct {
    uint32_t valid;
    nk_timestamp access, modify, change, birth;
} nk_times;
/* Validate ALL selected values before mutation. NTFS precision is 100 ns.
 * Unselected fields are preserved, except ctime advances unless specified.
 * Close/write errors propagate; this is not a crash-atomic transaction. */
int nk_set_times(nk_volume *v, const char *path, const nk_times *times);
int nk_validate_times(const nk_times *times); /* no device I/O */
int nk_sync(nk_volume *v);
/* Replace using a temporary recovery name. On a failed rollback, recovery_path
 * identifies preserved data and must be shown to the user. Not crash-atomic. */
int nk_move(nk_volume *v, const char *old_path, const char *new_dir,
            const char *new_name, int replace, char *recovery_path, size_t recovery_size);


#ifdef __cplusplus
}
#endif
#endif
