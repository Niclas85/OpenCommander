import Foundation
import Security
import OSLog
import Darwin

/// Refresh the installed bundle after an update. macOS 15 can retain an obsolete
/// ExtensionKit record while the File System Extensions switch still reads ON.
/// Registration does not grant approval, mount media, or restart a service.
enum NTFSExtensionRegistration {
    struct Plan {
        let host: URL
        let module: URL
        let fingerprint: String
    }
    static let preferenceKey = "ntfs_registered_installed_build_v1"
    static let registrationTool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let queue = DispatchQueue(label: "OpenCommander.NTFSRegistration", qos: .utility)
    private static let logger = Logger(subsystem: "com.github.niklaus85.OpenCommander.NTFS", category: "Registration")

    static func start() {
        let host = Bundle.main.bundleURL
        queue.async {
            do {
                guard let plan = try plan(for: host) else { return }
                if try refresh(plan, defaults: .standard, run: run) {
                    logger.notice("Installed NTFS extension registration refreshed; activation and mounting remain separate.")
                }
            } catch {
                logger.error("Installed NTFS extension registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func plan(for host: URL) throws -> Plan? {
        let host = host.standardizedFileURL
        let directories = [URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        guard directories.contains(host.deletingLastPathComponent()),
              host.resolvingSymlinksInPath() == host,
              let bundle = Bundle(url: host),
              bundle.bundleIdentifier == "com.github.niklaus85.OpenCommander" else { return nil }
        let module = host.appendingPathComponent("Contents/Extensions/OpenCommanderNTFSModule.appex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: module.path) else { return nil }
        let hostIdentity = try signedIdentity(at: host)
        let moduleIdentity = try signedIdentity(at: module)
        guard let team = hostIdentity[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
              moduleIdentity[kSecCodeInfoTeamIdentifier as String] as? String == team,
              let identifier = moduleIdentity[kSecCodeInfoIdentifier as String] as? String,
              ["com.github.niklaus85.OpenCommander.NTFSModule", "com.github.niklaus85.OpenCommander.NTFSModuleV2"].contains(identifier),
              let hash = moduleIdentity[kSecCodeInfoUnique as String] as? Data,
              let entitlements = moduleIdentity[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              ["com.apple.security.app-sandbox", "com.apple.developer.fskit.fsmodule"].allSatisfy({ key in
                  guard let value = entitlements[key] as? NSNumber else { return false }
                  return CFGetTypeID(value) == CFBooleanGetTypeID() && value.boolValue
              }) else { throw failure("NTFS extension identity or entitlements do not match the installed app.") }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Plan(host: host, module: module, fingerprint: [host.path, version, identifier, hash.base64EncodedString()].joined(separator: "\n"))
    }

    static func refresh(_ plan: Plan, defaults: UserDefaults,
                        run: (String, [String]) throws -> Void) throws -> Bool {
        guard defaults.string(forKey: preferenceKey) != plan.fingerprint else { return false }
        try run(registrationTool, ["-f", plan.host.path])
        try run("/usr/bin/pluginkit", ["-a", plan.module.path])
        // Do not persist a failed attempt or infer user consent from registration.
        defaults.set(plan.fingerprint, forKey: preferenceKey)
        return true
    }

    private static func signedIdentity(at url: URL) throws -> [String: Any] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
            throw failure("Installed NTFS app or extension signature is invalid.")
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else { throw failure("Cannot inspect the installed NTFS signature.") }
        return information
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        try task.run()
        if finished.wait(timeout: .now() + 10) == .timedOut {
            task.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut, task.isRunning {
                // Only the child we launched, never an OS daemon.
                kill(task.processIdentifier, SIGKILL)
            }
            throw failure("NTFS extension registration timed out.")
        }
        guard task.terminationStatus == 0 else { throw failure("NTFS extension registration failed (\(task.terminationStatus)).") }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OpenCommander.NTFSRegistration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
