import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2,
      let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let root = String(cString: physical)
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else {
    fatalError("verification requires stopped isolated app")
}
let fm = FileManager.default
let store = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json"))) as! [String: Any]
let jobs = store["jobs"] as! [[String: Any]]
precondition(jobs.allSatisfy { ["completed", "cancelled"].contains($0["state"] as! String) })
precondition(Set(jobs.map { $0["id"] as! String }).count == jobs.count)
let own = jobs.filter { ($0["id"] as! String).hasPrefix("121EC5B0-") }
precondition(own.count == 6)
for job in own {
    let source = job["source"] as! String, destination = job["destination"] as! String
    precondition(source.hasPrefix(root + "/QueueControls/Sources/") && destination.hasPrefix(root + "/QueueControls/"))
    let sourceBytes = try Data(contentsOf: URL(fileURLWithPath: source))
    precondition(sourceBytes.count == 64 * 1024 * 1024)
    let expectedByte: [String: UInt8] = ["Alpha.bin": 65, "Beta.bin": 66, "Gamma.bin": 67]
    precondition(sourceBytes == Data(repeating: expectedByte[(source as NSString).lastPathComponent]!, count: 64 * 1024 * 1024))
    if job["state"] as! String == "completed" {
        let result = try Data(contentsOf: URL(fileURLWithPath: destination))
        precondition(result == sourceBytes)
        print("PASS completed exact", job["id"]!, result.count)
    } else {
        precondition(!fm.fileExists(atPath: destination))
        if let stage = job["staging"] as? String {
            precondition(stage.hasPrefix(root + "/QueueControls/"))
            let partial = try Data(contentsOf: URL(fileURLWithPath: stage + "/payload"))
            precondition(partial.count == (job["bytes"] as! NSNumber).intValue)
            precondition(partial == sourceBytes.prefix(partial.count))
            print("PASS cancelled retained exact source prefix", job["id"]!, partial.count)
        } else {
            let contents = try fm.contentsOfDirectory(atPath: (destination as NSString).deletingLastPathComponent)
            precondition(contents.isEmpty)
            print("PASS queued cancellation no stage/no target", job["id"]!)
        }
    }
}
print("PASS six own jobs terminal, unique IDs, exact outputs and retained partial data; no source changed")
