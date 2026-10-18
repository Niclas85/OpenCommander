import AppKit
import Foundation

let root = URL(fileURLWithPath: "/Users/niklaus/OpenCommander-MacUITest-Hover-20261017", isDirectory: true)
let fm = FileManager.default
func file(_ path: String, _ data: Data) throws {
    let url = root.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !fm.fileExists(atPath: url.path) { try data.write(to: url, options: .withoutOverwriting) }
}
try file("Source/OpenCommander-MacUITest-Drag.txt", Data("Synthetic external drag, hover and edge-scroll acceptance. Grüsse.\n".utf8))
try file("Receive/Keep.txt", Data("Synthetic receive sentinel.\n".utf8))
try file("External/OpenCommander-MacUITest-Document.txt", Data("Synthetic TextEdit destination.\n".utf8))
for index in 0..<70 {
    try file(String(format: "Target/Folder-%03d/Child/Keep.txt", index), Data("Synthetic nested folder sentinel.\n".utf8))
}
for index in 0..<120 {
    try file(String(format: "Target/Row-%03d.txt", index), Data("Synthetic scroll row \(index).\n".utf8))
}
if CommandLine.arguments.contains("--large-list") {
    for index in 0..<20_000 {
        try file(String(format: "LargeList/OpenCommander-Row-%05d.txt", index), Data("Synthetic large-list row \(index).\n".utf8))
    }
}
for (name, color) in [("A", NSColor.systemBlue), ("B", NSColor.systemOrange)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 100)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try file("Media/OpenCommander-MacUITest-\(name).png", bitmap.representation(using: .png, properties: [:])!)
}
print(root.path)
