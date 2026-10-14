// SPDX-License-Identifier: GPL-2.0-or-later
// Independent readback of the native engine fixture through Apple's NTFS reader.
import Foundation
import Darwin

precondition(CommandLine.arguments.count == 2)
let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
precondition(root.lastPathComponent == "mount" && root.deletingLastPathComponent().lastPathComponent.hasPrefix("engine-fixture."))
var filesystem = statfs()
precondition(statfs(root.path, &filesystem) == 0)
let kind = withUnsafePointer(to: &filesystem.f_fstypename) {
    $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
}
let mount = withUnsafePointer(to: &filesystem.f_mntonname) {
    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
}
precondition(kind == "ntfs" && filesystem.f_flags & UInt32(MNT_RDONLY) != 0)
precondition(URL(fileURLWithPath: mount).resolvingSymlinksInPath() == root)
let fm = FileManager.default
// The native suite finishes with an explicit case-only rename to HELLO.TXT.
let content = try Data(contentsOf: root.appendingPathComponent("HELLO.TXT"))
precondition(content == Data("Hello NTFS!\r\n".utf8))
var dated = stat()
precondition(lstat(root.appendingPathComponent("timestamps.txt").path, &dated) == 0)
print("Apple timestamp readback: modify=\(dated.st_mtimespec.tv_sec).\(dated.st_mtimespec.tv_nsec), birth=\(dated.st_birthtimespec.tv_sec).\(dated.st_birthtimespec.tv_nsec)")
fflush(stdout)
precondition(dated.st_mtimespec.tv_sec == 1_500_000_001 && dated.st_mtimespec.tv_nsec == 456_789_100)
precondition(dated.st_birthtimespec.tv_sec == 1_234_567_890 && dated.st_birthtimespec.tv_nsec == 234_567_800)
var historical = stat()
precondition(lstat(root.appendingPathComponent("pre-1970.txt").path, &historical) == 0)
if historical.st_birthtimespec.tv_sec != -1 || historical.st_birthtimespec.tv_nsec != 234_567_800 {
    // Keep this incompatibility explicit, not a passed independent date check.
    // The native suite separately verifies the exact on-disk pre-1970 value
    // after reopen. Apple's Sequoia reader underflows this signed epoch case.
    print("LIMITATION Apple NTFS pre-1970 creation date: \(historical.st_birthtimespec.tv_sec).\(historical.st_birthtimespec.tv_nsec); expected -1 + 234567800ns. Not independently verified by Apple.")
}
let names = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("many").path)
precondition(names.count == 200 && Set(names) == Set((0..<200).map { String(format: "Entry-%03d.TxT", $0) }))
let mixed = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("case-proof").path)
precondition(mixed.contains("MiXeD.txt") && mixed.contains("NestedFolder"))
print("PASS Apple NTFS native-engine reopen: exact file data, 100ns post-1970 modification/birth dates, 200 original-case names")
