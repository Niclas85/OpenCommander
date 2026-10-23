import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let root = String(cString: physical), fm = FileManager.default
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
let journal = URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json")
let backup = URL(fileURLWithPath: root + "/Transfers/BeforeTrashBookmarkSmoke.saved.json")
let bytes = try Data(contentsOf: journal)
guard !fm.fileExists(atPath: backup.path), var store = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
      var jobs = store["jobs"] as? [[String: Any]], jobs.count < 1000,
      jobs.allSatisfy({ ["completed", "cancelled"].contains($0["state"] as? String ?? "") }) else { fatalError("never modify unfinished jobs or overwrite backup") }
let fixture = root + "/QueueControls/TrashBookmarkSmoke"
guard !fm.fileExists(atPath: fixture) else { fatalError("never overwrite own fixture") }
try fm.createDirectory(atPath: fixture, withIntermediateDirectories: false)
for name in ["Sources", "Copy"] { try fm.createDirectory(atPath: fixture + "/" + name, withIntermediateDirectories: false) }
let source = fixture + "/Sources/MacBookmarkSmoke.txt"
let text = "Own Mac Catalyst Trash bookmark smoke – restore exactly.\n"
try Data(text.utf8).write(to: URL(fileURLWithPath: source), options: .withoutOverwriting)
jobs.append(["id": "121EC5B0-4526-410D-A1FA-A3A9BF31C801", "source": source,
             "destination": fixture + "/Copy/MacBookmarkSmoke.txt", "state": "paused", "bytes": 0,
             "total": text.utf8.count, "created": Date().timeIntervalSinceReferenceDate, "compact": true])
try bytes.write(to: backup, options: .withoutOverwriting)
store["jobs"] = jobs
try JSONSerialization.data(withJSONObject: store).write(to: journal, options: .atomic)
print("READY own single paused reservation; request Trash through native app, restart before Undo")
