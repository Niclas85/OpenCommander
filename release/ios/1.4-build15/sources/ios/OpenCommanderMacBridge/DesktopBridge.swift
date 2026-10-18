import AppKit
import UniformTypeIdentifiers
import Darwin

/// AppKit file promises let Finder choose the destination before any network
/// work starts. Unlike Catalyst's lazy file URLs, this never blocks pasteboard
/// resolution waiting for the main actor.
private final class OnlineFilePromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let token: String
    let name: String
    let writer: (String, URL, @escaping (NSError?) -> Void) -> Void
    init(token: String, name: String, type: String,
         writer: @escaping (String, URL, @escaping (NSError?) -> Void) -> Void) {
        self.token = token; self.name = name; self.writer = writer
        super.init()
        fileType = type; delegate = self
    }
    required init?(coder: NSCoder) { fatalError("Not archived") }
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [NSPasteboard.PasteboardType(token)]
    }
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type.rawValue == token ? Data() : super.pasteboardPropertyList(forType: type)
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { name }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        NSLog("OpenCommander native promise write requested")
        DispatchQueue.main.async { [self] in
            writer(token, url) { [self] error in
                withExtendedLifetime(self) { completionHandler(error) }
            }
        }
    }
}

private final class OnlineFilePromiseSource: NSObject, NSDraggingSource {
    typealias Writer = (String, URL, @escaping (NSError?) -> Void) -> Void
    private var sources: [String: ((CGPoint) -> [[String: String]], Writer)] = [:]
    private var monitor: Any?
    private var down: NSEvent?
    private var prepared: [OnlineFilePromise] = []
    private var active: [OnlineFilePromise] = []
    func register(_ id: String, items: @escaping (CGPoint) -> [[String: String]], write: @escaping Writer) {
        sources[id] = (items, write)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }; return self.handle(event)
        }
    }
    func remove(_ id: String) { sources.removeValue(forKey: id) }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseDown {
            down = event; prepared = []
            guard let view = event.window?.contentView else { return event }
            let location = view.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: location.x / view.bounds.width, y: (view.isFlipped ? location.y : view.bounds.height - location.y) / view.bounds.height)
            // Snapshot before UIKit changes selection for the pressed row.
            for (items, writer) in sources.values {
                let entries = items(point)
                guard !entries.isEmpty else { continue }
                prepared = entries.compactMap { entry in
                    guard let token = entry["token"], let name = entry["name"], let type = entry["type"] else { return nil }
                    return OnlineFilePromise(token: token, name: name, type: type, writer: writer)
                }
                break
            }
            return event
        }
        if event.type == .leftMouseUp { down = nil; prepared = []; return event }
        guard let start = down, start.window === event.window,
              hypot(event.locationInWindow.x - start.locationInWindow.x,
                    event.locationInWindow.y - start.locationInWindow.y) > 5,
              let view = event.window?.contentView else { return event }
        down = nil
        let location = view.convert(start.locationInWindow, from: nil)
        if !prepared.isEmpty {
            active = prepared; prepared = []
            let draggingItems = active.map { promise -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: promise)
                let icon = NSWorkspace.shared.icon(for: UTType(promise.fileType) ?? .data)
                item.setDraggingFrame(NSRect(x: location.x, y: location.y, width: 32, height: 32), contents: icon)
                return item
            }
            guard !draggingItems.isEmpty else { return event }
            view.beginDraggingSession(with: draggingItems, event: event, source: self)
            return nil
        }
        return event
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.copy, .move] : .copy
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NSLog("OpenCommander native drag ended at %@ operation %lu", NSStringFromPoint(screenPoint), operation.rawValue)
        // Keep delegate-backed providers alive through Finder's asynchronous
        // write request. The writer's completion captures each provider too.
        let retained = active; active = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { withExtendedLifetime(retained) {} }
    }
}

private final class SSHPasswordBroker {
    let path: String
    private let descriptor: Int32
    private let directory: URL
    private let lock = NSLock()
    private var closed = false
    init(password: String) throws {
        guard password.utf8.count <= 8192, !password.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) else { throw RemoteConnection.failure("remote_invalid") }
        directory = URL(fileURLWithPath: "/tmp/oc-ask-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        path = directory.appendingPathComponent("password.sock").path
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { try? FileManager.default.removeItem(at: directory); throw RemoteConnection.failure("remote_unavailable") }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in destination.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor); try? FileManager.default.removeItem(at: directory); throw RemoteConnection.failure("remote_unavailable")
        }
        let server = descriptor
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { lock.lock(); closed = true; Darwin.close(server); lock.unlock() }
            var waiting = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
            guard poll(&waiting, 1, 30_000) > 0, waiting.revents & Int16(POLLIN) != 0 else { return }
            let client = accept(server, nil, nil); guard client >= 0 else { return }
            defer { Darwin.close(client) }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var secret = Array((password + "\n").utf8)
            defer { secret.withUnsafeMutableBytes { if let base = $0.baseAddress { _ = memset_s(base, $0.count, 0, $0.count) } } }
            secret.withUnsafeBytes { bytes in
                var written = 0
                while written < bytes.count {
                    let count = Darwin.write(client, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                    if count <= 0 { break }; written += count
                }
            }
        }
    }
    func stop() {
        lock.lock(); if !closed { shutdown(descriptor, SHUT_RDWR) }; lock.unlock()
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Native AppKit bundle loaded only by the Mac Catalyst host. Uses public
/// NSWorkspace APIs, the same Launch Services associations as Finder, no shell.
final class DesktopBridge: NSObject, DesktopBridgeProtocol {
    private let onlineDragSource = OnlineFilePromiseSource()
    func registerOnlineDragSource(_ identifier: String, items: @escaping (CGPoint) -> [[String: String]],
                                  write: @escaping (String, URL, @escaping (NSError?) -> Void) -> Void) {
        onlineDragSource.register(identifier, items: items, write: write)
    }
    func removeOnlineDragSource(_ identifier: String) { onlineDragSource.remove(identifier) }
    override init() {
        super.init()
        NTFSExtensionRegistration.start()
        NTFSAutoMount.shared.start()
    }
    func showNTFSWriteSettings() { NTFSAutoMount.shared.showSettings() }
    private var applicationPanel: NSOpenPanel?
    private var locationPanel: NSOpenPanel?
    private var archivePanel: NSSavePanel?
    private let remoteLock = NSLock()
    private var remoteTasks: [String: Process] = [:]
    private var cancelledRemote = Set<String>()
    private let cloudRunner = RcloneProcessRunner()
    func stableVolumeIdentity(_ url: URL) -> String? { VolumeIdentity.nativeToken(at: url) }
    func chooseCloudConfiguration(title: String, completion: @escaping (URL?) -> Void) {
        guard locationPanel == nil else { completion(nil); return }
        let panel = NSOpenPanel(); locationPanel = panel
        panel.title = title; panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] result in
            self?.locationPanel = nil; completion(result == .OK ? panel.url : nil)
        }
    }
    func cancelCloudOperation(_ requestID: String) { cloudRunner.cancel(requestID) }
    func cloudIdentity(_ connection: Data, completion: @escaping (String?, NSError?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                guard connection.count <= 64 * 1024 else { throw CloudConnection.failure("cloud_invalid") }
                let profile = try JSONDecoder().decode(CloudConnection.self, from: connection)
                let lease = try CloudConfigurationLease(profile)
                let identity = lease.identity
                DispatchQueue.main.async { completion(identity, nil) }
            } catch { DispatchQueue.main.async { completion(nil, error as NSError) } }
        }
    }
    func cloudSetup(_ requestID: String, connection: Data, state: String?, answer: String?, password: Bool, oauthClient: Data?,
                    browser: @escaping (URL) -> Void, completion: @escaping (Data?, NSError?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            defer { self.cloudRunner.finish(requestID) }
            do {
                guard UUID(uuidString: requestID) != nil, connection.count <= 64 * 1024,
                    (state?.utf8.count ?? 0) <= 8192, state?.contains("\0") != true,
                    (answer?.utf8.count ?? 0) <= 8192, answer?.contains("\0") != true,
                    (oauthClient?.count ?? 0) <= 16 * 1024, oauthClient == nil || state == nil else { throw CloudConnection.failure("cloud_invalid") }
                let profile = try JSONDecoder().decode(CloudConnection.self, from: connection)
                try profile.validate()
                let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenCommander/CloudSetup", isDirectory: true)
                let directory = root.appendingPathComponent(profile.id, isDirectory: true)
                let configuration = directory.appendingPathComponent("rclone.conf")
                guard profile.configPath == configuration.path, profile.remote == "oc_" + profile.id.replacingOccurrences(of: "-", with: "").lowercased() else {
                    throw CloudConnection.failure("cloud_invalid")
                }
                for path in [root, directory] {
                    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    var info = stat()
                    guard lstat(path.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
                        info.st_mode & 0o077 == 0, path.resolvingSymlinksInPath().path == path.path else { throw CloudConnection.failure("cloud_config_private") }
                }
                let descriptor = open(configuration.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { throw CloudConnection.failure("cloud_config_private") }
                var info = stat()
                let valid = fstat(descriptor, &info) == 0 && info.st_mode & S_IFMT == S_IFREG && info.st_uid == geteuid() && info.st_mode & 0o077 == 0 && info.st_size <= 1024 * 1024
                close(descriptor)
                guard valid else { throw CloudConnection.failure("cloud_config_private") }
                let binary = try RcloneRuntime(runner: self.cloudRunner).executable(id: requestID)
                var environment = ["RCLONE_CONFIG_" + profile.remote.uppercased() + "_CONFIG_AUTH_NO_BROWSER": "true"]
                var arguments = ["--config", configuration.path, "config"]
                let client = try oauthClient.map { try PublicCloudOAuth.decode($0, kind: profile.kind) }
                if let client, client.pkce {
                    guard info.st_size == 0 else { throw CloudConnection.failure("cloud_config_changed") }
                    let token = try NativeCloudOAuth.authorize(kind: profile.kind, client: client,
                        check: { try self.cloudRunner.check(requestID) }, browser: { url in DispatchQueue.main.async { browser(url) } })
                    try self.cloudRunner.check(requestID)
                    try NativeCloudOAuth.seed(profile: profile, client: client, token: token)
                } else if let client {
                    try NativeCloudOAuth.seedGoogle(profile: profile, client: client)
                }
                if let state, !state.isEmpty {
                    environment["RCLONE_STATE"] = state
                    var result = answer ?? ""
                    if password && state.hasPrefix("*all-set,") {
                        guard !result.contains(where: \.isNewline) else { throw CloudConnection.failure("cloud_invalid") }
                        let encoded = try self.cloudRunner.run(binary, ["obscure", "-"], id: requestID, timeout: 10,
                            maximumOutput: 16384, input: Data((result + "\n").utf8))
                        result = String(decoding: encoded, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard CloudConfigurationValidator.obscured(result) else { throw CloudConnection.failure("cloud_icloud_incomplete") }
                    }
                    environment["RCLONE_RESULT"] = result
                    arguments += ["update", profile.remote, "--continue", "--non-interactive"]
                } else {
                    if client != nil {
                        arguments += ["update", profile.remote, "--non-interactive"]
                    } else {
                        guard info.st_size == 0 else { throw CloudConnection.failure("cloud_config_changed") }
                        arguments += ["create", profile.remote, profile.kind, "--non-interactive"]
                    }
                    if profile.kind == "iclouddrive" { arguments.append("--all") }
                }
                let response = try self.cloudRunner.run(binary, arguments, id: requestID, timeout: 600,
                    maximumOutput: 256 * 1024, environment: environment, browser: { url in DispatchQueue.main.async { browser(url) } }, setupKind: profile.kind)
                let question = try CloudSetupQuestion.decode(response, kind: profile.kind)
                guard chmod(configuration.path, 0o600) == 0 else { throw CloudConnection.failure("cloud_config_private") }
                if question.complete { _ = try CloudConfigurationValidator.identity(profile) }
                DispatchQueue.main.async { completion(response, nil) }
            } catch { DispatchQueue.main.async { completion(nil, error as NSError) } }
        }
    }
    func cloudOperation(_ requestID: String, connection: Data, operation: String, path: String,
                        destination: String?, localURL: URL?, completion: @escaping (Data?, NSError?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            defer { self.cloudRunner.finish(requestID) }
            var lease: CloudConfigurationLease?
            do {
                guard UUID(uuidString: requestID) != nil, connection.count <= 64 * 1024 else { throw CloudConnection.failure("cloud_invalid") }
                var profile = try JSONDecoder().decode(CloudConnection.self, from: connection)
                if operation != "profiles" {
                    lease = try CloudConfigurationLease(profile, check: { try self.cloudRunner.check(requestID) })
                    profile = lease!.profile
                }
                var arguments = try RcloneCommandPlan.arguments(profile: profile, operation: operation, path: path, destination: destination, local: localURL)
                var info = stat()
                guard lstat(profile.configPath, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                    info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw CloudConnection.failure("cloud_config_private") }
                if operation != "profiles" {
                    let descriptor = open(profile.configPath, O_RDONLY | O_NOFOLLOW)
                    guard descriptor >= 0 else { throw CloudConnection.failure("cloud_config_private") }
                    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                    defer { try? file.close() }
                    var opened = stat()
                    guard fstat(descriptor, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG,
                        opened.st_uid == geteuid(), opened.st_mode & 0o077 == 0,
                        opened.st_size > 0, opened.st_size <= 1024 * 1024,
                        opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else { throw CloudConnection.failure("cloud_config_private") }
                    let configuration = try file.read(upToCount: 1024 * 1024 + 1) ?? Data()
                    try CloudConfigurationValidator.validate(configuration, profile: profile)
                }
                let binary = try RcloneRuntime(runner: self.cloudRunner).executable(id: requestID)
                let profiles = try self.cloudRunner.run(binary, try RcloneCommandPlan.arguments(profile: profile, operation: "profiles", path: ""), id: requestID)
                try lease?.checkSource()
                let available = try JSONDecoder().decode([RcloneRemoteInfo].self, from: profiles)
                guard available.count <= 1000 else { throw CloudConnection.failure("cloud_limit") }
                if operation == "profiles" {
                    let supported = available.filter { CloudConnection.kinds.contains($0.type) && $0.source == "file" }
                    let data = try JSONEncoder().encode(supported)
                    DispatchQueue.main.async { completion(data, nil) }; return
                }
                guard available.contains(where: { $0.name == profile.remote && $0.type == profile.kind && $0.source == "file" }) else { throw CloudConnection.failure("cloud_config_changed") }
                if ["copy", "rename"].contains(operation) {
                    let metadata = try self.cloudRunner.run(binary, RcloneCommandPlan.arguments(profile: profile, operation: "stat", path: path), id: requestID)
                    try lease?.checkSource()
                    let item = try JSONDecoder().decode(RcloneListingItem.self, from: metadata)
                    if item.IsDir { arguments = try RcloneCommandPlan.arguments(profile: profile, operation: operation + "tree", path: path, destination: destination) }
                }
                if ["download", "export"].contains(operation) {
                    guard let localURL, lstat(localURL.path, &info) != 0, errno == ENOENT,
                        localURL.deletingLastPathComponent().resolvingSymlinksInPath() == localURL.deletingLastPathComponent() else { throw CloudConnection.failure("cloud_invalid") }
                } else if operation == "upload" {
                    guard let localURL, lstat(localURL.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw CloudConnection.failure("cloud_invalid") }
                }
                try lease?.checkSource()
                let data = try self.cloudRunner.run(binary, arguments, id: requestID, timeout: ["download", "export", "upload", "copy", "rename"].contains(operation) ? 900 : 60)
                try lease?.commit()
                DispatchQueue.main.async { completion(data, nil) }
            } catch {
                var failure = error
                // A failed request may still have legitimately rotated its
                // refresh token. Preserve that rotation only with the same pin.
                do { try lease?.commit() } catch { failure = error }
                let result = failure as NSError
                DispatchQueue.main.async { completion(nil, result) }
            }
        }
    }
    var sshAskPassURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("OpenCommanderSSHAskPass")
    func remoteHostKeys(_ connection: Data, completion: @escaping (String?, NSError?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let profile = try JSONDecoder().decode(RemoteConnection.self, from: connection); try profile.validate()
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keyscan")
                process.arguments = ["-T", "5", "-p", String(profile.port), "-t", "ed25519,ecdsa,rsa", profile.host]
                process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                guard process.terminationStatus == 0, data.count < 64 * 1024, let keys = String(data: data, encoding: .utf8) else { throw RemoteConnection.failure("remote_ssh_failed") }
                _ = try RemoteConnection.fingerprints(keys)
                DispatchQueue.main.async { completion(keys, nil) }
            } catch { DispatchQueue.main.async { completion(nil, error as NSError) } }
        }
    }

    func cancelRemoteOperation(_ requestID: String) {
        remoteLock.lock(); cancelledRemote.insert(requestID)
        let task = remoteTasks[requestID]; remoteLock.unlock()
        if task?.isRunning == true { task?.terminate() }
    }

    func remoteOperation(_ requestID: String, connection: Data, password: String?, operation: String,
                         path: String, destination: String?, localURL: URL?, completion: @escaping (Data?, NSError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let profile = try JSONDecoder().decode(RemoteConnection.self, from: connection)
                try profile.validate()
                guard password?.contains("\0") != true else { throw RemoteConnection.failure("remote_invalid") }
                guard profile.contains(path), destination.map(profile.contains) != false,
                      ["list", "download", "upload", "mkdir", "rename", "delete", "rmdir"].contains(operation) else {
                    throw RemoteConnection.failure("remote_invalid")
                }
                let task = Process(), input = Pipe(), output = Pipe()
                task.standardInput = input; task.standardOutput = output
                task.standardError = FileHandle.nullDevice // never leak authentication or server responses
#if REMOTE_TRANSPORT_TESTS
                task.standardError = FileHandle.standardError
#endif
                var payload = ""
                var passwordBroker: SSHPasswordBroker?
                defer { passwordBroker?.stop() }
                if profile.scheme == "sftp" {
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
                    // No shell, no user ssh_config hooks, no implicit host-key acceptance.
                    // OpenSSH uses the first value: set BatchMode before -b adds its default.
                    task.arguments = ["-o", "BatchMode=\(profile.passwordAuthentication == true ? "no" : "yes")", "-F", "/dev/null", "-b", "-", "-P", String(profile.port),
                        "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15",
                        "-o", "IdentitiesOnly=\(profile.keyPath.isEmpty ? "no" : "yes")", "-o", "ForwardAgent=no"]
                    if !profile.keyPath.isEmpty { task.arguments! += ["-i", profile.keyPath] }
                    if profile.passwordAuthentication == true {
                        guard let password, !password.isEmpty, let helper = self.sshAskPassURL,
                              FileManager.default.isExecutableFile(atPath: helper.path) else { throw RemoteConnection.failure("remote_password_missing") }
                        passwordBroker = try SSHPasswordBroker(password: password)
                        task.arguments! += ["-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no", "-o", "NumberOfPasswordPrompts=1"]
                    }
                    if let keys = profile.trustedHostKeys {
                        _ = try RemoteConnection.fingerprints(keys)
                        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                            .appendingPathComponent("OpenCommander/SSH", isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        let knownHosts = directory.appendingPathComponent(profile.id + "-known_hosts")
                        try Data(keys.utf8).write(to: knownHosts, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHosts.path)
                        let quotedHosts = knownHosts.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                        task.arguments! += ["-o", "UserKnownHostsFile=\"\(quotedHosts)\"", "-o", "GlobalKnownHostsFile=/dev/null"]
                    }
                    let host = profile.host.contains(":") ? "[\(profile.host)]" : profile.host
                    task.arguments! += ["\(profile.user)@\(host)"]
                    func quote(_ value: String) -> String {
                        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
                            .replacingOccurrences(of: "*", with: "\\*")
                            .replacingOccurrences(of: "?", with: "\\?")
                            .replacingOccurrences(of: "[", with: "\\[") + "\""
                    }
                    switch operation {
                    case "list": payload = "ls -lan " + quote(path.hasSuffix("/") ? path : path + "/")
                    case "download", "upload":
                        guard let localURL, localURL.isFileURL, RemoteConnection.validPath(localURL.path) else { throw RemoteConnection.failure("remote_invalid") }
                        payload = operation == "download" ? "get \(quote(path)) \(quote(localURL.path))" : "put \(quote(localURL.path)) \(quote(path))"
                    case "mkdir": payload = "mkdir " + quote(path)
                    case "rename":
                        guard let destination else { throw RemoteConnection.failure("remote_invalid") }
                        payload = "rename \(quote(path)) \(quote(destination))"
                    case "delete": payload = "rm " + quote(path)
                    default: payload = "rmdir " + quote(path)
                    }
                    payload += "\n"
                } else {
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                    task.arguments = ["--disable", "--silent", "--show-error", "--fail", "--globoff",
                        "--connect-timeout", "15", "--max-time", "300", "--noproxy", "*", "--ftp-skip-pasv-ip", "--proto", "=ftp", "--config", "-"]
                    if profile.scheme == "ftps" { task.arguments! += ["--ssl-reqd", "--tlsv1.2"] }
                    if profile.scheme == "ftps", let ca = profile.tlsCAPath { task.arguments! += ["--cacert", ca] }
                    var components = URLComponents()
                    components.scheme = "ftp"; components.host = profile.host; components.port = profile.port
                    // Double slash selects an absolute server path instead of the FTP login home.
                    components.path = "/" + (operation == "list" ? (path.hasSuffix("/") ? path : path + "/") : path)
                    guard let address = components.url?.absoluteString else { throw RemoteConnection.failure("remote_invalid") }
                    func config(_ value: String) -> String {
                        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
                    }
                    payload = "user = " + config(profile.user + ":" + (password ?? "")) + "\n"
                    switch operation {
                    case "list": task.arguments! += ["--request", "MLSD"]
                    case "download", "upload":
                        guard let localURL, localURL.isFileURL else { throw RemoteConnection.failure("remote_invalid") }
                        task.arguments! += [operation == "download" ? "--output" : "--upload-file", localURL.path]
                    default:
                        task.arguments! += ["--head"]
                        let commands: [String]
                        switch operation {
                        case "mkdir": commands = ["MKD " + path]
                        case "rename":
                            guard let destination else { throw RemoteConnection.failure("remote_invalid") }
                            commands = ["RNFR " + path, "RNTO " + destination]
                        case "delete": commands = ["DELE " + path]
                        default: commands = ["RMD " + path]
                        }
                        for command in commands { task.arguments! += ["--quote", command] }
                        components.path = "/" + profile.root + "/"
                    }
                    task.arguments! += ["--url", ["list", "download", "upload"].contains(operation) ? address : components.url!.absoluteString]
                }
                var environment = ProcessInfo.processInfo.environment
                environment["LC_ALL"] = "en_US.UTF-8"; environment["LANG"] = "en_US.UTF-8"
                if let passwordBroker, let helper = self.sshAskPassURL {
                    environment["SSH_ASKPASS"] = helper.path; environment["SSH_ASKPASS_REQUIRE"] = "force"
                    environment["DISPLAY"] = "OpenCommander"
                    environment["OPENCOMMANDER_ASKPASS_SOCKET"] = passwordBroker.path
                } else {
                    environment.removeValue(forKey: "SSH_ASKPASS"); environment.removeValue(forKey: "SSH_ASKPASS_REQUIRE")
                    environment.removeValue(forKey: "OPENCOMMANDER_ASKPASS_SOCKET")
                }
                task.environment = environment
                self.remoteLock.lock()
                if self.cancelledRemote.contains(requestID) {
                    self.cancelledRemote.remove(requestID); self.remoteLock.unlock(); throw CancellationError()
                }
                self.remoteTasks[requestID] = task
                do { try task.run() } catch { self.remoteTasks.removeValue(forKey: requestID); self.remoteLock.unlock(); throw error }
                self.remoteLock.unlock()
                defer {
                    self.remoteLock.lock(); self.remoteTasks.removeValue(forKey: requestID)
                    self.cancelledRemote.remove(requestID); self.remoteLock.unlock()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 300) { if task.isRunning { task.terminate() } }
                try input.fileHandleForWriting.write(contentsOf: Data(payload.utf8)); try input.fileHandleForWriting.close()
                var data = Data()
                while let part = try output.fileHandleForReading.read(upToCount: 64 * 1024), !part.isEmpty {
                    data.append(part)
                    if data.count > 16 * 1024 * 1024 { task.terminate(); throw RemoteConnection.failure("remote_limit") }
                }
                task.waitUntilExit()
                self.remoteLock.lock(); let cancelled = self.cancelledRemote.contains(requestID); self.remoteLock.unlock()
                if cancelled { throw CancellationError() }
                guard task.terminationStatus == 0 else { throw RemoteConnection.failure(profile.scheme == "sftp" ? "remote_ssh_failed" : "remote_ftp_failed") }
                if operation == "list" {
                    guard let text = String(data: data, encoding: .utf8) else { throw RemoteConnection.failure("remote_listing") }
                    data = try JSONEncoder().encode(profile.scheme == "sftp" ? RemoteDirectoryItem.sftp(text) : RemoteDirectoryItem.mlsd(text))
                }
                DispatchQueue.main.async { completion(data, nil) }
            } catch { DispatchQueue.main.async { completion(nil, error as NSError) } }
        }
    }

    func chooseArchiveDestination(name: String, directory: URL, title: String, completion: @escaping (URL?) -> Void) {
        guard archivePanel == nil else { completion(nil); return }
        let panel = NSSavePanel()
        archivePanel = panel
        panel.title = title
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = name
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            self?.archivePanel = nil
            completion(response == .OK ? panel.url : nil)
        }
    }

    func chooseLocation(title: String, completion: @escaping (URL?) -> Void) {
        guard locationPanel == nil else { completion(nil); return }
        let panel = NSOpenPanel()
        locationPanel = panel
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            self?.locationPanel = nil
            completion(response == .OK ? panel.url : nil)
        }
    }

    private func diskUtility(_ arguments: [String]) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        try task.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
            if task.isRunning { task.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "OpenCommander.Volumes", code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "macOS could not complete the volume operation."])
        }
        return data
    }

    private func discoverUnmountedVolumes() throws -> [[String: String]] {
        let data = try diskUtility(["list", "-plist", "external"])
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        var result: [[String: String]] = []
        func visit(_ node: [String: Any]) {
            if let identifier = node["DeviceIdentifier"] as? String,
               let name = node["VolumeName"] as? String, !name.isEmpty,
               (node["MountPoint"] as? String ?? "").isEmpty {
                result.append(["identifier": identifier, "name": name])
            }
            for key in ["Partitions", "APFSVolumes"] {
                (node[key] as? [[String: Any]] ?? []).forEach(visit)
            }
        }
        (plist?["AllDisksAndPartitions"] as? [[String: Any]] ?? []).forEach(visit)
        return result
    }

    func unmountedVolumes(completion: @escaping ([[String: String]], NSError?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let volumes = try self.discoverUnmountedVolumes()
                DispatchQueue.main.async { completion(volumes, nil) }
            } catch { DispatchQueue.main.async { completion([], error as NSError) } }
        }
    }

    func mountVolume(_ identifier: String, completion: @escaping (NSError?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                // Re-discover before acting. No shell, no formatting, no forcing
                // read-write mode, and never target an internal/system device.
                guard identifier.range(of: "^disk[0-9]+(s[0-9]+)*$", options: .regularExpression) != nil,
                      try self.discoverUnmountedVolumes().contains(where: { $0["identifier"] == identifier }) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                _ = try self.diskUtility(["mount", identifier])
                DispatchQueue.main.async { completion(nil) }
            } catch { DispatchQueue.main.async { completion(error as NSError) } }
        }
    }

    func isEjectableVolume(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeIsInternalKey]),
              url.standardizedFileURL.path.hasPrefix("/Volumes/"),
              (values.allValues[.volumeURLKey] as? URL)?.standardizedFileURL == url.standardizedFileURL,
              values.volumeIsInternal != true else { return false }
        // Disk images may omit Foundation's internal-volume flag. Confirm with
        // Disk Arbitration metadata instead of treating an unknown flag as safe.
        guard let data = try? diskUtility(["info", "-plist", url.path]),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              (info["Internal"] as? Bool) == false,
              let mountPoint = info["MountPoint"] as? String,
              URL(fileURLWithPath: mountPoint).standardizedFileURL == url.standardizedFileURL
        else { return false }
        return true
    }

    func ejectVolume(_ url: URL, completion: @escaping (NSError?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                guard self.isEjectableVolume(url) else { throw CocoaError(.fileWriteNoPermission) }
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                DispatchQueue.main.async { completion(nil) }
            } catch { DispatchQueue.main.async { completion(error as NSError) } }
        }
    }

    func installedCloudApplications() -> [[String: String]] {
        [("Google Drive", ["com.google.drivefs"]),
         ("OneDrive", ["com.microsoft.OneDrive", "com.microsoft.OneDrive-mac"]),
         ("Dropbox", ["com.getdropbox.dropbox"]), ("Box", ["com.box.desktop"])].compactMap { name, identifiers in
            guard let url = identifiers.lazy.compactMap({
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }).first else { return nil }
            return ["name": name, "path": url.path]
        }
    }

    func setFolderApplication(_ application: URL, completion: @escaping (NSError?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: application, toOpen: .folder) { error in
            DispatchQueue.main.async { completion(error as NSError?) }
        }
    }

    func openFile(_ url: URL, application: URL?, completion: @escaping (Bool, NSError?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let finished: (NSRunningApplication?, Error?) -> Void = { _, error in
            DispatchQueue.main.async { completion(error == nil, error as NSError?) }
        }
        if let application {
            NSWorkspace.shared.open([url], withApplicationAt: application,
                                    configuration: configuration, completionHandler: finished)
        } else {
            NSWorkspace.shared.open(url, configuration: configuration, completionHandler: finished)
        }
    }

    func chooseApplication(for url: URL, title: String, completion: @escaping (Bool, NSError?) -> Void) {
        guard applicationPanel == nil else { completion(false, nil); return }
        let panel = NSOpenPanel()
        applicationPanel = panel
        panel.title = title
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { [weak self] response in
            self?.applicationPanel = nil
            guard response == .OK, let application = panel.url else { completion(false, nil); return }
            self?.openFile(url, application: application, completion: completion)
        }
    }
}
