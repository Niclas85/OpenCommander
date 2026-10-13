import Foundation
import Darwin
func require(_ test: Bool, _ message: String) { if !test { fatalError(message) } }
func rejects(_ body: () throws -> Void) { do { try body(); fatalError("unsafe lease accepted") } catch {} }
let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("OpenCommander-Lease-Test-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: directory) }
let pins = directory.appendingPathComponent("pins"), source = directory.appendingPathComponent("rclone.conf")
func configuration(_ token: String = "SYNTHETIC_TOKEN", type: String = "drive", other: String = "untouched") -> Data {
    Data("[test]\ntype = \(type)\nclient_id = synthetic-client\ntoken = {\"access_token\":\"\(token)\"}\n[other]\ntype = drive\nclient_id = \(other)\ntoken = {\"access_token\":\"SYNTHETIC_OTHER\"}\n".utf8)
}
try configuration().write(to: source); chmod(source.path, 0o600)
let profile = CloudConnection(name: "Synthetic", kind: "drive", remote: "test", configPath: source.path)
var anchor = ""
do {
    let lease = try CloudConfigurationLease(profile, root: pins); anchor = lease.identity
    let initial = try Data(contentsOf: source), snapshot = try Data(contentsOf: URL(fileURLWithPath: lease.profile.configPath))
    require(lease.profile.configPath != source.path && initial == snapshot, "child is not using private snapshot")
    try configuration("SYNTHETIC_OWN_ROTATION").write(to: URL(fileURLWithPath: lease.profile.configPath)); chmod(lease.profile.configPath, 0o600)
    try lease.commit()
}
do { let lease = try CloudConfigurationLease(profile, root: pins); require(lease.identity == anchor, "own token rotation changes account pin") }
print("PASS private child snapshot, legitimate token rotation and persistent stable account identity")
let rotated = try Data(contentsOf: source)
try configuration("SYNTHETIC_EXTERNAL_ACCOUNT").write(to: source); chmod(source.path, 0o600)
rejects { _ = try CloudConfigurationLease(profile, root: pins) }
require(try Data(contentsOf: source) == configuration("SYNTHETIC_EXTERNAL_ACCOUNT"), "external configuration overwritten")
try rotated.write(to: source); chmod(source.path, 0o600)
do {
    let lease = try CloudConfigurationLease(profile, root: pins)
    try configuration("SYNTHETIC_OWN_ROTATION", other: "other-account").write(to: URL(fileURLWithPath: lease.profile.configPath)); chmod(lease.profile.configPath, 0o600)
    rejects { try lease.commit() }
    require(try Data(contentsOf: source) == rotated, "unrelated configuration overwritten")
}
print("PASS external account switch and unexpected/unrelated backend changes refuse without replacing user config")
do {
    let lease = try CloudConfigurationLease(profile, root: pins)
    try configuration("SYNTHETIC_RACE").write(to: source); chmod(source.path, 0o600)
    rejects { try lease.checkSource() }; rejects { try lease.commit() }
    require(try Data(contentsOf: source) == configuration("SYNTHETIC_RACE"), "concurrent config switch lost")
}
try rotated.write(to: source); chmod(source.path, 0o600)
print("PASS in-flight config mutation fails before subsequent mutation or token publication")
for crashPhase in ["pending", "published"] {
    var expected = rotated
    do {
        let lease = try CloudConfigurationLease(profile, root: pins)
        let update = configuration("SYNTHETIC_CRASH_" + crashPhase)
        try update.write(to: URL(fileURLWithPath: lease.profile.configPath)); chmod(lease.profile.configPath, 0o600)
        rejects { try lease.commit { phase in if phase == crashPhase { throw CancellationError() } } }
        if crashPhase == "published" { expected = update }
    }
    do { let lease = try CloudConfigurationLease(profile, root: pins); require(lease.identity == anchor, "interrupted own rotation loses account") }
    require(try Data(contentsOf: source) == expected, "interrupted publication changed unexpected generation")
    // Use the now-current proven generation for the following scenario.
    if crashPhase == "pending" { require(expected == rotated, "pending publication not preserved") }
}
print("PASS restart recovers either side of atomic token-rotation publication without accepting another account")
let symlink = directory.appendingPathComponent("symlink.conf"); try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
var linked = profile; linked.configPath = symlink.path
rejects { _ = try CloudConfigurationLease(linked, root: pins) }
do {
    let lease = try CloudConfigurationLease(profile, root: pins)
    rejects { _ = try CloudConfigurationLease(profile, root: pins, check: { throw CancellationError() }) }
    _ = lease.identity
}
for file in try FileManager.default.contentsOfDirectory(at: pins, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
    let data = try Data(contentsOf: file)
    require(!String(decoding: data, as: UTF8.self).contains("SYNTHETIC"), "tokens entered account registry")
}
print("PASS symlink/unsafe config refusal, cancellation while waiting, bounded credential-free pin registry")
