import Foundation
import Darwin
func require(_ test: Bool, _ message: String) { if !test { fatalError(message) } }
func rejects(_ action: () throws -> Void) { do { try action(); fatalError("unsafe input accepted") } catch {} }
let profile = CloudConnection(name: "Drive", kind: "drive", remote: "OpenCommander", root: "Ordner", configPath: "/private/tmp/own.conf")
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
let runner = RcloneProcessRunner()
let output = try runner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", "a b;$(no shell)"], id: "literal")
require(String(decoding: output, as: UTF8.self) == "a b;$(no shell)", "shell interpretation")
rejects { _ = try runner.run(URL(fileURLWithPath: "/usr/bin/yes"), [], id: "limit", maximumOutput: 4096) }
rejects { _ = try runner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], id: "timeout", timeout: 0.2) }
runner.cancel("before-start")
rejects { _ = try runner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], id: "before-start") }
runner.finish("before-start")
print("PASS native runner: no shell, bounded output, timeout and pre-start cancellation")
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
