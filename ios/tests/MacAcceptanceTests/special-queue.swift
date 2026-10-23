import Foundation
import Darwin

// Synthetic journal states for direct native UI acceptance. Never use a real
// profile or alter a running queue. Caller closes its disposable test app first.
guard CommandLine.arguments.count == 3 else { fatalError("root and full|restore required") }
let fm = FileManager.default
guard let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("fixture root missing") }
defer { free(physical) }
let root = URL(fileURLWithPath: String(cString: physical))
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      root.deletingLastPathComponent().path == "/private/tmp",
      fm.fileExists(atPath: root.appendingPathComponent("Left/Source.txt").path),
      fm.fileExists(atPath: root.appendingPathComponent("Right/Sentinel.txt").path) else { fatalError("not an isolated special-case fixture") }
let directory = root.appendingPathComponent("Transfers")
let journal = directory.appendingPathComponent("copy-jobs-v1.json")
switch CommandLine.arguments[2] {
case "full":
    let retained = directory.appendingPathComponent("damaged-journal.saved")
    guard !fm.fileExists(atPath: retained.path) else { fatalError("backup already exists") }
    try fm.copyItem(at: journal, to: retained)
    let jobs: [[String: Any]] = (0..<1000).map { index in [
        "id": UUID().uuidString,
        "source": root.appendingPathComponent("Left/Source.txt").path,
        "destination": root.appendingPathComponent("Right/Synthetic-old-\(index).txt").path,
        "state": "cancelled", "bytes": 0, "total": 62,
        "created": Date().timeIntervalSinceReferenceDate, "compact": true
    ] }
    try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 2, "jobs": jobs]).write(to: journal, options: .atomic)
case "restore":
    let backup = directory.appendingPathComponent("known-good-backup.json")
    let bytes = try Data(contentsOf: backup)
    try bytes.write(to: journal, options: .atomic)
default: fatalError("unsupported fixture mode")
}
print("Prepared synthetic queue: \(CommandLine.arguments[2])")
