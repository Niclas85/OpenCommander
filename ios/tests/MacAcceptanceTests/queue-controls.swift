import Foundation
import Darwin

guard CommandLine.arguments.count == 2,
      let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated fixture required") }
defer { free(physical) }
let rootPath = String(cString: physical)
let root = URL(fileURLWithPath: rootPath)
let fm = FileManager.default
guard rootPath.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      fm.fileExists(atPath: root.appendingPathComponent("PreserveAppState.txt").path) else { fatalError("unsafe root") }
let fixture = root.appendingPathComponent("QueueControls")
guard !fm.fileExists(atPath: fixture.path) else { fatalError("never overwrite an existing fixture") }
try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
for name in ["Sources", "DestA", "DestB", "DestC", "DestOverlap"] {
    try fm.createDirectory(at: fixture.appendingPathComponent(name), withIntermediateDirectories: false)
}
for (index, name) in ["Alpha.bin", "Beta.bin", "Gamma.bin"].enumerated() {
    let file = fixture.appendingPathComponent("Sources/" + name)
    let descriptor = open(file.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    let block = Data(repeating: UInt8(65 + index), count: 1024 * 1024)
    for _ in 0..<64 { try handle.write(contentsOf: block) }
    try handle.synchronize(); try handle.close()
}
print("READY three own distinct 64-MiB files and four empty destinations; originals never overwritten")
