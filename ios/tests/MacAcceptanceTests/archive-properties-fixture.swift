import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2, let canonical = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated root required") }
defer { free(canonical) }
let root = URL(fileURLWithPath: String(cString: canonical)), fm = FileManager.default
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
let fixture = root.appendingPathComponent("ArchivePropertiesAcceptance")
guard !fm.fileExists(atPath: fixture.path) else { fatalError("never overwrite fixture") }
try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
let source = fixture.appendingPathComponent("Source")
try fm.createDirectory(at: source.appendingPathComponent("folder/sub"), withIntermediateDirectories: true)
try fm.createDirectory(at: source.appendingPathComponent("folderish"), withIntermediateDirectories: false)
try Data(repeating: 120, count: 8192).write(to: source.appendingPathComponent("folder/Repeated.txt"), options: .withoutOverwriting)
try Data("hello".utf8).write(to: source.appendingPathComponent("folder/sub/Five.txt"), options: .withoutOverwriting)
try Data("not in folder".utf8).write(to: source.appendingPathComponent("folderish/Outside.txt"), options: .withoutOverwriting)
let zip = Process()
zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
zip.currentDirectoryURL = source
zip.arguments = ["-q", "-r", "-D", fixture.appendingPathComponent("Properties.zip").path, "folder", "folderish"]
try zip.run(); zip.waitUntilExit()
guard zip.terminationStatus == 0 else { fatalError("fixture ZIP failed") }
print("READY \(fixture.path)/Properties.zip: implicit folder=8197B, two entries; Repeated.txt=8192B; outside sibling excluded")
