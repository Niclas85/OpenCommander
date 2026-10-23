import Foundation
import Darwin
setbuf(stdout, nil)

func require(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
struct Plan: Codable { let source: String, kind: String, phase: String }
func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(30)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    require(condition(), "deadline expired")
}
let fm = FileManager.default
if CommandLine.arguments.count == 3 {
    let mode = CommandLine.arguments[1], root = URL(fileURLWithPath: CommandLine.arguments[2])
    require(root.path.hasPrefix("/private/tmp/OpenCommander-DeletionCrash-"), "unsafe child root")
    let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: root.appendingPathComponent("plan.json")))
    require(plan.source.hasPrefix(root.path + "/Sources/"), "unsafe planned source")
    let queue = DurableTransferQueue(directory: root.appendingPathComponent("Queue"), deletionCheckpoint: { _, point in
        guard mode == "crash" else { return }
        if (plan.phase == "before-receipt" && point == .afterMutationBeforeReceipt) ||
           (plan.phase == "after-receipt" && point == .afterReceipt) {
            guard kill(getpid(), SIGKILL) == 0 else { fatalError("could not signal own test child") }
            // Delivery can complete on another thread after kill() returns.
            // Do not print a false failure while the mandatory signal arrives.
            while true { pause() }
        }
    })
    var jobs: [DurableTransferQueue.Job] = [], error: String?
    queue.changed = { snapshot, _, failure in jobs = snapshot; error = failure }
    if mode == "crash" {
        queue.enqueueDeletion(source: URL(fileURLWithPath: plan.source), toTrash: true)
        wait({ error != nil || jobs.first?.state == .failed || jobs.first?.state == .completed })
        print("FAIL crash checkpoint not reached", error ?? jobs.first?.errorMessage ?? "unexpected completion")
        exit(3)
    } else {
        require(mode == "recover", "unsupported child mode")
        queue.refresh(); wait({ jobs.count == 1 || error != nil })
        require(error == nil && jobs[0].state == .paused, "recovered queue automatically mutated or lost pause")
        queue.control(jobs[0].id, .proceed)
        wait({ [.completed, .failed].contains(jobs[0].state) })
        require(jobs[0].state == .completed, "recovery failed: " + (jobs[0].errorMessage ?? "unknown"))
        try JSONEncoder().encode(jobs[0]).write(to: root.appendingPathComponent("recovered.json"), options: .withoutOverwriting)
        print("PASS fresh-process explicit recovery", plan.kind, plan.phase)
        exit(0)
    }
}
let suite = URL(fileURLWithPath: "/private/tmp/OpenCommander-DeletionCrash-" + UUID().uuidString)
try fm.createDirectory(at: suite, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
print("FIXTURE", suite.path)
let executable = URL(fileURLWithPath: CommandLine.arguments[0])
for kind in ["file", "folder", "symlink"] {
    for phase in ["before-receipt", "after-receipt"] {
        let area = suite.appendingPathComponent(kind + "-" + phase)
        try fm.createDirectory(at: area.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        let source = area.appendingPathComponent("Sources/OpenCommanderCrash-" + kind + "-" + UUID().uuidString)
        let outside = area.appendingPathComponent("outside.txt")
        let external = Data("Own outside symlink target must remain unchanged\n".utf8)
        try external.write(to: outside, options: .withoutOverwriting)
        if kind == "folder" {
            try fm.createDirectory(at: source.appendingPathComponent("Nested/Empty"), withIntermediateDirectories: true)
            try Data("Own folder child – 日本語\n".utf8).write(to: source.appendingPathComponent("Nested/Grüsse.txt"))
            try fm.createSymbolicLink(atPath: source.appendingPathComponent("outside-link").path, withDestinationPath: outside.path)
        } else if kind == "symlink" {
            try fm.createSymbolicLink(atPath: source.path, withDestinationPath: outside.path)
        } else { try Data(repeating: 91, count: 8193).write(to: source) }
        let expected = try SafeFileOperations.snapshot(source)
        let identity = try DurableTransferQueue.DeletionIdentity.read(source)
        try JSONEncoder().encode(Plan(source: source.path, kind: kind, phase: phase)).write(to: area.appendingPathComponent("plan.json"))
        func run(_ mode: String) throws -> Process {
            let child = Process(); child.executableURL = executable; child.arguments = [mode, area.path]
            try child.run(); child.waitUntilExit(); return child
        }
        let crashed = try run("crash")
        require(crashed.terminationReason == .uncaughtSignal && crashed.terminationStatus == SIGKILL,
                "child did not die at requested actual Trash boundary: " + kind + " " + phase)
        require(!SafeFileOperations.exists(source), "OS Trash action did not remove original source")
        let store = try JSONSerialization.jsonObject(with: Data(contentsOf: area.appendingPathComponent("Queue/copy-jobs-v1.json"))) as! [String: Any]
        let saved = (store["jobs"] as! [[String: Any]])[0]
        let stage = URL(fileURLWithPath: saved["staging"] as! String)
        require(fm.fileExists(atPath: stage.appendingPathComponent("selected-bookmark.json").path), "pre-mutation bookmark missing")
        require(fm.fileExists(atPath: stage.appendingPathComponent("deletion-receipt.json").path) == (phase == "after-receipt"), "wrong crash/receipt boundary")
        // Reuse the user-visible path, not the private journal path.
        try fm.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("New unrelated replacement at original path\n".utf8).write(to: source.appendingPathComponent("New.txt"))
        let replacement = try SafeFileOperations.snapshot(source)
        let recovered = try run("recover")
        require(recovered.terminationStatus == 0, "fresh-process recovery failed")
        let result = try JSONDecoder().decode(DurableTransferQueue.Job.self, from: Data(contentsOf: area.appendingPathComponent("recovered.json")))
        let actual = URL(fileURLWithPath: result.destination)
        let actualIdentity = try DurableTransferQueue.DeletionIdentity.read(actual)
        require(actualIdentity == identity, "recovered wrong selected identity")
        let actualProof = try SafeFileOperations.snapshot(actual, rootName: source.lastPathComponent)
        require(actualProof == expected, "recovered original content/metadata differs")
        let replacementAfter = try SafeFileOperations.snapshot(source)
        require(replacementAfter == replacement, "recovery mutated new source entry")
        let preserved = area.appendingPathComponent("NewSourcePreserved")
        try fm.moveItem(at: source, to: preserved)
        try fm.moveItem(at: actual, to: source) // Only this verified own Trash object.
        let restored = try SafeFileOperations.snapshot(source)
        let externalAfter = try Data(contentsOf: outside)
        require(restored == expected && externalAfter == external, "own originals/outside target not restored exactly")
        print("PASS actual SIGKILL", kind, phase, "fresh process, original path reused, exact original recovered/restored, replacement preserved")
    }
}
print("PASS six actual OS Trash process-death cases; own fixtures retained, no OS reboot or personal data touched")
