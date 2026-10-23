import Foundation
import AppKit
import Darwin

guard CommandLine.arguments.count == 2 else { fatalError("isolated root required") }
let fm = FileManager.default
guard let path = realpath(CommandLine.arguments[1], nil) else { fatalError("existing isolated root required") }
defer { free(path) }
let root = URL(fileURLWithPath: String(cString: path))
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.niklaus85.OpenCommander.MacUITests").isEmpty else { fatalError("stopped isolated app required") }
let target = root.appendingPathComponent("PropertiesAcceptance")
guard !fm.fileExists(atPath: target.path) else { fatalError("never overwrite fixture") }
try fm.createDirectory(at: target, withIntermediateDirectories: false)
try Data("Properties ä — exact selected item.\n".utf8).write(to: target.appendingPathComponent("Properties.txt"), options: .withoutOverwriting)
try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.appendingPathComponent("Properties.txt").path)
let folder = target.appendingPathComponent("Folder")
try fm.createDirectory(at: folder, withIntermediateDirectories: false)
try Data("123456".utf8).write(to: folder.appendingPathComponent("Six.txt"), options: .withoutOverwriting)
try fm.createSymbolicLink(at: target.appendingPathComponent("Folder-link"), withDestinationURL: folder)
try fm.createSymbolicLink(atPath: target.appendingPathComponent("Broken-link").path, withDestinationPath: "absent-target")
print("READY \(target.path), file=\(try Data(contentsOf: target.appendingPathComponent("Properties.txt")).count)B, folder=6B")
