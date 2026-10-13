#if os(macOS)
import Foundation
import CryptoKit
import Darwin

/// A child uses a private snapshot, not the mutable user config. Only token
/// rotation from that child can advance the persistent account pin. External
/// config changes refuse before a mutation; no bearer/refresh token enters pins.
final class CloudConfigurationLease {
    private struct Pin: Codable {
        var version = 1
        let anchor: String
        var digest: String
        var pending: String?
    }
    private static let registryLock = NSLock()
    private static var locks: [String: NSLock] = [:]
    private let lock: NSLock
    private let original: CloudConnection
    private let source: Data
    private let sourceHash: String
    private let sections: [String: [String: String]]
    private let directory: URL
    private let pinURL: URL
    private var pin: Pin
    let profile: CloudConnection
    var identity: String { pin.anchor + ":" + Self.digest(Data(original.root.utf8)) }

    init(_ original: CloudConnection, root: URL? = nil, check: () throws -> Void = {}) throws {
        try original.validate()
        let key = Self.digest(Data((original.configPath + "\0" + original.remote + "\0" + original.kind).utf8))
        Self.registryLock.lock()
        let selectedLock = Self.locks[original.configPath] ?? NSLock(); Self.locks[original.configPath] = selectedLock
        Self.registryLock.unlock()
        while !selectedLock.try() { try check(); Thread.sleep(forTimeInterval: 0.05) }
        // Different remotes sharing a config must also serialize publication.
        var unlockOnFailure = true
        defer { if unlockOnFailure { selectedLock.unlock() } }
        try check()
        let source = try Self.read(original.configPath, limit: 1024 * 1024)
        try CloudConfigurationValidator.validate(source, profile: original)
        let sections = try Self.parse(source), selected = sections[original.remote] ?? [:]
        let accountHash = try Self.selectedDigest(selected)
        let root = root ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenCommander/CloudPins", isDirectory: true)
        try Self.privateDirectory(root)
        let pinURL = root.appendingPathComponent(key + ".json")
        var pin: Pin
        if FileManager.default.fileExists(atPath: pinURL.path) {
            pin = try JSONDecoder().decode(Pin.self, from: Self.read(pinURL.path, limit: 4096))
            guard pin.version == 1, UUID(uuidString: pin.anchor) != nil, pin.digest.count == 64,
                pin.pending.map({ $0.count == 64 }) != false else { throw CloudConnection.failure("cloud_config_changed") }
            if let pending = pin.pending {
                // Interrupted own rotation: both proven generations retain the
                // same account anchor. Any third generation is refused.
                guard accountHash == pending || accountHash == pin.digest else { throw CloudConnection.failure("cloud_config_changed") }
                pin.digest = accountHash; pin.pending = nil
                try Self.atomic(try JSONEncoder().encode(pin), at: pinURL)
            }
            guard pin.digest == accountHash else { throw CloudConnection.failure("cloud_config_changed") }
        } else {
            pin = Pin(anchor: UUID().uuidString, digest: accountHash)
            try Self.atomic(try JSONEncoder().encode(pin), at: pinURL)
        }
        let directory = root.appendingPathComponent("lease-" + UUID().uuidString, isDirectory: true)
        try Self.privateDirectory(directory)
        var profile = original; profile.configPath = directory.appendingPathComponent("rclone.conf").path
        do { try Self.atomic(source, at: URL(fileURLWithPath: profile.configPath)) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
        self.lock = selectedLock; self.original = original; self.source = source; self.sourceHash = Self.digest(source)
        self.sections = sections; self.pinURL = pinURL; self.pin = pin; self.directory = directory; self.profile = profile
        unlockOnFailure = false
    }
    deinit { try? FileManager.default.removeItem(at: directory); lock.unlock() }
    func checkSource() throws {
        guard Self.digest(try Self.read(original.configPath, limit: 1024 * 1024)) == sourceHash else {
            throw CloudConnection.failure("cloud_config_changed")
        }
    }
    /// Refresh is never an unconditional replacement of the user's config.
    /// The two-generation pin closes the crash window across its two files.
    func commit(checkpoint: (String) throws -> Void = { _ in }) throws {
        try checkSource()
        let updated = try Self.read(profile.configPath, limit: 1024 * 1024)
        try CloudConfigurationValidator.validate(updated, profile: original)
        var before = sections, after = try Self.parse(updated)
        let mutable: Set<String> = original.kind == "iclouddrive" ? ["cookies", "trust_token"] : ["token"]
        for key in mutable { before[original.remote]?.removeValue(forKey: key); after[original.remote]?.removeValue(forKey: key) }
        guard before == after else { throw CloudConnection.failure("cloud_config_changed") }
        let digest = try Self.selectedDigest(Self.parse(updated)[original.remote] ?? [:])
        if digest == pin.digest { return } // Ignore harmless formatting changes.
        pin.pending = digest
        try Self.atomic(try JSONEncoder().encode(pin), at: pinURL)
        try checkpoint("pending")
        try checkSource()
        try Self.atomic(updated, at: URL(fileURLWithPath: original.configPath))
        try checkpoint("published")
        pin.digest = digest; pin.pending = nil
        try Self.atomic(try JSONEncoder().encode(pin), at: pinURL)
    }
    private static func selectedDigest(_ section: [String: String]) throws -> String {
        digest(try JSONSerialization.data(withJSONObject: section, options: [.sortedKeys]))
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func privateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
            url.resolvingSymlinksInPath().path == url.path else { throw CloudConnection.failure("cloud_config_private") }
    }
    private static func read(_ path: String, limit: Int) throws -> Data {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw CloudConnection.failure("cloud_config_private") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var initial = stat(), final = stat()
        guard fstat(fd, &initial) == 0, initial.st_mode & S_IFMT == S_IFREG, initial.st_uid == geteuid(),
            initial.st_mode & 0o077 == 0, initial.st_nlink == 1, initial.st_size > 0, initial.st_size <= limit else { throw CloudConnection.failure("cloud_config_private") }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count == initial.st_size, fstat(fd, &final) == 0,
            initial.st_ino == final.st_ino, initial.st_dev == final.st_dev, initial.st_size == final.st_size,
            initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec, initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec,
            initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec, initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec else { throw CloudConnection.failure("cloud_config_changed") }
        return data
    }
    private static func parse(_ data: Data) throws -> [String: [String: String]] {
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw CloudConnection.failure("cloud_config_unreadable") }
        var result: [String: [String: String]] = [:], current: String?
        for raw in text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")).split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, result[name] == nil, result.count < 1000 else { throw CloudConnection.failure("cloud_config_unreadable") }
                result[name] = [:]; current = name
            } else {
                guard let current, let split = line.firstIndex(of: "=") else { throw CloudConnection.failure("cloud_config_unreadable") }
                let key = String(line[..<split]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, result[current]?[key] == nil else { throw CloudConnection.failure("cloud_config_unreadable") }
                result[current]?[key] = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }
    private static func atomic(_ data: Data, at target: URL) throws {
        let parent = target.deletingLastPathComponent()
        guard parent.resolvingSymlinksInPath().path == parent.path else { throw CloudConnection.failure("cloud_config_private") }
        let temporary = parent.appendingPathComponent(".pin-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CloudConnection.failure("cloud_config_private") }
        defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw CloudConnection.failure("cloud_config_private") }; offset += count
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, target.path) == 0 else { throw CloudConnection.failure("cloud_config_private") }
        let directory = open(parent.path, O_RDONLY | O_NOFOLLOW); guard directory >= 0 else { throw CloudConnection.failure("cloud_config_private") }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw CloudConnection.failure("cloud_config_private") }
    }
}
#endif
