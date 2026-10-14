import Foundation
import Darwin
import SystemConfiguration

// No arbitrary commands, paths, UIDs, repair, formatting or file-write API.
// The independent worker restores the open device descriptor even if the
// daemon/client dies. No persistent device permission changes are supported.
func worker() throws {
    // Parent death is observed through stdin EOF. Never die on a closed stdout
    // or launchd's termination signal between granting and restoring ownership.
    signal(SIGPIPE, SIG_IGN); signal(SIGTERM, SIG_IGN); signal(SIGHUP, SIG_IGN); signal(SIGINT, SIG_IGN)
    guard geteuid() == 0, CommandLine.arguments.count == 5,
          let uid = UInt32(CommandLine.arguments[4]), uid >= 501 else { throw NTFSAccessPolicy.failure("Invalid worker") }
    let device = CommandLine.arguments[2], uuid = CommandLine.arguments[3]
    let info = try NTFSAccessPolicy.info(device)
    guard NTFSAccessPolicy.eligible(info, device: device, uuid: uuid), !NTFSAccessPolicy.isMounted(info) else { throw NTFSAccessPolicy.failure("Partition not eligible or mounted") }
    let fd = open("/dev/r" + device, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw NTFSAccessPolicy.failure("Device open refused") }
    defer { close(fd) }
    var original = stat()
    guard fstat(fd, &original) == 0, original.st_mode & S_IFMT == S_IFCHR,
          original.st_uid == 0, original.st_gid == 5, original.st_mode & 0o777 == 0o640 else { throw NTFSAccessPolicy.failure("Unexpected device permissions") }
    var boot = [UInt8](repeating: 0, count: 512)
    var current = stat()
    guard pread(fd, &boot, 512, 0) == 512,
          Array(boot[3..<11]) == Array("NTFS    ".utf8), boot[510] == 0x55, boot[511] == 0xaa,
          NTFSAccessPolicy.eligible(try NTFSAccessPolicy.info(device), device: device, uuid: uuid),
          lstat("/dev/r" + device, &current) == 0, current.st_rdev == original.st_rdev,
          current.st_ino == original.st_ino else { throw NTFSAccessPolicy.failure("Not an external NTFS partition") }
    // Root-owned /Volumes gives the app a stable location across reconnections.
    // Never accept a client-supplied mount path or replace an existing object.
    let mountPath = "/Volumes/OpenCommander-" + UUID(uuidString: uuid)!.uuidString
    if mkdir(mountPath, 0o755) != 0 && errno != EEXIST { throw NTFSAccessPolicy.failure("Mount directory refused") }
    let directory = open(mountPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard directory >= 0 else { throw NTFSAccessPolicy.failure("Mount directory open refused") }
    defer { close(directory) }
    var directoryInfo = stat(), filesystem = statfs()
    guard fstat(directory, &directoryInfo) == 0, directoryInfo.st_uid == 0,
          directoryInfo.st_mode & 0o777 == 0o755, fstatfs(directory, &filesystem) == 0 else { throw NTFSAccessPolicy.failure("Unsafe mount directory") }
    let mountedAt = withUnsafePointer(to: &filesystem.f_mntonname) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
    guard mountedAt != mountPath, try FileManager.default.contentsOfDirectory(atPath: mountPath).isEmpty else { throw NTFSAccessPolicy.failure("Mount directory is occupied") }
    guard fchown(directory, uid, directoryInfo.st_gid) == 0 else { throw NTFSAccessPolicy.failure("Mount directory access refused") }
    defer { if fchown(directory, directoryInfo.st_uid, directoryInfo.st_gid) != 0 { exit(2) } }
    // Retain descriptors so restoration cannot target reused device/path names.
    guard fchown(fd, uid, original.st_gid) == 0 else { throw NTFSAccessPolicy.failure("Device authorization failed") }
    defer {
        if fchown(fd, original.st_uid, original.st_gid) != 0 { fputs("RESTORE_FAILED\n", stderr); exit(2) }
    }
    print("READY"); fflush(stdout)
    var input = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
    _ = poll(&input, 1, 60_000)
    // Any input, EOF, crash of the parent, or the deadline restores access.
}

final class Session: NSObject, NTFSAccessProtocol {
    static let queue = DispatchQueue(label: "NTFSAccess.serial")
    static var busy = false
    let uid: uid_t
    var process: Process?, input: Pipe?, token: String?
    init(uid: uid_t) { self.uid = uid }
    func begin(device: String, uuid: String, reply: @escaping (String?, NSError?) -> Void) {
        Self.queue.async {
            guard !Self.busy, self.process == nil else { reply(nil, NTFSAccessPolicy.failure("NTFS access busy")); return }
            do {
                var consoleUID: uid_t = 0
                _ = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil)
                guard consoleUID == self.uid, self.uid >= 501 else { throw NTFSAccessPolicy.failure("Active login required") }
                Self.busy = true
                let p = Process(), input = Pipe(), output = Pipe()
                p.executableURL = try NTFSAccessPolicy.executableURL()
                p.arguments = ["--lease", device, uuid, String(self.uid)]
                p.standardInput = input; p.standardOutput = output; p.standardError = FileHandle.nullDevice
                try p.run()
                // Worker performs bounded disk-info checks before READY.
                var line = Data()
                while line.count < 64, let b = try output.fileHandleForReading.read(upToCount: 1), !b.isEmpty {
                    line.append(b); if b[0] == 10 { break }
                }
                guard String(data: line, encoding: .utf8) == "READY\n" else {
                    try? input.fileHandleForWriting.close(); p.waitUntilExit()
                    throw NTFSAccessPolicy.failure("External NTFS access refused")
                }
                let token = UUID().uuidString
                self.process = p; self.input = input; self.token = token
                reply(token, nil)
                Self.queue.asyncAfter(deadline: .now() + 61) { if self.token == token { self.close() } }
            } catch { Self.busy = false; reply(nil, error as NSError) }
        }
    }
    func end(token: String, reply: @escaping (NSError?) -> Void) {
        Self.queue.async {
            guard token == self.token else { reply(NTFSAccessPolicy.failure("Invalid access token")); return }
            reply(self.close())
        }
    }
    @discardableResult func close() -> NSError? {
        try? input?.fileHandleForWriting.close()
        process?.waitUntilExit()
        let failed = process?.terminationStatus != 0
        process = nil; input = nil; token = nil; Self.busy = false
        return failed ? NTFSAccessPolicy.failure("Device permission restoration failed") : nil
    }
    func disconnect() { Self.queue.async { if self.process != nil { self.close() } } }
}
final class Listener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier >= 501,
              let requirement = try? NTFSAccessPolicy.signingRequirement(identifier: NTFSAccessPolicy.host) else { return false }
        connection.setCodeSigningRequirement(requirement)
        let session = Session(uid: connection.effectiveUserIdentifier)
        connection.exportedInterface = NSXPCInterface(with: NTFSAccessProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { session.disconnect() }
        connection.interruptionHandler = { session.disconnect() }
        connection.resume(); return true
    }
}
guard geteuid() == 0 else { exit(1) }
if CommandLine.arguments.dropFirst().first == "--lease" {
    do { try worker(); exit(0) } catch { fputs("External NTFS access refused\n", stderr); exit(1) }
}
guard CommandLine.arguments.count == 1 else { exit(1) }
let delegate = Listener(), listener = NSXPCListener(machServiceName: NTFSAccessPolicy.service)
listener.delegate = delegate; listener.resume(); RunLoop.current.run()
