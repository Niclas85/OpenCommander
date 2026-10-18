import Foundation
import ImageIO

enum MediaPlaybackPolicy {
    static func shouldRestart(position: Double, duration: Double) -> Bool {
        guard position.isFinite, duration.isFinite, position >= 0, duration > 0 else { return false }
        return position >= duration - min(0.05, duration * 0.01)
    }
}

/// Only roots just created by archive materialization may be registered. Never
/// discover/delete old caches or infer ownership from a provider's source URL.
final class PreviewTemporaryFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var roots = Set<URL>()
    func retainCreatedRoot(_ root: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommanderPreview")
        guard root.isFileURL, UUID(uuidString: root.lastPathComponent) != nil,
              root.deletingLastPathComponent().pathComponents.filter({ $0 != "/" }) == base.pathComponents.filter({ $0 != "/" }) else { return }
        lock.lock(); roots.insert(root); lock.unlock()
    }
    deinit { for root in roots { try? FileManager.default.removeItem(at: root) } }
}

enum ImagePreviewLoader {
    enum PreviewError: Error {
        case invalidImage
    }

    /// Decode inside coordinated read access so File Providers can download an
    /// online-only file first. Reading Data preserves filesystem/provider errors
    /// which ImageIO's URL initializer otherwise turns into an unexplained nil.
    static func load(at url: URL, maximumPixelSize: Int,
                     coordinator: NSFileCoordinator = NSFileCoordinator(),
                     prepareURL: (URL) throws -> URL = { $0 }) throws -> CGImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<CGImage, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges,
                               error: &coordinationError) { coordinatedURL in
            result = Result {
                let readableURL = try prepareURL(coordinatedURL)
                let data = try Data(contentsOf: readableURL, options: .mappedIfSafe)
                guard let source = CGImageSourceCreateWithData(data as CFData, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize)
                ] as CFDictionary) else { throw PreviewError.invalidImage }
                return image
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
