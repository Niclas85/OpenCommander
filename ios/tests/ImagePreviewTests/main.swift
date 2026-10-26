import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

let fm = FileManager.default
precondition(!ThumbnailInputPolicy.permits(size: -1))
precondition(ThumbnailInputPolicy.permits(size: 0))
precondition(ThumbnailInputPolicy.permits(size: 32 * 1024 * 1024))
precondition(!ThumbnailInputPolicy.permits(size: 32 * 1024 * 1024 + 1))
precondition(!ThumbnailInputPolicy.permits(size: Int64.max))
print("PASS thumbnail inputs reject unknown/oversized size and accept exact32MiB boundary")
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
let textFixture = fixture.appendingPathComponent("Preview.txt")
func verifyText(_ data: Data, expected: String?, truncated: Bool = false) throws {
    try data.write(to: textFixture)
    switch try BoundedTextPreviewLoader.load(at: textFixture) {
    case .text(let text, let wasTruncated):
        precondition(expected == text && truncated == wasTruncated)
    case .unsupported: precondition(expected == nil)
    }
    let unchanged = try Data(contentsOf: textFixture)
    precondition(unchanged == data)
}
try verifyText(Data(), expected: "")
try verifyText(Data("Grüße 日本語 👋\n".utf8), expected: "Grüße 日本語 👋\n")
let textLimit = BoundedTextPreviewLoader.maximumBytes
let asciiLimit = Data(repeating: 65, count: textLimit)
try verifyText(asciiLimit, expected: String(repeating: "A", count: textLimit))
try verifyText(asciiLimit + Data("NOT DISPLAYED".utf8), expected: String(repeating: "A", count: textLimit), truncated: true)
for character in ["ü", "€", "👋"] {
    let prefix = Data(repeating: 65, count: textLimit - 1)
    try verifyText(prefix + Data(character.utf8) + Data("tail".utf8), expected: String(repeating: "A", count: textLimit - 1), truncated: true)
}
try verifyText(Data([65, 0, 66]), expected: nil)
try verifyText(Data([65, 0xFF, 66]), expected: nil)
try verifyText(Data(repeating: 65, count: textLimit - 1) + Data([0xFF, 65]), expected: nil)
let fifo = fixture.appendingPathComponent("Pipe.txt")
precondition(mkfifo(fifo.path, 0o600) == 0)
if case .unsupported = try BoundedTextPreviewLoader.load(at: fifo) {} else { fatalError("FIFO accepted") }
if case .unsupported = try BoundedTextPreviewLoader.load(at: fixture) {} else { fatalError("Directory accepted") }
do {
    _ = try BoundedTextPreviewLoader.load(at: fixture.appendingPathComponent("Missing.txt"))
    fatalError("Missing text accepted")
} catch { precondition(error is POSIXError) }
precondition(BoundedTextPreviewLoader.isCandidate(textFixture))
precondition(!BoundedTextPreviewLoader.isCandidate(fixture.appendingPathComponent("Document.pdf")))
print("PASS bounded text: Unicode, empty/exact/over-limit, UTF-8 split, binary, invalid encoding, FIFO, directory, missing file, unchanged sources and PDF routing")
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
let boundedFixture = fixture.appendingPathComponent("Bounded.png")
for count in [0, 16, 17] {
    let bytes = Data(repeating: 65, count: count)
    try bytes.write(to: boundedFixture)
    do {
        let actual = try ImagePreviewLoader.boundedData(at: boundedFixture, limit: 16)
        precondition(count <= 16 && actual == bytes)
    } catch ImagePreviewLoader.PreviewError.tooLarge { precondition(count > 16) }
    let unchanged = try Data(contentsOf: boundedFixture)
    precondition(unchanged == bytes)
}
let sparse = fixture.appendingPathComponent("Oversized.png")
precondition(fm.createFile(atPath: sparse.path, contents: nil))
let sparseHandle = try FileHandle(forWritingTo: sparse)
try sparseHandle.truncate(atOffset: UInt64(ImagePreviewLoader.maximumBytes + 1))
try sparseHandle.close()
do {
    _ = try ImagePreviewLoader.load(at: sparse, maximumPixelSize: Int.max)
    fatalError("Oversized image accepted")
} catch ImagePreviewLoader.PreviewError.tooLarge {}
let sparseSize = try fm.attributesOfItem(atPath: sparse.path)[.size] as! NSNumber
precondition(sparseSize.intValue == ImagePreviewLoader.maximumBytes + 1)
for url in [fifo, fixture] {
    do {
        _ = try ImagePreviewLoader.boundedData(at: url)
        fatalError("Special file accepted")
    } catch ImagePreviewLoader.PreviewError.unsupportedFile {}
}
print("PASS image input: empty/exact/over-limit, sparse 128 MiB+1 rejection, FIFO/directory refusal, unchanged sources")
let vector = fixture.appendingPathComponent("Vector.svg")
let vectorBytes = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"16\"><rect width=\"32\" height=\"16\" fill=\"blue\"/></svg>".utf8)
try vectorBytes.write(to: vector)
var vectorLease: PreviewTemporaryFiles? = PreviewTemporaryFiles()
let vectorSnapshot = try ImagePreviewLoader.vectorSnapshot(at: vector, coordinator: NSFileCoordinator(), temporaryRoot: vectorLease!.retainCreatedRoot)
let snapshotBeforeChange = try Data(contentsOf: vectorSnapshot)
precondition(snapshotBeforeChange == vectorBytes)
try Data("changed source".utf8).write(to: vector)
let snapshotAfterChange = try Data(contentsOf: vectorSnapshot)
precondition(snapshotAfterChange == vectorBytes)
vectorLease = nil
precondition(!fm.fileExists(atPath: vectorSnapshot.deletingLastPathComponent().path))
do {
    _ = try ImagePreviewLoader.vectorSnapshot(at: sparse, coordinator: NSFileCoordinator(), temporaryRoot: { _ in fatalError("Oversize vector allocated snapshot") })
    fatalError("Oversize vector snapshot accepted")
} catch ImagePreviewLoader.PreviewError.tooLarge {}
print("PASS bounded vector snapshot is immutable, owned root cleans on release, oversized source refused before snapshot")
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
var preparedOversizedSource = false
do {
    _ = try ImagePreviewLoader.load(at: sparse, maximumPixelSize: 64) { url in
        preparedOversizedSource = true; return url
    }
    fatalError("Oversized physical preflight accepted")
} catch ImagePreviewLoader.PreviewError.tooLarge {}
precondition(!preparedOversizedSource)
// A large archive's container size is not its member image's input size.
let smallMember = try ImagePreviewLoader.load(at: sparse, maximumPixelSize: 64, preflightSource: false) { _ in
    fixture.appendingPathComponent("02-Grüße.PNG")
}
precondition(smallMember.width == 64)
print("PASS physical size preflight precedes preparation; archive container does not block small prepared member")
let wideContext = CGContext(data: nil, width: 5000, height: 10, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let wideURL = fixture.appendingPathComponent("Wide.png")
let wideDestination = CGImageDestinationCreateWithURL(wideURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(wideDestination, wideContext.makeImage()!, nil)
precondition(CGImageDestinationFinalize(wideDestination))
let capped = try ImagePreviewLoader.load(at: wideURL, maximumPixelSize: Int.max)
precondition(capped.width == 4096 && capped.height <= 4096)
let minimum = try ImagePreviewLoader.load(at: wideURL, maximumPixelSize: -1)
precondition(minimum.width == 1 && minimum.height == 1)
print("PASS decoder output dimension clamps excessive and negative requests")
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
