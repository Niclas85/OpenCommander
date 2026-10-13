import Foundation
import Darwin
func require(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
func rejects(_ body: () throws -> Void, key: String? = nil) {
    do { try body(); fatalError("unsafe input accepted") }
    catch { if let key { require((error as NSError).localizedDescription == key, "unsanitized/wrong error") } }
}
func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
let id = "00000000-1111-2222-3333-444444444444"
let microsoft = try PublicCloudOAuth.decode(json(["client_id": id, "flow": "pkce"]), kind: "onedrive")
let dropbox = try PublicCloudOAuth.decode(json(["client_id": "synthetic123456", "flow": "pkce"]), kind: "dropbox")
let google = try PublicCloudOAuth.decode(json(["installed": ["client_id": "synthetic.apps.googleusercontent.com", "client_secret": "synthetic-desktop"]]), kind: "drive")
require(microsoft.pkce && dropbox.pkce && !google.pkce, "public client flow lost")
require(try PublicCloudOAuth.decode(google.encoded(), kind: "drive") == google, "Google wire schema differs")
for value: [String: Any] in [["client_id": id, "flow": "pkce", "client_secret": "SYNTHETIC_SERVER_SECRET"],
                             ["client_id": id, "flow": "pkce", "token": "SYNTHETIC_TOKEN"],
                             ["client_id": id, "flow": "implicit"], ["client_id": "invalid", "flow": "pkce"],
                             ["client_id": id + "\n", "flow": "pkce"]] {
    rejects({ _ = try PublicCloudOAuth.decode(json(value), kind: "onedrive") }, key: "cloud_oauth_client_invalid")
}
for value: [String: Any] in [["web": ["client_id": "synthetic.apps.googleusercontent.com", "client_secret": "server"]],
                             ["client_id": "synthetic.apps.googleusercontent.com", "client_secret": "x\nmalicious"],
                             ["installed": ["client_id": "synthetic.apps.googleusercontent.com", "client_secret": "synthetic"], "access_token": "SYNTHETIC"]] {
    rejects({ _ = try PublicCloudOAuth.decode(json(value), kind: "drive") }, key: "cloud_oauth_client_invalid")
}
rejects({ _ = try PublicCloudOAuth.decode(Data(repeating: 65, count: 16385), kind: "onedrive") }, key: "cloud_oauth_client_invalid")
print("PASS publisher schema matches Linux: desktop Google, secret-free Microsoft/Dropbox, tokens/server credentials/oversize rejected")

// RFC 7636 reference vector: verify S256 rather than silently falling back to plain.
require(NativeCloudOAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "S256 vector")
let randomA = NativeCloudOAuth.random(64), randomB = NativeCloudOAuth.random(64)
require(randomA != randomB && randomA.count == 86 && !randomA.contains("="), "verifiers not fresh/base64url")
for (kind, client) in [("onedrive", microsoft), ("dropbox", dropbox)] {
    let url = try NativeCloudOAuth.authorizationURL(kind: kind, client: client, state: "synthetic-state", verifier: randomA)
    let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
    require(url.scheme == "https" && query["code_challenge_method"] == "S256" && query["redirect_uri"] == "http://localhost:53682/", "OAuth contract")
    require(query["client_secret"] == nil && query["code_verifier"] == nil && query["response_type"] == "code", "authorization exposed secret/verifier")
    require(query["scope"] == (try NativeCloudOAuth.scope(kind: kind)), "different Linux scopes")
    if kind == "dropbox" { require(query["token_access_type"] == "offline", "missing offline access") }
}
let body = String(decoding: NativeCloudOAuth.form(["code": "a&b+c=ä", "client_id": id]), as: UTF8.self)
require(body.contains("a%26b%2Bc%3D%C3%A4"), "form injection")
print("PASS fresh PKCE/state, RFC S256 vector, official endpoints, offline scopes, loopback redirect and bounded form encoding")

let receiver = try OAuthLoopbackReceiver(state: "expected-state", port: 0)
func callback(_ target: String, host: String? = nil, extra: String = "") -> Data {
    Data("GET \(target) HTTP/1.1\r\nHost: \(host ?? "localhost:\(receiver.port)")\r\n\(extra)\r\n".utf8)
}
func invalid(_ data: Data) { if case .invalid = receiver.parse(data) {} else { fatalError("callback bypass") } }
invalid(callback("/?state=wrong&code=synthetic"))
invalid(callback("/?state=expected-state&state=expected-state&code=synthetic"))
invalid(callback("/?state=expected-state&code=one&code=two"))
invalid(callback("/?state=expected-state&code=synthetic", host: "attacker.example"))
invalid(callback("/?state=expected-state&code=synthetic", extra: "Host: localhost:\(receiver.port)\r\n"))
invalid(callback("/other?state=expected-state&code=synthetic"))
invalid(callback("/?state=expected-state&code=synthetic#fragment"))
invalid(callback("/?state=expected-state&code=%00"))
invalid(Data(repeating: 65, count: 16385))
if case .denied = receiver.parse(callback("/?state=expected-state&error=access_denied")) {} else { fatalError("denial not propagated") }
if case .code(let code) = receiver.parse(callback("/?state=expected-state&code=a%2Bb")) { require(code == "a+b", "code decoding") } else { fatalError("valid callback refused") }
rejects({ _ = try OAuthLoopbackReceiver(state: "other", port: receiver.port) }, key: "cloud_oauth_port_busy")
rejects { _ = try receiver.wait(timeout: 1) { throw CancellationError() } }
rejects({ _ = try receiver.wait(timeout: 0.05) {} }, key: "cloud_timeout")
print("PASS callback Host/state/duplicate/path/fragment/code bounds, denial, port conflict, cancellation and timeout")

// Actual loopback socket, no browser/account, no external service.
DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
    let peer = socket(AF_INET, SOCK_STREAM, 0); defer { close(peer) }
    var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = receiver.port.bigEndian
    let connected = withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(peer, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    require(connected == 0, "loopback test couldn't connect")
    let request = callback("/?state=expected-state&code=SYNTHETIC_CODE")
    _ = request.withUnsafeBytes { send(peer, $0.baseAddress, $0.count, 0) }
    var response = [UInt8](repeating: 0, count: 4096); let count = recv(peer, &response, response.count, 0)
    let text = String(decoding: response.prefix(max(0, count)), as: UTF8.self)
    require(text.contains("Cache-Control: no-store") && !text.contains("SYNTHETIC_CODE"), "callback leaks auth code")
}
require(try receiver.wait(timeout: 2) {} == "SYNTHETIC_CODE", "loopback didn't deliver code")
receiver.closeListener()
print("PASS real loopback callback receives code and returns no-store response without echoing credentials")

let validToken: [String: Any] = ["access_token": "SYNTHETIC_ACCESS", "refresh_token": "SYNTHETIC_REFRESH", "token_type": "Bearer", "expires_in": 3600]
let token = try NativeCloudOAuth.tokenData(json(validToken), now: Date(timeIntervalSince1970: 0))
let decoded = try JSONSerialization.jsonObject(with: token) as! [String: Any]
require(decoded["expiry"] as? String == "1970-01-01T01:00:00Z", "expiry differs")
for (key, value): (String, Any) in [("refresh_token", ""), ("access_token", ""), ("access_token", "synthetic\0token"), ("token_type", "Basic"), ("expires_in", true), ("expires_in", 0), ("expires_in", 1.5), ("expires_in", 999999999)] {
    var bad = validToken; bad[key] = value
    rejects({ _ = try NativeCloudOAuth.tokenData(json(bad)) }, key: "cloud_oauth_token_failed")
}
rejects({ _ = try NativeCloudOAuth.tokenData(Data(repeating: 65, count: 65537)) }, key: "cloud_oauth_token_failed")
print("PASS token exchange schema: refresh required, bounded Bearer tokens, valid integral expiry, no raw errors")

final class SyntheticTokenProtocol: URLProtocol {
    static var body = Data(), status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyntheticTokenProtocol.self]
let request = URLRequest(url: try NativeCloudOAuth.endpoint(kind: "onedrive", token: true))
SyntheticTokenProtocol.body = try json(validToken)
require(try NativeCloudOAuth.exchangeToken(request, check: {}, configuration: config) == SyntheticTokenProtocol.body, "exchange lost data")
SyntheticTokenProtocol.body = Data(repeating: 65, count: 65537)
rejects({ _ = try NativeCloudOAuth.exchangeToken(request, check: {}, configuration: config) }, key: "cloud_oauth_token_failed")
SyntheticTokenProtocol.status = 400; SyntheticTokenProtocol.body = Data("SYNTHETIC_SECRET_IN_SERVER_ERROR".utf8)
rejects({ _ = try NativeCloudOAuth.exchangeToken(request, check: {}, configuration: config) }, key: "cloud_oauth_token_failed")
print("PASS bounded HTTP token exchange and sanitized failure via isolated mock transport (no provider account)")

let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommander-OAuth-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: root) }
let path = root.appendingPathComponent("rclone.conf")
try Data().write(to: path, options: .withoutOverwriting); chmod(path.path, 0o600)
let profile = CloudConnection(name: "Synthetic", kind: "onedrive", remote: "oc_test", configPath: path.path)
try NativeCloudOAuth.seed(profile: profile, client: microsoft, token: token)
let original = try Data(contentsOf: path)
require(String(decoding: original, as: UTF8.self).contains("oc_oauth_flow = pkce"), "missing backend flow identity")
rejects({ try NativeCloudOAuth.seed(profile: profile, client: microsoft, token: token) }, key: "cloud_config_changed")
require(try Data(contentsOf: path) == original, "existing account changed")
let linked = root.appendingPathComponent("linked"); try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: path)
var symlinkProfile = profile; symlinkProfile.configPath = linked.path
rejects({ try NativeCloudOAuth.seed(profile: symlinkProfile, client: microsoft, token: token) }, key: "cloud_config_private")
let googlePath = root.appendingPathComponent("google.conf"); try Data().write(to: googlePath); chmod(googlePath.path, 0o600)
var googleProfile = profile; googleProfile.kind = "drive"; googleProfile.configPath = googlePath.path
try NativeCloudOAuth.seedGoogle(profile: googleProfile, client: google)
require(try String(contentsOf: googlePath, encoding: .utf8).contains("client_secret = synthetic-desktop"), "desktop identity not preserved for refresh")
print("PASS private new configuration seed, existing account unchanged, symlink refusal, Google desktop identity persists outside arguments")
