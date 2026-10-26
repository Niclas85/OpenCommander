import Foundation
import ImageIO
import Darwin

/// Read at most one byte beyond the display limit, including for special files.
enum BoundedTextPreviewLoader {
    static let maximumBytes = 2 * 1024 * 1024
    enum Content { case text(String, truncated: Bool), unsupported }

    static func isCandidate(_ url: URL) -> Bool {
        let extensions: Set<String> = ["txt", "md", "markdown", "log", "csv", "tsv", "json", "xml", "yaml", "yml", "toml", "ini", "conf", "cfg", "swift", "py", "js", "ts", "css", "html", "htm", "sh", "c", "h", "cpp", "java", "kt", "rs", "sql", "bin", "dat"]
        return extensions.contains(url.pathExtension.lowercased()) || ["Makefile", "Dockerfile", "LICENSE", "README"].contains(url.lastPathComponent)
    }

    static func load(at url: URL) throws -> Content {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard attributes.st_mode & S_IFMT == S_IFREG else { return .unsupported }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while bytes.count <= maximumBytes {
            let count = read(descriptor, &buffer, min(buffer.count, maximumBytes + 1 - bytes.count))
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        let truncated = bytes.count > maximumBytes
        bytes = bytes.prefix(maximumBytes)
        guard !bytes.contains(0) else { return .unsupported }
        // A valid multibyte character may straddle the byte limit. Only trim
        // the final incomplete code point; never silently repair invalid UTF-8.
        for trim in 0...(truncated ? min(3, bytes.count) : 0) {
            if trim > 0 {
                let suffix = Array(bytes.suffix(trim))
                let lead = suffix[0]
                let expected = (0xC2...0xDF).contains(lead) ? 2 : (0xE0...0xEF).contains(lead) ? 3 : (0xF0...0xF4).contains(lead) ? 4 : 0
                guard expected > trim, suffix.dropFirst().allSatisfy({ (0x80...0xBF).contains($0) }) else { continue }
            }
            if let text = String(data: bytes.dropLast(trim), encoding: .utf8) {
                return .text(text, truncated: truncated)
            }
        }
        return .unsupported
    }
}

enum MediaPlaybackPolicy {
    static func shouldRestart(position: Double, duration: Double) -> Bool {
        guard position.isFinite, duration.isFinite, position >= 0, duration > 0 else { return false }
        return position >= duration - min(0.05, duration * 0.01)
    }
}

enum ThumbnailInputPolicy {
    static let maximumBytes: Int64 = 32 * 1024 * 1024
    static func permits(size: Int64) -> Bool { size >= 0 && size <= maximumBytes }
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
    static let maximumBytes = 128 * 1024 * 1024
    static let maximumDecodedDimension = 4096
    enum PreviewError: Error, Equatable {
        case invalidImage
        case tooLarge
        case unsupportedFile
    }
    private static func preflightSourceSize(_ url: URL) throws {
        // Metadata only: refuse known oversized File Provider placeholders
        // before coordinated reading can request hydration of their body.
        var fresh = url; fresh.removeAllCachedResourceValues()
        if let size = try fresh.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            throw PreviewError.tooLarge
        }
    }

    /// Quick Look receives an immutable owned snapshot, not an unbounded
    /// provider/source URL that can grow after metadata inspection.
    static func vectorSnapshot(at url: URL, coordinator: NSFileCoordinator,
                               temporaryRoot: (URL) -> Void) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try preflightSourceSize(url)
        var error: NSError?
        var bytes: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { coordinatedURL in
            bytes = Result { try boundedData(at: coordinatedURL) }
        }
        if let error { throw error }
        guard let bytes else { throw CocoaError(.fileReadUnknown) }
        let data = try bytes.get()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommanderPreview")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        temporaryRoot(root)
        let snapshot = root.appendingPathComponent("Preview.svg")
        try data.write(to: snapshot, options: .atomic)
        return snapshot
    }

    /// Open nonblocking before inspecting the descriptor: a FIFO must not hang
    /// the preview worker. Recheck while reading because a file may grow after stat.
    static func boundedData(at url: URL, limit: Int = maximumBytes) throws -> Data {
        precondition(limit >= 0 && limit < Int.max)
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard attributes.st_mode & S_IFMT == S_IFREG else { throw PreviewError.unsupportedFile }
        guard attributes.st_size <= limit else { throw PreviewError.tooLarge }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while bytes.count <= limit {
            let count = read(descriptor, &buffer, min(buffer.count, limit + 1 - bytes.count))
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        guard bytes.count <= limit else { throw PreviewError.tooLarge }
        return bytes
    }

    /// Decode inside coordinated read access so File Providers can download an
    /// online-only file first. Reading Data preserves filesystem/provider errors
    /// which ImageIO's URL initializer otherwise turns into an unexplained nil.
    static func load(at url: URL, maximumPixelSize: Int,
                     coordinator: NSFileCoordinator = NSFileCoordinator(),
                     preflightSource: Bool = true,
                     prepareURL: (URL) throws -> URL = { $0 }) throws -> CGImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if preflightSource { try preflightSourceSize(url) }
        var coordinationError: NSError?
        var result: Result<CGImage, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges,
                               error: &coordinationError) { coordinatedURL in
            result = Result {
                let readableURL = try prepareURL(coordinatedURL)
                let data = try boundedData(at: readableURL)
                guard let source = CGImageSourceCreateWithData(data as CFData, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(maximumDecodedDimension, max(1, maximumPixelSize))
                ] as CFDictionary) else { throw PreviewError.invalidImage }
                return image
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
