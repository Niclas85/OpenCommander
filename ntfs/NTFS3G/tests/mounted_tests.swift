// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Darwin
func check(_ condition: Bool) { precondition(condition) }

// Only run inside the private image mount created by test-fskit.sh.
let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
precondition(root.lastPathComponent == "mount" && root.deletingLastPathComponent().lastPathComponent.hasPrefix("fskit-fixture."))
var fs = statfs()
precondition(statfs(root.path, &fs) == 0)
let kind = withUnsafePointer(to: &fs.f_fstypename) {
    $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
}
// FSKit exposes the volume's fileSystemTypeName, not the framework name.
precondition(kind == "openntfs", "Expected OpenCommander NTFS mount, got \(kind)")
let mountPoint = withUnsafePointer(to: &fs.f_mntonname) {
    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
}
precondition(URL(fileURLWithPath: mountPoint).resolvingSymlinksInPath() == root, "Test directory must be the mount root")
let fm = FileManager.default
let folder = root.appendingPathComponent("OpenCommander-Test-" + UUID().uuidString)
try fm.createDirectory(at: folder, withIntermediateDirectories: false)
let file = folder.appendingPathComponent("Grüsse-文件.txt")
let payload = Data("OpenCommander → FSKit → NTFS-3G\n".utf8)
try payload.write(to: file)
try check(Data(contentsOf: file) == payload)
check(try fm.contentsOfDirectory(atPath: root.path).contains(folder.lastPathComponent))
check(try fm.contentsOfDirectory(atPath: folder.path).contains("Grüsse-文件.txt"))
try check(Data(contentsOf: folder.appendingPathComponent("grüsse-文件.TXT")) == payload)
let mixed = folder.appendingPathComponent("MiXeD-Name.TxT")
try payload.write(to: mixed)
let caseRenamed = folder.appendingPathComponent("mIxEd-NAME.txt")
try fm.moveItem(at: mixed, to: caseRenamed)
let displayedNames = try fm.contentsOfDirectory(atPath: folder.path)
check(displayedNames.contains("mIxEd-NAME.txt") && !displayedNames.contains("MiXeD-Name.TxT"))
try check(Data(contentsOf: folder.appendingPathComponent("MIXED-NAME.TXT")) == payload)
print("PASS FSKit exact case-preserving listing, case-insensitive access and case-only rename")
let dated = folder.appendingPathComponent("Zeitstempel.txt")
try payload.write(to: dated)
let birth = Date(timeIntervalSince1970: 1_234_567_890)
try fm.setAttributes([.creationDate: birth], ofItemAtPath: dated.path)
var exactTimes = [timespec(tv_sec: 1_600_000_000, tv_nsec: 123_456_700),
                  timespec(tv_sec: 1_500_000_001, tv_nsec: 456_789_100)]
check(exactTimes.withUnsafeBufferPointer { utimensat(AT_FDCWD, dated.path, $0.baseAddress, 0) } == 0)
var datedStat = stat()
check(lstat(dated.path, &datedStat) == 0)
check(datedStat.st_atimespec.tv_sec == exactTimes[0].tv_sec && datedStat.st_atimespec.tv_nsec == exactTimes[0].tv_nsec)
check(datedStat.st_mtimespec.tv_sec == exactTimes[1].tv_sec && datedStat.st_mtimespec.tv_nsec == exactTimes[1].tv_nsec)
check(datedStat.st_birthtimespec.tv_sec == 1_234_567_890)
let datedCopy = folder.appendingPathComponent("Zeitstempel-Kopie.txt")
try fm.copyItem(at: dated, to: datedCopy)
check(lstat(datedCopy.path, &datedStat) == 0)
check(datedStat.st_mtimespec.tv_sec == exactTimes[1].tv_sec && datedStat.st_mtimespec.tv_nsec == exactTimes[1].tv_nsec)
try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_500_000_003)], ofItemAtPath: folder.path)
check(lstat(folder.path, &datedStat) == 0 && datedStat.st_mtimespec.tv_sec == 1_500_000_003)
print("PASS FSKit timestamps: exact access/modify precision, creation date, copy preservation and directory updates")
let large = folder.appendingPathComponent("large.bin")
let bytes = Data((0..<(2 * 1024 * 1024 + 17)).map { UInt8($0 % 251) })
try bytes.write(to: large)
try check(Data(contentsOf: large) == bytes)
let copy = folder.appendingPathComponent("copy.bin")
try fm.copyItem(at: large, to: copy)
try check(Data(contentsOf: copy) == bytes)
let renamed = folder.appendingPathComponent("renamed.bin")
try fm.moveItem(at: copy, to: renamed)
precondition(!fm.fileExists(atPath: copy.path))
try payload.write(to: renamed, options: .atomic)
try check(Data(contentsOf: renamed) == payload)
try fm.removeItem(at: renamed)
precondition(!fm.fileExists(atPath: renamed.path))
let handle = try FileHandle(forUpdating: large)
try handle.truncate(atOffset: 517)
try handle.synchronize()
try handle.close()
try check(Data(contentsOf: large) == bytes.prefix(517))
print("PASS FSKit mount: Unicode, create, read/write, copy, rename, replace, delete, truncate, fsync")
print("Retained test directory: \(folder.path)")
