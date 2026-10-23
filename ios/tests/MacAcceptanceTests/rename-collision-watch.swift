import Foundation
import Darwin

// Test-only concurrent writer, never arbitrary user paths. Run AFTER preview.
guard CommandLine.arguments.count == 2 else { fatalError("fixture required") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
guard directory.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      directory.lastPathComponent == "RenamePartial",
      try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { fatalError("unsafe fixture") }
let original = directory.appendingPathComponent("A.bin")
let renamed = directory.appendingPathComponent("Result-A.bin")
guard FileManager.default.fileExists(atPath: original.path),
      !FileManager.default.fileExists(atPath: renamed.path),
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("B.txt").path) else { fatalError("unexpected fixture state") }
let descriptor = open(directory.path, O_EVTONLY | O_NOFOLLOW)
guard descriptor >= 0 else { fatalError("fixture not observable") }
let watch = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
watch.setEventHandler {
    if !FileManager.default.fileExists(atPath: original.path), FileManager.default.fileExists(atPath: renamed.path) {
        let output = open(original.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard output >= 0 else { exit(3) }
        let data = Data("Synthetic concurrent occupant; preserve this file.\n".utf8)
        let count = data.withUnsafeBytes { write(output, $0.baseAddress!, $0.count) }
        guard count == data.count, fsync(output) == 0 else { close(output); exit(4) }
        close(output)
        print("COLLISION_INJECTED after first committed rename; only own A.bin created exclusively")
        exit(0)
    }
}
watch.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
    fputs("No rename boundary observed; no collision injected\n", stderr)
    exit(2)
}
dispatchMain()
