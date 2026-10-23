import Foundation
import MobileCoreServices
import UniformTypeIdentifiers
import ZIPFoundation

class FileEntry: Hashable, Equatable {
    let url: URL
    private let _parent: FileEntry?
    let zipPath: String?
    let zipDirectory: Bool
    let zipSize: Int64
    let zipModified: Int64
    let isUpButton: Bool
    // Retain the original lazy provider for in-process drops: Catalyst may
    // substitute a serialized provider that represents folders as ZIP bytes.
    var dragProvider: NSItemProvider?
    private var listingSize: Int64?
    private var listingModified: Int64?
    private var listingDirectory: Bool?
    private let entryName: String
    private let archiveName: Bool
    private let volumeRoot: Bool

    private func cacheListingMetadata() {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        listingSize = values?.fileSize.map(Int64.init)
        listingModified = values?.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) }
        listingDirectory = values?.isDirectory
    }

    var parent: FileEntry? {
        if let p = _parent { return p }
        if zipPath != nil {
            // ZIP parent logic could be added here if needed
        }
        if url.path == "/" { return nil }
        return FileEntry(url: url.deletingLastPathComponent(), parent: nil)
    }


    init(url: URL, parent: FileEntry?, zipPath: String? = nil, zipDirectory: Bool = false, zipSize: Int64 = 0, zipModified: Int64 = 0, isUpButton: Bool = false) {
        self.url = url
        self._parent = parent
        self.zipPath = zipPath
        self.zipDirectory = zipDirectory
        self.zipSize = zipSize
        self.zipModified = zipModified
        self.isUpButton = isUpButton
        volumeRoot = zipPath == nil && !isUpButton && url.path == "/"
        if isUpButton { entryName = ".." }
        else if let zipPath {
            let normalized = zipPath.hasSuffix("/") ? String(zipPath.dropLast()) : zipPath
            entryName = normalized.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? normalized
        } else { entryName = url.lastPathComponent }
#if targetEnvironment(macCatalyst)
        archiveName = CommanderNativeArchive.supports(entryName)
#else
        archiveName = entryName.lowercased().hasSuffix(".zip")
#endif
    }

    static func == (lhs: FileEntry, rhs: FileEntry) -> Bool {
        return lhs.key() == rhs.key()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key())
    }

    func key() -> String {
        if let zipPath = zipPath {
            return physicalKey() + "!/" + zipPath
        }
        if isZipArchive() {
            return physicalKey() + "!/"
        }
        return physicalKey()
    }

    func physicalKey() -> String {
        return url.path
    }

    func name() -> String {
        if volumeRoot {
            return (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
        }
        return entryName
    }

    func mimeType() -> String {
        if isDirectoryLike() {
            return "resource/folder"
        }
        let ext = (zipPath != nil ? (name() as NSString).pathExtension : url.pathExtension).lowercased()
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    func isPhysical() -> Bool {
        return zipPath == nil
    }

    func isPhysicalDirectory() -> Bool {
        if zipPath != nil { return false }
        if let listingDirectory { return listingDirectory }
        return HostFileSystem.isDirectory(url)
    }

    func isZipArchive() -> Bool {
        return zipPath == nil && archiveName && !isPhysicalDirectory()
    }

    func isZipEntry() -> Bool {
        return zipPath != nil
    }

    func isDirectoryLike() -> Bool {
        return isUpButton || isPhysicalDirectory() || isZipArchive() || (zipPath != nil && zipDirectory)
    }

    /// Archives open in the pane; macOS application packages keep their assigned app.
    func opensInPaneByDefault() -> Bool {
#if targetEnvironment(macCatalyst)
        if zipPath != nil { return zipDirectory }
        if isZipArchive() { return true }
        return isPhysicalDirectory() &&
            (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true
#else
        return isDirectoryLike()
#endif
    }

    func canWriteDirectory() -> Bool {
        if !isPhysicalDirectory() {
            return false
        }
        if (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true {
            return false
        }
        return FileManager.default.isWritableFile(atPath: url.path)
    }
    /// Cached shape only: do not stat FileProvider/network paths on mouse moves.
    var isListedPhysicalDirectory: Bool { zipPath == nil && listingDirectory == true }
    var offersDirectoryDrop: Bool { isListedPhysicalDirectory || (zipPath == nil && isUpButton) }

    func displayPath() -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Device URLs may use either /var or /private/var for the same container.
        let documentsPath = documents.resolvingSymlinksInPath().path
        let resolvedPath = url.resolvingSymlinksInPath().path
        let physicalPath: String
        if resolvedPath == documentsPath {
            physicalPath = "/Documents"
        } else if resolvedPath.hasPrefix(documentsPath + "/") {
            physicalPath = "/Documents" + String(resolvedPath.dropFirst(documentsPath.count))
        } else {
            physicalPath = url.path
        }
        if let zipPath = zipPath {
            return physicalPath + "!/" + zipPath
        }
        if isZipArchive() {
            return physicalPath + "!/"
        }
        return physicalPath
    }

    func size() -> Int64 {
        if let _ = zipPath {
            return zipSize
        }
        if let listingSize { return listingSize }
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            return attr[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    func modified() -> Int64 {
        if let _ = zipPath {
            return zipModified
        }
        if let listingModified { return listingModified }
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
            if let date = attr[.modificationDate] as? Date {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
        } catch {}
        return 0
    }

    func children(directoriesOnly: Bool) -> [FileEntry] {
        // Compatibility for non-UI callers. The browser uses readChildren and
        // presents failures instead of turning them into an empty directory.
        do { return try readChildren(directoriesOnly: directoriesOnly) }
        catch { return [] }
    }

    func readChildren(directoriesOnly: Bool) throws -> [FileEntry] {
        if isZipArchive() || isZipEntry() {
            return try zipChildren(directoriesOnly: directoriesOnly)
        }
        
        var entries: [FileEntry] = []
        let urls = try HostFileSystem.directoryContents(at: url,
            showHidden: UserDefaults.standard.bool(forKey: "show_hidden_files"))
        // Directly opened roots are not children of a previous listing, so
        // their metadata cache starts empty. A successful enumeration proves
        // the root is a directory, including when it contains no children.
        // Drop proposals can now recognize it without blocking filesystem I/O.
        listingDirectory = true
        for childUrl in urls {
            let entry = FileEntry(url: childUrl, parent: self)
            entry.cacheListingMetadata()
            if directoriesOnly && !entry.isDirectoryLike() {
                continue
            }
            entries.append(entry)
        }
        
        // Sort like Android: directories first, then alphabetically
        entries.sort { a, b in
            if a.isDirectoryLike() && !b.isDirectoryLike() { return true }
            if !a.isDirectoryLike() && b.isDirectoryLike() { return false }
            return a.name().localizedStandardCompare(b.name()) == .orderedAscending
        }
        return entries
    }

    func contentBytes() -> Int64 {
        if isZipEntry() || isZipArchive() {
            // Synthetic archive folders have a listing size of zero, not zero
            // contents. Re-read bounded metadata; failures remain unknown.
            return (try? archiveProperties().size) ?? -2
        }
        if !isPhysicalDirectory() { return size() }
        return (try? BoundedFolderSize.bytes(at: url, excludingRecovery: true)) ?? -2
    }

    func materializedURLForOpening(sourceURL: URL? = nil, temporaryRoot: ((URL) -> Void)? = nil) throws -> URL {
        let sourceURL = sourceURL ?? url
        guard let zipPath else { return sourceURL }
#if targetEnvironment(macCatalyst)
        if sourceURL.pathExtension.lowercased() != "zip" {
            guard !zipDirectory else { throw CocoaError(.fileReadUnsupportedScheme) }
            let parent = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommanderPreview", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try CommanderNativeArchive.extract(sourceURL, prefixes: [zipPath], to: root, maximumBytes: 128 * 1024 * 1024)
            temporaryRoot?(root)
            return root.appendingPathComponent(zipPath)
        }
#endif
        guard !zipDirectory, let archive = Archive(url: sourceURL, accessMode: .read),
              let item = archive.first(where: { $0.path == zipPath }) else {
            throw NSError(domain: "OpenCommander", code: 2, userInfo: [NSLocalizedDescriptionKey: "ZIP entry is unavailable"])
        }
        var limits = SafeArchiveLimits()
        try limits.include(path: item.path, size: UInt64(item.uncompressedSize), symbolicLink: item.type == .symlink)
        guard item.uncompressedSize <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCommanderPreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let output = outputDirectory.appendingPathComponent(name())
        do {
            guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            var written: UInt64 = 0
            let checksum = try archive.extract(item) { data in
                guard UInt64(data.count) <= item.uncompressedSize - written else { throw CocoaError(.fileReadCorruptFile) }
                written += UInt64(data.count)
                try handle.write(contentsOf: data)
            }
            guard checksum == item.checksum, written == item.uncompressedSize else { throw CocoaError(.fileReadCorruptFile) }
            temporaryRoot?(outputDirectory)
            return output
        } catch {
            try? FileManager.default.removeItem(at: outputDirectory)
            throw error
        }
    }

    func archiveProperties() throws -> CommanderArchiveProperties {
        guard zipPath != nil || isZipArchive() else { throw CocoaError(.fileReadUnsupportedScheme) }
        let selectedPath = zipPath ?? ""
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        func zipMembers() throws -> [CommanderArchiveProperties.Member] {
            var members: [CommanderArchiveProperties.Member] = []
            let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
            for item in archive {
                guard members.count < 100_000, ProcessInfo.processInfo.systemUptime < deadline,
                      item.uncompressedSize <= UInt64(Int64.max), item.compressedSize <= UInt64(Int64.max) else {
                    throw CocoaError(.fileReadTooLarge)
                }
                members.append(.init(path: item.path, directory: item.type == .directory,
                    size: Int64(item.uncompressedSize), compressed: Int64(item.compressedSize),
                    modified: item.fileAttributes[.modificationDate] as? Date))
            }
            return members
        }
        let members: [CommanderArchiveProperties.Member]
#if targetEnvironment(macCatalyst)
        if url.pathExtension.lowercased() != "zip" {
            members = try CommanderNativeArchive.members(url, checkCancellation: {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw CocoaError(.userCancelled) }
            }).map {
                .init(path: $0.path, directory: $0.directory, size: $0.size, compressed: nil,
                      modified: $0.modified > 0 ? Date(timeIntervalSince1970: Double($0.modified) / 1000) : nil)
            }
        } else {
            members = try zipMembers()
        }
#else
        members = try zipMembers()
#endif
        return try CommanderArchiveProperties(member: selectedPath, directory: zipPath == nil || zipDirectory, members: members,
            wallClockTimestamp: url.pathExtension.lowercased() == "zip")
    }

    private func zipChildren(directoriesOnly: Bool) throws -> [FileEntry] {
        let members: [(path: String, directory: Bool, size: Int64, modified: Int64, symbolic: Bool)]
#if targetEnvironment(macCatalyst)
        if url.pathExtension.lowercased() != "zip" {
            members = try CommanderNativeArchive.members(url).map { ($0.path, $0.directory, $0.size, $0.modified, false) }
        } else {
            let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
            members = archive.map { ($0.path, $0.type == .directory, Int64($0.uncompressedSize), Int64((($0.fileAttributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000), $0.type == .symlink) }
        }
#else
        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        members = archive.map { ($0.path, $0.type == .directory, Int64($0.uncompressedSize), Int64((($0.fileAttributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000), $0.type == .symlink) }
#endif
        var base = zipPath ?? ""
        if !base.isEmpty && !base.hasSuffix("/") { base += "/" }

        struct ZipChild {
            var isDirectory: Bool
            var size: Int64
            var modified: Int64
        }
        var children: [String: ZipChild] = [:]
        var limits = SafeArchiveLimits()
        let hidden = UserDefaults.standard.bool(forKey: "show_hidden_files")
        for item in members {
            try limits.include(path: item.path, size: UInt64(item.size), symbolicLink: item.symbolic)
            guard item.path.hasPrefix(base) else { continue }
            let remainder = String(item.path.dropFirst(base.count))
            guard !remainder.isEmpty else { continue }
            let parts = remainder.split(separator: "/", omittingEmptySubsequences: true)
            guard let first = parts.first else { continue }
            let childName = String(first)
            guard hidden || !childName.hasPrefix(".") else { continue }
            let childPath = base + childName
            let directory = parts.count > 1 || item.directory || remainder.hasSuffix("/")
            let childSize = directory ? 0 : item.size
            if var existing = children[childName] {
                existing.isDirectory = existing.isDirectory || directory
                existing.size = max(existing.size, childSize)
                children[childName] = existing
            } else {
                children[childName] = ZipChild(isDirectory: directory, size: childSize,
                    modified: item.modified)
            }
            _ = childPath
        }

        return children.compactMap { name, child in
            if directoriesOnly && !child.isDirectory { return nil }
            return FileEntry(
                url: url,
                parent: self,
                zipPath: base + name + (child.isDirectory ? "/" : ""),
                zipDirectory: child.isDirectory,
                zipSize: child.size,
                zipModified: child.modified
            )
        }.sorted { a, b in
            if a.isDirectoryLike() != b.isDirectoryLike() { return a.isDirectoryLike() }
            return a.name().localizedStandardCompare(b.name()) == .orderedAscending
        }
    }
}
