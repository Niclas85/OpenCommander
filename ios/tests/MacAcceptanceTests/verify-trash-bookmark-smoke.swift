import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated root required") }
defer { free(physical) }
let root = String(cString: physical), fm = FileManager.default
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
let source = root + "/QueueControls/TrashBookmarkSmoke/Sources/MacBookmarkSmoke.txt"
let text = try String(contentsOfFile: source, encoding: .utf8)
precondition(text == "Own Mac Catalyst Trash bookmark smoke – restore exactly.\n")
let store = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json"))) as! [String: Any]
let jobs = store["jobs"] as! [[String: Any]]
precondition(jobs.allSatisfy { ["completed", "cancelled"].contains($0["state"] as! String) })
precondition(Set(jobs.map { $0["id"] as! String }).count == jobs.count)
let job = jobs.first { $0["id"] as? String == "8155A3F4-5384-4616-88DC-3A82210A30B7" }!
precondition(job["state"] as? String == "completed" && job["deleteToTrash"] as? Bool == true)
let stage = job["staging"] as! String
precondition(stage.hasPrefix(root + "/QueueControls/TrashBookmarkSmoke/Sources/.OpenCommanderUndo-"))
let reference = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: stage + "/selected-bookmark.json"))) as! [String: Any]
precondition(reference["id"] as? String == job["id"] as? String)
precondition(Data(base64Encoded: reference["proof"] as! String)?.count == 32)
precondition(Data(base64Encoded: reference["bookmark"] as! String)?.isEmpty == false)
let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: stage + "/deletion-receipt.json"))) as! [String: Any]
precondition(receipt["id"] as? String == job["id"] as? String && receipt["destination"] as? String == job["destination"] as? String)
precondition(!fm.fileExists(atPath: job["destination"] as! String))
precondition(!fm.fileExists(atPath: root + "/QueueControls/TrashBookmarkSmoke/Copy/MacBookmarkSmoke.txt"))
precondition(jobs.first { $0["id"] as? String == "121EC5B0-4526-410D-A1FA-A3A9BF31C801" }?["state"] as? String == "cancelled")
print("PASS Catalyst bookmark/receipt persisted; fresh-process native Undo restored exact text; own Trash entry absent, no copy published, all jobs terminal/unique")
