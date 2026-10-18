import Foundation
import CryptoKit
import Darwin

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
        init(_ source: URL) throws {
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
                let filters = try symbol("archive_read_support_filter_all", (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
                let formats = try symbol("archive_read_support_format_all", (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
                let open = try symbol("archive_read_open_filename", (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Int32).self)
                guard let archive = create() else { throw CocoaError(.fileReadUnknown) }
                guard filters(archive) == 0, formats(archive) == 0,
                      source.path.withCString({ open(archive, $0, 64 * 1024) }) == 0 else {
                    _ = release(archive); throw CocoaError(.fileReadCorruptFile)
                }
                self.archive = archive; self.library = library
            } catch { dlclose(library); throw error }
        }
        deinit { _ = release(archive); dlclose(library) }
        func member(_ entry: UnsafeMutableRawPointer) throws -> Member? {
            guard let pointer = pathname(entry), var path = String(validatingUTF8: pointer) else { throw CocoaError(.fileReadCorruptFile) }
            let directory = filetype(entry) == UInt32(S_IFDIR)
            guard [UInt32(S_IFREG), UInt32(S_IFDIR)].contains(filetype(entry)),
                  symlink(entry) == nil, hardlink(entry) == nil, encrypted(entry) == 0, size(entry) >= 0,
                  !directory || size(entry) == 0 else {
                throw CocoaError(.fileReadCorruptFile)
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
        let reader = try Reader(source)
        var result: [Member] = [], limits = SafeArchiveLimits()
        while true {
            try checkCancellation()
            var entry: UnsafeMutableRawPointer?
            let status = reader.next(reader.archive, &entry)
            if status == 1 { break }
            guard status == 0, let entry else { throw CocoaError(.fileReadCorruptFile) }
            if let member = try reader.member(entry) {
                try limits.include(path: member.path, size: UInt64(member.size), symbolicLink: false)
                result.append(member)
            }
            guard reader.skip(reader.archive) == 0 else { throw CocoaError(.fileReadCorruptFile) }
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
            let reader = try Reader(source)
            let expected = Dictionary(uniqueKeysWithValues: all.map { ($0.path, $0) })
            var seen = Set<String>(), completed = 0, total: UInt64 = 0
            let wanted = Set(selected.map(\.path))
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try checkCancellation()
                var entry: UnsafeMutableRawPointer?
                let status = reader.next(reader.archive, &entry)
                if status == 1 { break }
                guard status == 0, let entry else { throw CocoaError(.fileReadCorruptFile) }
                guard let member = try reader.member(entry) else { continue }
                guard expected[member.path] == member, seen.insert(member.path).inserted else { throw CocoaError(.fileReadCorruptFile) }
                if !wanted.contains(member.path) {
                    guard reader.skip(reader.archive) == 0 else { throw CocoaError(.fileReadCorruptFile) }; continue
                }
                let output = destination.appendingPathComponent(member.path)
                guard output.standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path + "/") else { throw CocoaError(.fileReadCorruptFile) }
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
                        guard count >= 0 else { throw CocoaError(.fileReadCorruptFile) }
                        if count == 0 { break }
                        guard UInt64(count) <= UInt64(member.size) - written, UInt64(count) <= maximumBytes - total else { throw CocoaError(.fileReadTooLarge) }
                        try handle.write(contentsOf: Data(buffer.prefix(count)))
                        written += UInt64(count); total += UInt64(count)
                    }
                    guard written == UInt64(member.size) else { throw CocoaError(.fileReadCorruptFile) }
                    try handle.synchronize()
                    if member.modified > 0 { try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(member.modified) / 1000)], ofItemAtPath: output.path) }
                }
                completed += 1; progress(completed, selected.count)
            }
            guard seen == Set(expected.keys), completed == selected.count else { throw CocoaError(.fileReadCorruptFile) }
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
                  record.replacedBackup == nil, record.quarantinedSource == nil else {
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

/// Desktop selection rules mirror the Linux context menu and ZIP toolbar.
enum DesktopInteractionPolicy {
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

enum BoundedFolderSize {
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
        [".OpenCommanderJob-", ".OpenCommanderTransfer-", ".OpenCommanderMoved-", ".OpenCommanderUndo-", ".OpenCommanderExtract-", ".OpenCommander-transfer-"].contains {
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
    static func exists(_ url: URL) -> Bool {
        // Includes dangling symlinks: these are still occupied destination names.
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
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
            let attributes = try fm.attributesOfItem(atPath: item.path)
            guard let type = attributes[.type] as? FileAttributeType else { throw conflict(item) }
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
                let handle = try FileHandle(forReadingFrom: item)
                defer { try? handle.close() }
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
    private(set) var completed = false
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

    init(source: URL, destination: URL, replacedBackup: URL?, quarantinedSource: URL? = nil) {
        createdAt = Date()
        self.source = source
        self.destination = destination
        self.replacedBackup = replacedBackup
        self.quarantinedSource = quarantinedSource
        backupVerificationRequired = replacedBackup != nil
        backupSnapshot = replacedBackup.flatMap { try? SafeFileOperations.snapshot($0, contentOnly: true) }
        quarantineSnapshot = quarantinedSource.flatMap { try? SafeFileOperations.snapshot($0) }
        // A read failure disables undo; it must never roll back an already completed move.
        providerIdentity = SafeFileOperations.providerLocation(destination)
        snapshot = try? SafeFileOperations.snapshot(destination, providerIdentity: providerIdentity == true)
    }

    func verifyUnchangedDestination(checkCancellation: () throws -> Void = {}) throws {
        guard !completed, !destinationReverted else { throw SafeFileOperations.conflict(destination) }
        if providerIdentity == true, !SafeFileOperations.providerLocation(destination) { throw SafeFileOperations.conflict(destination) }
        guard let snapshot, snapshot == (try SafeFileOperations.snapshot(destination, providerIdentity: providerIdentity == true, checkCancellation: checkCancellation)) else {
            throw SafeFileOperations.conflict(destination)
        }
    }

    func undo(move: Bool, checkCancellation: () throws -> Void = {}) throws {
        if completed { return }
        try checkCancellation()
        let fm = FileManager.default
        // Check recovery before displacing the current version. A missing cloud
        // backup must leave the visible destination completely untouched.
        if let backup = replacedBackup {
            if backupVerificationRequired == true, backupSnapshot == nil { throw SafeFileOperations.conflict(backup) }
            let current = try SafeFileOperations.snapshot(backup, contentOnly: true, checkCancellation: checkCancellation)
            if let backupSnapshot, current != backupSnapshot { throw SafeFileOperations.conflict(backup) }
        }
        if !destinationReverted {
            try verifyUnchangedDestination(checkCancellation: checkCancellation)
            try checkCancellation()
            if move {
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
            } else {
                // Retain the current version even if an external writer raced the snapshot.
                let recovery = destination.deletingLastPathComponent()
                    .appendingPathComponent(".OpenCommanderUndo-\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: recovery, withIntermediateDirectories: false)
                try fm.moveItem(at: destination, to: recovery.appendingPathComponent(destination.lastPathComponent))
            }
            destinationReverted = true
        }
        if let backup = replacedBackup {
            try checkCancellation()
            if restorePublished != true {
                guard !SafeFileOperations.exists(destination) else { throw SafeFileOperations.conflict(destination) }
                // A provider can acknowledge a move before reconciliation. Keep
                // the backup until restored bytes have been read back successfully.
                try fm.copyItem(at: backup, to: destination)
                restorePublished = true
            }
            guard try SafeFileOperations.snapshot(destination, rootName: backup.lastPathComponent, contentOnly: true,
                checkCancellation: checkCancellation) == SafeFileOperations.snapshot(backup, contentOnly: true,
                checkCancellation: checkCancellation) else { throw SafeFileOperations.conflict(destination) }
        }
        completed = true
    }
}
