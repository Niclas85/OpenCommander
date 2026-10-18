import Foundation
import AppKit
import Darwin

@main struct InteractiveAcceptanceFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 2, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("Existing isolated root required") }
        defer { free(physical) }
        let root = URL(fileURLWithPath: String(cString: physical))
        guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Acceptance-20261018-"),
              root.deletingLastPathComponent().path == "/private/tmp" else { fatalError("Not a test root") }
        let fm = FileManager.default
        func file(_ name: String, _ bytes: Data) throws {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { try bytes.write(to: url, options: .withoutOverwriting) }
        }
        for directory in ["Left/Matrix", "Left/Matrix/Empty", "Right/MatrixTarget", "Limits", "Archives/Source/Ordner/Empty"] {
            try fm.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        for (name, bytes) in [("Alpha.txt", "A"), ("beta.txt", "BBBB"), ("Grüsse & $(nicht-ausführen).txt", "Unicode – 中文\n"),
                              (".Hidden.txt", "hidden"), ("Nested/Child.txt", "Nested data"), ("Space Folder/Sub/Deep.txt", "Deep data")] {
            try file("Left/Matrix/" + name, Data(bytes.utf8))
        }
        try file("Archives/Source/Ordner/Grüsse.txt", Data("Archive content, Grüße.\n".utf8))
        try file("Left/Matrix/Binary.bin", Data((0..<256).map(UInt8.init)))
        try file("Limits/LargeText.txt", Data(String(repeating: "Bounded text preview.\n", count: 160000).utf8))
        try file("Left/Matrix/Broken.jpg", Data("This is not a valid image.".utf8))
        for n in 1...3 {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            (n == 1 ? NSColor.systemBlue : n == 2 ? NSColor.systemOrange : NSColor.systemGreen).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 100)).fill(); NSGraphicsContext.restoreGraphicsState()
            try file("Left/Matrix/Image\(n).jpg", bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!)
            try file("Left/Matrix/Image\(n).png", bitmap.representation(using: .png, properties: [:])!)
            if n == 1 { try file("Left/Matrix/Animation.gif", bitmap.representation(using: .gif, properties: [:])!) }
        }
        // Many small files keep native queue controls observable without using
        // gigabytes of host storage. Each tree has a distinct payload.
        for lane in 1...4 {
            for number in 0..<1000 {
                try file(String(format: "QueueStress/Source/Lane%d/Part-%04d.bin", lane, number),
                         Data(repeating: UInt8(lane), count: 8 * 1024))
            }
        }
        try fm.createDirectory(at: root.appendingPathComponent("QueueStress/Target"), withIntermediateDirectories: true)
        print(root.path)
    }
}
