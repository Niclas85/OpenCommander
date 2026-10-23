import Foundation
import CryptoKit

guard CommandLine.arguments.count == 2 else { fatalError("own conflict fixture required") }
let root = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
precondition(root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-ProfileGuard-20261023-"))
let expected = [
    "Left/Guard.txt": "Own guarded profile source.\n",
    "Right/Guard.txt": "Own older destination for native replace acceptance.\n",
    "Right/Guard (2).txt": "Own guarded profile source.\n",
    "Right/Sentinel.txt": "Own guarded profile destination sentinel.\n"
]
for path in expected.keys.sorted() {
    let bytes = try Data(contentsOf: root.appendingPathComponent(path))
    precondition(bytes == Data(expected[path]!.utf8))
    print("SHA256", path, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
}
let left = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Left").path)
let right = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Right").path)
func userNames(_ names: [String], in folder: String) throws -> [String] {
    let prefixes = [".OpenCommanderJob-", ".OpenCommanderTransfer-", ".OpenCommanderUndo-"]
    return try names.filter { name in
        guard let prefix = prefixes.first(where: { name.hasPrefix($0) }) else { return true }
        precondition(UUID(uuidString: String(name.dropFirst(prefix.count))) != nil)
        let info = try root.appendingPathComponent(folder).appendingPathComponent(name)
            .resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        precondition(info.isDirectory == true && info.isSymbolicLink != true)
        return false // Undo/recovery-owned directories are intentionally retained.
    }.sorted()
}
let leftUserNames = try userNames(left, in: "Left")
let rightUserNames = try userNames(right, in: "Right")
precondition(leftUserNames == ["Guard.txt"] && rightUserNames == ["Guard (2).txt", "Guard.txt", "Sentinel.txt"])
let store = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Transfers/copy-jobs-v1.json"))) as! [String: Any]
precondition((store["jobs"] as? [[String: Any]])?.isEmpty == true)
print("PASS native Copy/Move replacement Undo restores exact source and older target, Keep retains both, Cancel adds no job, clear-completed persists empty queue without changing files")
