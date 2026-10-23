import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let root = String(cString: physical), fm = FileManager.default
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      URL(fileURLWithPath: root).deletingLastPathComponent().path == "/private/tmp",
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
let journal = URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json")
let backup = URL(fileURLWithPath: root + "/Transfers/BeforeDeferredFolder.saved.json")
let bytes = try Data(contentsOf: journal)
guard !fm.fileExists(atPath: backup.path), var store = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      var jobs = store["jobs"] as? [[String: Any]], jobs.count <= 998,
      jobs.allSatisfy({ ["completed", "cancelled"].contains($0["state"] as? String ?? "") }) else { fatalError("never alter unfinished work or overwrite backup") }
let fixture = root + "/QueueControls/DeferredFolder"
guard !fm.fileExists(atPath: fixture) else { fatalError("never overwrite fixture") }
try fm.createDirectory(atPath: fixture, withIntermediateDirectories: false)
for name in ["Sources", "Copy", "Other"] { try fm.createDirectory(atPath: fixture + "/" + name, withIntermediateDirectories: false) }
let folder = fixture + "/Sources/DeferredDeleteFolder"
try fm.createDirectory(atPath: folder + "/Nested/Empty", withIntermediateDirectories: true)
try Data("Own native recursive deletion proof – Grüsse 日本語\n".utf8).write(to: URL(fileURLWithPath: folder + "/Nested/Grüsse.txt"), options: .withoutOverwriting)
try Data("Outside target must remain unchanged\n".utf8).write(to: URL(fileURLWithPath: fixture + "/outside.txt"), options: .withoutOverwriting)
try fm.createSymbolicLink(atPath: folder + "/outside-link", withDestinationPath: fixture + "/outside.txt")
try fm.createSymbolicLink(atPath: folder + "/cycle-link", withDestinationPath: folder)
let independent = fixture + "/Sources/Independent.txt"
try Data("Own independent paused folder-test job\n".utf8).write(to: URL(fileURLWithPath: independent), options: .withoutOverwriting)
for (index, name) in ["DeferredDeleteFolder", "Independent.txt"].enumerated() {
    jobs.append(["id": "121EC5B0-4526-410D-A1FA-A3A9BF31C50" + String(index + 1),
                 "source": fixture + "/Sources/" + name, "destination": fixture + (index == 0 ? "/Copy/" : "/Other/") + name,
                 "state": "paused", "bytes": 0, "total": 0,
                 "created": Date().timeIntervalSinceReferenceDate, "compact": true])
}
try bytes.write(to: backup, options: .withoutOverwriting)
store["jobs"] = jobs; store["limit"] = 2
try JSONSerialization.data(withJSONObject: store).write(to: journal, options: .atomic)
print("READY own folder, nested Unicode child, empty directory, external/cyclic symlinks, paused blocker and independent admission")
