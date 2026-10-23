import Foundation

guard CommandLine.arguments.count == 3 else { fatalError("isolated root and phase required") }
let fm = FileManager.default, root = URL(fileURLWithPath: CommandLine.arguments[1])
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-") else { fatalError("unsafe test root") }
let local = root.appendingPathComponent("NativeNASAcceptance")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: local.appendingPathComponent("Manifest.json"))) as! [String:String]
guard manifest["local"] == local.path, let path = manifest["remote"],
      path.hasPrefix("/Volumes/Test/OpenCommander-LiveQA-20261018-qOIIyg/FoundationTree/NativeTransfers-20261019-") else { fatalError("unsafe own NAS fixture") }
let remote = URL(fileURLWithPath: path)
let source = try Data(contentsOf: local.appendingPathComponent("Source/Probe.txt"))
precondition(source == Data("Own native NAS copy ä – replacement version.\n".utf8))
let original = Data("Own native NAS copy ä – original version.\n".utf8)
let phase = CommandLine.arguments[2]
switch phase {
case "overwrite-undone", "move-undone":
    let bytes = try Data(contentsOf: remote.appendingPathComponent("Probe.txt"))
    precondition(bytes == original)
    precondition(!fm.fileExists(atPath: local.appendingPathComponent("Returned/Probe.txt").path))
case "moved-to-local":
    let bytes = try Data(contentsOf: local.appendingPathComponent("Returned/Probe.txt"))
    precondition(bytes == original)
    precondition(!fm.fileExists(atPath: remote.appendingPathComponent("Probe.txt").path))
case "tree-copied", "tree-move-undone", "tree-moved-to-local", "final":
    let target = phase == "tree-moved-to-local" ? local.appendingPathComponent("Returned") : remote
    let sourceBytes = try Data(contentsOf: local.appendingPathComponent("Source/Tree/Nested/Grüsse.txt"))
    let targetBytes = try Data(contentsOf: target.appendingPathComponent("Tree/Nested/Grüsse.txt"))
    precondition(sourceBytes == targetBytes && targetBytes == Data("Own native NAS tree – Grüße.\n".utf8))
    let empty = try fm.contentsOfDirectory(atPath: target.appendingPathComponent("Tree/Nested/Empty").path)
    precondition(empty.isEmpty)
    if phase == "tree-moved-to-local" { precondition(!fm.fileExists(atPath: remote.appendingPathComponent("Tree").path)) }
    if phase == "tree-move-undone" { precondition(!fm.fileExists(atPath: local.appendingPathComponent("Returned/Tree").path)) }
default: fatalError("unknown phase")
}
if phase == "final" {
    let remoteFile = try Data(contentsOf: remote.appendingPathComponent("Probe.txt"))
    precondition(remoteFile == original)
    precondition(!fm.fileExists(atPath: local.appendingPathComponent("Returned/Probe.txt").path))
    precondition(!fm.fileExists(atPath: local.appendingPathComponent("Returned/Tree").path))
    let queue = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Transfers/copy-jobs-v1.json"))) as! [String:Any]
    let jobs = queue["jobs"] as! [[String:Any]]
    precondition(Set(jobs.compactMap { $0["id"] as? String }).count == jobs.count)
    precondition(jobs.allSatisfy { ["completed", "cancelled"].contains($0["state"] as? String ?? "") })
    let ownJobs = jobs.filter { ($0["source"] as? String ?? "").hasPrefix(local.path + "/") || ($0["source"] as? String ?? "").hasPrefix(remote.path + "/") }
    precondition(ownJobs.count == 5 && ownJobs.allSatisfy { $0["state"] as? String == "completed" && $0["error"] == nil })
    print("PASS five native NAS jobs completed, unique IDs, no active queue work, original45B and Unicode tree restored, returned paths removed")
}
print("PASS native NAS \(phase): exact own contents and untouched48B source")
