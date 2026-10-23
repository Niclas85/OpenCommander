import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let root = String(cString: physical), fm = FileManager.default
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      URL(fileURLWithPath: root).deletingLastPathComponent().path == "/private/tmp",
      fm.fileExists(atPath: root + "/PreserveAppState.txt"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else {
    fatalError("only a stopped isolated app may receive synthetic reservations")
}
let journal = URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json")
let backup = URL(fileURLWithPath: root + "/Transfers/BeforeQueueReservations.saved.json")
let bytes = try Data(contentsOf: journal)
guard !fm.fileExists(atPath: backup.path),
      var store = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      var jobs = store["jobs"] as? [[String: Any]], jobs.count <= 997,
      jobs.allSatisfy({ ["completed", "cancelled"].contains($0["state"] as? String ?? "") }) else { fatalError("never modify nonterminal jobs or overwrite backup") }
let fixture = root + "/QueueControls/Reservations"
guard !fm.fileExists(atPath: fixture), !fm.fileExists(atPath: root + "/SlowQueueControls.txt") else { fatalError("never overwrite fixtures") }
try fm.createDirectory(atPath: fixture, withIntermediateDirectories: false)
for name in ["Sources", "Copy", "Move", "Other"] { try fm.createDirectory(atPath: fixture + "/" + name, withIntermediateDirectories: false) }
try fm.copyItem(atPath: root + "/QueueControls/Sources/Alpha.bin", toPath: fixture + "/Sources/Reserved.bin")
try Data("Own independent reversible deletion acceptance\n".utf8).write(to: URL(fileURLWithPath: fixture + "/Sources/DeleteMe.txt"), options: .withoutOverwriting)
let source = fixture + "/Sources/Reserved.bin"
for (index, name) in ["Copy", "Move", "Other"].enumerated() {
    jobs.append(["id": "121EC5B0-4526-410D-A1FA-A3A9BF31C30" + String(index + 1),
                 "source": index == 2 ? root + "/QueueControls/Sources/Gamma.bin" : source,
                 "destination": fixture + "/" + name + "/" + (index == 2 ? "Gamma.bin" : "Reserved.bin"),
                 "move": index == 1, "state": "paused", "bytes": 0, "total": 64 * 1024 * 1024,
                 "created": Date().timeIntervalSinceReferenceDate, "compact": true])
}
try bytes.write(to: backup, options: .withoutOverwriting)
store["jobs"] = jobs; store["limit"] = 2
try JSONSerialization.data(withJSONObject: store).write(to: journal, options: .atomic)
try Data("isolated reservation acceptance only\n".utf8).write(to: URL(fileURLWithPath: root + "/SlowQueueControls.txt"), options: .withoutOverwriting)
print("READY paused copy/overlapping move/independent copy, separate own source, reversible deletion fixture, concurrency two")
