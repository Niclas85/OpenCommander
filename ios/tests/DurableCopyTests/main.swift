import Foundation
var boot = Data(repeating: 0, count: 512)
boot.replaceSubrange(3..<11, with: Data("NTFS    ".utf8))
boot[12] = 2; boot[13] = 8; boot[42] = 2; boot[72] = 17; boot[510] = 0x55; boot[511] = 0xaa
let bootIdentity = VolumeIdentity.ntfsBootToken(boot)
precondition(bootIdentity == "ntfs:0000000000000011:512:131072")
var differentBoot = boot; differentBoot[72] = 18
precondition(VolumeIdentity.ntfsBootToken(differentBoot) != bootIdentity)
var invalidBoot = boot; invalidBoot[13] = 3
precondition(VolumeIdentity.ntfsBootToken(invalidBoot) == nil)
precondition(VolumeIdentity.ntfsBootToken(Data(repeating: 0, count: 512)) == nil)
let offsetData = Data(repeating: 0, count: 128) + boot
precondition(VolumeIdentity.ntfsBootToken(offsetData[128..<640]) == bootIdentity)
print("PASS stable NTFS serial/geometry identity, changed-volume and malformed-header refusal, offset data slices")
import Darwin

func require(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func rejected(_ action: () throws -> Void, _ message: String) {
    do { try action(); fatalError(message) } catch {}
}
let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
    .appendingPathComponent("OpenCommander-DurableTests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }
let source = root.appendingPathComponent("source.bin")
let bytes = Data((0..<131072).map { UInt8($0 % 251) })
try bytes.write(to: source)
let destination = root.appendingPathComponent("target.bin")
let stage = try DurableFileCopy.create(source: source, destination: destination)
var checkpoint: Int64 = 0
let paused = try DurableFileCopy.resume(stage, blockSize: 4096,
    control: { checkpoint >= 16384 ? .pause : .proceed },
    progress: { checkpoint = $0; require($1 == Int64(bytes.count), "wrong total") })
require(paused.state == .paused && paused.bytes == 16384, "pause boundary")
require(!FileManager.default.fileExists(atPath: destination.path), "partial destination published")
let checkpointJournal = try DurableFileCopy.inspect(stage)
require(checkpointJournal.offset == paused.bytes, "checkpoint not durable")
var verification: [DurableFileCopy.Activity] = []
var resumedOffsets: [Int64] = []
let resumed = try DurableFileCopy.resume(stage, blockSize: 4096,
    progress: { bytes, _ in resumedOffsets.append(bytes) }, activity: { verification.append($0) })
require(resumed.state == .completed, "resume failed")
let resumedData = try Data(contentsOf: destination)
require(resumedData == bytes, "resume content mismatch")
require(resumedOffsets.first == paused.bytes && resumedOffsets.allSatisfy { $0 >= paused.bytes }, "resume resets copied byte count")
let partialChecks = verification.filter { $0.phase == .checkingPartial }
require(partialChecks.first?.done == 0 && partialChecks.last?.done == paused.bytes,
    "partial verification must have its own zero-to-checkpoint counter")
require(partialChecks.allSatisfy { $0.total == paused.bytes }, "verification counted uncopied source bytes")
require(verification.contains { $0.phase == .copying } && verification.contains { $0.phase == .publishing }, "copy/publication phases absent")
print("PASS resumed copied bytes stay stable; independent checked-byte progress, copy and publication phases")
let again = try DurableFileCopy.resume(stage)
require(again.state == .completed, "completed inspection failed")
try Data("altered published target".utf8).write(to: destination)
rejected({ _ = try DurableFileCopy.resume(stage) }, "changed completed destination accepted")
print("PASS pause, persisted checkpoint, explicit resume and complete byte equality")

let corruptTarget = root.appendingPathComponent("corrupt-target")
let corruptStage = try DurableFileCopy.create(source: source, destination: corruptTarget)
var offset: Int64 = 0
_ = try DurableFileCopy.resume(corruptStage, blockSize: 4096,
    control: { offset > 0 ? .pause : .proceed }, progress: { copied, _ in offset = copied })
let handle = try FileHandle(forWritingTo: corruptStage.appendingPathComponent("payload"))
try handle.write(contentsOf: Data([255])); try handle.close()
rejected({ _ = try DurableFileCopy.resume(corruptStage) }, "corrupt prefix accepted")
require(!FileManager.default.fileExists(atPath: corruptTarget.path), "corruption published")
print("PASS altered partial prefix refused without destination mutation")

let existing = root.appendingPathComponent("existing")
let old = Data("old destination".utf8); try old.write(to: existing)
let existingStage = try DurableFileCopy.create(source: source, destination: existing)
rejected({ _ = try DurableFileCopy.resume(existingStage) }, "existing destination overwritten")
let existingData = try Data(contentsOf: existing)
require(existingData == old, "old destination changed")
print("PASS atomic publication refuses collisions and preserves existing destination")

let cancelledTarget = root.appendingPathComponent("cancelled")
let cancelledStage = try DurableFileCopy.create(source: source, destination: cancelledTarget)
let cancelled = try DurableFileCopy.resume(cancelledStage, control: { .cancel })
require(cancelled.state == .cancelled, "cancel state")
rejected({ _ = try DurableFileCopy.resume(cancelledStage) }, "cancelled job resumed")
require(!FileManager.default.fileExists(atPath: cancelledTarget.path), "cancel destination exists")
print("PASS cancellation retains private recovery and refuses implicit restart")

let changedStage = try DurableFileCopy.create(source: source, destination: root.appendingPathComponent("changed"))
try Data("changed source".utf8).write(to: source)
rejected({ _ = try DurableFileCopy.resume(changedStage) }, "changed source accepted")
let alias = root.appendingPathComponent("alias")
try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
rejected({ _ = try DurableFileCopy.create(source: source, destination: alias.appendingPathComponent("unsafe")) }, "directory alias accepted")
try Data("not a journal".utf8).write(to: changedStage.appendingPathComponent("journal.json"))
rejected({ _ = try DurableFileCopy.inspect(changedStage) }, "invalid journal accepted")
print("PASS changed source, alias destination and corrupt journal safely rejected")

let lockedStage = try DurableFileCopy.create(source: source, destination: root.appendingPathComponent("locked"))
var testedLock = false
_ = try DurableFileCopy.resume(lockedStage, blockSize: 4, progress: { _, _ in
    if !testedLock {
        testedLock = true
        rejected({ _ = try DurableFileCopy.resume(lockedStage) }, "concurrent worker accepted")
    }
})
require(testedLock, "worker lock not tested")
print("PASS one worker per staging journal, including concurrent resume refusal")

var interruptedPublication = try DurableFileCopy.inspect(lockedStage)
interruptedPublication.state = .publishing
try JSONEncoder().encode(interruptedPublication).write(to: lockedStage.appendingPathComponent("journal.json"))
let reconciled = try DurableFileCopy.resume(lockedStage)
require(reconciled.state == .completed, "exclusive publication recovery failed")
var uncertain = try DurableFileCopy.inspect(stage)
uncertain.state = .publishing
try JSONEncoder().encode(uncertain).write(to: stage.appendingPathComponent("journal.json"))
rejected({ _ = try DurableFileCopy.resume(stage) }, "changed published target accepted as recovered success")
print("PASS explicit recovery across publication window validates identity; changed target refused")

let volumeStage = try DurableFileCopy.create(source: source, destination: root.appendingPathComponent("volume-check"))
var wrongVolume = try DurableFileCopy.inspect(volumeStage)
wrongVolume.targetVolume = "different-volume"
try JSONEncoder().encode(wrongVolume).write(to: volumeStage.appendingPathComponent("journal.json"))
rejected({ _ = try DurableFileCopy.resume(volumeStage) }, "wrong target volume accepted")
print("PASS stored target volume UUID prevents resume on a different mounted volume")
