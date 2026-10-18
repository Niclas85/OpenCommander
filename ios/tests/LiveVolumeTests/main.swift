import Foundation
import Darwin

// Explicit opt-in live-volume test. Only a newly created empty fixture directory
// may be supplied. Never format, remount, repair, or enumerate user directories.
let fm = FileManager.default
guard CommandLine.arguments.count == 2 else { fatalError("Pass an empty OpenCommander-LiveQA-* directory") }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard root.path.hasPrefix("/Volumes/"), root.lastPathComponent.hasPrefix("OpenCommander-LiveQA-"),
      root.resolvingSymlinksInPath().path == root.path,
      try fm.contentsOfDirectory(atPath: root.path).isEmpty else { fatalError("Not an empty explicit live fixture") }
let local = URL(fileURLWithPath: "/private/tmp/OpenCommander-LiveQA-" + UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: local, withIntermediateDirectories: false)
let bytes = Data((0..<(3 * 1024 * 1024 + 137)).map { UInt8($0 % 251) })
let source = local.appendingPathComponent("Grüsse 日本語.bin")
try bytes.write(to: source, options: .withoutOverwriting)
var failures = 0
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); print("PASS " + name) }
    catch { failures += 1; print("FAIL \(name): \(error)") }
    fflush(stdout)
}
func require(_ valid: Bool) throws { if !valid { throw CocoaError(.fileReadCorruptFile) } }
check("Foundation write/read, rename, overwrite, return copy") {
    let first = root.appendingPathComponent("Grüsse 日本語.bin")
    let renamed = root.appendingPathComponent("Renamed.bin")
    try fm.copyItem(at: source, to: first)
    try require(Data(contentsOf: first) == bytes)
    try fm.moveItem(at: first, to: renamed)
    let replacement = Data("OpenCommander synthetic replacement\n".utf8)
    try replacement.write(to: renamed)
    let returned = local.appendingPathComponent("Returned.bin")
    try fm.copyItem(at: renamed, to: returned)
    try require(Data(contentsOf: returned) == replacement)
}
check("Production durable copy pause/resume and byte-exact return") {
    let target = root.appendingPathComponent("Durable.bin")
    let stage = try DurableFileCopy.create(source: source, destination: target)
    var transferred: Int64 = 0
    let paused = try DurableFileCopy.resume(stage, control: { transferred > 0 ? .pause : .proceed },
        progress: { done, _ in transferred = done })
    try require(paused.state == .paused && !fm.fileExists(atPath: target.path))
    try require(DurableFileCopy.inspect(stage).state == .paused)
    try require(DurableFileCopy.resume(stage).state == .completed)
    try require(Data(contentsOf: target) == bytes)
    let returned = local.appendingPathComponent("Durable-return.bin")
    let reverse = try DurableFileCopy.create(source: target, destination: returned)
    try require(DurableFileCopy.resume(reverse).state == .completed)
    try require(Data(contentsOf: returned) == bytes)
}
check("Production tree copy, empty directory, hidden file and size") {
    let tree = local.appendingPathComponent("Tree")
    try fm.createDirectory(at: tree.appendingPathComponent("Nested/Empty"), withIntermediateDirectories: true)
    try Data("hidden".utf8).write(to: tree.appendingPathComponent("Nested/.hidden"))
    let target = root.appendingPathComponent("Tree")
    let stage = try DurableTreeTransfer.create(source: tree, destination: target, move: false, replace: false)
    try require(DurableTreeTransfer.resume(stage).state == .completed)
    try require(Data(contentsOf: target.appendingPathComponent("Nested/.hidden")) == Data("hidden".utf8))
    try require(fm.fileExists(atPath: target.appendingPathComponent("Nested/Empty").path))
    let report = BoundedFolderSize.report(at: target)
    try require(report.complete && report.bytes == 6)
}
print("RETAINED_LIVE_FIXTURE \(root.path)")
// Diagnostic for the rejected Foundation fallback, not the product publisher.
// A failure here must never be treated as permission to install that fallback.
check("Foundation fallback rejects pre-existing file/directory collisions") {
    for directory in [false, true] {
        let prefix = directory ? "directory" : "file"
        let a = root.appendingPathComponent(prefix + "-collision-source")
        let b = root.appendingPathComponent(prefix + "-collision-target")
        if directory {
            try fm.createDirectory(at: a, withIntermediateDirectories: false)
            try fm.createDirectory(at: b, withIntermediateDirectories: false)
        } else {
            try Data("source".utf8).write(to: a)
            try Data("sentinel".utf8).write(to: b)
        }
        var refused = false
        do { try FileManager().moveItem(at: a, to: b) } catch { refused = true }
        try require(refused && fm.fileExists(atPath: a.path))
        if !directory { try require(Data(contentsOf: b) == Data("sentinel".utf8)) }
    }
}
check("Foundation fallback concurrent-publication safety gate") {
    for i in 0..<30 {
        let a = root.appendingPathComponent("race-\(i)-a"), b = root.appendingPathComponent("race-\(i)-b")
        let target = root.appendingPathComponent("race-\(i)-target")
        try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
        let group = DispatchGroup(), lock = NSLock()
        var successes = 0
        for source in [a, b] {
            group.enter()
            DispatchQueue.global().async {
                if (try? FileManager().moveItem(at: source, to: target)) != nil {
                    lock.lock(); successes += 1; lock.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        print("RACE \(i) successes=\(successes) a=\(fm.fileExists(atPath: a.path)) b=\(fm.fileExists(atPath: b.path))")
        try require(successes == 1)
        let value = try Data(contentsOf: target)
        try require(value == Data("a".utf8) ? fm.fileExists(atPath: b.path) : fm.fileExists(atPath: a.path))
    }
}
print("RETAINED_LOCAL_FIXTURE \(local.path)")
exit(failures == 0 ? 0 : 1)
