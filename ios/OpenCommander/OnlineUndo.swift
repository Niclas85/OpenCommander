#if os(macOS) || targetEnvironment(macCatalyst)
import Foundation

/// Independent batch entries never replay a failed mutation. Report its exact
/// item, then attempt the next entry; cancellation stops the entire batch.
@MainActor enum OnlineBatch {
    static func run<Item>(_ items: [Item], operation: (Item) async throws -> Void,
                          failed: (Item, Error) -> Void) async throws -> Int {
        var failures = 0
        for item in items {
            try Task.checkCancellation()
            do { try await operation(item) }
            catch {
                let ns = error as NSError
                if error is CancellationError || Task.isCancelled ||
                    (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) ||
                    (ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) {
                    throw CancellationError()
                }
                failures += 1
                failed(item, error)
            }
        }
        return failures
    }
}

@MainActor private func pauseMoveAcceptance(_ id: UUID) async throws {
#if DEBUG && targetEnvironment(macCatalyst)
    guard Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests",
          let root = AppDelegate.macUITestRoot else { return }
    let flag = root.appendingPathComponent("PauseCloudMoveAfterRetention")
    if FileManager.default.fileExists(atPath: flag.path) {
        try Data(id.uuidString.utf8).write(to: root.appendingPathComponent("CloudMoveRetentionReady.txt"), options: .atomic)
        while FileManager.default.fileExists(atPath: flag.path) { try await Task.sleep(nanoseconds: 250_000_000) }
    }
#endif
}

/// Restartable non-destructive downloads. A completed private payload is reused
/// only after both its bytes and the remote version have been checked again.
/// Incomplete network downloads restart; no unverified byte offset is adopted.
@MainActor enum PendingCloudDownload {
    private static var moving = Set<UUID>()
    struct Job: Codable {
        let id: UUID
        let endpoint: String
        let account: String
        let itemID: String
        let itemPath: String?
        let name: String
        let directory: String
        let device: UInt64
        let inode: UInt64
        let version: [String: String]
        var content: [String: String]?
        var move: Bool?
    }
    private static var active = Set<UUID>()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenCommander/CloudDownloads", isDirectory: true)
    }
    static func folder(_ job: Job, root: URL) -> URL { root.appendingPathComponent(job.id.uuidString, isDirectory: true) }
    static func pending(root: URL = directory) throws -> [Job] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard UUID(uuidString: url.lastPathComponent) != nil else { return nil }
            let manifest = url.appendingPathComponent("job.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
            let data = try Data(contentsOf: manifest)
            guard data.count <= 32 * 1024 * 1024 else { throw CloudConnection.failure("cloud_undo_changed") }
            let job = try JSONDecoder().decode(Job.self, from: data)
            guard job.id.uuidString == url.lastPathComponent, OneDriveClient.validName(job.name),
                  job.directory.hasPrefix("/") else { throw CloudConnection.failure("cloud_undo_changed") }
            return job
        }
    }
    static func destination(_ job: Job) throws -> URL {
        let url = URL(fileURLWithPath: job.directory, isDirectory: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.systemNumber] as? NSNumber)?.uint64Value == job.device,
              (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == job.inode else { throw CloudConnection.failure("cloud_undo_changed") }
        return url
    }
    static func prepare(_ item: OneDriveItem, client: any CommanderOnlineClient, destination: URL,
                        move: Bool = false, root: URL = directory) async throws -> Job {
        let account = try await client.accountIdentity()
        let itemPath = try client.persistentPath(item.id)
        if let existing = try pending(root: root).first(where: { saved in
            saved.endpoint == client.clientID && saved.account == account &&
                (itemPath.map { saved.itemPath == $0 } ?? (saved.itemID == item.id)) &&
                saved.name == item.name && saved.directory == destination.path && (saved.move == true) == move
        }) {
            _ = try self.destination(existing)
            return existing
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              OneDriveClient.validName(item.name) else { throw CloudConnection.failure("cloud_undo_changed") }
        let job = Job(id: UUID(), endpoint: client.clientID, account: account, itemID: item.id,
            itemPath: itemPath, name: item.name, directory: destination.path,
            device: device.uint64Value, inode: inode.uint64Value, version: try await client.remoteSnapshot(item), move: move)
        let container = folder(job, root: root)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(job).write(to: container.appendingPathComponent("job.json"), options: .atomic)
#if DEBUG && targetEnvironment(macCatalyst)
        if Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests",
           let root = AppDelegate.macUITestRoot {
            let pause = root.appendingPathComponent("PauseCloudDownloadAfterCheckpoint")
            if FileManager.default.fileExists(atPath: pause.path) {
                try Data(job.id.uuidString.utf8).write(to: root.appendingPathComponent("CloudDownloadCheckpointReady.txt"), options: .atomic)
                while FileManager.default.fileExists(atPath: pause.path) { try await Task.sleep(nanoseconds: 250_000_000) }
            }
        }
#endif
        return job
    }
    static func resume(_ job: Job, client: any CommanderOnlineClient, root: URL = directory) async throws -> URL {
        guard active.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { active.remove(job.id) }
        _ = try destination(job)
        guard client.clientID == job.endpoint, try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_account") }
        let item = try await client.restoreReference(job.itemID, path: job.itemPath)
        guard item.name == job.name, try await client.remoteSnapshot(item) == job.version else { throw CloudConnection.failure("cloud_undo_changed") }
        let container = folder(job, root: root), payload = folder(job, root: root).appendingPathComponent("payload")
        if let content = job.content {
            guard try await RemoteContent.snapshotAsync(payload) == content else { throw CloudConnection.failure("cloud_undo_changed") }
            return payload
        }
        // A previous process may have completed the copy but not the manifest.
        // Only this job's private, uncommitted staging may be discarded.
        if FileManager.default.fileExists(atPath: payload.path) { try FileManager.default.removeItem(at: payload) }
        let downloaded = try await client.downloadTree(item)
        defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }
        guard try await client.accountIdentity() == job.account,
              try await client.remoteSnapshot(item) == job.version else { throw CloudConnection.failure("cloud_undo_changed") }
        try await Task.detached { try FileManager.default.copyItem(at: downloaded, to: payload) }.value
        var ready = job
        ready.content = try await RemoteContent.snapshotAsync(payload)
        try JSONEncoder().encode(ready).write(to: container.appendingPathComponent("job.json"), options: .atomic)
        return payload
    }
    static func hasMovePublication(_ job: Job, root: URL = directory) -> Bool {
        FileManager.default.fileExists(atPath: folder(job, root: root).appendingPathComponent("publication.json").path)
    }
    static func completeMove(_ job: Job, client: any CommanderOnlineClient, record: FileUndoRecord? = nil,
                             sourceLocation: String, root: URL = directory) async throws -> CloudUndoPayload {
        guard moving.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { moving.remove(job.id) }
        guard job.move == true, client.clientID == job.endpoint,
              try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_account") }
        let destination = try destination(job)
        let publication = folder(job, root: root).appendingPathComponent("publication.json")
        if let record {
            guard record.destination.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL,
                  record.replacedBackup == nil || record.hasVerifiedRecoveryProof else { throw CloudConnection.failure("cloud_undo_changed") }
            try record.verifyUnchangedDestination()
            try record.verifyRecovery()
            try JSONEncoder().encode(record).write(to: publication, options: .atomic)
        }
        let saved = try JSONDecoder().decode(FileUndoRecord.self, from: Data(contentsOf: publication))
        guard saved.destination.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL,
              saved.replacedBackup == nil || saved.hasVerifiedRecoveryProof else { throw CloudConnection.failure("cloud_undo_changed") }
        try saved.verifyUnchangedDestination()
        try saved.verifyRecovery()
        let moveRoot = folder(job, root: root).appendingPathComponent("move")
        let existing = try PendingOnlineMove.pending(root: moveRoot)
        guard existing.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
        if let retained = existing.first {
            // Path-backed providers issue session-local IDs after relaunch.
            // Bind to the saved path when available; Graph uses stable IDs.
            let sameSource: Bool
            if let path = job.itemPath { sameSource = retained.source.path == path }
            else { sameSource = retained.source.id == job.itemID }
            guard retained.endpoint == job.endpoint, retained.account == job.account,
                  sameSource, retained.source.name == job.name,
                  retained.destinationLocation == saved.destination.path else { throw CloudConnection.failure("cloud_undo_changed") }
            return try await PendingOnlineMove.resume(retained, client: client)
        }
        let item = try await client.restoreReference(job.itemID, path: job.itemPath)
        guard try await client.remoteSnapshot(item) == job.version else { throw CloudConnection.failure("cloud_undo_changed") }
        let content = try await RemoteContent.snapshotAsync(saved.destination)
        let retained = try await PendingOnlineMove.prepare(client, item: item, content: content, local: saved,
            sourceLocation: sourceLocation, destinationLocation: saved.destination.path, root: moveRoot)
        return try await PendingOnlineMove.resume(retained, client: client)
    }
    static func finish(_ job: Job, root: URL = directory) throws {
        try FileManager.default.removeItem(at: folder(job, root: root))
    }
}

/// Durable, non-destructive upload recovery. An ambiguous existing destination
/// is verified, never overwritten or made eligible for destructive Undo.
@MainActor enum PendingCloudUpload {
    private static var moving = Set<UUID>()
    struct MoveIntent: Codable {
        let original: String
        let fingerprint: Data
        let destination: String
    }
    private static var active = Set<UUID>()
    private struct Receipt: Codable {
        let jobID: UUID
        let undo: CloudUndoPayload
        let version: [String: String]
    }
    struct Job: Codable {
        let id: UUID
        let endpoint: String
        let account: String
        let parent: String?
        let parentPath: String?
        let name: String
        let source: String
        let content: [String: String]
        var actionKey: String?
        var moveIntent: MoveIntent?
    }
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenCommander/CloudUploads", isDirectory: true)
    }
    static func folder(_ job: Job, root: URL) -> URL { root.appendingPathComponent(job.id.uuidString, isDirectory: true) }
    static func pending(root: URL = directory) throws -> [Job] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard UUID(uuidString: url.lastPathComponent) != nil else { return nil }
            let manifest = url.appendingPathComponent("job.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
            let job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: manifest))
            guard job.id.uuidString == url.lastPathComponent, !job.name.isEmpty,
                  job.name != ".", job.name != "..", !job.name.contains("/"),
                  job.actionKey.map({ ["copy", "zip", "extract_archive", "duplicate"].contains($0) }) != false else { throw CloudConnection.failure("cloud_undo_changed") }
            return job
        }
    }
    static func prepare(_ staged: URL, source: String, client: any CommanderOnlineClient,
                        parent: String?, account: String, actionKey: String? = nil,
                        moveOriginal: URL? = nil, moveDestination: String? = nil, root: URL = directory) async throws -> Job {
        guard actionKey.map({ ["copy", "zip", "extract_archive", "duplicate"].contains($0) }) != false else { throw CloudConnection.failure("cloud_undo_changed") }
        var job = Job(id: UUID(), endpoint: client.clientID, account: account, parent: parent,
                      parentPath: try client.persistentPath(parent), name: staged.lastPathComponent,
                      source: source, content: try await RemoteContent.snapshotAsync(staged), actionKey: actionKey)
        if let original = moveOriginal {
            guard original.isFileURL, original.path != "/", let destination = moveDestination,
                  try await RemoteContent.snapshotAsync(original) == job.content else { throw CloudConnection.failure("cloud_undo_changed") }
            job.moveIntent = MoveIntent(original: original.path,
                fingerprint: try await Task.detached { try SafeFileOperations.snapshot(original) }.value,
                destination: destination)
        }
        let container = folder(job, root: root)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: container) } }
        try FileManager.default.createDirectory(at: container.appendingPathComponent("data"), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let destination = container.appendingPathComponent("data").appendingPathComponent(job.name)
        try await Task.detached { try FileManager.default.copyItem(at: staged, to: destination) }.value
        guard try await RemoteContent.snapshotAsync(destination) == job.content else { throw CloudConnection.failure("cloud_undo_changed") }
        try JSONEncoder().encode(job).write(to: container.appendingPathComponent("job.json"), options: .atomic)
        published = true
#if DEBUG && targetEnvironment(macCatalyst)
        // Deterministic restart acceptance in the isolated UI app only. Never
        // enabled by production arguments, accounts or downloaded content.
        if Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests",
           let root = AppDelegate.macUITestRoot {
            let pause = root.appendingPathComponent("PauseCloudUploadAfterCheckpoint")
            if FileManager.default.fileExists(atPath: pause.path) {
                try Data(job.id.uuidString.utf8).write(to: root.appendingPathComponent("CloudCheckpointReady.txt"), options: .atomic)
                while FileManager.default.fileExists(atPath: pause.path) {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
#endif
        return job
    }
    static func resume(_ job: Job, client: any CommanderOnlineClient, root: URL = directory) async throws -> CloudUndoPayload? {
        guard active.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { active.remove(job.id) }
        guard client.clientID == job.endpoint, try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_account") }
        let staged = folder(job, root: root).appendingPathComponent("data").appendingPathComponent(job.name)
        let graph = client as? OneDriveClient
        let previousRecoveryAccount = graph?.uploadRecoveryAccount
        graph?.uploadRecoveryAccount = job.account
        defer { graph?.uploadRecoveryAccount = previousRecoveryAccount }
        guard try await RemoteContent.snapshotAsync(staged) == job.content else { throw CloudConnection.failure("cloud_undo_changed") }
        var parent = job.parent
        if let id = parent { parent = try await client.restoreReference(id, path: job.parentPath).id }
        let receiptURL = folder(job, root: root).appendingPathComponent("receipt.json")
        if FileManager.default.fileExists(atPath: receiptURL.path) {
            let data = try Data(contentsOf: receiptURL)
            guard data.count <= 32 * 1024 * 1024 else { throw CloudConnection.failure("cloud_undo_changed") }
            let receipt = try JSONDecoder().decode(Receipt.self, from: data)
            try receipt.undo.validate()
            guard receipt.jobID == job.id, receipt.undo.kind == "remove",
                  receipt.undo.endpoint == job.endpoint, receipt.undo.account == job.account,
                  receipt.undo.current.name == job.name, receipt.undo.current.content == job.content else { throw CloudConnection.failure("cloud_undo_changed") }
            // Path-backed providers allocate session-local reference IDs. Restore
            // the persisted reference before comparing the current parent list.
            let restored = try await client.restoreReference(receipt.undo.current.id, path: receipt.undo.current.path)
            guard let current = try await client.children(of: parent).first(where: { $0.id == restored.id }),
                  current.name == job.name,
                  try await client.remoteSnapshot(current) == receipt.version,
                  try await CommanderOnlineTools.contentSnapshot(client, item: current) == job.content,
                  try await client.remoteSnapshot(current) == receipt.version,
                  try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_changed") }
            return receipt.undo
        }
        if let existing = try await client.children(of: parent).first(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(job.name) }) {
            let actual = try await CommanderOnlineTools.contentSnapshot(client, item: existing)
            if !existing.isFolder, existing.name == job.name, actual != job.content,
               try await client.resumePendingUpload(staged, parent: parent) {
                guard try await client.accountIdentity() == job.account,
                      let completed = try await client.children(of: parent).first(where: { $0.name == job.name }),
                      try await CommanderOnlineTools.contentSnapshot(client, item: completed) == job.content else { throw CloudConnection.failure("cloud_undo_changed") }
                return nil // Reconciled placeholder; do not infer destructive Undo ownership.
            }
            guard existing.name == job.name else { throw OneDriveFailure.nameConflict }
            // A session-created incomplete file can also live inside a partially
            // published folder. Reject extra paths and type changes first; a
            // mismatching file still requires its own saved session below.
            let compatibleTree = existing.isFolder && job.content[""] == "directory" && actual.allSatisfy { path, value in
                guard let expected = job.content[path] else { return false }
                return (value == "directory") == (expected == "directory")
            }
            guard actual.allSatisfy({ job.content[$0.key] == $0.value }) || compatibleTree else { throw OneDriveFailure.nameConflict }
            if actual != job.content {
                guard existing.isFolder, job.content[""] == "directory" else { throw OneDriveFailure.nameConflict }
                // Only resume an existing file through its account/path/source-
                // bound session. Ordinary existing files are never overwritten.
                func fill(_ local: URL, remote: OneDriveItem, depth: Int) async throws {
                    guard depth < 100, try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_account") }
                    let children = try await client.children(of: remote.id)
                    for child in try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil) {
                        try Task.checkCancellation()
                        if let present = children.first(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(child.lastPathComponent) }) {
                            guard present.name == child.lastPathComponent else { throw OneDriveFailure.nameConflict }
                            if present.isFolder { try await fill(child, remote: present, depth: depth + 1) }
                            else {
                                let expected = try await RemoteContent.snapshotAsync(child)
                                if try await CommanderOnlineTools.contentSnapshot(client, item: present) != expected {
                                    guard try await client.resumePendingUpload(child, parent: remote.id),
                                          try await CommanderOnlineTools.contentSnapshot(client, item: present) == expected else { throw OneDriveFailure.nameConflict }
                                }
                            }
                        } else { try await client.uploadTree(child, parent: remote.id) }
                    }
                }
                try await fill(staged, remote: existing, depth: 0)
            }
            guard try await client.accountIdentity() == job.account,
                  try await CommanderOnlineTools.contentSnapshot(client, item: existing) == job.content else { throw CloudConnection.failure("cloud_undo_changed") }
            return nil // Could predate this job; never claim ownership for Undo.
        }
        try Task.checkCancellation()
        try await client.uploadTree(staged, parent: parent)
        let undo = try await PersistentOnlineUndo.uploaded(client, parent: parent, name: job.name, content: job.content, account: job.account)
        let current = try await client.metadata(undo.current.id)
        let version = try await client.remoteSnapshot(current)
        guard try await CommanderOnlineTools.contentSnapshot(client, item: current) == job.content,
              try await client.remoteSnapshot(current) == version,
              try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_changed") }
        // Only a completed upload in this invocation creates ownership evidence.
        // A crash before this atomic receipt remains deliberately ambiguous.
        try JSONEncoder().encode(Receipt(jobID: job.id, undo: undo, version: version))
            .write(to: receiptURL, options: .atomic)
        return undo
    }
    /// The move intent exists before the first network write. Its retention
    /// journal stays inside the upload job until history publication finishes.
    /// Ambiguous remote success never authorizes removal of the original.
    static func resumeMove(_ job: Job, client: any CommanderOnlineClient, root: URL = directory) async throws -> CloudUndoPayload {
        guard moving.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { moving.remove(job.id) }
        guard let intent = job.moveIntent, intent.original.hasPrefix("/"), intent.original != "/",
              !intent.original.split(separator: "/").contains("..") else { throw CloudConnection.failure("cloud_undo_changed") }
        let retainedRoot = folder(job, root: root).appendingPathComponent("move", isDirectory: true)
        let existing = try PendingLocalCloudMove.pending(root: retainedRoot)
        guard existing.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
        if let retained = existing.first {
            guard retained.original == intent.original, retained.fingerprint == intent.fingerprint,
                  retained.uploaded.endpoint == job.endpoint, retained.uploaded.account == job.account,
                  retained.uploaded.current.content == job.content else { throw CloudConnection.failure("cloud_undo_changed") }
            return try await PendingLocalCloudMove.resume(retained, client: client)
        }
        let original = URL(fileURLWithPath: intent.original)
        guard try await Task.detached(operation: { try SafeFileOperations.snapshot(original) }).value == intent.fingerprint else { throw CloudConnection.failure("cloud_undo_changed") }
        guard let uploaded = try await resume(job, client: client, root: root) else {
            // A matching destination without our receipt might belong to
            // someone else. Keep both and retain the checkpoint for inspection.
            throw CloudConnection.failure("cloud_undo_changed")
        }
        guard try await Task.detached(operation: { try SafeFileOperations.snapshot(original) }).value == intent.fingerprint else { throw CloudConnection.failure("cloud_undo_changed") }
        let retained = try await PendingLocalCloudMove.prepare(original, uploaded: uploaded,
            destinationLocation: intent.destination, root: retainedRoot)
        return try await PendingLocalCloudMove.resume(retained, client: client)
    }
    static func finish(_ job: Job, root: URL = directory) throws {
        try FileManager.default.removeItem(at: folder(job, root: root))
    }
}

/// Replacement intent is durable before the old object is displaced. Recovery
/// accepts only the recorded old version or its unique verified recovery name.
/// Uploads use the same non-overwriting, restartable journal as ordinary copies.
@MainActor enum PendingCloudReplacement {
    struct Job: Codable {
        let id: UUID
        let upload: PendingCloudUpload.Job
        let originalID: String
        let originalPath: String?
        let originalTag: String
        let originalContent: [String: String]
        var moveIntent: PendingCloudUpload.MoveIntent? = nil
        var recoveryName: String { ".OpenCommander-Replaced-" + id.uuidString }
    }
    private static var active = Set<UUID>()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenCommander/CloudReplacements", isDirectory: true)
    }
    static func folder(_ job: Job, root: URL) -> URL { root.appendingPathComponent(job.id.uuidString, isDirectory: true) }
    static func pending(root: URL = directory) throws -> [Job] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { entry in
            guard UUID(uuidString: entry.lastPathComponent) != nil else { return nil }
            let manifest = entry.appendingPathComponent("job.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
            let data = try Data(contentsOf: manifest)
            guard data.count <= 32 * 1024 * 1024 else { throw CloudConnection.failure("cloud_undo_changed") }
            let job = try JSONDecoder().decode(Job.self, from: data)
            guard job.id.uuidString == entry.lastPathComponent, OneDriveClient.validName(job.upload.name) else { throw CloudConnection.failure("cloud_undo_changed") }
            return job
        }
    }
    static func prepare(_ source: URL, sourceLocation: String, existing: OneDriveItem,
                        client: any CommanderOnlineClient, parent: String?, moveOriginal: URL? = nil,
                        moveDestination: String? = nil, root: URL = directory) async throws -> Job {
        let account = try await client.accountIdentity()
        guard source.lastPathComponent == existing.name, let tag = existing.eTag,
              try await client.metadata(existing.id).eTag == tag,
              try await client.children(of: parent).contains(where: { $0.id == existing.id }) else { throw CloudConnection.failure("cloud_undo_changed") }
        let original = try await CommanderOnlineTools.contentSnapshot(client, item: existing)
        let id = UUID(), container = root.appendingPathComponent(".preparing-" + UUID().uuidString)
        // Publish under its final UUID directory only after every component exists.
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: container) } }
        let upload = try await PendingCloudUpload.prepare(source, source: sourceLocation, client: client, parent: parent,
            account: account, root: container.appendingPathComponent("upload"))
        var job = Job(id: id, upload: upload, originalID: existing.id, originalPath: try client.persistentPath(existing.id),
                      originalTag: tag, originalContent: original)
        if let moveOriginal {
            guard let moveDestination, moveOriginal.isFileURL, moveOriginal.path != "/",
                  try await RemoteContent.snapshotAsync(moveOriginal) == upload.content else { throw CloudConnection.failure("cloud_undo_changed") }
            let fingerprint = try await Task.detached { try SafeFileOperations.snapshot(moveOriginal) }.value
            job.moveIntent = .init(original: moveOriginal.path, fingerprint: fingerprint, destination: moveDestination)
        }
        try JSONEncoder().encode(job).write(to: container.appendingPathComponent("job.json"), options: .atomic)
        try FileManager.default.moveItem(at: container, to: folder(job, root: root))
        published = true
        return job
    }
    static func resume(_ job: Job, client: any CommanderOnlineClient, root: URL = directory) async throws -> CommanderOnlineTools.Replacement {
        guard active.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { active.remove(job.id) }
        guard client.clientID == job.upload.endpoint, try await client.accountIdentity() == job.upload.account else { throw CloudConnection.failure("cloud_undo_account") }
        var parent = job.upload.parent
        if let id = parent { parent = try await client.restoreReference(id, path: job.upload.parentPath).id }
        let listing = try await client.children(of: parent)
        var backup = listing.first { $0.name == job.recoveryName }
        if backup == nil {
            let original = try await client.restoreReference(job.originalID, path: job.originalPath)
            guard original.name == job.upload.name, original.eTag == job.originalTag,
                  try await CommanderOnlineTools.contentSnapshot(client, item: original) == job.originalContent,
                  !listing.contains(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(job.recoveryName) }) else { throw CloudConnection.failure("cloud_undo_changed") }
            try Task.checkCancellation()
            try await client.move(original, parent: parent, name: job.recoveryName)
            backup = try await client.children(of: parent).first { $0.name == job.recoveryName }
        }
        guard let backup, try await CommanderOnlineTools.contentSnapshot(client, item: backup) == job.originalContent else { throw CloudConnection.failure("cloud_undo_changed") }
#if DEBUG && targetEnvironment(macCatalyst)
        if Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests", let fixture = AppDelegate.macUITestRoot {
            let pause = fixture.appendingPathComponent("PauseCloudReplacementAfterBackup")
            if FileManager.default.fileExists(atPath: pause.path) {
                try Data(job.id.uuidString.utf8).write(to: fixture.appendingPathComponent("CloudReplacementReady.txt"), options: .atomic)
                while FileManager.default.fileExists(atPath: pause.path) { try await Task.sleep(nanoseconds: 250_000_000) }
            }
        }
#endif
        _ = try await PendingCloudUpload.resume(job.upload, client: client, root: folder(job, root: root).appendingPathComponent("upload"))
        guard try await client.accountIdentity() == job.upload.account,
              let replacement = try await client.children(of: parent).first(where: { $0.name == job.upload.name }),
              try await CommanderOnlineTools.contentSnapshot(client, item: replacement) == job.upload.content,
              try await CommanderOnlineTools.contentSnapshot(client, item: backup) == job.originalContent else { throw CloudConnection.failure("cloud_undo_changed") }
        return .init(previous: backup, replacement: replacement, parent: parent, name: job.upload.name,
                     previousContent: job.originalContent, replacementContent: job.upload.content)
    }
    static func resumeMove(_ job: Job, client: any CommanderOnlineClient, root: URL = directory) async throws -> CloudUndoPayload {
        guard let intent = job.moveIntent, client.clientID == job.upload.endpoint,
              try await client.accountIdentity() == job.upload.account else { throw CloudConnection.failure("cloud_undo_account") }
        let moveRoot = folder(job, root: root).appendingPathComponent("move")
        let pending = try PendingLocalCloudMove.pending(root: moveRoot)
        guard pending.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
        if let move = pending.first {
            guard move.original == intent.original, move.fingerprint == intent.fingerprint,
                  move.uploaded.endpoint == job.upload.endpoint, move.uploaded.account == job.upload.account,
                  move.uploaded.kind == "replacement", move.uploaded.current.content == job.upload.content,
                  move.uploaded.previous?.content == job.originalContent,
                  move.destinationLocation == intent.destination else { throw CloudConnection.failure("cloud_undo_changed") }
            return try await PendingLocalCloudMove.resume(move, client: client)
        }
        let original = URL(fileURLWithPath: intent.original)
        guard try await Task.detached(operation: { try SafeFileOperations.snapshot(original) }).value == intent.fingerprint else { throw CloudConnection.failure("cloud_undo_changed") }
        let result = try await resume(job, client: client, root: root)
        guard try await Task.detached(operation: { try SafeFileOperations.snapshot(original) }).value == intent.fingerprint else { throw CloudConnection.failure("cloud_undo_changed") }
        let undo = try PersistentOnlineUndo.replacement(client, record: result, account: job.upload.account)
        let move = try await PendingLocalCloudMove.prepare(original, uploaded: undo, destinationLocation: intent.destination, root: moveRoot)
        return try await PendingLocalCloudMove.resume(move, client: client)
    }
    static func finish(_ job: Job, root: URL = directory) throws {
        try FileManager.default.removeItem(at: folder(job, root: root))
    }
}

/// Persist the source-retention phase of a cross-provider/download move before
/// changing the source name. The verified destination is rechecked on every
/// retry; an ambiguous rename is reconciled, never blindly replayed.
/// Durable cross-provider intent, published before the first download. Nested
/// journals remain private until History has accepted the completed move.
@MainActor enum PendingCrossCloudMove {
    struct Job: Codable {
        let id: UUID
        let sourceEndpoint: String
        let sourceAccount: String
        let sourceID: String
        let sourcePath: String?
        let sourceName: String
        let version: [String: String]
        let endpoint: String
        let account: String
        let parent: String?
        let parentPath: String?
        let name: String
        let sourceLocation: String
        let destinationLocation: String
        var privateUploadName: String?
        var replacing: CloudUndoPayload.Object? = nil
        var replacingTag: String? = nil
    }
    private struct Publication: Codable {
        let jobID: UUID
        let identity: String?
        let content: [String: String]
    }
    private static var active = Set<UUID>()
    nonisolated static var directory: URL {
        PendingCloudUpload.directory.deletingLastPathComponent().appendingPathComponent("CrossCloudMoves", isDirectory: true)
    }
    static func folder(_ job: Job, root: URL) -> URL { root.appendingPathComponent(job.id.uuidString, isDirectory: true) }
    static func pending(root: URL = directory) throws -> [Job] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard UUID(uuidString: url.lastPathComponent) != nil else { return nil }
            let manifest = url.appendingPathComponent("job.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
            let data = try Data(contentsOf: manifest)
            guard data.count <= 32 * 1024 * 1024 else { throw CloudConnection.failure("cloud_undo_changed") }
            let job = try JSONDecoder().decode(Job.self, from: data)
            guard job.id.uuidString == url.lastPathComponent, OneDriveClient.validName(job.name),
                  OneDriveClient.validName(job.sourceName) else { throw CloudConnection.failure("cloud_undo_changed") }
            return job
        }
    }
    static func prepare(_ item: OneDriveItem, source: any CommanderOnlineClient,
                        target: any CommanderOnlineClient, parent: String?, name: String,
                        sourceLocation: String, destinationLocation: String, replacing: OneDriveItem? = nil,
                        root: URL = directory) async throws -> Job {
        guard OneDriveClient.validName(name) else { throw CloudConnection.failure("cloud_undo_changed") }
        let id = UUID()
        let privateName = ".OpenCommander-Cross-" + id.uuidString
        guard !(try await target.children(of: parent)).contains(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(privateName) }) else { throw CloudConnection.failure("cloud_undo_changed") }
        var job = Job(id: id, sourceEndpoint: source.clientID, sourceAccount: try await source.accountIdentity(),
            sourceID: item.id, sourcePath: try source.persistentPath(item.id), sourceName: item.name,
            version: try await source.remoteSnapshot(item), endpoint: target.clientID, account: try await target.accountIdentity(),
            parent: parent, parentPath: try target.persistentPath(parent), name: name,
            sourceLocation: sourceLocation, destinationLocation: destinationLocation, privateUploadName: privateName)
        let same = job.sourceEndpoint == job.endpoint && job.sourceAccount == job.account
        guard !same || replacing != nil else { throw CloudConnection.failure("cloud_undo_changed") }
        if same { try await target.validateDestination(parent, excluding: item.id) }
        if let replacing {
            guard replacing.name == name, let tag = replacing.eTag,
                  !same || replacing.id != item.id,
                  try await target.metadata(replacing.id).eTag == tag,
                  try await target.children(of: parent).contains(where: { $0.id == replacing.id }) else { throw CloudConnection.failure("cloud_undo_changed") }
            let content = try await CommanderOnlineTools.contentSnapshot(target, item: replacing)
            job.replacing = try PersistentOnlineUndo.object(target, item: replacing, content: content)
            job.replacingTag = tag
        }
        let container = folder(job, root: root)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(job).write(to: container.appendingPathComponent("job.json"), options: .atomic)
        return job
    }
    static func resume(_ job: Job, source: any CommanderOnlineClient, target: any CommanderOnlineClient,
                       root: URL = directory) async throws -> CloudUndoPayload {
        guard active.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { active.remove(job.id) }
        guard source.clientID == job.sourceEndpoint, target.clientID == job.endpoint,
              try await source.accountIdentity() == job.sourceAccount,
              try await target.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_account") }
        let container = folder(job, root: root)
        let movesRoot = container.appendingPathComponent("move"), uploadsRoot = container.appendingPathComponent("upload")
        let moves = try PendingOnlineMove.pending(root: movesRoot)
        guard moves.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
        if let move = moves.first {
            guard move.endpoint == job.sourceEndpoint, move.account == job.sourceAccount,
                  move.source.name == job.sourceName, move.uploaded?.endpoint == job.endpoint,
                  move.uploaded?.account == job.account, move.destinationLocation == job.destinationLocation,
                  job.sourcePath.map({ move.source.path == $0 }) ?? (move.source.id == job.sourceID) else { throw CloudConnection.failure("cloud_undo_changed") }
            return try await PendingOnlineMove.resume(move, client: source, targetClient: target)
        }
        let item = try await source.restoreReference(job.sourceID, path: job.sourcePath)
        guard item.name == job.sourceName, try await source.remoteSnapshot(item) == job.version else { throw CloudConnection.failure("cloud_undo_changed") }
        var parent = job.parent
        if let id = parent { parent = try await target.restoreReference(id, path: job.parentPath).id }
        if job.replacing != nil { return try await resumeReplacement(job, item: item, source: source, target: target, parent: parent, root: root) }
        let uploadName = job.privateUploadName ?? job.name
        guard job.privateUploadName == nil || uploadName == ".OpenCommander-Cross-" + job.id.uuidString else { throw CloudConnection.failure("cloud_undo_changed") }
        let uploads = try PendingCloudUpload.pending(root: uploadsRoot)
        guard uploads.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
        let upload: PendingCloudUpload.Job
        if let existing = uploads.first {
            guard existing.endpoint == job.endpoint, existing.account == job.account, existing.name == uploadName,
                  existing.parentPath == job.parentPath,
                  job.parentPath != nil || existing.parent == job.parent else { throw CloudConnection.failure("cloud_undo_changed") }
            upload = existing
        } else {
            let stage = container.appendingPathComponent("stage", isDirectory: true)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let downloadsRoot = container.appendingPathComponent("download")
            let downloads = try PendingCloudDownload.pending(root: downloadsRoot)
            guard downloads.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
            let download: PendingCloudDownload.Job
            if let existing = downloads.first { download = existing }
            else { download = try await PendingCloudDownload.prepare(item, client: source, destination: stage, root: downloadsRoot) }
            guard download.endpoint == job.sourceEndpoint, download.account == job.sourceAccount,
                  download.version == job.version, download.directory == stage.path else { throw CloudConnection.failure("cloud_undo_changed") }
            let payload = try await PendingCloudDownload.resume(download, client: source, root: downloadsRoot)
            let named = stage.appendingPathComponent(uploadName)
            // Only discard our private uncommitted staging, never a remote item.
            if FileManager.default.fileExists(atPath: named.path) { try FileManager.default.removeItem(at: named) }
            try FileManager.default.copyItem(at: payload, to: named)
            upload = try await PendingCloudUpload.prepare(named, source: job.sourceLocation, client: target,
                parent: parent, account: job.account, root: uploadsRoot)
        }
        let receipt: CloudUndoPayload
        if job.privateUploadName != nil {
            receipt = try await publish(job, upload: upload, target: target, parent: parent, root: root)
        } else {
            // Legacy final-name uploads have no private nonce: never infer ownership.
            guard let verified = try await PendingCloudUpload.resume(upload, client: target, root: uploadsRoot) else { throw CloudConnection.failure("cloud_undo_changed") }
            receipt = verified
        }
        guard try await source.remoteSnapshot(item) == job.version,
              try await source.accountIdentity() == job.sourceAccount else { throw CloudConnection.failure("cloud_undo_changed") }
        let move = try await PendingOnlineMove.prepare(source, item: item, content: upload.content, uploaded: receipt,
            sourceLocation: job.sourceLocation, destinationLocation: job.destinationLocation, root: movesRoot)
        return try await PendingOnlineMove.resume(move, client: source, targetClient: target)
    }
    private static func resumeReplacement(_ job: Job, item: OneDriveItem, source: any CommanderOnlineClient,
                                          target: any CommanderOnlineClient, parent: String?, root: URL) async throws -> CloudUndoPayload {
        guard let proof = job.replacing, let tag = job.replacingTag else { throw CloudConnection.failure("cloud_undo_changed") }
        let container = folder(job, root: root), replacementsRoot = container.appendingPathComponent("replacement")
        let jobs = try PendingCloudReplacement.pending(root: replacementsRoot)
        guard jobs.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
        let replacement: PendingCloudReplacement.Job
        if let saved = jobs.first {
            guard saved.upload.endpoint == job.endpoint, saved.upload.account == job.account,
                  saved.upload.name == job.name, saved.originalContent == proof.content,
                  saved.originalPath == proof.path, saved.originalTag == tag,
                  saved.upload.parentPath == job.parentPath,
                  job.parentPath != nil || saved.upload.parent == job.parent,
                  saved.moveIntent == nil else { throw CloudConnection.failure("cloud_undo_changed") }
            replacement = saved
        } else {
            let existing = try await target.restoreReference(proof.id, path: proof.path)
            guard existing.name == proof.name, existing.eTag == tag,
                  try await CommanderOnlineTools.contentSnapshot(target, item: existing) == proof.content else { throw CloudConnection.failure("cloud_undo_changed") }
            let stage = container.appendingPathComponent("stage", isDirectory: true)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let downloadsRoot = container.appendingPathComponent("download")
            let downloads = try PendingCloudDownload.pending(root: downloadsRoot)
            guard downloads.count <= 1 else { throw CloudConnection.failure("cloud_undo_changed") }
            let download: PendingCloudDownload.Job
            if let saved = downloads.first { download = saved }
            else { download = try await PendingCloudDownload.prepare(item, client: source, destination: stage, root: downloadsRoot) }
            guard download.endpoint == job.sourceEndpoint, download.account == job.sourceAccount,
                  download.version == job.version, download.directory == stage.path else { throw CloudConnection.failure("cloud_undo_changed") }
            let payload = try await PendingCloudDownload.resume(download, client: source, root: downloadsRoot)
            let named = stage.appendingPathComponent(job.name)
            if FileManager.default.fileExists(atPath: named.path) { try FileManager.default.removeItem(at: named) }
            try FileManager.default.copyItem(at: payload, to: named)
            replacement = try await PendingCloudReplacement.prepare(named, sourceLocation: job.sourceLocation,
                existing: existing, client: target, parent: parent, root: replacementsRoot)
        }
        let result = try await PendingCloudReplacement.resume(replacement, client: target, root: replacementsRoot)
        guard try await source.remoteSnapshot(item) == job.version,
              try await source.accountIdentity() == job.sourceAccount else { throw CloudConnection.failure("cloud_undo_changed") }
        let undo = try PersistentOnlineUndo.replacement(target, record: result, account: job.account)
        let move = try await PendingOnlineMove.prepare(source, item: item, content: replacement.upload.content, uploaded: undo,
            sourceLocation: job.sourceLocation, destinationLocation: job.destinationLocation, root: container.appendingPathComponent("move"))
        return try await PendingOnlineMove.resume(move, client: source, targetClient: target)
    }
    private static func publish(_ job: Job, upload: PendingCloudUpload.Job, target: any CommanderOnlineClient,
                                parent: String?, root: URL) async throws -> CloudUndoPayload {
        let container = folder(job, root: root), proofURL = container.appendingPathComponent("publication.json")
        func identity(_ item: OneDriveItem) throws -> String? {
            if try target.persistentPath(item.id) == nil { return item.id }
            return item.providerID.flatMap { $0.isEmpty ? nil : $0 }
        }
        let proof: Publication
        if FileManager.default.fileExists(atPath: proofURL.path) {
            proof = try JSONDecoder().decode(Publication.self, from: Data(contentsOf: proofURL))
            guard proof.jobID == job.id, proof.content == upload.content else { throw CloudConnection.failure("cloud_undo_changed") }
        } else {
            // A random, preflight-vacant per-job name is an operation-owned
            // namespace. Matching bytes in the user-visible final name are not.
            _ = try await PendingCloudUpload.resume(upload, client: target, root: container.appendingPathComponent("upload"))
            guard let staged = try await target.children(of: parent).first(where: { $0.name == upload.name }),
                  try await CommanderOnlineTools.contentSnapshot(target, item: staged) == upload.content else { throw CloudConnection.failure("cloud_undo_changed") }
            proof = Publication(jobID: job.id, identity: try identity(staged), content: upload.content)
            try JSONEncoder().encode(proof).write(to: proofURL, options: .atomic)
        }
        let listing = try await target.children(of: parent)
        if let final = listing.first(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(job.name) }) {
            guard final.name == job.name, let expected = proof.identity, try identity(final) == expected,
                  !listing.contains(where: { $0.name == upload.name }) else { throw OneDriveFailure.nameConflict }
        } else {
            guard let staged = listing.first(where: { $0.name == upload.name }),
                  try proof.identity == nil || identity(staged) == proof.identity,
                  try await CommanderOnlineTools.contentSnapshot(target, item: staged) == proof.content,
                  try await target.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_changed") }
            try await target.move(staged, parent: parent, name: job.name)
        }
        return try await PersistentOnlineUndo.uploaded(target, parent: parent, name: job.name, content: proof.content, account: job.account)
    }
    static func finish(_ job: Job, root: URL = directory) throws {
        try FileManager.default.removeItem(at: folder(job, root: root))
    }
}

@MainActor enum PendingOnlineMove {
    struct Job: Codable {
        let id: UUID
        let endpoint: String
        let account: String
        let source: CloudUndoPayload.Object
        let tag: String
        let uploaded: CloudUndoPayload?
        let local: Data?
        let sourceLocation: String
        let destinationLocation: String
        var recoveryName: String { ".OpenCommander-Moved-" + id.uuidString }
    }
    private static var active = Set<UUID>()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenCommander/CloudMoves", isDirectory: true)
    }
    static func pending(root: URL = directory) throws -> [Job] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { entry in
            guard UUID(uuidString: entry.deletingPathExtension().lastPathComponent) != nil, entry.pathExtension == "json" else { return nil }
            let data = try Data(contentsOf: entry)
            guard data.count <= 32 * 1024 * 1024 else { throw CloudConnection.failure("cloud_undo_changed") }
            let job = try JSONDecoder().decode(Job.self, from: data)
            guard entry.lastPathComponent == job.id.uuidString + ".json", (job.uploaded != nil) != (job.local != nil) else { throw CloudConnection.failure("cloud_undo_changed") }
            return job
        }
    }
    static func prepare(_ client: any CommanderOnlineClient, item: OneDriveItem, content: [String: String],
                        uploaded: CloudUndoPayload? = nil, local: FileUndoRecord? = nil,
                        sourceLocation: String, destinationLocation: String, root: URL = directory) async throws -> Job {
        let account = try await client.accountIdentity()
        let current = try await client.metadata(item.id)
        guard (uploaded != nil) != (local != nil), let tag = item.eTag,
              current.name == item.name, current.eTag == tag,
              try await CommanderOnlineTools.contentSnapshot(client, item: item) == content else { throw CloudConnection.failure("cloud_undo_changed") }
        if let uploaded { try uploaded.validate(); guard ["remove", "replacement"].contains(uploaded.kind), uploaded.current.content == content else { throw CloudConnection.failure("cloud_undo_changed") } }
        guard try await client.accountIdentity() == account else { throw CloudConnection.failure("cloud_undo_account") }
        let job = Job(id: UUID(), endpoint: client.clientID, account: account,
            source: try PersistentOnlineUndo.object(client, item: current, content: content), tag: tag,
            uploaded: uploaded, local: try local.map { try JSONEncoder().encode($0) },
            sourceLocation: sourceLocation, destinationLocation: destinationLocation)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(job).write(to: root.appendingPathComponent(job.id.uuidString + ".json"), options: .atomic)
        return job
    }
    static func resume(_ job: Job, client: any CommanderOnlineClient,
                       targetClient: (any CommanderOnlineClient)? = nil) async throws -> CloudUndoPayload {
        guard active.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { active.remove(job.id) }
        guard client.clientID == job.endpoint, try await client.accountIdentity() == job.account,
              (job.uploaded != nil) != (job.local != nil) else { throw CloudConnection.failure("cloud_undo_account") }
        let local = try job.local.map { try JSONDecoder().decode(FileUndoRecord.self, from: $0) }
        func verifyDestination() async throws {
            if let uploaded = job.uploaded {
                try uploaded.validate()
                let target = try targetClient ?? PersistentOnlineUndo.client(uploaded.endpoint)
                guard ["remove", "replacement"].contains(uploaded.kind), uploaded.current.content == job.source.content,
                      target.clientID == uploaded.endpoint, try await target.accountIdentity() == uploaded.account else { throw CloudConnection.failure("cloud_undo_account") }
                let current = try await target.restoreReference(uploaded.current.id, path: uploaded.current.path)
                try await PersistentOnlineUndo.verifyPrevious(uploaded, client: target, current: current)
                guard current.name == uploaded.current.name,
                      try await CommanderOnlineTools.contentSnapshot(target, item: current) == job.source.content else { throw CloudConnection.failure("cloud_undo_changed") }
            } else if let local {
                guard local.replacedBackup == nil || local.hasVerifiedRecoveryProof else { throw CloudConnection.failure("cloud_undo_changed") }
                try await Task.detached { try local.verifyUnchangedDestination(); try local.verifyRecovery() }.value
                guard try await RemoteContent.snapshotAsync(local.destination) == job.source.content else { throw CloudConnection.failure("cloud_undo_changed") }
            } else { throw CloudConnection.failure("cloud_undo_changed") }
        }
        try await verifyDestination()
        var parent = job.source.parent
        // Older intents created from Graph listing rows can omit parentReference.
        // Resolve only by the saved stable item ID, with name/version/content
        // guards; never guess root or search by name across the user's drive.
        if parent == nil, client is OneDriveClient {
            let current = try await client.metadata(job.source.id)
            guard (current.name == job.source.name && current.eTag == job.tag) || current.name == job.recoveryName,
                  try await CommanderOnlineTools.contentSnapshot(client, item: current) == job.source.content else { throw CloudConnection.failure("cloud_undo_changed") }
            guard let resolved = current.parentReference?.id else { throw CloudConnection.failure("cloud_undo_changed") }
            parent = resolved
        }
        if let id = parent { parent = try await client.restoreReference(id, path: job.source.parentPath).id }
        let listing = try await client.children(of: parent)
        var retained = listing.first { $0.name == job.recoveryName }
        if retained == nil {
            guard !listing.contains(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(job.recoveryName) }) else { throw CloudConnection.failure("cloud_undo_changed") }
            let current = try await client.restoreReference(job.source.id, path: job.source.path)
            guard current.name == job.source.name, current.eTag == job.tag, current.parentReference?.id == parent,
                  try await CommanderOnlineTools.contentSnapshot(client, item: current) == job.source.content,
                  try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_changed") }
            try Task.checkCancellation()
            try await client.move(current, parent: parent, name: job.recoveryName)
            retained = try await client.children(of: parent).first { $0.name == job.recoveryName }
        }
        guard let retained, try await client.accountIdentity() == job.account,
              try await CommanderOnlineTools.contentSnapshot(client, item: retained) == job.source.content else { throw CloudConnection.failure("cloud_undo_changed") }
        try await pauseMoveAcceptance(job.id)
        try await verifyDestination()
        let restore = CloudUndoPayload.SourceRestore(endpoint: job.endpoint, account: job.account,
            recovery: try PersistentOnlineUndo.object(client, item: retained, content: job.source.content),
            name: job.source.name, parent: parent, parentPath: job.source.parentPath)
        if let uploaded = job.uploaded { return try PersistentOnlineUndo.crossMove(uploaded, source: restore) }
        guard let local else { throw CloudConnection.failure("cloud_undo_changed") }
        return try PersistentOnlineUndo.downloadMove(restore, local: local)
    }
    static func finish(_ job: Job, root: URL = directory) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(job.id.uuidString + ".json"))
    }
}

/// Local-to-online moves retain the local original under a deterministic sibling
/// name. A same-volume rename is recoverable even if the app dies before History
/// is saved; it never requires deleting the user's original bytes.
@MainActor enum PendingLocalCloudMove {
    struct Job: Codable {
        let id: UUID
        let uploaded: CloudUndoPayload
        let original: String
        let fingerprint: Data
        let parentDevice: UInt64
        let parentInode: UInt64
        let destinationLocation: String
        var recovery: URL {
            URL(fileURLWithPath: original).deletingLastPathComponent().appendingPathComponent(".OpenCommander-Moved-" + id.uuidString)
        }
    }
    private static var active = Set<UUID>()
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenCommander/LocalCloudMoves", isDirectory: true)
    }
    static func pending(root: URL = directory) throws -> [Job] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { entry in
            guard UUID(uuidString: entry.deletingPathExtension().lastPathComponent) != nil, entry.pathExtension == "json" else { return nil }
            let data = try Data(contentsOf: entry)
            guard data.count <= 32 * 1024 * 1024 else { throw CloudConnection.failure("cloud_undo_changed") }
            let job = try JSONDecoder().decode(Job.self, from: data)
            guard entry.lastPathComponent == job.id.uuidString + ".json" else { throw CloudConnection.failure("cloud_undo_changed") }
            try job.uploaded.validate()
            return job
        }
    }
    static func prepare(_ original: URL, uploaded: CloudUndoPayload, destinationLocation: String,
                        root: URL = directory) async throws -> Job {
        try uploaded.validate()
        guard ["remove", "replacement"].contains(uploaded.kind), original.isFileURL, original.path != "/",
              try await RemoteContent.snapshotAsync(original) == uploaded.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
        let attributes = try FileManager.default.attributesOfItem(atPath: original.deletingLastPathComponent().path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let device = attributes[.systemNumber] as? NSNumber, let inode = attributes[.systemFileNumber] as? NSNumber else { throw CloudConnection.failure("cloud_undo_changed") }
        let fingerprint = try await Task.detached { try SafeFileOperations.snapshot(original) }.value
        let job = Job(id: UUID(), uploaded: uploaded, original: original.path, fingerprint: fingerprint,
            parentDevice: device.uint64Value, parentInode: inode.uint64Value, destinationLocation: destinationLocation)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(job).write(to: root.appendingPathComponent(job.id.uuidString + ".json"), options: .atomic)
        return job
    }
    static func resume(_ job: Job, client: any CommanderOnlineClient) async throws -> CloudUndoPayload {
        guard active.insert(job.id).inserted else { throw CloudConnection.failure("cloud_undo_changed") }
        defer { active.remove(job.id) }
        try job.uploaded.validate()
        guard ["remove", "replacement"].contains(job.uploaded.kind), job.original.hasPrefix("/"), job.original != "/",
              !job.original.split(separator: "/").contains(".."), client.clientID == job.uploaded.endpoint,
              try await client.accountIdentity() == job.uploaded.account else { throw CloudConnection.failure("cloud_undo_account") }
        let original = URL(fileURLWithPath: job.original), parent = original.deletingLastPathComponent()
        let scope = parent.startAccessingSecurityScopedResource()
        defer { if scope { parent.stopAccessingSecurityScopedResource() } }
        let attributes = try FileManager.default.attributesOfItem(atPath: parent.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.systemNumber] as? NSNumber)?.uint64Value == job.parentDevice,
              (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == job.parentInode else { throw CloudConnection.failure("cloud_undo_changed") }
        let current = try await client.restoreReference(job.uploaded.current.id, path: job.uploaded.current.path)
        try await PersistentOnlineUndo.verifyPrevious(job.uploaded, client: client, current: current)
        guard current.name == job.uploaded.current.name,
              try await CommanderOnlineTools.contentSnapshot(client, item: current) == job.uploaded.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
        if !SafeFileOperations.exists(job.recovery) {
            let fingerprint = try await Task.detached { try SafeFileOperations.snapshot(original) }.value
            guard fingerprint == job.fingerprint, try await RemoteContent.snapshotAsync(original) == job.uploaded.current.content,
                  try await client.accountIdentity() == job.uploaded.account else { throw CloudConnection.failure("cloud_undo_changed") }
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: original, to: job.recovery)
        }
        let retainedFingerprint = try await Task.detached { try SafeFileOperations.snapshot(job.recovery, rootName: original.lastPathComponent) }.value
        try await PersistentOnlineUndo.verifyPrevious(job.uploaded, client: client, current: current)
        try await pauseMoveAcceptance(job.id)
        guard retainedFingerprint == job.fingerprint, !SafeFileOperations.exists(original),
              try await client.accountIdentity() == job.uploaded.account,
              try await CommanderOnlineTools.contentSnapshot(client, item: current) == job.uploaded.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
        return try await PersistentOnlineUndo.localMove(job.uploaded, original: original, recovery: job.recovery)
    }
    static func finish(_ job: Job, root: URL = directory) throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent(job.id.uuidString + ".json"))
    }
}

@MainActor enum PersistentOnlineUndo {
    static func verifyPrevious(_ payload: CloudUndoPayload, client: any CommanderOnlineClient, current: OneDriveItem) async throws {
        guard let proof = payload.previous else { return }
        let previous = try await client.restoreReference(proof.id, path: proof.path)
        guard previous.name == proof.name, previous.parentReference?.id == current.parentReference?.id,
              try await CommanderOnlineTools.contentSnapshot(client, item: previous) == proof.content,
              try await client.accountIdentity() == payload.account else { throw CloudConnection.failure("cloud_undo_changed") }
    }
    /// Direct cloud deletion retains a verified object, so restore it through
    /// the same persistent relocation protocol as rename (including restart).
    static func cloudRecoveryDelete(_ client: CloudFileClient, item: OneDriveItem) async throws -> CloudUndoPayload {
        let account = try await client.accountIdentity()
        let content = try await CommanderOnlineTools.contentSnapshot(client, item: item)
        let original = try await client.metadata(item.id)
        guard original.eTag == item.eTag else { throw CloudConnection.failure("cloud_undo_changed") }
        let parent = original.parentReference?.id, parentPath = try client.persistentPath(parent)
        try await client.recycle(item)
        let retained = try await client.metadata(item.id)
        guard try await client.accountIdentity() == account,
              try await CommanderOnlineTools.contentSnapshot(client, item: retained) == content else {
            throw CloudConnection.failure("cloud_undo_changed")
        }
        return try relocation(client, current: retained, content: content,
                              parent: parent, parentPath: parentPath, name: item.name, account: account)
    }
    static func object(_ client: any CommanderOnlineClient, item: OneDriveItem, content: [String: String]) throws -> CloudUndoPayload.Object {
        .init(id: item.id, name: item.name, path: try client.persistentPath(item.id), parent: item.parentReference?.id,
              parentPath: try client.persistentPath(item.parentReference?.id), content: content)
    }
    static func relocation(_ client: any CommanderOnlineClient, current: OneDriveItem, content: [String: String],
                           parent: String?, parentPath: String?, name: String, account: String) throws -> CloudUndoPayload {
        let payload = CloudUndoPayload(endpoint: client.clientID, account: account, kind: "relocate", current: try object(client, item: current, content: content),
            originalName: name, originalParent: parent, originalParentPath: parentPath)
        try payload.validate(); return payload
    }
    static func replacement(_ client: any CommanderOnlineClient, record: CommanderOnlineTools.Replacement, account: String) throws -> CloudUndoPayload {
        let payload = CloudUndoPayload(endpoint: client.clientID, account: account, kind: "replacement",
            current: try object(client, item: record.replacement, content: record.replacementContent),
            previous: try object(client, item: record.previous, content: record.previousContent))
        try payload.validate(); return payload
    }
    static func client(_ endpoint: String) throws -> any CommanderOnlineClient {
        if endpoint.hasPrefix("cloud:"), let profile = CloudConnection.load().first(where: { "cloud:" + $0.id == endpoint }) { return CloudFileClient.browserClient(profile) }
        if endpoint.hasPrefix("remote:"), let profile = RemoteConnection.load().first(where: { "remote:" + $0.id == endpoint }) { return RemoteFileClient(profile) }
        if OneDriveClient.validClientID(endpoint) { return OneDriveClient.browserClient(clientID: endpoint) }
        throw CloudConnection.failure("cloud_undo_account")
    }
    static func uploaded(_ client: any CommanderOnlineClient, parent: String?, name: String, content: [String: String], account: String) async throws -> CloudUndoPayload {
        guard try await client.accountIdentity() == account,
            let item = try await client.children(of: parent).first(where: { $0.name == name }),
            try await CommanderOnlineTools.contentSnapshot(client, item: item) == content else { throw CloudConnection.failure("cloud_undo_changed") }
        let payload = CloudUndoPayload(endpoint: client.clientID, account: account, kind: "remove", current: try object(client, item: item, content: content))
        try payload.validate(); return payload
    }
    /// Retain a verifiable source object instead of sending it to a provider's
    /// opaque recycle bin. This allows cross-account Undo after app restart.
    static func retainMoveSource(_ client: any CommanderOnlineClient, item: OneDriveItem,
                                 content: [String: String], account: String) async throws -> CloudUndoPayload.SourceRestore {
        guard try await client.accountIdentity() == account,
              try await CommanderOnlineTools.contentSnapshot(client, item: item) == content else { throw CloudConnection.failure("cloud_undo_changed") }
        let current = try await client.metadata(item.id)
        guard current.eTag == item.eTag else { throw CloudConnection.failure("cloud_undo_changed") }
        let parent = current.parentReference?.id, parentPath = try client.persistentPath(parent)
        let recoveryName = ".OpenCommander-Moved-" + UUID().uuidString
        try await client.move(current, parent: parent, name: recoveryName)
        let recovery = try await client.metadata(item.id)
        guard try await client.accountIdentity() == account,
              try await CommanderOnlineTools.contentSnapshot(client, item: recovery) == content else { throw CloudConnection.failure("cloud_undo_changed") }
        return .init(endpoint: client.clientID, account: account, recovery: try object(client, item: recovery, content: content),
            name: item.name, parent: parent, parentPath: parentPath)
    }
    static func crossMove(_ uploaded: CloudUndoPayload, source: CloudUndoPayload.SourceRestore) throws -> CloudUndoPayload {
        guard ["remove", "replacement"].contains(uploaded.kind) else { throw CloudConnection.failure("cloud_undo_changed") }
        let payload = CloudUndoPayload(endpoint: uploaded.endpoint, account: uploaded.account, kind: "crossMove",
            current: uploaded.current, previous: uploaded.previous, sourceRestore: source)
        try payload.validate(); return payload
    }
    static func localMove(_ uploaded: CloudUndoPayload, original: URL, recovery: URL) async throws -> CloudUndoPayload {
        guard ["remove", "replacement"].contains(uploaded.kind), try await RemoteContent.snapshotAsync(recovery) == uploaded.current.content else {
            throw CloudConnection.failure("cloud_undo_changed")
        }
        let parent = try FileManager.default.attributesOfItem(atPath: original.deletingLastPathComponent().path)
        guard parent[.type] as? FileAttributeType == .typeDirectory,
              let device = parent[.systemNumber] as? NSNumber, let inode = parent[.systemFileNumber] as? NSNumber else {
            throw CloudConnection.failure("cloud_undo_changed")
        }
        var payload = CloudUndoPayload(endpoint: uploaded.endpoint, account: uploaded.account, kind: "localMove", current: uploaded.current)
        payload.previous = uploaded.previous
        payload.localSourceRestore = .init(original: original.path, recovery: recovery.path, parentDevice: device.uint64Value, parentInode: inode.uint64Value)
        try payload.validate(); return payload
    }
    static func downloadMove(_ source: CloudUndoPayload.SourceRestore, local: FileUndoRecord) throws -> CloudUndoPayload {
        var payload = CloudUndoPayload(endpoint: source.endpoint, account: source.account, kind: "downloadMove", current: source.recovery,
            originalName: source.name, originalParent: source.parent, originalParentPath: source.parentPath)
        payload.localCopyUndo = try JSONEncoder().encode(local)
        try payload.validate(); return payload
    }
    /// Reconcile process loss after both originals were restored but before
    /// History saved success. This path only reads; it never adopts ownership
    /// for another destructive operation based on matching content.
    private static func replacementAlreadyUndone(_ payload: CloudUndoPayload, client: any CommanderOnlineClient,
                                                  sourceClient: (any CommanderOnlineClient)?) async throws -> Bool {
        guard let previous = payload.previous, ["localMove", "crossMove"].contains(payload.kind) else { return false }
        var parent = payload.current.parent
        if let id = parent { parent = try await client.restoreReference(id, path: payload.current.parentPath).id }
        guard let restoredTarget = try await client.children(of: parent).first(where: { $0.name == payload.current.name }),
              try await CommanderOnlineTools.contentSnapshot(client, item: restoredTarget) == previous.content else { return false }
        if payload.kind == "localMove", let local = payload.localSourceRestore {
            let original = URL(fileURLWithPath: local.original)
            let attributes = try FileManager.default.attributesOfItem(atPath: original.deletingLastPathComponent().path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.systemNumber] as? NSNumber)?.uint64Value == local.parentDevice,
                  (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == local.parentInode,
                  SafeFileOperations.exists(original), try await RemoteContent.snapshotAsync(original) == payload.current.content else { return false }
        } else if let source = payload.sourceRestore {
            let origin = try sourceClient ?? Self.client(source.endpoint)
            guard origin.clientID == source.endpoint, try await origin.accountIdentity() == source.account else { throw CloudConnection.failure("cloud_undo_account") }
            var sourceParent = source.parent
            if let id = sourceParent { sourceParent = try await origin.restoreReference(id, path: source.parentPath).id }
            guard let restoredSource = try await origin.children(of: sourceParent).first(where: { $0.name == source.name }),
                  try await CommanderOnlineTools.contentSnapshot(origin, item: restoredSource) == source.recovery.content else { return false }
            guard try await origin.accountIdentity() == source.account else { throw CloudConnection.failure("cloud_undo_account") }
        } else { return false }
        guard try await client.accountIdentity() == payload.account else { throw CloudConnection.failure("cloud_undo_account") }
        return true
    }
    /// Every restart resolves fresh references and verifies account/content
    /// before displacement. No mutation is replayed after an ambiguous failure.
    static func undo(_ payload: CloudUndoPayload, client: any CommanderOnlineClient,
                     sourceClient: (any CommanderOnlineClient)? = nil) async throws -> String? {
        try payload.validate()
        guard client.clientID == payload.endpoint, try await client.accountIdentity() == payload.account else { throw CloudConnection.failure("cloud_undo_account") }
        if try await replacementAlreadyUndone(payload, client: client, sourceClient: sourceClient) { return nil }
        if payload.kind == "downloadMove", let data = payload.localCopyUndo, let originalName = payload.originalName {
            let local = try JSONDecoder().decode(FileUndoRecord.self, from: data)
            try await Task.detached { try local.verifyUnchangedDestination(); try local.verifyRecovery() }.value
            // Preflight the local copy before restoring the remote name. The
            // local Undo engine separately rechecks metadata before displacement.
            guard try await RemoteContent.snapshotAsync(local.destination) == payload.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
            var parent = payload.originalParent
            if let id = parent { parent = try await client.restoreReference(id, path: payload.originalParentPath).id }
            if let restored = try await client.children(of: parent).first(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(originalName) }) {
                guard restored.id == payload.current.id, restored.name == originalName,
                      try await CommanderOnlineTools.contentSnapshot(client, item: restored) == payload.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
            } else {
                let recovery = try await client.restoreReference(payload.current.id, path: payload.current.path)
                guard recovery.name == payload.current.name,
                      try await CommanderOnlineTools.contentSnapshot(client, item: recovery) == payload.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
                try await client.move(recovery, parent: parent, name: originalName)
            }
            guard try await client.accountIdentity() == payload.account,
                  let restored = try await client.children(of: parent).first(where: { $0.name == originalName }),
                  try await CommanderOnlineTools.contentSnapshot(client, item: restored) == payload.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
            let worker = Task.detached { try local.undo(move: false, checkCancellation: { try Task.checkCancellation() }) }
            try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            return nil
        }
        let current = try await client.restoreReference(payload.current.id, path: payload.current.path)
        guard current.name == payload.current.name, try await CommanderOnlineTools.contentSnapshot(client, item: current) == payload.current.content else {
            throw CloudConnection.failure("cloud_undo_changed")
        }
        try Task.checkCancellation()
        if let parent = payload.current.parent { _ = try await client.restoreReference(parent, path: payload.current.parentPath) }
        if payload.kind == "localMove", let local = payload.localSourceRestore {
            try await verifyPrevious(payload, client: client, current: current)
            let original = URL(fileURLWithPath: local.original), recovery = URL(fileURLWithPath: local.recovery)
            let attributes = try FileManager.default.attributesOfItem(atPath: original.deletingLastPathComponent().path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.systemNumber] as? NSNumber)?.uint64Value == local.parentDevice,
                  (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == local.parentInode else { throw CloudConnection.failure("cloud_undo_changed") }
            let content = payload.current.content
            if SafeFileOperations.exists(original) {
                guard try await RemoteContent.snapshotAsync(original) == content else { throw CloudConnection.failure("cloud_undo_changed") }
            } else {
                guard try await RemoteContent.snapshotAsync(recovery) == content else { throw CloudConnection.failure("cloud_undo_changed") }
                let worker = Task.detached {
                    _ = try SafeFileOperations.copyReplacing(source: recovery, destination: original, replace: false,
                        copy: { source, staged in
                            try Task.checkCancellation()
                            try FileManager.default.copyItem(at: source, to: staged)
                            guard try RemoteContent.snapshot(staged) == content else { throw CloudConnection.failure("cloud_undo_changed") }
                        }, publish: { staged, target in
                            try Task.checkCancellation()
                            try FileManager.default.moveItem(at: staged, to: target)
                        })
                }
                try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            }
            // Restore and verify the source before retiring the cloud copy.
            // The recovery object remains available even after a successful Undo.
            guard try await RemoteContent.snapshotAsync(original) == content,
                  try await client.accountIdentity() == payload.account,
                  try await CommanderOnlineTools.contentSnapshot(client, item: current) == content else { throw CloudConnection.failure("cloud_undo_changed") }
            if let previous = payload.previous {
                let retained = try await client.restoreReference(previous.id, path: previous.path)
                _ = try await CommanderOnlineTools.undoReplacement(client, record: .init(previous: retained, replacement: current,
                    parent: current.parentReference?.id, name: current.name, previousContent: previous.content, replacementContent: content))
            } else {
                let proof = try await client.remoteSnapshot(current)
                try await client.recycleUnchanged(current, snapshot: proof)
            }
            return local.recovery
        }
        if payload.kind == "crossMove" {
            try await verifyPrevious(payload, client: client, current: current)
            guard let source = payload.sourceRestore else { throw CloudConnection.failure("cloud_undo_changed") }
            let origin = try sourceClient ?? Self.client(source.endpoint)
            guard origin.clientID == source.endpoint, try await origin.accountIdentity() == source.account else { throw CloudConnection.failure("cloud_undo_account") }
            var parent = source.parent
            if let id = parent { parent = try await origin.restoreReference(id, path: source.parentPath).id }
            // A prior attempt may have restored the source and then failed while
            // retiring the destination. Accept only verified original bytes.
            if let restored = try await origin.children(of: parent).first(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(source.name) }) {
                guard restored.name == source.name,
                      try await CommanderOnlineTools.contentSnapshot(origin, item: restored) == source.recovery.content else { throw CloudConnection.failure("cloud_undo_changed") }
            } else {
                let recovery = try await origin.restoreReference(source.recovery.id, path: source.recovery.path)
                guard recovery.name == source.recovery.name,
                      try await CommanderOnlineTools.contentSnapshot(origin, item: recovery) == source.recovery.content else { throw CloudConnection.failure("cloud_undo_changed") }
                try await origin.move(recovery, parent: parent, name: source.name)
                guard try await CommanderOnlineTools.contentSnapshot(origin, item: origin.metadata(recovery.id)) == source.recovery.content else { throw CloudConnection.failure("cloud_undo_changed") }
            }
            guard try await origin.accountIdentity() == source.account,
                  try await client.accountIdentity() == payload.account,
                  try await CommanderOnlineTools.contentSnapshot(client, item: current) == payload.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
            if let previous = payload.previous {
                let retained = try await client.restoreReference(previous.id, path: previous.path)
                _ = try await CommanderOnlineTools.undoReplacement(client, record: .init(previous: retained, replacement: current,
                    parent: current.parentReference?.id, name: current.name, previousContent: previous.content, replacementContent: payload.current.content))
            } else {
                let proof = try await client.remoteSnapshot(current)
                try await client.recycleUnchanged(current, snapshot: proof)
            }
            return client.moveBackupLocation
        }
        if payload.kind == "replacement" {
            guard let proof = payload.previous else { throw CloudConnection.failure("cloud_undo_changed") }
            let previous = try await client.restoreReference(proof.id, path: proof.path)
            guard previous.name == proof.name, previous.parentReference?.id == current.parentReference?.id,
                try await CommanderOnlineTools.contentSnapshot(client, item: previous) == proof.content,
                try await client.accountIdentity() == payload.account else { throw CloudConnection.failure("cloud_undo_changed") }
            let retained = try await CommanderOnlineTools.undoReplacement(client, record: .init(previous: previous, replacement: current,
                parent: current.parentReference?.id, name: current.name, previousContent: proof.content, replacementContent: payload.current.content))
            return retained.name
        }
        guard try await client.accountIdentity() == payload.account else { throw CloudConnection.failure("cloud_undo_account") }
        if payload.kind == "remove" {
            let snapshot = try await client.remoteSnapshot(current)
            guard try await CommanderOnlineTools.contentSnapshot(client, item: current) == payload.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
            try await client.recycleUnchanged(current, snapshot: snapshot)
            return client.moveBackupLocation
        }
        guard let name = payload.originalName else { throw CloudConnection.failure("cloud_undo_changed") }
        var parent = payload.originalParent
        if let id = parent { parent = try await client.restoreReference(id, path: payload.originalParentPath).id }
        guard !(try await client.children(of: parent)).contains(where: { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(name) }) else { throw OneDriveFailure.nameConflict }
        try await client.move(current, parent: parent, name: name)
        guard try await CommanderOnlineTools.contentSnapshot(client, item: client.metadata(current.id)) == payload.current.content else { throw CloudConnection.failure("cloud_undo_changed") }
        return nil
    }
}
#endif
