/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included ONLY in the separate, opt-in laboratory checkpoint tool.
 * Not a general repair engine: only two mapped $LogFile restart pages may
 * change, after successful replay and validation in the read-only sandbox. */
#include <sys/mount.h>
#include <ntfs-3g/mst.h>

struct checkpoint_backup {
    char magic[16];
    uint64_t size;
    uint32_t sector, count;
    struct page pages[2]; /* exact originals AND replacements, for inspection */
};

static int checkpoint_flush(int fd, int physical) {
    return physical ? ioctl(fd, DKIOCSYNCHRONIZECACHE) :
        (fsync(fd) || fcntl(fd, F_FULLFSYNC));
}
static int checkpoint_unmounted(const struct stat *source) {
    if (!S_ISCHR(source->st_mode)) return 1;
    int count = getfsstat(NULL, 0, MNT_NOWAIT);
    if (count <= 0) return 0;
    struct statfs *mounts = calloc((size_t)count + 8, sizeof(*mounts));
    if (!mounts) return 0;
    int got = getfsstat(mounts, ((size_t)count + 8) * sizeof(*mounts), MNT_NOWAIT);
    int allowed = got > 0 && got < count + 8;
    for (int index = 0; allowed && index < got; index++) {
        struct stat target;
        if (!stat(mounts[index].f_mntfromname, &target) &&
            (S_ISBLK(target.st_mode) || S_ISCHR(target.st_mode)) && target.st_rdev == source->st_rdev) allowed = 0;
    }
    free(mounts);
    return allowed;
}
static int checkpoint_identity(struct backing *source, int output) {
    struct stat a, b;
    if (fstat(source->fd, &a) || fstat(output, &b) ||
        (fcntl(output, F_GETFL) & O_ACCMODE) != O_RDWR) return 0;
    if (S_ISREG(a.st_mode)) return S_ISREG(b.st_mode) && a.st_dev == b.st_dev &&
        a.st_ino == b.st_ino && a.st_size == b.st_size && a.st_uid == getuid() && a.st_nlink == 1;
    if (!S_ISCHR(a.st_mode) || !S_ISCHR(b.st_mode) || a.st_rdev != b.st_rdev || a.st_dev != b.st_dev) return 0;
    uint32_t sector = 0; uint64_t blocks = 0;
    return !ioctl(output, DKIOCGETBLOCKSIZE, &sector) && !ioctl(output, DKIOCGETBLOCKCOUNT, &blocks) &&
        sector == source->sector && blocks == (uint64_t)source->size / sector && checkpoint_unmounted(&a);
}
static int checkpoint_page_valid(const unsigned char *bytes) {
    unsigned char decoded[PAGE_BYTES]; memcpy(decoded, bytes, sizeof(decoded));
    RESTART_PAGE_HEADER *header = (RESTART_PAGE_HEADER *)decoded;
    if (header->magic != magic_RSTR || le32_to_cpu(header->system_page_size) != PAGE_BYTES ||
        le32_to_cpu(header->log_page_size) != PAGE_BYTES || sle16_to_cpu(header->major_ver) != 1 ||
        sle16_to_cpu(header->minor_ver) != 1 ||
        ntfs_mst_post_read_fixup((NTFS_RECORD *)decoded, sizeof(decoded))) return 0;
    unsigned offset = le16_to_cpu(header->restart_area_offset);
    if (offset < sizeof(*header) || offset > PAGE_BYTES - sizeof(RESTART_AREA)) return 0;
    RESTART_AREA *area = (RESTART_AREA *)(decoded + offset);
    return (area->flags & RESTART_VOLUME_IS_CLEAN) && area->client_in_use_list == LOGFILE_NO_CLIENT;
}
static int checkpoint_pages(struct backing *source, struct page *ordered[2]) {
    if (source->overlay->count != 2 || source->overlay->failed) return 0;
    nk_io io = {.ctx = source, .pread = source_read, .size = source->size, .readonly = 1};
    char reason[512];
    nk_volume *volume = nk_mount_io(&io, reason, sizeof(reason));
    if (!volume) return 0;
    ntfs_inode *inode = ntfs_inode_open(volume->vol, FILE_LogFile);
    ntfs_attr *attribute = inode ? ntfs_attr_open(inode, AT_DATA, AT_UNNAMED, 0) : NULL;
    int valid = attribute && NAttrNonResident(attribute) && volume->vol->cluster_size >= PAGE_BYTES;
    for (int index = 0; valid && index < 2; index++) {
        s64 logical = index * PAGE_BYTES;
        LCN cluster = ntfs_attr_vcn_to_lcn(attribute, logical >> volume->vol->cluster_size_bits);
        s64 physical = cluster < 0 ? -1 : (cluster << volume->vol->cluster_size_bits) +
            (logical & (volume->vol->cluster_size - 1));
        ordered[index] = find_page(source->overlay, physical);
        valid = physical >= 0 && ordered[index] && physical % PAGE_BYTES == 0 &&
            physical <= source->size - PAGE_BYTES && checkpoint_page_valid(ordered[index]->bytes);
    }
    if (attribute) ntfs_attr_close(attribute);
    if (inode && ntfs_inode_close(inode)) valid = 0;
    if (nk_umount(volume)) valid = 0;
    return valid && ordered[0] != ordered[1] && !memcmp(ordered[0]->bytes, ordered[1]->bytes, PAGE_BYTES);
}
static int checkpoint_backup_file(struct backing *source, struct page *pages[2], const char *path) {
    struct checkpoint_backup backup = {.magic = "OCNTFSCKPT-v1", .size = source->size,
        .sector = source->sector, .count = 2};
    backup.pages[0] = *pages[0]; backup.pages[1] = *pages[1];
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return 0;
    ssize_t written = write(fd, &backup, sizeof(backup));
    struct stat info;
    int valid = written == sizeof(backup) && !fstat(fd, &info) && S_ISREG(info.st_mode) &&
        info.st_nlink == 1 && info.st_uid == getuid() && !checkpoint_flush(fd, 0);
    if (close(fd)) valid = 0;
    /* Also require the backup directory entry to reach stable storage. */
    char *directory = strdup(path);
    if (!directory) return 0;
    char *slash = strrchr(directory, '/');
    if (!slash || slash == directory) { free(directory); return 0; }
    *slash = 0;
    fd = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0 || fsync(fd)) valid = 0;
    if (fd >= 0) close(fd);
    free(directory);
    return valid;
}
static int checkpoint_matches(struct backing *source, struct page *pages[2], int replacement) {
    unsigned char bytes[PAGE_BYTES];
    for (int index = 0; index < 2; index++) {
        if (backing_read(source, bytes, PAGE_BYTES, pages[index]->offset) != PAGE_BYTES ||
            memcmp(bytes, replacement ? pages[index]->bytes : pages[index]->original, PAGE_BYTES)) return 0;
    }
    return 1;
}
static uint64_t checkpoint_original_lsn(const struct page *page) {
    const RESTART_PAGE_HEADER *header = (const RESTART_PAGE_HEADER *)page->original;
    unsigned offset = le16_to_cpu(header->restart_area_offset);
    if (offset < sizeof(*header) || offset > PAGE_BYTES - sizeof(RESTART_AREA)) return UINT64_MAX;
    return sle64_to_cpu(((const RESTART_AREA *)(page->original + offset))->current_lsn);
}
static int checkpoint_apply(struct backing *source, int output, const char *backup_path) {
    struct page *pages[2] = {0};
    struct stat info;
    if (!checkpoint_identity(source, output) || !checkpoint_pages(source, pages) ||
        !source_unchanged(source) || fstat(source->fd, &info)) {
        puts("CHECKPOINT_REFUSED: only a validated, unchanged pair of mapped restart pages may be applied"); return 4;
    }
    if (!checkpoint_backup_file(source, pages, backup_path)) {
        puts("CHECKPOINT_REFUSED: durable exclusive local backup failed; no device writes"); return 4;
    }
    /* Recheck after backup and immediately before the first write. */
    if (!checkpoint_identity(source, output) || !checkpoint_matches(source, pages, 0)) return 4;
    int physical = S_ISCHR(info.st_mode), success = 1, attempted = 0;
    /* Keep the more recent original restart copy until the other is flushed. */
    int first = checkpoint_original_lsn(pages[0]) > checkpoint_original_lsn(pages[1]) ? 1 : 0;
    for (int step = 0; step < 2; step++) {
        int index = first ^ step;
        attempted = 1;
#ifdef NK_CHECKPOINT_TESTS
        int fail = getenv("NK_TEST_CHECKPOINT_FAIL_SECOND") && step == 1;
        int fail_flush = getenv("NK_TEST_CHECKPOINT_FAIL_FLUSH") && step == 0;
#else
        int fail = 0;
        int fail_flush = 0;
#endif
        if (fail || pwrite(output, pages[index]->bytes, PAGE_BYTES, pages[index]->offset) != PAGE_BYTES ||
            fail_flush || checkpoint_flush(output, physical)) { success = 0; break; }
    }
    nk_io original = {.ctx = source, .pread = source_read, .size = source->size, .readonly = 1};
    nk_safety_report report; char reason[512];
    if (success && (!checkpoint_matches(source, pages, 1) ||
        nk_inspect_io(&original, &report, reason, sizeof(reason)) || report.blockers)) success = 0;
    if (success) {
        puts("CHECKPOINT_APPLIED: two restart pages flushed and read back; clean source preflight passed");
        printf("CHECKPOINT_BACKUP %s\n", backup_path);
        return 0;
    }
    int restored = attempted;
    for (int index = 0; index < 2; index++)
        if (pwrite(output, pages[index]->original, PAGE_BYTES, pages[index]->offset) != PAGE_BYTES) restored = 0;
    if (checkpoint_flush(output, physical) || !checkpoint_matches(source, pages, 0)) restored = 0;
    puts(restored ? "CHECKPOINT_ROLLED_BACK: exact original pages restored and flushed after failure" :
        "CHECKPOINT_CRITICAL: rollback not verified; keep device unmounted and retain backup");
    return restored ? 4 : 5;
}
