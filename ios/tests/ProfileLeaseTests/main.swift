import Foundation
import Darwin

let fm = FileManager.default
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "hold" {
    let profile = URL(fileURLWithPath: CommandLine.arguments[2])
    guard profile.deletingLastPathComponent().lastPathComponent.hasPrefix("OpenCommander-ProfileLease-") else { exit(2) }
    let lease = try CommanderProfileLease(directory: profile)
    try Data("ready".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .withoutOverwriting)
    withExtendedLifetime(lease) { while true { pause() } }
    exit(0)
}
let root = fm.temporaryDirectory.appendingPathComponent("OpenCommander-ProfileLease-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: root) }
func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "ProfileLeaseTest", code: 1, userInfo: [NSLocalizedDescriptionKey:message]) }
}
func refuses(_ folder: URL, _ expected: CommanderProfileLease.Failure) throws {
    do { _ = try CommanderProfileLease(directory: folder); throw NSError(domain:"MissingRefusal",code:1) }
    catch let error as CommanderProfileLease.Failure { try require(error == expected, "wrong refusal") }
}
let profile = root.appendingPathComponent("Profile-A")
var owner: CommanderProfileLease? = try CommanderProfileLease(directory: profile)
try refuses(profile, .inUse)
let alias = root.appendingPathComponent("Alias-A")
try fm.createSymbolicLink(at: alias, withDestinationURL: profile)
try refuses(alias, .inUse)
let independent = try CommanderProfileLease(directory: root.appendingPathComponent("Profile-B"))
withExtendedLifetime(independent) {}
let path = profile.appendingPathComponent(".opencommander-profile.lock").path
let mode = try fm.attributesOfItem(atPath:path)[.posixPermissions] as! NSNumber
try require(mode.intValue == 0o600, "private lease permissions")
withExtendedLifetime(owner) {}
owner = nil
do { let reopened = try CommanderProfileLease(directory: profile); withExtendedLifetime(reopened) {} }
print("PASS profile lease excludes second writer and path alias, independent profile works, private lock, normal release")

for signal in [SIGTERM, SIGKILL] {
    let child = Process(), ready = root.appendingPathComponent("ready-\(signal)")
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["hold",profile.path,ready.path]
    try child.run()
    defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
    let deadline = Date().addingTimeInterval(10)
    while !fm.fileExists(atPath: ready.path), child.isRunning, Date() < deadline { Thread.sleep(forTimeInterval:0.01) }
    try require(fm.fileExists(atPath:ready.path), "child did not acquire lease")
    try refuses(profile, .inUse)
    try require(kill(child.processIdentifier, signal) == 0, "could not signal own child")
    child.waitUntilExit()
    try require(child.terminationReason == .uncaughtSignal && child.terminationStatus == signal, "wrong child exit")
    let recovered = try CommanderProfileLease(directory:profile)
    withExtendedLifetime(recovered) {}
    print("PASS actual child signal\(signal) releases kernel lease; fresh owner acquires without deleting lock")
}
let malicious = root.appendingPathComponent("Symlink-lock")
try fm.createDirectory(at:malicious,withIntermediateDirectories:false)
let sentinel = root.appendingPathComponent("Sentinel.txt")
try Data("do not alter".utf8).write(to:sentinel)
try fm.createSymbolicLink(at:malicious.appendingPathComponent(".opencommander-profile.lock"),withDestinationURL:sentinel)
try refuses(malicious,.unavailable)
let bytes = try Data(contentsOf:sentinel)
try require(bytes == Data("do not alter".utf8), "sentinel changed")
print("PASS symlink lock refuses without altering target")

for kind in ["Hardlink", "Directory", "FIFO"] {
    let folder = root.appendingPathComponent(kind + "-lock")
    try fm.createDirectory(at: folder, withIntermediateDirectories: false)
    let lock = folder.appendingPathComponent(".opencommander-profile.lock")
    if kind == "Hardlink" { try fm.linkItem(at: sentinel, to: lock) }
    else if kind == "Directory" { try fm.createDirectory(at: lock, withIntermediateDirectories: false) }
    else { try require(mkfifo(lock.path, 0o600) == 0, "could not create own FIFO fixture") }
    try refuses(folder, .unavailable)
    let intact = try Data(contentsOf: sentinel)
    try require(intact == Data("do not alter".utf8), "special lock changed sentinel")
}
print("PASS hardlink, directory and FIFO locks refuse safely without blocking or altering target")
