import Foundation
func check(_ condition: Bool) { precondition(condition) }

let name = "OpenCommander-NTFSRegistrationTests-" + UUID().uuidString
let defaults = UserDefaults(suiteName: name)!
defer { defaults.removePersistentDomain(forName: name) }
let plan = NTFSExtensionRegistration.Plan(host: URL(fileURLWithPath: "/Applications/OpenCommander.app"),
    module: URL(fileURLWithPath: "/Applications/OpenCommander.app/Contents/Extensions/OpenCommanderNTFSModule.appex"), fingerprint: "build-a")
var calls: [(String, [String])] = []
func record(_ executable: String, _ arguments: [String]) { calls.append((executable, arguments)) }
try check(NTFSExtensionRegistration.refresh(plan, defaults: defaults, run: record))
precondition(calls.count == 2)
precondition(calls[0].0 == NTFSExtensionRegistration.registrationTool && calls[0].1 == ["-f", plan.host.path])
precondition(calls[1].0 == "/usr/bin/pluginkit" && calls[1].1 == ["-a", plan.module.path])
try check(!NTFSExtensionRegistration.refresh(plan, defaults: defaults, run: record))
precondition(calls.count == 2)
print("PASS one registration per installed build, exact paths, no approval or mount commands")
let update = NTFSExtensionRegistration.Plan(host: plan.host, module: plan.module, fingerprint: "build-b")
do {
    _ = try NTFSExtensionRegistration.refresh(update, defaults: defaults) { executable, _ in
        if executable == "/usr/bin/pluginkit" { throw NSError(domain: "injected", code: 1) }
    }
    fatalError("Expected registration failure")
} catch { precondition(defaults.string(forKey: NTFSExtensionRegistration.preferenceKey) == "build-a") }
try check(NTFSExtensionRegistration.refresh(update, defaults: defaults, run: record))
precondition(defaults.string(forKey: NTFSExtensionRegistration.preferenceKey) == "build-b")
print("PASS failed update remains retryable; successful changed build is retained")
for path in ["/tmp/OpenCommander.app", "/Applications/Other.app", "/Applications/OpenCommander NTFS Starttest.app"] {
    try check(NTFSExtensionRegistration.plan(for: URL(fileURLWithPath: path)) == nil)
}
print("PASS build directories, unrelated apps and diagnostic host are not registered")
if CommandLine.arguments.contains("--installed") {
    guard let actual = try NTFSExtensionRegistration.plan(for: plan.host) else { fatalError("Installed host not recognized") }
    precondition(actual.module == plan.module && !actual.fingerprint.isEmpty)
    print("PASS installed host/module signatures, matching team and Boolean FSKit/sandbox entitlements (read-only)")
}
