import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2, let canonical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated root required") }
defer { free(canonical) }
let root = URL(fileURLWithPath: String(cString: canonical)), fm = FileManager.default
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
let local = root.appendingPathComponent("NativeNASAcceptance")
guard !fm.fileExists(atPath: local.path) else { fatalError("never overwrite fixture") }
let scopedNAS = URL(fileURLWithPath: "/Volumes/Test/OpenCommander-LiveQA-20261018-qOIIyg/FoundationTree")
var info = statfs()
guard statfs(scopedNAS.path, &info) == 0,
      withUnsafeBytes(of: &info.f_fstypename, { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }) == "smbfs" else { fatalError("exact existing SMB test root required") }
let remote = scopedNAS.appendingPathComponent("NativeTransfers-20261019-" + UUID().uuidString)
try fm.createDirectory(at: remote, withIntermediateDirectories: false)
try fm.createDirectory(at: local, withIntermediateDirectories: false)
for folder in ["Source", "Returned"] { try fm.createDirectory(at: local.appendingPathComponent(folder), withIntermediateDirectories: false) }
try Data("Own native NAS copy ä – original version.\n".utf8).write(to: local.appendingPathComponent("Source/Probe.txt"), options: .withoutOverwriting)
try fm.createDirectory(at: local.appendingPathComponent("Source/Tree/Nested/Empty"), withIntermediateDirectories: true)
try Data("Own native NAS tree – Grüße.\n".utf8).write(to: local.appendingPathComponent("Source/Tree/Nested/Grüsse.txt"), options: .withoutOverwriting)
let manifest: [String:String] = ["local":local.path,"remote":remote.path]
try JSONSerialization.data(withJSONObject: manifest, options:.sortedKeys).write(to: local.appendingPathComponent("Manifest.json"), options: .withoutOverwriting)
print("LOCAL \(local.path)\nREMOTE \(remote.path)")
