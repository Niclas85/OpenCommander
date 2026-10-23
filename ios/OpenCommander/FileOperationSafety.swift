import Foundation
import CryptoKit
import Darwin

/// Hold for the entire application lifetime, before reading/writing a profile.
/// The lock file is never deleted: kernel ownership, not stale PID text, decides
/// whether an existing profile writer is alive.
final class CommanderProfileLease {
    enum Failure: Error, Equatable { case inUse, unavailable }
    private let descriptor: Int32
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent(".opencommander-profile.lock").path
        let fd = Darwin.open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.unavailable }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1 else { close(fd); throw Failure.unavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK || errno == EAGAIN
            close(fd); throw busy ? Failure.inUse : Failure.unavailable
        }
        descriptor = fd
    }
    deinit { _ = flock(descriptor, LOCK_UN); close(descriptor) }
}

/// Classifies the complete underlying error chain; a provider wrapper must not
/// hide a full disk or a revoked grant. No localized-message matching.
enum MobileStorageIssue {
    static func key(for error: Error) -> String {
        var errors: [NSError] = []
        var current: NSError? = error as NSError
        while let item = current, errors.count < 12 {
            errors.append(item); current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        if errors.contains(where: { ($0.domain == NSCocoaErrorDomain && $0.code == NSUserCancelledError) || ($0.domain == NSPOSIXErrorDomain && $0.code == Int(ECANCELED)) }) { return "history_error_cancelled" }
        if errors.contains(where: { ($0.domain == NSPOSIXErrorDomain && $0.code == Int(ENOSPC)) || ($0.domain == NSCocoaErrorDomain && $0.code == NSFileWriteOutOfSpaceError) }) { return "mobile_error_space" }
        if errors.contains(where: { ($0.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains($0.code)) || ($0.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains($0.code)) }) { return "mobile_error_permission" }
        if errors.contains(where: { ($0.domain == NSPOSIXErrorDomain && $0.code == Int(EROFS)) || ($0.domain == NSCocoaErrorDomain && $0.code == NSFileWriteVolumeReadOnlyError) }) { return "mobile_error_readonly" }
        if errors.contains(where: { ($0.domain == NSPOSIXErrorDomain && $0.code == Int(ENOENT)) || ($0.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains($0.code)) }) { return "mobile_error_missing" }
        if errors.contains(where: { $0.domain == NSURLErrorDomain }) { return "mobile_error_network" }
        return "mobile_error_provider"
    }
}

/// Pointer-time preflight only: no filesystem reads, symlink resolution or network
/// requests. The transfer engine must still perform authoritative validation.
enum CommanderDropPolicy {
    static func accepts(_ sources: [(url: URL, directory: Bool)], target: URL) -> Bool {
        guard !sources.isEmpty, target.isFileURL, sources.allSatisfy({ $0.url.isFileURL }) else { return false }
        let destination = target.standardizedFileURL.path
        let entries = sources.map { ($0.url.standardizedFileURL, $0.directory) }
        if entries.allSatisfy({ $0.0.deletingLastPathComponent().path == destination }) { return false }
        return !entries.contains { source, directory in
            directory && (source.path == destination || destination.hasPrefix(source.path == "/" ? "/" : source.path + "/"))
        }
    }
}

enum CommanderDuration {
    static func format(_ seconds: TimeInterval, german: Bool) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let units: [(TimeInterval, String)] = german
            ? [(86400, "Tage"), (3600, "Std."), (60, "Min."), (1, "Sek.")]
            : [(86400, "days"), (3600, "hours"), (60, "min"), (1, "sec")]
        let unit = units.first { seconds >= $0.0 } ?? units.last!
        return String(format: seconds >= 60 ? "%.1f %@" : "%.0f %@", seconds / unit.0, unit.1)
    }
}

#if os(macOS) || targetEnvironment(macCatalyst)
/// Native system libarchive. Never delegate extraction to a shell or accept
/// archive-provided links, permissions, device nodes or destination paths.
enum CommanderNativeArchive {
    struct Member: Equatable {
        let path: String
        let size: Int64
        let directory: Bool
        let modified: Int64
    }
    static let extensions = [".zip", ".7z", ".rar", ".tar", ".tgz", ".tar.gz", ".tbz", ".tbz2", ".tar.bz2", ".txz", ".tar.xz", ".tar.zst"]
    static func supports(_ name: String) -> Bool { extensions.contains { name.lowercased().hasSuffix($0) } }

    /// libarchive on macOS otherwise tries to run a separately installed zstd
    /// program. Decode in-process into an exclusive private staging file instead.
    /// Header bytes, not the filename, decide whether decoding is necessary.
    static func decodedZstandard(_ source: URL, maximumBytes: UInt64 = SafeArchiveLimits.maximumBytes + 64 * 1024 * 1024,
                                checkCancellation: () throws -> Void = {}) throws -> URL? {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let header = try input.read(upToCount: 4) ?? Data()
        guard header.count == 4 else { return nil }
        let bytes = Array(header)
        let magic = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        guard magic == 0xFD2FB528 || magic & 0xFFFFFFF0 == 0x184D2A50 else { return nil }
#if OPENCOMMANDER_ZSTD || targetEnvironment(macCatalyst)
        try checkCancellation()
        guard let context = oc_zstd_create() else { throw CocoaError(.fileReadUnknown) }
        defer { oc_zstd_free(context) }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommander-Zstd-" + UUID().uuidString + ".tar")
        let descriptor = Darwin.open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var retained = false
        defer { try? handle.close(); if !retained { try? FileManager.default.removeItem(at: output) } }
        try input.seek(toOffset: 0)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total: UInt64 = 0, lastStatus: Int32 = 1
        let deadline = Date().addingTimeInterval(60)
        while true {
            try checkCancellation()
            guard Date() < deadline else { throw CocoaError(.userCancelled) }
            let compressed = try input.read(upToCount: 64 * 1024) ?? Data()
            if compressed.isEmpty {
                guard lastStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
                break
            }
            var position = 0, lastProduced = 0
            repeat {
                try checkCancellation()
                guard Date() < deadline else { throw CocoaError(.userCancelled) }
                var consumed = 0, produced = 0
                lastStatus = compressed.withUnsafeBytes { raw in
                    buffer.withUnsafeMutableBytes { out in
                        oc_zstd_step(context, raw.baseAddress!.advanced(by: position), raw.count - position,
                                     &consumed, out.baseAddress, out.count, &produced)
                    }
                }
                guard lastStatus >= 0 else { throw CocoaError(.fileReadCorruptFile) }
                if consumed == 0 && produced == 0 {
                    guard position == compressed.count else { throw CocoaError(.fileReadCorruptFile) }
                    break // Decoder needs the next input chunk.
                }
                guard UInt64(produced) <= maximumBytes - total else { throw CocoaError(.fileReadTooLarge) }
                if produced > 0 { try handle.write(contentsOf: Data(buffer.prefix(produced))); total += UInt64(produced) }
                position += consumed
                lastProduced = produced
                // Drain a full output buffer even when this input chunk ended.
            } while position < compressed.count || (lastProduced == buffer.count && lastStatus != 0)
        }
        try handle.close()
        retained = true
        return output
#else
        throw CocoaError(.featureUnsupported)
#endif
    }

    private final class Reader {
        private let library: UnsafeMutableRawPointer
        let archive: UnsafeMutableRawPointer
        let next: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
        let read: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int) -> Int
        let skip: @convention(c) (UnsafeMutableRawPointer?) -> Int32
        let pathname: @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
        let filetype: @convention(c) (UnsafeMutableRawPointer?) -> UInt32
        let size: @convention(c) (UnsafeMutableRawPointer?) -> Int64
        let mtime: @convention(c) (UnsafeMutableRawPointer?) -> Int64
        let symlink: @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
        let hardlink: @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
        let encrypted: @convention(c) (UnsafeMutableRawPointer?) -> Int32
        let release: @convention(c) (UnsafeMutableRawPointer?) -> Int32
        private let decoded: URL?
        init(_ source: URL, checkCancellation: () throws -> Void = {}) throws {
            let decoded = try CommanderNativeArchive.decodedZstandard(source, checkCancellation: checkCancellation)
            self.decoded = decoded
            var retained = false
            defer { if !retained, let decoded { try? FileManager.default.removeItem(at: decoded) } }
            guard let library = dlopen("/usr/lib/libarchive.dylib", RTLD_NOW | RTLD_LOCAL) else { throw CocoaError(.featureUnsupported) }
            func symbol<T>(_ name: String, _: T.Type) throws -> T {
                guard let address = dlsym(library, name) else { throw CocoaError(.featureUnsupported) }
                return unsafeBitCast(address, to: T.self)
            }
            do {
                let create = try symbol("archive_read_new", (@convention(c) () -> UnsafeMutableRawPointer?).self)
                release = try symbol("archive_read_free", (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
                next = try symbol("archive_read_next_header", (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32).self)
                read = try symbol("archive_read_data", (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int) -> Int).self)
                skip = try symbol("archive_read_data_skip", (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
                pathname = try symbol("archive_entry_pathname_utf8", (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?).self)
                filetype = try symbol("archive_entry_filetype", (@convention(c) (UnsafeMutableRawPointer?) -> UInt32).self)
                size = try symbol("archive_entry_size", (@convention(c) (UnsafeMutableRawPointer?) -> Int64).self)
                mtime = try symbol("archive_entry_mtime", (@convention(c) (UnsafeMutableRawPointer?) -> Int64).self)
                symlink = try symbol("archive_entry_symlink", (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?).self)
                hardlink = try symbol("archive_entry_hardlink", (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?).self)
                encrypted = try symbol("archive_entry_is_encrypted", (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
                let formats = try symbol("archive_read_support_format_all", (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
                let open = try symbol("archive_read_open_filename", (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Int32).self)
                let builtinFilters = try ["none", "gzip", "bzip2", "xz", "lzma"].map { filter in
                    try symbol("archive_read_support_filter_" + filter, (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
                }
                guard let archive = create() else { throw CocoaError(.fileReadUnknown) }
                // Register only built-in filters, never libarchive's external
                // program fallbacks (zstd/lzop/etc.).
                let filtersOK = builtinFilters.allSatisfy { $0(archive) == 0 }
                guard filtersOK, formats(archive) == 0,
                      (decoded ?? source).path.withCString({ open(archive, $0, 64 * 1024) }) == 0 else {
                    _ = release(archive); throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "native archive reader initialization"])
                }
                self.archive = archive; self.library = library
                retained = true
            } catch { dlclose(library); throw error }
        }
        deinit { _ = release(archive); dlclose(library); if let decoded { try? FileManager.default.removeItem(at: decoded) } }
        func member(_ entry: UnsafeMutableRawPointer) throws -> Member? {
            guard let pointer = pathname(entry), var path = String(validatingUTF8: pointer) else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "native archive UTF-8 pathname unavailable"]) }
            let directory = filetype(entry) == UInt32(S_IFDIR)
            guard [UInt32(S_IFREG), UInt32(S_IFDIR)].contains(filetype(entry)),
                  symlink(entry) == nil, hardlink(entry) == nil, encrypted(entry) == 0, size(entry) >= 0,
                  !directory || size(entry) == 0 else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "native archive unsupported member metadata: type=\(filetype(entry)), size=\(size(entry)), encrypted=\(encrypted(entry))"])
            }
            if directory && [".", "./"].contains(path) { return nil }
            while path.hasPrefix("./") { path.removeFirst(2) }
            if directory && !path.hasSuffix("/") { path += "/" }
            let seconds = mtime(entry)
            return Member(path: path, size: directory ? 0 : size(entry), directory: directory,
                modified: seconds >= 0 && seconds <= Int64.max / 1000 ? seconds * 1000 : 0)
        }
    }
    static func members(_ source: URL, checkCancellation: () throws -> Void = {}) throws -> [Member] {
        let reader = try Reader(source, checkCancellation: checkCancellation)
        var result: [Member] = [], limits = SafeArchiveLimits()
        while true {
            try checkCancellation()
            var entry: UnsafeMutableRawPointer?
            let status = reader.next(reader.archive, &entry)
            if status == 1 { break }
            guard status == 0, let entry else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "native archive listing header \(status)"]) }
            if let member = try reader.member(entry) {
                try limits.include(path: member.path, size: UInt64(member.size), symbolicLink: false)
                result.append(member)
            }
            guard reader.skip(reader.archive) == 0 else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "native archive listing skip"]) }
        }
        return result
    }
    /// Output must be a new directory. Failed/cancelled extraction removes only
    /// this newly created staging directory, never an existing destination.
    static func extract(_ source: URL, prefixes: [String] = [], to destination: URL,
                        maximumBytes: UInt64 = SafeArchiveLimits.maximumBytes,
                        checkCancellation: () throws -> Void = {}, progress: (Int, Int) -> Void = { _, _ in }) throws {
        let all = try members(source, checkCancellation: checkCancellation)
        let selected = all.filter { member in prefixes.isEmpty || prefixes.contains { member.path == $0 || member.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") } }
        guard !selected.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        guard selected.reduce(UInt64(0), { $0 + UInt64($1.size) }) <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let fm = FileManager.default
        guard !SafeFileOperations.exists(destination) else { throw SafeFileOperations.conflict(destination) }
        try fm.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let reader = try Reader(source, checkCancellation: checkCancellation)
            let expected = Dictionary(uniqueKeysWithValues: all.map { ($0.path, $0) })
            var seen = Set<String>(), completed = 0, total: UInt64 = 0
            let wanted = Set(selected.map(\.path))
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try checkCancellation()
                var entry: UnsafeMutableRawPointer?
                let status = reader.next(reader.archive, &entry)
                if status == 1 { break }
                guard status == 0, let entry else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "archive extraction header status \(status)"]) }
                guard let member = try reader.member(entry) else { continue }
                guard expected[member.path] == member, seen.insert(member.path).inserted else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "archive extraction changed or duplicate member"]) }
                if !wanted.contains(member.path) {
                    guard reader.skip(reader.archive) == 0 else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "native archive extraction skip"]) }; continue
                }
                let output = try SafeArchiveLimits.outputURL(for: member.path, in: destination)
                if member.directory {
                    try fm.createDirectory(at: output, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let descriptor = Darwin.open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                    defer { try? handle.close() }
                    var written: UInt64 = 0
                    while true {
                        try checkCancellation()
                        let count = buffer.withUnsafeMutableBytes { reader.read(reader.archive, $0.baseAddress, $0.count) }
                        guard count >= 0 else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "archive extraction data read failed"]) }
                        if count == 0 { break }
                        guard UInt64(count) <= UInt64(member.size) - written, UInt64(count) <= maximumBytes - total else { throw CocoaError(.fileReadTooLarge) }
                        try handle.write(contentsOf: Data(buffer.prefix(count)))
                        written += UInt64(count); total += UInt64(count)
                    }
                    guard written == UInt64(member.size) else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "archive extraction declared-size mismatch"]) }
                    try handle.synchronize()
                    if member.modified > 0 { try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(member.modified) / 1000)], ofItemAtPath: output.path) }
                }
                completed += 1; progress(completed, selected.count)
            }
            guard seen == Set(expected.keys), completed == selected.count else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "archive extraction incomplete member set"]) }
            try checkCancellation()
        } catch { try? fm.removeItem(at: destination); throw error }
    }
}
#endif

/// Content proof and logical references only, never credentials/download URLs.
/// Item paths let non-Graph clients restore their ID registry after restart.
struct CloudUndoPayload: Codable, Equatable {
    struct Object: Codable, Equatable {
        let id: String
        let name: String
        let path: String?
        let parent: String?
        let parentPath: String?
        let content: [String: String]
    }
    struct SourceRestore: Codable, Equatable {
        let endpoint: String
        let account: String
        let recovery: Object
        let name: String
        let parent: String?
        let parentPath: String?
    }
    struct LocalSourceRestore: Codable, Equatable {
        let original: String
        let recovery: String
        let parentDevice: UInt64
        let parentInode: UInt64
    }
    let endpoint: String
    let account: String
    let kind: String
    let current: Object
    var previous: Object? = nil
    var originalName: String? = nil
    var originalParent: String? = nil
    var originalParentPath: String? = nil
    var sourceRestore: SourceRestore? = nil
    var localSourceRestore: LocalSourceRestore? = nil
    var localCopyUndo: Data? = nil
    func validate() throws {
        func bounded(_ text: String?, limit: Int = 8192) -> Bool { text == nil || (text!.utf8.count <= limit && !text!.contains("\0")) }
        func name(_ text: String) -> Bool { !text.isEmpty && text != "." && text != ".." && !text.contains("/") && !text.contains("\0") }
        let objects = [current] + [previous, sourceRestore?.recovery].compactMap { $0 }
        if let source = sourceRestore {
            guard !source.endpoint.isEmpty, !source.account.isEmpty, bounded(source.endpoint, limit: 512),
                  bounded(source.account, limit: 1024), name(source.name), bounded(source.parent), bounded(source.parentPath) else {
                throw NSError(domain: "OpenCommander.Cloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "cloud_undo_changed"])
            }
        }
        if let local = localSourceRestore {
            guard [local.original, local.recovery].allSatisfy({ $0.hasPrefix("/") && $0 != "/" && bounded($0) && !$0.split(separator: "/").contains("..") }),
                  local.original != local.recovery else {
                throw NSError(domain: "OpenCommander.Cloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "cloud_undo_changed"])
            }
        }
        if let data = localCopyUndo {
            let record = try JSONDecoder().decode(FileUndoRecord.self, from: data)
            guard data.count <= 16 * 1024 * 1024, record.destination.isFileURL, record.destination.path != "/",
                  record.quarantinedSource == nil,
                  record.replacedBackup.map({ $0.isFileURL && $0.path != "/" && record.hasVerifiedRecoveryProof }) != false else {
                throw NSError(domain: "OpenCommander.Cloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "cloud_undo_changed"])
            }
        }
        guard ["relocate", "replacement", "remove", "crossMove", "localMove", "downloadMove"].contains(kind), !endpoint.isEmpty, !account.isEmpty,
            bounded(endpoint, limit: 512), bounded(account, limit: 1024), bounded(originalParent), bounded(originalParentPath),
            originalName.map(name) != false, objects.allSatisfy({ object in
                !object.id.isEmpty && bounded(object.id) && name(object.name) && bounded(object.path) && bounded(object.parent) && bounded(object.parentPath) &&
                !object.content.isEmpty && object.content.count <= 100_000 && object.content.allSatisfy({ path, digest in
                    bounded(path) && !path.hasPrefix("/") && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) &&
                    (digest == "directory" || (digest.hasPrefix("sha256:") && digest.utf8.count == 51))
                })
            }), kind != "replacement" || previous != nil,
            kind != "crossMove" || (sourceRestore != nil && sourceRestore?.recovery.content == current.content),
            kind != "localMove" || localSourceRestore != nil,
            kind != "downloadMove" || (localCopyUndo != nil && originalName != nil),
            kind != "relocate" || originalName != nil, try JSONEncoder().encode(self).count <= 16 * 1024 * 1024 else {
            throw NSError(domain: "OpenCommander.Cloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "cloud_undo_changed"])
        }
    }
}

/// Legacy audit entries remain readable; new optional fields support safe
/// remote Undo and localized failures without treating online paths as files.
struct CloudOperationRecord: Codable, Equatable {
    let action: String
    let source: String
    let destination: String
    var createdAt = Date()
    var actionKey: String? = nil
    var identifier: String? = nil
    var undo: CloudUndoPayload? = nil
    var status: String? = nil
    var failure: HistoryFailure? = nil
    var failureKey: String? = nil
    var failureMessage: String? { failureKey.map { L10n.get($0) } ?? failure?.message }
    var displayAction: String {
        if let actionKey { return L10n.get(actionKey) }
        // Match only established labels, not arbitrary provider error sentences.
        let keys = ["undo", "rename", "rename_button", "move_to_trash", "delete", "zip", "extract_archive", "duplicate", "remote_recovery", "folder", "copy", "move"]
        if let key = keys.first(where: { key in L10n.strings.values.contains { $0[key] == action } }) { return L10n.get(key) }
        return action
    }
}

enum OperationType: Codable {
    case delete(files: [FileUndoRecord])
    case move(files: [FileUndoRecord])
    case copy(files: [FileUndoRecord])
    case zip(record: FileUndoRecord)
    case rename(record: FileUndoRecord)
    case cloud(record: CloudOperationRecord)
}

/// Presentation only: never truncate the persistent audit or change Undo IDs.
enum HistoryPaging {
    static func indices(count: Int, page: Int, size: Int = 50) -> [Int] {
        guard count > 0 else { return [] }
        let size = max(1, min(100, size))
        let pages = (count - 1) / size + 1
        let page = max(0, min(pages - 1, page))
        let upper = count - page * size
        return Array((max(0, upper - size)..<upper).reversed())
    }
}

/// Desktop selection rules mirror the Linux context menu and ZIP toolbar.
enum DesktopInteractionPolicy {
    /// Tree identity only: Foundation deliberately shortens /private/tmp to
    /// /tmp even after resolvingSymlinksInPath, which breaks parent matching.
    /// Do not use this spelling for a displayed path or a transfer destination.
    static func treePath(_ url: URL) -> String {
        guard let pointer = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(pointer) }
        return String(cString: pointer)
    }
    static func selection(clicked: String, visible: [String], selected: Set<String>, anchor: String?,
                          extend: Bool, toggle: Bool) -> (keys: Set<String>, anchor: String?) {
        guard let end = visible.firstIndex(of: clicked) else { return (selected, anchor) }
        if extend {
            let start = anchor.flatMap { visible.firstIndex(of: $0) } ?? end
            let range = Set(visible[min(start, end)...max(start, end)])
            return (toggle ? selected.union(range) : range, visible[start])
        }
        if toggle {
            var keys = selected
            if keys.contains(clicked) { keys.remove(clicked) } else { keys.insert(clicked) }
            return (keys, clicked)
        }
        return ([clicked], clicked)
    }
    static func contextSelection(clicked: String, selected: Set<String>) -> Set<String> {
        selected.contains(clicked) ? selected : [clicked]
    }

    static func showsExtraction(archiveContext: Bool, selectedArchives: [Bool]) -> Bool {
        archiveContext || (!selectedArchives.isEmpty && selectedArchives.allSatisfy { $0 })
    }
}

/// Reject unsafe/ambiguous ZIP names before creating any output. Limits match
/// the Linux desktop implementation and also apply to preview materialization.
struct SafeArchiveLimits {
    static let maximumEntries = 100_000
    static let maximumBytes: UInt64 = 4 * 1024 * 1024 * 1024
    private var paths = Set<String>()
    private var bytes: UInt64 = 0

    /// Compare validated lexical components. standardizedFileURL may resolve
    /// /private/tmp and append directory slashes differently for an existing
    /// staging root and its not-yet-existing child on Mac Catalyst.
    static func outputURL(for path: String, in root: URL) throws -> URL {
        var validation = SafeArchiveLimits()
        try validation.include(path: path, size: 0, symbolicLink: false)
        guard root.isFileURL else { throw CocoaError(.fileReadCorruptFile) }
        let output = root.appendingPathComponent(path)
        let parent = root.pathComponents.filter { $0 != "/" }
        let child = output.pathComponents.filter { $0 != "/" }
        guard child.count > parent.count, Array(child.prefix(parent.count)) == parent else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "archive output path confinement"])
        }
        return output
    }

    mutating func include(path: String, size: UInt64, symbolicLink: Bool) throws {
        let name = path.hasSuffix("/") ? String(path.dropLast()) : path
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !symbolicLink, !name.isEmpty, !name.hasPrefix("/"),
              !name.contains("\\"), !name.contains("\0"),
              !parts.contains(".."), !parts.contains("."), !parts.contains(""),
              !(parts.first?.contains(":") ?? false),
              paths.count < Self.maximumEntries, size <= Self.maximumBytes - bytes,
              paths.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
            throw NSError(domain: "OpenCommander.ZIP", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.get("extract_unsafe")])
        }
        bytes += size
    }
}

/// Metadata only: never extracts archive contents or confuses a selected member
/// with the size/date of the physical container. Implicit directories are valid.
struct CommanderArchiveProperties {
    struct Member {
        let path: String
        let directory: Bool
        let size: Int64
        let compressed: Int64?
        let modified: Date?
    }
    let size: Int64
    let compressed: Int64?
    let modified: Date?
    let entries: Int?
    let wallClockTimestamp: Bool

    init(member: String, directory: Bool, members: [Member], wallClockTimestamp: Bool = false) throws {
        self.wallClockTimestamp = wallClockTimestamp
        guard members.count <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
        guard Set(members.map(\.path)).count == members.count else { throw CocoaError(.fileReadCorruptFile) }
        if directory {
            let prefix = member.isEmpty ? "" : member.hasSuffix("/") ? member : member + "/"
            let selected = members.filter { $0.path == prefix || $0.path.hasPrefix(prefix) }
            guard member.isEmpty || !selected.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            var total: Int64 = 0
            for item in selected where !item.directory {
                let next = total.addingReportingOverflow(item.size)
                guard item.size >= 0, !next.overflow else { throw CocoaError(.fileReadCorruptFile) }
                total = next.partialValue
            }
            size = total; compressed = nil; modified = selected.first(where: { $0.path == prefix })?.modified
            entries = selected.count
        } else {
            guard !member.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            let selected = members.filter { $0.path == member }
            guard selected.count == 1, let item = selected.first, !item.directory, item.size >= 0,
                  item.compressed == nil || item.compressed! >= 0 else { throw CocoaError(.fileReadCorruptFile) }
            size = item.size; compressed = item.compressed; modified = item.modified; entries = nil
        }
    }

    var extraDescription: String {
        if let entries {
            return L10n.get("properties_archive_contents") + ": " + CommanderFileProperties.byteDescription(size)
                + "\n" + L10n.get("properties_archive_entries") + ": \(entries)"
        }
        return L10n.get("properties_compressed") + ": "
            + (compressed.map(CommanderFileProperties.byteDescription) ?? L10n.get("properties_unknown"))
            + (wallClockTimestamp ? "\n\n" + L10n.get("properties_zip_timestamp_note") : "")
    }

    var modifiedDescription: String {
        guard let modified else { return L10n.get("properties_unknown") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.currentLanguage)
        formatter.dateStyle = .medium; formatter.timeStyle = .medium
        // ZIPFoundation decodes DOS wall-clock fields through timegm(), not an
        // actual UTC instant. Applying the viewer timezone a second time is wrong.
        if wallClockTimestamp { formatter.timeZone = TimeZone(secondsFromGMT: 0) }
        return formatter.string(from: modified)
    }

    static func storedZIPColumnDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// A fresh, non-recursive snapshot of the selected entry, not a symlink's target.
/// A failed metadata read remains unknown; it must never become zero or “No”.
struct CommanderFileProperties {
    static func byteDescription(_ value: Int64) -> String {
        if value < 1024 { return "\(value) B" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file) + " (\(value) B)"
    }
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64?
    let created: Date?
    let modified: Date?
    let accessed: Date?
    let permissions: String?
    let owner: String?
    let group: String?
    let linkTarget: String?
    let readable: Bool?
    let writable: Bool?
    let filesystem: String?
    let readOnly: Bool?
    let capacity: Int64?
    let available: Int64?

    init(at url: URL) {
        self.url = url
        var info = stat()
        let exists = url.withUnsafeFileSystemRepresentation { pointer in
            pointer.map { lstat($0, &info) == 0 } ?? false
        }
        isSymbolicLink = exists && (info.st_mode & S_IFMT) == S_IFLNK
        isDirectory = exists && (info.st_mode & S_IFMT) == S_IFDIR
        size = exists && !isDirectory ? Int64(info.st_size) : nil
        func date(_ value: timespec) -> Date? {
            guard exists, value.tv_sec != 0 || value.tv_nsec != 0 else { return nil }
            return Date(timeIntervalSince1970: Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000)
        }
        created = date(info.st_birthtimespec)
        modified = date(info.st_mtimespec)
        accessed = date(info.st_atimespec)
        permissions = exists ? String(format: "%04o", info.st_mode & 0o7777) : nil
        let attributes = exists ? try? FileManager.default.attributesOfItem(atPath: url.path) : nil
        owner = exists ? attributes?[.ownerAccountName] as? String ?? String(info.st_uid) : nil
        group = exists ? attributes?[.groupOwnerAccountName] as? String ?? String(info.st_gid) : nil
        linkTarget = isSymbolicLink ? try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil
        // access() follows links, so don't mislabel target access as link access.
        readable = exists && !isSymbolicLink ? url.withUnsafeFileSystemRepresentation { $0.map { access($0, R_OK) == 0 } } : nil
        writable = exists && !isSymbolicLink ? url.withUnsafeFileSystemRepresentation { $0.map { access($0, W_OK) == 0 } } : nil
        let volumeURL = isSymbolicLink ? url.deletingLastPathComponent() : url
        let volume = exists ? try? volumeURL.resourceValues(forKeys: [.volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeIsReadOnlyKey]) : nil
        readOnly = volume?.volumeIsReadOnly
        capacity = volume?.volumeTotalCapacity.map(Int64.init)
        available = volume?.volumeAvailableCapacity.map(Int64.init)
        var volumeInfo = statfs()
        let hasVolume = exists && volumeURL.withUnsafeFileSystemRepresentation { pointer in
            pointer.map { statfs($0, &volumeInfo) == 0 } ?? false
        }
        filesystem = hasVolume ? withUnsafeBytes(of: &volumeInfo.f_fstypename) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        } : nil
    }

    var extraDescription: String {
        let unknown = L10n.get("properties_unknown")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.currentLanguage)
        formatter.dateStyle = .medium; formatter.timeStyle = .medium
        func boolean(_ value: Bool?) -> String { value.map { L10n.get($0 ? "properties_yes" : "properties_no") } ?? unknown }
        func bytes(_ value: Int64?) -> String { value.map(Self.byteDescription) ?? unknown }
        var rows: [(String, String)] = [
            ("properties_uri", url.absoluteString),
            ("properties_accessed", accessed.map(formatter.string) ?? unknown),
            ("properties_owner", owner ?? unknown), ("properties_group", group ?? unknown),
            ("properties_readable", boolean(readable)), ("properties_writable", boolean(writable)),
            ("properties_filesystem", filesystem ?? unknown), ("properties_readonly", boolean(readOnly)),
            ("properties_capacity", bytes(capacity)), ("properties_available", bytes(available))]
        if isSymbolicLink { rows.append(("properties_link_target", linkTarget ?? unknown)) }
        return rows.map { L10n.get($0.0) + ": " + $0.1 }.joined(separator: "\n") + "\n\n" + L10n.get("properties_provider_note")
    }
}

enum BoundedFolderSize {
    struct Report {
        var bytes: Int64 = 0
        var entries = 0
        var errors = 0
        var limit: String?
        var complete: Bool { errors == 0 && limit == nil }
        var summary: String {
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            if complete { return size }
            return String(format: L10n.get("folder_size_partial"), size, entries, errors,
                          limit.map { L10n.get($0) } ?? L10n.get("folder_size_read_errors"))
        }
    }

    /// Interactive properties may report a lower bound. Transfer verification
    /// continues to use the throwing, all-or-nothing `bytes` function below.
    static func report(at root: URL, timeout: TimeInterval = 10, maximumEntries: Int = 100_000) -> Report {
        var result = Report()
        let start = ProcessInfo.processInfo.systemUptime
        func withinBudget() -> Bool {
            if ProcessInfo.processInfo.systemUptime - start >= timeout {
                result.limit = "folder_size_time_limit"; return false
            }
            return true
        }
        guard withinBudget() else { return result }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let rootValues = try? root.resourceValues(forKeys: keys),
              rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            result.errors = 1; return result
        }
        guard let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, _ in result.errors += 1; return withinBudget() }) else {
            result.errors += 1; return result
        }
        while withinBudget(), let url = items.nextObject() as? URL {
            guard result.entries < maximumEntries else { result.limit = "folder_size_entry_limit"; break }
            result.entries += 1
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true, isRecoveryName(url.lastPathComponent) {
                    items.skipDescendants(); continue
                }
                if values.isRegularFile == true {
                    guard let size = values.fileSize, size >= 0 else { result.errors += 1; continue }
                    let sum = result.bytes.addingReportingOverflow(Int64(size))
                    guard !sum.overflow else { result.limit = "folder_size_overflow"; break }
                    result.bytes = sum.partialValue
                }
            } catch { result.errors += 1 }
        }
        return result
    }

    static func bytes(at root: URL, timeout: TimeInterval = 10, maximumEntries: Int = 100_000, excludingRecovery: Bool = false) throws -> Int64 {
        let deadline = Date().addingTimeInterval(timeout)
        var total: Int64 = 0
        var count = 0
        var enumerationError: Error?
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        for case let url as URL in items {
            let values = try url.resourceValues(forKeys: keys)
            if excludingRecovery, values.isDirectory == true, values.isSymbolicLink != true, isRecoveryName(url.lastPathComponent) {
                items.skipDescendants()
                continue
            }
            count += 1
            guard count <= maximumEntries, Date() < deadline else { throw CocoaError(.userCancelled) }
            // DirectoryEnumerator does not descend through symlinks. Calling
            // skipDescendants on a leaf can instead skip the next real directory.
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true {
                let sum = total.addingReportingOverflow(Int64(values.fileSize ?? 0))
                guard !sum.overflow else { throw CocoaError(.fileReadTooLarge) }
                total = sum.partialValue
            }
        }
        if let enumerationError { throw enumerationError }
        return total
    }
    static func isRecoveryName(_ name: String) -> Bool {
        [".OpenCommanderExclusive-", ".OpenCommanderJob-", ".OpenCommanderTransfer-", ".OpenCommanderMoved-", ".OpenCommanderUndo-", ".OpenCommanderExtract-", ".OpenCommander-transfer-"].contains {
            name.hasPrefix($0) && UUID(uuidString: String(name.dropFirst($0.count))) != nil
        }
    }
}

/// Thread-safe cooperative cancellation. Partial copies exist only in staging.
final class FileOperationCancellation {
    private let lock = NSLock()
    private var requested = false
    func reset() { lock.lock(); requested = false; lock.unlock() }
    func cancel() { lock.lock(); requested = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return requested }
    func check() throws { if isCancelled { throw CocoaError(.userCancelled) } }

    func copy(_ source: URL, _ destination: URL) throws {
        try check()
        guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { _, _, _, _, _, context in
            guard let context else { return COPYFILE_QUIT }
            return Unmanaged<FileOperationCancellation>.fromOpaque(context).takeUnretainedValue().isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(self).toOpaque())
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW_SRC | COPYFILE_EXCL)
        guard copyfile(source.path, destination.path, state, flags) == 0 else {
            try check()
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try check()
    }
}

/// File operations kept separate from UIKit so failure paths can be tested with fixtures.
enum SafeFileOperations {
    static func clipboardSourcesAvailable(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { $0.isFileURL && exists($0) }
    }
    static func exists(_ url: URL) -> Bool {
        // Includes dangling symlinks: these are still occupied destination names.
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Same-directory rename, including case-only changes on case-insensitive
    /// volumes. Never use an overwriting POSIX rename or a two-hop temporary
    /// name: the latter leaves the original name lost across process failure.
    static func renameEntry(_ source: URL, to destination: URL) throws {
        guard source.isFileURL, destination.isFileURL,
              source.deletingLastPathComponent().standardizedFileURL == destination.deletingLastPathComponent().standardizedFileURL,
              !["", ".", ".."].contains(destination.lastPathComponent) else { throw CocoaError(.fileWriteInvalidFileName) }
        if source.path == destination.path { return }
        let fm = FileManager.default
        // Two distinct hard links can share an inode. Their existing spelling
        // must still be a conflict, not mistaken for a case-only alias.
        if try fm.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path).contains(destination.lastPathComponent) {
            throw CocoaError(.fileWriteFileExists)
        }
#if os(macOS) || targetEnvironment(macCatalyst)
        // APFS permits an atomic case-only rename with RENAME_EXCL while
        // refusing a target introduced after the directory preflight.
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
#else
        try fm.moveItem(at: source, to: destination)
#endif
    }

    static func conflict(_ url: URL) -> NSError {
        NSError(domain: "OpenCommander.FileSafety", code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.get("undo_changed") + "\n" + url.path])
    }

    /// Provider reconciliation may replace an inode without changing the file.
    /// Restrict the relaxed identity format to known per-user provider roots.
    static func providerLocation(_ url: URL, home: URL? = nil) -> Bool {
        let userHome = home ?? getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir)) }
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return ["Library/CloudStorage", "Library/Mobile Documents"].contains { component in
            let root = userHome.appendingPathComponent(component).resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(root + "/")
        }
    }

    static func snapshot(_ url: URL, rootName: String? = nil, contentOnly: Bool = false, providerIdentity: Bool = false,
                         progress: ((Int64) -> Void)? = nil, checkCancellation: () throws -> Void = {}) throws -> Data {
        let fm = FileManager.default
        var digest = SHA256()
        var bytesRead: Int64 = 0
        progress?(0)
        func field(_ string: String) {
            let data = Data(string.utf8)
            digest.update(data: Data("\(data.count):".utf8))
            digest.update(data: data)
        }
        func visit(_ item: URL) throws {
            try checkCancellation()
            var attributes = try fm.attributesOfItem(atPath: item.path)
            guard let type = attributes[.type] as? FileAttributeType else { throw conflict(item) }
            // Open before recording metadata. SMB can replace speculative cached
            // attributes on the first server open. Keep the same descriptor open
            // through verification instead of comparing pre-open and post-close
            // caches. O_NOFOLLOW also rejects a raced-in link.
            var input: FileHandle?
            var openedInfo = stat()
            if type == .typeRegular {
                let fd = open(item.path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { throw conflict(item) }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                guard fstat(fd, &openedInfo) == 0, openedInfo.st_mode & S_IFMT == S_IFREG else {
                    try? handle.close(); throw conflict(item)
                }
                input = handle
                attributes = try fm.attributesOfItem(atPath: item.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw conflict(item) }
            }
            defer { try? input?.close() }
            field(item == url ? (rootName ?? item.lastPathComponent) : item.lastPathComponent)
            field(type.rawValue)
            if !contentOnly {
                if providerIdentity { field(String(describing: attributes[.systemNumber])) }
                else { field(String(describing: attributes[.systemFileNumber])) }
                field(String((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0))
                for key in [FileAttributeKey.posixPermissions, .ownerAccountID, .groupOwnerAccountID] {
                    field(String(describing: attributes[key]))
                }
            }
            if type == .typeDirectory {
                let children = try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                field(String(children.count))
                for child in children { try visit(child) }
            } else if type == .typeSymbolicLink {
                field(try fm.destinationOfSymbolicLink(atPath: item.path))
            } else if type == .typeRegular {
                var content = SHA256()
                guard let handle = input else { throw conflict(item) }
                while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
                    try checkCancellation()
                    content.update(data: data)
                    bytesRead += Int64(data.count); progress?(bytesRead)
                }
                digest.update(data: Data(content.finalize()))
            } else {
                throw conflict(item)
            }
            // Even provider proofs must reject replacement or mutation during
            // verification; inode relaxation applies only between snapshots.
            let after = try fm.attributesOfItem(atPath: item.path)
            if let input {
                var finished = stat()
                guard fstat(input.fileDescriptor, &finished) == 0,
                      openedInfo.st_dev == finished.st_dev, openedInfo.st_ino == finished.st_ino,
                      openedInfo.st_size == finished.st_size,
                      openedInfo.st_mtimespec.tv_sec == finished.st_mtimespec.tv_sec,
                      openedInfo.st_mtimespec.tv_nsec == finished.st_mtimespec.tv_nsec else { throw conflict(item) }
            }
            for key in [FileAttributeKey.systemNumber, .systemFileNumber, .type, .size,
                        .modificationDate, .posixPermissions, .ownerAccountID, .groupOwnerAccountID] {
                guard String(describing: attributes[key]) == String(describing: after[key]) else { throw conflict(item) }
            }
        }
        try visit(url)
        try checkCancellation()
        return Data(digest.finalize())
    }

    /// File Providers may discard internal staging names during reconciliation.
    /// Keep an independently verified previous version outside the sync domain.
    static func privateRecoveryRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let root = support.appendingPathComponent("OpenCommander/CloudRecovery", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return root
    }

    /// Finish copying before displacing the old target. Staging is on the target volume.
    static func copyReplacing(source: URL, destination: URL, replace: Bool, recoveryRoot: URL? = nil,
                              copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
                              publish: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws -> URL? {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".OpenCommanderTransfer-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        let payload = staging.appendingPathComponent("payload")
        let displacedTarget = staging.appendingPathComponent("previous")
        var backup = displacedTarget
        var displaced = false
        var keepRecovery = false
        defer {
            if !keepRecovery { try? fm.removeItem(at: staging) }
        }
        do {
            try copy(source, payload)
            if exists(destination) {
                guard replace else { throw conflict(destination) }
                let expectedContent = try snapshot(destination, rootName: "previous", contentOnly: true)
                if let recoveryRoot {
                    let original = try snapshot(destination)
                    let independent = recoveryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try fm.createDirectory(at: independent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    backup = independent.appendingPathComponent("previous")
                    try copy(destination, backup)
                    guard try snapshot(backup, contentOnly: true) == expectedContent,
                          try snapshot(destination) == original else { throw conflict(destination) }
                    // Never discard this verified recovery copy, including on failure.
                }
                try fm.moveItem(at: destination, to: displacedTarget)
                displaced = true
                guard exists(displacedTarget), exists(backup) else { throw conflict(destination) }
                guard try snapshot(displacedTarget, contentOnly: true) == expectedContent else { throw conflict(displacedTarget) }
            }
            try publish(payload, destination)
            keepRecovery = displaced
            return displaced ? backup : nil
        } catch {
            if displaced {
                // Never remove an unexpected destination just to restore the previous file.
                do {
                    guard !exists(destination) else { throw conflict(destination) }
                    if exists(displacedTarget) {
                        // Restore the actual displaced object, including any edit
                        // racing the final snapshot. Never discard that version.
                        try fm.moveItem(at: displacedTarget, to: destination)
                    } else if recoveryRoot != nil {
                        // Copy back; the independently verified backup remains recoverable.
                        try fm.copyItem(at: backup, to: destination)
                    } else { throw conflict(backup) }
                } catch let recoveryError {
                    keepRecovery = true
                    throw NSError(domain: "OpenCommander.FileSafety", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey:
                                    L10n.get("recovery_retained", staging.path) + "\n" + backup.path + "\n" + recoveryError.localizedDescription,
                                             NSUnderlyingErrorKey: error])
                }
            }
            throw error
        }
    }
}

/// Store stable error identity, not an OS sentence in the system language.
/// Render using the current app language, including after restarting/switching language.
struct HistoryFailure: Codable, Equatable {
    /// Present coded OS errors in the app's selected language, rather than
    /// leaking the host OS language or private configuration paths into alerts.
    static func presentation(_ error: Error) -> String {
        let value = error as NSError
        if [NSCocoaErrorDomain, NSPOSIXErrorDomain].contains(value.domain) { return HistoryFailure(error).message }
        if ["OpenCommander.Remote", "OpenCommander.Cloud"].contains(value.domain) { return L10n.get(value.localizedDescription) }
        return error.localizedDescription
    }
    let domain: String
    let code: Int
    init(_ error: Error) {
        let value = error as NSError
        domain = value.domain; code = value.code
    }
    var message: String {
        let key: String
        if domain == "OpenCommander.FileSafety" { key = "undo_changed" }
        else if domain == NSCocoaErrorDomain {
            switch code {
            case 4, 260: key = "history_error_missing"
            case 257, 513: key = "history_error_permission"
            case 516: key = "history_error_exists"
            case 640: key = "history_error_space"
            case 3072: key = "history_error_cancelled"
            default: key = "history_error_generic"
            }
        } else if domain == NSPOSIXErrorDomain {
            switch Int32(code) {
            case ENOENT: key = "history_error_missing"
            case EACCES, EPERM, EROFS: key = "history_error_permission"
            case EEXIST, ENOTEMPTY: key = "history_error_exists"
            case ENOSPC: key = "history_error_space"
            case ECANCELED: key = "history_error_cancelled"
            default: key = "history_error_generic"
            }
        } else { key = "history_error_generic" }
        return L10n.get(key)
    }
}

final class FileUndoRecord: Codable {
    let createdAt: Date
    let source: URL
    var displaySource: String? = nil
    /// Optional for backward-compatible decoding of histories written before folder Undo.
    private(set) var createdDirectory: Bool? = nil
    let destination: URL
    let replacedBackup: URL?
    let quarantinedSource: URL?
    private var backupSnapshot: Data? = nil
    private var backupVerificationRequired: Bool? = nil
    private let quarantineSnapshot: Data?
    private let snapshot: Data?
    private var providerIdentity: Bool? = nil
    private var destinationReverted = false
    private var restorePublished: Bool? = nil
    private var nasRestoreStage: String? = nil
    private var nasMoveRestoreStage: String? = nil
    private(set) var completed = false
    private(set) var renameBatchID: UUID? = nil
    private(set) var renameEntryID: UUID? = nil
    var lastError: String?
    var lastFailure: HistoryFailure?
    var historyErrorMessage: String? {
        if let lastFailure { return lastFailure.message }
        // Legacy histories contain only a language-frozen OS sentence. Without
        // an error code do not guess the cause or expose English as German UI.
        return lastError == nil ? nil : L10n.get("history_error_legacy")
    }
    func setHistoryError(_ error: Error) {
        lastFailure = HistoryFailure(error)
        lastError = nil
    }

    init(source: URL, destination: URL, replacedBackup: URL?, quarantinedSource: URL? = nil, createdDirectory: Bool = false,
         expectedRenameSnapshot: Data? = nil, renameBatchID: UUID? = nil, renameEntryID: UUID? = nil) {
        createdAt = Date()
        self.source = source
        self.destination = destination
        self.replacedBackup = replacedBackup
        self.quarantinedSource = quarantinedSource
        self.createdDirectory = createdDirectory ? true : nil
        self.renameBatchID = renameBatchID; self.renameEntryID = renameEntryID
        backupVerificationRequired = replacedBackup != nil
        backupSnapshot = replacedBackup.flatMap { try? SafeFileOperations.snapshot($0, contentOnly: true) }
        quarantineSnapshot = quarantinedSource.flatMap { try? SafeFileOperations.snapshot($0) }
        // A read failure disables undo; it must never roll back an already completed move.
        providerIdentity = SafeFileOperations.providerLocation(destination)
        snapshot = expectedRenameSnapshot ?? (try? SafeFileOperations.snapshot(destination, providerIdentity: providerIdentity == true))
    }

    func verifyUnchangedDestination(checkCancellation: () throws -> Void = {}) throws {
        guard !completed, !destinationReverted else { throw SafeFileOperations.conflict(destination) }
        if providerIdentity == true, !SafeFileOperations.providerLocation(destination) { throw SafeFileOperations.conflict(destination) }
        guard let snapshot, snapshot == (try SafeFileOperations.snapshot(destination, providerIdentity: providerIdentity == true, checkCancellation: checkCancellation)) else {
            throw SafeFileOperations.conflict(destination)
        }
    }

    var hasVerifiedRecoveryProof: Bool { backupVerificationRequired == true && backupSnapshot != nil }
    func matchesRenameProof(_ proof: Data) -> Bool {
        snapshot == proof && replacedBackup == nil && quarantinedSource == nil && createdDirectory != true &&
            !completed && !destinationReverted && restorePublished != true
    }
    func sameRenameIntent(as other: FileUndoRecord) -> Bool {
        renameBatchID == other.renameBatchID && renameEntryID == other.renameEntryID &&
            source == other.source && destination == other.destination && snapshot == other.snapshot
    }

    func verifyRecovery(checkCancellation: () throws -> Void = {}) throws {
        // Check recovery before displacing the current version. A missing cloud
        // backup must leave the visible destination completely untouched.
        if let backup = replacedBackup {
            if backupVerificationRequired == true, backupSnapshot == nil { throw SafeFileOperations.conflict(backup) }
            let current = try SafeFileOperations.snapshot(backup, contentOnly: true, checkCancellation: checkCancellation)
            if let backupSnapshot, current != backupSnapshot { throw SafeFileOperations.conflict(backup) }
        }
    }

    func undo(move: Bool, checkCancellation: () throws -> Void = {}, didRestore: (() throws -> Void)? = nil) throws {
        if completed { try didRestore?(); return }
        try checkCancellation()
        let fm = FileManager.default
        try verifyRecovery(checkCancellation: checkCancellation)
        if !destinationReverted {
            try verifyUnchangedDestination(checkCancellation: checkCancellation)
            try checkCancellation()
            var restoredNASMove = false
            #if OPENCOMMANDER_NAS || targetEnvironment(macCatalyst)
            if move, let original = quarantinedSource,
               NASExclusiveCopy.isSMB(source.deletingLastPathComponent()) || NASExclusiveCopy.isSMB(destination.deletingLastPathComponent()) {
                guard let quarantineSnapshot,
                      try SafeFileOperations.snapshot(original, checkCancellation: checkCancellation) == quarantineSnapshot else { throw SafeFileOperations.conflict(original) }
                if nasMoveRestoreStage == nil {
                    nasMoveRestoreStage = try NASExclusiveCopy.create(source: original, target: source,
                        journalParent: source.deletingLastPathComponent()).path
                }
                let state = try NASExclusiveCopy.resume(URL(fileURLWithPath: nasMoveRestoreStage!), control: {
                    do { try checkCancellation(); return .proceed } catch { return .pause }
                })
                guard state == .completed else { throw CocoaError(.userCancelled) }
                // Retain both recovery versions. Never restore onto a public
                // source name with an overwriting Foundation rename on SMB.
                try verifyUnchangedDestination(checkCancellation: checkCancellation)
                let recovery = destination.deletingLastPathComponent().appendingPathComponent(".OpenCommanderUndo-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: recovery, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try fm.moveItem(at: destination, to: recovery.appendingPathComponent(destination.lastPathComponent))
                restoredNASMove = true
            }
            #endif
            if restoredNASMove {
                destinationReverted = true
            } else {
            if move {
                if quarantinedSource == nil, replacedBackup == nil,
                   source.deletingLastPathComponent().standardizedFileURL == destination.deletingLastPathComponent().standardizedFileURL {
                    try SafeFileOperations.renameEntry(destination, to: source)
                } else {
                guard !SafeFileOperations.exists(source) else { throw SafeFileOperations.conflict(source) }
                if let original = quarantinedSource {
                    guard let quarantineSnapshot, try SafeFileOperations.snapshot(original, checkCancellation: checkCancellation) == quarantineSnapshot else { throw SafeFileOperations.conflict(original) }
                    let recovery = destination.deletingLastPathComponent().appendingPathComponent(".OpenCommanderUndo-\(UUID().uuidString)", isDirectory: true)
                    try fm.createDirectory(at: recovery, withIntermediateDirectories: false)
                    let retained = recovery.appendingPathComponent(destination.lastPathComponent)
                    try fm.moveItem(at: destination, to: retained)
                    do { try fm.moveItem(at: original, to: source) }
                    catch {
                        if !SafeFileOperations.exists(destination) { try? fm.moveItem(at: retained, to: destination) }
                        throw error
                    }
                } else { try fm.moveItem(at: destination, to: source) }
                }
            } else {
                // Retain the current version even if an external writer raced the snapshot.
                let recovery = destination.deletingLastPathComponent()
                    .appendingPathComponent(".OpenCommanderUndo-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: recovery, withIntermediateDirectories: false)
                try fm.moveItem(at: destination, to: recovery.appendingPathComponent(destination.lastPathComponent))
            }
            destinationReverted = true
            }
        }
        if let backup = replacedBackup {
            try checkCancellation()
            if restorePublished != true {
                #if OPENCOMMANDER_NAS || targetEnvironment(macCatalyst)
                if NASExclusiveCopy.isSMB(destination.deletingLastPathComponent()) {
                    if nasRestoreStage == nil {
                        nasRestoreStage = try NASExclusiveCopy.create(source: backup, target: destination,
                            journalParent: destination.deletingLastPathComponent()).path
                    }
                    let outcome = try NASExclusiveCopy.resume(URL(fileURLWithPath: nasRestoreStage!), control: {
                        do { try checkCancellation(); return .proceed } catch { return .pause }
                    })
                    guard outcome == .completed else { throw CocoaError(.userCancelled) }
                } else {
                    guard !SafeFileOperations.exists(destination) else { throw SafeFileOperations.conflict(destination) }
                    try fm.copyItem(at: backup, to: destination)
                }
                #else
                guard !SafeFileOperations.exists(destination) else { throw SafeFileOperations.conflict(destination) }
                // A provider can acknowledge a move before reconciliation. Keep
                // the backup until restored bytes have been read back successfully.
                try fm.copyItem(at: backup, to: destination)
                #endif
                restorePublished = true
            }
            guard try SafeFileOperations.snapshot(destination, rootName: backup.lastPathComponent, contentOnly: true,
                checkCancellation: checkCancellation) == SafeFileOperations.snapshot(backup, contentOnly: true,
                checkCancellation: checkCancellation) else { throw SafeFileOperations.conflict(destination) }
        }
        try didRestore?()
        completed = true
    }
}
