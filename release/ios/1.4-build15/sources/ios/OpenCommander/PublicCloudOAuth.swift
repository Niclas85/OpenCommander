import Foundation
import CryptoKit
import Darwin

/// Publisher credentials describe a desktop application, never a user account.
/// The schema matches Linux public_oauth.py. Microsoft/Dropbox need no secret.
struct PublicCloudOAuth: Equatable {
    let clientID: String
    let clientSecret: String
    let pkce: Bool
    static func decode(_ data: Data, kind: String) throws -> Self {
        guard data.count <= 16 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudConnection.failure("cloud_oauth_client_invalid")
        }
        var values = object
        if kind == "drive", let installed = object["installed"] as? [String: Any] {
            guard Set(object.keys) == ["installed"] else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
            values = installed
        }
        guard let clientID = values["client_id"] as? String else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
        if kind == "drive" {
            let allowed: Set<String> = ["client_id", "client_secret", "project_id", "auth_uri", "token_uri", "auth_provider_x509_cert_url", "redirect_uris"]
            guard Set(values.keys).isSubset(of: allowed),
                clientID.range(of: #"^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com\z"#, options: .regularExpression) != nil,
                let secret = values["client_secret"] as? String, !secret.isEmpty, secret.utf8.count <= 1024,
                !secret.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                throw CloudConnection.failure("cloud_oauth_client_invalid")
            }
            return Self(clientID: clientID, clientSecret: secret, pkce: false)
        }
        let pattern: String
        switch kind {
        case "onedrive": pattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\z"#
        case "dropbox": pattern = #"^[A-Za-z0-9]{10,64}\z"#
        default: throw CloudConnection.failure("cloud_oauth_client_invalid")
        }
        guard Set(values.keys) == ["client_id", "flow"], values["flow"] as? String == "pkce",
            clientID.range(of: pattern, options: .regularExpression) != nil else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
        return Self(clientID: clientID, clientSecret: "", pkce: true)
    }
    func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: pkce ? ["client_id": clientID, "flow": "pkce"] : ["client_id": clientID, "client_secret": clientSecret])
    }
    static func bundled(kind: String, bundle: Bundle = .main) throws -> Self? {
        let names = ["drive": "google", "onedrive": "onedrive", "dropbox": "dropbox"]
        guard let name = names[kind], let url = bundle.url(forResource: name + "-oauth", withExtension: "json") else { return nil }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0, info.st_size <= 16 * 1024 else {
            throw CloudConnection.failure("cloud_oauth_client_invalid")
        }
        return try decode(handle.read(upToCount: 16 * 1024 + 1) ?? Data(), kind: kind)
    }
}

#if os(macOS)
/// Fixed official endpoints, fresh verifier/state, loopback-only callback and
/// cancellable bounded exchange. Runs on the bridge's background worker.
enum NativeCloudOAuth {
    static let redirect = "http://localhost:53682/"
    static func scope(kind: String) throws -> String {
        switch kind {
        case "onedrive": return "Files.ReadWrite.All offline_access User.Read"
        case "dropbox": return "account_info.read files.metadata.read files.metadata.write files.content.read files.content.write sharing.read sharing.write"
        default: throw CloudConnection.failure("cloud_oauth_client_invalid")
        }
    }
    static func endpoint(kind: String, token: Bool) throws -> URL {
        let urls = token ? ["onedrive": "https://login.microsoftonline.com/common/oauth2/v2.0/token", "dropbox": "https://api.dropboxapi.com/oauth2/token"] :
            ["onedrive": "https://login.microsoftonline.com/common/oauth2/v2.0/authorize", "dropbox": "https://www.dropbox.com/oauth2/authorize"]
        guard let text = urls[kind], let url = URL(string: text) else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
        return url
    }
    static func random(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        arc4random_buf(&bytes, bytes.count)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func authorizationURL(kind: String, client: PublicCloudOAuth, state: String, verifier: String) throws -> URL {
        guard client.pkce else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
        var components = URLComponents(url: try endpoint(kind: kind, token: false), resolvingAgainstBaseURL: false)!
        var fields = ["response_type": "code", "client_id": client.clientID, "redirect_uri": redirect,
                      "scope": try scope(kind: kind), "state": state, "code_challenge": challenge(verifier), "code_challenge_method": "S256"]
        if kind == "onedrive" { fields["prompt"] = "select_account" }
        if kind == "dropbox" { fields["token_access_type"] = "offline" }
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
        return url
    }
    static func tokenData(_ data: Data, now: Date = Date()) throws -> Data {
        guard data.count <= 65536, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = object["access_token"] as? String, !access.isEmpty,
            let refresh = object["refresh_token"] as? String, !refresh.isEmpty,
            [access, refresh].allSatisfy({ $0.utf8.count <= 32768 && !$0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }),
            let type = object["token_type"] as? String, type.lowercased() == "bearer",
            let expiry = object["expires_in"] as? NSNumber, CFGetTypeID(expiry) != CFBooleanGetTypeID(),
            expiry.doubleValue >= 1, expiry.doubleValue <= 366 * 86400,
            expiry.doubleValue.rounded(.towardZero) == expiry.doubleValue else { throw CloudConnection.failure("cloud_oauth_token_failed") }
        return try JSONSerialization.data(withJSONObject: ["access_token": access, "refresh_token": refresh, "token_type": type,
            "expiry": ISO8601DateFormatter().string(from: now.addingTimeInterval(expiry.doubleValue))], options: [.sortedKeys])
    }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").utf8)
    }
    static func authorize(kind: String, client: PublicCloudOAuth, check: () throws -> Void, browser: (URL) -> Void) throws -> Data {
        let verifier = random(64), state = random(32)
        try check()
        let receiver = try OAuthLoopbackReceiver(state: state)
        defer { receiver.closeListener() }
        browser(try authorizationURL(kind: kind, client: client, state: state, verifier: verifier))
        let code = try receiver.wait(check: check)
        try check()
        var request = URLRequest(url: try endpoint(kind: kind, token: true), timeoutInterval: 15)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["grant_type": "authorization_code", "client_id": client.clientID,
            "redirect_uri": redirect, "code": code, "code_verifier": verifier])
        return try tokenData(exchangeToken(request, check: check))
    }
    static func exchangeToken(_ request: URLRequest, check: () throws -> Void, configuration: URLSessionConfiguration = .ephemeral) throws -> Data {
        let exchange = OAuthTokenExchange()
        configuration.httpShouldSetCookies = false; configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: exchange, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request); task.resume()
        let deadline = Date().addingTimeInterval(20)
        while exchange.done.wait(timeout: .now() + 0.1) != .success {
            try check(); guard Date() < deadline else { throw CloudConnection.failure("cloud_timeout") }
        }
        try check()
        guard exchange.valid else { throw CloudConnection.failure("cloud_oauth_token_failed") }
        return exchange.data
    }
    /// Write only a NEW private empty config, never replace an existing account.
    static func seed(profile: CloudConnection, client: PublicCloudOAuth, token: Data) throws {
        guard client.pkce, token.count <= 65536, let json = String(data: token, encoding: .utf8), !json.contains(where: \.isNewline) else {
            throw CloudConnection.failure("cloud_oauth_token_failed")
        }
        var body = "[\(profile.remote)]\ntype = \(profile.kind)\nclient_id = \(client.clientID)\nclient_secret =\noc_oauth_flow = pkce\ntoken = \(json)\n"
        if profile.kind == "onedrive" { body += "access_scopes = \(try scope(kind: profile.kind))\ndisable_site_permission = true\n" }
        try writeNew(profile: profile, body: body)
    }
    static func seedGoogle(profile: CloudConnection, client: PublicCloudOAuth) throws {
        guard profile.kind == "drive", !client.pkce else { throw CloudConnection.failure("cloud_oauth_client_invalid") }
        try writeNew(profile: profile, body: "[\(profile.remote)]\ntype = drive\nclient_id = \(client.clientID)\nclient_secret = \(client.clientSecret)\n")
    }
    private static func writeNew(profile: CloudConnection, body: String) throws {
        try profile.validate()
        let descriptor = open(profile.configPath, O_WRONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CloudConnection.failure("cloud_config_private") }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
            info.st_mode & 0o077 == 0, info.st_nlink == 1, info.st_size == 0 else { throw CloudConnection.failure("cloud_config_changed") }
        let bytes = Data(body.utf8)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw CloudConnection.failure("cloud_config_private") }; offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw CloudConnection.failure("cloud_config_private") }
    }
}

final class OAuthLoopbackReceiver {
    private var listener: Int32
    let state: String
    let port: UInt16
    init(state: String, port: UInt16 = 53682) throws {
        listener = socket(AF_INET, SOCK_STREAM, 0); self.state = state
        guard listener >= 0 else { throw CloudConnection.failure("cloud_oauth_port_busy") }
        let descriptor = listener
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var reuse: Int32 = 1; setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        let bound = withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(listener, 8) == 0 else { Darwin.close(listener); listener = -1; throw CloudConnection.failure("cloud_oauth_port_busy") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        guard named == 0 else { Darwin.close(listener); listener = -1; throw CloudConnection.failure("cloud_oauth_port_busy") }
        self.port = UInt16(bigEndian: address.sin_port)
    }
    deinit { closeListener() }
    func closeListener() { if listener >= 0 { Darwin.close(listener); listener = -1 } }
    enum Reply { case invalid, denied, code(String) }
    func parse(_ data: Data) -> Reply {
        guard data.count <= 16 * 1024, let text = String(data: data, encoding: .utf8), text.hasSuffix("\r\n\r\n") else { return .invalid }
        let lines = text.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").components(separatedBy: " ")
        guard request.count == 3, request[0] == "GET", ["HTTP/1.0", "HTTP/1.1"].contains(request[2]), request[1].hasPrefix("/?"),
            let components = URLComponents(string: "http://localhost" + request[1]), components.path == "/", components.fragment == nil else { return .invalid }
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        guard hosts.count == 1, ["localhost:\(port)", "127.0.0.1:\(port)"].contains(hosts[0]) else { return .invalid }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, let received = states.first?.value, constantEqual(received, state) else { return .invalid }
        if items.contains(where: { $0.name == "error" }) { return .denied }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty, code.utf8.count <= 8192, !code.contains("\0") else { return .invalid }
        return .code(code)
    }
    private func constantEqual(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8), rhs = Array(b.utf8)
        guard lhs.count == rhs.count else { return false }
        var value: UInt8 = 0; for index in lhs.indices { value |= lhs[index] ^ rhs[index] }; return value == 0
    }
    func wait(timeout: TimeInterval = 600, check: () throws -> Void) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try check()
            var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let result = poll(&ready, 1, 100)
            if result < 0 && errno == EINTR { continue }
            guard result >= 0 else { throw CloudConnection.failure("cloud_oauth_token_failed") }
            if result == 0 { continue }
            let peer = accept(listener, nil, nil)
            if peer < 0 { continue }
            defer { Darwin.close(peer) }
            var noSignal: Int32 = 1; setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(peer, F_SETFL, O_NONBLOCK)
            var request = Data(); let connectionDeadline = min(deadline, Date().addingTimeInterval(0.5))
            while Date() < connectionDeadline && request.count <= 16 * 1024 && !request.suffix(4).elementsEqual([13, 10, 13, 10]) {
                try check()
                var readable = pollfd(fd: peer, events: Int16(POLLIN), revents: 0)
                if poll(&readable, 1, 50) <= 0 { continue }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = recv(peer, &bytes, bytes.count, 0)
                if count <= 0 { break }; request.append(contentsOf: bytes.prefix(count))
            }
            let reply = parse(request)
            let valid: Bool; switch reply { case .invalid: valid = false; default: valid = true }
            let body = valid ? "Sign-in received. Return to OpenCommander. / Anmeldung empfangen. Zurück zu OpenCommander." : "Invalid callback."
            let response = Data("HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n\(body)".utf8)
            _ = response.withUnsafeBytes { send(peer, $0.baseAddress, $0.count, 0) }
            try check()
            switch reply {
            case .code(let code): return code
            case .denied: throw CloudConnection.failure("cloud_oauth_denied")
            case .invalid: continue
            }
        }
        throw CloudConnection.failure("cloud_timeout")
    }
}

private final class OAuthTokenExchange: NSObject, URLSessionDataDelegate {
    let done = DispatchSemaphore(value: 0)
    var data = Data()
    private var responseOK = false, failed = false
    var valid: Bool { responseOK && !failed && !data.isEmpty }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { failed = true; completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        responseOK = (response as? HTTPURLResponse)?.statusCode == 200
        if response.expectedContentLength > 65536 || !responseOK { failed = true; completionHandler(.cancel) } else { completionHandler(.allow) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard chunk.count <= 65536 - data.count else { failed = true; dataTask.cancel(); return }; data.append(chunk)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { if error != nil { failed = true }; done.signal() }
}
#endif
