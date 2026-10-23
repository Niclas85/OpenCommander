import Foundation
import CryptoKit
import Darwin

@MainActor private final class RecoverableSessionClient: CommanderOnlineClient {
    let base: any CommanderOnlineClient
    let resume: (URL, String?) async throws -> Bool
    var toolsListing: ((String?) async throws -> [OneDriveItem])?
    init(_ base: any CommanderOnlineClient, resume: @escaping (URL, String?) async throws -> Bool) { self.base = base; self.resume = resume }
    var clientID: String { base.clientID }
    func accountIdentity() async throws -> String { try await base.accountIdentity() }
    func persistentPath(_ id: String?) throws -> String? { try base.persistentPath(id) }
    func restoreReference(_ id: String?, path: String?) async throws -> OneDriveItem { try await base.restoreReference(id, path: path) }
    func children(of id: String?) async throws -> [OneDriveItem] { try await base.children(of: id) }
    func toolChildren(of id: String?) async throws -> [OneDriveItem] {
        if let toolsListing { return try await toolsListing(id) }
        return try await base.toolChildren(of: id)
    }
    func metadata(_ id: String?) async throws -> OneDriveItem { try await base.metadata(id) }
    func createFolder(_ name: String, parent: String?) async throws { try await base.createFolder(name, parent: parent) }
    func rename(_ item: OneDriveItem, to name: String) async throws { try await base.rename(item, to: name) }
    func move(_ item: OneDriveItem, parent: String?, name: String?) async throws { try await base.move(item, parent: parent, name: name) }
    func recycle(_ item: OneDriveItem) async throws { try await base.recycle(item) }
    func validateDestination(_ parent: String?, excluding itemID: String) async throws { try await base.validateDestination(parent, excluding: itemID) }
    func upload(_ url: URL, parent: String?) async throws { try await base.upload(url, parent: parent) }
    func uploadTree(_ url: URL, parent: String?) async throws { try await base.uploadTree(url, parent: parent) }
    func resumePendingUpload(_ url: URL, parent: String?) async throws -> Bool { try await resume(url, parent) }
    func download(_ item: OneDriveItem) async throws -> URL { try await base.download(item) }
    func downloadTree(_ item: OneDriveItem) async throws -> URL { try await base.downloadTree(item) }
    func remoteSnapshot(_ item: OneDriveItem) async throws -> [String: String] { try await base.remoteSnapshot(item) }
    func recycleUnchanged(_ item: OneDriveItem, snapshot: [String: String]) async throws { try await base.recycleUnchanged(item, snapshot: snapshot) }
    func hasSavedLogin() throws -> Bool { try base.hasSavedLogin() }
    func beginLogin() async throws -> OneDriveDeviceCode { try await base.beginLogin() }
    func completeLogin(_ code: OneDriveDeviceCode) async throws { try await base.completeLogin(code) }
    func disconnect() throws { try base.disconnect() }
}

@main struct CloudClientTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let restartPhase = ProcessInfo.processInfo.environment["OPENCOMMANDER_RESTART_PHASE"]
        let restartRoot = ProcessInfo.processInfo.environment["OPENCOMMANDER_RESTART_ROOT"]
        let fixture = URL(fileURLWithPath: restartRoot ?? "/private/tmp/OpenCommander-CloudTests-" + UUID().uuidString)
        if restartPhase != nil {
            guard fixture.path.hasPrefix("/private/tmp/OpenCommander-CloudRestart-"),
                  try fixture.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { fatalError("Invalid isolated restart fixture") }
        }
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { if restartPhase == nil { try? fm.removeItem(at: fixture) } }
        let remote = fixture.appendingPathComponent("remote"), local = fixture.appendingPathComponent("local")
        try fm.createDirectory(at: remote, withIntermediateDirectories: true)
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        var requests = [String]()
        var unknownNames = Set<String>()
        var failUploads = false
        var failAfterUpload = false
        var failAfterRename = false
        var changeDuringExport = false
        var failExports = false
        var exportOutputs = [URL]()
        let profileFile = fixture.appendingPathComponent("profile.json")
        let profile = fm.fileExists(atPath: profileFile.path)
            ? try JSONDecoder().decode(CloudConnection.self, from: Data(contentsOf: profileFile))
            : CloudConnection(name: "Test Drive", kind: "drive", remote: "synthetic", configPath: "/private/tmp/test.conf")
        if restartPhase != nil { try JSONEncoder().encode(profile).write(to: profileFile, options: .atomic) }
        let secondRemote = fixture.appendingPathComponent("second-account")
        try fm.createDirectory(at: secondRemote, withIntermediateDirectories: true)
        let transport: CloudFileClient.Transport = { _, data, operation, path, destination, localURL, callback in
            do {
                let selected = try JSONDecoder().decode(CloudConnection.self, from: data)
                _ = try RcloneCommandPlan.arguments(profile: selected, operation: operation, path: path, destination: destination, local: localURL)
                requests.append(operation)
                let backend = selected.id == profile.id ? remote : secondRemote
                let source = path.isEmpty ? backend : backend.appendingPathComponent(path)
                var response = Data()
                switch operation {
                case "list":
                    let list = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).map { url -> [String: Any] in
                        let attributes = try fm.attributesOfItem(atPath: url.path)
                        let directory = attributes[.type] as? FileAttributeType == .typeDirectory
                        let contents = directory ? Data() : try Data(contentsOf: url)
                        let hash = Data(SHA256.hash(data: contents)).base64EncodedString()
                        return ["Name": url.lastPathComponent, "Path": url.lastPathComponent, "Size": unknownNames.contains(url.lastPathComponent) ? -1 : directory ? 0 : contents.count,
                            "IsDir": directory, "ID": String(describing: attributes[.systemFileNumber]!),
                            "ModTime": "2026-10-12T10:20:00Z", "Hashes": ["sha256": hash]]
                    }
                    response = try JSONSerialization.data(withJSONObject: list)
                case "mkdir": try fm.createDirectory(at: source, withIntermediateDirectories: false)
                case "download": try fm.copyItem(at: source, to: localURL!)
                case "export":
                    exportOutputs.append(localURL!)
                    try fm.copyItem(at: source, to: localURL!)
                    if changeDuringExport { try Data("changed native document".utf8).write(to: source) }
                    if failExports { throw CancellationError() }
                case "upload":
                    if failUploads { throw CloudConnection.failure("cloud_request_failed") }
                    try fm.copyItem(at: localURL!, to: source)
                case "rename":
                    try fm.moveItem(at: source, to: backend.appendingPathComponent(destination!))
                    // Real abrupt process loss after the backend committed but
                    // before its callback acknowledged the mutation. Strictly
                    // limited to this runner's disposable restart fixture.
                    if restartPhase == "cross-kill-crash",
                       let boundary = ProcessInfo.processInfo.environment["OPENCOMMANDER_KILL_BOUNDARY"],
                       (boundary == "publication" && selected.id != profile.id && destination == "kill-target.txt") ||
                       (boundary == "retention" && selected.id == profile.id && (destination! as NSString).lastPathComponent.hasPrefix(".OpenCommander-Moved-")) {
                        try Data(boundary.utf8).write(to: fixture.appendingPathComponent("kill-boundary-reached"), options: .atomic)
                        Darwin.kill(getpid(), SIGKILL)
                        _exit(99)
                    }
                    if failAfterUpload && (destination! as NSString).lastPathComponent.hasPrefix(".OpenCommander-Cross-") {
                        throw CloudConnection.failure("cloud_request_failed")
                    }
                    if failAfterRename && selected.id != profile.id { throw CloudConnection.failure("cloud_request_failed") }
                case "copy": try fm.copyItem(at: source, to: backend.appendingPathComponent(destination!))
                case "link": response = Data("https://drive.google.com/file/d/synthetic/view\n".utf8)
                default: throw CloudConnection.failure("cloud_invalid")
                }
                callback(response, nil)
            } catch { callback(nil, error as NSError) }
        }
        let client = CloudFileClient(profile, transport: transport)
        func require(_ value: Bool, _ text: String) { if !value { fatalError(text) } }
        if restartPhase == nil {
            let cancelledListing = RecoverableSessionClient(client, resume: { _, _ in false })
            cancelledListing.toolsListing = { _ in
                // Simulate a provider completing an empty response concurrently
                // with cancellation; transports may still acknowledge success.
                withUnsafeCurrentTask { $0?.cancel() }
                return []
            }
            let emptyScan = Task { @MainActor in
                try await CommanderOnlineTools.scan(cancelledListing, ancestors: [], hidden: false)
            }
            do { _ = try await emptyScan.value; fatalError("cancelled empty online scan reported complete") }
            catch is CancellationError { }
            let emptyContent = Task { @MainActor in
                try await CommanderOnlineTools.content(cancelledListing, ancestors: [], hidden: false)
            }
            do { _ = try await emptyContent.value; fatalError("cancelled empty online comparison reported equality") }
            catch is CancellationError { }
            print("PASS cancellation concurrent with empty online listing cannot publish complete scan or equality")
            let sizingProfile = CloudConnection(name: "Dropbox size fixture", kind: "dropbox", remote: "size", configPath: "/private/tmp/size.conf")
            var unknownSize = false, denied = false, huge = false
            var sizingWrites = 0
            let sizing = CloudFileClient(sizingProfile, transport: { _, _, operation, path, _, _, callback in
                guard operation == "list" else { sizingWrites += 1; callback(nil, CloudConnection.failure("cloud_invalid")); return }
                if denied && path == "Root/Sub" { callback(nil, CloudConnection.failure("cloud_request_failed")); return }
                let nodes: [(String, Int64, Bool)]
                switch path {
                case "": nodes = [("Root", 99999, true)]
                case "Root": nodes = [("a.bin", huge ? Int64.max : 5, false), ("Sub", 123, true), (".OpenCommanderMoved-DB68BA5F-A947-473E-8865-FCBEF42BF73E", 0, true)]
                case "Root/Sub": nodes = [("b.bin", unknownSize ? -1 : 7, false)]
                default: nodes = [("recovery.bin", 400, false)]
                }
                let rows: [[String: Any]] = nodes.map { ["Name": $0.0, "Path": $0.0, "Size": $0.1, "IsDir": $0.2] }
                callback(try! JSONSerialization.data(withJSONObject: rows), nil)
            })
            let folder = try await sizing.children(of: nil)[0]
            let complete = try await CommanderOnlineTools.folderSize(sizing, root: folder)
            require(complete.complete && complete.bytes == 12 && complete.entries == 4, "online size must count files, not provider folder sizes or recovery contents")
            unknownSize = true
            let unknown = try await CommanderOnlineTools.folderSize(sizing, root: folder)
            require(!unknown.complete && unknown.bytes == 5 && unknown.errors == 1, "unknown online export size must be partial")
            unknownSize = false; denied = true
            let inaccessible = try await CommanderOnlineTools.folderSize(sizing, root: folder)
            require(!inaccessible.complete && inaccessible.bytes == 5 && inaccessible.errors == 1, "inaccessible online subfolder must be partial")
            denied = false
            let bounded = try await CommanderOnlineTools.folderSize(sizing, root: folder, maximumEntries: 1)
            require(!bounded.complete && bounded.limit == "folder_size_entry_limit", "online size entry bound")
            let timed = try await CommanderOnlineTools.folderSize(sizing, root: folder, timeout: 0)
            require(timed.limit == "folder_size_time_limit", "online size time bound")
            huge = true
            let overflow = try await CommanderOnlineTools.folderSize(sizing, root: folder)
            require(overflow.limit == "folder_size_overflow", "online size overflow must not wrap")
            let cancelled = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await CommanderOnlineTools.folderSize(sizing, root: folder)
            }
            do { _ = try await cancelled.value; fatalError("online size ignored cancellation") } catch is CancellationError { }
            require(sizingWrites == 0, "properties scan performed a mutation")
            print("PASS online folder size: recursive exact bytes, recovery exclusion, unknown/denied partial results, entry/time/overflow bounds and cancellation")
            var collisionWrites = 0
            var collisionNames = ["duplicate.txt", "duplicate.txt", "Case.txt", "case.txt", "Safe"]
            let collisions = CloudFileClient(profile, transport: { _, _, operation, _, _, _, callback in
                if operation == "list" {
                    let rows = collisionNames.map { ["Name": $0, "Path": $0, "Size": 0, "IsDir": true] as [String: Any] }
                    callback(try! JSONSerialization.data(withJSONObject: rows), nil)
                } else { collisionWrites += 1; callback(Data(), nil) }
            })
            let displayed = try await collisions.browserListing(of: nil)
            require(displayed.items.map(\.name) == ["Safe"] && displayed.warningKey == "cloud_ambiguous_names_hidden", "duplicate listing must show safe items with warning")
            do { _ = try await collisions.toolChildren(of: nil); fatalError("partial recursive traversal accepted") } catch {}
            do { try await collisions.createFolder("DUPLICATE.txt", parent: nil); fatalError("ambiguous destination accepted") } catch {}
            require(collisionWrites == 0, "collision caused a write")
            try await collisions.createFolder("Unique QA", parent: nil)
            require(collisionWrites == 1, "unrelated unique destination blocked")
            collisionNames = ["Safe"]
            let resolved = try await collisions.browserListing(of: nil)
            require(resolved.warningKey == nil, "resolved duplicate warning persisted")
            print("PASS ambiguous cloud names excluded with warning; recursive tools and collisions blocked; unique destinations usable")
        }
        func runRestartPhase(_ restartPhase: String) async throws {
            let journal = fixture.appendingPathComponent("journal")
            let source = local.appendingPathComponent("Restart folder")
            let bytes = Data("Cloud restart: Grüsse, exact bytes\n".utf8)
            if restartPhase.hasPrefix("cross-kill-") {
                let targetFile = fixture.appendingPathComponent("kill-target-profile.json")
                let targetProfile: CloudConnection
                if fm.fileExists(atPath: targetFile.path) {
                    targetProfile = try JSONDecoder().decode(CloudConnection.self, from: Data(contentsOf: targetFile))
                } else {
                    targetProfile = CloudConnection(name: "Kill target", kind: "drive", remote: "kill-target", configPath: "/private/tmp/synthetic-kill.conf")
                    try JSONEncoder().encode(targetProfile).write(to: targetFile, options: .atomic)
                }
                let target = CloudFileClient(targetProfile, transport: transport)
                let killJournal = fixture.appendingPathComponent("kill-journal")
                let original = remote.appendingPathComponent("kill-source.txt")
                let destination = secondRemote.appendingPathComponent("kill-target.txt")
                let old = Data("previous kill-test destination\n".utf8)
                let replacing = ProcessInfo.processInfo.environment["OPENCOMMANDER_KILL_REPLACE"] == "1"
                if restartPhase == "cross-kill-prepare" {
                    try bytes.write(to: original)
                    if replacing { try old.write(to: destination) }
                    let item = try await client.children(of: nil).first { $0.name == "kill-source.txt" }!
                    let previous = try await target.children(of: nil).first { $0.name == "kill-target.txt" }
                    _ = try await PendingCrossCloudMove.prepare(item, source: client, target: target, parent: nil,
                        name: "kill-target.txt", sourceLocation: "synthetic:/kill-source.txt", destinationLocation: "synthetic:/kill-target.txt",
                        replacing: previous, root: killJournal)
                    print("PASS abrupt-loss fixture intent persisted before mutation")
                } else {
                    let jobs = try PendingCrossCloudMove.pending(root: killJournal)
                    require(jobs.count == 1, "abrupt loss lost/duplicated move intent")
                    let job = jobs[0]
                    if restartPhase == "cross-kill-crash" {
                        _ = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: killJournal)
                        fatalError("kill boundary was not reached")
                    }
                    require(fm.fileExists(atPath: fixture.appendingPathComponent("kill-boundary-reached").path), "no actual kill boundary evidence")
                    require(try Data(contentsOf: destination) == bytes, "committed target lost after kill")
                    if restartPhase == "cross-kill-tamper" {
                        let sourceObject: URL
                        if fm.fileExists(atPath: original.path) { sourceObject = original }
                        else {
                            let recovery = try fm.contentsOfDirectory(at: remote, includingPropertiesForKeys: nil)
                                .filter { $0.lastPathComponent.hasPrefix(".OpenCommander-Moved-") }
                            require(recovery.count == 1, "ambiguous source recovery in isolated kill fixture")
                            sourceObject = recovery[0]
                        }
                        let changed = Data("externally changed after actual process loss\n".utf8)
                        try changed.write(to: sourceObject)
                        do {
                            _ = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: killJournal)
                            fatalError("changed source accepted during abrupt-loss cleanup")
                        } catch {}
                        require(try Data(contentsOf: sourceObject) == changed, "changed source overwritten or removed")
                        require(try Data(contentsOf: destination) == bytes, "refused cleanup changed verified target")
                        require(try PendingCrossCloudMove.pending(root: killJournal).count == 1, "refused cleanup lost intent")
                        // Restore only this synthetic fixture's bytes for the
                        // following separate-process positive recovery test.
                        try bytes.write(to: sourceObject)
                        print("PASS after actual kill changed visible/retained source blocks cleanup; verified target and pending intent preserved")
                        return
                    }
                    let undo = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: killJournal)
                    require(try Data(contentsOf: destination) == bytes, "resume changed published bytes")
                    require(!fm.fileExists(atPath: original.path), "resume did not retain source")
                    require(try fm.contentsOfDirectory(atPath: remote.path).filter { $0.hasPrefix(".OpenCommander-Moved-") }.count == 1,
                        "resume duplicated source retention")
                    if restartPhase == "cross-kill-resume" {
                        print("PASS fresh process reconciles actual SIGKILL after committed mutation without duplicate retention")
                    } else if restartPhase == "cross-kill-undo" {
                        _ = try await PersistentOnlineUndo.undo(undo, client: target, sourceClient: client)
                        require(try Data(contentsOf: original) == bytes, "kill recovery Undo lost original source")
                        if replacing { require(try Data(contentsOf: destination) == old, "kill recovery Undo lost previous target") }
                        else { require(!fm.fileExists(atPath: destination.path), "kill recovery Undo left published target") }
                        try PendingCrossCloudMove.finish(job, root: killJournal)
                        require(try PendingCrossCloudMove.pending(root: killJournal).isEmpty, "kill recovery journal not finished")
                        print("PASS actual-kill recovery two-sided Undo and explicit journal cleanup")
                    } else { fatalError("unknown kill phase") }
                }
                return
            }
            if restartPhase.hasPrefix("cross-") && restartPhase != "cross-undo-confirm" {
                let profileURL = fixture.appendingPathComponent("cross-target.json")
                let targetProfile: CloudConnection
                if fm.fileExists(atPath: profileURL.path) { targetProfile = try JSONDecoder().decode(CloudConnection.self, from: Data(contentsOf: profileURL)) }
                else {
                    targetProfile = CloudConnection(name: "Restart target", kind: "drive", remote: "second", configPath: "/private/tmp/second.conf")
                    try JSONEncoder().encode(targetProfile).write(to: profileURL, options: .atomic)
                }
                let target = CloudFileClient(targetProfile, transport: transport)
                let crossJournal = fixture.appendingPathComponent("cross-journal")
                if restartPhase == "cross-replace-prepare" {
                    try bytes.write(to: remote.appendingPathComponent("cross-replace.txt"))
                    try Data("old cross target".utf8).write(to: secondRemote.appendingPathComponent("cross-replace.txt"))
                    let item = try await client.children(of: nil).first { $0.name == "cross-replace.txt" }!
                    let existing = try await target.children(of: nil).first { $0.name == item.name }!
                    _ = try await PendingCrossCloudMove.prepare(item, source: client, target: target, parent: nil, name: item.name,
                        sourceLocation: "source:/" + item.name, destinationLocation: "target:/" + item.name, replacing: existing, root: crossJournal)
                    print("PASS cross replacement intent persists both provider versions before mutation")
                } else if restartPhase == "cross-prepare" {
                    try bytes.write(to: remote.appendingPathComponent("cross-process.txt"))
                    let item = try await client.children(of: nil).first { $0.name == "cross-process.txt" }!
                    _ = try await PendingCrossCloudMove.prepare(item, source: client, target: target, parent: nil,
                        name: "cross-target.txt", sourceLocation: "source:/cross-process.txt", destinationLocation: "target:/cross-target.txt", root: crossJournal)
                    print("PASS process 19 cross-cloud intent before download")
                } else {
                    let job = try PendingCrossCloudMove.pending(root: crossJournal).first!
                    if restartPhase == "cross-replace-fail" {
                        failUploads = true
                        do { _ = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: crossJournal); fatalError("replacement ignored failed upload") } catch {}
                        require(try Data(contentsOf: remote.appendingPathComponent(job.sourceName)) == bytes, "failed replacement retired cloud source")
                        print("PASS interrupted cross replacement retains source and old-target recovery")
                    } else if restartPhase == "cross-replace-resume" {
                        _ = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: crossJournal)
                        require(try Data(contentsOf: secondRemote.appendingPathComponent(job.name)) == bytes, "cross replacement target mismatch")
                        require(!fm.fileExists(atPath: remote.appendingPathComponent(job.sourceName).path), "cross replacement source still visible")
                        print("PASS cross replacement resumes after process loss")
                    } else if restartPhase == "cross-replace-undo" {
                        let undo = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: crossJournal)
                        try JSONEncoder().encode(undo).write(to: fixture.appendingPathComponent("cross-replace-undo.json"), options: .atomic)
                        _ = try await PersistentOnlineUndo.undo(undo, client: target, sourceClient: client)
                        require(try Data(contentsOf: remote.appendingPathComponent(job.sourceName)) == bytes, "cross replacement Undo source mismatch")
                        require(try Data(contentsOf: secondRemote.appendingPathComponent(job.name)) == Data("old cross target".utf8), "cross replacement Undo lost target")
                        try PendingCrossCloudMove.finish(job, root: crossJournal)
                        print("PASS cross replacement restart reconciliation restores both originals")
                    } else if restartPhase == "cross-fail" {
                        failUploads = true
                        do { _ = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: crossJournal); fatalError("cross-process upload failure accepted") } catch {}
                        require(try Data(contentsOf: remote.appendingPathComponent(job.sourceName)) == bytes, "interrupted cross move lost source")
                        print("PASS process 20 cross-cloud upload failure preserves source and staging")
                    } else if restartPhase == "cross-resume" {
                        _ = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: crossJournal)
                        require(try Data(contentsOf: secondRemote.appendingPathComponent(job.name)) == bytes, "cross restart target mismatch")
                        print("PASS process 21 cross-cloud resume publishes target and retains source")
                    } else if restartPhase == "cross-undo" {
                        let undo = try await PendingCrossCloudMove.resume(job, source: client, target: target, root: crossJournal)
                        _ = try await PersistentOnlineUndo.undo(undo, client: target, sourceClient: client)
                        require(try Data(contentsOf: remote.appendingPathComponent(job.sourceName)) == bytes, "cross restart Undo mismatch")
                        try PendingCrossCloudMove.finish(job, root: crossJournal)
                        print("PASS process 22 cross-cloud retained source reconciliation and Undo")
                    } else { fatalError("Unknown cross restart phase") }
                }
                return
            }
            if restartPhase == "replacement-undo-confirm" || restartPhase == "cross-undo-confirm" {
                let cross = restartPhase == "cross-undo-confirm"
                let file = fixture.appendingPathComponent(cross ? "cross-replace-undo.json" : "replacement-move-undo.json")
                let undo = try JSONDecoder().decode(CloudUndoPayload.self, from: Data(contentsOf: file))
                let target: CloudFileClient
                if cross {
                    let targetProfile = try JSONDecoder().decode(CloudConnection.self, from: Data(contentsOf: fixture.appendingPathComponent("cross-target.json")))
                    target = CloudFileClient(targetProfile, transport: transport)
                } else { target = client }
                let writes = requests.filter { !["list", "download"].contains($0) }.count
                _ = try await PersistentOnlineUndo.undo(undo, client: target, sourceClient: cross ? client : nil)
                require(requests.filter { !["list", "download"].contains($0) }.count == writes, "completed replacement Undo replayed mutation after restart")
                print("PASS completed replacement Undo reconciles after process loss with zero writes")
            } else if restartPhase == "prepare" {
                try fm.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
                try bytes.write(to: source.appendingPathComponent("done.txt"))
                try bytes.write(to: source.appendingPathComponent("nested/pending.txt"))
                let job = try await PendingCloudUpload.prepare(source, source: source.path, client: client,
                    parent: nil, account: client.accountIdentity(), root: journal)
                try await client.createFolder(job.name, parent: nil)
                let target = try await client.children(of: nil).first { $0.name == job.name }!
                try await client.uploadTree(source.appendingPathComponent("done.txt"), parent: target.id)
                try fm.removeItem(at: source)
                print("PASS process 1 persisted partially uploaded folder; original source removed")
            } else if restartPhase == "resume" {
                let jobs = try PendingCloudUpload.pending(root: journal)
                require(jobs.count == 1, "restart lost journal")
                let undo = try await PendingCloudUpload.resume(jobs[0], client: client, root: journal)
                require(undo == nil, "partial recovery claimed destructive ownership")
                require(try Data(contentsOf: remote.appendingPathComponent("Restart folder/nested/pending.txt")) == bytes, "restart bytes differ")
                require(try Data(contentsOf: remote.appendingPathComponent("Restart folder/done.txt")) == bytes, "completed bytes changed")
                // Leave the journal intentionally: next process models termination
                // after remote success but before local checkpoint cleanup.
                print("PASS process 2 resumed missing descendants without original source")
            } else if restartPhase == "reconcile" {
                let job = try PendingCloudUpload.pending(root: journal).first!
                require(try await PendingCloudUpload.resume(job, client: client, root: journal) == nil, "ambiguous success acquired Undo")
                try PendingCloudUpload.finish(job, root: journal)
                require(try PendingCloudUpload.pending(root: journal).isEmpty, "completed journal remains")
                print("PASS process 3 reconciled remote success after restart without duplicate writes")
            } else if restartPhase == "download-prepare" {
                let target = fixture.appendingPathComponent("download-target")
                try fm.createDirectory(at: target, withIntermediateDirectories: false)
                let item = try await client.children(of: nil).first { $0.name == "Restart folder" }!
                _ = try await PendingCloudDownload.prepare(item, client: client, destination: target, root: journal)
                print("PASS process 4 persisted download intent before network transfer")
            } else if restartPhase == "download-resume" {
                let job = try PendingCloudDownload.pending(root: journal).first!
                let freshItem = try await client.restoreReference(job.itemID, path: job.itemPath)
                let reused = try await PendingCloudDownload.prepare(freshItem, client: client, destination: PendingCloudDownload.destination(job), root: journal)
                let pendingCount = try PendingCloudDownload.pending(root: journal).count
                require(reused.id == job.id && pendingCount == 1, "restart with session-local IDs duplicated download journal")
                let downloaded = try await PendingCloudDownload.resume(job, client: client, root: journal)
                require(try Data(contentsOf: downloaded.appendingPathComponent("nested/pending.txt")) == bytes, "resumed download differs")
                print("PASS process 5 downloaded persisted folder intent and saved verified payload")
            } else if restartPhase == "download-reconcile" {
                let job = try PendingCloudDownload.pending(root: journal).first!
                let current = try await client.restoreReference(job.itemID, path: job.itemPath)
                _ = try await client.remoteSnapshot(current)
                let verificationDownloads = requests.filter { $0 == "download" }.count
                requests.removeAll()
                let downloaded = try await PendingCloudDownload.resume(job, client: client, root: journal)
                require(requests.filter { $0 == "download" }.count == verificationDownloads, "completed staging downloaded beyond source verification")
                require(try Data(contentsOf: downloaded.appendingPathComponent("nested/pending.txt")) == bytes, "retained download differs")
                try Data("changed source".utf8).write(to: remote.appendingPathComponent("Restart folder/done.txt"))
                do { _ = try await PendingCloudDownload.resume(job, client: client, root: journal); fatalError("changed remote source accepted") } catch {}
                try bytes.write(to: remote.appendingPathComponent("Restart folder/done.txt"))
                try Data("tampered staging".utf8).write(to: downloaded.appendingPathComponent("done.txt"))
                do { _ = try await PendingCloudDownload.resume(job, client: client, root: journal); fatalError("tampered staged content accepted") } catch {}
                let destination = URL(fileURLWithPath: job.directory)
                try fm.moveItem(at: destination, to: fixture.appendingPathComponent("original-download-target"))
                try fm.createDirectory(at: destination, withIntermediateDirectories: false)
                do { _ = try PendingCloudDownload.destination(job); fatalError("replacement destination directory accepted") } catch {}
                try PendingCloudDownload.finish(job, root: journal)
                print("PASS process 6 reused verified payload; changed source, staging and destination refused")
            } else if restartPhase == "move-prepare" {
                let source = local.appendingPathComponent("restart-local-move.txt")
                try bytes.write(to: source)
                try await client.upload(source, parent: nil)
                let proof = try await PersistentOnlineUndo.uploaded(client, parent: nil, name: source.lastPathComponent,
                    content: RemoteContent.snapshotAsync(source), account: client.accountIdentity())
                _ = try await PendingLocalCloudMove.prepare(source, uploaded: proof, destinationLocation: "cloud:/restart-local-move.txt",
                    root: fixture.appendingPathComponent("local-moves"))
                let item = try await client.children(of: nil).first { $0.name == source.lastPathComponent }!
                let target = local.appendingPathComponent("restart-online-move.txt")
                try bytes.write(to: target)
                _ = try await PendingOnlineMove.prepare(client, item: item, content: RemoteContent.snapshotAsync(source),
                    local: FileUndoRecord(source: source, destination: target, replacedBackup: nil),
                    sourceLocation: "cloud:/restart-local-move.txt", destinationLocation: target.path,
                    root: fixture.appendingPathComponent("online-moves"))
                print("PASS process 7 published independent local and online source-retention intents")
            } else if restartPhase == "move-rename" {
                let localJob = try PendingLocalCloudMove.pending(root: fixture.appendingPathComponent("local-moves")).first!
                try fm.moveItem(at: URL(fileURLWithPath: localJob.original), to: localJob.recovery)
                let onlineJob = try PendingOnlineMove.pending(root: fixture.appendingPathComponent("online-moves")).first!
                let item = try await client.restoreReference(onlineJob.source.id, path: onlineJob.source.path)
                try await client.move(item, parent: nil, name: onlineJob.recoveryName)
                print("PASS process 8 retained sources without saving completion, simulating abrupt termination")
            } else if restartPhase == "move-resume" {
                let onlineRoot = fixture.appendingPathComponent("online-moves")
                let onlineJob = try PendingOnlineMove.pending(root: onlineRoot).first!
                let undo = try await PendingOnlineMove.resume(onlineJob, client: client)
                require(!requests.contains("rename"), "move restart replayed completed online rename")
                _ = try await PersistentOnlineUndo.undo(undo, client: client)
                try PendingOnlineMove.finish(onlineJob, root: onlineRoot)
                let localRoot = fixture.appendingPathComponent("local-moves")
                let localJob = try PendingLocalCloudMove.pending(root: localRoot).first!
                let localUndo = try await PendingLocalCloudMove.resume(localJob, client: client)
                _ = try await PersistentOnlineUndo.undo(localUndo, client: client)
                require(try Data(contentsOf: URL(fileURLWithPath: localJob.original)) == bytes, "move restart lost original bytes")
                try PendingLocalCloudMove.finish(localJob, root: localRoot)
                print("PASS process 9 reconciled both source retentions and verified durable Undo")
            } else if restartPhase == "receipt-prepare" {
                let source = local.appendingPathComponent("receipt-restart.txt")
                try bytes.write(to: source)
                let job = try await PendingCloudUpload.prepare(source, source: source.path, client: client,
                    parent: nil, account: client.accountIdentity(), root: journal)
                let proof = try await PendingCloudUpload.resume(job, client: client, root: journal)
                require(proof != nil, "completed upload has no receipt")
                try fm.removeItem(at: source)
                print("PASS process 10 saved verified upload receipt before history completion")
            } else if restartPhase == "receipt-resume" {
                let job = try PendingCloudUpload.pending(root: journal).first!
                let proof = try await PendingCloudUpload.resume(job, client: client, root: journal)
                require(proof != nil, "process restart lost verified upload ownership")
                require(!requests.contains("upload"), "receipt recovery uploaded again")
                require(try Data(contentsOf: remote.appendingPathComponent(job.name)) == bytes, "receipt recovery changed bytes")
                _ = try await PersistentOnlineUndo.undo(proof!, client: client)
                require(!fm.fileExists(atPath: remote.appendingPathComponent(job.name).path), "recovered Undo did not retire target")
                try PendingCloudUpload.finish(job, root: journal)
                print("PASS process 11 recovered verified ownership and Undo without source or duplicate upload")
            } else if restartPhase == "early-move-prepare" {
                let source = local.appendingPathComponent("early-process-move.txt")
                try bytes.write(to: source)
                _ = try await PendingCloudUpload.prepare(source, source: source.path, client: client,
                    parent: nil, account: client.accountIdentity(), moveOriginal: source,
                    moveDestination: "cloud:/early-process-move.txt", root: journal)
                require(!fm.fileExists(atPath: remote.appendingPathComponent(source.lastPathComponent).path), "preparation published destination")
                print("PASS process 12 persisted move intent before any upload")
            } else if restartPhase == "early-move-upload" {
                let job = try PendingCloudUpload.pending(root: journal).first!
                _ = try await PendingCloudUpload.resume(job, client: client, root: journal)
                require(fm.fileExists(atPath: job.moveIntent!.original), "upload receipt removed original")
                print("PASS process 13 uploaded after restart without retiring source")
            } else if restartPhase == "early-move-retain" {
                let job = try PendingCloudUpload.pending(root: journal).first!
                _ = try await PendingCloudUpload.resumeMove(job, client: client, root: journal)
                require(!fm.fileExists(atPath: job.moveIntent!.original), "move did not retain source")
                print("PASS process 14 resumed move from durable upload receipt")
            } else if restartPhase == "early-move-undo" {
                let job = try PendingCloudUpload.pending(root: journal).first!
                let undo = try await PendingCloudUpload.resumeMove(job, client: client, root: journal)
                _ = try await PersistentOnlineUndo.undo(undo, client: client)
                require(try Data(contentsOf: URL(fileURLWithPath: job.moveIntent!.original)) == bytes, "cross-process move Undo lost source")
                try PendingCloudUpload.finish(job, root: journal)
                print("PASS process 15 reconciled source retention and restored original via Undo")
            } else if restartPhase == "replacement-move-prepare" {
                let seed = local.appendingPathComponent("replacement-process.txt")
                try Data("previous cloud destination".utf8).write(to: seed)
                try await client.upload(seed, parent: nil)
                let existing = try await client.children(of: nil).first { $0.name == seed.lastPathComponent }!
                try bytes.write(to: seed)
                _ = try await PendingCloudReplacement.prepare(seed, sourceLocation: seed.path, existing: existing, client: client,
                    parent: nil, moveOriginal: seed, moveDestination: "cloud:/replacement-process.txt", root: journal)
                print("PASS persisted replacement move intent before target displacement")
            } else if restartPhase == "replacement-move-resume" {
                let job = try PendingCloudReplacement.pending(root: journal).first!
                _ = try await PendingCloudReplacement.resumeMove(job, client: client, root: journal)
                require(!fm.fileExists(atPath: job.moveIntent!.original), "replacement move left visible local source")
                require(try Data(contentsOf: remote.appendingPathComponent(job.upload.name)) == bytes, "replacement move published wrong bytes")
                print("PASS replacement move resumed after process restart")
            } else if restartPhase == "replacement-move-undo" {
                let job = try PendingCloudReplacement.pending(root: journal).first!
                let undo = try await PendingCloudReplacement.resumeMove(job, client: client, root: journal)
                try JSONEncoder().encode(undo).write(to: fixture.appendingPathComponent("replacement-move-undo.json"), options: .atomic)
                _ = try await PersistentOnlineUndo.undo(undo, client: client)
                require(try Data(contentsOf: URL(fileURLWithPath: job.moveIntent!.original)) == bytes, "replacement move Undo lost local original")
                require(try Data(contentsOf: remote.appendingPathComponent(job.upload.name)) == Data("previous cloud destination".utf8), "replacement move Undo lost cloud destination")
                try PendingCloudReplacement.finish(job, root: journal)
                print("PASS replacement move restart reconciliation and two-sided Undo")
            } else if restartPhase == "early-download-prepare" {
                let source = local.appendingPathComponent("early-process-download.txt")
                try bytes.write(to: source)
                try await client.upload(source, parent: nil)
                let item = try await client.children(of: nil).first { $0.name == source.lastPathComponent }!
                let target = fixture.appendingPathComponent("move-download-target")
                try fm.createDirectory(at: target, withIntermediateDirectories: false)
                try Data("previous destination".utf8).write(to: target.appendingPathComponent(source.lastPathComponent))
                _ = try await PendingCloudDownload.prepare(item, client: client, destination: target, move: true, root: journal)
                print("PASS process 16 persisted cloud-local move before download")
            } else if restartPhase == "early-download-publish" {
                let job = try PendingCloudDownload.pending(root: journal).first!
                let payload = try await PendingCloudDownload.resume(job, client: client, root: journal)
                let target = try PendingCloudDownload.destination(job).appendingPathComponent(job.name)
                let backup = try SafeFileOperations.copyReplacing(source: payload, destination: target, replace: true)
                let record = FileUndoRecord(source: payload, destination: target, replacedBackup: backup)
                _ = try await PendingCloudDownload.completeMove(job, client: client, record: record,
                    sourceLocation: "cloud:/" + job.name, root: journal)
                print("PASS process 17 resumed download, published local copy and retained cloud original")
            } else if restartPhase == "early-download-undo" {
                let job = try PendingCloudDownload.pending(root: journal).first!
                let undo = try await PendingCloudDownload.completeMove(job, client: client,
                    sourceLocation: "cloud:/" + job.name, root: journal)
                _ = try await PersistentOnlineUndo.undo(undo, client: client)
                require(try Data(contentsOf: remote.appendingPathComponent(job.name)) == bytes, "download restart Undo lost original")
                require(try Data(contentsOf: PendingCloudDownload.destination(job).appendingPathComponent(job.name)) == Data("previous destination".utf8), "restart replacement Undo lost previous local target")
                try PendingCloudDownload.finish(job, root: journal)
                print("PASS process 18 reconciled published download move and restored cloud original")
            } else { fatalError("Unknown restart phase") }
        }
        if let restartPhase { try await runRestartPhase(restartPhase); return }
        var unicodeName = "Prüfung.txt".precomposedStringWithCanonicalMapping
        let unicodeProfile = CloudConnection(name: "Unicode fixture", kind: "drive", remote: "synthetic", configPath: "/private/tmp/test.conf")
        let unicodeClient = CloudFileClient(unicodeProfile, transport: { _, _, operation, path, _, localURL, callback in
            do {
                if operation == "list" {
                    callback(try JSONSerialization.data(withJSONObject: [["Name": unicodeName, "Path": unicodeName, "Size": 3, "IsDir": false, "ID": "unicode-fixture"]]), nil)
                } else if operation == "download" {
                    require(Array(path.utf8) == Array(unicodeName.utf8), "download did not use provider-exact Unicode spelling")
                    try Data("abc".utf8).write(to: localURL!)
                    callback(Data(), nil)
                } else { fatalError("unexpected Unicode fixture operation") }
            } catch { callback(nil, error as NSError) }
        })
        let unicodeBefore = try await unicodeClient.children(of: nil)[0]
        unicodeName = unicodeName.decomposedStringWithCanonicalMapping
        let unicodeAfter = try await unicodeClient.children(of: nil)[0]
        require(unicodeBefore.id == unicodeAfter.id, "Unicode spelling refresh changed stable reference")
        let unicodeDownload = try await unicodeClient.download(unicodeBefore)
        require(try Data(contentsOf: unicodeDownload) == Data("abc".utf8), "Unicode download content mismatch")
        try fm.removeItem(at: unicodeDownload.deletingLastPathComponent())
        print("PASS provider-exact Unicode spelling refresh with stable reference and verified download")
        var batchAttempts: [Int] = [], batchFailures: [Int] = []
        let failedCount = try await OnlineBatch.run([1, 2, 3, 4], operation: { value in
            batchAttempts.append(value)
            if value == 2 || value == 4 { throw CocoaError(.fileReadNoSuchFile) }
        }, failed: { value, _ in batchFailures.append(value) })
        require(batchAttempts == [1, 2, 3, 4] && batchFailures == [2, 4] && failedCount == 2,
                "batch must identify failures exactly and continue independent items without replay")
        for cancellation in [CancellationError() as Error, URLError(.cancelled), CocoaError(.userCancelled)] {
            batchAttempts = []; batchFailures = []
            do {
                _ = try await OnlineBatch.run([1, 2, 3], operation: { value in
                    batchAttempts.append(value)
                    if value == 2 { throw cancellation }
                }, failed: { value, _ in batchFailures.append(value) })
                fatalError("batch swallowed cancellation")
            } catch is CancellationError {} catch { fatalError("batch did not normalize cancellation") }
            require(batchAttempts == [1, 2] && batchFailures.isEmpty, "cancelled batch continued or reported duplicate failure")
        }
        let emptyFailures = try await OnlineBatch.run([Int](), operation: { _ in fatalError("empty batch ran") }, failed: { _, _ in fatalError("empty batch failed") })
        require(emptyFailures == 0, "empty batch failure count")
        print("PASS independent batch exact per-item failures, no replay, continuation and Swift/URL/Cocoa cancellation")
        let file = local.appendingPathComponent("Grüsse: Drive\\Name.txt")
        let content = Data("synthetic data, not personal cloud content".utf8)
        try content.write(to: file)
        try await client.uploadTree(file, parent: nil)
        let listing = try await client.children(of: nil)
        require(listing.count == 1 && listing[0].name == file.lastPathComponent, "cloud names or upload publication changed")
        let item = listing[0]
        require(!requests.contains("link"), "listing or upload changed sharing without an explicit request")
        let sharingURL = try await client.createPublicShareLink(item)
        require(sharingURL.host == "drive.google.com" && requests.filter { $0 == "link" }.count == 1, "explicit link request was not bounded to one mutation")
        for value in ["http://drive.google.com/test", "https://drive.google.com.evil.invalid/test", "https://user:password@drive.google.com/test", "file:///tmp/test", String(repeating: "x", count: 8193)] {
            do { _ = try CloudFileClient.sharingURL(Data(value.utf8), kind: "drive"); fatalError("unsafe sharing response accepted") } catch {}
        }
        require(try CloudFileClient.sharingURL(Data("https://www.dropbox.com/scl/fi/synthetic/test".utf8), kind: "dropbox").host == "www.dropbox.com", "Dropbox sharing URL refused")
        require(try CloudFileClient.sharingURL(Data("https://example.sharepoint.com/:u:/synthetic".utf8), kind: "onedrive").host == "example.sharepoint.com", "OneDrive business sharing URL refused")
        do { _ = try RcloneCommandPlan.arguments(profile: profile, operation: "link", path: ""); fatalError("whole-account link accepted") } catch {}
        var noSharing = profile; noSharing.kind = "iclouddrive"
        do { _ = try RcloneCommandPlan.arguments(profile: noSharing, operation: "link", path: "test"); fatalError("unsupported sharing provider accepted") } catch {}
        print("PASS explicit-only cloud public-link command, bounded HTTPS provider URL validation, root and unsupported-provider refusal")
        let downloaded = try await client.download(item)
        defer { try? fm.removeItem(at: downloaded.deletingLastPathComponent()) }
        let copied = try Data(contentsOf: downloaded)
        require(copied == content, "cloud download differs")
        print("PASS cloud transport adapter: Unicode/colon/backslash names, upload readback, publication and verified download")
        try await client.createFolder("Ziel", parent: nil)
        let destination = try await client.children(of: nil).first { $0.name == "Ziel" }!
        try await client.move(item, parent: destination.id, name: "Neu.txt")
        require(!fm.fileExists(atPath: remote.appendingPathComponent(file.lastPathComponent).path), "cloud move left original visible")
        require(fm.fileExists(atPath: remote.appendingPathComponent("Ziel/Neu.txt").path), "cloud move destination missing")
        let saved = try fm.contentsOfDirectory(at: remote, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".OpenCommander-Recovery-") }!
        require(try Data(contentsOf: saved) == content, "cloud move backup differs")
        require(client.moveBackupLocation?.contains(saved.lastPathComponent) == true, "cloud recovery location unavailable")
        print("PASS cloud move keeps and verifies original recovery copy before reporting success")
        let changed = try await client.children(of: destination.id)[0]
        try Data("changed".utf8).write(to: remote.appendingPathComponent("Ziel/Neu.txt"))
        let before = requests.count
        do { try await client.move(changed, parent: nil, name: "stale.txt"); fatalError("stale move accepted") } catch {}
        require(!requests.dropFirst(before).contains("rename"), "stale source was renamed")
        require(!fm.fileExists(atPath: remote.appendingPathComponent("stale.txt").path), "stale move target published")
        let fresh = try await client.children(of: destination.id).first { $0.name == "Neu.txt" }!
        let deletionUndo = try await PersistentOnlineUndo.cloudRecoveryDelete(client, item: fresh)
        require(!fm.fileExists(atPath: remote.appendingPathComponent("Ziel/Neu.txt").path), "recycle did not remove original name")
        let recovered = try fm.contentsOfDirectory(atPath: remote.appendingPathComponent("Ziel").path)
        require(recovered.count == 1 && recovered[0].hasPrefix(".OpenCommander-Recovery-"), "recycle did not retain data")
        print("PASS stale version refuses rename; cloud removal retains recoverable original")
        let savedDeletionUndo = try JSONDecoder().decode(CloudUndoPayload.self, from: JSONEncoder().encode(deletionUndo))
        let reopenedDeletionClient = CloudFileClient(profile, transport: transport)
        let deletedOriginal = remote.appendingPathComponent("Ziel/Neu.txt")
        try Data("later file at original name".utf8).write(to: deletedOriginal)
        do { _ = try await PersistentOnlineUndo.undo(savedDeletionUndo, client: reopenedDeletionClient); fatalError("delete Undo overwrote an occupied original") } catch {}
        require(try Data(contentsOf: deletedOriginal) == Data("later file at original name".utf8), "delete Undo changed collision")
        try fm.removeItem(at: deletedOriginal)
        _ = try await PersistentOnlineUndo.undo(savedDeletionUndo, client: reopenedDeletionClient)
        require(try Data(contentsOf: deletedOriginal) == Data("changed".utf8), "restart delete Undo lost original bytes")
        print("PASS recoverable cloud deletion Undo survives new client/reference serialization and refuses an occupied original")
        let nativeURL = remote.appendingPathComponent("NativeDocument.docx")
        try content.write(to: nativeURL); unknownNames.insert(nativeURL.lastPathComponent)
        let native = try await client.children(of: nil).first { $0.name == nativeURL.lastPathComponent }!
        require(native.size == nil, "unknown export was presented as empty content")
        let exported = try await client.download(native)
        require(try Data(contentsOf: exported) == content, "Google native document export differs")
        try fm.removeItem(at: exported.deletingLastPathComponent())
        require(requests.last == "list" && requests.contains("export"), "native export did not verify source version")
        let exportPlan = try RcloneCommandPlan.arguments(profile: profile, operation: "export", path: native.name, local: local.appendingPathComponent(native.name))
        require(exportPlan.contains("--max-transfer") && exportPlan.contains("256Mi") && exportPlan.contains("HARD"), "native export must be bounded")
        var nonGoogle = profile; nonGoogle.kind = "onedrive"
        do { _ = try RcloneCommandPlan.arguments(profile: nonGoogle, operation: "export", path: native.name, local: exported); fatalError("other provider treated as native Google export") } catch {}
        let unknownBefore = requests.count
        do { try await client.move(native, parent: destination.id, name: "converted.docx"); fatalError("unknown move accepted") } catch {}
        do { try await client.recycle(native); fatalError("unknown removal accepted") } catch {}
        require(!requests.dropFirst(unknownBefore).contains { ["download", "copy", "rename", "upload"].contains($0) }, "unknown export caused a content change")
        require(try Data(contentsOf: nativeURL) == content, "native document changed")
        changeDuringExport = true
        do { _ = try await client.download(native); fatalError("changed native document was exported successfully") } catch {}
        require(!fm.fileExists(atPath: exportOutputs.last!.deletingLastPathComponent().path), "changed export left private staging behind")
        changeDuringExport = false
        try content.write(to: nativeURL)
        failExports = true
        do { _ = try await client.download(native); fatalError("cancelled native export succeeded") } catch {}
        require(!fm.fileExists(atPath: exportOutputs.last!.deletingLastPathComponent().path), "cancelled export left staging behind")
        failExports = false
        try await client.createFolder("Native Folder", parent: nil)
        let nativeFolder = try await client.children(of: nil).first { $0.name == "Native Folder" }!
        let nativeChild = remote.appendingPathComponent("Native Folder/Sheet.xlsx")
        try content.write(to: nativeChild); unknownNames.insert("Sheet.xlsx")
        let exportedFolder = try await client.downloadTree(nativeFolder)
        require(try Data(contentsOf: exportedFolder.appendingPathComponent("Sheet.xlsx")) == content, "recursive native export differs")
        try fm.removeItem(at: exportedFolder.deletingLastPathComponent())
        let beforeFolderMove = requests.count
        do { try await client.move(nativeFolder, parent: destination.id, name: "Moved Native Folder"); fatalError("folder containing native original was destructively moved") } catch {}
        require(!requests.dropFirst(beforeFolderMove).contains { ["copy", "rename", "upload"].contains($0) }, "native folder move mutated original")
        let invalidData = try JSONSerialization.data(withJSONObject: ["Name": "invalid", "Path": "invalid", "Size": -2, "IsDir": false])
        do { try JSONDecoder().decode(RcloneListingItem.self, from: invalidData).validate(); fatalError("invalid negative size accepted") } catch {}
        print("PASS Google native document bounded export; other providers refused; original protected from destructive move/removal")
        let secondProfile = CloudConnection(name: "Second Test Account", kind: "drive", remote: "second", configPath: "/private/tmp/second.conf")
        let secondClient = CloudFileClient(secondProfile, transport: transport)
        let crossFile = local.appendingPathComponent("CrossAccount.txt")
        try content.write(to: crossFile)
        try await client.upload(crossFile, parent: nil)
        let crossSource = try await client.children(of: nil).first { $0.name == crossFile.lastPathComponent }!
        let crossContent = try await CommanderOnlineTools.contentSnapshot(client, item: crossSource)
        try await secondClient.upload(crossFile, parent: nil)
        let targetUndo = try await PersistentOnlineUndo.uploaded(secondClient, parent: nil, name: crossSource.name, content: crossContent, account: secondClient.accountIdentity())
        let retainedSource = try await PersistentOnlineUndo.retainMoveSource(client, item: crossSource, content: crossContent, account: client.accountIdentity())
        let crossUndo = try PersistentOnlineUndo.crossMove(targetUndo, source: retainedSource)
        let savedCrossUndo = try JSONEncoder().encode(crossUndo)
        let restoredCrossUndo = try JSONDecoder().decode(CloudUndoPayload.self, from: savedCrossUndo)
        do { _ = try await PersistentOnlineUndo.undo(restoredCrossUndo, client: secondClient, sourceClient: secondClient); fatalError("cross-account undo accepted wrong source account") } catch {}
        require(fm.fileExists(atPath: secondRemote.appendingPathComponent(crossSource.name).path), "wrong account damaged target")
        try Data("occupied".utf8).write(to: remote.appendingPathComponent(crossSource.name))
        do { _ = try await PersistentOnlineUndo.undo(restoredCrossUndo, client: secondClient, sourceClient: client); fatalError("cross-account undo overwrote source collision") } catch {}
        require(try Data(contentsOf: secondRemote.appendingPathComponent(crossSource.name)) == content, "source collision damaged target")
        try fm.removeItem(at: remote.appendingPathComponent(crossSource.name))
        _ = try await PersistentOnlineUndo.undo(restoredCrossUndo, client: secondClient, sourceClient: client)
        require(try Data(contentsOf: remote.appendingPathComponent(crossSource.name)) == content, "cross-account undo did not restore source")
        require(!fm.fileExists(atPath: secondRemote.appendingPathComponent(crossSource.name).path), "cross-account undo left target visible")
        print("PASS persistent cross-account move Undo restores source, retains destination recovery, refuses wrong accounts and occupied source names")
        let localMoveSource = local.appendingPathComponent("local-move-proof.txt")
        let localRecovery = local.appendingPathComponent("retained-local-move-proof.txt")
        try content.write(to: localMoveSource)
        try await client.uploadTree(localMoveSource, parent: nil)
        let uploadedLocalMove = try await PersistentOnlineUndo.uploaded(client, parent: nil, name: localMoveSource.lastPathComponent,
            content: RemoteContent.snapshotAsync(localMoveSource), account: client.accountIdentity())
        try fm.moveItem(at: localMoveSource, to: localRecovery)
        let localMoveUndo = try await PersistentOnlineUndo.localMove(uploadedLocalMove, original: localMoveSource, recovery: localRecovery)
        let reloadedLocalUndo = try JSONDecoder().decode(CloudUndoPayload.self, from: JSONEncoder().encode(localMoveUndo))
        try Data("occupied local path".utf8).write(to: localMoveSource)
        do { _ = try await PersistentOnlineUndo.undo(reloadedLocalUndo, client: client); fatalError("local move Undo overwrote occupied source") } catch {}
        require(fm.fileExists(atPath: remote.appendingPathComponent(localMoveSource.lastPathComponent).path), "failed local restore removed cloud copy")
        try fm.removeItem(at: localMoveSource)
        try Data("changed recovery".utf8).write(to: localRecovery)
        do { _ = try await PersistentOnlineUndo.undo(reloadedLocalUndo, client: client); fatalError("local move Undo accepted changed recovery") } catch {}
        try content.write(to: localRecovery)
        _ = try await PersistentOnlineUndo.undo(reloadedLocalUndo, client: client)
        require(try Data(contentsOf: localMoveSource) == content, "local move Undo did not restore bytes")
        require(fm.fileExists(atPath: localRecovery.path), "local move Undo discarded recovery")
        require(!fm.fileExists(atPath: remote.appendingPathComponent(localMoveSource.lastPathComponent).path), "local move Undo left cloud target visible")
        print("PASS persistent local-to-cloud move Undo restores source first; collision and changed recovery preserve cloud copy")
        let onlineMoveSeed = local.appendingPathComponent("online-move-seed.txt")
        let downloadedMove = local.appendingPathComponent("online-move-downloaded.txt")
        try content.write(to: onlineMoveSeed)
        try await client.uploadTree(onlineMoveSeed, parent: nil)
        let onlineMoveItem = try await client.children(of: nil).first { $0.name == onlineMoveSeed.lastPathComponent }!
        try fm.copyItem(at: onlineMoveSeed, to: downloadedMove)
        let copiedRecord = FileUndoRecord(source: onlineMoveSeed, destination: downloadedMove, replacedBackup: nil)
        let movedProof = try await PersistentOnlineUndo.retainMoveSource(client, item: onlineMoveItem,
            content: RemoteContent.snapshotAsync(onlineMoveSeed), account: client.accountIdentity())
        let downloadUndo = try PersistentOnlineUndo.downloadMove(movedProof, local: copiedRecord)
        let restoredDownloadUndo = try JSONDecoder().decode(CloudUndoPayload.self, from: JSONEncoder().encode(downloadUndo))
        try Data("occupied online name".utf8).write(to: remote.appendingPathComponent(onlineMoveSeed.lastPathComponent))
        do { _ = try await PersistentOnlineUndo.undo(restoredDownloadUndo, client: client); fatalError("download move Undo overwrote online collision") } catch {}
        require(try Data(contentsOf: downloadedMove) == content, "failed remote restoration displaced local copy")
        try fm.removeItem(at: remote.appendingPathComponent(onlineMoveSeed.lastPathComponent))
        _ = try await PersistentOnlineUndo.undo(restoredDownloadUndo, client: client)
        require(try Data(contentsOf: remote.appendingPathComponent(onlineMoveSeed.lastPathComponent)) == content, "download move Undo lost online source")
        require(!fm.fileExists(atPath: downloadedMove.path), "download move Undo retained visible local copy")
        print("PASS persistent cloud-to-local move Undo restores online source before guarded local recovery; collision preserves both copies")
        let moveJournal = local.appendingPathComponent("move-journal")
        let cleanupSeed = local.appendingPathComponent("move-cleanup.txt")
        try content.write(to: cleanupSeed)
        try await client.upload(cleanupSeed, parent: nil)
        try await secondClient.upload(cleanupSeed, parent: nil)
        let cleanupSource = try await client.children(of: nil).first { $0.name == cleanupSeed.lastPathComponent }!
        let cleanupContent = try await RemoteContent.snapshotAsync(cleanupSeed)
        let cleanupTarget = try await PersistentOnlineUndo.uploaded(secondClient, parent: nil, name: cleanupSource.name,
            content: cleanupContent, account: secondClient.accountIdentity())
        let cleanupJob = try await PendingOnlineMove.prepare(client, item: cleanupSource, content: cleanupContent,
            uploaded: cleanupTarget, sourceLocation: "source:/move-cleanup.txt", destinationLocation: "target:/move-cleanup.txt", root: moveJournal)
        let cleanupReloaded = try PendingOnlineMove.pending(root: moveJournal).first!
        require(cleanupReloaded.id == cleanupJob.id, "move cleanup intent lost on reload")
        do { _ = try await PendingOnlineMove.resume(cleanupReloaded, client: secondClient, targetClient: secondClient); fatalError("move cleanup accepted wrong source account") } catch {}
        try Data("changed target".utf8).write(to: secondRemote.appendingPathComponent(cleanupSource.name))
        do { _ = try await PendingOnlineMove.resume(cleanupReloaded, client: client, targetClient: secondClient); fatalError("move cleanup accepted changed target") } catch {}
        require(fm.fileExists(atPath: remote.appendingPathComponent(cleanupSource.name).path), "changed target removed original source")
        try content.write(to: secondRemote.appendingPathComponent(cleanupSource.name))
        // Simulate a server-side rename that succeeded just before process loss.
        try await client.move(cleanupSource, parent: nil, name: cleanupJob.recoveryName)
        let beforeCleanupRetry = requests.filter { $0 == "rename" }.count
        let cleanupUndo = try await PendingOnlineMove.resume(cleanupReloaded, client: client, targetClient: secondClient)
        _ = try await PendingOnlineMove.resume(cleanupReloaded, client: client, targetClient: secondClient)
        require(requests.filter { $0 == "rename" }.count == beforeCleanupRetry, "move recovery replayed completed rename")
        _ = try await PersistentOnlineUndo.undo(cleanupUndo, client: secondClient, sourceClient: client)
        require(try Data(contentsOf: remote.appendingPathComponent(cleanupSource.name)) == content, "recovered move Undo lost original")
        try PendingOnlineMove.finish(cleanupReloaded, root: moveJournal)
        require(try PendingOnlineMove.pending(root: moveJournal).isEmpty, "finished move journal retained")
        let localTarget = local.appendingPathComponent("download-cleanup.txt")
        try content.write(to: localTarget)
        let localRecord = FileUndoRecord(source: cleanupSeed, destination: localTarget, replacedBackup: nil)
        let freshCleanupSource = try await client.children(of: nil).first { $0.name == cleanupSource.name }!
        let localCleanup = try await PendingOnlineMove.prepare(client, item: freshCleanupSource, content: cleanupContent,
            local: localRecord, sourceLocation: "source:/move-cleanup.txt", destinationLocation: localTarget.path, root: moveJournal)
        try Data("changed local copy".utf8).write(to: localTarget)
        do { _ = try await PendingOnlineMove.resume(localCleanup, client: client); fatalError("move cleanup accepted changed local destination") } catch {}
        require(fm.fileExists(atPath: remote.appendingPathComponent(cleanupSource.name).path), "changed local target removed source")
        try content.write(to: localTarget)
        do { _ = try await PendingOnlineMove.resume(localCleanup, client: client); fatalError("changed destination metadata accepted") } catch {}
        try PendingOnlineMove.finish(localCleanup, root: moveJournal)
        let freshRecord = FileUndoRecord(source: cleanupSeed, destination: localTarget, replacedBackup: nil)
        let freshLocalCleanup = try await PendingOnlineMove.prepare(client, item: freshCleanupSource, content: cleanupContent,
            local: freshRecord, sourceLocation: "source:/move-cleanup.txt", destinationLocation: localTarget.path, root: moveJournal)
        let localCleanupUndo = try await PendingOnlineMove.resume(freshLocalCleanup, client: client)
        _ = try await PersistentOnlineUndo.undo(localCleanupUndo, client: client)
        require(try Data(contentsOf: remote.appendingPathComponent(cleanupSource.name)) == content, "download cleanup Undo lost source")
        try PendingOnlineMove.finish(freshLocalCleanup, root: moveJournal)
        print("PASS durable online move cleanup reload, wrong account/changed destinations refusal, ambiguous rename reconciliation without replay and cloud/local Undo")
        try await client.upload(cleanupSeed, parent: destination.id)
        var sparseRow = try await client.children(of: destination.id).first { $0.name == cleanupSeed.lastPathComponent }!
        sparseRow.parentReference = nil // Graph children rows may omit it.
        let nestedLocal = local.appendingPathComponent("nested-move-download.txt")
        try content.write(to: nestedLocal)
        let nestedJob = try await PendingOnlineMove.prepare(client, item: sparseRow, content: cleanupContent,
            local: FileUndoRecord(source: cleanupSeed, destination: nestedLocal, replacedBackup: nil),
            sourceLocation: "source:/Ziel/move-cleanup.txt", destinationLocation: nestedLocal.path, root: moveJournal)
        require(nestedJob.source.parent == destination.id, "sparse listing treated nested source as root")
        let nestedMoveUndo = try await PendingOnlineMove.resume(nestedJob, client: client)
        _ = try await PersistentOnlineUndo.undo(nestedMoveUndo, client: client)
        require(try Data(contentsOf: remote.appendingPathComponent("Ziel/move-cleanup.txt")) == content, "nested source restored to wrong parent")
        try PendingOnlineMove.finish(nestedJob, root: moveJournal)
        print("PASS sparse listing source parent resolved from fresh metadata; nested move recovery and Undo retain original folder")
        let localCloudJournal = local.appendingPathComponent("local-cloud-move-journal")
        let localCloudSource = local.appendingPathComponent("local-cloud-restart.txt")
        try content.write(to: localCloudSource)
        try await client.upload(localCloudSource, parent: nil)
        let localCloudTarget = try await PersistentOnlineUndo.uploaded(client, parent: nil, name: localCloudSource.lastPathComponent,
            content: RemoteContent.snapshotAsync(localCloudSource), account: client.accountIdentity())
        let localCloudJob = try await PendingLocalCloudMove.prepare(localCloudSource, uploaded: localCloudTarget,
            destinationLocation: "cloud:/local-cloud-restart.txt", root: localCloudJournal)
        let localCloudReloaded = try PendingLocalCloudMove.pending(root: localCloudJournal).first!
        do { _ = try await PendingLocalCloudMove.resume(localCloudReloaded, client: secondClient); fatalError("local move accepted wrong account") } catch {}
        try Data("changed destination".utf8).write(to: remote.appendingPathComponent(localCloudSource.lastPathComponent))
        do { _ = try await PendingLocalCloudMove.resume(localCloudReloaded, client: client); fatalError("local move accepted changed destination") } catch {}
        require(fm.fileExists(atPath: localCloudSource.path), "changed destination removed local source")
        try content.write(to: remote.appendingPathComponent(localCloudSource.lastPathComponent))
        // Rename completed, then process died before recording History.
        try fm.moveItem(at: localCloudSource, to: localCloudJob.recovery)
        let localCloudUndo = try await PendingLocalCloudMove.resume(localCloudReloaded, client: client)
        _ = try await PendingLocalCloudMove.resume(localCloudReloaded, client: client)
        require(try Data(contentsOf: localCloudJob.recovery) == content, "local move reconciliation lost recovery")
        _ = try await PersistentOnlineUndo.undo(localCloudUndo, client: client)
        require(try Data(contentsOf: localCloudSource) == content, "local move restart Undo lost source")
        try PendingLocalCloudMove.finish(localCloudReloaded, root: localCloudJournal)
        require(try PendingLocalCloudMove.pending(root: localCloudJournal).isEmpty, "local move journal not finished")
        print("PASS durable local-to-cloud move cleanup, destination/account guards, completed rename reconciliation and Undo")
        func testEarlyMoves() async throws {
        let earlyMoveRoot = local.appendingPathComponent("early-move-journal")
        let earlySource = local.appendingPathComponent("early-move.txt")
        try content.write(to: earlySource)
        let earlyJob = try await PendingCloudUpload.prepare(earlySource, source: earlySource.path, client: client,
            parent: nil, account: client.accountIdentity(), moveOriginal: earlySource,
            moveDestination: "cloud:/early-move.txt", root: earlyMoveRoot)
        failUploads = true
        do { _ = try await PendingCloudUpload.resumeMove(earlyJob, client: client, root: earlyMoveRoot); fatalError("failed move upload succeeded") } catch {}
        failUploads = false
        require(try Data(contentsOf: earlySource) == content, "interrupted upload removed source")
        let earlyReloaded = try PendingCloudUpload.pending(root: earlyMoveRoot).first!
        do { _ = try await PendingCloudUpload.resumeMove(earlyReloaded, client: secondClient, root: earlyMoveRoot); fatalError("early move accepted wrong account") } catch {}
        try Data("changed source".utf8).write(to: earlySource)
        do { _ = try await PendingCloudUpload.resumeMove(earlyReloaded, client: client, root: earlyMoveRoot); fatalError("early move accepted changed source") } catch {}
        try content.write(to: earlySource)
        // Rewriting changes the fingerprint: resume must still refuse it.
        do { _ = try await PendingCloudUpload.resumeMove(earlyReloaded, client: client, root: earlyMoveRoot); fatalError("early move ignored source metadata change") } catch {}
        try PendingCloudUpload.finish(earlyReloaded, root: earlyMoveRoot)
        let freshMove = try await PendingCloudUpload.prepare(earlySource, source: earlySource.path, client: client,
            parent: nil, account: client.accountIdentity(), moveOriginal: earlySource,
            moveDestination: "cloud:/early-move.txt", root: earlyMoveRoot)
        let earlyUndo = try await PendingCloudUpload.resumeMove(freshMove, client: client, root: earlyMoveRoot)
        require(!fm.fileExists(atPath: earlySource.path), "successful move retained visible source")
        _ = try await PendingCloudUpload.resumeMove(freshMove, client: client, root: earlyMoveRoot)
        _ = try await PersistentOnlineUndo.undo(earlyUndo, client: client)
        require(try Data(contentsOf: earlySource) == content, "early move Undo lost original")
        try PendingCloudUpload.finish(freshMove, root: earlyMoveRoot)
        print("PASS early local-cloud move interruption, source/account guards, retention reconciliation and Undo")
        let downMoveRoot = local.appendingPathComponent("early-download-move-journal")
        let downMoveTarget = local.appendingPathComponent("early-download-target")
        try fm.createDirectory(at: downMoveTarget, withIntermediateDirectories: false)
        let downMoveSeed = local.appendingPathComponent("early-download-move.txt")
        try content.write(to: downMoveSeed)
        try await client.upload(downMoveSeed, parent: nil)
        let downMoveItem = try await client.children(of: nil).first { $0.name == downMoveSeed.lastPathComponent }!
        _ = try await PendingCloudDownload.prepare(downMoveItem, client: client, destination: downMoveTarget, move: true, root: downMoveRoot)
        let downMoveJob = try PendingCloudDownload.pending(root: downMoveRoot).first!
        require(downMoveJob.move == true, "download restart lost move intent")
        let downPayload = try await PendingCloudDownload.resume(downMoveJob, client: client, root: downMoveRoot)
        let downPublished = downMoveTarget.appendingPathComponent(downMoveItem.name)
        try fm.copyItem(at: downPayload, to: downPublished)
        let downRecord = FileUndoRecord(source: downPayload, destination: downPublished, replacedBackup: nil)
        let downUndo = try await PendingCloudDownload.completeMove(downMoveJob, client: client, record: downRecord,
            sourceLocation: "cloud:/early-download-move.txt", root: downMoveRoot)
        require(PendingCloudDownload.hasMovePublication(downMoveJob, root: downMoveRoot), "missing durable local publication")
        _ = try await PendingCloudDownload.completeMove(downMoveJob, client: client,
            sourceLocation: "cloud:/early-download-move.txt", root: downMoveRoot)
        _ = try await PersistentOnlineUndo.undo(downUndo, client: client)
        require(try Data(contentsOf: remote.appendingPathComponent(downMoveItem.name)) == content, "download move Undo lost cloud original")
        try PendingCloudDownload.finish(downMoveJob, root: downMoveRoot)
        print("PASS early cloud-local move intent, retained payload, publication recovery and Undo")
        }
        try await testEarlyMoves()
        func testDownloadMoveReplacement() async throws {
            let root = local.appendingPathComponent("replacement-download-journal")
            let target = local.appendingPathComponent("replacement-download-target")
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            let seed = local.appendingPathComponent("replacement-download.txt")
            try content.write(to: seed)
            try await client.upload(seed, parent: nil)
            let item = try await client.children(of: nil).first { $0.name == seed.lastPathComponent }!
            let job = try await PendingCloudDownload.prepare(item, client: client, destination: target, move: true, root: root)
            let payload = try await PendingCloudDownload.resume(job, client: client, root: root)
            let published = target.appendingPathComponent(item.name)
            let old = Data("old local destination".utf8)
            try old.write(to: published)
            let backup = try SafeFileOperations.copyReplacing(source: payload, destination: published, replace: true)!
            let record = FileUndoRecord(source: payload, destination: published, replacedBackup: backup)
            var legacyData = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
            legacyData.removeValue(forKey: "backupSnapshot")
            legacyData.removeValue(forKey: "backupVerificationRequired")
            let unverified = try JSONDecoder().decode(FileUndoRecord.self, from: JSONSerialization.data(withJSONObject: legacyData))
            do {
                _ = try await PendingCloudDownload.completeMove(job, client: client, record: unverified, sourceLocation: "cloud:/" + item.name, root: root)
                fatalError("move accepted unverified legacy destination backup")
            } catch {}
            require(fm.fileExists(atPath: remote.appendingPathComponent(item.name).path), "missing backup proof retired cloud source")
            try Data("tampered backup".utf8).write(to: backup)
            do {
                _ = try await PendingCloudDownload.completeMove(job, client: client, record: record, sourceLocation: "cloud:/" + item.name, root: root)
                fatalError("move accepted changed destination backup")
            } catch {}
            require(fm.fileExists(atPath: remote.appendingPathComponent(item.name).path), "invalid backup retired cloud source")
            try old.write(to: backup)
            let undo = try await PendingCloudDownload.completeMove(job, client: client, record: record, sourceLocation: "cloud:/" + item.name, root: root)
            require(!fm.fileExists(atPath: remote.appendingPathComponent(item.name).path), "replacement move left visible source")
            try Data("tampered backup".utf8).write(to: backup)
            do { _ = try await PersistentOnlineUndo.undo(undo, client: client); fatalError("Undo accepted changed backup") } catch {}
            require(!fm.fileExists(atPath: remote.appendingPathComponent(item.name).path), "failed preflight restored cloud source")
            require(try Data(contentsOf: published) == content, "failed Undo displaced current destination")
            try old.write(to: backup)
            _ = try await PersistentOnlineUndo.undo(undo, client: client)
            require(try Data(contentsOf: published) == old, "Undo lost previous local destination")
            require(try Data(contentsOf: remote.appendingPathComponent(item.name)) == content, "Undo lost cloud original")
            try PendingCloudDownload.finish(job, root: root)
            print("PASS cloud-local replacement move, recovery-backup preflight, source retention and full Undo")
        }
        try await testDownloadMoveReplacement()
        func testSameProviderReplacementMove() async throws {
            let label = "same-provider-replace"
            try await client.createFolder(label, parent: nil)
            let parent = try await client.children(of: nil).first { $0.name == label }!
            let staging = local.appendingPathComponent("same-provider-stage")
            let seed = staging.appendingPathComponent("Clash")
            try fm.createDirectory(at: seed.appendingPathComponent("Empty"), withIntermediateDirectories: true)
            try content.write(to: seed.appendingPathComponent("new.txt"))
            try await client.uploadTree(seed, parent: nil)
            let item = try await client.children(of: nil).first { $0.name == "Clash" }!
            let oldStage = local.appendingPathComponent("same-provider-old/Clash")
            try fm.createDirectory(at: oldStage, withIntermediateDirectories: true)
            let old = Data("old folder content".utf8)
            try old.write(to: oldStage.appendingPathComponent("old.txt"))
            try await client.uploadTree(oldStage, parent: parent.id)
            let existing = try await client.children(of: parent.id).first { $0.name == "Clash" }!
            let root = local.appendingPathComponent("same-provider-replace-journal")
            let job = try await PendingCrossCloudMove.prepare(item, source: client, target: client, parent: parent.id,
                name: item.name, sourceLocation: "cloud:/Clash", destinationLocation: "cloud:/" + label + "/Clash", replacing: existing, root: root)
            let undo = try await PendingCrossCloudMove.resume(job, source: client, target: client, root: root)
            require(!fm.fileExists(atPath: remote.appendingPathComponent("Clash").path), "same-provider replacement left visible source")
            require(try RemoteContent.snapshot(remote.appendingPathComponent(label + "/Clash")) == RemoteContent.snapshot(seed), "folder replacement merged or lost empty directory")
            let backup = remote.appendingPathComponent(undo.previous!.path!.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            try Data("tampered".utf8).write(to: backup.appendingPathComponent("old.txt"))
            do { _ = try await PersistentOnlineUndo.undo(undo, client: client, sourceClient: client); fatalError("cross Undo accepted modified old target") } catch {}
            require(!fm.fileExists(atPath: remote.appendingPathComponent("Clash").path), "preflight failure restored source prematurely")
            try old.write(to: backup.appendingPathComponent("old.txt"))
            _ = try await PersistentOnlineUndo.undo(undo, client: client, sourceClient: client)
            require(try RemoteContent.snapshot(remote.appendingPathComponent("Clash")) == RemoteContent.snapshot(seed), "same-provider Undo lost source folder")
            require(try RemoteContent.snapshot(remote.appendingPathComponent(label + "/Clash")) == RemoteContent.snapshot(oldStage), "same-provider Undo lost previous target")
            let writes = requests.filter { !["list", "download"].contains($0) }.count
            _ = try await PersistentOnlineUndo.undo(undo, client: client, sourceClient: client)
            require(requests.filter { !["list", "download"].contains($0) }.count == writes, "same-provider completed Undo replayed writes")
            try PendingCrossCloudMove.finish(job, root: root)
            print("PASS same-provider folder replacement move, no merging, empty folder, tampered recovery refusal and two-sided Undo")
        }
        try await testSameProviderReplacementMove()
        func testCrossMoveRecovery() async throws {
            let journal = local.appendingPathComponent("cross-early-journal")
            let seed = local.appendingPathComponent("cross-early.txt")
            try content.write(to: seed)
            try await client.upload(seed, parent: nil)
            let item = try await client.children(of: nil).first { $0.name == seed.lastPathComponent }!
            let job = try await PendingCrossCloudMove.prepare(item, source: client, target: secondClient,
                parent: nil, name: "cross-renamed.txt", sourceLocation: "source:/cross-early.txt",
                destinationLocation: "target:/cross-renamed.txt", root: journal)
            require(!fm.fileExists(atPath: secondRemote.appendingPathComponent(job.name).path), "intent uploaded before resume")
            failUploads = true
            do { _ = try await PendingCrossCloudMove.resume(job, source: client, target: secondClient, root: journal); fatalError("cross move ignored upload failure") } catch {}
            failUploads = false
            require(try Data(contentsOf: remote.appendingPathComponent(item.name)) == content, "failed cross move removed source")
            let reloaded = try PendingCrossCloudMove.pending(root: journal).first!
            do { _ = try await PendingCrossCloudMove.resume(reloaded, source: secondClient, target: client, root: journal); fatalError("cross move accepted wrong accounts") } catch {}
            try Data("changed".utf8).write(to: remote.appendingPathComponent(item.name))
            do { _ = try await PendingCrossCloudMove.resume(reloaded, source: client, target: secondClient, root: journal); fatalError("cross move ignored changed source") } catch {}
            try content.write(to: remote.appendingPathComponent(item.name))
            let undo = try await PendingCrossCloudMove.resume(reloaded, source: client, target: secondClient, root: journal)
            require(!fm.fileExists(atPath: remote.appendingPathComponent(item.name).path), "cross move left visible source")
            require(try Data(contentsOf: secondRemote.appendingPathComponent(job.name)) == content, "cross move changed bytes")
            // New provider objects have new session-local item IDs.
            let newSource = CloudFileClient(profile, transport: transport)
            let newTarget = CloudFileClient(secondProfile, transport: transport)
            _ = try await PendingCrossCloudMove.resume(reloaded, source: newSource, target: newTarget, root: journal)
            _ = try await PersistentOnlineUndo.undo(undo, client: secondClient, sourceClient: client)
            require(try Data(contentsOf: remote.appendingPathComponent(item.name)) == content, "cross move Undo lost source")
            try PendingCrossCloudMove.finish(reloaded, root: journal)
            require(try PendingCrossCloudMove.pending(root: journal).isEmpty, "cross move checkpoint not finished")
            print("PASS early cross-cloud failure, durable staging, account/source guards, new-session reconciliation and Undo")
            let nonceSeed = remote.appendingPathComponent("cross-nonce.txt")
            try content.write(to: nonceSeed)
            let nonceItem = try await client.children(of: nil).first { $0.name == nonceSeed.lastPathComponent }!
            let nonceJob = try await PendingCrossCloudMove.prepare(nonceItem, source: client, target: secondClient,
                parent: nil, name: "cross-nonce-final.txt", sourceLocation: "source:/cross-nonce.txt",
                destinationLocation: "target:/cross-nonce-final.txt", root: journal)
            failAfterUpload = true
            do { _ = try await PendingCrossCloudMove.resume(nonceJob, source: client, target: secondClient, root: journal); fatalError("lost upload response reported success") } catch {}
            failAfterUpload = false
            require(try Data(contentsOf: nonceSeed) == content, "lost upload response changed source")
            require(fm.fileExists(atPath: secondRemote.appendingPathComponent(nonceJob.privateUploadName!).path), "missing private upload")
            // Same bytes at the final path still do not authorize overwriting.
            let occupied = secondRemote.appendingPathComponent(nonceJob.name)
            try content.write(to: occupied)
            do { _ = try await PendingCrossCloudMove.resume(nonceJob, source: client, target: secondClient, root: journal); fatalError("foreign equal-content final adopted") } catch {}
            try fm.removeItem(at: occupied)
            failAfterRename = true
            do { _ = try await PendingCrossCloudMove.resume(nonceJob, source: client, target: secondClient, root: journal); fatalError("lost rename response reported success") } catch {}
            failAfterRename = false
            require(try Data(contentsOf: nonceSeed) == content, "lost rename response changed source")
            let restoredSource = CloudFileClient(profile, transport: transport)
            let restoredTarget = CloudFileClient(secondProfile, transport: transport)
            let nonceUndo = try await PendingCrossCloudMove.resume(nonceJob, source: restoredSource, target: restoredTarget, root: journal)
            require(try Data(contentsOf: occupied) == content, "nonce publication changed bytes")
            _ = try await PersistentOnlineUndo.undo(nonceUndo, client: restoredTarget, sourceClient: restoredSource)
            require(try Data(contentsOf: nonceSeed) == content, "nonce move Undo lost source")
            try PendingCrossCloudMove.finish(nonceJob, root: journal)
            print("PASS cross-cloud lost upload and rename responses, private ownership, foreign final collision, server-identity recovery and Undo")
        }
        try await testCrossMoveRecovery()
        let generatedRoot = local.appendingPathComponent("generated-upload-journal")
        for action in ["zip", "extract_archive", "duplicate"] {
            let generated = local.appendingPathComponent("generated-" + action + ".txt")
            try content.write(to: generated)
            let generatedJob = try await PendingCloudUpload.prepare(generated, source: "cloud:/synthetic-source",
                client: client, parent: nil, account: client.accountIdentity(), actionKey: action, root: generatedRoot)
            failUploads = true
            do { _ = try await PendingCloudUpload.resume(generatedJob, client: client, root: generatedRoot); fatalError("generated upload failure reported success") } catch {}
            failUploads = false
            try fm.removeItem(at: generated)
            let reloaded = try PendingCloudUpload.pending(root: generatedRoot).first!
            require(reloaded.actionKey == action, "recovered generated operation lost History action")
            let generatedUndo = try await PendingCloudUpload.resume(reloaded, client: client, root: generatedRoot)
            require(try Data(contentsOf: remote.appendingPathComponent(generated.lastPathComponent)) == content, "generated result lost after staging cleanup")
            require(generatedUndo != nil, "resumed generated upload lost Undo")
            try PendingCloudUpload.finish(reloaded, root: generatedRoot)
        }
        do {
            _ = try await PendingCloudUpload.prepare(localCloudSource, source: "synthetic", client: client,
                parent: nil, account: client.accountIdentity(), actionKey: "unsupported", root: generatedRoot)
            fatalError("unsupported journal action accepted")
        } catch {}
        print("PASS generated ZIP/extraction/duplicate results survive upload failure and staging removal with correct persisted action and Undo")
        let recoveryRoot = local.appendingPathComponent("upload-journal")
        let recoveryFile = local.appendingPathComponent("restart-proof.txt")
        try content.write(to: recoveryFile)
        let recoveryJob = try await PendingCloudUpload.prepare(recoveryFile, source: recoveryFile.path, client: client,
            parent: nil, account: client.accountIdentity(), root: recoveryRoot)
        let reloadedJob = try PendingCloudUpload.pending(root: recoveryRoot).first!
        require(reloadedJob.id == recoveryJob.id, "upload checkpoint did not survive reload")
        try fm.removeItem(at: recoveryFile)
        do { _ = try await PendingCloudUpload.resume(reloadedJob, client: secondClient, root: recoveryRoot); fatalError("recovery accepted another account") } catch {}
        let resumedUndo = try await PendingCloudUpload.resume(reloadedJob, client: client, root: recoveryRoot)
        require(resumedUndo != nil, "fresh recovered upload lost Undo")
        require(try Data(contentsOf: remote.appendingPathComponent(reloadedJob.name)) == content, "resumed upload differs")
        let reconciled = try await PendingCloudUpload.resume(reloadedJob, client: client, root: recoveryRoot)
        require(reconciled == resumedUndo, "verified completion receipt lost Undo after reload")
        let receiptURL = PendingCloudUpload.folder(reloadedJob, root: recoveryRoot).appendingPathComponent("receipt.json")
        let receipt = try Data(contentsOf: receiptURL)
        try Data("invalid receipt".utf8).write(to: receiptURL)
        do { _ = try await PendingCloudUpload.resume(reloadedJob, client: client, root: recoveryRoot); fatalError("corrupt receipt accepted") } catch {}
        try receipt.write(to: receiptURL)
        try Data("other bytes".utf8).write(to: remote.appendingPathComponent(reloadedJob.name))
        do { _ = try await PendingCloudUpload.resume(reloadedJob, client: client, root: recoveryRoot); fatalError("resume overwrote conflict") } catch {}
        require(try Data(contentsOf: remote.appendingPathComponent(reloadedJob.name)) == Data("other bytes".utf8), "conflicting target changed")
        try content.write(to: remote.appendingPathComponent(reloadedJob.name))
        try fm.removeItem(at: receiptURL)
        require(try await PendingCloudUpload.resume(reloadedJob, client: client, root: recoveryRoot) == nil,
                "completion without receipt acquired destructive Undo")
        try PendingCloudUpload.finish(reloadedJob, root: recoveryRoot)
        require(try PendingCloudUpload.pending(root: recoveryRoot).isEmpty, "completed upload journal retained")
        print("PASS durable upload journal reload, source-independent resume, wrong account and collision refusal, ambiguous completion reconciliation")
        let recoveryTree = local.appendingPathComponent("restart-tree")
        try fm.createDirectory(at: recoveryTree.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try content.write(to: recoveryTree.appendingPathComponent("done.txt"))
        try content.write(to: recoveryTree.appendingPathComponent("nested/pending.txt"))
        let treeJob = try await PendingCloudUpload.prepare(recoveryTree, source: recoveryTree.path, client: client,
            parent: nil, account: client.accountIdentity(), root: recoveryRoot)
        try await client.createFolder(treeJob.name, parent: nil)
        let partialTree = try await client.children(of: nil).first { $0.name == treeJob.name }!
        try await client.uploadTree(recoveryTree.appendingPathComponent("done.txt"), parent: partialTree.id)
        _ = try await PendingCloudUpload.resume(PendingCloudUpload.pending(root: recoveryRoot).first!, client: client, root: recoveryRoot)
        require(try await CommanderOnlineTools.contentSnapshot(client, item: partialTree) == treeJob.content, "partial folder did not resume")
        let nestedPlaceholder = remote.appendingPathComponent("restart-tree/nested/pending.txt")
        try Data("incomplete upload".utf8).write(to: nestedPlaceholder)
        do { _ = try await PendingCloudUpload.resume(treeJob, client: client, root: recoveryRoot); fatalError("foreign nested conflict overwritten") } catch {}
        require(try Data(contentsOf: nestedPlaceholder) == Data("incomplete upload".utf8), "foreign conflict bytes changed")
        var sessionResumes = 0
        let sessionClient = RecoverableSessionClient(client) { staged, parent in
            let nested = try await client.children(of: partialTree.id).first { $0.name == "nested" }!
            guard staged.lastPathComponent == "pending.txt", parent == nested.id else { return false }
            sessionResumes += 1
            try Data(contentsOf: staged).write(to: nestedPlaceholder)
            return true
        }
        let extra = remote.appendingPathComponent("restart-tree/foreign.txt")
        try Data("foreign".utf8).write(to: extra)
        do { _ = try await PendingCloudUpload.resume(treeJob, client: sessionClient, root: recoveryRoot); fatalError("extra foreign path accepted") } catch {}
        require(sessionResumes == 0, "mutated before foreign path preflight")
        try fm.removeItem(at: extra)
        let nestedUndo = try await PendingCloudUpload.resume(treeJob, client: sessionClient, root: recoveryRoot)
        require(sessionResumes == 1 && nestedUndo == nil, "nested session did not reconcile safely")
        require(try await CommanderOnlineTools.contentSnapshot(client, item: partialTree) == treeJob.content, "nested resumed bytes differ")
        try PendingCloudUpload.finish(treeJob, root: recoveryRoot)
        print("PASS partially published cloud folder resumes missing descendants without replacing completed files")
        print("PASS nested upload placeholder resumes only its saved session; foreign conflicts and extra paths preserve bytes")
        let replacementRoot = local.appendingPathComponent("replacement-journal")
        let replacementSource = local.appendingPathComponent("restart-replace.txt")
        let oldReplacementBytes = Data("old replacement bytes".utf8)
        try oldReplacementBytes.write(to: replacementSource)
        try await client.upload(replacementSource, parent: nil)
        let replacementOriginal = try await client.children(of: nil).first { $0.name == replacementSource.lastPathComponent }!
        try content.write(to: replacementSource)
        let replacementJob = try await PendingCloudReplacement.prepare(replacementSource, sourceLocation: replacementSource.path,
            existing: replacementOriginal, client: client, parent: nil, root: replacementRoot)
        let replacementReloaded = try PendingCloudReplacement.pending(root: replacementRoot).first!
        require(replacementReloaded.id == replacementJob.id, "replacement intent lost on reload")
        let unpublished = replacementRoot.appendingPathComponent(".preparing-" + UUID().uuidString)
        try fm.createDirectory(at: unpublished, withIntermediateDirectories: false)
        try Data("incomplete private preparation".utf8).write(to: unpublished.appendingPathComponent("job.json"))
        require(try PendingCloudReplacement.pending(root: replacementRoot).count == 1, "unpublished preparation blocked valid recovery")
        do { _ = try await PendingCloudReplacement.resume(replacementReloaded, client: secondClient, root: replacementRoot); fatalError("replacement accepted another account") } catch {}
        try fm.removeItem(at: replacementSource)
        // Simulate process loss after displacement but before upload publication.
        try await client.move(replacementOriginal, parent: nil, name: replacementJob.recoveryName)
        failUploads = true
        do { _ = try await PendingCloudReplacement.resume(replacementReloaded, client: client, root: replacementRoot); fatalError("failed replacement upload succeeded") } catch {}
        require(try Data(contentsOf: remote.appendingPathComponent(replacementJob.recoveryName)) == oldReplacementBytes, "interrupted replacement lost old bytes")
        failUploads = false
        let unexpectedReplacement = remote.appendingPathComponent("restart-replace.txt")
        try Data("foreign destination".utf8).write(to: unexpectedReplacement)
        do { _ = try await PendingCloudReplacement.resume(replacementReloaded, client: client, root: replacementRoot); fatalError("replacement overwrote unexpected destination") } catch {}
        require(try Data(contentsOf: unexpectedReplacement) == Data("foreign destination".utf8), "replacement changed foreign destination")
        try fm.removeItem(at: unexpectedReplacement)
        let replacementResult = try await PendingCloudReplacement.resume(replacementReloaded, client: client, root: replacementRoot)
        require(try Data(contentsOf: remote.appendingPathComponent("restart-replace.txt")) == content, "replacement restart lost new bytes")
        // A second restart after remote completion must reconcile, not upload again.
        let uploadsBeforeReconcile = requests.filter { $0 == "upload" }.count
        _ = try await PendingCloudReplacement.resume(replacementReloaded, client: client, root: replacementRoot)
        require(requests.filter { $0 == "upload" }.count == uploadsBeforeReconcile, "completed replacement replayed upload")
        let replacementUndo = try await PersistentOnlineUndo.replacement(client, record: replacementResult, account: client.accountIdentity())
        try PendingCloudReplacement.finish(replacementReloaded, root: replacementRoot)
        _ = try await PersistentOnlineUndo.undo(replacementUndo, client: client)
        require(try Data(contentsOf: remote.appendingPathComponent("restart-replace.txt")) == oldReplacementBytes, "recovered replacement Undo lost original")
        require(try PendingCloudReplacement.pending(root: replacementRoot).isEmpty, "finished replacement retained checkpoint")
        print("PASS durable replacement resumes after displacement and upload failure without source, reconciles completion without replay and preserves Undo")
        let aliasSource = local.appendingPathComponent("AliasSource.txt"), aliasTarget = local.appendingPathComponent("AliasTarget.txt")
        try content.write(to: aliasSource); try content.write(to: aliasTarget)
        try await client.upload(aliasSource, parent: nil); try await client.upload(aliasTarget, parent: nil)
        let aliasListing = try await client.children(of: nil)
        let aliasItem = aliasListing.first { $0.name == aliasSource.lastPathComponent }!
        let oldAlias = aliasListing.first { $0.name == aliasTarget.lastPathComponent }!
        try fm.removeItem(at: remote.appendingPathComponent(aliasTarget.lastPathComponent))
        try await client.move(aliasItem, parent: nil, name: aliasTarget.lastPathComponent)
        for reference in [aliasItem.id, oldAlias.id] {
            let resolved = try await client.metadata(reference)
            require(resolved.id == reference && resolved.name == aliasTarget.lastPathComponent, "logical path alias lost after external deletion and move")
        }
        print("PASS remote logical aliases resolve deterministically after external deletion and name reuse")
        let oldContent = Data("old replacement content".utf8), newContent = Data("new replacement content".utf8)
        let remoteReplacement = remote.appendingPathComponent("Replace.txt"), localReplacement = local.appendingPathComponent("Replace.txt")
        try oldContent.write(to: remoteReplacement); try newContent.write(to: localReplacement)
        let old = try await client.children(of: nil).first { $0.name == "Replace.txt" }!
        let replacement = try await CommanderOnlineTools.replace(client, existing: old, with: localReplacement, parent: nil)
        require(try Data(contentsOf: remoteReplacement) == newContent, "replacement data differs")
        require(try Data(contentsOf: remote.appendingPathComponent(replacement.previous.name)) == oldContent, "previous content not retained")
        let account = try await client.accountIdentity()
        let persistedUndo = try PersistentOnlineUndo.replacement(client, record: replacement, account: account)
        let retainedNewName = try await PersistentOnlineUndo.undo(persistedUndo, client: client)
        let retainedNew = try await client.children(of: nil).first { $0.name == retainedNewName! }!
        require(try Data(contentsOf: remoteReplacement) == oldContent, "Undo did not restore previous data")
        require(try Data(contentsOf: remote.appendingPathComponent(retainedNew.name)) == newContent, "Undo discarded replacement data")
        print("PASS verified online replacement retains old content; Undo restores it and keeps new content recoverable")
        let undoLocal = local.appendingPathComponent("PersistentUndo.txt")
        try Data("persistent online undo".utf8).write(to: undoLocal)
        try await client.uploadTree(undoLocal, parent: nil)
        let undoItem = try await client.children(of: nil).first { $0.name == undoLocal.lastPathComponent }!
        let undoContent = try await CommanderOnlineTools.contentSnapshot(client, item: undoItem)
        try await client.rename(undoItem, to: "PersistentUndo-Renamed.txt")
        let renamedUndoItem = try await client.metadata(undoItem.id)
        let relocation = try PersistentOnlineUndo.relocation(client, current: renamedUndoItem, content: undoContent,
            parent: nil, parentPath: nil, name: undoLocal.lastPathComponent, account: account)
        _ = try await PersistentOnlineUndo.undo(relocation, client: client)
        require(try await client.children(of: nil).contains { $0.name == undoLocal.lastPathComponent },
            "persistent relocation Undo did not restore the original name")
        let removal = try await PersistentOnlineUndo.uploaded(client, parent: nil, name: undoLocal.lastPathComponent,
            content: undoContent, account: account)
        let mismatchedAccount = CloudUndoPayload(endpoint: removal.endpoint, account: "another-account", kind: removal.kind,
            current: removal.current, previous: removal.previous, originalName: removal.originalName,
            originalParent: removal.originalParent, originalParentPath: removal.originalParentPath)
        let writesBeforeAccountRefusal = requests.count
        do { _ = try await PersistentOnlineUndo.undo(mismatchedAccount, client: client); fatalError("Undo crossed account boundary") } catch {}
        require(requests.count == writesBeforeAccountRefusal, "wrong-account Undo issued a cloud request")
        _ = try await PersistentOnlineUndo.undo(removal, client: client)
        require(!(try await client.children(of: nil)).contains { $0.name == undoLocal.lastPathComponent },
            "persistent upload Undo left the new item in its original location")
        print("PASS persistent online rename/remove Undo, reference round-trip and account mismatch refusal")
        try await client.createFolder("Created Empty Folder", parent: nil)
        let createdFolderUndo = try await PersistentOnlineUndo.uploaded(client, parent: nil, name: "Created Empty Folder",
            content: ["": "directory"], account: account)
        let restoredFolderUndo = try JSONDecoder().decode(CloudUndoPayload.self, from: JSONEncoder().encode(createdFolderUndo))
        _ = try await PersistentOnlineUndo.undo(restoredFolderUndo, client: client)
        require(!(try await client.children(of: nil)).contains { $0.name == "Created Empty Folder" }, "created empty folder Undo failed after serialization")
        try await client.createFolder("Created Changed Folder", parent: nil)
        let changedFolderUndo = try await PersistentOnlineUndo.uploaded(client, parent: nil, name: "Created Changed Folder",
            content: ["": "directory"], account: account)
        let laterChild = remote.appendingPathComponent("Created Changed Folder/Later.txt")
        try Data("Added after folder creation".utf8).write(to: laterChild)
        do { _ = try await PersistentOnlineUndo.undo(changedFolderUndo, client: client); fatalError("created cloud folder Undo removed later content") } catch {}
        require(try Data(contentsOf: laterChild) == Data("Added after folder creation".utf8), "later cloud folder contents changed")
        print("PASS created cloud folder Undo survives serialization; later child additions refuse removal and retain bytes")
        failUploads = true
        let beforeFailure = try await client.children(of: nil).first { $0.name == "Replace.txt" }!
        do { _ = try await CommanderOnlineTools.replace(client, existing: beforeFailure, with: localReplacement, parent: nil); fatalError("failed upload reported success") } catch {}
        failUploads = false
        require(try Data(contentsOf: remoteReplacement) == oldContent, "failed replacement did not restore previous target")
        require(try Data(contentsOf: localReplacement) == newContent, "failed replacement changed source")
        print("PASS failed replacement upload restores verified old target and leaves source intact")
        let beforeChanged = try await client.children(of: nil).first { $0.name == "Replace.txt" }!
        let changedRecord = try await CommanderOnlineTools.replace(client, existing: beforeChanged, with: localReplacement, parent: nil)
        try content.write(to: remoteReplacement)
        let writesBeforeUndo = requests.count
        do { _ = try await CommanderOnlineTools.undoReplacement(client, record: changedRecord); fatalError("changed target Undo accepted") } catch {}
        require(!requests.dropFirst(writesBeforeUndo).contains { ["rename", "copy", "upload"].contains($0) }, "changed Undo mutated content")
        require(try Data(contentsOf: remoteReplacement) == content, "changed content lost")
        print("PASS changed online replacement refuses Undo before writes, retaining both versions")
        let oldDirectory = remote.appendingPathComponent("ReplaceDirectory"), newDirectory = local.appendingPathComponent("ReplaceDirectory")
        try fm.createDirectory(at: oldDirectory, withIntermediateDirectories: false)
        try oldContent.write(to: oldDirectory.appendingPathComponent("Old.txt"))
        try fm.createDirectory(at: newDirectory.appendingPathComponent("Nested/Empty"), withIntermediateDirectories: true)
        try newContent.write(to: newDirectory.appendingPathComponent("Nested/New.txt"))
        let oldFolder = try await client.children(of: nil).first { $0.name == "ReplaceDirectory" }!
        let folderReplacement = try await CommanderOnlineTools.replace(client, existing: oldFolder, with: newDirectory, parent: nil)
        require(!fm.fileExists(atPath: oldDirectory.appendingPathComponent("Old.txt").path), "folder replacement accidentally merged old entries")
        require(try Data(contentsOf: oldDirectory.appendingPathComponent("Nested/New.txt")) == newContent, "folder replacement data differs")
        require(fm.fileExists(atPath: oldDirectory.appendingPathComponent("Nested/Empty").path), "empty folder lost")
        _ = try await CommanderOnlineTools.undoReplacement(client, record: folderReplacement)
        require(try Data(contentsOf: oldDirectory.appendingPathComponent("Old.txt")) == oldContent, "folder Undo did not restore old directory")
        print("PASS whole-folder replacement, empty descendants, no accidental merge and verified Undo")

        var displayProfile = profile; displayProfile.id = UUID().uuidString
        var now = Date(timeIntervalSince1970: 1_000_000), count = 0
        var displayError: NSError?
        var delays: [TimeInterval] = []
        let display = CloudFileClient(displayProfile, transport: { _, _, operation, _, _, _, callback in
            require(operation == "list", "display test wrote data")
            count += 1; callback(displayError == nil ? Data("[]".utf8) : nil, displayError)
        }, clock: { now }, wait: { seconds in delays.append(seconds); now = now.addingTimeInterval(seconds) })
        _ = try await display.browserListing(of: nil)
        displayError = CloudProviderErrors.temporary("cloud_google_quota", cooldown: 60)
        let stale = try await display.browserListing(of: nil)
        require(stale.cachedAt != nil && stale.warningKey == "cloud_google_quota" && stale.retryAfter == 60, "quota fallback must be explicit and localized")
        let countAfterQuota = count
        _ = try await display.browserListing(of: nil)
        require(count == countAfterQuota && delays.isEmpty, "Google application quota immediately queried again")
        do { _ = try await display.toolChildren(of: nil); fatalError("tool used cached listing") } catch {}
        require(count == countAfterQuota + 1, "tools must request fresh authoritative data")
        now = now.addingTimeInterval(61); displayError = CloudConnection.failure("cloud_login_incomplete")
        do { _ = try await display.browserListing(of: nil); fatalError("invalid login exposed cached data") } catch {}
        require(delays.isEmpty, "login failure retried")
        displayError = nil
        let freshDisplay = try await display.browserListing(of: nil)
        require(freshDisplay.cachedAt == nil && freshDisplay.warningKey == nil, "restored access not fresh")
        print("PASS direct-cloud quota cooldown, explicit localized stale cache, fresh tools and authentication cache refusal")

        var attempts = 0, retryDelays: [TimeInterval] = []
        let retry = CloudFileClient(displayProfile, transport: { _, _, _, _, _, _, callback in
            attempts += 1
            callback(attempts < 3 ? nil : Data("[]".utf8), attempts < 3 ? CloudProviderErrors.temporary("cloud_rate_limited") : nil)
        }, wait: { retryDelays.append($0) })
        _ = try await retry.browserListing(of: nil)
        require(attempts == 3 && retryDelays == [2, 4], "display retries not bounded to three with 2/4-second waits")
        var writeCalls: [String] = []
        let writer = CloudFileClient(displayProfile, transport: { _, _, operation, _, _, _, callback in
            writeCalls.append(operation)
            callback(operation == "list" ? Data("[]".utf8) : nil,
                operation == "mkdir" ? CloudProviderErrors.temporary("cloud_rate_limited") : nil)
        })
        do { try await writer.createFolder("Synthetic", parent: nil); fatalError("failed mkdir reported success") } catch {}
        require(writeCalls.filter { $0 == "mkdir" }.count == 1, "cloud write was replayed")
        print("PASS bounded display-only retries; mutation requests are never automatically replayed")

        var pending: [(Data?, NSError?) -> Void] = []
        let shared = CloudFileClient(displayProfile, transport: { _, _, _, _, _, _, callback in pending.append(callback) })
        let cancelledWaiter = Task { try await shared.browserListing(of: nil) }
        let liveWaiter = Task { try await shared.browserListing(of: nil) }
        for _ in 0..<1000 { if pending.count == 1 { break }; await Task.yield() }
        require(pending.count == 1, "shared display request not coalesced")
        cancelledWaiter.cancel(); pending[0](Data("[]".utf8), nil)
        do { _ = try await cancelledWaiter.value; fatalError("cancelled waiter succeeded") } catch {}
        _ = try await liveWaiter.value
        require(pending.count == 1, "cancelling one pane repeated another pane's request")
        pending.removeAll()
        let obsolete = Task { try await shared.browserListing(of: nil) }
        for _ in 0..<1000 { if pending.count == 1 { break }; await Task.yield() }
        require(pending.count == 1, "invalidation fixture did not start")
        try shared.disconnect(); pending[0](Data("[]".utf8), nil)
        do { _ = try await obsolete.value; fatalError("disconnected request reused old account data") } catch {}
        print("PASS direct-cloud shared reads, independent waiter cancellation and disconnect/in-flight invalidation")
        var binding = "synthetic-account-a", bindingRequests = 0, changeDuringRead = false
        var bindingNow = Date(timeIntervalSince1970: 2_000_000)
        var bindingError: NSError?
        let bound = CloudFileClient(displayProfile, transport: { _, _, _, _, _, _, callback in
            bindingRequests += 1
            if changeDuringRead { binding = "synthetic-account-b" }
            callback(bindingError == nil ? Data("[]".utf8) : nil, bindingError)
        }, clock: { bindingNow }, configurationIdentity: { binding })
        _ = try await bound.browserListing(of: nil)
        binding = "synthetic-account-b"; bindingError = CloudProviderErrors.temporary("cloud_google_quota", cooldown: 60)
        do { _ = try await bound.browserListing(of: nil); fatalError("changed configuration reused previous account cache") } catch {}
        require(bindingRequests == 2, "changed configuration kept the old cooldown/data")
        bindingNow = bindingNow.addingTimeInterval(61)
        bindingError = nil; _ = try await bound.browserListing(of: nil)
        binding = "synthetic-account-a"; changeDuringRead = true
        do { _ = try await bound.browserListing(of: nil); fatalError("in-flight configuration swap accepted as current data") } catch {}
        print("PASS configuration-bound display cache clears on account/config change and rejects in-flight source changes")
    }
}
