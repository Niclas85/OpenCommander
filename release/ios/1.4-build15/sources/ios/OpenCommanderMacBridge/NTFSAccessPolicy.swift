import Foundation
import Security
import Darwin

/// Shared by the unprivileged app and the narrowly scoped root service.
enum NTFSAccessPolicy {
    static let service = "com.github.niklaus85.OpenCommander.NTFSAccess"
    static let host = "com.github.niklaus85.OpenCommander"
    static func isMounted(_ info: [String: Any]) -> Bool {
        guard let path = info["MountPoint"] as? String else { return false }
        return !path.isEmpty
    }
    static func executableURL() throws -> URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var path = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&path, &size) == 0 else { throw failure("Executable path unavailable") }
        return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
    }
    static func validDevice(_ value: String) -> Bool {
        value.range(of: #"\Adisk[0-9]+s[0-9]+\z"#, options: .regularExpression) != nil && value.count < 40
    }
    static func eligible(_ info: [String: Any], device: String, uuid: String) -> Bool {
        guard validDevice(device), UUID(uuidString: uuid) != nil,
              info["DeviceIdentifier"] as? String == device,
              info["DiskUUID"] as? String == uuid,
              info["Internal"] as? Bool == false,
              info["WholeDisk"] as? Bool == false,
              info["WritableMedia"] as? Bool == true,
              info["BusProtocol"] as? String == "USB",
              info["Content"] as? String == "Microsoft Basic Data",
              let size = info["IOKitSize"] as? UInt64, size >= 1024 * 1024 else { return false }
        return true
    }
    static func failure(_ reason: String) -> NSError {
        NSError(domain: service, code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 15) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        let dataLock = NSLock(); var output = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            dataLock.lock(); if output.count < 1024 * 1024 { output.append(bytes) }; dataLock.unlock()
        }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            pipe.fileHandleForReading.readabilityHandler = nil
            throw failure("NTFS operation timed out")
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let tail = pipe.fileHandleForReading.readDataToEndOfFile()
        dataLock.lock(); output.append(tail); let result = output; dataLock.unlock()
        guard process.terminationStatus == 0 else { throw failure("NTFS operation refused (\(process.terminationStatus))") }
        return result
    }
    static func info(_ device: String) throws -> [String: Any] {
        guard validDevice(device) else { throw failure("Invalid partition") }
        let data = try run("/usr/sbin/diskutil", ["info", "-plist", "/dev/" + device])
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw failure("Invalid disk information") }
        return info
    }
    static func signingRequirement(identifier: String) throws -> String {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else { throw failure("Missing signed team identity") }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}

@objc protocol NTFSAccessProtocol {
    func begin(device: String, uuid: String, reply: @escaping (String?, NSError?) -> Void)
    func end(token: String, reply: @escaping (NSError?) -> Void)
}
