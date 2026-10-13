import Foundation

final class MemoryTokens: OneDriveTokenStore {
    var value: String? = "fixture-refresh"
    func read(clientID: String) throws -> String? { value }
    func write(_ token: String?, clientID: String) throws { value = token }
}

final class MockMicrosoft: URLProtocol {
    static var headers: [String: String] = [:]
    static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: Self.headers.merging(["Content-Type": "application/json"]) { _, new in new })!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main struct OneDriveTests {
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAIL: " + label) }
    }
    @MainActor static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockMicrosoft.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = MemoryTokens()
        let id = "00000000-0000-0000-0000-000000000001"
        let api = OneDriveClient(clientID: id, session: session, store: store)
        var requests: [URLRequest] = []
        MockMicrosoft.handler = { request in
            requests.append(request)
            if request.url!.host == "login.microsoftonline.com" {
                check(request.value(forHTTPHeaderField: "Authorization") == nil, "Graph token must not reach OAuth endpoint")
                return (200, #"{"access_token":"fixture-access","refresh_token":"rotated-refresh","expires_in":3600}"#)
            }
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access", "Graph receives access token")
            if request.url!.query == "page=2" { return (200, #"{"value":[{"id":"2","name":"Alpha","folder":{"childCount":0}}]}"#) }
            return (200, #"{"value":[{"id":"1","name":"Grüsse.txt","size":42}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/drive/root/children?page=2"}"#)
        }
        let listing = try await api.children()
        check(listing.count == 2 && listing.first?.isFolder == true, "Pagination and folder-first sorting")
        check(listing.last?.name == "Grüsse.txt", "Unicode filenames")
        check(store.value == "rotated-refresh", "Refresh rotation is persisted")
        check(requests.count == 3, "Exactly one refresh and two listing pages")
        _ = try await api.children()
        check(requests.count == 5, "Unexpired access token reused")
        print("PASS refresh, rotation, pagination, Unicode, token reuse")

        requests = []
        MockMicrosoft.handler = { request in
            requests.append(request)
            return (200, #"{"value":[],"@odata.nextLink":"https://untrusted.example/v1.0/steal"}"#)
        }
        do { _ = try await api.children(); fatalError("Unexpected foreign page accepted") }
        catch { check(requests.count == 1, "Untrusted pagination never requested") }
        check(!OneDriveClient.safeGraphURL(URL(string: "http://graph.microsoft.com/v1.0/me/drive")!), "Reject HTTP")
        check(!OneDriveClient.safeGraphURL(URL(string: "https://graph.microsoft.com:8443/v1.0/me/drive")!), "Reject alternate port")
        check(!OneDriveClient.safeGraphURL(URL(string: "https://graph.microsoft.com.attacker.example/v1.0/me/drive")!), "Reject lookalike host")
        check(!OneDriveClient.allowedRedirect(from: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token"), to: URL(string: "https://untrusted.example/token")), "OAuth body cannot follow a foreign redirect")
        check(!OneDriveClient.allowedRedirect(from: URL(string: "https://graph.microsoft.com/v1.0/me/drive"), to: URL(string: "https://untrusted.example/")), "Bearer request cannot follow a foreign redirect")
        check(!OneDriveClient.allowedRedirect(from: URL(string: "https://download.example/file"), to: URL(string: "http://download.example/file")), "Download cannot downgrade TLS")
        print("PASS unexpected pagination URL and insecure API addresses refused")

        MockMicrosoft.handler = { _ in (200, #"{"value":[],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/drive/root/children"}"#) }
        do { _ = try await api.children(); fatalError("Repeated page accepted") } catch { }
        print("PASS pagination loop detection")

        let file = try JSONDecoder().decode(OneDriveItem.self, from: Data(#"{"id":"fixture-id","name":"fixture.txt","size":7,"eTag":"fixture-v1"}"#.utf8))
        requests = []
        MockMicrosoft.handler = { request in
            requests.append(request)
            if request.httpMethod == "POST" || request.httpMethod == "PATCH" { return (201, "{}") }
            if request.httpMethod == "DELETE" { return (204, "") }
            return (409, #"{"error":{"code":"nameAlreadyExists"}}"#)
        }
        try await api.createFolder("Grüsse", parent: nil)
        try await api.rename(file, to: "Renamed.txt")
        try await api.recycle(file)
        check(requests.map(\.httpMethod) == ["POST", "PATCH", "DELETE"], "Correct mutation methods")
        check(requests[1].value(forHTTPHeaderField: "If-Match") == "fixture-v1", "Rename and undo protect against concurrent changes")
        let renameBody = try JSONSerialization.jsonObject(with: body(requests[1])) as! [String: Any]
        check(renameBody["@microsoft.graph.conflictBehavior"] as? String == "fail", "Rename never replaces a destination")
        let before = requests.count
        for invalid in ["../escape", "bad\\name", "bad:name", "trailing.", "", "..", "\n"] {
            do { try await api.createFolder(invalid, parent: nil); fatalError("Invalid name accepted") } catch { }
        }
        check(requests.count == before, "Invalid names cause no requests")
        print("PASS create/rename/recycle requests and invalid name protection")

        check(OneDriveConflictNames.available("Photo.JPG", folder: false, existing: ["photo.jpg", "PHOTO (2).jpg"]) == "Photo (3).JPG", "Keep both is case insensitive and preserves extension")
        check(OneDriveConflictNames.available("Grüsse.txt", folder: false, existing: ["Gru\u{0308}sse.txt"]) == "Grüsse (2).txt", "Canonically equivalent Unicode names conflict")
        check(OneDriveConflictNames.available("Folder.v1", folder: true, existing: ["Folder.v1"]) == "Folder.v1 (2)", "Folder dots are not extensions")
        check(OneDriveConflictNames.available(".env", folder: false, existing: [".env"]) == ".env (2)", "Extensionless dotfiles retain their name")
        check(OneDriveConflictNames.available("new.txt", folder: false, existing: []) == "new.txt", "No conflict keeps original name")
        let longName = String(repeating: "x", count: 251) + ".txt"
        check(OneDriveClient.validName(OneDriveConflictNames.available(longName, folder: false, existing: [longName])), "Numbered name stays within name limit")
        let longExtension = "x." + String(repeating: "e", count: 253)
        check(OneDriveClient.validName(OneDriveConflictNames.available(longExtension, folder: false, existing: [longExtension])), "Extreme extension cannot exceed numbered name limit")
        print("PASS safe conflict names, case/Unicode equivalence, folders, extensions and length limit")

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommander-OneDriveTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let local = fixture.appendingPathComponent("Grüsse.txt")
        try Data("fixture".utf8).write(to: local)
        do { try await api.upload(local, parent: nil); fatalError("Failed upload falsely succeeded") } catch { }
        check(requests.last?.httpMethod == "PUT", "Upload uses PUT")
        check(requests.last?.url?.query?.contains("conflictBehavior=fail") == true, "Upload explicitly refuses replacement")
        check(requests.last?.url?.path.contains("Grüsse.txt") == true, "Upload preserves Unicode after URL decoding")
        let large = fixture.appendingPathComponent("large.bin")
        try Data().write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 20 * 1024 * 1024 + 1); try handle.close()
        let count = requests.count
        do { try await api.upload(large, parent: nil); fatalError("Failed session accepted") } catch { }
        check(count + 1 == requests.count && requests.last?.url?.path.hasSuffix("createUploadSession") == true, "Large upload uses a session")
        print("PASS failed upload propagates, collision refusal, encoding, upload-session failure")

        var offset = 0
        let total = 20 * 1024 * 1024 + 1
        MockMicrosoft.handler = { request in
            if request.url!.host == "graph.microsoft.com" {
                check(request.httpMethod == "POST", "Session creation uses POST")
                check(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access", "Only session creation receives Graph token")
                return (200, #"{"uploadUrl":"https://upload.example/fixture"}"#)
            }
            check(request.value(forHTTPHeaderField: "Authorization") == nil, "Upload chunks never contain a Graph bearer")
            let bytes = body(request).count
            check(request.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(offset + bytes - 1)/\(total)", "Contiguous byte ranges")
            offset += bytes
            if offset == total { return (201, "{\"id\":\"large\",\"name\":\"large.bin\",\"size\":\(total)}") }
            check(bytes % 327_680 == 0, "Intermediate chunk multiple of 320 KiB")
            return (202, "{\"nextExpectedRanges\":[\"\(offset)-\"]}")
        }
        try await api.upload(large, parent: nil)
        check(offset == total, "All large-file bytes sent")
        MockMicrosoft.handler = { request in
            if request.url!.host == "graph.microsoft.com" { return (200, #"{"uploadUrl":"https://upload.example/fixture"}"#) }
            return (202, #"{"nextExpectedRanges":["0-"]}"#)
        }
        do { try await api.upload(large, parent: nil); fatalError("Unexpected chunk offset accepted") } catch { }
        check(FileManager.default.fileExists(atPath: large.path), "Failed chunk upload retains the source")
        let beforeSnapshot = try OneDriveClient.localSnapshot(local)
        try Data("changed".utf8).write(to: local)
        let afterSnapshot = try OneDriveClient.localSnapshot(local)
        check(afterSnapshot != beforeSnapshot, "Same-size edits change source fingerprint")
        let link = fixture.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: local)
        do { _ = try OneDriveClient.localSnapshot(link); fatalError("Link followed") } catch { }
        print("PASS large-file streaming, byte ranges, credential separation, fingerprints, links")

        requests = []
        MockMicrosoft.handler = { request in
            requests.append(request)
            if request.httpMethod == "GET" { return (200, #"{"id":"actual-root","name":"root","folder":{}}"#) }
            let object = try JSONSerialization.jsonObject(with: body(request)) as! [String: Any]
            check((object["parentReference"] as? [String: String])?["id"] == "actual-root", "Move to root uses actual ID")
            check(object["@microsoft.graph.conflictBehavior"] as? String == "fail", "Move refuses name conflicts")
            return (200, "{}")
        }
        try await api.move(file, parent: nil)
        check(requests.map(\.httpMethod) == ["GET", "PATCH"], "Root lookup then server-side move")
        requests = []
        MockMicrosoft.handler = { request in
            requests.append(request)
            let object = try JSONSerialization.jsonObject(with: body(request)) as! [String: Any]
            check(object["name"] as? String == "Grüsse (2).txt", "Keep Both name sent atomically with move")
            check((object["parentReference"] as? [String: String])?["id"] == "target", "Move and rename share one request")
            check(request.value(forHTTPHeaderField: "If-Match") == file.eTag, "Conflict-safe move retains version condition")
            return (200, "{}")
        }
        try await api.move(file, parent: "target", name: "Grüsse (2).txt")
        check(requests.count == 1, "No source rename before successful move")
        MockMicrosoft.handler = { _ in (409, #"{"error":{"code":"nameAlreadyExists"}}"#) }
        do { try await api.move(file, parent: "target"); fatalError("Name collision falsely succeeded") }
        catch OneDriveFailure.nameConflict { }
        print("PASS atomic conflict-name moves and typed 409 failures")
        let folder = try JSONDecoder().decode(OneDriveItem.self, from: Data(#"{"id":"folder","name":"Folder","folder":{},"eTag":"v1"}"#.utf8))
        MockMicrosoft.handler = { request in
            if request.url!.path.hasSuffix("child") { return (200, #"{"id":"child","parentReference":{"id":"folder"}}"#) }
            fatalError("Descendant check must stop before traversing the source")
        }
        do { try await api.validateDestination("child", excluding: "folder"); fatalError("Descendant destination accepted") } catch { }
        print("PASS server-side move, real root ID, collisions, descendant protection")

        let nested = fixture.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("abc".utf8).write(to: nested.appendingPathComponent("child.txt"))
        requests = []
        MockMicrosoft.handler = { request in
            requests.append(request)
            if request.httpMethod == "POST" { return (201, #"{"id":"new-folder","name":"Nested","folder":{}}"#) }
            check(request.url!.path.contains("new-folder:/child.txt:/content"), "Child uploaded into created directory")
            return (201, #"{"id":"new-child","name":"child.txt","size":3}"#)
        }
        try await api.uploadTree(nested, parent: nil)
        check(requests.map(\.httpMethod) == ["POST", "PUT"], "Folder and child upload")
        var version = "v1"
        var deletes = 0
        let versioned = try JSONDecoder().decode(OneDriveItem.self, from: Data(#"{"id":"versioned","name":"test.txt","size":3,"eTag":"v1"}"#.utf8))
        MockMicrosoft.handler = { request in
            if request.httpMethod == "DELETE" {
                deletes += 1
                check(request.value(forHTTPHeaderField: "If-Match") == "v1", "Move deletion is conditional on source version")
                return (412, "{}")
            }
            return (200, "{\"id\":\"versioned\",\"name\":\"test.txt\",\"size\":3,\"eTag\":\"\(version)\"}")
        }
        let manifest = try await api.remoteSnapshot(versioned)
        version = "v2"
        do { try await api.recycleUnchanged(versioned, snapshot: manifest); fatalError("Changed source removed") } catch { }
        check(deletes == 0, "Changed remote source never deleted")
        version = "v1"
        do { try await api.recycleUnchanged(versioned, snapshot: manifest); fatalError("Failed conditional removal accepted") } catch { }
        check(deletes == 1, "Conditional failure propagates")
        MockMicrosoft.handler = { request in
            if request.url!.path.hasSuffix("children") { return (200, #"{"value":[]}"#) }
            check(request.httpMethod != "DELETE", "Folder must never be recursively deleted by a cross-storage move")
            return (200, #"{"id":"folder","name":"Folder","folder":{},"eTag":"v1"}"#)
        }
        let folderManifest = try await api.remoteSnapshot(folder)
        do { try await api.recycleUnchanged(folder, snapshot: folderManifest); fatalError("Folder source removed without an atomic descendant guard") } catch { }
        print("PASS folder upload, source-change protection, conditional deletion failure")

        @MainActor func checkDownload(before: String, after: String, contentBefore: String?, contentAfter: String?, succeeds: Bool) async throws {
            var reads = 0
            var temporary: URL?
            MockMicrosoft.handler = { request in
                if request.url!.host == "login.microsoftonline.com" {
                    return (200, #"{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_in":3600}"#)
                }
                check(request.httpMethod == "GET", "Copy download never mutates its source")
                reads += 1
                var metadata: [String: Any] = ["id": "versioned", "name": "test.txt", "size": 3,
                    "eTag": reads == 1 ? before : after,
                    "@microsoft.graph.downloadUrl": "https://download.example/test"]
                if let tag = reads == 1 ? contentBefore : contentAfter { metadata["cTag"] = tag }
                return (200, String(data: try JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)!)
            }
            let reader = OneDriveClient(clientID: id, session: session, store: MemoryTokens(), downloadFile: { url in
                check(url.host == "download.example", "Only metadata-provided download URL used")
                let staged = fixture.appendingPathComponent("download-" + UUID().uuidString)
                temporary = staged
                try Data("abc".utf8).write(to: staged)
                return (staged, HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
            })
            do {
                // `versioned` was selected with an older v1 eTag. Reads must
                // fetch a fresh version rather than rejecting that stale list.
                let downloaded = try await reader.download(versioned)
                check(succeeds, "Changed content must not be published")
                let content = try String(contentsOf: downloaded, encoding: .utf8)
                check(content == "abc", "Complete current content copied")
                try FileManager.default.removeItem(at: downloaded.deletingLastPathComponent())
            } catch { if succeeds { throw error } }
            check(reads == 2, "Current version checked before and after download")
            if let temporary { check(!FileManager.default.fileExists(atPath: temporary.path), "Downloaded staging cleaned on success/failure") }
        }
        try await checkDownload(before: "fresh-v2", after: "fresh-v2", contentBefore: nil, contentAfter: nil, succeeds: true)
        try await checkDownload(before: "fresh-v2", after: "metadata-v3", contentBefore: "content-v2", contentAfter: "content-v2", succeeds: true)
        try await checkDownload(before: "fresh-v2", after: "edited-v3", contentBefore: "content-v2", contentAfter: "content-v3", succeeds: false)
        try await checkDownload(before: "fresh-v2", after: "edited-v3", contentBefore: nil, contentAfter: nil, succeeds: false)
        try await checkDownload(before: "fresh-v2", after: "metadata-v3", contentBefore: "content-v2", contentAfter: nil, succeeds: false)
        print("PASS fresh download snapshots, stale-list recovery, metadata-only changes and concurrent-content protection")

        MockMicrosoft.handler = { request in
            check(request.url!.query == nil, "Default metadata requested for download annotation")
            let metadata: [String: Any] = ["id": file.id, "name": file.name, "eTag": "fresh", "size": 3,
                "@microsoft.graph.downloadUrl": "http://unsafe.example/fixture"]
            return (200, String(data: try JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)!)
        }
        do { _ = try await api.download(file); fatalError("HTTP download URL accepted") } catch { }
        try api.disconnect(); check(store.value == nil, "Disconnect removes credential")
        let disconnectedCount = requests.count
        do { _ = try await api.children(); fatalError("Disconnected account used") } catch { }
        check(disconnectedCount == requests.count, "No account request after disconnect")
        print("PASS secure download URL guard and disconnect")

        let loginStore = MemoryTokens(); loginStore.value = nil
        let login = OneDriveClient(clientID: id, session: session, store: loginStore)
        var polls = 0
        MockMicrosoft.handler = { request in
            if request.url!.path.hasSuffix("devicecode") {
                return (200, #"{"device_code":"fixture-device","user_code":"FIXTURE","verification_uri":"https://microsoft.com/devicelogin","expires_in":30,"interval":1}"#)
            }
            polls += 1
            if polls == 1 { return (400, #"{"error":"authorization_pending"}"#) }
            return (200, #"{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_in":3600}"#)
        }
        let code = try await login.beginLogin()
        try await login.completeLogin(code)
        check(polls == 2 && loginStore.value == "fixture-refresh", "Device polling persists authorized credential")
        let cancelled = Task { try await login.completeLogin(code) }
        cancelled.cancel()
        do { try await cancelled.value; fatalError("Cancelled login continued") } catch is CancellationError { }
        check(polls == 2, "Cancelled login makes no requests")
        let expired = OneDriveDeviceCode(device_code: "expired", user_code: "EXPIRED", verification_uri: "https://microsoft.com/devicelogin", expires_in: 0, interval: 1)
        do { try await login.completeLogin(expired); fatalError("Expired device code accepted") } catch { }
        check(polls == 2, "Expired code makes no token requests")
        print("PASS device-code pending/success and cancellation")

        let deniedStore = MemoryTokens()
        let denied = OneDriveClient(clientID: id, session: session, store: deniedStore)
        MockMicrosoft.handler = { _ in (400, #"{"error":"invalid_grant","error_description":"sensitive fixture"}"#) }
        do { _ = try await denied.children(); fatalError("Expired refresh accepted") }
        catch { check(!error.localizedDescription.contains("sensitive"), "Raw OAuth response is not exposed") }
        check(deniedStore.value == nil, "Revoked refresh token removed")
        print("PASS revoked credential and sanitized OAuth errors")

        var toolName = "Kind.txt", toolTag = "v1"
        let toolClient = OneDriveClient(clientID: id, session: session, store: MemoryTokens(), downloadFile: { url in
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("abc".utf8).write(to: file)
            return (file, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        MockMicrosoft.handler = { request in
            if request.url!.host == "login.microsoftonline.com" { return (200, #"{"access_token":"fixture-access","expires_in":3600}"#) }
            let path = request.url!.path
            if request.httpMethod == "PATCH" {
                check(request.value(forHTTPHeaderField: "If-Match") == toolTag, "Online tool rename must pin version")
                toolName = (try JSONSerialization.jsonObject(with: body(request)) as! [String: Any])["name"] as! String
                toolTag = "v2"
            }
            let item: [String: Any] = ["id": "tool-file", "name": toolName, "size": 3, "eTag": toolTag,
                "parentReference": ["id": "tool-folder"], "@microsoft.graph.downloadUrl": "https://download.example/fixture"]
            let object: [String: Any]
            if path.hasSuffix("root/children") {
                object = ["value": [["id": "tool-folder", "name": "Ordner", "folder": ["childCount": 1], "eTag": "folder-v1"]]]
            } else if path.hasSuffix("children") { object = ["value": [item]] }
            else { object = item }
            return (200, String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!)
        }
        let parents = try await CommanderOnlineTools.resolve("/Ordner", client: toolClient)
        let found = try await CommanderOnlineTools.scan(toolClient, ancestors: [], hidden: false)
        check(found.contains { $0.path == "Ordner/Kind.txt" }, "Graph recursive tool search")
        let content = try await CommanderOnlineTools.content(toolClient, ancestors: parents, hidden: false)
        check(content["Kind.txt"]?.hasPrefix("sha256:") == true, "Graph content comparison")
        let onlineItem = try await toolClient.children(of: parents.last!.id).first!
        let rename = try await CommanderOnlineTools.renamePlan(toolClient, parent: parents.last!.id, selected: [onlineItem], fields: ["Test-[C][E]", "", "", "1", "3"])
        var toolAudit = 0
        let renamed = try await CommanderOnlineTools.rename(toolClient, plan: rename) { _ in toolAudit += 1 }
        check(renamed == 1 && toolAudit == 1 && toolName == "Test-001.txt", "Graph tool preview/apply/audit")
        print("PASS OneDrive online tools: recursive search, editable path, content comparison and conditional multi-rename")

        var retryCalls = 0, delays: [TimeInterval] = []
        let retryAPI = OneDriveClient(clientID: id, session: session, store: MemoryTokens(), retrySleep: { delays.append($0) })
        MockMicrosoft.handler = { request in
            if request.url!.host == "login.microsoftonline.com" { return (200, #"{"access_token":"fixture-access","expires_in":3600}"#) }
            retryCalls += 1
            return retryCalls < 3 ? (429, "{}") : (200, #"{"value":[]}"#)
        }
        _ = try await retryAPI.children()
        check(retryCalls == 3 && delays == [2, 4], "Read retries are bounded with exponential backoff")
        retryCalls = 0; delays = []; MockMicrosoft.headers = ["Retry-After": "7"]
        _ = try await retryAPI.children()
        check(delays == [7, 7], "Server Retry-After respected")
        retryCalls = 0; delays = []; MockMicrosoft.headers = ["Retry-After": "3600"]
        do { _ = try await retryAPI.children(); fatalError("Long rate limit accepted") } catch { }
        check(retryCalls == 1 && delays.isEmpty, "Long Retry-After does not exceed time budget or retry early")
        MockMicrosoft.headers = [:]; retryCalls = 0; delays = []
        MockMicrosoft.handler = { _ in retryCalls += 1; return (503, "{}") }
        do { try await retryAPI.createFolder("NeverReplay", parent: nil); fatalError("Failed mutation accepted") } catch { }
        check(retryCalls == 1 && delays.isEmpty, "Mutations are never replayed")
        retryCalls = 0
        MockMicrosoft.handler = { _ in retryCalls += 1; return (403, "{}") }
        do { _ = try await retryAPI.children(); fatalError("Denied read accepted") } catch { }
        check(retryCalls == 1, "Permission failures are never retried")
        retryCalls = 0
        MockMicrosoft.handler = { request in
            if request.url!.host == "login.microsoftonline.com" { return (200, #"{"access_token":"fixture-access","expires_in":3600}"#) }
            retryCalls += 1; return (429, "{}")
        }
        let cancelAPI = OneDriveClient(clientID: id, session: session, store: MemoryTokens(), retrySleep: { _ in throw CancellationError() })
        do { _ = try await cancelAPI.children(); fatalError("Cancelled retry continued") } catch is CancellationError { }
        // One OAuth request followed by one Graph read; no second read after cancellation.
        check(retryCalls <= 2, "Cancellation stops retries")
        print("PASS read-only throttling retries, Retry-After, bounded deadline, mutation/permission safety and cancellation")

        var shareRequests = 0
        MockMicrosoft.handler = { request in
            shareRequests += 1
            check(request.httpMethod == "POST" && request.url!.path.hasSuffix("/createLink"), "Share uses createLink mutation")
            let payload = try JSONSerialization.jsonObject(with: body(request)) as! [String: Any]
            check(payload["type"] as? String == "view" && payload["scope"] as? String == "anonymous", "Share grants read-only access")
            check(payload["retainInheritedPermissions"] as? Bool == true, "Existing permissions retained")
            return (201, #"{"link":{"webUrl":"https://1drv.ms/fixture"}}"#)
        }
        let shared = try await retryAPI.createReadOnlyShareLink(file)
        check(shared.absoluteString == "https://1drv.ms/fixture" && shareRequests == 1, "Sharing link returned without automatic copy/open")
        MockMicrosoft.handler = { _ in shareRequests += 1; return (503, "{}") }
        do { _ = try await retryAPI.createReadOnlyShareLink(file); fatalError("Failed share accepted") } catch { }
        check(shareRequests == 2, "Sharing mutation never replayed")
        MockMicrosoft.handler = { _ in (201, #"{"link":{"webUrl":"http://attacker.example/fixture"}}"#) }
        do { _ = try await retryAPI.createReadOnlyShareLink(file); fatalError("Insecure share URL accepted") } catch { }
        print("PASS read-only sharing, retained permissions, no replay, safe link validation")

        MockMicrosoft.handler = { _ in (200, #"{"value":[{"id":"cached","name":"Cache.txt","size":3}]}"#) }
        let fresh = try await retryAPI.browserListing(of: "cache-folder")
        check(fresh.cachedAt == nil && fresh.items.count == 1, "Successful browser listing is fresh")
        retryCalls = 0
        MockMicrosoft.handler = { _ in retryCalls += 1; return (429, "{}") }
        let cached = try await retryAPI.browserListing(of: "cache-folder")
        check(cached.cachedAt != nil && cached.warning != nil && cached.items.first?.id == "cached", "Stale browser listing explicitly marked")
        let cachedRequestCount = retryCalls
        _ = try await retryAPI.browserListing(of: "cache-folder")
        check(retryCalls == cachedRequestCount, "Rate-limited browser requests honor cooldown")
        do { _ = try await retryAPI.children(of: "cache-folder"); fatalError("Mutation/tool listing used stale cache") } catch { }
        check(retryCalls == cachedRequestCount + 3, "Regular children always request fresh data")
        MockMicrosoft.handler = { _ in (200, #"{"value":[]}"#) }
        try await retryAPI.createFolder("InvalidateCache", parent: nil)
        retryCalls = 0; MockMicrosoft.handler = { _ in retryCalls += 1; return (429, "{}") }
        do { _ = try await retryAPI.browserListing(of: "cache-folder"); fatalError("Cache survived mutation") } catch { }
        MockMicrosoft.handler = { _ in (200, #"{"value":[{"id":"private","name":"Private.txt"}]}"#) }
        _ = try await retryAPI.browserListing(of: "private-folder")
        MockMicrosoft.handler = { _ in (403, "{}") }
        do { _ = try await retryAPI.browserListing(of: "private-folder"); fatalError("Permission failure revealed cache") } catch { }
        print("PASS explicit browser-only cache, cooldown, fresh mutation/tool reads, mutation invalidation and permission refusal")
        MockMicrosoft.handler = { _ in (200, #"{"value":[{"id":"bounded","name":"Bounded.txt"}]}"#) }
        for index in 0..<33 { _ = try await retryAPI.browserListing(of: "bounded-\(index)") }
        MockMicrosoft.handler = { _ in (429, "{}") }
        do { _ = try await retryAPI.browserListing(of: "bounded-0"); fatalError("Cache exceeded 32 entries") } catch { }
        let newestCache = try await retryAPI.browserListing(of: "bounded-32")
        check(newestCache.cachedAt != nil, "Newest cached folder survives eviction")
        try retryAPI.disconnect()
        do { _ = try await retryAPI.browserListing(of: "bounded-32"); fatalError("Disconnected account revealed cached content") } catch { }
        print("PASS cache capacity, oldest eviction and disconnect clearing")
        check(!OnlineDisplayPolicy.visible(".hidden", hidden: false), "Online hidden entries respect global preference")
        check(OnlineDisplayPolicy.visible(".hidden", hidden: true) && OnlineDisplayPolicy.visible("Visible.txt", hidden: false), "Hidden toggle preserves ordinary entries")
        check(OnlineDisplayPolicy.modifiedDate("bad timestamp") == "—" && OnlineDisplayPolicy.modifiedDate(nil) == "—", "Malformed provider dates are not displayed as dates")
        check(OnlineDisplayPolicy.modifiedDate("2026-10-12T12:30:00Z") != "—" && OnlineDisplayPolicy.modifiedDate("2026-10-12T12:30:00.123Z") != "—", "Provider dates support both ISO precision variants")
        let sameDate = ISO8601DateFormatter().date(from: "2026-10-12T12:30:00Z")!
        check(OnlineDisplayPolicy.modifiedDate("2026-10-12T12:30:00Z") == OnlineDisplayPolicy.localDate(sameDate), "Local and online columns use the same timestamp format")
        check(OnlineDisplayPolicy.modifiedDate(String(repeating: "1", count: 65)) == "—", "Oversized provider date rejected")
        print("PASS online visibility policy and robust provider timestamps")

        let reads = SharedDirectoryReads<Int>()
        var sharedLoads = 0
        let firstWaiter = Task { try await reads.value(for: "folder") {
            sharedLoads += 1; try await Task.sleep(nanoseconds: 100_000_000); return 42
        } }
        while sharedLoads == 0 { await Task.yield() }
        let secondWaiter = Task { try await reads.value(for: "folder") { sharedLoads += 1; return -1 } }
        await Task.yield()
        firstWaiter.cancel()
        do { _ = try await firstWaiter.value; fatalError("Cancelled waiter returned a listing") } catch is CancellationError {} catch { fatalError("Wrong cancellation error") }
        let sharedValue = try await secondWaiter.value
        check(sharedValue == 42 && sharedLoads == 1, "One cancelled pane does not cancel another pane or duplicate I/O")
        var pendingStarted = false
        let invalidatedWaiter = Task { try await reads.value(for: "invalidated") {
            pendingStarted = true; try await Task.sleep(nanoseconds: 10_000_000_000); return 1
        } }
        while !pendingStarted { await Task.yield() }
        reads.invalidate()
        do { _ = try await invalidatedWaiter.value; fatalError("Invalidated listing survived account/mutation change") } catch is CancellationError {} catch { fatalError("Wrong invalidation error") }
        let afterInvalidation = try await reads.value(for: "invalidated") { 7 }
        check(afterInvalidation == 7, "Fresh load after invalidation is not overwritten by old task")
        print("PASS shared display reads, per-waiter cancellation and mutation/account invalidation")

        let concurrentStore = MemoryTokens()
        let concurrentAPI = OneDriveClient(clientID: id, session: session, store: concurrentStore)
        let counterLock = NSLock()
        var refreshCount = 0
        MockMicrosoft.handler = { request in
            if request.url?.host == "login.microsoftonline.com" {
                counterLock.lock(); refreshCount += 1; counterLock.unlock()
                Thread.sleep(forTimeInterval: 0.05)
                return (200, #"{"access_token":"shared-access","refresh_token":"shared-refresh","expires_in":3600}"#)
            }
            return (200, #"{"value":[]}"#)
        }
        async let concurrentLeft = concurrentAPI.children(of: "left")
        async let concurrentRight = concurrentAPI.children(of: "right")
        _ = try await (concurrentLeft, concurrentRight)
        check(refreshCount == 1, "Concurrent directory reads share one credential refresh")
        let revokedStore = MemoryTokens()
        let revokedAPI = OneDriveClient(clientID: id, session: session, store: revokedStore)
        var refreshStarted = false
        MockMicrosoft.handler = { request in
            if request.url?.host == "login.microsoftonline.com" {
                counterLock.lock(); refreshStarted = true; counterLock.unlock()
                Thread.sleep(forTimeInterval: 0.05)
                return (200, #"{"access_token":"old-access","refresh_token":"old-refresh","expires_in":3600}"#)
            }
            return (200, #"{"value":[]}"#)
        }
        let revokedRead = Task { try await revokedAPI.children() }
        while true {
            let started = counterLock.withLock { refreshStarted }
            if started { break }; await Task.yield()
        }
        try revokedAPI.disconnect()
        do { _ = try await revokedRead.value; fatalError("Read survived disconnect") } catch {}
        check(revokedStore.value == nil, "An in-flight refresh cannot restore a disconnected account")
        print("PASS shared token refresh and disconnect generation guard preserve account isolation")
    }
}
