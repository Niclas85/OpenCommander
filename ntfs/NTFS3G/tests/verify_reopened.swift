// SPDX-License-Identifier: GPL-2.0-or-later
// Independent, read-only verification through Apple's NTFS implementation.
import Foundation
import Darwin

guard CommandLine.arguments.count == 2 else { fatalError("Expected mount path") }
let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
var fs = statfs()
precondition(statfs(root.path, &fs) == 0)
let kind = withUnsafePointer(to: &fs.f_fstypename) {
    $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
}
precondition(kind == "ntfs" && (fs.f_flags & UInt32(MNT_RDONLY)) != 0,
             "Expected Apple's read-only NTFS mount, got \(kind)")
let fm = FileManager.default
let folders = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("OpenCommander-Test-") }
precondition(folders.count == 1, "Expected one retained FSKit test directory")
let folder = folders[0]
let payload = Data("OpenCommander → FSKit → NTFS-3G\n".utf8)
let small = try Data(contentsOf: folder.appendingPathComponent("Grüsse-文件.txt"))
precondition(small == payload, "Unicode file did not persist")
let displayedNames = try fm.contentsOfDirectory(atPath: folder.path)
precondition(displayedNames.contains("Grüsse-文件.txt") && displayedNames.contains("mIxEd-NAME.txt"),
             "Original spelling and case-only rename must persist on disk")
let mixed = try Data(contentsOf: folder.appendingPathComponent("mIxEd-NAME.txt"))
precondition(mixed == payload)
let large = try Data(contentsOf: folder.appendingPathComponent("large.bin"))
precondition(large == Data((0..<517).map { UInt8($0 % 251) }), "Truncated file did not persist")
precondition(!fm.fileExists(atPath: folder.appendingPathComponent("copy.bin").path))
precondition(!fm.fileExists(atPath: folder.appendingPathComponent("renamed.bin").path))
for name in ["Zeitstempel.txt", "Zeitstempel-Kopie.txt"] {
    var datedStat = stat()
    precondition(lstat(folder.appendingPathComponent(name).path, &datedStat) == 0)
    precondition(datedStat.st_mtimespec.tv_sec == 1_500_000_001 && datedStat.st_mtimespec.tv_nsec == 456_789_100,
                 "Modification timestamp did not persist")
}
var birthStat = stat()
precondition(lstat(folder.appendingPathComponent("Zeitstempel.txt").path, &birthStat) == 0 && birthStat.st_birthtimespec.tv_sec == 1_234_567_890)
print("PASS independent Apple NTFS read-only reopen: persisted exact modification/creation timestamps")
print("PASS independent Apple NTFS read-only reopen: exact Unicode content, 517-byte data, rename/delete persistence")
