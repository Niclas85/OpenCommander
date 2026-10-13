import Foundation
import CryptoKit

@main struct CloudClientTests {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let fixture = URL(fileURLWithPath: "/private/tmp/OpenCommander-CloudTests-" + UUID().uuidString)
        try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: fixture) }
        let remote = fixture.appendingPathComponent("remote"), local = fixture.appendingPathComponent("local")
        try fm.createDirectory(at: remote, withIntermediateDirectories: false)
        try fm.createDirectory(at: local, withIntermediateDirectories: false)
        var requests = [String]()
        var unknownNames = Set<String>()
        var failUploads = false
        let profile = CloudConnection(name: "Test Drive", kind: "drive", remote: "synthetic", configPath: "/private/tmp/test.conf")
        let client = CloudFileClient(profile, transport: { _, data, operation, path, destination, localURL, callback in
            do {
                let selected = try JSONDecoder().decode(CloudConnection.self, from: data)
                _ = try RcloneCommandPlan.arguments(profile: selected, operation: operation, path: path, destination: destination, local: localURL)
                requests.append(operation)
                let source = path.isEmpty ? remote : remote.appendingPathComponent(path)
                var response = Data()
                switch operation {
                case "list":
                    let list = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).map { url -> [String: Any] in
                        let attributes = try fm.attributesOfItem(atPath: url.path)
                        let directory = attributes[.type] as? FileAttributeType == .typeDirectory
                        let contents = directory ? Data() : try Data(contentsOf: url)
                        let hash = Data(SHA256.hash(data: contents)).base64EncodedString()
                        return ["Name": url.lastPathComponent, "Path": url.lastPathComponent, "Size": unknownNames.contains(url.lastPathComponent) ? -1 : directory ? 0 : contents.count,
                            "IsDir": directory, "ModTime": "2026-10-12T10:20:00Z", "Hashes": ["sha256": hash]]
                    }
                    response = try JSONSerialization.data(withJSONObject: list)
                case "mkdir": try fm.createDirectory(at: source, withIntermediateDirectories: false)
                case "download": try fm.copyItem(at: source, to: localURL!)
                case "upload":
                    if failUploads { throw CloudConnection.failure("cloud_request_failed") }
                    try fm.copyItem(at: localURL!, to: source)
                case "rename": try fm.moveItem(at: source, to: remote.appendingPathComponent(destination!))
                case "copy": try fm.copyItem(at: source, to: remote.appendingPathComponent(destination!))
                default: throw CloudConnection.failure("cloud_invalid")
                }
                callback(response, nil)
            } catch { callback(nil, error as NSError) }
        })
        func require(_ value: Bool, _ text: String) { if !value { fatalError(text) } }
        let file = local.appendingPathComponent("Grüsse: Drive\\Name.txt")
        let content = Data("synthetic data, not personal cloud content".utf8)
        try content.write(to: file)
        try await client.uploadTree(file, parent: nil)
        let listing = try await client.children(of: nil)
        require(listing.count == 1 && listing[0].name == file.lastPathComponent, "cloud names or upload publication changed")
        let item = listing[0]
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
        try await client.recycle(fresh)
        require(!fm.fileExists(atPath: remote.appendingPathComponent("Ziel/Neu.txt").path), "recycle did not remove original name")
        let recovered = try fm.contentsOfDirectory(atPath: remote.appendingPathComponent("Ziel").path)
        require(recovered.count == 1 && recovered[0].hasPrefix(".OpenCommander-Recovery-"), "recycle did not retain data")
        print("PASS stale version refuses rename; cloud removal retains recoverable original")
        let nativeURL = remote.appendingPathComponent("NativeDocument.docx")
        try content.write(to: nativeURL); unknownNames.insert(nativeURL.lastPathComponent)
        let native = try await client.children(of: nil).first { $0.name == nativeURL.lastPathComponent }!
        require(native.size == nil, "unknown export was presented as empty content")
        let unknownBefore = requests.count
        do { _ = try await client.download(native); fatalError("unknown export accepted") }
        catch { require((error as NSError).localizedDescription == "remote_unknown_size", "unknown export not explained") }
        do { try await client.move(native, parent: destination.id, name: "converted.docx"); fatalError("unknown move accepted") } catch {}
        do { try await client.recycle(native); fatalError("unknown removal accepted") } catch {}
        require(!requests.dropFirst(unknownBefore).contains { ["download", "copy", "rename", "upload"].contains($0) }, "unknown export caused a content change")
        require(try Data(contentsOf: nativeURL) == content, "native document changed")
        let invalidData = try JSONSerialization.data(withJSONObject: ["Name": "invalid", "Path": "invalid", "Size": -2, "IsDir": false])
        do { try JSONDecoder().decode(RcloneListingItem.self, from: invalidData).validate(); fatalError("invalid negative size accepted") } catch {}
        print("PASS unknown native export remains visible, never reported as empty, and refuses transfer/removal before any write")
        let oldContent = Data("old replacement content".utf8), newContent = Data("new replacement content".utf8)
        let remoteReplacement = remote.appendingPathComponent("Replace.txt"), localReplacement = local.appendingPathComponent("Replace.txt")
        try oldContent.write(to: remoteReplacement); try newContent.write(to: localReplacement)
        let old = try await client.children(of: nil).first { $0.name == "Replace.txt" }!
        let replacement = try await CommanderOnlineTools.replace(client, existing: old, with: localReplacement, parent: nil)
        require(try Data(contentsOf: remoteReplacement) == newContent, "replacement data differs")
        require(try Data(contentsOf: remote.appendingPathComponent(replacement.previous.name)) == oldContent, "previous content not retained")
        let retainedNew = try await CommanderOnlineTools.undoReplacement(client, record: replacement)
        require(try Data(contentsOf: remoteReplacement) == oldContent, "Undo did not restore previous data")
        require(try Data(contentsOf: remote.appendingPathComponent(retainedNew.name)) == newContent, "Undo discarded replacement data")
        print("PASS verified online replacement retains old content; Undo restores it and keeps new content recoverable")
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
