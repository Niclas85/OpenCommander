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
let backup = URL(fileURLWithPath: root + "/Transfers/BeforeDeferredDelete.saved.json")
let bytes = try Data(contentsOf: journal)
guard !fm.fileExists(atPath: backup.path), var store = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      var jobs = store["jobs"] as? [[String: Any]], jobs.count <= 998,
      jobs.allSatisfy({ ["completed", "cancelled"].contains($0["state"] as? String ?? "") }) else { fatalError("never alter unfinished work or overwrite backup") }
let fixture = root + "/QueueControls/DeferredDelete"
guard !fm.fileExists(atPath: fixture) else { fatalError("never overwrite fixture") }
try fm.createDirectory(atPath: fixture, withIntermediateDirectories: false)
for name in ["Sources", "Copy", "Other"] { try fm.createDirectory(atPath: fixture + "/" + name, withIntermediateDirectories: false) }
for (index, name) in ["DeferredDelete.txt", "Independent.txt"].enumerated() {
    let text = index == 0 ? "Own native deferred deletion acceptance, restore exactly.\n" : "Own independent paused job, never start automatically.\n"
    let source = fixture + "/Sources/" + name
    let data = Data(text.utf8)
    try data.write(to: URL(fileURLWithPath: source), options: .withoutOverwriting)
    jobs.append(["id": "121EC5B0-4526-410D-A1FA-A3A9BF31C40" + String(index + 1),
                 "source": source, "destination": fixture + (index == 0 ? "/Copy/" : "/Other/") + name,
                 "state": "paused", "bytes": 0, "total": data.count,
                 "created": Date().timeIntervalSinceReferenceDate, "compact": true])
}
try bytes.write(to: backup, options: .withoutOverwriting)
store["jobs"] = jobs; store["limit"] = 2
try JSONSerialization.data(withJSONObject: store).write(to: journal, options: .atomic)
print("READY two own paused admissions; deferred deletion must be requested through native controls")
