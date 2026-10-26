import Foundation
import Darwin
#if os(macOS) || targetEnvironment(macCatalyst)

/// Durable local transfers; online providers keep their coordinated adapters.
final class DurableTransferQueue {
    enum State: String, Codable { case queued, running, paused, cancelled, failed, completed }
    enum DeletionCheckpoint { case afterMutationBeforeReceipt, afterReceipt }
    struct DeletionIdentity: Codable, Equatable {
        let device: UInt64, inode: UInt64, kind: UInt32
        let size: Int64, seconds: Int64, nanoseconds: Int64
        static func read(_ url: URL) throws -> Self {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let kind = UInt32(info.st_mode & S_IFMT)
            guard [UInt32(S_IFREG), UInt32(S_IFDIR), UInt32(S_IFLNK)].contains(kind) else { throw CocoaError(.fileWriteInvalidFileName) }
            return Self(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), kind: kind, size: info.st_size,
                        seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: Int64(info.st_mtimespec.tv_nsec))
        }
    }
    struct Job: Codable {
        var id = UUID()
        var source: String
        var destination: String
        var staging: String?
        var state: State = .queued
        var bytes: Int64 = 0
        var total: Int64 = 0
        // Optional for pre-existing queues; unknown is distinct from zero.
        var filesDone: Int?
        var filesTotal: Int?
        var created = Date()
        var compact = true
        var error: String?
        var failure: HistoryFailure?
        var errorKey: String?
        var recoveryPath: String?
        var errorMessage: String? {
            // Keep persisted prior-attempt evidence, but do not present it as
            // a current failure after an explicit retry completed successfully.
            guard state != .completed else { return nil }
            guard let message = errorKey.map({ L10n.get($0) }) ?? failure?.message ?? error else { return nil }
            return recoveryPath.map { message + "\n" + L10n.get("recovery_retained", $0) } ?? message
        }
        var move: Bool?
        var replace: Bool?
        var engine: String?
        var backup: String?
        var quarantine: String?
        var elapsed: TimeInterval?
        var activeSince: Date?
        var lastActivity: Date?
        var workPhase: DurableFileCopy.WorkPhase?
        var checkedBytes: Int64?
        var checkingTotal: Int64?
        var requestedControl: String?
        var controlRequestedAt: Date?
        // Presentation-only annotation, recalculated from the authoritative
        // queue on each emission. Never a source of scheduler decisions.
        var waitingForReservedPaths: Bool?
        var deleteToTrash: Bool?
        var deletionIdentity: DeletionIdentity?
        var deletionProof: Data?
        var deletionProofPending: Bool?
        var isDeletion: Bool { deleteToTrash != nil }
        var displayName: String {
            (isDeletion ? L10n.get("transfer_delete_title") + ": " : "") + URL(fileURLWithPath: source).lastPathComponent
        }
        var routeDescription: String {
            source + " → " + (isDeletion && state != .completed ? L10n.get(deleteToTrash == true ? "trash" : "transfer_delete_recovery") : destination)
        }
        var canForget: Bool {
            [.completed, .cancelled].contains(state) && !(engine == "nas-exclusive" && state != .completed)
        }
        var isChecking: Bool { state == .running && (workPhase == .checkingPartial || workPhase == .verifying) }
        var progressFraction: Float {
            if state == .completed { return 1 }
            let done = isChecking ? checkedBytes ?? 0 : bytes
            let expected = isChecking ? checkingTotal ?? 0 : total
            let fraction = expected > 0 ? Float(max(0, min(done, expected))) / Float(expected) : 0
            // Finishing the last data block is not successful publication.
            // Verification is a separately labelled meter and may reach100%.
            return isChecking ? fraction : min(0.99, fraction)
        }
        var statusKey: String {
            if state == .queued, deletionProofPending == true { return "transfer_delete_preparing" }
            if state == .queued, waitingForReservedPaths == true { return "transfer_waiting_paths" }
            if state == .cancelled, staging == nil, recoveryPath == nil, backup == nil, quarantine == nil {
                return "transfer_cancelled_no_data"
            }
            if state == .running, let requestedControl { return requestedControl == "pause" ? "transfer_pausing" : "transfer_cancelling" }
            if state == .running, isDeletion { return "transfer_deleting" }
            if state == .running, let workPhase, workPhase != .copying { return "transfer_phase_" + workPhase.rawValue }
            return state == .running && move == true ? "transfer_moving" : "transfer_" + state.rawValue
        }
    }
    private struct Store: Codable { var version = 1; var limit: Int; var jobs: [Job] }
    private final class Signal {
        private let lock = NSLock()
        private var value = DurableFileCopy.Control.proceed
        private let checkpoint: (() -> Void)?
        init(checkpoint: (() -> Void)? = nil) { self.checkpoint = checkpoint }
        func set(_ value: DurableFileCopy.Control) {
            lock.lock(); defer { lock.unlock() }
            // Cancellation is terminal for this worker. A delayed UI action
            // must never turn an accepted cancellation back into copying.
            guard self.value != .cancel else { return }
            self.value = value
        }
        func get() -> DurableFileCopy.Control {
            checkpoint?() // Worker-only dependency injection; never hold the control lock here.
            lock.lock(); defer { lock.unlock() }; return value
        }
    }
    private let serial = DispatchQueue(label: "OpenCommander.DurableTransferQueue")
    private let workers = DispatchQueue(label: "OpenCommander.DurableTransferWorkers", qos: .utility, attributes: .concurrent)
    private let storeURL: URL
    private var jobs: [Job] = []
    private var signals: [UUID: Signal] = [:]
    private var deletionProofSignals: [UUID: Signal] = [:]
    private let deletionProofWorker = DispatchQueue(label: "OpenCommander.DeletionProofs", qos: .utility)
    private var limit = 2
    private var storeFailure: Error?
    private var admissionFailure: String?
    private var foregroundOperationActive = false
    private let controlCheckpoint: ((Job) -> Void)?
    private let deletionHandler: (URL, Bool, UUID) throws -> URL
    private let deletionCheckpoint: ((Job, DeletionCheckpoint) -> Void)?
    var changed: (([Job], Int, String?) -> Void)?

    init(directory: URL, controlCheckpoint: ((Job) -> Void)? = nil,
         deletionHandler: @escaping (URL, Bool, UUID) throws -> URL = DurableTransferQueue.performDeletion,
         deletionCheckpoint: ((Job, DeletionCheckpoint) -> Void)? = nil) {
        self.controlCheckpoint = controlCheckpoint
        self.deletionHandler = deletionHandler
        self.deletionCheckpoint = deletionCheckpoint
        storeURL = directory.appendingPathComponent("copy-jobs-v1.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: storeURL.path) {
                let data = try Data(contentsOf: storeURL)
                guard data.count <= 4 * 1024 * 1024 else { throw DurableFileCopy.Failure.invalidJournal }
                let stored = try JSONDecoder().decode(Store.self, from: data)
                guard stored.version == 1, (1...4).contains(stored.limit), stored.jobs.count <= 1000,
                    Set(stored.jobs.map(\.id)).count == stored.jobs.count else { throw DurableFileCopy.Failure.invalidJournal }
                limit = stored.limit
                jobs = stored.jobs.map { job in
                    var recovered = job
                    if [.running, .queued].contains(job.state) {
                        recovered.state = .paused
                        if let started = job.activeSince { recovered.elapsed = (job.elapsed ?? 0) + max(0, (job.lastActivity ?? started).timeIntervalSince(started)) }
                        recovered.activeSince = nil
                    }
                    recovered.requestedControl = nil; recovered.controlRequestedAt = nil
                    recovered.workPhase = nil; recovered.checkedBytes = nil; recovered.checkingTotal = nil
                    return recovered
                }
                try persist()
            }
        } catch { storeFailure = error }
    }
    func refresh() { serial.async { self.emit() } }
    /// A foreground action has already checked the running queue's paths. Keep
    /// paused/new jobs from starting underneath it via the still-visible panel.
    /// Existing independent workers continue; release schedules queued work.
    func setForegroundOperationActive(_ active: Bool) {
        serial.async {
            self.foregroundOperationActive = active
            if !active { self.commitAndSchedule() } else { self.emit() }
        }
    }
    /// UI mutations must not invalidate an active queued copy or move. Check
    /// against the authoritative queue, not a delayed display snapshot.
    func conflicts(reading: [URL] = [], writing: [URL] = []) -> Bool {
        func path(_ url: URL) -> String {
            url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).standardizedFileURL.path
        }
        let requests = reading.map { (path($0), false) } + writing.map { (path($0), true) }
        return serial.sync {
            jobs.contains { job in
                requests.contains { requested, write in Self.pathConflicts(requested: requested, writing: write, job: job) }
            }
        }
    }
    static func pathConflicts(requested: String, writing: Bool, job: Job) -> Bool {
        guard [.running, .queued, .paused].contains(job.state) else { return false }
        let requested = reservationPath(requested)
        func family(_ path: String) -> String {
            path.replacingOccurrences(of: #"(?: \([0-9]+\))+(?=\.[^./]+$|$)"#, with: "", options: .regularExpression)
        }
        func related(_ a: String, _ b: String) -> Bool { a == b || a == "/" || b == "/" || a.hasPrefix(b + "/") || b.hasPrefix(a + "/") }
        return [(job.source, job.move == true), (job.destination, true)].contains { reserved, otherWrite in
            let reserved = reservationPath(reserved)
            return (writing || otherWrite) && (related(requested, reserved) || related(family(requested), family(reserved)))
        }
    }
    /// Comparison only: never rewrite stored file identities/journal paths.
    /// Catalyst can standardize a live URL to /tmp while its persisted queue
    /// path remains /private/tmp. Both spellings reserve the same object.
    static func reservationPath(_ raw: String) -> String {
        var path = raw
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        for alias in ["/private/tmp", "/private/var", "/private/etc"] {
            if path == alias || path.hasPrefix(alias + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }
    func setLimit(_ value: Int) {
        serial.async {
            guard (1...4).contains(value) else { return }
            self.limit = value
            self.commitAndSchedule()
        }
    }
    func enqueue(source: URL, destination: URL, move: Bool = false, replace: Bool = false) {
        serial.async {
            guard self.storeFailure == nil else { self.emit(); return }
            guard self.jobs.count < 1000 else {
                self.admissionFailure = "transfer_queue_full"; self.emit(); return
            }
            var chosen = destination
            let name = destination.lastPathComponent as NSString
            var suffix = 2
            while !replace && (FileManager.default.fileExists(atPath: chosen.path) || self.jobs.contains(where: {
                ![.completed, .cancelled].contains($0.state) && $0.destination == chosen.path
            })) {
                chosen = destination.deletingLastPathComponent().appendingPathComponent(name.deletingPathExtension + " (\(suffix))" + (name.pathExtension.isEmpty ? "" : "." + name.pathExtension)); suffix += 1
            }
            self.jobs.append(Job(source: source.path, destination: chosen.path, move: move, replace: replace))
            self.commitAndSchedule()
        }
    }
    /// Admission captures the selected entry, not just a path that may point at
    /// a different file by the time an earlier reservation is released.
    func enqueueDeletion(source: URL, toTrash: Bool) {
        serial.async {
            guard self.storeFailure == nil else { self.emit(); return }
            guard self.jobs.count < 1000 else { self.admissionFailure = "transfer_queue_full"; self.emit(); return }
            do {
                guard source.isFileURL, let parent = realpath(source.deletingLastPathComponent().path, nil) else { throw CocoaError(.fileWriteInvalidFileName) }
                defer { free(parent) }
                let canonical = URL(fileURLWithPath: String(cString: parent)).appendingPathComponent(source.lastPathComponent)
                guard !self.jobs.contains(where: { $0.isDeletion && ![.completed, .cancelled].contains($0.state) &&
                    Self.reservationPath($0.source) == Self.reservationPath(canonical.path) }) else {
                    self.admissionFailure = "transfer_delete_already_queued"; self.emit(); return
                }
                let identity = try DeletionIdentity.read(canonical)
                var job = Job(source: canonical.path, destination: canonical.path, move: true)
                job.deleteToTrash = toTrash; job.deletionIdentity = identity; job.engine = "delete"
                job.deletionProofPending = identity.kind == UInt32(S_IFDIR)
                self.admissionFailure = nil
                self.jobs.append(job); self.commitAndSchedule()
            } catch { self.admissionFailure = "transfer_delete_admission_failed"; self.emit() }
        }
    }
    static func performDeletion(_ source: URL, toTrash: Bool, id: UUID) throws -> URL {
        let fm = FileManager.default
        if toTrash {
            var result: NSURL?
            try fm.trashItem(at: source, resultingItemURL: &result)
            guard let target = result as URL? else { throw CocoaError(.fileWriteUnknown) }
            return target
        }
        // The queue already moved this exact entry into its journaled private
        // recovery directory. "Delete" remains reversible, as foreground Delete.
        return source
    }
    func forget(_ id: UUID) {
        serial.async {
            self.jobs.removeAll { $0.id == id && $0.canForget }
            if self.jobs.count < 1000 { self.admissionFailure = nil }
            self.commitAndSchedule()
        }
    }
    /// Remove cards only, never transferred files, recovery data or unfinished work.
    func forgetCompleted() {
        serial.async {
            self.jobs.removeAll { $0.state == .completed }
            if self.jobs.count < 1000 { self.admissionFailure = nil }
            self.commitAndSchedule()
        }
    }
    static func removedCards(previous: [Job], current: [Job]) -> Bool {
        let remaining = Set(current.map(\.id))
        return previous.contains { $0.canForget && !remaining.contains($0.id) }
    }
    struct CardPage { let jobs: [Job]; let index: Int; let count: Int }
    static func cardPage(_ jobs: [Job], index: Int) -> CardPage {
        let size = 50
        let count = max(1, (jobs.count + size - 1) / size)
        let index = max(0, min(index, count - 1))
        return CardPage(jobs: Array(jobs.reversed().dropFirst(index * size).prefix(size)), index: index, count: count)
    }
    func control(_ id: UUID, _ command: DurableFileCopy.Control) {
        serial.async {
            guard let index = self.jobs.firstIndex(where: { $0.id == id }) else { return }
            let job = self.jobs[index]
            guard ![.completed, .cancelled].contains(job.state), job.requestedControl != "cancel" else { return }
            switch command {
            case .proceed:
                guard [.paused, .failed].contains(job.state) else { return }
            case .pause:
                guard [.queued, .running].contains(job.state), job.requestedControl == nil else { return }
            case .cancel: break
            }
            if self.jobs.count < 1000 { self.admissionFailure = nil }
            if let proof = self.deletionProofSignals[id], command != .proceed { proof.set(command) }
            if let signal = self.signals[id] {
                signal.set(command)
                let requested = command == .pause ? "pause" : command == .cancel ? "cancel" : nil
                if self.jobs[index].requestedControl != requested { self.jobs[index].controlRequestedAt = requested == nil ? nil : Date() }
                self.jobs[index].requestedControl = requested
                do { try self.persist() } catch { self.storeFailure = error }
                self.emit(); return
            }
            self.jobs[index].state = command == .proceed ? .queued : command == .pause ? .paused : .cancelled
            self.jobs[index].requestedControl = nil; self.jobs[index].controlRequestedAt = nil
            self.commitAndSchedule()
        }
    }
    /// Change the whole snapshot before scheduling, so pausing queued jobs
    /// cannot accidentally start another worker between individual requests.
    func controlAll(_ command: DurableFileCopy.Control) {
        serial.async {
            if self.jobs.count < 1000 { self.admissionFailure = nil }
            for index in self.jobs.indices {
                let job = self.jobs[index]
                if command == .proceed {
                    guard job.state == .paused else { continue }
                    self.jobs[index].state = .queued
                } else if command == .pause {
                    guard [.queued, .running].contains(job.state), job.requestedControl == nil else { continue }
                    self.deletionProofSignals[job.id]?.set(.pause)
                    if let signal = self.signals[job.id] {
                        signal.set(.pause)
                        self.jobs[index].requestedControl = "pause"
                        self.jobs[index].controlRequestedAt = Date()
                    } else { self.jobs[index].state = .paused }
                }
            }
            self.commitAndSchedule()
        }
    }
    func compact(_ id: UUID) {
        serial.async {
            guard let index = self.jobs.firstIndex(where: { $0.id == id }) else { return }
            self.jobs[index].compact.toggle()
            self.commitAndSchedule()
        }
    }
    private func emit() {
        // Expose stable localization keys, never a Foundation decoder message
        // or an already translated value that cannot follow language changes.
        let snapshot = Self.presentationSnapshot(jobs), parallelism = limit, error = storeFailure == nil ? admissionFailure : "transfer_store_error"
        DispatchQueue.main.async { [weak self] in self?.changed?(snapshot, parallelism, error) }
    }
    static func presentationSnapshot(_ jobs: [Job]) -> [Job] {
        jobs.map { job in
            var displayed = job
            displayed.waitingForReservedPaths = job.state == .queued && jobs.contains {
                $0.id != job.id && [.running, .paused].contains($0.state) && overlaps(job, $0)
            }
            return displayed
        }
    }
    private func persist() throws {
        let data = try JSONEncoder().encode(Store(limit: limit, jobs: jobs))
        let pending = storeURL.deletingLastPathComponent().appendingPathComponent(".jobs-\(UUID().uuidString).tmp")
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
        guard fsync(fd) == 0, rename(pending.path, storeURL.path) == 0 else { throw POSIXError(.EIO) }
        let directory = open(storeURL.deletingLastPathComponent().path, O_RDONLY | O_NOFOLLOW)
        guard directory >= 0 else { throw POSIXError(.EIO) }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw POSIXError(.EIO) }
    }
    private func commitAndSchedule() {
        do { guard storeFailure == nil else { emit(); return }; try persist(); schedule() }
        catch { storeFailure = error }
        emit()
    }
    static func overlaps(_ a: Job, _ b: Job) -> Bool {
        func family(_ path: String) -> String {
            path.replacingOccurrences(of: #"(?: \([0-9]+\))+(?=\.[^./]+$|$)"#, with: "", options: .regularExpression)
        }
        let left = [(reservationPath(a.source), a.move == true), (reservationPath(a.destination), true)]
        let right = [(reservationPath(b.source), b.move == true), (reservationPath(b.destination), true)]
        func related(_ a: String, _ b: String) -> Bool { a == b || a == "/" || b == "/" || a.hasPrefix(b + "/") || b.hasPrefix(a + "/") }
        return left.contains { path, write in right.contains { other, otherWrite in
            (write || otherWrite) && (related(path, other) || related(family(path), family(other)))
        } }
    }
    private func schedule() {
        guard storeFailure == nil, !foregroundOperationActive else { return }
        for job in jobs where job.state == .queued && job.deletionProofPending == true { startDeletionProof(job) }
        for index in jobs.indices where jobs[index].state == .queued {
            guard jobs[index].deletionProofPending != true else { continue }
            guard signals.count < limit else { break }
            let candidate = jobs[index]
            if jobs.contains(where: { $0.id != candidate.id && (signals[$0.id] != nil || $0.state == .paused) && Self.overlaps(candidate, $0) }) { continue }
            let signal = Signal(checkpoint: controlCheckpoint.map { handler in { handler(candidate) } })
            signals[candidate.id] = signal
            jobs[index].state = .running
            jobs[index].workPhase = .planning
            jobs[index].checkedBytes = nil; jobs[index].checkingTotal = nil
            jobs[index].requestedControl = nil; jobs[index].controlRequestedAt = nil
            jobs[index].activeSince = Date(); jobs[index].lastActivity = Date()
            do { try persist() } catch { signals.removeValue(forKey: candidate.id); storeFailure = error; return }
            workers.async { self.run(candidate, signal: signal) }
        }
    }
    private func startDeletionProof(_ job: Job) {
        guard deletionProofSignals[job.id] == nil else { return }
        let signal = Signal(checkpoint: controlCheckpoint.map { handler in { handler(job) } })
        deletionProofSignals[job.id] = signal
        deletionProofWorker.async {
            do {
                let source = URL(fileURLWithPath: job.source)
                let proof = try SafeFileOperations.snapshot(source, checkCancellation: {
                    guard signal.get() == .proceed else { throw DurableFileCopy.Failure.interrupted }
                })
                guard try DeletionIdentity.read(source) == job.deletionIdentity else { throw DurableFileCopy.Failure.changedSource }
                self.serial.async {
                    self.deletionProofSignals.removeValue(forKey: job.id)
                    if let index = self.jobs.firstIndex(where: { $0.id == job.id }), self.jobs[index].state != .cancelled {
                        self.jobs[index].deletionProof = proof
                        self.jobs[index].deletionProofPending = false
                    }
                    self.commitAndSchedule()
                }
            } catch {
                let command = signal.get()
                self.serial.async {
                    self.deletionProofSignals.removeValue(forKey: job.id)
                    if let index = self.jobs.firstIndex(where: { $0.id == job.id }),
                       ![.cancelled, .paused].contains(self.jobs[index].state), command == .proceed {
                        self.jobs[index].state = .failed
                        self.jobs[index].errorKey = "transfer_delete_changed"
                        self.jobs[index].failure = HistoryFailure(error)
                    }
                    self.commitAndSchedule()
                }
            }
        }
    }
    private func run(_ job: Job, signal: Signal) {
        if job.isDeletion { runDeletion(job, signal: signal); return }
        var staging = job.staging.map { URL(fileURLWithPath: $0) }
        do {
            let source = URL(fileURLWithPath: job.source), destination = URL(fileURLWithPath: job.destination)
            let type = try? FileManager.default.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType
            let nas = job.engine == "nas-exclusive" || (staging == nil &&
                (NASExclusiveCopy.isSMB(destination.deletingLastPathComponent()) || NASExclusiveCopy.isSMB(source.deletingLastPathComponent())))
            let tree = job.engine == "tree" || (staging == nil && (job.move == true || job.replace == true || type == .typeDirectory || type == .typeSymbolicLink))
            if staging == nil {
                if nas {
                    staging = try NASExclusiveCopy.create(source: source, target: destination,
                        journalParent: destination.deletingLastPathComponent(), replace: job.replace == true, move: job.move == true)
                } else if tree {
                    staging = try DurableTreeTransfer.create(source: source, destination: destination, move: job.move == true, replace: job.replace == true, check: {
                        guard signal.get() == .proceed else { throw DurableFileCopy.Failure.interrupted }
                    })
                } else { staging = try DurableFileCopy.create(source: source, destination: destination) }
                try serial.sync {
                    guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { throw DurableFileCopy.Failure.invalidJournal }
                    jobs[index].staging = staging!.path
                    jobs[index].engine = nas ? "nas-exclusive" : tree ? "tree" : "file"
                    try persist()
                }
            }
            let report: (Int64, Int64) -> Void = { bytes, total in
                // Checkpoints are already durable in the engine. UI updates are
                // coalesced to four per second rather than emitting every block.
                self.serial.async {
                    guard let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                    self.jobs[index].bytes = bytes; self.jobs[index].total = total
                    self.jobs[index].lastActivity = Date()
                    if Date().timeIntervalSince(self.lastMetricsSave) >= 1 {
                        self.lastMetricsSave = Date()
                        do { try self.persist() } catch { self.storeFailure = error }
                    }
                    self.emitProgressIfDue()
                }
            }
            let fileProgress: (Int, Int) -> Void = { done, total in
                self.serial.async {
                    guard let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                    self.jobs[index].filesDone = done; self.jobs[index].filesTotal = total
                    self.emitProgressIfDue()
                }
            }
            let state: DurableFileCopy.State, bytes: Int64, backup: String?, quarantine: String?
            var lastActivityUpdate = Date.distantPast
            var lastPhase: DurableFileCopy.WorkPhase?
            let activity: (DurableFileCopy.Activity) -> Void = { value in
                guard lastPhase != value.phase || Date().timeIntervalSince(lastActivityUpdate) >= 0.1 || value.done == value.total else { return }
                lastPhase = value.phase; lastActivityUpdate = Date()
                self.serial.async {
                    guard let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                    self.jobs[index].workPhase = value.phase
                    self.jobs[index].checkedBytes = value.done; self.jobs[index].checkingTotal = value.total
                    self.jobs[index].lastActivity = Date()
                    if Date().timeIntervalSince(self.lastMetricsSave) >= 1 {
                        self.lastMetricsSave = Date()
                        do { try self.persist() } catch { self.storeFailure = error }
                    }
                    self.emitProgressIfDue()
                }
            }
            if nas {
                activity(.init(phase: .copying))
                let planned = try NASExclusiveCopy.summary(staging!)
                report(planned.bytes, planned.total)
                let outcome = try NASExclusiveCopy.resume(staging!, control: {
                    switch signal.get() { case .proceed: return .proceed; case .pause: return .pause; case .cancel: return .cancel }
                }, progress: { report($0, planned.total) }, fileProgress: fileProgress)
                let result = try NASExclusiveCopy.summary(staging!)
                state = outcome == .completed ? .completed : outcome == .cancelled ? .cancelled : .paused
                bytes = result.bytes; backup = result.backup?.path; quarantine = result.quarantine?.path
            } else if tree {
                let result = try DurableTreeTransfer.resume(staging!, control: signal.get, progress: report, fileProgress: fileProgress, activity: activity)
                state = result.state; bytes = result.bytes; backup = result.backup?.path; quarantine = result.quarantine?.path
            } else {
                fileProgress(0, 1)
                let result = try DurableFileCopy.resume(staging!, control: signal.get, progress: report, activity: activity)
                if result.state == .completed { fileProgress(1, 1) }
                state = result.state; bytes = result.bytes; backup = nil; quarantine = nil
            }
            serial.async {
                if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                    self.jobs[index].bytes = bytes
                    self.jobs[index].backup = backup; self.jobs[index].quarantine = quarantine
                    self.finishElapsed(index)
                    self.jobs[index].state = state == .completed ? .completed : state == .cancelled ? .cancelled : .paused
                }
                self.signals.removeValue(forKey: job.id)
                self.commitAndSchedule()
            }
        } catch {
            let networkInterrupted = staging?.lastPathComponent.hasPrefix(".OpenCommanderExclusive-") == true && NASExclusiveCopy.isConnectionFailure(error)
            serial.async {
                if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                    let command = signal.get()
                    self.jobs[index].state = command == .pause ? .paused : command == .cancel ? .cancelled : networkInterrupted ? .paused : .failed
                    if command == .proceed {
                        let coded = [NSCocoaErrorDomain, NSPOSIXErrorDomain].contains((error as NSError).domain)
                        self.jobs[index].errorKey = networkInterrupted ? "transfer_nas_reconnect" : nil
                        self.jobs[index].failure = coded && !networkInterrupted ? HistoryFailure(error) : nil
                        self.jobs[index].error = coded || networkInterrupted ? nil : error.localizedDescription
                        self.jobs[index].recoveryPath = nil
                        if let staging, staging.lastPathComponent.hasPrefix(".OpenCommanderExclusive-") {
                            self.jobs[index].recoveryPath = staging.path
                        }
                    }
                    self.jobs[index].staging = staging?.path
                    self.finishElapsed(index)
                }
                self.signals.removeValue(forKey: job.id)
                self.commitAndSchedule()
            }
        }
    }
    private func runDeletion(_ job: Job, signal: Signal) {
        var deletionAttempted = false
        do {
            let command = signal.get()
            guard command == .proceed else {
                serial.async {
                    if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                        self.jobs[index].state = command == .cancel ? .cancelled : .paused
                        self.finishElapsed(index)
                    }
                    self.signals.removeValue(forKey: job.id); self.commitAndSchedule()
                }
                return
            }
            let source = URL(fileURLWithPath: job.source)
            guard let expected = job.deletionIdentity else { throw CocoaError(.fileReadCorruptFile) }
            func verifyContents(_ url: URL, cancellable: Bool) throws {
                guard expected.kind == UInt32(S_IFDIR) else { return }
                guard let proof = job.deletionProof, job.deletionProofPending != true else { throw CocoaError(.fileReadCorruptFile) }
                let actual = try SafeFileOperations.snapshot(url, rootName: source.lastPathComponent, checkCancellation: {
                    if cancellable, signal.get() != .proceed { throw DurableFileCopy.Failure.interrupted }
                })
                guard actual == proof else { throw DurableFileCopy.Failure.changedSource }
            }
            let stage = source.deletingLastPathComponent().appendingPathComponent(".OpenCommanderUndo-" + job.id.uuidString)
            if job.staging == nil {
                guard try DeletionIdentity.read(source) == expected else { throw DurableFileCopy.Failure.changedSource }
                try verifyContents(source, cancellable: true)
            }
            if let saved = job.staging {
                guard Self.reservationPath(saved) == Self.reservationPath(stage.path) else { throw CocoaError(.fileReadCorruptFile) }
            } else {
                guard !SafeFileOperations.exists(stage) else { throw CocoaError(.fileWriteFileExists) }
                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try FileManager.default.createDirectory(at: stage.appendingPathComponent("items"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try serial.sync {
                    guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { throw CocoaError(.fileReadCorruptFile) }
                    jobs[index].staging = stage.path
                    try persist() // Write-ahead location, before removing any visible entry.
                }
            }
            var stageInfo = stat()
            guard lstat(stage.path, &stageInfo) == 0, stageInfo.st_mode & S_IFMT == S_IFDIR,
                  stageInfo.st_uid == getuid(), stageInfo.st_mode & 0o077 == 0 else { throw CocoaError(.fileReadCorruptFile) }
            let items = stage.appendingPathComponent("items")
            var itemsInfo = stat()
            guard lstat(items.path, &itemsInfo) == 0, itemsInfo.st_mode & S_IFMT == S_IFDIR,
                  itemsInfo.st_uid == getuid(), itemsInfo.st_mode & 0o077 == 0 else { throw CocoaError(.fileReadCorruptFile) }
            let payload = items.appendingPathComponent(source.lastPathComponent)
            let receipt = stage.appendingPathComponent("deletion-receipt.json")
            let reference = stage.appendingPathComponent("selected-bookmark.json")
            let destination: URL
            if SafeFileOperations.exists(receipt) {
                deletionAttempted = true // A prior OS mutation may already be complete; never claim a no-effect cancellation.
                let fd = open(receipt.path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { throw CocoaError(.fileReadCorruptFile) }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                let data = try handle.read(upToCount: 16 * 1024 + 1) ?? Data(); try handle.close()
                guard data.count <= 16 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                let saved = try JSONDecoder().decode(DeletionReceipt.self, from: data)
                destination = URL(fileURLWithPath: saved.destination)
                guard saved.id == job.id, saved.identity == expected,
                      try DeletionIdentity.read(destination) == expected else { throw CocoaError(.fileReadCorruptFile) }
                try verifyContents(destination, cancellable: true)
            } else {
                var recoveredTrash: URL?
                if job.deleteToTrash == true, !SafeFileOperations.exists(payload), SafeFileOperations.exists(reference) {
                    deletionAttempted = true // An interrupted OS action may have completed already.
                    let saved = try JSONDecoder().decode(DeletionReference.self, from: Self.readDeletionData(reference, limit: 1024 * 1024))
                    guard saved.id == job.id, saved.identity == expected else { throw CocoaError(.fileReadCorruptFile) }
                    let candidate = try Self.resolveDeletionReference(saved, check: {
                        guard signal.get() == .proceed else { throw DurableFileCopy.Failure.interrupted }
                    })
                    if try Self.isDeletionInTrash(candidate) {
                        deletionAttempted = true
                        recoveredTrash = candidate
                    } else {
                        // A cooperative pause may have restored the exact entry
                        // before the OS action. Never act on another location.
                        guard Self.reservationPath(candidate.path) == Self.reservationPath(source.path) else { throw CocoaError(.fileReadCorruptFile) }
                        deletionAttempted = false
                    }
                }
                if let recoveredTrash {
                    destination = recoveredTrash
                    try verifyContents(destination, cancellable: true)
                } else {
                if !SafeFileOperations.exists(payload) {
                    guard expected == (try DeletionIdentity.read(source)) else { throw CocoaError(.fileReadCorruptFile) }
                    if job.staging != nil { try verifyContents(source, cancellable: true) }
                    // No-follow atomic rename closes the gap between validating
                    // the path and acting on it. Validate again after rename.
                    guard renamex_np(source.path, payload.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    do {
                        guard try DeletionIdentity.read(payload) == expected else { throw DurableFileCopy.Failure.changedSource }
                        try verifyContents(payload, cancellable: true)
                    } catch {
                        // Never overwrite a newly appeared source on rollback.
                        _ = renamex_np(payload.path, source.path, UInt32(RENAME_EXCL))
                        throw error
                    }
                    try Self.syncDeletionDirectory(source.deletingLastPathComponent())
                    try Self.syncDeletionDirectory(items)
                } else {
                    guard try DeletionIdentity.read(payload) == expected else { throw CocoaError(.fileReadCorruptFile) }
                    try verifyContents(payload, cancellable: true)
                }
                if job.deleteToTrash == true {
                    if !SafeFileOperations.exists(reference) {
                        let data = try payload.bookmarkData(options: [.minimalBookmark, .withoutImplicitSecurityScope],
                            includingResourceValuesForKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey], relativeTo: nil)
                        let proof = try SafeFileOperations.snapshot(payload, rootName: source.lastPathComponent, checkCancellation: {
                            guard signal.get() == .proceed else { throw DurableFileCopy.Failure.interrupted }
                        })
                        let saved = DeletionReference(id: job.id, identity: expected, bookmark: data, proof: proof, rootName: source.lastPathComponent)
                        try Self.saveDeletionData(JSONEncoder().encode(saved), to: reference, stage: stage)
                    }
                    let saved = try JSONDecoder().decode(DeletionReference.self, from: Self.readDeletionData(reference, limit: 1024 * 1024))
                    guard saved.id == job.id, saved.identity == expected else { throw CocoaError(.fileReadCorruptFile) }
                    let selected = try Self.resolveDeletionReference(saved, check: {
                        guard signal.get() == .proceed else { throw DurableFileCopy.Failure.interrupted }
                    })
                    guard Self.reservationPath(selected.path) == Self.reservationPath(payload.path) else { throw CocoaError(.fileReadCorruptFile) }
                }
                guard signal.get() == .proceed else {
                    // Proof reads can take time. Honour control before the OS
                    // deletion action and restore the selected entry if possible.
                    _ = renamex_np(payload.path, source.path, UInt32(RENAME_EXCL))
                    throw DurableFileCopy.Failure.interrupted
                }
                deletionAttempted = true
                destination = try deletionHandler(payload, job.deleteToTrash == true, job.id)
                deletionCheckpoint?(job, .afterMutationBeforeReceipt)
                guard try DeletionIdentity.read(destination) == expected else { throw CocoaError(.fileReadCorruptFile) }
                try verifyContents(destination, cancellable: false)
                }
                let data = try JSONEncoder().encode(DeletionReceipt(id: job.id, destination: destination.path, identity: expected))
                try Self.saveDeletionData(data, to: receipt, stage: stage)
                deletionCheckpoint?(job, .afterReceipt)
            }
            serial.async {
                if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                    self.jobs[index].destination = destination.path
                    // The atomic filesystem action already happened; a late
                    // Cancel must not falsely report that nothing was removed.
                    self.jobs[index].state = .completed; self.finishElapsed(index)
                }
                self.signals.removeValue(forKey: job.id); self.commitAndSchedule()
            }
        } catch {
            let command = signal.get()
            if !deletionAttempted, command != .proceed, let expected = job.deletionIdentity {
                let source = URL(fileURLWithPath: job.source)
                let payload = source.deletingLastPathComponent().appendingPathComponent(".OpenCommanderUndo-" + job.id.uuidString + "/items/" + source.lastPathComponent)
                if let actual = try? DeletionIdentity.read(payload), actual.device == expected.device,
                   actual.inode == expected.inode, actual.kind == expected.kind {
                    _ = renamex_np(payload.path, source.path, UInt32(RENAME_EXCL))
                }
            }
            let state: State = !deletionAttempted && command != .proceed ? (command == .cancel ? .cancelled : .paused) : .failed
            serial.async {
                if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                    self.jobs[index].state = state
                    if state == .failed {
                        self.jobs[index].errorKey = "transfer_delete_changed"
                        self.jobs[index].failure = HistoryFailure(error)
                        self.jobs[index].recoveryPath = self.jobs[index].staging
                    } else if state == .cancelled,
                              SafeFileOperations.exists(URL(fileURLWithPath: job.source)),
                              let stage = self.jobs[index].staging,
                              !SafeFileOperations.exists(URL(fileURLWithPath: stage).appendingPathComponent("items/" + URL(fileURLWithPath: job.source).lastPathComponent)) {
                        self.jobs[index].staging = nil // Only empty bookkeeping remains, not retained user data.
                    }
                    self.finishElapsed(index)
                }
                self.signals.removeValue(forKey: job.id); self.commitAndSchedule()
            }
        }
    }
    private struct DeletionReceipt: Codable { let id: UUID; let destination: String; let identity: DeletionIdentity }
    private struct DeletionReference: Codable {
        let id: UUID; let identity: DeletionIdentity; let bookmark: Data; let proof: Data; let rootName: String
    }
    private static func readDeletionData(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let data = try handle.read(upToCount: limit + 1) ?? Data(); try handle.close()
        guard data.count <= limit else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
    private static func saveDeletionData(_ data: Data, to url: URL, stage: URL) throws {
        let pending = stage.appendingPathComponent(".metadata-" + UUID().uuidString)
        let fd = open(pending.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        guard renamex_np(pending.path, url.path, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EIO) }
        try syncDeletionDirectory(stage)
    }
    private static func resolveDeletionReference(_ saved: DeletionReference, check: () throws -> Void = {}) throws -> URL {
        guard saved.proof.count == 32, !saved.rootName.isEmpty, !saved.rootName.contains("/") else { throw CocoaError(.fileReadCorruptFile) }
        var stale = false
        let url = try URL(resolvingBookmarkData: saved.bookmark, options: [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard try DeletionIdentity.read(url) == saved.identity,
              try SafeFileOperations.snapshot(url, rootName: saved.rootName, checkCancellation: check) == saved.proof else { throw CocoaError(.fileReadCorruptFile) }
        return url
    }
    private static func isDeletionInTrash(_ url: URL) throws -> Bool {
        let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)
        let root = trash.resolvingSymlinksInPath().standardizedFileURL.path
        // Do not follow a selected symlink itself outside Trash.
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        return parent == root || parent.hasPrefix(root + "/")
    }
    private static func syncDeletionDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    private var lastProgress = Date.distantPast
    private var lastMetricsSave = Date.distantPast
    private func finishElapsed(_ index: Int) {
        if let start = jobs[index].activeSince { jobs[index].elapsed = (jobs[index].elapsed ?? 0) + max(0, Date().timeIntervalSince(start)) }
        jobs[index].activeSince = nil; jobs[index].lastActivity = Date()
        jobs[index].requestedControl = nil; jobs[index].controlRequestedAt = nil
    }
    private func emitProgressIfDue() {
        guard Date().timeIntervalSince(lastProgress) >= 0.25 else { return }
        lastProgress = Date(); emit()
    }
}

/// Presentation-only, monotonic rolling throughput. Never persisted or used to
/// decide whether data is valid, a job may resume, or publication succeeded.
struct TransferRateEstimator {
    struct Estimate { let bytesPerSecond: Double; let remaining: TimeInterval? }
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    private var generation: Date?
    private var lastIncrease: TimeInterval?
    mutating func observe(_ job: DurableTransferQueue.Job, uptime: TimeInterval) -> Estimate? {
        guard uptime.isFinite, job.state == .running, job.workPhase == .copying,
              !job.isDeletion, job.requestedControl == nil, job.bytes >= 0, job.total >= job.bytes else {
            samples.removeAll(); generation = nil; lastIncrease = nil; return nil
        }
        if generation != job.activeSince || samples.last.map({ uptime <= $0.time || job.bytes < $0.bytes }) == true {
            samples.removeAll(); lastIncrease = nil
        }
        generation = job.activeSince
        if let last = samples.last, job.bytes > last.bytes { lastIncrease = uptime }
        samples.append((uptime, job.bytes))
        // Keep one sample just outside the five-second window for a stable
        // slope, with bounded storage even when the UI refreshes very often.
        while samples.count > 2 && samples[1].time < uptime - 5 { samples.removeFirst() }
        if samples.count > 128 { samples.removeFirst(samples.count - 128) }
        guard let first = samples.first, let lastIncrease, uptime - lastIncrease < 3,
              uptime - first.time >= 0.25, job.bytes > first.bytes else { return nil }
        let rate = Double(job.bytes - first.bytes) / (uptime - first.time)
        guard rate.isFinite, rate > 0 else { return nil }
        let remaining = job.total > job.bytes ? Double(job.total - job.bytes) / rate : nil
        return Estimate(bytesPerSecond: rate, remaining: remaining.flatMap { $0.isFinite ? $0 : nil })
    }
}
#endif
