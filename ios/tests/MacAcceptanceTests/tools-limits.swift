import Foundation
import Darwin

guard CommandLine.arguments.count == 2 else { fatalError("isolated fixture required") }
let root = URL(fileURLWithPath: CommandLine.arguments[1])
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { fatalError("unsafe fixture root") }
let fm = FileManager.default
let large = root.appendingPathComponent("ToolsLarge")
let rename = root.appendingPathComponent("ToolsRenameLimit")
guard !fm.fileExists(atPath: large.path), !fm.fileExists(atPath: rename.path) else { fatalError("fixture already exists; never overwrite") }
func fill(_ directory: URL, count: Int) throws {
    try fm.createDirectory(at: directory, withIntermediateDirectories: false)
    let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard parent >= 0 else { throw CocoaError(.fileWriteNoPermission) }
    defer { close(parent) }
    for index in 0..<count {
        let name = String(format: "Entry-%05d.txt", index)
        let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        close(fd)
    }
}
try fm.createDirectory(at: large, withIntermediateDirectories: false)
for index in 0..<100 {
    try fill(large.appendingPathComponent(String(format: "Folder-%03d", index)), count: 1001)
}
try fm.createSymbolicLink(atPath: large.appendingPathComponent("Folder-000/Cycle").path, withDestinationPath: "..")
try fill(rename, count: 10_001)
print("FIXTURE_READY 100100 search files + 100 directories + cycle; 10001 flat rename candidates; all own empty synthetic files")
