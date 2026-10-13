#if os(macOS) || targetEnvironment(macCatalyst)
import Foundation

@MainActor enum PersistentOnlineUndo {
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
    /// Every restart resolves fresh references and verifies account/content
    /// before displacement. No mutation is replayed after an ambiguous failure.
    static func undo(_ payload: CloudUndoPayload, client: any CommanderOnlineClient) async throws -> String? {
        try payload.validate()
        guard client.clientID == payload.endpoint, try await client.accountIdentity() == payload.account else { throw CloudConnection.failure("cloud_undo_account") }
        let current = try await client.restoreReference(payload.current.id, path: payload.current.path)
        guard current.name == payload.current.name, try await CommanderOnlineTools.contentSnapshot(client, item: current) == payload.current.content else {
            throw CloudConnection.failure("cloud_undo_changed")
        }
        try Task.checkCancellation()
        if let parent = payload.current.parent { _ = try await client.restoreReference(parent, path: payload.current.parentPath) }
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
