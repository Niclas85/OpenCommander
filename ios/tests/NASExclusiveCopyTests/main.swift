import Foundation
import Darwin

let fm = FileManager.default
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--prepare-disconnect" {
    let mount = URL(fileURLWithPath: CommandLine.arguments[2])
    guard mount.path.hasPrefix("/private/tmp/OpenCommander-NASMount."), NASExclusiveCopy.isSMB(mount) else { fatalError("Not an isolated test mount") }
    let fixture = mount.appendingPathComponent("OpenCommander-LiveQA-Disconnect-" + UUID().uuidString)
    try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
    let source = URL(fileURLWithPath: "/private/tmp/OpenCommander-NetworkSource-" + UUID().uuidString)
    try Data(repeating: 47, count: 8 * 1024 * 1024).write(to: source, options: .withoutOverwriting)
    let stage = try NASExclusiveCopy.create(source: source, target: fixture.appendingPathComponent("payload.bin"), journalParent: fixture)
    do { _ = try NASExclusiveCopy.resume(stage, fault: { if $0 == .wroteUncheckpointedBytes { throw POSIXError(.ENOTCONN) } }); exit(2) }
    catch { guard NASExclusiveCopy.isConnectionFailure(error) else { throw error } }
    print("DISCONNECT_STAGE \(stage.path)")
    print("DISCONNECT_SOURCE \(source.path)")
    exit(0)
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--resume" {
    let stage = URL(fileURLWithPath: CommandLine.arguments[2])
    guard stage.lastPathComponent.hasPrefix(".OpenCommanderExclusive-") else { fatalError("Not a test journal") }
    do { guard try NASExclusiveCopy.resume(stage) == .completed else { exit(2) } }
    catch { print("REFUSED resume: \(error)"); exit(1) }
    print("PASS new-process resume")
    exit(0)
}
guard (2...3).contains(CommandLine.arguments.count) else { fatalError("Pass empty, own fixture directory and optional Elements source fixture") }
let targetRoot = URL(fileURLWithPath: CommandLine.arguments[1])
guard targetRoot.lastPathComponent.hasPrefix("OpenCommander-LiveQA-"),
      targetRoot.path.hasPrefix("/Volumes/"), try fm.contentsOfDirectory(atPath: targetRoot.path).isEmpty else { fatalError("Unsafe fixture") }
let local = URL(fileURLWithPath: "/private/tmp/OpenCommander-NASExclusive-" + UUID().uuidString)
try fm.createDirectory(at: local, withIntermediateDirectories: false)
let sourceParent = CommandLine.arguments.count == 3 ? URL(fileURLWithPath: CommandLine.arguments[2]) : local
if sourceParent != local {
    guard sourceParent.path.hasPrefix("/Volumes/"), sourceParent.lastPathComponent.hasPrefix("OpenCommander-LiveQA-"),
          try fm.contentsOfDirectory(atPath: sourceParent.path).isEmpty else { fatalError("Unsafe source fixture") }
}
let source = sourceParent.appendingPathComponent("Source")
try fm.createDirectory(at: source.appendingPathComponent("Nested/Empty"), withIntermediateDirectories: true)
let bytes = Data((0..<(3 * 1024 * 1024 + 17)).map { UInt8($0 % 251) })
try bytes.write(to: source.appendingPathComponent("Grüsse 日本語.bin"))
try Data("hidden".utf8).write(to: source.appendingPathComponent("Nested/.hidden"))
var failures = 0
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); print("PASS " + name) } catch { failures += 1; print("FAIL \(name): \(error)") }
    fflush(stdout)
}
func require(_ condition: Bool) throws { if !condition { throw CocoaError(.fileReadCorruptFile) } }
check("exclusive tree with Unicode, hidden file and empty directory") {
    let target = targetRoot.appendingPathComponent("Tree")
    let stage = try NASExclusiveCopy.create(source: source, target: target, journalParent: local)
    try require(NASExclusiveCopy.resume(stage) == .completed)
    try require(Data(contentsOf: target.appendingPathComponent("Grüsse 日本語.bin")) == bytes)
    try require(NASExclusiveCopy.resume(stage) == .completed)
}
check("pause then explicit resume verifies existing prefix") {
    let target = targetRoot.appendingPathComponent("Paused.bin")
    let stage = try NASExclusiveCopy.create(source: source.appendingPathComponent("Grüsse 日本語.bin"), target: target, journalParent: local)
    var copied: Int64 = 0
    try require(NASExclusiveCopy.resume(stage, control: { copied > 0 ? .pause : .proceed }, progress: { copied = $0 }) == .paused)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["--resume", stage.path]
    try process.run(); process.waitUntilExit()
    try require(process.terminationStatus == 0)
    try require(Data(contentsOf: target) == bytes)
}
check("changed partial refused without repairing another writer's data") {
    let target = targetRoot.appendingPathComponent("Changed.bin")
    let stage = try NASExclusiveCopy.create(source: source.appendingPathComponent("Grüsse 日本語.bin"), target: target, journalParent: local)
    var copied: Int64 = 0
    _ = try NASExclusiveCopy.resume(stage, control: { copied > 0 ? .pause : .proceed }, progress: { copied = $0 })
    let fd = open(target.path, O_WRONLY); guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
    var byte: UInt8 = 99; _ = pwrite(fd, &byte, 1, 0); close(fd)
    var refused = false
    do { _ = try NASExclusiveCopy.resume(stage) } catch { refused = true }
    try require(refused && Data(contentsOf: target).first == 99)
}
check("two jobs racing the same name: exactly one wins, source intact") {
    for i in 0..<20 {
        let destination = targetRoot.appendingPathComponent("Race-\(i).bin")
        let a = try NASExclusiveCopy.create(source: source.appendingPathComponent("Nested/.hidden"), target: destination, journalParent: local)
        let b = try NASExclusiveCopy.create(source: source.appendingPathComponent("Nested/.hidden"), target: destination, journalParent: local)
        let results = Results(), group = DispatchGroup()
        for stage in [a,b] {
            group.enter(); DispatchQueue.global().async {
                if (try? NASExclusiveCopy.resume(stage)) == .completed { results.increment() }
                group.leave()
            }
        }
        group.wait(); try require(results.count == 1)
        try require(Data(contentsOf: destination) == Data("hidden".utf8))
    }
}
check("NAS replacement retains previous tree in private recovery") {
    let replacement = sourceParent.appendingPathComponent("Replacement")
    try fm.createDirectory(at: replacement, withIntermediateDirectories: false)
    try Data("new version".utf8).write(to: replacement.appendingPathComponent("New.txt"))
    let target = targetRoot.appendingPathComponent("Tree")
    let stage = try NASExclusiveCopy.create(source: replacement, target: target, journalParent: targetRoot, replace: true)
    try require(NASExclusiveCopy.resume(stage) == .completed)
    try require(Data(contentsOf: target.appendingPathComponent("New.txt")) == Data("new version".utf8))
    try require(Data(contentsOf: stage.appendingPathComponent("previous/Grüsse 日本語.bin")) == bytes)
    try require(NASExclusiveCopy.resume(stage) == .completed)
}
if sourceParent != local {
    check("NAS to Elements production tree copy and overwrite with retained previous version") {
        let from = targetRoot.appendingPathComponent("Tree"), to = sourceParent.appendingPathComponent("Returned")
        let first = try DurableTreeTransfer.create(source: from, destination: to, move: false, replace: false)
        try require(DurableTreeTransfer.resume(first).state == .completed)
        try require(Data(contentsOf: to.appendingPathComponent("New.txt")) == Data("new version".utf8))
        let second = try DurableTreeTransfer.create(source: from, destination: to, move: false, replace: true)
        let result = try DurableTreeTransfer.resume(second)
        try require(result.state == .completed && result.backup != nil)
        try require(Data(contentsOf: result.backup!.appendingPathComponent("New.txt")) == Data("new version".utf8))
        try require(Data(contentsOf: to.appendingPathComponent("New.txt")) == Data("new version".utf8))
    }
}
check("NAS overwrite undo restores old bytes and retains backup") {
    let target = targetRoot.appendingPathComponent("Undo.bin")
    let original = source.appendingPathComponent("Grüsse 日本語.bin")
    let first = try NASExclusiveCopy.create(source: original, target: target, journalParent: targetRoot)
    try require(NASExclusiveCopy.resume(first) == .completed)
    let replacement = source.appendingPathComponent("Nested/.hidden")
    let second = try NASExclusiveCopy.create(source: replacement, target: target, journalParent: targetRoot, replace: true)
    try require(NASExclusiveCopy.resume(second) == .completed)
    let backup = try NASExclusiveCopy.summary(second).backup!
    let undo = FileUndoRecord(source: replacement, destination: target, replacedBackup: backup)
    try undo.undo(move: false)
    try require(undo.completed && Data(contentsOf: target) == bytes && Data(contentsOf: backup) == bytes)
}
check("cancel preserves source and incomplete target without reporting completion") {
    let target = targetRoot.appendingPathComponent("Cancelled.bin")
    let stage = try NASExclusiveCopy.create(source: source.appendingPathComponent("Grüsse 日本語.bin"), target: target, journalParent: targetRoot)
    var copied: Int64 = 0
    try require(NASExclusiveCopy.resume(stage, control: { copied > 0 ? .cancel : .proceed }, progress: { copied = $0 }) == .cancelled)
    try require(NASExclusiveCopy.resume(stage) == .cancelled)
    try require(Data(contentsOf: target).count < bytes.count)
    try require(Data(contentsOf: source.appendingPathComponent("Grüsse 日本語.bin")) == bytes)
}
check("lost write acknowledgement resumes uncheckpointed bytes in a fresh process") {
    let target = targetRoot.appendingPathComponent("NetworkInterrupted.bin")
    let stage = try NASExclusiveCopy.create(source: source.appendingPathComponent("Grüsse 日本語.bin"), target: target, journalParent: targetRoot)
    var interrupted = false
    do { _ = try NASExclusiveCopy.resume(stage, fault: { if $0 == .wroteUncheckpointedBytes { throw POSIXError(.ENOTCONN) } }) }
    catch { interrupted = true }
    try require(interrupted && Data(contentsOf: target).count > 0 && NASExclusiveCopy.summary(stage).bytes == 0)
    let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--resume", stage.path]
    try process.run(); process.waitUntilExit(); try require(process.terminationStatus == 0)
    try require(Data(contentsOf: target) == bytes)
}
check("lost replacement acknowledgement retains backup and safely reconciles") {
    let target = targetRoot.appendingPathComponent("NetworkReplace.bin")
    try Data("old bytes".utf8).write(to: target)
    let stage = try NASExclusiveCopy.create(source: source.appendingPathComponent("Grüsse 日本語.bin"), target: target, journalParent: targetRoot, replace: true)
    var interrupted = false
    do { _ = try NASExclusiveCopy.resume(stage, fault: { if $0 == .retainedPrevious { throw POSIXError(.ENOTCONN) } }) } catch { interrupted = true }
    try require(interrupted && Data(contentsOf: stage.appendingPathComponent("previous")) == Data("old bytes".utf8))
    try require(NASExclusiveCopy.resume(stage) == .completed && Data(contentsOf: target) == bytes)
}
check("move source acknowledgement loss, replay and undo on NAS") {
    let origin = targetRoot.appendingPathComponent("MoveOrigin"), target = targetRoot.appendingPathComponent("Moved")
    try fm.createDirectory(at: origin, withIntermediateDirectories: false)
    try bytes.write(to: origin.appendingPathComponent("payload.bin"))
    let stage = try NASExclusiveCopy.create(source: origin, target: target, journalParent: targetRoot, move: true)
    var interrupted = false
    do { _ = try NASExclusiveCopy.resume(stage, fault: { if $0 == .retainedSource { throw POSIXError(.ENOTCONN) } }) }
    catch { guard NASExclusiveCopy.isConnectionFailure(error) else { throw error }; interrupted = true }
    try require(interrupted && !fm.fileExists(atPath: origin.path))
    try require(NASExclusiveCopy.resume(stage) == .completed)
    try require(NASExclusiveCopy.resume(stage) == .completed)
    let retained = try NASExclusiveCopy.summary(stage).quarantine!
    try require(Data(contentsOf: retained.appendingPathComponent("payload.bin")) == bytes)
    let undo = FileUndoRecord(source: origin, destination: target, replacedBackup: nil, quarantinedSource: retained)
    try undo.undo(move: true)
    try require(undo.completed && Data(contentsOf: origin.appendingPathComponent("payload.bin")) == bytes && !fm.fileExists(atPath: target.path))
}
check("Finder tags, FinderInfo, resource fork and dates survive NAS roundtrip") {
    let origin = local.appendingPathComponent("Attributed.txt"), target = targetRoot.appendingPathComponent("Attributed.txt"), returned = local.appendingPathComponent("Attributed-returned.txt")
    try Data("attributed data".utf8).write(to: origin)
    try require(chmod(origin.path, 0o751) == 0)
    let tags = try PropertyListSerialization.data(fromPropertyList: ["OpenCommander Test\n6"], format: .binary, options: 0)
    var finder = Data(repeating: 0, count: 32); finder.replaceSubrange(0..<4, with: Data("TEXT".utf8))
    let attributes = ["com.apple.metadata:_kMDItemUserTags": tags, "com.apple.FinderInfo": finder, "com.apple.ResourceFork": Data("test resource fork".utf8), "com.opencommander.test-user-attribute": Data("kept".utf8)]
    for (name, data) in attributes {
        try require(data.withUnsafeBytes { setxattr(origin.path, name, $0.baseAddress, $0.count, 0, 0) } == 0)
    }
    let date = Date(timeIntervalSince1970: 1_600_000_000)
    try fm.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: origin.path)
    let outward = try NASExclusiveCopy.create(source: origin, target: target, journalParent: targetRoot)
    try require(NASExclusiveCopy.resume(outward) == .completed)
    let inward = try NASExclusiveCopy.create(source: target, target: returned, journalParent: local)
    try require(NASExclusiveCopy.resume(inward) == .completed)
    for (name, expected) in attributes {
        var actual = Data(count: expected.count)
        try require(actual.withUnsafeMutableBytes { getxattr(returned.path, name, $0.baseAddress, $0.count, 0, 0) } == expected.count)
        try require(actual == expected)
    }
    let info = try fm.attributesOfItem(atPath: returned.path)
    try require(abs((info[.modificationDate] as! Date).timeIntervalSince(date)) < 1)
    try require(abs((info[.creationDate] as! Date).timeIntervalSince(date)) < 1)
    try require((info[.posixPermissions] as! NSNumber).uint16Value == 0o751)
}
if sourceParent != local {
    check("Elements to NAS move and NAS to Elements move preserve recoverable source") {
        let origin = sourceParent.appendingPathComponent("PhysicalMove.bin"), onNAS = targetRoot.appendingPathComponent("PhysicalMove.bin"), back = sourceParent.appendingPathComponent("PhysicalMovedBack.bin")
        try bytes.write(to: origin)
        let tag = Data("physical roundtrip attribute".utf8)
        try require(tag.withUnsafeBytes { setxattr(origin.path, "com.opencommander.test-user-attribute", $0.baseAddress, $0.count, 0, 0) } == 0)
        let outward = try NASExclusiveCopy.create(source: origin, target: onNAS, journalParent: targetRoot, move: true)
        try require(NASExclusiveCopy.resume(outward) == .completed && !fm.fileExists(atPath: origin.path))
        let inward = try NASExclusiveCopy.create(source: onNAS, target: back, journalParent: sourceParent, move: true)
        try require(NASExclusiveCopy.resume(inward) == .completed && !fm.fileExists(atPath: onNAS.path))
        try require(Data(contentsOf: back) == bytes)
        var returnedTag = Data(count: tag.count)
        try require(returnedTag.withUnsafeMutableBytes { getxattr(back.path, "com.opencommander.test-user-attribute", $0.baseAddress, $0.count, 0, 0) } == tag.count && returnedTag == tag)
        try require(Data(contentsOf: NASExclusiveCopy.summary(outward).quarantine!) == bytes)
        try require(Data(contentsOf: NASExclusiveCopy.summary(inward).quarantine!) == bytes)
    }
}
check("hidden flag survives a NAS roundtrip independently of ACL support") {
    let origin = local.appendingPathComponent("Hidden-only.txt"), target = targetRoot.appendingPathComponent("Hidden-only.txt")
    let returned = local.appendingPathComponent("Hidden-returned.txt")
    try Data("hidden metadata".utf8).write(to: origin)
    try require(chflags(origin.path, UInt32(UF_HIDDEN)) == 0)
    let outward = try NASExclusiveCopy.create(source: origin, target: target, journalParent: targetRoot)
    try require(NASExclusiveCopy.resume(outward) == .completed)
    let inward = try NASExclusiveCopy.create(source: target, target: returned, journalParent: local)
    try require(NASExclusiveCopy.resume(inward) == .completed)
    var info = stat()
    try require(lstat(returned.path, &info) == 0 && info.st_flags & UInt32(UF_HIDDEN) != 0)
    try require(Data(contentsOf: returned) == Data(contentsOf: origin))
}
check("changed source attributes prevent a move without removing source") {
    let origin = local.appendingPathComponent("ChangedMetadata.txt"), target = targetRoot.appendingPathComponent("ChangedMetadata.txt")
    try Data("source retained".utf8).write(to: origin)
    let stage = try NASExclusiveCopy.create(source: origin, target: target, journalParent: targetRoot, move: true)
    let changed = Data("external edit".utf8)
    try require(changed.withUnsafeBytes { setxattr(origin.path, "com.opencommander.test-user-attribute", $0.baseAddress, $0.count, 0, 0) } == 0)
    do { _ = try NASExclusiveCopy.resume(stage); throw CocoaError(.fileWriteUnknown) }
    catch NASExclusiveCopy.Failure.changedSource { }
    try require(Data(contentsOf: origin) == Data("source retained".utf8))
}
check("hidden flag and explicit ACL are preserved or safely refused before moving source") {
    let origin = local.appendingPathComponent("ACL-hidden.txt"), target = targetRoot.appendingPathComponent("ACL-hidden.txt")
    try Data("special metadata".utf8).write(to: origin)
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
    process.arguments = ["+a", "user:\(NSUserName()) allow read", origin.path]
    try process.run(); process.waitUntilExit(); try require(process.terminationStatus == 0)
    try require(chflags(origin.path, UInt32(UF_HIDDEN)) == 0)
    let stage = try NASExclusiveCopy.create(source: origin, target: target, journalParent: targetRoot, move: true)
    do {
        try require(NASExclusiveCopy.resume(stage) == .completed)
        try require(!fm.fileExists(atPath: origin.path))
        print("ACL_HIDDEN_NATIVE_PRESERVED")
    } catch NASExclusiveCopy.Failure.unsupported {
        try require(Data(contentsOf: origin) == Data("special metadata".utf8))
        print("ACL_HIDDEN_SERVER_UNSUPPORTED_SOURCE_RETAINED")
    }
}
print("FIXTURE \(targetRoot.path) JOURNALS \(local.path)")
exit(failures == 0 ? 0 : 1)
final class Results: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
