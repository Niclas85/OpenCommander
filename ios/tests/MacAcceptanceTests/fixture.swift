import Foundation
import AppKit
import Darwin

@main struct AcceptanceFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected an existing empty test root") }
        guard let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("Missing test root") }
        defer { free(physical) }
        let root = URL(fileURLWithPath: String(cString: physical))
        let fm = FileManager.default
        guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Acceptance-20261018-"),
              root.deletingLastPathComponent().path == "/private/tmp" else { fatalError("Not an acceptance fixture") }
        func file(_ path: String, _ data: Data) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { try data.write(to: url, options: .withoutOverwriting) }
        }
        try file("Left/OpenCommander-MacUITest-Drag.txt", Data("Synthetic external file representation. Grüße.\n".utf8))
        try file("Right/Keep.txt", Data("Synthetic destination sentinel.\n".utf8))
        try file("External/OpenCommander-MacUITest-Document.txt", Data("Synthetic external document.\n".utf8))
        try file("QueueSource.txt", Data(repeating: 43, count: 64 * 1024))
        try file("Left/HistoryUndoSource.txt", Data("Synthetic oldest-history Undo proof.\n".utf8))
        try file("Right/HistoryOldestUndo.txt", Data("Synthetic oldest-history Undo proof.\n".utf8))
        for index in 0..<80 { try file(String(format: "Left/Navigation/Folder-%03d/Nested.txt", index), Data("Synthetic navigation sentinel.\n".utf8)) }
        for (name, color) in [("A", NSColor.systemBlue), ("B", NSColor.systemOrange)] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            color.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 100)).fill(); NSGraphicsContext.restoreGraphicsState()
            try file("Media/OpenCommander-MacUITest-\(name).png", bitmap.representation(using: .png, properties: [:])!)
        }
        let history: [OperationType] = (0..<1000).map { index in
            if index == 0 {
                return .copy(files: [FileUndoRecord(source: root.appendingPathComponent("Left/HistoryUndoSource.txt"),
                    destination: root.appendingPathComponent("Right/HistoryOldestUndo.txt"), replacedBackup: nil)])
            }
            var record = CloudOperationRecord(action: "Copy", source: root.appendingPathComponent("Left/Audit-\(index)").path,
                destination: root.appendingPathComponent("Right/Audit-\(index)").path)
            record.actionKey = "copy"; record.identifier = UUID().uuidString; record.createdAt = Date().addingTimeInterval(Double(index - 1000))
            return .cloud(record: record)
        }
        try file("AcceptanceHistory.json", JSONEncoder().encode(history))
        let jobs: [[String: Any]] = (0..<20).map { index in [
            "id": UUID().uuidString, "source": root.appendingPathComponent("QueueSource.txt").path,
            "destination": root.appendingPathComponent(String(format: "Right/Queue-%02d.txt", index)).path,
            "state": "paused", "bytes": 0, "total": 65536, "created": Date().timeIntervalSinceReferenceDate,
            "compact": true, "engine": "file"] }
        try file("Transfers/copy-jobs-v1.json", JSONSerialization.data(withJSONObject: ["version": 1, "limit": 2, "jobs": jobs]))
        print(root.path)
    }
}
