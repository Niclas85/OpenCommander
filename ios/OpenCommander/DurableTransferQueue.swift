import Foundation
import Darwin
#if os(macOS) || targetEnvironment(macCatalyst)

/// Durable local transfers; online providers keep their coordinated adapters.
final class DurableTransferQueue {
    enum State: String, Codable { case queued, running, paused, cancelled, failed, completed }
    struct Job: Codable {
        var id = UUID()
        var source: String
        var destination: String
        var staging: String?
        var state: State = .queued
        var bytes: Int64 = 0
        var total: Int64 = 0
        var created = Date()
        var compact = true
        var error: String?
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
        var isChecking: Bool { state != .completed && (workPhase == .checkingPartial || workPhase == .verifying) }
        var progressFraction: Float {
            if state == .completed { return 1 }
            let done = isChecking ? checkedBytes ?? 0 : bytes
            let expected = isChecking ? checkingTotal ?? 0 : total
            return expected > 0 ? Float(max(0, min(done, expected))) / Float(expected) : 0
        }
        var statusKey: String {
            if state == .running, let requestedControl { return requestedControl == "pause" ? "transfer_pausing" : "transfer_cancelling" }
            if state == .running, let workPhase, workPhase != .copying { return "transfer_phase_" + workPhase.rawValue }
            return state == .running && move == true ? "transfer_moving" : "transfer_" + state.rawValue
        }
    }
    private struct Store: Codable { var version = 1; var limit: Int; var jobs: [Job] }
    private final class Signal {
        private let lock = NSLock()
        private var value = DurableFileCopy.Control.proceed
        func set(_ value: DurableFileCopy.Control) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> DurableFileCopy.Control { lock.lock(); defer { lock.unlock() }; return value }
    }
    private let serial = DispatchQueue(label: "OpenCommander.DurableTransferQueue")
    private let workers = DispatchQueue(label: "OpenCommander.DurableTransferWorkers", qos: .utility, attributes: .concurrent)
    private let storeURL: URL
    private var jobs: [Job] = []
    private var signals: [UUID: Signal] = [:]
    private var limit = 2
    private var storeFailure: Error?
    private var admissionFailure: String?
    private var foregroundOperationActive = false
    var changed: (([Job], Int, String?) -> Void)?

    init(directory: URL) {
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
    func forget(_ id: UUID) {
        serial.async {
            self.jobs.removeAll { $0.id == id && [.completed, .cancelled].contains($0.state) && !($0.engine == "nas-exclusive" && $0.state != .completed) }
            if self.jobs.count < 1000 { self.admissionFailure = nil }
            self.commitAndSchedule()
        }
    }
    func control(_ id: UUID, _ command: DurableFileCopy.Control) {
        serial.async {
            guard let index = self.jobs.firstIndex(where: { $0.id == id }) else { return }
            if let signal = self.signals[id] {
                signal.set(command)
                let requested = command == .pause ? "pause" : command == .cancel ? "cancel" : nil
                if self.jobs[index].requestedControl != requested { self.jobs[index].controlRequestedAt = requested == nil ? nil : Date() }
                self.jobs[index].requestedControl = requested
                do { try self.persist() } catch { self.storeFailure = error }
                self.emit(); return
            }
            guard ![.completed, .cancelled].contains(self.jobs[index].state) else { return }
            self.jobs[index].state = command == .proceed ? .queued : command == .pause ? .paused : .cancelled
            self.jobs[index].requestedControl = nil; self.jobs[index].controlRequestedAt = nil
            self.commitAndSchedule()
        }
    }
    /// Change the whole snapshot before scheduling, so pausing queued jobs
    /// cannot accidentally start another worker between individual requests.
    func controlAll(_ command: DurableFileCopy.Control) {
        serial.async {
            for index in self.jobs.indices {
                let job = self.jobs[index]
                if command == .proceed {
                    guard job.state == .paused else { continue }
                    self.jobs[index].state = .queued
                } else if command == .pause {
                    guard [.queued, .running].contains(job.state) else { continue }
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
        let snapshot = jobs, parallelism = limit, error = storeFailure?.localizedDescription ?? admissionFailure.map { L10n.get($0) }
        DispatchQueue.main.async { [weak self] in self?.changed?(snapshot, parallelism, error) }
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
        for index in jobs.indices where jobs[index].state == .queued {
            guard signals.count < limit else { break }
            let candidate = jobs[index]
            if jobs.contains(where: { $0.id != candidate.id && (signals[$0.id] != nil || $0.state == .paused) && Self.overlaps(candidate, $0) }) { continue }
            let signal = Signal(); signals[candidate.id] = signal
            jobs[index].state = .running
            jobs[index].workPhase = .planning
            jobs[index].checkedBytes = nil; jobs[index].checkingTotal = nil
            jobs[index].requestedControl = nil; jobs[index].controlRequestedAt = nil
            jobs[index].activeSince = Date(); jobs[index].lastActivity = Date()
            do { try persist() } catch { signals.removeValue(forKey: candidate.id); storeFailure = error; return }
            workers.async { self.run(candidate, signal: signal) }
        }
    }
    private func run(_ job: Job, signal: Signal) {
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
                }, progress: { report($0, planned.total) })
                let result = try NASExclusiveCopy.summary(staging!)
                state = outcome == .completed ? .completed : outcome == .cancelled ? .cancelled : .paused
                bytes = result.bytes; backup = result.backup?.path; quarantine = result.quarantine?.path
            } else if tree {
                let result = try DurableTreeTransfer.resume(staging!, control: signal.get, progress: report, activity: activity)
                state = result.state; bytes = result.bytes; backup = result.backup?.path; quarantine = result.quarantine?.path
            } else {
                let result = try DurableFileCopy.resume(staging!, control: signal.get, progress: report, activity: activity)
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
                        self.jobs[index].error = networkInterrupted ? L10n.get("transfer_nas_reconnect") : error.localizedDescription
                        if let staging, staging.lastPathComponent.hasPrefix(".OpenCommanderExclusive-") {
                            self.jobs[index].error! += "\n" + L10n.get("recovery_retained", staging.path)
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
#endif
