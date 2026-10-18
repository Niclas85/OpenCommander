#if targetEnvironment(macCatalyst) || os(macOS)
import Foundation
import CryptoKit

/// Cloud transport reuses the existing pane, read-back verification, recursive
/// tools and transfer mechanics rather than opening a second cloud-only window.
@MainActor final class CloudFileClient: CommanderOnlineClient {
    let profile: CloudConnection
    var clientID: String { "cloud:" + profile.id }
    private var retainedMove: String?
    var moveBackupLocation: String? { retainedMove ?? core.moveBackupLocation }
    var transferProgress: ((String, Int64, Int64) -> Void)? {
        get { core.transferProgress }
        set { core.transferProgress = newValue }
    }
    typealias Transport = (String, Data, String, String, String?, URL?, @escaping (Data?, NSError?) -> Void) -> Void
    private let transport: Transport
    private let cancelTransport: (String) -> Void
    private let reads = SharedDirectoryReads<OnlineBrowserListing>()
    private struct Cached { var at: Date; var items: [OneDriveItem] }
    private var cached: [String: Cached] = [:]
    private var cooldowns: [String: (Date, NSError)] = [:]
    private var listingRevision = 0
    private var ambiguousDirectories = Set<String>()
    private let clock: () -> Date
    private let wait: (TimeInterval) async throws -> Void
    private let configurationIdentity: () async throws -> String
    private var boundConfiguration: String?
    private final class WeakClient { weak var value: CloudFileClient?; init(_ value: CloudFileClient) { self.value = value } }
    private static var browsers: [String: WeakClient] = [:]
    static func browserClient(_ profile: CloudConnection) -> CloudFileClient {
        if let client = browsers[profile.id]?.value, client.profile == profile { return client }
        browsers = browsers.filter { $0.value.value != nil }
        let client = CloudFileClient(profile); browsers[profile.id] = WeakClient(client); return client
    }
    private lazy var core: RemoteFileClient = {
        let reference = RemoteConnection(id: profile.id, name: profile.name, scheme: "ftp", host: "cloud.invalid", port: 21, user: "cloud", root: "/", keyPath: "")
        return RemoteFileClient(reference, transport: { [weak self] id, _, _, operation, path, destination, local, completion in
            guard let self else { completion(nil, CloudConnection.failure("cloud_backend_unavailable")); return }
            do {
                let opcode = ["list": "list", "download": "download", "export": "export", "upload": "upload", "mkdir": "mkdir", "rename": "rename", "delete": "deletefile", "rmdir": "rmdir"][operation]
                guard let opcode else { throw CloudConnection.failure("cloud_invalid") }
                let relative = try Self.relative(path), target = try destination.map(Self.relative)
                let connection = try JSONEncoder().encode(self.profile)
                let writing = !["list", "download", "export"].contains(operation)
                if writing { self.invalidate() }
                self.transport(id, connection, opcode, relative, target, local) { [weak self] data, error in
                    Task { @MainActor in
                        if writing { self?.invalidate() }
                        if let error { completion(nil, error); return }
                        do {
                            if operation == "list" {
                                guard let data, data.count <= 32 * 1024 * 1024 else { throw CloudConnection.failure("cloud_limit") }
                                let items = try JSONDecoder().decode([RcloneListingItem].self, from: data)
                                guard items.count <= 100_000 else { throw CloudConnection.failure("cloud_invalid_listing") }
                                let groups = Dictionary(grouping: items, by: { OneDriveConflictNames.key($0.Name) })
                                let ambiguous = Set(groups.filter { $0.value.count > 1 }.keys)
                                if ambiguous.isEmpty { self?.ambiguousDirectories.remove(relative) }
                                else { self?.ambiguousDirectories.insert(relative) }
                                let entries = try items.map { item -> RemoteDirectoryItem in
                                    try item.validate()
                                    guard item.Path == item.Name else { throw CloudConnection.failure("cloud_invalid_listing") }
                                    let facts = [item.Name, String(item.IsDir), String(item.Size), item.ModTime ?? "", item.ID ?? ""] + (item.Hashes ?? [:]).sorted { $0.key < $1.key }.map { $0.key + ":" + $0.value }
                                    let canonical = try JSONEncoder().encode(facts)
                                    let fingerprint = Data(SHA256.hash(data: canonical)).base64EncodedString()
                                    // Native Google documents have unknown export sizes.
                                    // Preserve that state: it is not an empty file and
                                    // must not invalidate the rest of the directory.
                                    let collision = ambiguous.contains(OneDriveConflictNames.key(item.Name))
                                    return RemoteDirectoryItem(name: item.Name, directory: item.IsDir, size: item.Size, modified: item.ModTime ?? "", unsafe: collision, fingerprint: fingerprint, nameCollision: collision, providerID: item.ID)
                                }
                                completion(try JSONEncoder().encode(entries), nil)
                            } else { completion(data ?? Data(), nil) }
                        } catch { completion(nil, error as NSError) }
                    }
                }
            } catch { completion(nil, error as NSError) }
        }, cancel: cancelTransport, password: { nil }, validName: CloudConnection.validName,
            validPath: { (try? Self.relative($0)) != nil }, describePath: { [profile] in profile.name + ":" + $0 },
            allowsNativeExport: profile.kind == "drive")
    }()
    init(_ profile: CloudConnection, transport: Transport? = nil, cancel: ((String) -> Void)? = nil,
         clock: @escaping () -> Date = Date.init,
         wait: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         configurationIdentity: (() async throws -> String)? = nil) {
        self.profile = profile; self.clock = clock; self.wait = wait
        if let configurationIdentity { self.configurationIdentity = configurationIdentity }
        else if transport != nil {
            // Dependency-injected test transports never read a real config.
            self.configurationIdentity = { "injected:" + profile.id }
        } else {
#if targetEnvironment(macCatalyst)
            self.configurationIdentity = {
                guard let bridge = DesktopBridge.shared else { throw CloudConnection.failure("cloud_backend_unavailable") }
                let data = try JSONEncoder().encode(profile)
                return try await withCheckedThrowingContinuation { continuation in
                    bridge.cloudIdentity(data) { identity, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let identity { continuation.resume(returning: identity) }
                        else { continuation.resume(throwing: CloudConnection.failure("cloud_config_changed")) }
                    }
                }
            }
#else
            self.configurationIdentity = { try await Task.detached { try CloudConfigurationValidator.identity(profile) }.value }
#endif
        }
#if targetEnvironment(macCatalyst)
        self.transport = transport ?? { id, connection, operation, path, destination, local, completion in
            guard let bridge = DesktopBridge.shared else { completion(nil, CloudConnection.failure("cloud_backend_unavailable")); return }
            bridge.cloudOperation(id, connection: connection, operation: operation, path: path, destination: destination, localURL: local, completion: completion)
        }
        cancelTransport = cancel ?? { DesktopBridge.shared?.cancelCloudOperation($0) }
#else
        self.transport = transport ?? { _, _, _, _, _, _, completion in completion(nil, CloudConnection.failure("cloud_backend_unavailable")) }
        cancelTransport = cancel ?? { _ in }
#endif
    }
    private static func relative(_ path: String) throws -> String {
        guard path.hasPrefix("/") else { throw CloudConnection.failure("cloud_invalid") }
        let relative = String(path.dropFirst())
        guard CloudConnection.validRelative(relative) else { throw CloudConnection.failure("cloud_invalid") }
        return relative
    }
    private func invalidate() {
        listingRevision += 1; cached.removeAll(); cooldowns.removeAll()
        reads.invalidate()
        NotificationCenter.default.post(name: OneDriveClient.listingChanged, object: clientID)
    }
    func validFileName(_ name: String) -> Bool { CloudConnection.validName(name) }
    func accountIdentity() async throws -> String {
        clientID + ":" + (try await configurationIdentity())
    }
    func persistentPath(_ id: String?) throws -> String? { try core.persistentPath(id) }
    var supportsSharingLink: Bool { ["drive", "onedrive", "dropbox"].contains(profile.kind) }
    /// Call only after explicit public-link confirmation in the browser UI.
    /// No retries or automatic clipboard/browser handoff after publication.
    func createPublicShareLink(_ item: OneDriveItem) async throws -> URL {
        let account = try await accountIdentity()
        guard supportsSharingLink, try await core.metadata(item.id).eTag == item.eTag,
              let path = try core.persistentPath(item.id) else { throw CloudConnection.failure("cloud_changed") }
        guard try await accountIdentity() == account else { throw CloudConnection.failure("cloud_config_changed") }
        let relativePath = try Self.relative(path)
        let id = UUID().uuidString, connection = try JSONEncoder().encode(profile), cancellation = cancelTransport
        let data: Data = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                transport(id, connection, "link", relativePath, nil, nil) { data, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: data ?? Data()) }
                }
            }
        }, onCancel: { cancellation(id) })
        return try Self.sharingURL(data, kind: profile.kind)
    }
    static func sharingURL(_ data: Data, kind: String) throws -> URL {
        guard data.count <= 8192, let text = String(data: data, encoding: .utf8),
              let value = text.split(whereSeparator: \.isNewline).last,
              let url = URL(string: String(value).trimmingCharacters(in: .whitespaces)),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { throw CloudConnection.failure("cloud_request_failed") }
        let allowed: Bool
        switch kind {
        case "drive": allowed = ["drive.google.com", "docs.google.com"].contains(host)
        case "dropbox": allowed = ["dropbox.com", "www.dropbox.com"].contains(host)
        case "onedrive": allowed = ["1drv.ms", "onedrive.live.com"].contains(host) || host.hasSuffix(".sharepoint.com")
        default: allowed = false
        }
        guard allowed else { throw CloudConnection.failure("cloud_request_failed") }
        return url
    }
    func restoreReference(_ id: String?, path: String?) async throws -> OneDriveItem { try await core.restoreReference(id, path: path) }
    func children(of id: String?) async throws -> [OneDriveItem] { try await core.children(of: id) }
    func browserListing(of id: String?) async throws -> OnlineBrowserListing {
        let key = id ?? "root"
        try Task.checkCancellation()
        do {
            let identity = try await configurationIdentity()
            try Task.checkCancellation()
            if let boundConfiguration, boundConfiguration != identity { invalidate() }
            boundConfiguration = identity
        } catch {
            invalidate(); throw error
        }
        if let (until, error) = cooldowns[key], until > clock() { return try fallback(key, error: error) }
        return try await reads.value(for: key) { [weak self] in
            guard let self else { throw CancellationError() }; return try await self.displayRead(id, key: key)
        }
    }
    private func fallback(_ key: String, error: NSError) throws -> OnlineBrowserListing {
        guard let stored = cached[key], clock().timeIntervalSince(stored.at) < 300 else { throw error }
        return OnlineBrowserListing(items: stored.items, cachedAt: stored.at, warning: nil,
            warningKey: error.localizedDescription, retryAfter: max(10, cooldowns[key]?.0.timeIntervalSince(clock()) ?? 10))
    }
    private func displayRead(_ id: String?, key: String) async throws -> OnlineBrowserListing {
        let revision = listingRevision, deadline = clock().addingTimeInterval(30)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let items = try await timedRead(id, deadline: deadline)
                try Task.checkCancellation()
                try await checkConfiguration()
                guard listingRevision == revision else { throw CancellationError() }
                cached[key] = Cached(at: clock(), items: items); cooldowns.removeValue(forKey: key)
                while cached.count > 32, let oldest = cached.min(by: { $0.value.at < $1.value.at })?.key { cached.removeValue(forKey: oldest) }
                let relative = try Self.relative(core.persistentPath(id) ?? "/")
                return OnlineBrowserListing(items: items, cachedAt: nil, warning: nil,
                    warningKey: ambiguousDirectories.contains(relative) ? "cloud_ambiguous_names_hidden" : nil)
            } catch {
                try Task.checkCancellation()
                guard listingRevision == revision else { throw CancellationError() }
                try await checkConfiguration()
                guard let delay = CloudProviderErrors.cooldown(error) else {
                    cached.removeValue(forKey: key); cooldowns.removeValue(forKey: key); throw error
                }
                let value = error as NSError
                let retryWait = pow(2.0, Double(attempt + 1))
                if delay > 10 || cached[key] != nil || attempt == 2 || deadline.timeIntervalSince(clock()) <= retryWait {
                    cooldowns[key] = (clock().addingTimeInterval(delay), value)
                    return try fallback(key, error: value)
                }
                try await wait(retryWait)
            }
        }
        throw CloudProviderErrors.temporary("cloud_timeout")
    }
    private func checkConfiguration() async throws {
        let identity: String
        do { identity = try await configurationIdentity() }
        catch { cached.removeAll(); cooldowns.removeAll(); throw error }
        guard identity == boundConfiguration else {
            cached.removeAll(); cooldowns.removeAll(); listingRevision += 1
            boundConfiguration = identity
            throw CloudConnection.failure("cloud_config_changed")
        }
    }
    private func timedRead(_ id: String?, deadline: Date) async throws -> [OneDriveItem] {
        let remaining = deadline.timeIntervalSince(clock())
        guard remaining > 0 else { throw CloudProviderErrors.temporary("cloud_timeout") }
        let request = Task { try await core.children(of: id) }
        var expired = false
        let watchdog = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(min(30, remaining) * 1_000_000_000)) } catch { return }
            expired = true; request.cancel()
        }
        defer { watchdog.cancel() }
        do {
            return try await withTaskCancellationHandler(operation: { try await request.value }, onCancel: { request.cancel() })
        } catch {
            if expired { throw CloudProviderErrors.temporary("cloud_timeout") }
            throw error
        }
    }
    func toolChildren(of id: String?) async throws -> [OneDriveItem] { try await core.toolChildren(of: id) }
    func metadata(_ id: String?) async throws -> OneDriveItem { try await core.metadata(id) }
    func createFolder(_ name: String, parent: String?) async throws { try await core.createFolder(name, parent: parent) }
    func validateDestination(_ parent: String?, excluding itemID: String) async throws { try await core.validateDestination(parent, excluding: itemID) }
    func rename(_ item: OneDriveItem, to name: String) async throws {
        let parent = try await core.metadata(item.id).parentReference?.id
        try await move(item, parent: parent, name: name)
    }
    func move(_ item: OneDriveItem, parent: String?, name: String?) async throws {
        retainedMove = nil
        try await core.validateDestination(parent, excluding: item.id)
        guard item.eTag != nil, try await core.metadata(item.id).eTag == item.eTag else { throw CloudConnection.failure("cloud_changed") }
        let original = try Self.relative(core.logicalPath(item.id))
        let oldParent = try await core.metadata(item.id).parentReference?.id
        let base = (original as NSString).deletingLastPathComponent
        let backupName = ".OpenCommander-Recovery-" + UUID().uuidString
        let backupPath = [base, backupName].filter { !$0.isEmpty }.joined(separator: "/")
        let snapshot = try await core.remoteSnapshot(item)
        let id = UUID().uuidString, data = try JSONEncoder().encode(profile), cancellation = cancelTransport
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                transport(id, data, "copy", original, backupPath, nil) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }, onCancel: { cancellation(id) })
        retainedMove = profile.name + ":/" + backupPath
        guard let backup = try await core.children(of: oldParent).first(where: { $0.name == backupName }),
              try await core.remoteSnapshot(backup) == snapshot else { throw CloudConnection.failure("cloud_changed") }
        try await core.move(item, parent: parent, name: name)
        guard try await core.remoteSnapshot(core.metadata(item.id)) == snapshot else { throw CloudConnection.failure("cloud_changed") }
        invalidate()
    }
    func recycle(_ item: OneDriveItem) async throws {
        retainedMove = nil
        // A cloud backend may implement move as copy-and-delete. Verify the
        // recoverable original, including every descendant, before and after
        // relocating it. Unsupported native exports fail before any mutation.
        let snapshot = try await core.remoteSnapshot(item)
        do {
            try await core.recycleUnchanged(item, snapshot: snapshot)
            retainedMove = core.moveBackupLocation
        } catch { retainedMove = core.moveBackupLocation; throw error }
    }
    func upload(_ url: URL, parent: String?) async throws { try await core.upload(url, parent: parent) }
    func uploadTree(_ url: URL, parent: String?) async throws { try await core.uploadTree(url, parent: parent) }
    func download(_ item: OneDriveItem) async throws -> URL { try await core.download(item) }
    func downloadTree(_ item: OneDriveItem) async throws -> URL { try await core.downloadTree(item) }
    func remoteSnapshot(_ item: OneDriveItem) async throws -> [String: String] { try await core.remoteSnapshot(item) }
    func recycleUnchanged(_ item: OneDriveItem, snapshot: [String: String]) async throws { try await core.recycleUnchanged(item, snapshot: snapshot) }
    func hasSavedLogin() throws -> Bool { try profile.validate(); return true }
    func beginLogin() async throws -> OneDriveDeviceCode { throw CloudConnection.failure("cloud_setup_required") }
    func completeLogin(_ code: OneDriveDeviceCode) async throws { throw CloudConnection.failure("cloud_setup_required") }
    func disconnect() throws { invalidate() }
}
#endif
