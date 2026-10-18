// Generates synthetic bytes only inside an existing isolated UI-test fixture.
import Foundation
import CryptoKit
guard CommandLine.arguments.count == 2 else { fatalError("Expected isolated fixture root") }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard root.lastPathComponent.hasPrefix("OpenCommander-MacUITest-"),
      root.deletingLastPathComponent().resolvingSymlinksInPath().path == URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path else { fatalError("Unexpected fixture root") }
let destination = root.appendingPathComponent("Left/AAA-Large-Restart-20261016.bin")
guard !FileManager.default.fileExists(atPath: destination.path) else { fatalError("Fixture already exists") }
var bytes = Data(repeating: 0x5a, count: 12 * 1024 * 1024)
bytes.replaceSubrange(0..<32, with: Data("OpenCommander synthetic restart!!".utf8))
try bytes.write(to: destination, options: .withoutOverwriting)
print(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
