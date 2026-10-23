import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2,
      let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let root = String(cString: physical)
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else {
    fatalError("only a stopped isolated app may receive synthetic queued-job fixtures")
}
let fm = FileManager.default
let journal = URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json")
let backup = URL(fileURLWithPath: root + "/Transfers/BeforeQueueControls.saved.json")
guard !fm.fileExists(atPath: backup.path) else { fatalError("never overwrite an earlier queue backup") }
let data = try Data(contentsOf: journal)
guard var store = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      var jobs = store["jobs"] as? [[String: Any]], jobs.count <= 997,
      jobs.allSatisfy({ ["completed", "cancelled"].contains($0["state"] as? String ?? "") }) else {
    fatalError("never modify active, pending, paused, failed or unknown jobs")
}
let ids = ["6DCD9B7A-AE46-42CA-94B3-78F73B17A601", "BAF61F0C-AAC3-4CA0-AC13-A205CA692602", "CFF64E36-1054-4518-B720-FDC53DF89603"]
for (index, name) in ["Alpha.bin", "Beta.bin", "Gamma.bin"].enumerated() {
    let source = root + "/QueueControls/Sources/" + name
    guard (try fm.attributesOfItem(atPath: source)[.size] as? NSNumber)?.int64Value == 64 * 1024 * 1024 else { fatalError("own source missing or changed") }
    let destination = root + "/QueueControls/Dest" + ["A", "B", "C"][index] + "/" + name
    guard !fm.fileExists(atPath: destination) else { fatalError("destination must not exist") }
    jobs.append(["id": ids[index], "source": source, "destination": destination,
                 "state": "paused", "bytes": 0, "total": 64 * 1024 * 1024,
                 "created": Date().timeIntervalSinceReferenceDate, "compact": true])
}
try data.write(to: backup, options: .withoutOverwriting)
store["jobs"] = jobs; store["limit"] = 2
try JSONSerialization.data(withJSONObject: store).write(to: journal, options: .atomic)
print("READY three paused own jobs; original terminal-only queue backed up unchanged; limit=2")
