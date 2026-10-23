import Foundation
import Darwin

// This executable only ever addresses an explicitly isolated test directory.
guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1].hasPrefix("/private/tmp/OpenCommander-DurableCrash-"),
      ["prepare", "crash", "resume"].contains(CommandLine.arguments[2]) else {
    fatalError("isolated crash fixture required")
}
let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[1])
guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
    fatalError("fixture alias refused")
}
let source = root.appendingPathComponent("source.bin")
let target = root.appendingPathComponent("target.bin")
let pathFile = root.appendingPathComponent("stage-path.txt")
let bytes = Data((0..<(1024 * 1024)).map { UInt8($0 % 251) })
switch CommandLine.arguments[2] {
case "prepare":
    try bytes.write(to: source, options: .withoutOverwriting)
    let stage = try DurableFileCopy.create(source: source, destination: target)
    try Data(stage.path.utf8).write(to: pathFile, options: .withoutOverwriting)
    print("PASS local abrupt-loss intent durably persisted")
case "crash":
    let stage = URL(fileURLWithPath: try String(contentsOf: pathFile, encoding: .utf8))
    guard stage.deletingLastPathComponent().path == root.path else { fatalError("foreign stage") }
    _ = try DurableFileCopy.resume(stage, blockSize: 4096, progress: { copied, _ in
        if copied >= 65536 {
            Darwin.kill(getpid(), SIGKILL)
            _exit(99)
        }
    })
    fatalError("copy completed instead of reaching kill boundary")
case "resume":
    let stage = URL(fileURLWithPath: try String(contentsOf: pathFile, encoding: .utf8))
    guard stage.deletingLastPathComponent().path == root.path else { fatalError("foreign stage") }
    let before = try DurableFileCopy.inspect(stage)
    guard before.offset == 65536, before.state == .copying,
          !fm.fileExists(atPath: target.path), try Data(contentsOf: source) == bytes else {
        fatalError("unexpected state following actual SIGKILL")
    }
    var offsets = [Int64]()
    let result = try DurableFileCopy.resume(stage, blockSize: 4096, progress: { copied, _ in offsets.append(copied) })
    guard result.state == .completed, offsets.first == before.offset,
          try Data(contentsOf: source) == bytes, try Data(contentsOf: target) == bytes else {
        fatalError("actual-kill resume did not preserve exact data/prefix")
    }
    print("PASS actual SIGKILL during data copy: readable 64-KiB checkpoint, unpublished partial, unchanged source, fresh-process exact resume")
default: fatalError("unknown fixture phase")
}
