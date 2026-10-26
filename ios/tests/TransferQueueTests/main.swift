import Foundation
import Darwin
setbuf(stdout, nil)

func require(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 30) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    require(condition(), "queue condition timed out")
}
do {
    let language = L10n.currentLanguage
    defer { L10n.currentLanguage = language }
    var coded = DurableTransferQueue.Job(source: "/synthetic/source", destination: "/synthetic/target")
    coded.failure = HistoryFailure(POSIXError(.ENOSPC))
    let data = try JSONEncoder().encode(coded)
    let reopened = try JSONDecoder().decode(DurableTransferQueue.Job.self, from: data)
    L10n.currentLanguage = "de"
    require(reopened.errorMessage == L10n.get("history_error_space") && reopened.errorMessage!.contains("Speicher"), "saved ENOSPC not German")
    L10n.currentLanguage = "en"
    require(reopened.errorMessage == L10n.get("history_error_space") && reopened.errorMessage!.contains("free space"), "saved ENOSPC not dynamically translated")
    require(!String(decoding: data, as: UTF8.self).contains("free space"), "queue persisted translated OS error")
    var completedRetry = reopened
    completedRetry.state = .completed
    require(completedRetry.errorMessage == nil, "successful retry still displays stale failure")
    let completedBytes = try JSONEncoder().encode(completedRetry)
    let completedReopened = try JSONDecoder().decode(DurableTransferQueue.Job.self, from: completedBytes)
    require(completedReopened.errorMessage == nil && completedReopened.failure != nil,
            "successful retry must hide old error while preserving prior-attempt evidence")
    completedRetry.state = .failed
    require(completedRetry.errorMessage != nil, "current failure was hidden")
    print("PASS completed retry hides stale error, preserves persisted failure evidence and still shows current failures")
    var cancelled = DurableTransferQueue.Job(source: "/synthetic/source", destination: "/synthetic/target")
    cancelled.state = .cancelled
    require(cancelled.statusKey == "transfer_cancelled_no_data", "queued cancellation falsely claims retained partial data")
    for property in ["staging", "recovery", "backup", "quarantine"] {
        var retained = cancelled
        if property == "staging" { retained.staging = "/synthetic/stage" }
        if property == "recovery" { retained.recoveryPath = "/synthetic/recovery" }
        if property == "backup" { retained.backup = "/synthetic/backup" }
        if property == "quarantine" { retained.quarantine = "/synthetic/quarantine" }
        let restored = try JSONDecoder().decode(DurableTransferQueue.Job.self, from: JSONEncoder().encode(retained))
        require(restored.statusKey == "transfer_cancelled", "retained cancellation data hidden after reopen: " + property)
    }
    L10n.currentLanguage = "de"
    require(L10n.get(cancelled.statusKey).contains("keine"), "cancelled-without-data German caption missing")
    L10n.currentLanguage = "en"
    require(L10n.get(cancelled.statusKey).contains("no partial"), "cancelled-without-data English caption missing")
    print("PASS queued cancellation has no false retention claim; staged/recovery/backup/quarantine data stay explicit after reopen")
    coded.errorKey = "transfer_nas_reconnect"
    coded.recoveryPath = "/synthetic/recovery"
    let network = try JSONDecoder().decode(DurableTransferQueue.Job.self, from: JSONEncoder().encode(coded))
    require(network.errorMessage!.hasPrefix(L10n.get("transfer_nas_reconnect")) && network.errorMessage!.contains("/synthetic/recovery"), "coded NAS reconnect lost recovery diagnostics")
    print("PASS queue coded ENOSPC persists without language-frozen OS text; DE/EN rerender and NAS recovery details")
}
let root = URL(fileURLWithPath: "/private/tmp/OpenCommander-QueueTests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }
let source = root.appendingPathComponent("source")
let bytes = Data(repeating: 37, count: 2 * 1024 * 1024)
try bytes.write(to: source)
let store = root.appendingPathComponent("state")
do {
    let folderRoot = root.appendingPathComponent("folder-deletion")
    try FileManager.default.createDirectory(at: folderRoot, withIntermediateDirectories: false)
    let external = folderRoot.appendingPathComponent("outside.txt")
    let outside = Data("Outside target must never be followed or changed\n".utf8)
    try outside.write(to: external)
    for scenario in ["unchanged", "edited-child", "added-child", "cancel-proof", "pause-proof", "cancel-staged-proof"] {
        let area = folderRoot.appendingPathComponent(scenario)
        try FileManager.default.createDirectory(at: area, withIntermediateDirectories: false)
        let source = area.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Nested/Empty"), withIntermediateDirectories: true)
        let original = Data("Original child\n".utf8)
        let child = source.appendingPathComponent("Nested/child.txt")
        try original.write(to: child)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("outside-link").path, withDestinationPath: external.path)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("cycle-link").path, withDestinationPath: source.path)
        let admission = try SafeFileOperations.snapshot(source)
        let gate = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let gateLock = NSLock(); var blockOnce = ["cancel-proof", "pause-proof", "cancel-staged-proof"].contains(scenario)
        let queue = DurableTransferQueue(directory: area.appendingPathComponent("queue"), controlCheckpoint: { job in
            guard job.isDeletion else { return }
            if scenario == "cancel-staged-proof" {
                guard job.deletionProofPending != true,
                      !FileManager.default.fileExists(atPath: source.path),
                      FileManager.default.fileExists(atPath: source.deletingLastPathComponent().appendingPathComponent(".OpenCommanderUndo-" + job.id.uuidString + "/items/" + source.lastPathComponent).path) else { return }
            } else { guard job.deletionProofPending == true else { return } }
            gateLock.lock(); let block = blockOnce; blockOnce = false; gateLock.unlock()
            if block { entered.signal(); _ = gate.wait(timeout: .now() + 10) }
        })
        var jobs: [DurableTransferQueue.Job] = []; var updates = 0
        queue.changed = { current, _, error in require(error == nil, "folder proof admission failed"); jobs = current; updates += 1 }
        queue.setForegroundOperationActive(true)
        queue.enqueue(source: source, destination: area.appendingPathComponent("NeverCopied"))
        waitFor({ jobs.count == 1 }); let blocker = jobs[0].id
        queue.control(blocker, .pause); waitFor({ jobs[0].state == .paused })
        queue.enqueueDeletion(source: source, toTrash: false)
        waitFor({ jobs.count == 2 }); let deletion = jobs[1].id
        queue.setForegroundOperationActive(false)
        if scenario == "cancel-proof" || scenario == "pause-proof" {
            require(entered.wait(timeout: .now() + 5) == .success, "folder proof never started")
            queue.control(deletion, scenario == "pause-proof" ? .pause : .cancel)
            waitFor({ jobs[1].state == (scenario == "pause-proof" ? .paused : .cancelled) })
            let before = updates; gate.signal()
            waitFor({ updates > before })
            require(jobs[0].state == .paused, "cancel proof started unrelated paused job")
            let after = try SafeFileOperations.snapshot(source)
            require(after == admission, "cancel proof changed source tree")
            if scenario == "pause-proof" {
                queue.changed = nil
                let reopened = DurableTransferQueue(directory: area.appendingPathComponent("queue"))
                var restored: [DurableTransferQueue.Job] = []
                reopened.changed = { current, _, error in require(error == nil, "paused proof reopen failed"); restored = current }
                reopened.refresh(); waitFor({ restored.count == 2 })
                require(restored.allSatisfy { $0.state == .paused } && restored[1].deletionProofPending == true,
                        "interrupted admission proof lost its explicit pause or restarted automatically")
                reopened.control(deletion, .proceed)
                waitFor({ restored[1].deletionProof != nil && restored[1].state == .queued })
                reopened.control(blocker, .cancel); waitFor({ restored[1].state == .completed })
                try FileManager.default.moveItem(at: URL(fileURLWithPath: restored[1].destination), to: source)
                let returned = try SafeFileOperations.snapshot(source)
                require(returned == admission, "resumed folder proof/restore changed source tree")
            } else {
                queue.control(blocker, .cancel); waitFor({ jobs[0].state == .cancelled })
            }
        } else {
            waitFor({ jobs[1].deletionProof != nil && jobs[1].deletionProofPending == false })
            require(jobs[1].state == .queued && jobs[1].statusKey == "transfer_waiting_paths", "proved folder ignored reservation")
            if scenario == "edited-child" {
                let attributes = try FileManager.default.attributesOfItem(atPath: child.path)
                try Data("Modified child\n".utf8).write(to: child)
                try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: child.path)
            } else if scenario == "added-child" {
                try Data("New child\n".utf8).write(to: source.appendingPathComponent("added.txt"))
            }
            let requestedVersion = try SafeFileOperations.snapshot(source)
            queue.control(blocker, .cancel)
            if scenario == "cancel-staged-proof" {
                require(entered.wait(timeout: .now() + 5) == .success, "post-rename folder proof never reached checkpoint")
                queue.control(deletion, .cancel)
                waitFor({ jobs[1].requestedControl == "cancel" })
                gate.signal(); waitFor({ jobs[1].state == .cancelled })
                let returned = try SafeFileOperations.snapshot(source)
                require(returned == admission && jobs[1].staging == nil, "cancelled staged proof did not restore exact source or claimed retained payload")
            } else if scenario == "unchanged" {
                waitFor({ jobs[1].state == .completed })
                require(!FileManager.default.fileExists(atPath: source.path), "unchanged folder not removed")
                let target = URL(fileURLWithPath: jobs[1].destination)
                let retained = try SafeFileOperations.snapshot(target)
                require(retained == admission, "folder recovery differs from original proof")
                try FileManager.default.moveItem(at: target, to: source)
                let restored = try SafeFileOperations.snapshot(source)
                require(restored == admission, "folder restore changed tree")
            } else {
                waitFor({ jobs[1].state == .failed })
                let after = try SafeFileOperations.snapshot(source)
                require(after == requestedVersion, "changed folder was deleted or altered")
            }
        }
        let untouchedOutside = try Data(contentsOf: external)
        require(untouchedOutside == outside, "folder proof followed/mutated external symlink target")
        print("PASS folder deferred deletion " + scenario + ": recursive proof, empty dirs, symlink/cycle non-following and reserved-path safety")
    }
}
do {
    let deletionRoot = root.appendingPathComponent("deferred-deletion")
    try FileManager.default.createDirectory(at: deletionRoot, withIntermediateDirectories: false)
    for scenario in ["cancel", "replace", "edit", "restart", "receipt-name", "retry"] {
        let directory = deletionRoot.appendingPathComponent(scenario)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = directory.appendingPathComponent(scenario == "receipt-name" ? "deletion-receipt.json" : "selected.txt")
        let original = Data("Original selected entry\n".utf8)
        try original.write(to: source, options: .withoutOverwriting)
        let privateTrash = directory.appendingPathComponent("own-simulated-trash")
        try FileManager.default.createDirectory(at: privateTrash, withIntermediateDirectories: false)
        let callLock = NSLock(); var handlerCalls = 0
        let handler: (URL, Bool, UUID) throws -> URL = { staged, trash, id in
            require(trash, "Trash intent changed")
            require(staged.lastPathComponent == source.lastPathComponent, "staging lost original filename")
            callLock.lock(); handlerCalls += 1; callLock.unlock()
            if scenario == "retry", handlerCalls == 1 { throw POSIXError(.EIO) }
            let target = privateTrash.appendingPathComponent(id.uuidString)
            try FileManager.default.moveItem(at: staged, to: target)
            return target
        }
        let queueDirectory = directory.appendingPathComponent("queue")
        let deletionQueue = DurableTransferQueue(directory: queueDirectory, deletionHandler: handler)
        var snapshot: [DurableTransferQueue.Job] = []
        deletionQueue.changed = { jobs, _, error in require(error == nil, "deletion queue admission failed"); snapshot = jobs }
        deletionQueue.setForegroundOperationActive(true)
        deletionQueue.enqueue(source: source, destination: directory.appendingPathComponent("never-published-copy"))
        waitFor({ snapshot.count == 1 })
        let copyID = snapshot[0].id
        deletionQueue.control(copyID, .pause)
        waitFor({ snapshot.first?.state == .paused })
        deletionQueue.enqueueDeletion(source: source, toTrash: true)
        waitFor({ snapshot.count == 2 })
        let deleteID = snapshot[1].id
        deletionQueue.setForegroundOperationActive(false)
        deletionQueue.refresh()
        waitFor({ snapshot[1].statusKey == "transfer_waiting_paths" })
        require(snapshot[1].isDeletion && snapshot[1].state == .queued, "delete did not wait on paused reservation")
        let untouched = try Data(contentsOf: source)
        require(untouched == original, "waiting deletion changed source")
        if scenario == "cancel" {
            deletionQueue.control(deleteID, .cancel)
            waitFor({ snapshot[1].state == .cancelled })
            deletionQueue.control(copyID, .cancel)
            waitFor({ snapshot[0].state == .cancelled })
            let after = try Data(contentsOf: source)
            require(after == original, "cancelled queued deletion removed source")
            callLock.lock(); let calls = handlerCalls; callLock.unlock()
            require(calls == 0, "cancelled queued deletion invoked mutator")
        } else if scenario == "replace" || scenario == "edit" {
            if scenario == "replace" { try FileManager.default.moveItem(at: source, to: directory.appendingPathComponent("preserved-original")) }
            let changed = Data("Different replacement or changed content\n".utf8)
            try changed.write(to: source)
            deletionQueue.control(copyID, .cancel)
            waitFor({ snapshot[1].state == .failed })
            let after = try Data(contentsOf: source)
            require(after == changed, "deferred deletion removed changed/replaced entry")
            callLock.lock(); let calls = handlerCalls; callLock.unlock()
            require(calls == 0, "changed entry reached mutator")
        } else if scenario == "restart" {
            deletionQueue.changed = nil
            let resumed = DurableTransferQueue(directory: queueDirectory, deletionHandler: handler)
            var restored: [DurableTransferQueue.Job] = []
            resumed.changed = { jobs, _, error in require(error == nil, "restore deletion store failure"); restored = jobs }
            resumed.refresh(); waitFor({ restored.count == 2 })
            require(restored.allSatisfy { $0.state == .paused }, "restored deletion auto-started")
            resumed.control(deleteID, .proceed)
            waitFor({ restored[1].statusKey == "transfer_waiting_paths" })
            resumed.control(copyID, .cancel)
            waitFor({ restored[1].state == .completed })
            require(!FileManager.default.fileExists(atPath: source.path), "released deletion did not remove original")
            let retained = try Data(contentsOf: URL(fileURLWithPath: restored[1].destination))
            require(retained == original, "released deletion lost recovery contents")
            resumed.changed = nil
            // Reproduce death after the per-job receipt but before final queue
            // publication; a new file at the old path must never be deleted.
            let journal = queueDirectory.appendingPathComponent("copy-jobs-v1.json")
            var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as! [String: Any]
            var savedJobs = saved["jobs"] as! [[String: Any]]
            savedJobs[1]["state"] = "running"; saved["jobs"] = savedJobs
            try JSONSerialization.data(withJSONObject: saved).write(to: journal, options: .atomic)
            let newcomer = Data("New independent file at original path\n".utf8)
            try newcomer.write(to: source, options: .withoutOverwriting)
            let receiptQueue = DurableTransferQueue(directory: queueDirectory, deletionHandler: handler)
            var replay: [DurableTransferQueue.Job] = []
            receiptQueue.changed = { jobs, _, error in require(error == nil, "receipt reopen failed"); replay = jobs }
            receiptQueue.refresh(); waitFor({ replay.count == 2 })
            receiptQueue.control(deleteID, .proceed)
            waitFor({ replay[1].state == .completed })
            let after = try Data(contentsOf: source)
            require(after == newcomer, "receipt replay deleted a new source entry")
            callLock.lock(); let calls = handlerCalls; callLock.unlock()
            require(calls == 1, "receipt replay repeated deletion")
        } else {
            deletionQueue.control(copyID, .cancel)
            if scenario == "retry" {
                waitFor({ snapshot[1].state == .failed })
                require(snapshot[1].recoveryPath == snapshot[1].staging, "failed staged deletion lacks recovery path")
                require(!FileManager.default.fileExists(atPath: source.path), "failed handler lost expected staged state")
                let payload = URL(fileURLWithPath: snapshot[1].staging!).appendingPathComponent("items/" + source.lastPathComponent)
                let retained = try Data(contentsOf: payload)
                require(retained == original, "failed handler lost staged original")
                deletionQueue.control(deleteID, .proceed)
            }
            waitFor({ snapshot[1].state == .completed })
            let retained = try Data(contentsOf: URL(fileURLWithPath: snapshot[1].destination))
            require(retained == original, "receipt-like source name corrupted journal")
        }
        print("PASS deferred deletion " + scenario + ": own simulated Trash only, source identity, waiting, control and recovery evidence")
    }
    let source = deletionRoot.appendingPathComponent("private-recovery.txt")
    let original = Data("Reversible private deletion\n".utf8)
    try original.write(to: source, options: .withoutOverwriting)
    let actual = DurableTransferQueue(directory: deletionRoot.appendingPathComponent("actual-private-queue"))
    var result: [DurableTransferQueue.Job] = []
    actual.changed = { jobs, _, error in require(error == nil, "actual private deletion admission failed"); result = jobs }
    actual.enqueueDeletion(source: source, toTrash: false)
    waitFor({ result.first?.state == .completed })
    require(!FileManager.default.fileExists(atPath: source.path), "default private deletion did not remove selected entry")
    let record = FileUndoRecord(source: source, destination: URL(fileURLWithPath: result[0].destination), replacedBackup: nil)
    try record.verifyUnchangedDestination()
    let retained = try Data(contentsOf: record.destination)
    require(retained == original, "default private recovery changed bytes")
    try FileManager.default.moveItem(at: record.destination, to: source)
    let restored = try Data(contentsOf: source)
    require(restored == original, "private deletion restore changed bytes")
    print("PASS default private deferred deletion keeps exact undo destination and verifies restoration")
    let duplicateSource = deletionRoot.appendingPathComponent("duplicate-request.txt")
    try original.write(to: duplicateSource, options: .withoutOverwriting)
    let duplicate = DurableTransferQueue(directory: deletionRoot.appendingPathComponent("duplicate-queue"))
    var duplicateJobs: [DurableTransferQueue.Job] = [], duplicateError: String?
    duplicate.changed = { jobs, _, error in duplicateJobs = jobs; duplicateError = error }
    duplicate.setForegroundOperationActive(true)
    duplicate.enqueue(source: duplicateSource, destination: deletionRoot.appendingPathComponent("duplicate-never-copied"))
    waitFor({ duplicateJobs.count == 1 })
    let blockerID = duplicateJobs[0].id
    duplicate.control(blockerID, .pause); waitFor({ duplicateJobs[0].state == .paused })
    duplicate.enqueueDeletion(source: duplicateSource, toTrash: true)
    waitFor({ duplicateJobs.count == 2 })
    duplicate.enqueueDeletion(source: duplicateSource, toTrash: true)
    waitFor({ duplicateError == "transfer_delete_already_queued" })
    require(duplicateJobs.count == 2, "duplicate deletion admitted another mutator")
    duplicate.control(duplicateJobs[1].id, .cancel)
    waitFor({ duplicateJobs[1].state == .cancelled && duplicateError == nil })
    duplicate.control(blockerID, .cancel); waitFor({ duplicateJobs[0].state == .cancelled })
    let unchanged = try Data(contentsOf: duplicateSource)
    require(unchanged == original, "duplicate/cancel flow mutated source")
    require(L10n.get("transfer_queue") != "transfer_queue", "transfer queue status has no translation")
    print("PASS duplicate pending deletion refused; cancel clears transient admission error and preserves original; queue title localized")
}
do {
    var copy = DurableTransferQueue.Job(source: "/synthetic/source", destination: "/synthetic/copy")
    copy.state = .paused
    let move = DurableTransferQueue.Job(source: copy.source, destination: "/synthetic/moved", move: true)
    let independent = DurableTransferQueue.Job(source: "/synthetic/other", destination: "/synthetic/other-copy")
    let waiting = DurableTransferQueue.presentationSnapshot([copy, move, independent])
    require(waiting[1].statusKey == "transfer_waiting_paths", "overlapping paused reservation has no waiting explanation")
    require(waiting[2].statusKey == "transfer_queued", "independent queued transfer falsely claims path conflict")
    copy.state = .running
    require(DurableTransferQueue.presentationSnapshot([copy, move])[1].statusKey == "transfer_waiting_paths", "running reservation unexplained")
    copy.state = .cancelled
    let released = DurableTransferQueue.presentationSnapshot([copy, waiting[1]])
    require(released[1].statusKey == "transfer_queued", "stale path explanation survives reservation release")
    var pausedMove = waiting[1]; pausedMove.state = .paused
    require(pausedMove.statusKey == "transfer_paused", "stale waiting annotation hides explicit pause")
    print("PASS current queued overlap reason, independent capacity wait, release clears stale reason and explicit pause remains visible")
}
do {
    let gate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)
    let gateLock = NSLock()
    var firstCheckpoint = true
    let controls = DurableTransferQueue(directory: root.appendingPathComponent("control-race"), controlCheckpoint: { _ in
        gateLock.lock(); let first = firstCheckpoint; firstCheckpoint = false; gateLock.unlock()
        if first { entered.signal(); _ = gate.wait(timeout: .now() + 10) }
    })
    var snapshot: [DurableTransferQueue.Job] = []
    var updates = 0
    controls.changed = { jobs, _, error in
        require(error == nil, "control-race store failure")
        snapshot = jobs; updates += 1
    }
    let output = root.appendingPathComponent("control-race-output")
    controls.enqueue(source: source, destination: output)
    waitFor({ snapshot.first?.state == .running })
    require(entered.wait(timeout: .now() + 5) == .success, "worker never reached controllable checkpoint")
    let id = snapshot[0].id
    controls.control(id, .cancel)
    waitFor({ snapshot.first?.requestedControl == "cancel" })
    controls.control(id, .pause); controls.control(id, .pause)
    controls.control(id, .proceed); controls.control(id, .proceed)
    controls.controlAll(.pause)
    let before = updates
    controls.refresh()
    waitFor({ updates > before })
    require(snapshot.first?.requestedControl == "cancel", "late pause/resume downgraded an accepted cancellation")
    gate.signal()
    waitFor({ snapshot.first?.state == .cancelled })
    require(!FileManager.default.fileExists(atPath: output.path), "cancelled transition published final output")
    let unchanged = try Data(contentsOf: source)
    require(unchanged == bytes, "control transition changed source")
    print("PASS accepted cancellation survives stale repeated pause/resume/global pause; one worker, no publication, source exact")
}
let queue = DurableTransferQueue(directory: store)
var jobs: [DurableTransferQueue.Job] = []
var observedLimit = 0
var maximumRunning = 0
queue.changed = { snapshot, limit, error in
    require(error == nil, "queue storage failed: \(error ?? "")")
    jobs = snapshot; observedLimit = limit
    maximumRunning = max(maximumRunning, snapshot.filter { $0.state == .running }.count)
}
queue.setLimit(2)
queue.enqueue(source: source, destination: root.appendingPathComponent("copy"))
queue.enqueue(source: source, destination: root.appendingPathComponent("copy"))
queue.enqueue(source: source, destination: root.appendingPathComponent("independent"))
waitFor({ jobs.count == 3 && jobs.allSatisfy { $0.state == .completed } })
require(maximumRunning == 2, "parallel scheduling or limit failed")
require(Set(jobs.map(\.destination)).count == 3, "pending filename collision")
for job in jobs { let data = try Data(contentsOf: URL(fileURLWithPath: job.destination)); require(data == bytes, "copy mismatch") }
require(jobs.allSatisfy { $0.filesDone == 1 && $0.filesTotal == 1 }, "regular-file queue counters missing")
print("PASS persisted queue, two independent copies, pending-name allocation and parallel limit")
let id = jobs[0].id
require(jobs.allSatisfy(\.compact), "new jobs must start as single compact rows")
queue.compact(id); queue.setLimit(4)
waitFor({ observedLimit == 4 && jobs.first(where: { $0.id == id })?.compact == false })
let reopened = DurableTransferQueue(directory: store)
var recovered: [DurableTransferQueue.Job] = []
var recoveredLimit = 0
reopened.changed = { snapshot, limit, error in require(error == nil, "reopen failed"); recovered = snapshot; recoveredLimit = limit }
reopened.refresh()
waitFor({ recovered.count == 3 })
require(recoveredLimit == 4 && recovered.first(where: { $0.id == id })?.compact == false, "card/limit persistence")
require(recovered.allSatisfy { $0.filesDone == 1 && $0.filesTotal == 1 }, "file counters lost across queue restart")
var a = DurableTransferQueue.Job(source: "/a/source", destination: "/b/photo.jpg")
let b = DurableTransferQueue.Job(source: "/b/photo.jpg", destination: "/c/result")
require(DurableTransferQueue.overlaps(a, b), "write/read overlap missed")
let c = DurableTransferQueue.Job(source: "/d/source", destination: "/b/photo (2).jpg")
require(DurableTransferQueue.overlaps(a, c), "keep-both filename family overlap missed")
a.destination = "/x/independent"
require(!DurableTransferQueue.overlaps(a, c), "unrelated jobs blocked")
print("PASS persisted compact cards/parallelism and write/read/filename-family locks")
for prefix in ["tmp", "var", "etc"] {
    for source in ["/\(prefix)/source", "/private/\(prefix)/source/"] {
        var paused = DurableTransferQueue.Job(source: source, destination: "/private/\(prefix)/target/")
        paused.state = .paused
        for request in ["/\(prefix)/source", "/private/\(prefix)/source/", "/\(prefix)/source/child"] {
            require(DurableTransferQueue.pathConflicts(requested: request, writing: true, job: paused), "Paused source alias mutation escaped reservation")
            require(!DurableTransferQueue.pathConflicts(requested: request, writing: false, job: paused), "Independent source read unnecessarily blocked")
        }
        require(DurableTransferQueue.pathConflicts(requested: "/\(prefix)/target", writing: false, job: paused), "Reserved target alias read escaped")
        require(!DurableTransferQueue.pathConflicts(requested: "/\(prefix)/source-other", writing: true, job: paused), "Path-prefix neighbour incorrectly blocked")
        require(DurableTransferQueue.pathConflicts(requested: "/", writing: true, job: paused), "Root ancestor reservation missed")
        let mutation = DurableTransferQueue.Job(source: "/\(prefix)/source", destination: "/unrelated", move: true)
        require(DurableTransferQueue.overlaps(paused, mutation), "Scheduler aliases bypass paused source lock")
    }
}
print("PASS paused queue source/target locks across macOS private aliases, trailing slashes, descendants and scheduler comparisons")
var checking = DurableTransferQueue.Job(source: "/source", destination: "/target")
checking.state = .running; checking.bytes = 75; checking.total = 100
checking.workPhase = .verifying; checking.checkedBytes = 2; checking.checkingTotal = 8
require(checking.progressFraction == 0.25 && checking.bytes == 75, "verification overwrites copied bytes or uses copy progress")
checking.state = .paused
require(!checking.isChecking && checking.progressFraction == 0.75 && checking.bytes == 75,
        "paused verification must show durable copied bytes, not the unfinished verification percentage")
checking.state = .running
require(checking.isChecking && checking.progressFraction == 0.25, "resumed verification lost its distinct live progress")
print("PASS paused verification reports durable copy progress; active verification remains distinct")
require(checking.statusKey == "transfer_phase_verifying", "verification caption absent")
checking.requestedControl = "pause"; checking.controlRequestedAt = Date()
require(checking.statusKey == "transfer_pausing" && checking.state == .running, "pending pause falsely reports worker paused")
checking.requestedControl = "cancel"
require(checking.statusKey == "transfer_cancelling", "pending cancellation not explicit")
checking.state = .completed
require(checking.progressFraction == 1 && checking.statusKey == "transfer_completed" && !checking.isChecking, "completed status retains pending/verification caption")
print("PASS independent verification percentage, stable copied bytes and truthful pending pause/cancel status")
var metered = DurableTransferQueue.Job(source: "/source", destination: "/target")
metered.state = .running; metered.workPhase = .copying; metered.total = 10000
metered.activeSince = Date(timeIntervalSinceReferenceDate: 100)
metered.bytes = 5000 // Saved bytes are a baseline, never new throughput.
var meter = TransferRateEstimator()
require(meter.observe(metered, uptime: 10) == nil, "resume invented a throughput before a fresh sample")
metered.bytes = 6000
let measured = meter.observe(metered, uptime: 11)
require(measured?.bytesPerSecond == 1000 && measured?.remaining == 4, "rate or remaining time includes resumed bytes")
require(meter.observe(metered, uptime: 14) == nil, "stalled transfer retains a fixed ETA")
metered.state = .paused
require(meter.observe(metered, uptime: 15) == nil, "paused transfer reports live speed")
metered.state = .running; metered.activeSince = Date(timeIntervalSinceReferenceDate: 200)
require(meter.observe(metered, uptime: 20) == nil, "resume uses stale timing samples")
metered.bytes = 7000
require(meter.observe(metered, uptime: 21)?.bytesPerSecond == 1000, "fresh resumed rate incorrect")
metered.workPhase = .verifying
require(meter.observe(metered, uptime: 22) == nil, "verification is falsely reported as copy throughput")
metered.workPhase = .copying
require(meter.observe(metered, uptime: 23) == nil, "copy restart includes verification duration")
metered.bytes = 8000
require(meter.observe(metered, uptime: 24)?.bytesPerSecond == 1000, "new copying phase rate")
metered.bytes = 100
require(meter.observe(metered, uptime: 25) == nil, "regressing checkpoint reports unsafe negative speed")
metered.bytes = 1100
require(meter.observe(metered, uptime: 26)?.bytesPerSecond == 1000, "rate cannot recover after checkpoint reset")
require(meter.observe(metered, uptime: .nan) == nil, "invalid monotonic time accepted")
metered.bytes = metered.total
require(metered.progressFraction < 1 && Int(metered.progressFraction * 100) == 99, "100 percent before publication")
metered.state = .paused
require(metered.progressFraction < 1, "paused unpublished file reports100%")
metered.state = .completed
require(metered.progressFraction == 1, "confirmed completion not100%")
print("PASS live monotonic rate and ETA exclude saved bytes, pause, verification, stalls and clock/checkpoint resets;100% only after completion")
do {
    // Exercise the production non-exclusive-rename adapter on an owned local
    // filesystem. This is a callback/counter regression, not live SMB evidence.
    let nasSource = root.appendingPathComponent("CounterSource")
    try FileManager.default.createDirectory(at: nasSource.appendingPathComponent("EmptyFolder"), withIntermediateDirectories: true)
    let payload = Data(repeating: 71, count: 2 * 1024 * 1024)
    try payload.write(to: nasSource.appendingPathComponent("Payload.bin"))
    try Data().write(to: nasSource.appendingPathComponent("Zero.bin"))
    let target = root.appendingPathComponent("CounterDestination")
    let staging = try NASExclusiveCopy.create(source: nasSource, target: target, journalParent: root)
    var copied: Int64 = 0
    var counts: [(Int, Int)] = []
    let paused = try NASExclusiveCopy.resume(staging, control: { copied >= 1024 * 1024 ? .pause : .proceed },
        progress: { copied = $0 }, fileProgress: { counts.append(($0, $1)) })
    require(paused == .paused, "NAS counter fixture did not pause")
    let resumed = try NASExclusiveCopy.resume(staging, fileProgress: { counts.append(($0, $1)) })
    require(resumed == .completed && counts.last?.0 == 2 && counts.allSatisfy { $0.1 == 2 && $0.0 <= 2 }, "NAS counter resume/zero-file mismatch")
    require(zip(counts, counts.dropFirst()).allSatisfy { $0.0.0 <= $0.1.0 }, "NAS counters regressed or double counted")
    let received = try Data(contentsOf: target.appendingPathComponent("Payload.bin"))
    require(received == payload, "NAS counter callback changed bytes")
    let replay = try NASExclusiveCopy.resume(staging, fileProgress: { counts.append(($0, $1)) })
    require(replay == .completed, "completed NAS replay failed")
    require(counts.last?.0 == 2, "completed NAS replay lost counters")
    print("PASS NAS adapter file counts across pause/resume/replay including zero-byte file and empty directory (local fixture)")
}
var guarded = DurableTransferQueue.Job(source: "/a/source", destination: "/b/photo (2).jpg", move: false)
guarded.state = .running
require(DurableTransferQueue.pathConflicts(requested: "/a", writing: true, job: guarded), "parent removal can invalidate active read")
require(!DurableTransferQueue.pathConflicts(requested: "/a/source", writing: false, job: guarded), "independent reader blocked")
require(DurableTransferQueue.pathConflicts(requested: "/b/photo.jpg", writing: true, job: guarded), "pending name-family collision missed")
require(!DurableTransferQueue.pathConflicts(requested: "/c/other", writing: true, job: guarded), "unrelated mutation blocked")
guarded.move = true
require(DurableTransferQueue.pathConflicts(requested: "/a/source", writing: false, job: guarded), "reader can race phased move")
guarded.state = .paused
require(DurableTransferQueue.pathConflicts(requested: "/a", writing: true, job: guarded), "paused source can be removed before resume")
print("PASS mutation path guards, parent/child and pending-name families, compatible readers and paused reservations")
queue.forget(id)
waitFor({ jobs.count == 2 })
require(FileManager.default.fileExists(atPath: recovered[0].destination), "forget removed copied data")
print("PASS remove completed card without deleting output or recovery data")

// Simulate a process exit after engine publication but before the queue index
// was updated. Reopening must never start work until explicitly resumed.
let storeURL = store.appendingPathComponent("copy-jobs-v1.json")
var stored = try JSONSerialization.jsonObject(with: Data(contentsOf: storeURL)) as! [String: Any]
var savedJobs = stored["jobs"] as! [[String: Any]]
let restartID = UUID(uuidString: savedJobs[0]["id"] as! String)!
savedJobs[0]["state"] = "running"
savedJobs[0]["requestedControl"] = "pause"
savedJobs[0]["workPhase"] = "verifying"
savedJobs[0]["checkedBytes"] = 8
savedJobs[0]["checkingTotal"] = 12
savedJobs[0]["error"] = "synthetic previous error"
stored["jobs"] = savedJobs
try JSONSerialization.data(withJSONObject: stored).write(to: storeURL)
let restart = DurableTransferQueue(directory: store)
var restartJobs: [DurableTransferQueue.Job] = []
restart.changed = { snapshot, _, error in require(error == nil, "restart failed"); restartJobs = snapshot }
restart.refresh()
waitFor({ restartJobs.first(where: { $0.id == restartID })?.state == .paused })
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
require(restartJobs.first(where: { $0.id == restartID })?.state == .paused, "recovered job started automatically")
let stopped = restartJobs.first { $0.id == restartID }!
require(stopped.requestedControl == nil && stopped.workPhase == nil && stopped.checkingTotal == nil,
    "restart kept a dead worker's pending request/verification phase")
restart.setForegroundOperationActive(true)
restart.control(restartID, .proceed)
waitFor({ restartJobs.first(where: { $0.id == restartID })?.state == .queued })
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
require(restartJobs.first(where: { $0.id == restartID })?.state == .queued, "resume started underneath a foreground action")
restart.setForegroundOperationActive(false)
waitFor({ restartJobs.first(where: { $0.id == restartID })?.state == .completed })
require(restartJobs.first(where: { $0.id == restartID })?.error == "synthetic previous error", "successful resume silently discarded previous failure")
print("PASS restart recovers a running index as paused, explicit resume validates completed publication")
let gateQueue = DurableTransferQueue(directory: root.appendingPathComponent("foreground-gate"))
var gateJobs: [DurableTransferQueue.Job] = []
gateQueue.changed = { snapshot, _, error in require(error == nil, "foreground gate failed"); gateJobs = snapshot }
gateQueue.setForegroundOperationActive(true)
let gatedDestination = root.appendingPathComponent("foreground-result")
gateQueue.enqueue(source: source, destination: gatedDestination)
waitFor({ gateJobs.count == 1 })
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
require(gateJobs[0].state == .queued && !FileManager.default.fileExists(atPath: gatedDestination.path), "new job escaped foreground gate")
gateQueue.setForegroundOperationActive(false)
waitFor({ gateJobs[0].state == .completed })
let gatedBytes = try Data(contentsOf: gatedDestination)
require(gatedBytes == bytes, "released foreground gate copy differs")
print("PASS foreground mutation gate defers new/resumed jobs until release without losing queued work")

let bulkQueue = DurableTransferQueue(directory: root.appendingPathComponent("bulk-controls"))
var bulkJobs: [DurableTransferQueue.Job] = []
var bulkMaximumRunning = 0
bulkQueue.changed = { snapshot, _, error in
    require(error == nil, "bulk controls store failure")
    bulkJobs = snapshot
    bulkMaximumRunning = max(bulkMaximumRunning, snapshot.filter { $0.state == .running }.count)
}
bulkQueue.setForegroundOperationActive(true)
bulkQueue.setLimit(2)
for number in 1...3 { bulkQueue.enqueue(source: source, destination: root.appendingPathComponent("bulk-\(number)")) }
waitFor({ bulkJobs.count == 3 })
bulkQueue.controlAll(.pause)
bulkQueue.setForegroundOperationActive(false)
waitFor({ bulkJobs.allSatisfy { $0.state == .paused } })
require(bulkJobs.allSatisfy { !FileManager.default.fileExists(atPath: $0.destination) }, "pause all started a queued job")
bulkQueue.controlAll(.proceed)
waitFor({ bulkJobs.allSatisfy { $0.state == .completed } })
require(bulkMaximumRunning <= 2, "resume all exceeded concurrency")
for job in bulkJobs {
    let copied = try Data(contentsOf: URL(fileURLWithPath: job.destination))
    require(copied == bytes, "bulk resume changed bytes")
}
print("PASS atomic pause-all/resume-all preserves queued work, byte integrity and concurrency")
let reservedQueue = DurableTransferQueue(directory: root.appendingPathComponent("paused-reservation"))
var reservedJobs: [DurableTransferQueue.Job] = []
reservedQueue.changed = { snapshot, _, error in require(error == nil, "reservation store failed"); reservedJobs = snapshot }
reservedQueue.setForegroundOperationActive(true)
reservedQueue.enqueue(source: source, destination: root.appendingPathComponent("reserved-copy"))
waitFor({ reservedJobs.count == 1 })
let pausedID = reservedJobs[0].id
reservedQueue.control(pausedID, .pause)
reservedQueue.enqueue(source: source, destination: root.appendingPathComponent("reserved-move"), move: true)
reservedQueue.setForegroundOperationActive(false)
waitFor({ reservedJobs.count == 2 && reservedJobs[0].state == .paused && reservedJobs[1].state == .queued })
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
require(reservedJobs[1].state == .queued && FileManager.default.fileExists(atPath: source.path), "move invalidated paused copy source")
reservedQueue.control(pausedID, .cancel)
waitFor({ reservedJobs[1].state == .completed })
require(reservedJobs[0].state == .cancelled, "cancel restarted paused work")
print("PASS paused source blocks later conflicting move; cancel releases reservation without starting paused jobs")

func testRemoveCompletedCards() throws {
    let directory = root.appendingPathComponent("remove-completed")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let source = directory.appendingPathComponent("cleanup-source")
    try bytes.write(to: source)
    let recovery = directory.appendingPathComponent("recovery.txt")
    let preserved = Data("preserve recovery".utf8)
    try preserved.write(to: recovery)
    let states: [DurableTransferQueue.State] = [.completed, .completed, .cancelled, .cancelled, .paused, .failed, .queued, .running]
    let seeded = states.enumerated().map { index, state in
        var job = DurableTransferQueue.Job(source: source.path, destination: directory.appendingPathComponent("target-\(index)").path)
        job.state = state
        if index == 1 || index == 3 { job.engine = "nas-exclusive" }
        job.backup = recovery.path
        return job
    }
    let data = try JSONEncoder().encode(seeded)
    for job in seeded.prefix(2) { try bytes.write(to: URL(fileURLWithPath: job.destination)) }
    let encodedJobs = try JSONSerialization.jsonObject(with: data)
    try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 1, "jobs": encodedJobs])
        .write(to: directory.appendingPathComponent("copy-jobs-v1.json"), options: .atomic)
    let cleanup = DurableTransferQueue(directory: directory)
    var observed: [DurableTransferQueue.Job] = []
    cleanup.changed = { snapshot, _, error in require(error == nil, "bulk removal persistence failed"); observed = snapshot }
    cleanup.refresh(); waitFor({ observed.count == 8 })
    let before = observed
    cleanup.forgetCompleted(); waitFor({ observed.count == 6 })
    require(observed.allSatisfy { $0.state != .completed }, "completed cards remain")
    require(Set(observed.map(\.id)) == Set(seeded.dropFirst(2).map(\.id)), "bulk removal lost unfinished or cancelled jobs")
    require(DurableTransferQueue.removedCards(previous: before, current: observed), "removed cards did not request pane refresh")
    require(!DurableTransferQueue.removedCards(previous: observed, current: observed), "unchanged progress requested redundant pane refresh")
    cleanup.forget(seeded[3].id); cleanup.refresh()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    require(observed.contains { $0.id == seeded[3].id }, "NAS partial recovery card removed")
    let persisted = DurableTransferQueue(directory: directory)
    var reopened: [DurableTransferQueue.Job] = []
    persisted.changed = { snapshot, _, error in require(error == nil, "reopen removal failed"); reopened = snapshot }
    persisted.refresh(); waitFor({ reopened.count == 6 })
    require(Set(reopened.map(\.id)) == Set(observed.map(\.id)), "removed cards reappeared after restart")
    let sourceData = try Data(contentsOf: source)
    let recoveryData = try Data(contentsOf: recovery)
    require(sourceData == bytes && recoveryData == preserved, "card removal deleted source or recovery contents")
    for job in seeded.prefix(2) {
        let copied = try Data(contentsOf: URL(fileURLWithPath: job.destination))
        require(copied == bytes, "card removal deleted completed target file")
    }

    let emptyDirectory = root.appendingPathComponent("remove-last-completed")
    try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: false)
    let completedJobs = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(seeded.prefix(2))))
    try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 1, "jobs": completedJobs])
        .write(to: emptyDirectory.appendingPathComponent("copy-jobs-v1.json"), options: .atomic)
    let emptyQueue = DurableTransferQueue(directory: emptyDirectory)
    var emptySnapshot: [DurableTransferQueue.Job] = seeded
    emptyQueue.changed = { snapshot, _, error in require(error == nil, "empty removal failed"); emptySnapshot = snapshot }
    emptyQueue.refresh(); waitFor({ emptySnapshot.count == 2 })
    let lastCards = emptySnapshot
    emptyQueue.forgetCompleted(); waitFor({ emptySnapshot.isEmpty })
    require(DurableTransferQueue.removedCards(previous: lastCards, current: emptySnapshot), "removing last cards did not refresh panes")
    print("PASS remove all completed: mixed-state protection, NAS recovery, persistence, last-card refresh and preserved files")
}
try testRemoveCompletedCards()

func testQueueAdmissionErrors() throws {
    let source = root.appendingPathComponent("admission-source")
    try bytes.write(to: source)
    let invalidRoot = root.appendingPathComponent("invalid-queue")
    try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: false)
    let journal = invalidRoot.appendingPathComponent("copy-jobs-v1.json")
    let damaged = Data("{ synthetic damaged journal".utf8)
    try damaged.write(to: journal)
    let invalid = DurableTransferQueue(directory: invalidRoot)
    var errorKey: String?
    var snapshot: [DurableTransferQueue.Job] = []
    invalid.changed = { jobs, _, error in snapshot = jobs; errorKey = error }
    invalid.enqueue(source: source, destination: root.appendingPathComponent("never-published"))
    waitFor { errorKey != nil }
    require(errorKey == "transfer_store_error" && snapshot.isEmpty, "damaged queue error must be stable, not accepted or raw decoder text")
    let retainedJournal = try Data(contentsOf: journal)
    require(retainedJournal == damaged, "damaged journal silently replaced")
    require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("never-published").path), "damaged queue wrote destination")

    let fullRoot = root.appendingPathComponent("full-queue")
    try FileManager.default.createDirectory(at: fullRoot, withIntermediateDirectories: false)
    let seeded = (0..<1000).map { index in
        DurableTransferQueue.Job(source: source.path, destination: root.appendingPathComponent("old-\(index)").path, state: .cancelled)
    }
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(seeded))
    try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 2, "jobs": encoded]).write(to: fullRoot.appendingPathComponent("copy-jobs-v1.json"))
    let full = DurableTransferQueue(directory: fullRoot)
    var fullError: String?
    var fullJobs: [DurableTransferQueue.Job] = []
    full.changed = { jobs, _, error in fullJobs = jobs; fullError = error }
    full.enqueue(source: source, destination: root.appendingPathComponent("after-full"))
    waitFor { fullError != nil }
    require(fullError == "transfer_queue_full" && fullJobs.count == 1000, "full queue mislabeled as corrupt or silently admitted")
    full.forget(seeded[0].id)
    waitFor { fullJobs.count == 999 && fullError == nil }
    full.enqueue(source: source, destination: root.appendingPathComponent("after-full"))
    waitFor { fullJobs.contains { $0.destination.hasSuffix("/after-full") && $0.state == .completed } }
    let retriedBytes = try Data(contentsOf: root.appendingPathComponent("after-full"))
    require(retriedBytes == bytes, "queue did not recover after freeing a card")
    print("PASS damaged/full queue admission: localized error keys, no silent data loss, safe refusal and retry after card removal")
}
try testQueueAdmissionErrors()
let pageJobs = (0..<1000).map { DurableTransferQueue.Job(source: "/source/\($0)", destination: "/target/\($0)") }
let pages = (0..<20).map { DurableTransferQueue.cardPage(pageJobs, index: $0) }
require(pages.allSatisfy { $0.jobs.count == 50 && $0.count == 20 }, "unbounded transfer card page")
require(pages.flatMap(\.jobs).map(\.id) == pageJobs.reversed().map(\.id), "paged cards lost, duplicated or reordered jobs")
require(DurableTransferQueue.cardPage(pageJobs, index: -100).index == 0, "negative page not clamped")
require(DurableTransferQueue.cardPage(pageJobs, index: 100).index == 19, "high page not clamped")
require(DurableTransferQueue.cardPage(Array(pageJobs.prefix(3)), index: 19).index == 0, "removal did not clamp current page")
require(DurableTransferQueue.cardPage([], index: 2).jobs.isEmpty, "empty queue invented cards")
print("PASS 1,000 transfer cards: bounded pages, complete newest-first coverage and page clamping after removal")
