import Foundation
import Darwin
func require(_ test: Bool, _ message: String) { if !test { fatalError(message) } }
func rejects(_ action: () throws -> Void) { do { try action(); fatalError("unsafe input accepted") } catch {} }
let profile = CloudConnection(name: "Drive", kind: "drive", remote: "OpenCommander", root: "Ordner", configPath: "/private/tmp/own.conf")
let sessionSuite = "OpenCommander-Session-Test-" + UUID().uuidString
let sessionDefaults = UserDefaults(suiteName: sessionSuite)!
defer { sessionDefaults.removePersistentDomain(forName: sessionSuite) }
let onlineSession = OnlinePaneSession(location: "cloud://" + UUID().uuidString, components: ["Grüsse", "Sub"])
onlineSession.save("1", defaults: sessionDefaults)
require(OnlinePaneSession.load("1", defaults: sessionDefaults) == onlineSession, "online navigation not persisted")
require(OnlinePaneSession.load("2", defaults: sessionDefaults) == nil, "pane sessions mixed")
for bad in ["..", "a/b", "a\\b", "", "a\u{0}"] {
    require(!OnlinePaneSession(location: onlineSession.location, components: [bad]).valid, "unsafe saved online path")
}
require(!OnlinePaneSession(location: "https://untrusted.invalid", components: []).valid, "external URL accepted as saved connection")
require(!OnlinePaneSession(location: "cloud://not-a-uuid", components: []).valid, "invalid connection identifier")
let sessionJSON = String(decoding: try JSONEncoder().encode(onlineSession), as: UTF8.self)
require(!sessionJSON.contains("token") && !sessionJSON.contains("password") && !sessionJSON.contains("configPath"), "navigation persisted credentials")
print("PASS per-pane online navigation persistence, Unicode and unsafe/malformed reference refusal without credentials")
let args = try RcloneCommandPlan.arguments(profile: profile, operation: "upload", path: "--config=evil.txt", local: URL(fileURLWithPath: "/private/tmp/Test ä.txt"))
require(args.suffix(3) == ["--", "/private/tmp/Test ä.txt", "OpenCommander:Ordner/--config=evil.txt"], "path escaped into CLI flags")
require(args.contains("--immutable") && args.contains("--low-level-retries"), "guardrails absent")
for path in ["../evil", "/absolute", "a//b", "a/./b", "a/../b", "a\0b"] {
    rejects { _ = try RcloneCommandPlan.arguments(profile: profile, operation: "list", path: path) }
}
rejects { _ = try RcloneCommandPlan.arguments(profile: profile, operation: "purge", path: "folder") }
rejects { _ = try RcloneCommandPlan.arguments(profile: profile, operation: "rename", path: "folder", destination: "folder/sub") }
rejects { _ = try RcloneCommandPlan.arguments(profile: profile, operation: "deletefile", path: "") }
let literal = try profile.address("a:b\n*.txt")
require(literal == "OpenCommander:Ordner/a:b\n*.txt", "valid cloud filename changed")
print("PASS cloud profile validation, argument boundaries, immutable writes, non-replay and safe root/cycle refusal")
var unicodeApple = profile
unicodeApple.kind = "iclouddrive"
unicodeApple.root = "Gru\u{308}sse"
let decomposedName = "Pru\u{308}fung.txt"
let expectedApple = "OpenCommander:Grüsse/Prüfung.txt"
require(Array(try unicodeApple.address(decomposedName).utf8) == Array(expectedApple.utf8), "iCloud wire path not NFC")
let appleRename = try RcloneCommandPlan.arguments(profile: unicodeApple, operation: "rename", path: decomposedName, destination: "Zwe\u{308}i.txt")
require(Array(appleRename[appleRename.count - 2].utf8) == Array(expectedApple.utf8), "iCloud rename source not NFC")
require(Array(appleRename.last!.utf8) == Array("OpenCommander:Grüsse/Zwëi.txt".utf8), "iCloud rename destination not NFC")
for provider in ["drive", "dropbox", "onedrive"] {
    var literalProfile = unicodeApple; literalProfile.kind = provider
    require(Array(try literalProfile.address(decomposedName).utf8) == Array(("OpenCommander:" + unicodeApple.root + "/" + decomposedName).utf8), "non-iCloud spelling changed")
}
print("PASS iCloud NFC source/destination wire paths and unchanged literal names for other providers")
var dropboxProfile = profile; dropboxProfile.kind = "dropbox"
for operation in ["copy", "copytree", "renametree", "upload", "download", "list"] {
    let plan = try RcloneCommandPlan.arguments(profile: dropboxProfile, operation: operation,
        path: "Source", destination: "Destination", local: URL(fileURLWithPath: "/private/tmp/fixture"))
    require(plan.contains("--transfers") && plan[plan.firstIndex(of: "--transfers")! + 1] == "1", "Dropbox concurrent writes enabled")
    require(plan.contains("--dropbox-batch-mode") && plan[plan.firstIndex(of: "--dropbox-batch-mode")! + 1] == "sync", "Dropbox asynchronous commit enabled")
    require(plan[plan.firstIndex(of: "--retries")! + 1] == "1", "Dropbox mutation retry silently enabled")
    if operation == "copy" || operation == "copytree" {
        require(plan.contains("--disable") && plan[plan.firstIndex(of: "--disable")! + 1] == "Copy", "Dropbox fragile server copy enabled")
    }
}
for code in ["from_write/too_many_write_operations/", "too_many_requests/."] {
    let failure = CloudProviderErrors.classify(Data((code + " SYNTHETIC_SECRET").utf8))
    require(CloudProviderErrors.cooldown(failure) == 15 && failure.localizedDescription == "cloud_rate_limited", "Dropbox namespace contention not classified")
    require(!failure.localizedDescription.contains("SYNTHETIC"), "Dropbox error leaked provider response")
}
print("PASS Dropbox writes serialized with synchronous completion; namespace contention sanitized without automatic mutation retry")
func validateConfig(_ body: String, kind: String = "drive") throws {
    var selected = profile; selected.kind = kind
    try CloudConfigurationValidator.validate(Data(body.utf8), profile: selected)
}
for body in ["[OpenCommander]\ntype = drive\n", "[OpenCommander]\ntype = drive\ntoken = invalid-json\n",
             "[OpenCommander]\ntype = drive\ntoken = {\"access_token\":\"\"}\n",
             "[Other]\ntype = drive\ntoken = {\"access_token\":\"synthetic\"}\n",
             "RCLONE_ENCRYPT_V0:\nopaque", "[OpenCommander]\ntype = drive\ntype = drive\n",
             "[OpenCommander]\ntype = drive\n[OpenCommander]\ntoken = {}\n"] {
    rejects { try validateConfig(body) }
}
try validateConfig("[OpenCommander]\ntype = drive\ntoken = {\"access_token\":\"synthetic\"}\n")
rejects { try validateConfig("[OpenCommander]\ntype = onedrive\ntoken = {\"access_token\":\"synthetic\"}\n", kind: "onedrive") }
try validateConfig("[OpenCommander]\ntype = onedrive\ntoken = {\"access_token\":\"synthetic\"}\ndrive_id = synthetic-drive\ndrive_type = personal\n", kind: "onedrive")
let syntheticObscured = Data(repeating: 43, count: 24).base64EncodedString()
let apple = "[OpenCommander]\ntype = iclouddrive\napple_id = test@example.invalid\npassword = \(syntheticObscured)\n"
rejects { try validateConfig(apple, kind: "iclouddrive") }
rejects { try validateConfig(apple + "trust_token = synthetic\n", kind: "iclouddrive") }
try validateConfig(apple + "trust_token = synthetic\ncookies = synthetic\n", kind: "iclouddrive")
require(!CloudConfigurationValidator.obscured("plaintext!") && !CloudConfigurationValidator.obscured(""), "plaintext accepted as obscure wire format")
print("PASS cloud setup validation: selected account, OAuth token, OneDrive drive, iCloud encoded password/device verification, malformed config refusal")
let testArgumentHelper = ProcessInfo.processInfo.environment["OPENCOMMANDER_TEST_ARGUMENT_HELPER"].map { URL(fileURLWithPath: $0) }
let runner = RcloneProcessRunner(argumentHelper: testArgumentHelper)
require(testArgumentHelper != nil, "native argument helper not provided")
for spelling in ["Grüsse/Prüfung.txt", "Gru\u{308}sse/Pru\u{308}fung.txt", "--not-a-flag; $(echo nope)"] {
    let echoed = try runner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", spelling], id: UUID().uuidString)
    require(echoed == Data(spelling.utf8), "process changed literal UTF-8 arguments")
}
print("PASS native child argv preserves NFC, NFD and literal shell metacharacters byte-for-byte")
rejects { _ = try runner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", "a\u{0}b"], id: UUID().uuidString) }
let cleanEnvironment = try runner.run(URL(fileURLWithPath: "/usr/bin/env"), [], id: UUID().uuidString)
require(!String(decoding: cleanEnvironment, as: UTF8.self).contains("OPENCOMMANDER_CLOUD_ARGV"), "argument envelope leaked into provider environment")
print("PASS native argument helper refuses embedded NUL and strips its envelope before exec")
let binaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommander-RuntimeCache-" + UUID().uuidString)
try FileManager.default.createDirectory(at: binaryRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: binaryRoot) }
let binaryFixture = binaryRoot.appendingPathComponent("rclone")
let markerFixture = binaryRoot.appendingPathComponent("binary-sha256.txt")
try Data("synthetic executable A".utf8).write(to: binaryFixture)
require(chmod(binaryFixture.path, 0o700) == 0, "executable fixture mode")
let initialDigest = try RcloneRuntime.hash(binaryFixture)
try Data(initialDigest.utf8).write(to: markerFixture)
let cachedRuntime = RcloneRuntime(root: binaryRoot, runner: runner)
for _ in 0..<20 { _ = try cachedRuntime.executable(id: "cache-proof") }
require(cachedRuntime.binaryVerificationCount == 1, "unchanged binary rehashed for every request")
let nextRequestRuntime = RcloneRuntime(root: binaryRoot, runner: runner)
_ = try nextRequestRuntime.executable(id: "next-request-proof")
require(nextRequestRuntime.binaryVerificationCount == 0, "bridge request discarded process-local binary proof")
let originalDate = try FileManager.default.attributesOfItem(atPath: binaryFixture.path)[.modificationDate] as! Date
try Data("synthetic executable B".utf8).write(to: binaryFixture)
try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: binaryFixture.path)
rejects { _ = try cachedRuntime.executable(id: "modified-proof") }
try Data("synthetic executable A".utf8).write(to: binaryFixture)
_ = try cachedRuntime.executable(id: "restored-proof")
try Data(String(repeating: "0", count: 64).utf8).write(to: markerFixture)
rejects { _ = try cachedRuntime.executable(id: "marker-proof") }
try Data(initialDigest.utf8).write(to: markerFixture)
require(chmod(binaryFixture.path, 0o722) == 0, "unsafe fixture mode")
rejects { _ = try cachedRuntime.executable(id: "mode-proof") }
require(chmod(binaryFixture.path, 0o700) == 0, "restore fixture mode")
try FileManager.default.removeItem(at: binaryFixture)
try FileManager.default.createSymbolicLink(at: binaryFixture, withDestinationURL: URL(fileURLWithPath: "/bin/echo"))
rejects { _ = try cachedRuntime.executable(id: "symlink-proof") }
print("PASS runtime digest reused for unchanged executable; writes with restored mtime, marker tampering, unsafe modes and symlinks invalidate/refuse cache")
let closingRunner = RcloneProcessRunner()
let listenerReady = URL(fileURLWithPath: "/private/tmp/OpenCommander-OAuthExit-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: listenerReady) }
let listenerStopped = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    defer { listenerStopped.signal() }
    do {
        _ = try closingRunner.run(URL(fileURLWithPath: "/usr/bin/python3"),
            ["-c", "import socket,sys,time; s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); open(sys.argv[1],'w').write(str(s.getsockname()[1])); time.sleep(60)", listenerReady.path],
            id: "pending-oauth", timeout: 60)
        fatalError("authorization listener survived host shutdown")
    } catch { require(error is CancellationError, "host shutdown did not cancel its pending operation") }
}
let readyDeadline = Date().addingTimeInterval(10)
while !FileManager.default.fileExists(atPath: listenerReady.path) && Date() < readyDeadline { Thread.sleep(forTimeInterval: 0.01) }
let port = UInt16(try String(contentsOf: listenerReady, encoding: .utf8))!
closingRunner.shutdown()
require(listenerStopped.wait(timeout: .now() + 5) == .success, "authorization listener remained alive")
let reusable = socket(AF_INET, SOCK_STREAM, 0)
require(reusable >= 0, "test socket")
var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
address.sin_port = port.bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
let rebound = withUnsafePointer(to: &address) { value in
    value.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(reusable, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
close(reusable)
require(rebound == 0, "shutdown did not release the authorization port")
closingRunner.finish("pending-oauth")
rejects { _ = try closingRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["unexpected"], id: "later") }
print("PASS host shutdown stops pending authorization listener, frees its port and rejects new subprocesses")
let output = try runner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", "a b;$(no shell)"], id: "literal")
require(String(decoding: output, as: UTF8.self) == "a b;$(no shell)", "shell interpretation")
rejects { _ = try runner.run(URL(fileURLWithPath: "/usr/bin/yes"), [], id: "limit", maximumOutput: 4096) }
rejects { _ = try runner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], id: "timeout", timeout: 0.2) }
runner.cancel("before-start")
rejects { _ = try runner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], id: "before-start") }
runner.finish("before-start")
print("PASS native runner: no shell, bounded output, timeout and pre-start cancellation")
let browserStart = Date()
let browserDelivered = DispatchSemaphore(value: 0)
_ = try runner.run(URL(fileURLWithPath: "/usr/bin/python3"),
    ["-c", "import sys,time; sys.stderr.write('http://127.0.0.1:53682/auth?state=abcdefghijklmnopqrstuv\\n'); sys.stderr.flush(); time.sleep(3)"],
    id: "live-browser-url", timeout: 5, browser: { url in
        require(Date().timeIntervalSince(browserStart) < 2, "browser URL buffered until process exit")
        require(url.host == "127.0.0.1", "unexpected browser host")
        browserDelivered.signal()
    })
require(browserDelivered.wait(timeout: .now()) == .success, "browser callback never delivered")
print("PASS short OAuth browser URL delivered while child process is still waiting")
let quotaError = CloudProviderErrors.classify(Data("SYNTHETIC_SECRET_TOKEN: defaultPerMinutePerProject".utf8))
require(CloudProviderErrors.cooldown(quotaError) == 60 && quotaError.localizedDescription == "cloud_google_quota", "Google application quota classification/cooldown")
require(!quotaError.localizedDescription.contains("SYNTHETIC"), "provider error leaked credential output")
require(CloudProviderErrors.cooldown(CloudProviderErrors.classify(Data("invalid_grant SYNTHETIC_SECRET".utf8))) == nil, "authentication retried")
require(CloudProviderErrors.cooldown(CloudProviderErrors.classify(Data("defaultPerMinutePerProject invalid_grant".utf8))) == nil, "quota hides authentication denial")
do {
    _ = try runner.run(URL(fileURLWithPath: "/usr/bin/python3"), ["-c", "import sys; sys.stderr.write('SYNTHETIC_CREDENTIAL-' * 10000 + ' defaultPerMinutePerProject'); sys.exit(1)"], id: "bounded-error-output", timeout: 5)
    fatalError("failed subprocess accepted")
} catch {
    require(!(error as NSError).localizedDescription.contains("SYNTHETIC"), "stderr leaked in process failure")
}
do {
    _ = try runner.run(URL(fileURLWithPath: "/usr/bin/python3"), ["-c", "import sys; sys.stderr.write('defaultPerMinutePerProject SYNTHETIC_SECRET'); sys.exit(1)"], id: "quota-output", timeout: 5)
    fatalError("failed quota request accepted")
} catch { require(CloudProviderErrors.cooldown(error) == 60, "native runner did not classify quota stderr") }
print("PASS bounded stderr drain, sanitized provider errors, project-quota cooldown and no credential echo")
let identityFile = URL(fileURLWithPath: "/private/tmp/OpenCommander-ConfigIdentity-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: identityFile) }
var identityProfile = profile; identityProfile.configPath = identityFile.path
try Data("[OpenCommander]\ntype = drive\ntoken = {\"access_token\":\"synthetic-account-a\"}\n".utf8).write(to: identityFile, options: .withoutOverwriting)
require(chmod(identityFile.path, 0o600) == 0, "private config fixture permissions")
let accountA = try CloudConfigurationValidator.identity(identityProfile)
try Data("[OpenCommander]\ntype = drive\ntoken = {\"access_token\":\"synthetic-account-b\"}\n".utf8).write(to: identityFile)
let accountB = try CloudConfigurationValidator.identity(identityProfile)
require(accountA != accountB && accountA.count == 64, "configuration changes keep cache identity")
require(chmod(identityFile.path, 0o644) == 0, "fixture mode change")
rejects { _ = try CloudConfigurationValidator.identity(identityProfile) }
print("PASS private bounded configuration identity, account/token change and world-readable-file refusal")
let appleQuestion = try CloudSetupQuestion.decode(Data(#"{"State":"*all-set,2,false","Option":{"Name":"password","IsPassword":true,"Required":true,"DefaultStr":"SYNTHETIC-OLD-PASSWORD"}}"#.utf8), kind: "iclouddrive")
require(appleQuestion.Option?.IsPassword == true && appleQuestion.automaticAnswer(kind: "iclouddrive") == nil, "password automatically submitted")
let teamQuestion = try CloudSetupQuestion.decode(Data(#"{"State":"drive","Option":{"Name":"config_change_team_drive"}}"#.utf8), kind: "drive")
require(teamQuestion.automaticAnswer(kind: "drive") == "false", "personal Google Drive left incomplete")
let authQuestion = try CloudSetupQuestion.decode(Data(#"{"State":"oauth","Option":{"Name":"config_is_local"}}"#.utf8), kind: "dropbox")
require(authQuestion.automaticAnswer(kind: "dropbox") == "true", "browser login replaced by token-paste question")
rejects { _ = try CloudSetupQuestion.decode(Data(#"{"State":"broken"}"#.utf8), kind: "drive") }
rejects { _ = try CloudSetupQuestion.decode(Data(#"{"State":"broken","Option":{"Name":"--bad-option"}}"#.utf8), kind: "drive") }
rejects { _ = try CloudSetupQuestion.decode(Data(#"{"Error":"401 SYNTHETIC-SECRET"}"#.utf8), kind: "iclouddrive") }
require(CloudSetupQuestion.loginFailure(kind: "iclouddrive", detail: "requestPCS: SYNTHETIC-SECRET").localizedDescription == "cloud_icloud_web_access", "Apple web approval error not sanitized")
for detail in ["Your Apple ID or password was incorrect. SYNTHETIC_SECRET", "Incorrect password SYNTHETIC_SECRET", "ErrorCode: -20101 SYNTHETIC_SECRET", "invalid username/password combination SYNTHETIC_SECRET"] {
    let failure = CloudSetupQuestion.loginFailure(kind: "iclouddrive", detail: detail)
    require(failure.localizedDescription == "cloud_icloud_credentials_incorrect", "incorrect Apple credentials not classified")
    require(!failure.localizedDescription.contains("SYNTHETIC_SECRET"), "credential detail leaked")
}
require(CloudSetupQuestion.loginFailure(kind: "iclouddrive", detail: "Device verification required; password field available").localizedDescription == "cloud_icloud_verification", "device verification misreported as wrong password")
require(CloudSetupQuestion.loginFailure(kind: "iclouddrive", detail: "Authentication failed SYNTHETIC_SECRET").localizedDescription == "cloud_icloud_signin_failed", "unknown Apple sign-in error falsely claims missing device verification")
require(CloudSetupQuestion.loginFailure(kind: "iclouddrive", detail: "HTTP 401 SYNTHETIC_SECRET").localizedDescription == "cloud_icloud_login_denied", "Apple rejection not classified")
for (detail, key) in [("shared app retired SYNTHETIC_SECRET", "cloud_google_shared_unavailable"),
                      ("rate limit SYNTHETIC_SECRET", "cloud_rate_limited"),
                      ("shared quota invalid_grant SYNTHETIC_SECRET", "cloud_google_login_expired"),
                      ("HTTP 401 SYNTHETIC_SECRET", "cloud_google_login_expired")] {
    require(CloudSetupQuestion.loginFailure(kind: "drive", detail: detail).localizedDescription == key, "Google setup classification leaks/misclassifies reply")
}
let sharedQuestion = try CloudSetupQuestion.decode(Data(#"{"State":"shared","Option":{"Name":"config_shared_client_id","DefaultStr":"true"}}"#.utf8), kind: "drive")
require(sharedQuestion.automaticAnswer(kind: "drive") == nil, "shared Google client silently accepted")
do {
    _ = try runner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], id: "setup-timeout", timeout: 0.2, setupKind: "drive")
    fatalError("expired setup accepted")
} catch { require((error as NSError).localizedDescription == "cloud_setup_expired", "setup timeout lacks restart guidance") }
require(CloudSetupQuestion.browserURL(Data("http://127.0.0.1:53682/auth?state=abcdefghijklmnopqrstuv\n".utf8))?.host == "127.0.0.1", "valid backend loopback URL missing")
for url in ["https://evil.invalid/auth?state=abcdefghijklmnopqrstuv", "http://127.0.0.1:1234/auth?state=abcdefghijklmnopqrstuv", "http://127.0.0.1:53682/auth?state=abcdefghijklmnopqrstuvEXTRA"] {
    require(CloudSetupQuestion.browserURL(Data(url.utf8)) == nil, "untrusted sign-in URL accepted")
}
print("PASS cloud setup question boundaries, explicit passwords, personal Google Drive default, sanitized Apple errors and loopback-only browser routing")
let stdinResult = try runner.run(URL(fileURLWithPath: "/bin/cat"), [], id: "private-input", input: Data("synthetic-private-input".utf8))
require(String(decoding: stdinResult, as: UTF8.self) == "synthetic-private-input", "private stdin not delivered")
let envResult = try runner.run(URL(fileURLWithPath: "/usr/bin/python3"), ["-c", "import os; print(os.environ.get('RCLONE_RESULT',''))"], id: "private-answer", environment: ["RCLONE_RESULT": "synthetic;not-a-shell"])
require(String(decoding: envResult, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "synthetic;not-a-shell", "private answer not delivered literally")
rejects { _ = try runner.run(URL(fileURLWithPath: "/bin/cat"), [], id: "invalid-env", environment: ["DYLD_INSERT_LIBRARIES": "untrusted"]) }
print("PASS bounded private stdin/config-answer environment and refusal of executable-loading environment overrides")
if CommandLine.arguments.contains("--benchmark-runtime") {
    let runtime = RcloneRuntime(runner: runner)
    let executable = try runtime.executable(id: "benchmark-prime")
    let fullStart = Date()
    for _ in 0..<20 { _ = try RcloneRuntime.hash(executable) }
    let full = Date().timeIntervalSince(fullStart)
    let cachedStart = Date()
    for _ in 0..<20 { _ = try RcloneRuntime(runner: runner).executable(id: "benchmark-cache") }
    let cached = Date().timeIntervalSince(cachedStart)
    print(String(format: "BENCHMARK 20 executable checks: full %.4fs, validated identity %.4fs, speedup %.1fx", full, cached, full / max(cached, 0.000001)))
}
if CommandLine.arguments.contains("--install") {
    let runtime = RcloneRuntime(runner: runner)
    runtime.status = { print($0); fflush(stdout) }
    let binary = try runtime.executable(id: "official-install")
    let version = try runner.run(binary, ["version"], id: "installed-version")
    require(String(decoding: version, as: UTF8.self).hasPrefix("rclone v"), "installed runtime version missing")
    let configFixture = URL(fileURLWithPath: "/private/tmp/OpenCommander-Rclone-Config-" + UUID().uuidString)
    try Data("[fixture]\ntype = local\n".utf8).write(to: configFixture, options: .withoutOverwriting)
    defer { try? FileManager.default.removeItem(at: configFixture) }
    let profiles = try runner.run(binary, ["listremotes", "--json", "--config", configFixture.path], id: "list-profiles")
    print(String(decoding: profiles, as: UTF8.self)) // Synthetic, contains no credentials.
    print("PASS official checksum-verified runtime install and synthetic config metadata listing")
    let setupFixture = URL(fileURLWithPath: "/private/tmp/OpenCommander-Rclone-Setup-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: setupFixture) }
    let setup = try runner.run(binary, ["--config", setupFixture.path, "config", "create", "oc_synthetic", "iclouddrive", "--all", "--non-interactive"], id: "apple-first-question", maximumOutput: 262144)
    let initialService = try CloudSetupQuestion.decode(setup, kind: "iclouddrive")
    require(initialService.automaticAnswer(kind: "iclouddrive") == "drive", "actual backend did not select Drive service")
    let appleStep = try runner.run(binary, ["--config", setupFixture.path, "config", "update", "oc_synthetic", "--continue", "--non-interactive"], id: "apple-id-question", maximumOutput: 262144,
        environment: ["RCLONE_STATE": initialService.State!, "RCLONE_RESULT": "drive"])
    let initialApple = try CloudSetupQuestion.decode(appleStep, kind: "iclouddrive")
    require(!initialApple.complete && initialApple.Option?.Name == "apple_id", "actual backend skipped Apple ID")
    let obscuredInput = try runner.run(binary, ["obscure", "-"], id: "actual-password-wire", input: Data("synthetic-not-an-account-password\n".utf8))
    require(CloudConfigurationValidator.obscured(String(decoding: obscuredInput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)), "actual stdin password encoding failed")
    print("PASS actual private rclone Apple setup starts at explicit Apple ID; synthetic password encoded over stdin without credential arguments")
    let cloudFixture = URL(fileURLWithPath: "/private/tmp/OpenCommander-Rclone-Files-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: cloudFixture.appendingPathComponent("source/Empty"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cloudFixture) }
    try Data("verified fixture".utf8).write(to: cloudFixture.appendingPathComponent("source/Grüsse.txt"))
    try Data("[fixture]\ntype = alias\nremote = \(cloudFixture.path)\n".utf8).write(to: configFixture)
    let localProfile = CloudConnection(name: "Synthetic only", kind: "drive", remote: "fixture", configPath: configFixture.path)
    // Command-plan test against a strictly local alias; the app transport
    // deliberately refuses alias configs for a profile claiming to be Drive.
    _ = try runner.run(binary, RcloneCommandPlan.arguments(profile: localProfile, operation: "copytree", path: "source", destination: "copy"), id: "local-copy")
    require(FileManager.default.fileExists(atPath: cloudFixture.appendingPathComponent("copy/Empty").path), "empty cloud folder lost")
    require(try Data(contentsOf: cloudFixture.appendingPathComponent("copy/Grüsse.txt")) == Data("verified fixture".utf8), "cloud copy bytes differ")
    try Data("do not overwrite".utf8).write(to: cloudFixture.appendingPathComponent("copy/Grüsse.txt"))
    rejects { _ = try runner.run(binary, RcloneCommandPlan.arguments(profile: localProfile, operation: "copytree", path: "source", destination: "copy"), id: "immutable-copy") }
    require(try Data(contentsOf: cloudFixture.appendingPathComponent("copy/Grüsse.txt")) == Data("do not overwrite".utf8), "immutable copy replaced existing file")
    print("PASS actual rclone command plan: Unicode tree, empty directories and immutable replacement refusal on local fixture")
}
