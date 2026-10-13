import Foundation

func require(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 30) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    require(condition(), "queue condition timed out")
}
let root = URL(fileURLWithPath: "/private/tmp/OpenCommander-QueueTests-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }
let source = root.appendingPathComponent("source")
let bytes = Data(repeating: 37, count: 2 * 1024 * 1024)
try bytes.write(to: source)
let store = root.appendingPathComponent("state")
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
var a = DurableTransferQueue.Job(source: "/a/source", destination: "/b/photo.jpg")
let b = DurableTransferQueue.Job(source: "/b/photo.jpg", destination: "/c/result")
require(DurableTransferQueue.overlaps(a, b), "write/read overlap missed")
let c = DurableTransferQueue.Job(source: "/d/source", destination: "/b/photo (2).jpg")
require(DurableTransferQueue.overlaps(a, c), "keep-both filename family overlap missed")
a.destination = "/x/independent"
require(!DurableTransferQueue.overlaps(a, c), "unrelated jobs blocked")
print("PASS persisted compact cards/parallelism and write/read/filename-family locks")
var checking = DurableTransferQueue.Job(source: "/source", destination: "/target")
checking.state = .running; checking.bytes = 75; checking.total = 100
checking.workPhase = .verifying; checking.checkedBytes = 2; checking.checkingTotal = 8
require(checking.progressFraction == 0.25 && checking.bytes == 75, "verification overwrites copied bytes or uses copy progress")
require(checking.statusKey == "transfer_phase_verifying", "verification caption absent")
checking.requestedControl = "pause"; checking.controlRequestedAt = Date()
require(checking.statusKey == "transfer_pausing" && checking.state == .running, "pending pause falsely reports worker paused")
checking.requestedControl = "cancel"
require(checking.statusKey == "transfer_cancelling", "pending cancellation not explicit")
checking.state = .completed
require(checking.progressFraction == 1 && checking.statusKey == "transfer_completed" && !checking.isChecking, "completed status retains pending/verification caption")
print("PASS independent verification percentage, stable copied bytes and truthful pending pause/cancel status")
var guarded = DurableTransferQueue.Job(source: "/a/source", destination: "/b/photo (2).jpg", move: false)
guarded.state = .running
require(DurableTransferQueue.pathConflicts(requested: "/a", writing: true, job: guarded), "parent removal can invalidate active read")
require(!DurableTransferQueue.pathConflicts(requested: "/a/source", writing: false, job: guarded), "independent reader blocked")
require(DurableTransferQueue.pathConflicts(requested: "/b/photo.jpg", writing: true, job: guarded), "pending name-family collision missed")
require(!DurableTransferQueue.pathConflicts(requested: "/c/other", writing: true, job: guarded), "unrelated mutation blocked")
guarded.move = true
require(DurableTransferQueue.pathConflicts(requested: "/a/source", writing: false, job: guarded), "reader can race phased move")
guarded.state = .paused
require(!DurableTransferQueue.pathConflicts(requested: "/a", writing: true, job: guarded), "paused job retains active reservation")
print("PASS mutation path guards, parent/child and pending-name families, compatible readers and paused release")
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
restart.control(restartID, .proceed)
waitFor({ restartJobs.first(where: { $0.id == restartID })?.state == .completed })
require(restartJobs.first(where: { $0.id == restartID })?.error == "synthetic previous error", "successful resume silently discarded previous failure")
print("PASS restart recovers a running index as paused, explicit resume validates completed publication")
