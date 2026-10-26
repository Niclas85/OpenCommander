import Foundation
import CryptoKit
import Darwin

/// Non-atomic, fail-closed publication for filesystems without exclusive rename.
/// New targets are visible while incomplete. Every target is created exclusively
/// and tagged before writing; pre-existing targets are never adopted or truncated.
/// Explicit replacement retains the old target in a private recovery directory.
enum NASExclusiveCopy {
    static func isConnectionFailure(_ error: Error) -> Bool {
        let value = error as NSError
        if value.domain == NSPOSIXErrorDomain && [ENOTCONN, ENETDOWN, ENETUNREACH, EHOSTDOWN, EHOSTUNREACH, ETIMEDOUT, ECONNRESET, ESTALE, EIO].contains(Int32(value.code)) { return true }
        return (value.userInfo[NSUnderlyingErrorKey] as? NSError).map { isConnectionFailure($0) } ?? false
    }
    private static func ioFailure(_ fallback: Failure) -> Error {
        let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        return isConnectionFailure(error) ? error : fallback
    }
    static func isSMB(_ url: URL) -> Bool {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return false }
        return withUnsafePointer(to: &info.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) == "smbfs" } }
    }
    static func summary(_ stage: URL) throws -> (bytes: Int64, total: Int64, backup: URL?, quarantine: URL?) {
        let value = try readJournal(stage)
        return (value.entries.reduce(0) { $0 + $1.offset }, value.entries.reduce(0) { $0 + $1.size },
                value.backupReady == true ? stage.appendingPathComponent("previous") : nil,
                value.state == .completed && value.move == true ? quarantine(value) : nil)
    }
    enum Failure: LocalizedError {
        case unsafePath, conflict, changedSource, changedTarget, invalidJournal, unsupported
        var errorDescription: String? {
            let german = L10n.currentLanguage.hasPrefix("de")
            switch self {
            case .unsafePath, .invalidJournal:
                return german ? "Der NAS-Pfad oder die Wiederherstellungsdaten konnten nicht sicher geprüft werden. Vorhandene Daten bleiben erhalten." : "The NAS path or recovery data could not be safely verified. Existing data was retained."
            case .conflict:
                return german ? "Das NAS-Ziel existiert bereits oder wird von einem anderen Vorgang verwendet. Es wurde nicht überschrieben." : "The NAS destination already exists or is owned by another operation. It was not overwritten."
            case .changedSource, .changedTarget:
                return german ? "Quelle oder NAS-Ziel wurden verändert. Die Übertragung wurde angehalten; Teilkopie und Sicherung bleiben erhalten." : "The source or NAS destination changed. Transfer stopped; partial copy and recovery data were retained."
            case .unsupported:
                return german ? "Das Ziellaufwerk kann diese Dateiart, Dateiattribute oder Sicherheitsmerkmale nicht vollständig erhalten. Die Quelldaten bleiben erhalten." : "The destination cannot fully preserve this item type, metadata or required safety features. Source data was retained."
            }
        }
    }
    enum Control { case proceed, pause, cancel }
    // Injected only by acceptance tests; production callers keep the no-op.
    enum Checkpoint { case wroteUncheckpointedBytes, retainedPrevious, retainedSource }
    enum State: String, Codable { case ready, backingUp, copying, paused, cancelled, moving, completed }
    struct Entry: Codable {
        let path: String
        let directory: Bool
        let size: Int64
        let digest: Data?
        var owned = false
        var offset: Int64 = 0
        var complete = false
        var metadata: Metadata?
        var metadataApplied: Bool?
    }
    struct Metadata: Codable, Equatable {
        var attributes: [String: Data]
        var modified: Int
        var modifiedNanos: Int
        var created: Int
        var createdNanos: Int
        var mode: UInt16
        var flags: UInt32
        var acl: String?
        var network: Bool
        var portableMode: Bool?
    }
    private static func metadata(_ fd: Int32, network: Bool) throws -> Metadata {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw Failure.changedSource }
        let length = flistxattr(fd, nil, 0, 0)
        guard length >= 0 else { throw ioFailure(.unsupported) }
        guard length <= 1024 * 1024 else { throw Failure.unsupported }
        var names = [CChar](repeating: 0, count: max(1, length)), values: [String: Data] = [:]
        guard flistxattr(fd, &names, length, 0) == length else { throw Failure.changedSource }
        var consumed = 0
        for nameBytes in names.prefix(length).split(separator: 0) {
            let name = String(decoding: nameBytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if name == marker || name == "com.opencommander.replace-lock" { continue }
            let size = fgetxattr(fd, name, nil, 0, 0, 0)
            guard size >= 0, size <= 16 * 1024 * 1024, consumed + size <= 32 * 1024 * 1024 else { throw Failure.unsupported }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { fgetxattr(fd, name, $0.baseAddress, $0.count, 0, 0) }
            guard read == size else { throw Failure.changedSource }
            values[name] = data; consumed += size
        }
        var aclText: String?
        if let acl = acl_get_fd(fd) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            if let text = acl_to_text(acl, nil) {
                defer { acl_free(text) }
                let value = String(cString: text)
                if value.split(separator: "\n").count > 1 { aclText = value }
            } else { throw Failure.unsupported }
        } else if errno != ENOTSUP && errno != ENOENT { throw Failure.unsupported }
        let savedMode = values.removeValue(forKey: "com.opencommander.posix-mode-v1")
        var mode = info.st_mode & 0o777, portable = false
        if network, let savedMode {
            guard savedMode.count <= 4, let text = String(data: savedMode, encoding: .utf8),
                  let saved = UInt16(text, radix: 8), saved <= 0o777 else { throw Failure.unsupported }
            mode = saved; portable = true
        }
        return Metadata(attributes: values, modified: info.st_mtimespec.tv_sec, modifiedNanos: info.st_mtimespec.tv_nsec,
                        created: info.st_birthtimespec.tv_sec, createdNanos: info.st_birthtimespec.tv_nsec,
                        mode: mode, flags: info.st_flags, acl: aclText, network: network, portableMode: portable)
    }
    private static func captureMetadata(_ url: URL) throws -> Metadata {
        var fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw ioFailure(.changedSource) }; defer { if fd >= 0 { close(fd) } }
        let network = isSMB(url)
        // Newly written SMB sources can still have lease-cached timestamps.
        // Flush the existing handle before accepting a metadata baseline; no
        // source bytes, permissions or timestamps are explicitly changed.
        if network { guard fsync(fd) == 0 else { throw ioFailure(.changedSource) } }
        var value = try metadata(fd, network: network)
        if network {
            var opened = stat(), refreshed = stat()
            guard fstat(fd, &opened) == 0 else { throw ioFailure(.changedSource) }
            close(fd); fd = -1
            // Read the pathname after closing the SMB handle as well: its
            // attribute cache may differ from the handle's. Content
            // is independently hashed again before any source is relocated.
            guard lstat(url.path, &refreshed) == 0, opened.st_dev == refreshed.st_dev,
                  opened.st_ino == refreshed.st_ino, opened.st_size == refreshed.st_size,
                  opened.st_mode & S_IFMT == refreshed.st_mode & S_IFMT else { throw Failure.changedSource }
            value.modified = refreshed.st_mtimespec.tv_sec; value.modifiedNanos = refreshed.st_mtimespec.tv_nsec
            value.created = refreshed.st_birthtimespec.tv_sec; value.createdNanos = refreshed.st_birthtimespec.tv_nsec
            value.flags = refreshed.st_flags
        }
        // SMB servers may synthesize the DOS hidden bit for every dotfile.
        // Its visibility is already preserved by the name; it is not a newly
        // added user flag or evidence of another writer changing the item.
        if value.network && url.lastPathComponent.hasPrefix(".") { value.flags &= ~UInt32(UF_HIDDEN) }
        return value
    }
    private static func attributesMatch(_ actual: Metadata, _ expected: Metadata) -> Bool {
        // SMB modes are client-synthesized access masks, not portable POSIX ACLs.
        // NTFS and SMB timestamps have 100 ns resolution; allow rounding to 1 us.
        let modeMatches = expected.network && expected.portableMode != true ? true :
            actual.mode == expected.mode && (!actual.network || actual.portableMode == true)
        return actual.attributes == expected.attributes && actual.acl == expected.acl && actual.flags == expected.flags && modeMatches &&
            abs(Double(actual.modified - expected.modified) + Double(actual.modifiedNanos - expected.modifiedNanos) / 1e9) <= 0.000001 &&
            abs(Double(actual.created - expected.created) + Double(actual.createdNanos - expected.createdNanos) / 1e9) <= 0.000001
    }
    private static func applyMetadata(_ expected: Metadata, to fd: Int32, network: Bool) throws {
        for (name, value) in expected.attributes {
            guard value.withUnsafeBytes({ fsetxattr(fd, name, $0.baseAddress, $0.count, 0, 0) }) == 0 else { throw Failure.unsupported }
        }
        if let text = expected.acl {
            guard let acl = acl_from_text(text) else { throw Failure.unsupported }
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            guard acl_set_fd(fd, acl) == 0 else { throw Failure.unsupported }
        }
        if !expected.network || expected.portableMode == true {
            if network {
                // SMB exposes a synthesized mode mask. Preserve the original
                // rwx bits as metadata for a faithful return to a POSIX volume;
                // this does not claim to change the server's access policy.
                let mode = Data(String(expected.mode, radix: 8).utf8)
                guard mode.withUnsafeBytes({ fsetxattr(fd, "com.opencommander.posix-mode-v1", $0.baseAddress, $0.count, 0, 0) }) == 0 else { throw Failure.unsupported }
            } else { guard fchmod(fd, expected.mode) == 0 else { throw Failure.unsupported } }
        }
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = UInt32(ATTR_CMN_CRTIME | ATTR_CMN_MODTIME)
        var times = [timespec(tv_sec: expected.created, tv_nsec: expected.createdNanos), timespec(tv_sec: expected.modified, tv_nsec: expected.modifiedNanos)]
        guard fsetattrlist(fd, &attributes, &times, MemoryLayout<timespec>.size * times.count, 0) == 0 else { throw Failure.unsupported }
        var current = stat()
        guard fstat(fd, &current) == 0 else { throw Failure.changedTarget }
        if current.st_flags != expected.flags { guard fchflags(fd, expected.flags) == 0 else { throw Failure.unsupported } }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }
    private static func verifyMetadata(_ expected: Metadata, at url: URL, control: () -> Control = { .proceed }) throws -> Bool {
        // Some servers/client leases retain directory-enumeration timestamps
        // beyond a short reopen. Never accept a differing timestamp; allow a
        // bounded cache-expiry window before refusing the operation instead.
        let attempts = isSMB(url) ? 65 : 1
        for attempt in 0..<attempts {
            guard control() == .proceed else { throw CocoaError(.userCancelled) }
            let current = try captureMetadata(url)
            if attributesMatch(current, expected) { return true }
            // Only timestamps are subject to the observed directory cache
            // problem. Other changes must fail immediately, not wait them out.
            var withoutDates = current
            withoutDates.modified = expected.modified; withoutDates.modifiedNanos = expected.modifiedNanos
            withoutDates.created = expected.created; withoutDates.createdNanos = expected.createdNanos
            guard attributesMatch(withoutDates, expected) else { return false }
            if attempt + 1 < attempts { Thread.sleep(forTimeInterval: 1) }
            #if OPENCOMMANDER_NAS
            if attempt + 1 == attempts {
                print("METADATA_MISMATCH \(url.lastPathComponent) attrs=\(current.attributes == expected.attributes) acl=\(current.acl == expected.acl) flags=\(current.flags)/\(expected.flags) mode=\(current.mode)/\(expected.mode) modified=\(current.modified).\(current.modifiedNanos)/\(expected.modified).\(expected.modifiedNanos) created=\(current.created).\(current.createdNanos)/\(expected.created).\(expected.createdNanos)")
            }
            #endif
        }
        return false
    }
    private static func privateDirectory(_ info: stat, at url: URL) -> Bool {
        guard info.st_uid == geteuid() else { return false }
        if info.st_mode & 0o077 == 0 { return true }
        var filesystem = statfs()
        guard statfs(url.path, &filesystem) == 0, info.st_mode & 0o022 == 0 else { return false }
        let type = withUnsafePointer(to: &filesystem.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
        }
        // The FSKit driver synthesizes 0755 directories even for mkdir(0700).
        // Do not mistake that read/execute mask for a different recovery folder.
        return type == "ntfs" || type.hasPrefix("openntfs")
    }
    struct Journal: Codable {
        var version = 2
        let id: String
        let source: String
        let target: String
        var device: Int32
        var state: State = .ready
        var entries: [Entry]
        var previousProof: Data?
        var backupReady: Bool?
        var move: Bool?
        var sourceVolume: String?
        var targetVolume: String?
        var moveProof: Data?
        var quarantineCreated: Bool?
    }
    private static func volume(_ url: URL) throws -> String? {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { throw POSIXError(.ENOTCONN) }
        if isSMB(url) {
            return withUnsafePointer(to: &info.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1024) { "smb:" + String(cString: $0) }
            }
        }
        return try VolumeIdentity.token(at: url)
    }
    private static func quarantine(_ journal: Journal) -> URL {
        URL(fileURLWithPath: journal.source).deletingLastPathComponent()
            .appendingPathComponent(".OpenCommanderMoved-" + journal.id)
            .appendingPathComponent(journal.version == 1 ? "original" : URL(fileURLWithPath: journal.source).lastPathComponent)
    }
    private static let marker = "com.opencommander.exclusive-copy"
    private static func directory(_ url: URL) throws -> stat {
        var current = URL(fileURLWithPath: "/"), info = stat()
        for part in url.pathComponents.dropFirst() {
            current.appendPathComponent(part)
            guard lstat(current.path, &info) == 0 else { throw ioFailure(.unsafePath) }
            guard info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unsafePath }
        }
        return info
    }
    private static func hash(_ fd: Int32) throws -> Data {
        var sum = SHA256(), buffer = [UInt8](repeating: 0, count: 1024 * 1024), offset: off_t = 0
        while true {
            let count = pread(fd, &buffer, buffer.count, offset)
            guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if count == 0 { break }
            sum.update(data: Data(buffer.prefix(count))); offset += off_t(count)
        }
        return Data(sum.finalize())
    }
    private static func sourceDigest(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw ioFailure(.changedSource) }
        defer { close(fd) }
        var before = stat(), after = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG else { throw Failure.changedSource }
        let result = try hash(fd)
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw Failure.changedSource }
        return result
    }
    private static func save(_ value: Journal, _ stage: URL) throws {
        let encoded = try JSONEncoder().encode(value)
        guard encoded.count <= 64 * 1024 * 1024 else { throw Failure.unsupported }
        try encoded.write(to: stage.appendingPathComponent("exclusive.json"), options: .atomic)
        let fd = open(stage.appendingPathComponent("exclusive.json").path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.invalidJournal }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
        let parent = open(stage.path, O_RDONLY | O_NOFOLLOW)
        guard parent >= 0 else { throw Failure.invalidJournal }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw POSIXError(.EIO) }
    }
    private static func proof(_ url: URL) throws -> Data {
        var hash = SHA256()
        func visit(_ item: URL, _ relative: String) throws {
            var info = stat()
            guard lstat(item.path, &info) == 0 else { throw Failure.changedTarget }
            let dir = info.st_mode & S_IFMT == S_IFDIR
            guard dir || info.st_mode & S_IFMT == S_IFREG else { throw Failure.unsupported }
            let name = Data(relative.utf8)
            hash.update(data: Data("\(name.count):\(dir):".utf8)); hash.update(data: name)
            if dir {
                let children = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
                hash.update(data: Data("\(children.count):".utf8))
                for child in children { try visit(child, relative + "/" + child.lastPathComponent) }
            } else { hash.update(data: try sourceDigest(item)) }
        }
        try visit(url, ""); return Data(hash.finalize())
    }
    static func create(source: URL, target: URL, journalParent: URL, replace: Bool = false, move: Bool = false) throws -> URL {
        _ = try directory(source.deletingLastPathComponent())
        let parent = try directory(target.deletingLastPathComponent())
        _ = try directory(journalParent)
        guard source != target, !target.path.hasPrefix(source.path + "/") else { throw Failure.unsafePath }
        var occupied = stat()
        let exists = lstat(target.path, &occupied) == 0
        guard exists ? replace : errno == ENOENT else { throw Failure.conflict }
        // A replacement backup must remain on the same volume. This is a
        // private destination, never an ordinary rename onto a public target.
        if exists { guard try directory(journalParent).st_dev == parent.st_dev else { throw Failure.unsafePath } }
        let previous = exists ? try proof(target) : nil
        var entries: [Entry] = []
        func visit(_ url: URL, _ relative: String) throws {
            guard entries.count < 100_000 else { throw Failure.unsupported }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw Failure.changedSource }
            let isDirectory = info.st_mode & S_IFMT == S_IFDIR
            guard isDirectory || info.st_mode & S_IFMT == S_IFREG else { throw Failure.unsupported }
            entries.append(Entry(path: relative, directory: isDirectory, size: isDirectory ? 0 : info.st_size,
                                 digest: isDirectory ? nil : try sourceDigest(url), metadata: try captureMetadata(url)))
            if isDirectory {
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(source, "")
        let id = UUID().uuidString
        let stage = journalParent.appendingPathComponent(".OpenCommanderExclusive-" + id)
        guard mkdir(stage.path, 0o700) == 0 else { throw Failure.conflict }
        try save(Journal(id: id, source: source.path, target: target.path, device: parent.st_dev, entries: entries,
                         previousProof: previous, move: move,
                         sourceVolume: try volume(source.deletingLastPathComponent()), targetVolume: try volume(target.deletingLastPathComponent())), stage)
        return stage
    }
    private static func owner(_ fd: Int32) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 128)
        let count = fgetxattr(fd, marker, &bytes, bytes.count, 0, 0)
        guard count > 0 else { throw Failure.changedTarget }
        return Data(bytes.prefix(count))
    }
    static func resume(_ stage: URL, control: () -> Control = { .proceed },
                       progress: (Int64) -> Void = { _ in }, fileProgress: (Int, Int) -> Void = { _, _ in },
                       fault: (Checkpoint) throws -> Void = { _ in }) throws -> State {
        let stageInfo = try directory(stage)
        guard privateDirectory(stageInfo, at: stage) else { throw Failure.invalidJournal }
        let lock = open(stage.appendingPathComponent("lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw Failure.invalidJournal }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure.conflict }
        defer { _ = flock(lock, LOCK_UN) }
        var journal = try readJournal(stage)
        return try transfer(stage, stageInfo: stageInfo, journal: &journal, control: control, progress: progress, fileProgress: fileProgress, fault: fault)
    }
    private static func readJournal(_ stage: URL) throws -> Journal {
        let stageInfo = try directory(stage)
        guard privateDirectory(stageInfo, at: stage) else { throw Failure.invalidJournal }
        let journalFD = open(stage.appendingPathComponent("exclusive.json").path, O_RDONLY | O_NOFOLLOW)
        guard journalFD >= 0 else { throw Failure.invalidJournal }
        defer { close(journalFD) }
        var journalInfo = stat()
        guard fstat(journalFD, &journalInfo) == 0, journalInfo.st_mode & S_IFMT == S_IFREG,
              journalInfo.st_size > 0, journalInfo.st_size <= 64 * 1024 * 1024 else { throw Failure.invalidJournal }
        var data = Data(count: Int(journalInfo.st_size))
        let count = data.withUnsafeMutableBytes { read(journalFD, $0.baseAddress, $0.count) }
        guard count == data.count else { throw Failure.invalidJournal }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard (1...2).contains(journal.version), stage.lastPathComponent == ".OpenCommanderExclusive-" + journal.id,
              UUID(uuidString: journal.id) != nil, !journal.entries.isEmpty, journal.entries.count <= 100_000,
              journal.entries[0].path.isEmpty, Set(journal.entries.map(\.path)).count == journal.entries.count,
              journal.entries.allSatisfy({ entry in entry.size >= 0 && entry.offset >= 0 && entry.offset <= entry.size &&
                  (entry.path.isEmpty || (!entry.path.hasPrefix("/") && entry.path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." })) }) else { throw Failure.invalidJournal }
        return journal
    }
    private static func transfer(_ stage: URL, stageInfo: stat, journal: inout Journal,
                                 control: () -> Control, progress: (Int64) -> Void, fileProgress: (Int, Int) -> Void,
                                 fault: (Checkpoint) throws -> Void) throws -> State {
        let fileCount = journal.entries.filter { !$0.directory }.count
        var finishedFiles = journal.entries.filter { !$0.directory && $0.complete }.count
        fileProgress(finishedFiles, fileCount)
        let originalSource = URL(fileURLWithPath: journal.source), target = URL(fileURLWithPath: journal.target)
        var source = originalSource
        if journal.move == true, journal.moveProof != nil, SafeFileOperations.exists(quarantine(journal)) {
            // The source rename may have succeeded before the SMB reply or the
            // local checkpoint was lost. Never repeat it onto a new source.
            guard !SafeFileOperations.exists(originalSource), let expected = journal.moveProof,
                  try proof(quarantine(journal)) == expected else { throw Failure.changedSource }
            source = quarantine(journal)
        }
        guard journal.source.hasPrefix("/"), journal.target.hasPrefix("/"),
              !journal.source.contains("\0"), !journal.target.contains("\0"), source != target,
              !target.path.hasPrefix(source.path + "/") else { throw Failure.invalidJournal }
        _ = try directory(source.deletingLastPathComponent())
        guard journal.entries.allSatisfy({ $0.directory ? ($0.size == 0 && $0.digest == nil) : ($0.digest?.count == 32) }) else { throw Failure.invalidJournal }
        if let expected = journal.sourceVolume { guard try volume(originalSource.deletingLastPathComponent()) == expected else { throw Failure.changedSource } }
        let currentDevice = try directory(target.deletingLastPathComponent()).st_dev
        if let expected = journal.targetVolume {
            guard try volume(target.deletingLastPathComponent()) == expected else { throw Failure.changedTarget }
            journal.device = currentDevice
        } else { guard currentDevice == journal.device else { throw Failure.changedTarget } }
        guard journal.state != .cancelled else { return .cancelled }
        let command = control()
        if command != .proceed {
            journal.state = command == .cancel ? .cancelled : .paused
            try save(journal, stage); return journal.state
        }
        let token = Data(journal.id.utf8)
        if let previous = journal.previousProof, journal.backupReady != true {
            guard stageInfo.st_dev == journal.device else { throw Failure.unsafePath }
            let backup = stage.appendingPathComponent("previous")
            var info = stat()
            if lstat(backup.path, &info) == 0 {
                guard journal.state == .backingUp, try proof(backup) == previous,
                      lstat(target.path, &info) != 0, errno == ENOENT else { throw Failure.changedTarget }
            } else {
                guard errno == ENOENT, try proof(target) == previous else { throw Failure.changedTarget }
                let claim = open(target.path, O_RDONLY | O_NOFOLLOW)
                guard claim >= 0 else { throw Failure.changedTarget }
                defer { close(claim) }
                // Competing OpenCommander replacements cannot both claim it.
                let claimName = "com.opencommander.replace-lock"
                let result = token.withUnsafeBytes { fsetxattr(claim, claimName, $0.baseAddress, $0.count, 0, XATTR_CREATE) }
                if result != 0 {
                    var bytes = [UInt8](repeating: 0, count: 128)
                    let n = fgetxattr(claim, claimName, &bytes, bytes.count, 0, 0)
                    guard n == token.count, Data(bytes.prefix(max(0, n))) == token else { throw Failure.conflict }
                }
                journal.state = .backingUp; try save(journal, stage)
                guard try proof(target) == previous else { throw Failure.changedTarget }
                // Only this locked journal owns this fresh private name. It is
                // not the unsafe public-name Foundation fallback rejected above.
                guard rename(target.path, backup.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                try fault(.retainedPrevious)
                guard try proof(backup) == previous else { throw Failure.changedTarget }
                let parentFD = open(target.deletingLastPathComponent().path, O_RDONLY | O_NOFOLLOW)
                guard parentFD >= 0 else { throw Failure.changedTarget }
                defer { close(parentFD) }
                guard fsync(parentFD) == 0 else { throw POSIXError(.EIO) }
            }
            journal.backupReady = true; journal.state = .ready; try save(journal, stage)
        }
        var total: Int64 = 0
        for index in journal.entries.indices {
            let entry = journal.entries[index]
            let origin = entry.path.isEmpty ? source : source.appendingPathComponent(entry.path)
            let destination = entry.path.isEmpty ? target : target.appendingPathComponent(entry.path)
            _ = try directory(destination.deletingLastPathComponent())
            if !entry.directory { guard try sourceDigest(origin) == entry.digest else { throw Failure.changedSource } }
            let initialCommand = control()
            if initialCommand != .proceed {
                journal.state = initialCommand == .cancel ? .cancelled : .paused
                try save(journal, stage); return journal.state
            }
            let fd: Int32
            if entry.owned {
                fd = open(destination.path, (entry.directory || entry.complete ? O_RDONLY : O_RDWR) | O_NOFOLLOW)
            } else {
                if entry.directory {
                    guard mkdir(destination.path, 0o700) == 0 else { throw Failure.conflict }
                    fd = open(destination.path, O_RDONLY | O_NOFOLLOW)
                } else { fd = open(destination.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
            }
            guard fd >= 0 else { throw ioFailure(.conflict) }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_dev == journal.device,
                  info.st_mode & S_IFMT == (entry.directory ? S_IFDIR : S_IFREG) else { throw Failure.changedTarget }
            if !entry.owned {
                let tagged = token.withUnsafeBytes { fsetxattr(fd, marker, $0.baseAddress, $0.count, 0, XATTR_CREATE) }
                guard tagged == 0, fsync(fd) == 0 else { throw Failure.unsupported }
                journal.entries[index].owned = true
                try save(journal, stage)
            }
            guard try owner(fd) == token else { throw Failure.changedTarget }
            if entry.directory { journal.entries[index].complete = true; try save(journal, stage); continue }
            let input = open(origin.path, O_RDONLY | O_NOFOLLOW)
            guard input >= 0 else { throw ioFailure(.changedSource) }
            defer { close(input) }
            guard info.st_size >= entry.offset, info.st_size <= entry.size else { throw Failure.changedTarget }
            // Revalidate all existing bytes, including an uncheckpointed last block.
            var offset: Int64 = 0
            var buffer = [UInt8](repeating: 0, count: 1024 * 1024), other = buffer
            while offset < info.st_size {
                let wanted = min(buffer.count, Int(info.st_size - offset))
                let a = pread(input, &buffer, wanted, off_t(offset)), b = pread(fd, &other, wanted, off_t(offset))
                guard a == wanted, b == wanted, buffer.prefix(wanted).elementsEqual(other.prefix(wanted)) else { throw Failure.changedTarget }
                offset += Int64(wanted)
            }
            journal.state = .copying
            while offset < entry.size {
                let command = control()
                if command != .proceed {
                    journal.state = command == .cancel ? .cancelled : .paused
                    try save(journal, stage); return journal.state
                }
                guard try owner(fd) == token else { throw Failure.changedTarget }
                let wanted = min(buffer.count, Int(entry.size - offset))
                guard pread(input, &buffer, wanted, off_t(offset)) == wanted else { throw Failure.changedSource }
                var done = 0
                while done < wanted {
                    let count = buffer.withUnsafeBytes { pwrite(fd, $0.baseAddress!.advanced(by: done), wanted - done, off_t(offset + Int64(done))) }
                    guard count > 0 else { throw POSIXError(.EIO) }; done += count
                }
                guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
                try fault(.wroteUncheckpointedBytes)
                offset += Int64(wanted); journal.entries[index].offset = offset
                try save(journal, stage); progress(total + offset)
            }
            guard try hash(fd) == entry.digest, try sourceDigest(origin) == entry.digest else { throw Failure.changedSource }
            journal.entries[index].complete = true; total += entry.size
            try save(journal, stage)
            if !entry.complete {
                finishedFiles += 1
                fileProgress(finishedFiles, fileCount)
            }
        }
        // A pathname may have been replaced while its descriptor was open.
        // Re-open each target without following links; also reject extra items.
        for entry in journal.entries {
            let destination = entry.path.isEmpty ? target : target.appendingPathComponent(entry.path)
            let fd = open(destination.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw Failure.changedTarget }
            defer { close(fd) }
            guard try owner(fd) == token else { throw Failure.changedTarget }
            if entry.directory {
                let expected = Set(journal.entries.filter {
                    !$0.path.isEmpty && ($0.path as NSString).deletingLastPathComponent == entry.path
                }.map { ($0.path as NSString).lastPathComponent })
                guard Set(try FileManager.default.contentsOfDirectory(atPath: destination.path)) == expected else { throw Failure.changedTarget }
                let original = entry.path.isEmpty ? source : source.appendingPathComponent(entry.path)
                guard Set(try FileManager.default.contentsOfDirectory(atPath: original.path)) == expected else { throw Failure.changedSource }
            } else { guard try hash(fd) == entry.digest else { throw Failure.changedTarget } }
        }
        // Children first: creating children changes their parent's modification date.
        for index in journal.entries.indices.reversed() {
            let entry = journal.entries[index]
            guard let expected = entry.metadata else { continue } // legacy byte-only journals
            let origin = entry.path.isEmpty ? source : source.appendingPathComponent(entry.path)
            guard try verifyMetadata(expected, at: origin, control: control) else { throw Failure.changedSource }
            let destination = entry.path.isEmpty ? target : target.appendingPathComponent(entry.path)
            let fd = open(destination.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw Failure.changedTarget }; defer { close(fd) }
            guard try owner(fd) == token else { throw Failure.changedTarget }
            if entry.metadataApplied == true {
                guard try verifyMetadata(expected, at: destination, control: control) else { throw Failure.changedTarget }
            } else if !attributesMatch(try metadata(fd, network: isSMB(destination)), expected) {
                try applyMetadata(expected, to: fd, network: isSMB(destination))
            }
            // SMB can return the pre-set attributes from the open handle's
            // cache. Re-open for authoritative readback, with bounded retries.
            guard try verifyMetadata(expected, at: destination, control: control) else { throw Failure.unsupported }
            journal.entries[index].metadataApplied = true; try save(journal, stage)
        }
        if journal.move == true, source == originalSource {
            let command = control()
            if command != .proceed {
                journal.state = command == .cancel ? .cancelled : .paused
                try save(journal, stage); return journal.state
            }
            let expected = try proof(source)
            guard try proof(target) == expected else { throw Failure.changedSource }
            let retained = quarantine(journal), root = retained.deletingLastPathComponent()
            if journal.quarantineCreated != true {
                guard mkdir(root.path, 0o700) == 0 else { throw Failure.conflict }
                journal.quarantineCreated = true; try save(journal, stage)
            }
            let info = try directory(root)
            guard privateDirectory(info, at: root),
                  try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else { throw Failure.conflict }
            journal.moveProof = expected; journal.state = .moving; try save(journal, stage)
            guard try proof(source) == expected, try proof(target) == expected else { throw Failure.changedSource }
            // Only a fresh private name, never a public overwriting rename.
            guard rename(source.path, retained.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try fault(.retainedSource)
            guard try proof(retained) == expected else { throw Failure.changedSource }
            for entry in journal.entries {
                if let attributes = entry.metadata {
                    let item = entry.path.isEmpty ? retained : retained.appendingPathComponent(entry.path)
                    guard try verifyMetadata(attributes, at: item, control: control) else { throw Failure.changedSource }
                }
            }
            let fd = open(originalSource.deletingLastPathComponent().path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw Failure.changedSource }
            defer { close(fd) }
            guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
        }
        journal.state = .completed; try save(journal, stage)
        return .completed
    }
}
