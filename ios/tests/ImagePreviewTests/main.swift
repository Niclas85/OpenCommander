import Foundation
import ImageIO
import UniformTypeIdentifiers

let fm = FileManager.default
for position in [0.0, 1, 5] { precondition(!MediaPlaybackPolicy.shouldRestart(position: position, duration: 6)) }
for position in [5.96, 6, 7] { precondition(MediaPlaybackPolicy.shouldRestart(position: position, duration: 6)) }
for duration in [0.0, -1, .nan, .infinity] { precondition(!MediaPlaybackPolicy.shouldRestart(position: 6, duration: duration)) }
for position in [-1.0, .nan, .infinity] { precondition(!MediaPlaybackPolicy.shouldRestart(position: position, duration: 6)) }
precondition(!MediaPlaybackPolicy.shouldRestart(position: 0, duration: 0.01))
precondition(MediaPlaybackPolicy.shouldRestart(position: 0.00995, duration: 0.01))
print("PASS playback replay policy: end/tolerance, short media, normal pause, unknown/invalid duration")
let fixture = fm.temporaryDirectory.appendingPathComponent("OpenCommander-ImageTests-" + UUID().uuidString)
try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
defer { if !CommandLine.arguments.contains("--keep-fixture") { try? fm.removeItem(at: fixture) } }
let previewBase = fm.temporaryDirectory.appendingPathComponent("OpenCommanderPreview", isDirectory: true)
try fm.createDirectory(at: previewBase, withIntermediateDirectories: true)
let owned = previewBase.appendingPathComponent(UUID().uuidString, isDirectory: true)
let neighbor = previewBase.appendingPathComponent(UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: owned, withIntermediateDirectories: false)
try fm.createDirectory(at: neighbor, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: neighbor) }
try Data("own temporary bytes".utf8).write(to: owned.appendingPathComponent("image.bin"))
var previewFiles: PreviewTemporaryFiles? = PreviewTemporaryFiles()
previewFiles!.retainCreatedRoot(owned)
previewFiles!.retainCreatedRoot(owned)
previewFiles!.retainCreatedRoot(fixture) // Never delete a physical/provider source.
previewFiles!.retainCreatedRoot(previewBase) // Never delete the shared parent.
precondition(fm.fileExists(atPath: owned.path))
previewFiles = nil
precondition(!fm.fileExists(atPath: owned.path) && fm.fileExists(atPath: neighbor.path) && fm.fileExists(atPath: fixture.path))
print("PASS preview lifetime removes only explicitly owned UUID root, retains source/shared parent/neighbor")
let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.15, green: 0.6, blue: 0.9, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.15, alpha: 1))
context.fill(CGRect(x: 30, y: 25, width: 140, height: 50))
let source = context.makeImage()!
for (name, type) in [("01-Test.JPG", UTType.jpeg), ("02-Grüße.PNG", UTType.png)] {
    let url = fixture.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, source, nil)
    precondition(CGImageDestinationFinalize(destination))
    let thumbnail = try ImagePreviewLoader.load(at: url, maximumPixelSize: 64)
    precondition(thumbnail.width == 64 && thumbnail.height == 32)
    print("PASS \(type.identifier): coordinated read and bounded thumbnail")
}
let corrupt = fixture.appendingPathComponent("03-Corrupt.png")
try Data("not an image".utf8).write(to: corrupt)
do {
    _ = try ImagePreviewLoader.load(at: corrupt, maximumPixelSize: 64)
    fatalError("Corrupt file accepted")
} catch ImagePreviewLoader.PreviewError.invalidImage {
    print("PASS corrupt image distinguished from access/provider failure")
}
do {
    _ = try ImagePreviewLoader.load(at: fixture.appendingPathComponent("Missing.jpg"), maximumPixelSize: 64)
    fatalError("Missing file accepted")
} catch {
    precondition(!(error is ImagePreviewLoader.PreviewError))
    print("PASS missing-file error preserved")
}
let marker = NSError(domain: "OpenCommander.ImagePreviewTests", code: 77)
do {
    _ = try ImagePreviewLoader.load(at: corrupt, maximumPixelSize: 64) { _ in throw marker }
    fatalError("Preparation error swallowed")
} catch {
    precondition((error as NSError).domain == marker.domain && (error as NSError).code == 77)
    print("PASS preparation/extraction failure preserved")
}
// Exercise the extraction hook without requiring ZIPFoundation in this small test.
let prepared = try ImagePreviewLoader.load(at: corrupt, maximumPixelSize: 64) { _ in
    fixture.appendingPathComponent("02-Grüße.PNG")
}
precondition(prepared.width == 64)
print("PASS decoding uses prepared URL inside coordinated access")
if let index = CommandLine.arguments.firstIndex(of: "--read-image"), CommandLine.arguments.indices.contains(index + 1) {
    do {
        let image = try ImagePreviewLoader.load(at: URL(fileURLWithPath: CommandLine.arguments[index + 1]), maximumPixelSize: 512)
        print("LIVE image decoded: \(image.width) × \(image.height)")
    } catch {
        let failure = error as NSError
        print("LIVE BLOCKED: domain=\(failure.domain) code=\(failure.code)")
    }
}
if CommandLine.arguments.contains("--keep-fixture") { print("FIXTURE \(fixture.path)") }
