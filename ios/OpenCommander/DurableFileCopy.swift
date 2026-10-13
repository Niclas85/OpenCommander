import Foundation
import Darwin
#if os(macOS) || targetEnvironment(macCatalyst)

/// A private, journaled regular-file copy. Incomplete output is never visible
/// at the destination. Recovery requires an explicit resume by the caller.
enum DurableFileCopy {
    enum Failure: Error { case unsafePath, changedSource, changedPartial, invalidJournal, interrupted, uncertainPublication }
    enum Control { case proceed, pause, cancel }
    enum WorkPhase: String, Codable { case planning, checkingPartial, verifying, copying, publishing, moving }
    struct Activity {
        var phase: WorkPhase
        var done: Int64 = 0
        var total: Int64 = 0
    }
    enum State: String, Codable { case copying, paused, cancelled, publishing, completed }
    struct Identity: Codable, Equatable {
        var device: UInt64
        var inode: UInt64
        var size: Int64
        var seconds: Int64
        var nanoseconds: Int64
    }
    struct Journal: Codable {
        var version = 1
        var id: UUID
        var source: String
        var destination: String
        var sourceIdentity: Identity
        var targetDevice: UInt64
        var offset: Int64 = 0
        var state: State = .copying
        var publishedIdentity: Identity?
        var sourceVolume: String?
        var targetVolume: String?
    }
    struct Result { let staging: URL; let destination: URL; let state: State; let bytes: Int64 }

    private static func identity(_ fd: Int32) throws -> Identity {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw Failure.unsafePath }
        return Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: info.st_size,
            seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: Int64(info.st_mtimespec.tv_nsec))
    }
    private static func directoryDevice(_ url: URL) throws -> UInt64 {
        // Reject aliases in every component, rather than following a swapped
        // staging symlink during restart. Explicit resolved paths can be used.
        var path = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            guard component != ".", component != ".." else { throw Failure.unsafePath }
            path.appendPathComponent(component)
            var info = stat()
            guard lstat(path.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
                throw Failure.unsafePath
            }
        }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw Failure.unsafePath }
        return UInt64(info.st_dev)
    }
    private static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.unsafePath }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }
    private static func save(_ journal: Journal, in staging: URL) throws {
        let pending = staging.appendingPathComponent("journal-next-\(UUID().uuidString).json")
        let final = staging.appendingPathComponent("journal.json")
        let fd = open(pending.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.unsafePath }
        defer { close(fd) }
        let data = try JSONEncoder().encode(journal)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw POSIXError(.EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(pending.path, final.path) == 0 else { throw POSIXError(.EIO) }
        try syncDirectory(staging)
    }
    static func create(source: URL, destination: URL) throws -> URL {
        let parent = destination.deletingLastPathComponent()
        let device = try directoryDevice(parent)
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.unsafePath }
        defer { close(fd) }
        let sourceIdentity = try identity(fd)
        guard source.standardizedFileURL != destination.standardizedFileURL else { throw Failure.unsafePath }
        let id = UUID()
        let staging = parent.appendingPathComponent(".OpenCommanderTransfer-\(id.uuidString)", isDirectory: true)
        guard mkdir(staging.path, 0o700) == 0 else { throw POSIXError(.EIO) }
        do {
            try save(Journal(id: id, source: source.path,
                destination: destination.path, sourceIdentity: sourceIdentity,
                targetDevice: device, sourceVolume: try VolumeIdentity.token(at: source),
                targetVolume: try VolumeIdentity.token(at: parent)), in: staging)
            try syncDirectory(parent)
            return staging
        } catch {
            // Retain the private staging folder on durable-write failure; never
            // delete an uncertain recovery artifact automatically.
            throw error
        }
    }
    static func inspect(_ staging: URL) throws -> Journal {
        _ = try directoryDevice(staging)
        let journalURL = staging.appendingPathComponent("journal.json")
        let fd = open(journalURL.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.invalidJournal }
        defer { close(fd) }
        let info = try identity(fd)
        guard info.size > 0, info.size <= 64 * 1024 else { throw Failure.invalidJournal }
        var data = Data(count: Int(info.size))
        let count = data.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count == data.count, let journal = try? JSONDecoder().decode(Journal.self, from: data),
            journal.version == 1, journal.offset >= 0, journal.offset <= journal.sourceIdentity.size,
            URL(fileURLWithPath: journal.destination).deletingLastPathComponent().standardizedFileURL == staging.deletingLastPathComponent().standardizedFileURL,
            staging.lastPathComponent == ".OpenCommanderTransfer-\(journal.id.uuidString)" else { throw Failure.invalidJournal }
        return journal
    }
    static func resume(_ staging: URL, blockSize: Int = 1024 * 1024,
                       control: () -> Control = { .proceed },
                       progress: (Int64, Int64) -> Void = { _, _ in },
                       activity: (Activity) -> Void = { _ in }) throws -> Result {
        guard blockSize > 0, blockSize <= 8 * 1024 * 1024 else { throw Failure.invalidJournal }
        _ = try directoryDevice(staging)
        let lock = open(staging.appendingPathComponent("worker.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw Failure.unsafePath }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure.interrupted }
        defer { _ = flock(lock, LOCK_UN) }
        var journal = try inspect(staging)
        progress(journal.offset, journal.sourceIdentity.size)
        let destination = URL(fileURLWithPath: journal.destination)
        let currentTargetDevice = try directoryDevice(destination.deletingLastPathComponent())
        if let expected = journal.targetVolume {
            guard try VolumeIdentity.matches(expected, at: destination.deletingLastPathComponent()) else { throw Failure.unsafePath }
            // BSD/VFS device numbers are mount-session identities. A verified
            // volume UUID plus inode/content checks permits explicit remount recovery.
            journal.targetDevice = currentTargetDevice
            if journal.publishedIdentity != nil { journal.publishedIdentity?.device = currentTargetDevice }
        } else {
            guard currentTargetDevice == journal.targetDevice else { throw Failure.unsafePath }
        }
        if journal.state == .publishing {
            // Explicit resume may reconcile a crash in the exclusive-rename
            // window, but never infer success from a filename alone.
            let target = open(destination.path, O_RDONLY | O_NOFOLLOW)
            if target >= 0 {
                defer { close(target) }
                guard let expected = journal.publishedIdentity, try identity(target) == expected,
                    access(staging.appendingPathComponent("payload").path, F_OK) != 0, errno == ENOENT else { throw Failure.uncertainPublication }
                try syncDirectory(destination.deletingLastPathComponent())
                journal.state = .completed; try save(journal, in: staging)
            } else {
                guard errno == ENOENT else { throw Failure.uncertainPublication }
                let partial = open(staging.appendingPathComponent("payload").path, O_RDONLY | O_NOFOLLOW)
                guard partial >= 0 else { throw Failure.uncertainPublication }
                defer { close(partial) }
                guard let expected = journal.publishedIdentity, try identity(partial) == expected else { throw Failure.uncertainPublication }
                journal.state = .paused; try save(journal, in: staging)
            }
        }
        if journal.state == .completed {
            let completed = open(destination.path, O_RDONLY | O_NOFOLLOW)
            guard completed >= 0 else { throw Failure.uncertainPublication }
            defer { close(completed) }
            guard let expected = journal.publishedIdentity, try identity(completed) == expected else { throw Failure.uncertainPublication }
            return Result(staging: staging, destination: destination, state: .completed, bytes: journal.offset)
        }
        guard journal.state != .cancelled else { throw Failure.interrupted }
        if let expected = journal.sourceVolume {
            guard try VolumeIdentity.matches(expected, at: URL(fileURLWithPath: journal.source)) else { throw Failure.changedSource }
        }
        let source = open(journal.source, O_RDONLY | O_NOFOLLOW)
        guard source >= 0 else { throw Failure.changedSource }
        defer { close(source) }
        let currentSourceIdentity = try identity(source)
        if journal.sourceVolume != nil { journal.sourceIdentity.device = currentSourceIdentity.device }
        guard currentSourceIdentity == journal.sourceIdentity else { throw Failure.changedSource }
        let payloadURL = staging.appendingPathComponent("payload")
        let payload = open(payloadURL.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard payload >= 0 else { throw Failure.unsafePath }
        defer { close(payload) }
        let partialIdentity = try identity(payload)
        guard partialIdentity.size >= journal.offset else { throw Failure.changedPartial }
        var payloadInfo = stat()
        guard fstat(payload, &payloadInfo) == 0, payloadInfo.st_nlink == 1,
            payloadInfo.st_uid == geteuid() else { throw Failure.unsafePath }
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var verificationOffset: Int64 = 0
        activity(Activity(phase: .checkingPartial, total: journal.offset))
        while verificationOffset < journal.offset {
            let command = control()
            if command != .proceed {
                journal.state = command == .pause ? .paused : .cancelled
                try save(journal, in: staging)
                return Result(staging: staging, destination: destination, state: journal.state, bytes: journal.offset)
            }
            let wanted = Int(min(Int64(blockSize), journal.offset - verificationOffset))
            var partial = [UInt8](repeating: 0, count: wanted)
            let a = pread(source, &buffer, wanted, off_t(verificationOffset))
            let b = pread(payload, &partial, wanted, off_t(verificationOffset))
            guard a == wanted, b == wanted, Array(buffer.prefix(wanted)) == partial else { throw Failure.changedPartial }
            verificationOffset += Int64(wanted)
            activity(Activity(phase: .checkingPartial, done: verificationOffset, total: journal.offset))
        }
        guard ftruncate(payload, off_t(journal.offset)) == 0 else { throw POSIXError(.EIO) }
        journal.state = .copying
        activity(Activity(phase: .copying))
        try save(journal, in: staging)
        while journal.offset < journal.sourceIdentity.size {
            let command = control()
            if command != .proceed {
                journal.state = command == .pause ? .paused : .cancelled
                try save(journal, in: staging)
                return Result(staging: staging, destination: destination, state: journal.state, bytes: journal.offset)
            }
            let wanted = Int(min(Int64(blockSize), journal.sourceIdentity.size - journal.offset))
            let count = pread(source, &buffer, wanted, off_t(journal.offset))
            guard count == wanted else { throw Failure.changedSource }
            var written = 0
            while written < count {
                let step = buffer.withUnsafeBytes {
                    pwrite(payload, $0.baseAddress!.advanced(by: written), count - written, off_t(journal.offset + Int64(written)))
                }
                guard step > 0 else { throw POSIXError(.EIO) }
                written += step
            }
            guard fsync(payload) == 0 else { throw POSIXError(.EIO) }
            journal.offset += Int64(count)
            try save(journal, in: staging)
            progress(journal.offset, journal.sourceIdentity.size)
        }
        guard try identity(source) == journal.sourceIdentity else { throw Failure.changedSource }
        let finalCommand = control()
        guard finalCommand == .proceed else {
            journal.state = finalCommand == .pause ? .paused : .cancelled
            try save(journal, in: staging)
            return Result(staging: staging, destination: destination, state: journal.state, bytes: journal.offset)
        }
        guard fcopyfile(source, payload, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0,
            fsync(payload) == 0 else { throw POSIXError(.EIO) }
        // Exclusive rename works without hard-link support (e.g. exFAT) and
        // atomically refuses an existing destination.
        // Replacement/Undo must be coordinated by the queue, not by this engine.
        journal.state = .publishing
        activity(Activity(phase: .publishing))
        journal.publishedIdentity = try identity(payload)
        try save(journal, in: staging)
        guard renamex_np(payloadURL.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            journal.state = .paused; try save(journal, in: staging)
            throw POSIXError(code)
        }
        try syncDirectory(destination.deletingLastPathComponent())
        journal.state = .completed
        try save(journal, in: staging)
        return Result(staging: staging, destination: destination, state: .completed, bytes: journal.offset)
    }
}
#endif
