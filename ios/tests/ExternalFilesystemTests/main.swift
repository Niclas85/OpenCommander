import Foundation
import Darwin

let fm = FileManager.default
guard (2...3).contains(CommandLine.arguments.count) else { fatalError("Pass the isolated mounted fixture") }
let volume = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard volume.path.hasPrefix("/private/tmp/OpenCommander-NTFS-Queue-"), volume.lastPathComponent == "mount" else { fatalError("Not an isolated fixture mountpoint") }
let resumeInfo = volume.deletingLastPathComponent().appendingPathComponent("resume.json")
if CommandLine.arguments.last == "--resume" {
    let info = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: resumeInfo))
    let stage = URL(fileURLWithPath: info["stage"]!), source = URL(fileURLWithPath: info["source"]!), target = URL(fileURLWithPath: info["target"]!)
    print("REMOUNT volumeUUID=\(String(describing: try volume.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString))")
    let journal = try DurableFileCopy.inspect(stage)
    print("JOURNAL UUID=\(String(describing: journal.targetVolume)), device=\(journal.targetDevice), state=\(journal.state)")
    print("CURRENT parent UUID=\(String(describing: try target.deletingLastPathComponent().resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString))")
    for url in [stage, stage.appendingPathComponent("worker.lock"), stage.appendingPathComponent("payload")] {
        var info = stat(); let result = lstat(url.path, &info)
        print("STAT \(url.lastPathComponent): result=\(result), mode=\(String(info.st_mode, radix: 8)), uid=\(info.st_uid), dev=\(info.st_dev), inode=\(info.st_ino), links=\(info.st_nlink)")
    }
    fflush(stdout)
    let result = try DurableFileCopy.resume(stage)
    guard result.state == .completed, try Data(contentsOf: source) == Data(contentsOf: target) else { fatalError("NTFS remount resume mismatch") }
    print("PASS durable NTFS resume after full detach/reattach, exact bytes")
    exit(0)
}
let source = URL(fileURLWithPath: "/private/tmp/OpenCommander-APFS-Queue-" + UUID().uuidString)
let destination = volume.appendingPathComponent("OpenCommander-External-" + UUID().uuidString)
try fm.createDirectory(at: source.appendingPathComponent("Unterordner"), withIntermediateDirectories: true)
try fm.createDirectory(at: destination, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: source) }
let file = source.appendingPathComponent("Grüsse.txt"), bytes = Data("APFS to NTFS metadata and durable transfer fixture".utf8)
try bytes.write(to: file)
try fm.setAttributes([.posixPermissions: 0o600, .modificationDate: Date(timeIntervalSince1970: 1_700_000_000.125)], ofItemAtPath: file.path)
try bytes.write(to: source.appendingPathComponent("Unterordner/.hidden"))
let metadata = try volume.resourceValues(forKeys: [.volumeSupportsAccessPermissionsKey, .volumeLocalizedFormatDescriptionKey])
print("FIXTURE capabilities: permissions=\(String(describing: metadata.volumeSupportsAccessPermissions)), format=\(metadata.volumeLocalizedFormatDescription ?? "unknown")"); fflush(stdout)
var fs = statfs(); _ = statfs(volume.path, &fs)
let type = withUnsafePointer(to: &fs.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) } }
let device = withUnsafePointer(to: &fs.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) } }
print("MOUNT type=\(type), source=\(device), stable=\(String(describing: try VolumeIdentity.token(at: volume)))"); fflush(stdout)
var failures = 0
func test(_ name: String, _ action: () throws -> Void) {
    do { try action(); print("PASS " + name) }
    catch { failures += 1; print("FAIL \(name): \(error)") }
    fflush(stdout)
}
test("Foundation APFS→NTFS regular file") {
    let target = destination.appendingPathComponent("foundation.txt")
    try fm.copyItem(at: file, to: target)
    guard try Data(contentsOf: target) == bytes else { throw CocoaError(.fileReadCorruptFile) }
}
test("Foundation APFS→NTFS folder") {
    let target = destination.appendingPathComponent("foundation-tree")
    try fm.copyItem(at: source, to: target)
    guard try Data(contentsOf: target.appendingPathComponent("Unterordner/.hidden")) == bytes else { throw CocoaError(.fileReadCorruptFile) }
}
test("Durable regular APFS→NTFS copy") {
    let target = destination.appendingPathComponent("durable.txt")
    let stage = try DurableFileCopy.create(source: file, destination: target)
    guard try DurableFileCopy.resume(stage).state == .completed, try Data(contentsOf: target) == bytes else { throw CocoaError(.fileReadCorruptFile) }
}
test("Durable tree APFS→NTFS copy") {
    let target = destination.appendingPathComponent("durable-tree")
    let stage = try DurableTreeTransfer.create(source: source, destination: target, move: false, replace: false)
    guard try DurableTreeTransfer.resume(stage).state == .completed,
        try Data(contentsOf: target.appendingPathComponent("Unterordner/.hidden")) == bytes else { throw CocoaError(.fileReadCorruptFile) }
}
print("External filesystem fixture retained at \(destination.path)")
let continuedSource = volume.deletingLastPathComponent().appendingPathComponent("resume-source.bin")
try Data(repeating: 37, count: 3 * 1024 * 1024).write(to: continuedSource)
let continuedTarget = destination.appendingPathComponent("resume-target.bin")
let continuedStage = try DurableFileCopy.create(source: continuedSource, destination: continuedTarget)
var count: Int64 = 0
let paused = try DurableFileCopy.resume(continuedStage, control: { count > 0 ? .pause : .proceed }, progress: { bytes, _ in count = bytes })
guard paused.state == .paused else { fatalError("NTFS fixture did not pause") }
try JSONEncoder().encode(["source": continuedSource.path, "target": continuedTarget.path, "stage": continuedStage.path]).write(to: resumeInfo)
print("PAUSED volumeUUID=\(String(describing: try volume.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)), bytes=\(count)")
exit(failures == 0 ? 0 : 1)
