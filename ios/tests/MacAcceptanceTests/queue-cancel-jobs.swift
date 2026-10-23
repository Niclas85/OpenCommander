import Foundation
import AppKit
import Darwin

let rapid = CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--rapid"
guard CommandLine.arguments.count == 2 || rapid,
      let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let root = String(cString: physical)
let fm = FileManager.default
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      fm.fileExists(atPath: root + "/PreserveAppState.txt"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else {
    fatalError("only a stopped isolated app may receive synthetic queued-job fixtures")
}
let journal = URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json")
let batch = rapid ? "QueueRapid" : "QueueCancel"
let backup = URL(fileURLWithPath: root + "/Transfers/Before" + batch + ".saved.json")
let data = try Data(contentsOf: journal)
guard !fm.fileExists(atPath: backup.path),
      var store = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      var jobs = store["jobs"] as? [[String: Any]], jobs.count <= 997,
      jobs.allSatisfy({ ["completed", "cancelled"].contains($0["state"] as? String ?? "") }) else {
    fatalError("never overwrite backup or modify active/nonterminal jobs")
}
let ids = rapid
    ? ["121EC5B0-4526-410D-A1FA-A3A9BF31C201", "121EC5B0-4526-410D-A1FA-A3A9BF31C202", "121EC5B0-4526-410D-A1FA-A3A9BF31C203"]
    : ["121EC5B0-4526-410D-A1FA-A3A9BF31C101", "121EC5B0-4526-410D-A1FA-A3A9BF31C102", "121EC5B0-4526-410D-A1FA-A3A9BF31C103"]
for (index, name) in ["Alpha.bin", "Beta.bin", "Gamma.bin"].enumerated() {
    let source = root + "/QueueControls/Sources/" + name
    let attrs = try fm.attributesOfItem(atPath: source)
    guard attrs[.type] as? FileAttributeType == .typeRegular,
          (attrs[.size] as? NSNumber)?.int64Value == 64 * 1024 * 1024 else { fatalError("own source missing or changed") }
    let directory = root + "/QueueControls/" + (rapid ? "RapidDest" : "CancelDest") + ["A", "B", "C"][index]
    guard !fm.fileExists(atPath: directory) else { fatalError("never reuse a test destination") }
    try fm.createDirectory(atPath: directory, withIntermediateDirectories: false)
    jobs.append(["id": ids[index], "source": source, "destination": directory + "/" + name,
                 "state": "paused", "bytes": 0, "total": 64 * 1024 * 1024,
                 "created": Date().timeIntervalSinceReferenceDate, "compact": true])
}
try data.write(to: backup, options: .withoutOverwriting)
store["jobs"] = jobs; store["limit"] = 1
try JSONSerialization.data(withJSONObject: store).write(to: journal, options: .atomic)
let flag = URL(fileURLWithPath: root + "/SlowQueueControls.txt")
if fm.fileExists(atPath: flag.path) {
    guard try String(contentsOf: flag, encoding: .utf8) == "isolated cancellation acceptance only\n" else { fatalError("unknown existing slow flag") }
} else {
    try Data("isolated cancellation acceptance only\n".utf8).write(to: flag, options: .withoutOverwriting)
}
print("READY three paused own cancellation jobs; original terminal-only queue backed up; concurrency one")
