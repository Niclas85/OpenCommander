import Foundation
import Darwin
#if os(macOS) || targetEnvironment(macCatalyst)

/// A journaled root transaction. Per-file checkpoints remain private until the
/// entire tree is verified. Existing targets and moved sources are retained.
enum DurableTreeTransfer {
    enum Phase: String, Codable { case copying, paused, cancelled, displacing, publishing, published, moving, reverting, completed }
    struct Entry: Codable {
        var path: String
        var kind: String
        var size: Int64
        var stage: String?
        var output: Data?
        var directoryInode: UInt64?
    }
    struct Journal: Codable {
        var version = 1
        var id: UUID
        var source: String
        var destination: String
        var sourceFingerprint: Data
        var previousFingerprint: Data?
        var publishedFingerprint: Data?
        var sourceVolume: String?
        var targetVolume: String?
        var targetDevice: UInt64
        var move: Bool
        var replace: Bool
        var phase: Phase = .copying
        var entries: [Entry]
    }
    struct Result {
        var state: DurableFileCopy.State
        var bytes: Int64
        var total: Int64
        var backup: URL?
        var quarantine: URL?
    }
    private static let logicalRoot = "OpenCommander-transfer-root"
    private static func digest(_ url: URL, check: () throws -> Void = {}, progress: ((Int64) -> Void)? = nil) throws -> Data {
        try SafeFileOperations.snapshot(url, rootName: logicalRoot, progress: progress, checkCancellation: check)
    }
    private static func sync(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DurableFileCopy.Failure.unsafePath }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }
    private static func directory(_ url: URL) throws -> stat {
        var current = URL(fileURLWithPath: "/", isDirectory: true), info = stat()
        for component in url.pathComponents.dropFirst() {
            guard component != ".", component != ".." else { throw DurableFileCopy.Failure.unsafePath }
            current.appendPathComponent(component)
            guard lstat(current.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw DurableFileCopy.Failure.unsafePath }
        }
        return info
    }
    private static func save(_ journal: Journal, at staging: URL) throws {
        let data = try JSONEncoder().encode(journal)
        let pending = staging.appendingPathComponent(".root-next-\(UUID().uuidString)")
        let fd = open(pending.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw POSIXError(.EIO) }; offset += count
            }
        }
        guard fsync(fd) == 0, rename(pending.path, staging.appendingPathComponent("root.json").path) == 0 else { throw POSIXError(.EIO) }
        try sync(staging)
    }
    static func create(source: URL, destination: URL, move: Bool, replace: Bool,
                       check: () throws -> Void = {}) throws -> URL {
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        let info = try directory(parent)
        guard source != destination, parent.path != source.path, !parent.path.hasPrefix(source.path + "/") else { throw DurableFileCopy.Failure.unsafePath }
        let initial = try digest(source, check: check)
        var entries: [Entry] = []
        func visit(_ item: URL, _ relative: String) throws {
            try check()
            guard entries.count < 100_000 else { throw DurableFileCopy.Failure.unsafePath }
            let attrs = try fm.attributesOfItem(atPath: item.path)
            guard let type = attrs[.type] as? FileAttributeType, [.typeRegular, .typeDirectory, .typeSymbolicLink].contains(type) else { throw DurableFileCopy.Failure.unsafePath }
            entries.append(Entry(path: relative, kind: type.rawValue, size: type == .typeRegular ? (attrs[.size] as? NSNumber)?.int64Value ?? 0 : 0))
            if type == .typeDirectory {
                for child in try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(source, "")
        guard try digest(source, check: check) == initial else { throw DurableFileCopy.Failure.changedSource }
        let previous = SafeFileOperations.exists(destination) ? try digest(destination, check: check) : nil
        guard previous == nil || replace else { throw SafeFileOperations.conflict(destination) }
        let id = UUID(), staging = parent.appendingPathComponent(".OpenCommanderJob-\(id.uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: staging.appendingPathComponent("archives"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try save(Journal(id: id, source: source.path, destination: destination.path, sourceFingerprint: initial,
            previousFingerprint: previous, sourceVolume: try VolumeIdentity.token(at: source.deletingLastPathComponent()),
            targetVolume: try VolumeIdentity.token(at: parent),
            targetDevice: UInt64(info.st_dev), move: move, replace: replace, entries: entries), at: staging)
        try sync(parent)
        return staging
    }
    static func resume(_ staging: URL, control: () -> DurableFileCopy.Control = { .proceed },
                       progress: (Int64, Int64) -> Void = { _, _ in },
                       fileProgress: (Int, Int) -> Void = { _, _ in },
                       activity: @escaping (DurableFileCopy.Activity) -> Void = { _ in },
                       publish: (URL, URL) throws -> Void = { from, to in
                           guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                       }) throws -> Result {
        _ = try directory(staging)
        let fd = open(staging.appendingPathComponent("root.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw DurableFileCopy.Failure.unsafePath }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw DurableFileCopy.Failure.interrupted }
        defer { _ = flock(fd, LOCK_UN) }
        let journalFile = open(staging.appendingPathComponent("root.json").path, O_RDONLY | O_NOFOLLOW)
        guard journalFile >= 0 else { throw DurableFileCopy.Failure.invalidJournal }
        defer { close(journalFile) }
        var journalInfo = stat()
        guard fstat(journalFile, &journalInfo) == 0, journalInfo.st_mode & S_IFMT == S_IFREG,
            journalInfo.st_size > 0, journalInfo.st_size <= 64 * 1024 * 1024 else { throw DurableFileCopy.Failure.invalidJournal }
        var data = Data(count: Int(journalInfo.st_size))
        let readCount = data.withUnsafeMutableBytes { read(journalFile, $0.baseAddress, $0.count) }
        guard readCount == data.count else { throw DurableFileCopy.Failure.invalidJournal }
        var journal = try JSONDecoder().decode(Journal.self, from: data)
        let fm = FileManager.default, source = URL(fileURLWithPath: journal.source), destination = URL(fileURLWithPath: journal.destination)
        let payload = staging.appendingPathComponent("payload"), backup = staging.appendingPathComponent("previous")
        let quarantine = source.deletingLastPathComponent().appendingPathComponent(".OpenCommanderMoved-\(journal.id.uuidString)")
        let parent = destination.deletingLastPathComponent()
        guard journal.version == 1, !journal.entries.isEmpty, journal.entries.count <= 100_000,
            journal.entries[0].path.isEmpty, parent.standardizedFileURL == staging.deletingLastPathComponent().standardizedFileURL,
            staging.lastPathComponent == ".OpenCommanderJob-\(journal.id.uuidString)",
            Set(journal.entries.map(\.path)).count == journal.entries.count else { throw DurableFileCopy.Failure.invalidJournal }
        var total: Int64 = 0
        for entry in journal.entries {
            guard entry.size >= 0, [FileAttributeType.typeDirectory.rawValue, FileAttributeType.typeRegular.rawValue, FileAttributeType.typeSymbolicLink.rawValue].contains(entry.kind) else { throw DurableFileCopy.Failure.invalidJournal }
            if !entry.path.isEmpty {
                guard !entry.path.hasPrefix("/"), entry.path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw DurableFileCopy.Failure.invalidJournal }
            }
            let addition = total.addingReportingOverflow(entry.size)
            guard !addition.overflow else { throw DurableFileCopy.Failure.invalidJournal }; total = addition.partialValue
        }
        let currentTargetDevice = UInt64(try directory(parent).st_dev)
        if let expected = journal.targetVolume {
            guard try VolumeIdentity.matches(expected, at: parent) else { throw DurableFileCopy.Failure.unsafePath }
            journal.targetDevice = currentTargetDevice
        } else { guard currentTargetDevice == journal.targetDevice else { throw DurableFileCopy.Failure.unsafePath } }
        if let expected = journal.sourceVolume { guard try VolumeIdentity.matches(expected, at: source.deletingLastPathComponent()) else { throw DurableFileCopy.Failure.changedSource } }
        let fileCount = journal.entries.filter { $0.kind != FileAttributeType.typeDirectory.rawValue }.count
        var finishedFiles = journal.entries.filter { $0.kind != FileAttributeType.typeDirectory.rawValue && $0.output != nil }.count
        fileProgress(finishedFiles, fileCount)
        func result(_ state: DurableFileCopy.State, _ bytes: Int64) -> Result {
            Result(state: state, bytes: bytes, total: total, backup: journal.previousFingerprint == nil ? nil : backup, quarantine: journal.move ? quarantine : nil)
        }
        func check() throws { guard control() == .proceed else { throw DurableFileCopy.Failure.interrupted } }
        func verifiedDigest(_ url: URL, bytes: Int64) throws -> Data {
            activity(.init(phase: .verifying, total: bytes))
            return try digest(url, check: check, progress: { count in
                activity(.init(phase: .verifying, done: count, total: bytes))
            })
        }
        func revertPublishedDestination() throws {
            guard let published = journal.publishedFingerprint else { throw DurableFileCopy.Failure.invalidJournal }
            journal.phase = .reverting; try save(journal, at: staging)
            if SafeFileOperations.exists(payload) {
                guard try digest(payload) == published else { throw DurableFileCopy.Failure.changedPartial }
            } else {
                guard try digest(destination) == published else { throw DurableFileCopy.Failure.uncertainPublication }
                guard renamex_np(destination.path, payload.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EIO) }
                try sync(parent); try sync(staging)
            }
            if let previous = journal.previousFingerprint {
                if SafeFileOperations.exists(backup) {
                    guard !SafeFileOperations.exists(destination), try digest(backup) == previous else { throw DurableFileCopy.Failure.uncertainPublication }
                    guard renamex_np(backup.path, destination.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EIO) }
                    try sync(parent); try sync(staging)
                } else { guard try digest(destination) == previous else { throw DurableFileCopy.Failure.uncertainPublication } }
            } else { guard !SafeFileOperations.exists(destination) else { throw DurableFileCopy.Failure.uncertainPublication } }
            journal.publishedFingerprint = nil; journal.phase = .paused; try save(journal, at: staging)
        }
        if journal.phase == .reverting { try revertPublishedDestination() }
        if [.copying, .paused].contains(journal.phase) {
            guard try verifiedDigest(source, bytes: total) == journal.sourceFingerprint else { throw DurableFileCopy.Failure.changedSource }
            var done = journal.entries.filter { $0.output != nil }.reduce(Int64(0)) { $0 + $1.size }
            let directories = journal.entries.indices.filter { journal.entries[$0].kind == FileAttributeType.typeDirectory.rawValue }
            let leaves = journal.entries.indices.filter { journal.entries[$0].kind != FileAttributeType.typeDirectory.rawValue }
            // Prepare ancestors first, continue the interrupted file next, then
            // start untouched files. Completed outputs are revalidated before
            // publication, without delaying the unfinished file's checkpoint.
            let partials = leaves.filter { journal.entries[$0].output == nil && journal.entries[$0].stage != nil }
            let untouched = leaves.filter { journal.entries[$0].output == nil && journal.entries[$0].stage == nil }
            let completed = leaves.filter { journal.entries[$0].output != nil }
            var pendingOffsets = partials.reduce(into: [Int: Int64]()) { result, index in
                guard let saved = journal.entries[index].stage, let child = try? DurableFileCopy.inspect(URL(fileURLWithPath: saved)) else { return }
                result[index] = min(journal.entries[index].size, child.offset)
            }
            func transferredBytes() -> Int64 { done + pendingOffsets.values.reduce(0, +) }
            progress(transferredBytes(), total)
            for index in directories + partials + untouched + completed {
                let entry = journal.entries[index]
                let origin = entry.path.isEmpty ? source : source.appendingPathComponent(entry.path)
                let target = entry.path.isEmpty ? payload : payload.appendingPathComponent(entry.path)
                let command = control()
                if command != .proceed {
                    journal.phase = command == .pause ? .paused : .cancelled; try save(journal, at: staging)
                    return result(command == .pause ? .paused : .cancelled, transferredBytes())
                }
                if entry.kind == FileAttributeType.typeDirectory.rawValue {
                    if let inode = entry.directoryInode { guard UInt64(try directory(target).st_ino) == inode else { throw DurableFileCopy.Failure.changedPartial } }
                    else {
                        if SafeFileOperations.exists(target) {
                            let existing = try directory(target)
                            guard existing.st_uid == geteuid(), existing.st_mode & 0o777 == 0o700,
                                try fm.contentsOfDirectory(atPath: target.path).isEmpty else { throw DurableFileCopy.Failure.changedPartial }
                        } else { try fm.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
                        journal.entries[index].directoryInode = UInt64(try directory(target).st_ino)
                        try save(journal, at: staging)
                    }
                } else if let fingerprint = entry.output {
                    guard try verifiedDigest(target, bytes: entry.size) == fingerprint else { throw DurableFileCopy.Failure.changedPartial }
                } else if entry.kind == FileAttributeType.typeSymbolicLink.rawValue {
                    let link = try fm.destinationOfSymbolicLink(atPath: origin.path)
                    if SafeFileOperations.exists(target) {
                        guard try fm.destinationOfSymbolicLink(atPath: target.path) == link else { throw DurableFileCopy.Failure.changedPartial }
                    } else { try fm.createSymbolicLink(atPath: target.path, withDestinationPath: link) }
                    journal.entries[index].output = try digest(target, check: check); try save(journal, at: staging)
                } else if entry.kind == FileAttributeType.typeRegular.rawValue {
                    let child: URL
                    if let saved = entry.stage {
                        child = URL(fileURLWithPath: saved)
                        guard child.deletingLastPathComponent() == target.deletingLastPathComponent(), child.lastPathComponent.hasPrefix(".OpenCommanderTransfer-") else { throw DurableFileCopy.Failure.invalidJournal }
                        let childJournal = try DurableFileCopy.inspect(child)
                        guard childJournal.source == origin.path, childJournal.destination == target.path else { throw DurableFileCopy.Failure.invalidJournal }
                    }
                    else {
                        let candidates = try fm.contentsOfDirectory(at: target.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".OpenCommanderTransfer-") }.filter {
                            guard let saved = try? DurableFileCopy.inspect($0) else { return false }
                            return saved.source == origin.path && saved.destination == target.path && saved.offset == 0 && saved.state == .copying
                        }
                        guard candidates.count <= 1 else { throw DurableFileCopy.Failure.changedPartial }
                        child = try candidates.first ?? DurableFileCopy.create(source: origin, destination: target)
                        journal.entries[index].stage = child.path; try save(journal, at: staging)
                    }
                    let copied = try DurableFileCopy.resume(child, control: control, progress: { bytes, _ in
                        progress(done + bytes + pendingOffsets.filter { $0.key != index }.values.reduce(0, +), total)
                    }, activity: activity)
                    if copied.state != .completed {
                        journal.phase = copied.state == .paused ? .paused : .cancelled; try save(journal, at: staging)
                        return result(copied.state, done + copied.bytes)
                    }
                    journal.entries[index].output = try verifiedDigest(target, bytes: entry.size)
                    try save(journal, at: staging)
                    done += entry.size
                    pendingOffsets.removeValue(forKey: index)
                } else { throw DurableFileCopy.Failure.invalidJournal }
                // Child journals must not be published inside the copied tree.
                if let saved = journal.entries[index].stage, journal.entries[index].output != nil {
                    let child = URL(fileURLWithPath: saved)
                    guard child.deletingLastPathComponent() == target.deletingLastPathComponent(), child.lastPathComponent.hasPrefix(".OpenCommanderTransfer-") else { throw DurableFileCopy.Failure.invalidJournal }
                    if SafeFileOperations.exists(child) {
                        try fm.moveItem(at: child, to: staging.appendingPathComponent("archives").appendingPathComponent(child.lastPathComponent))
                    }
                    journal.entries[index].stage = nil; try save(journal, at: staging)
                }
                if entry.kind != FileAttributeType.typeDirectory.rawValue, entry.output == nil,
                   journal.entries[index].output != nil {
                    finishedFiles += 1
                    fileProgress(finishedFiles, fileCount)
                }
                progress(transferredBytes(), total)
            }
            guard try verifiedDigest(source, bytes: total) == journal.sourceFingerprint else { throw DurableFileCopy.Failure.changedSource }
            for entry in journal.entries.reversed() where entry.kind == FileAttributeType.typeDirectory.rawValue {
                try check()
                let origin = entry.path.isEmpty ? source : source.appendingPathComponent(entry.path)
                let target = entry.path.isEmpty ? payload : payload.appendingPathComponent(entry.path)
                guard copyfile(origin.path, target.path, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)) == 0 else { throw POSIXError(.EIO) }
                try sync(target)
            }
            journal.publishedFingerprint = try verifiedDigest(payload, bytes: total)
            journal.phase = .displacing; try save(journal, at: staging)
        }
        guard journal.phase != .cancelled else { return result(.cancelled, 0) }
        if journal.phase == .displacing {
            activity(.init(phase: .publishing))
            if let previous = journal.previousFingerprint {
                if SafeFileOperations.exists(backup) { guard try digest(backup) == previous, !SafeFileOperations.exists(destination) else { throw DurableFileCopy.Failure.uncertainPublication } }
                else {
                    guard try digest(destination) == previous else { throw SafeFileOperations.conflict(destination) }
                    guard renamex_np(destination.path, backup.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EIO) }
                    try sync(parent); try sync(staging)
                }
            } else { guard !SafeFileOperations.exists(destination) else { throw SafeFileOperations.conflict(destination) } }
            journal.phase = .publishing; try save(journal, at: staging)
        }
        if journal.phase == .publishing {
            activity(.init(phase: .publishing))
            guard let expected = journal.publishedFingerprint else { throw DurableFileCopy.Failure.invalidJournal }
            if SafeFileOperations.exists(destination) {
                guard !SafeFileOperations.exists(payload), try digest(destination) == expected else { throw DurableFileCopy.Failure.uncertainPublication }
            } else {
                guard try digest(payload) == expected else { throw DurableFileCopy.Failure.changedPartial }
                do { try publish(payload, destination) }
                catch {
                    if !SafeFileOperations.exists(destination), let previous = journal.previousFingerprint,
                        SafeFileOperations.exists(backup), (try? digest(backup)) == previous {
                        if renamex_np(backup.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
                            journal.phase = .displacing; try? save(journal, at: staging); try? sync(parent)
                        }
                    }
                    throw error
                }
            }
            try sync(parent); journal.phase = .published; try save(journal, at: staging)
        }
        if [.published, .moving].contains(journal.phase) {
            guard let expected = journal.publishedFingerprint, try digest(destination) == expected else { throw DurableFileCopy.Failure.uncertainPublication }
            if journal.move {
                activity(.init(phase: .moving))
                journal.phase = .moving; try save(journal, at: staging)
                if SafeFileOperations.exists(quarantine) {
                    guard !SafeFileOperations.exists(source), try digest(quarantine) == journal.sourceFingerprint else { throw DurableFileCopy.Failure.changedSource }
                } else {
                    guard (try? digest(source)) == journal.sourceFingerprint else {
                        try revertPublishedDestination()
                        throw DurableFileCopy.Failure.changedSource
                    }
                    guard renamex_np(source.path, quarantine.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EIO) }
                    try sync(source.deletingLastPathComponent())
                    guard try digest(quarantine) == journal.sourceFingerprint else {
                        if !SafeFileOperations.exists(source), renamex_np(quarantine.path, source.path, UInt32(RENAME_EXCL)) == 0 {
                            try sync(source.deletingLastPathComponent())
                            try revertPublishedDestination()
                        }
                        throw DurableFileCopy.Failure.changedSource
                    }
                }
            }
            journal.phase = .completed; try save(journal, at: staging)
        }
        guard journal.phase == .completed, let expected = journal.publishedFingerprint, try digest(destination) == expected else { throw DurableFileCopy.Failure.uncertainPublication }
        return result(.completed, total)
    }
}
#endif
