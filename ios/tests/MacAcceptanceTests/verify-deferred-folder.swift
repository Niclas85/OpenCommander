import Foundation
import AppKit
import Darwin

@main enum VerifyDeferredFolder {
    static func main() throws {
        guard CommandLine.arguments.count == 2, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
        defer { free(physical) }
        let root = String(cString: physical), fm = FileManager.default
        guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
              NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
        let store = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: root + "/Transfers/copy-jobs-v1.json"))) as! [String: Any]
        let jobs = store["jobs"] as! [[String: Any]]
        precondition(jobs.allSatisfy { ["completed", "cancelled"].contains($0["state"] as! String) })
        precondition(Set(jobs.map { $0["id"] as! String }).count == jobs.count)
        let fixture = root + "/QueueControls/DeferredFolder"
        let source = URL(fileURLWithPath: fixture + "/Sources/DeferredDeleteFolder")
        let completed = jobs.filter { ($0["source"] as? String).map { DurableTransferQueue.reservationPath($0) == DurableTransferQueue.reservationPath(source.path) } == true && $0["deleteToTrash"] as? Bool == true && $0["state"] as? String == "completed" }
        precondition(completed.count == 1)
        let job = completed[0], id = job["id"] as! String
        let proof = Data(base64Encoded: job["deletionProof"] as! String)!
        let actual = try SafeFileOperations.snapshot(source)
        precondition(proof == actual && proof.count == 32)
        let text = try String(contentsOf: source.appendingPathComponent("Nested/Grüsse.txt"), encoding: .utf8)
        precondition(text == "Own native recursive deletion proof – Grüsse 日本語\n")
        let empty = try fm.contentsOfDirectory(atPath: source.appendingPathComponent("Nested/Empty").path)
        precondition(empty.isEmpty)
        let outsideLink = try fm.destinationOfSymbolicLink(atPath: source.appendingPathComponent("outside-link").path)
        let cycleLink = try fm.destinationOfSymbolicLink(atPath: source.appendingPathComponent("cycle-link").path)
        precondition(outsideLink == fixture + "/outside.txt")
        precondition(cycleLink == fixture + "/Sources/DeferredDeleteFolder")
        let outside = try String(contentsOfFile: fixture + "/outside.txt", encoding: .utf8)
        precondition(outside == "Outside target must remain unchanged\n")
        let independent = try String(contentsOfFile: fixture + "/Sources/Independent.txt", encoding: .utf8)
        precondition(independent == "Own independent paused folder-test job\n")
        precondition(!fm.fileExists(atPath: fixture + "/Copy/DeferredDeleteFolder") && !fm.fileExists(atPath: fixture + "/Other/Independent.txt"))
        for blocked in ["121EC5B0-4526-410D-A1FA-A3A9BF31C501", "121EC5B0-4526-410D-A1FA-A3A9BF31C502"] {
            precondition(jobs.first { $0["id"] as? String == blocked }?["state"] as? String == "cancelled")
        }
        let stage = job["staging"] as! String
        precondition(stage.hasPrefix(fixture + "/Sources/.OpenCommanderUndo-"))
        let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: stage + "/deletion-receipt.json"))) as! [String: Any]
        precondition(receipt["id"] as? String == id && receipt["destination"] as? String == job["destination"] as? String)
        precondition(!fm.fileExists(atPath: job["destination"] as! String))
        print("PASS actual folder Trash/Undo exact recursive admission proof, Unicode child, empty directory, unchanged symlinks/outside target, retained receipt and terminal-only queue")
    }
}
