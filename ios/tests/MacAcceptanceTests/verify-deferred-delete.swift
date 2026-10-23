import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let root = String(cString: physical), fm = FileManager.default
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
let store = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json"))) as! [String: Any]
let jobs = store["jobs"] as! [[String: Any]]
precondition(jobs.allSatisfy { ["completed", "cancelled"].contains($0["state"] as! String) })
precondition(Set(jobs.map { $0["id"] as! String }).count == jobs.count)
let fixture = root + "/QueueControls/DeferredDelete"
let original = try String(contentsOfFile: fixture + "/Sources/DeferredDelete.txt", encoding: .utf8)
precondition(original == "Own native deferred deletion acceptance, restore exactly.\n")
let independent = try String(contentsOfFile: fixture + "/Sources/Independent.txt", encoding: .utf8)
precondition(independent == "Own independent paused job, never start automatically.\n")
precondition(!fm.fileExists(atPath: fixture + "/Copy/DeferredDelete.txt"))
precondition(!fm.fileExists(atPath: fixture + "/Other/Independent.txt"))
let completed = jobs.first { $0["id"] as? String == "B69B4428-3888-46B6-8900-1E76F2A0C1DA" }!
precondition(completed["state"] as? String == "completed" && completed["deleteToTrash"] as? Bool == true)
let cancelled = jobs.first { $0["id"] as? String == "52ABF850-AEF9-423C-BFF9-50D82E52752F" }!
precondition(cancelled["state"] as? String == "cancelled" && cancelled["staging"] == nil)
let stage = completed["staging"] as! String
precondition(stage.hasPrefix(fixture + "/Sources/.OpenCommanderUndo-"))
let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: stage + "/deletion-receipt.json"))) as! [String: Any]
precondition(receipt["id"] as? String == completed["id"] as? String)
precondition(receipt["destination"] as? String == completed["destination"] as? String)
precondition(!fm.fileExists(atPath: completed["destination"] as! String)) // Actual Undo already restored it.
for id in ["121EC5B0-4526-410D-A1FA-A3A9BF31C401", "121EC5B0-4526-410D-A1FA-A3A9BF31C402"] {
    precondition(jobs.first { $0["id"] as? String == id }?["state"] as? String == "cancelled")
}
print("PASS actual native Trash receipt retained, own file restored exactly by Undo, independent source exact/no copy published, all jobs terminal/unique")
