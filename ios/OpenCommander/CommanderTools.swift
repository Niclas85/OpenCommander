import Foundation
import CryptoKit
import Darwin

/// Read-only, bounded traversal. Never follows directory links or hides access errors.
enum CommanderTools {
    /// Shared local path input: never interpret shell syntax or remote URLs.
    static func searchDirectory(_ path: String) -> URL? {
        guard !path.isEmpty, !path.contains("\0") else { return nil }
        if path.lowercased().hasPrefix("file:") {
            guard let url = URL(string: path), url.isFileURL,
                  url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
                  url.user == nil, url.password == nil, url.port == nil,
                  url.query == nil, url.fragment == nil,
                  url.path.hasPrefix("/"), !url.path.contains("\0") else { return nil }
            return URL(fileURLWithPath: url.path, isDirectory: true).standardizedFileURL
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }
    struct Scan {
        var entries: [String: URL] = [:]
        var warnings: [String] = []
    }
    static func scan(_ root: URL, hidden: Bool, cancel: FileOperationCancellation,
                     limit: Int = 100_000) throws -> Scan {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
        var result = Scan()
        let base = root.standardizedFileURL.path
        guard let iterator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: hidden ? [] : [.skipsHiddenFiles], errorHandler: { url, error in
                result.warnings.append(url.path + ": " + HistoryFailure.presentation(error)); return true
            }) else { throw CocoaError(.fileReadNoPermission) }
        for case let url as URL in iterator {
            try cancel.check()
            guard result.entries.count < limit else { throw failure("tools_limit", String(limit)) }
            result.entries[String(url.standardizedFileURL.path.dropFirst(base.count + (base == "/" ? 0 : 1)))] = url
        }
        return result
    }
    static func failure(_ key: String, _ detail: String? = nil) -> NSError {
        NSError(domain: "OpenCommander.Tools", code: 1,
                userInfo: [NSLocalizedDescriptionKey: detail.map { L10n.get(key, $0) } ?? L10n.get(key)])
    }
    static func search(_ root: URL, query: String, hidden: Bool, caseSensitive: Bool = false, cancel: FileOperationCancellation) throws -> (urls: [URL], warnings: [String]) {
        let scan = try scan(root, hidden: hidden, cancel: cancel)
        // Plain text matches part of a name; * and ? use anchored glob semantics.
        let normalized = query.precomposedStringWithCanonicalMapping
        let wildcard = normalized.contains("*") || normalized.contains("?")
        let expression = NSRegularExpression.escapedPattern(for: normalized)
            .replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".")
        let regex = try NSRegularExpression(pattern: wildcard ? "^" + expression + "$" : expression,
                                            options: caseSensitive ? [] : .caseInsensitive)
        var urls: [URL] = []
        for (_, url) in scan.entries.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            try cancel.check()
            let name = url.lastPathComponent.precomposedStringWithCanonicalMapping
            if regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil { urls.append(url) }
        }
        return (urls, scan.warnings)
    }
    static func digest(_ url: URL, cancel: FileOperationCancellation) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            try cancel.check()
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        return Data(hash.finalize())
    }
    struct Comparison {
        enum State { case equal, different, leftOnly, rightOnly, unreadable }
        let path: String
        let state: State
        let detail: String
    }
    static func compare(_ left: URL, _ right: URL, hidden: Bool, cancel: FileOperationCancellation) throws -> (rows: [Comparison], warnings: [String]) {
        let a = try scan(left, hidden: hidden, cancel: cancel)
        let b = try scan(right, hidden: hidden, cancel: cancel)
        var rows: [Comparison] = []
        for path in Set(a.entries.keys).union(b.entries.keys).sorted() {
            try cancel.check()
            guard let l = a.entries[path] else { rows.append(.init(path: path, state: .rightOnly, detail: "")); continue }
            guard let r = b.entries[path] else { rows.append(.init(path: path, state: .leftOnly, detail: "")); continue }
            do {
                let beforeL = try identity(l), beforeR = try identity(r)
                let la = try FileManager.default.attributesOfItem(atPath: l.path)
                let ra = try FileManager.default.attributesOfItem(atPath: r.path)
                let lt = la[.type] as? FileAttributeType, rt = ra[.type] as? FileAttributeType
                let equal: Bool
                if lt != rt { equal = false }
                else if lt == .typeDirectory { continue } // descendants are compared individually
                else if lt == .typeSymbolicLink {
                    equal = try FileManager.default.destinationOfSymbolicLink(atPath: l.path) == FileManager.default.destinationOfSymbolicLink(atPath: r.path)
                } else if lt == .typeRegular {
                    if (la[.size] as? NSNumber) != (ra[.size] as? NSNumber) { equal = false }
                    else { equal = try digest(l, cancel: cancel) == digest(r, cancel: cancel) }
                } else { throw failure("tools_unsupported_type") }
                guard beforeL == (try identity(l)), beforeR == (try identity(r)) else { throw failure("tools_changed", path) }
                rows.append(.init(path: path, state: equal ? .equal : .different, detail: ""))
            } catch {
                try cancel.check()
                rows.append(.init(path: path, state: .unreadable, detail: HistoryFailure.presentation(error)))
            }
        }
        return (rows, a.warnings + b.warnings)
    }
    static func identity(_ url: URL) throws -> String {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        return [a[.systemNumber], a[.systemFileNumber], a[.type], a[.size], a[.modificationDate]].map { String(describing: $0) }.joined(separator: "|")
    }
    struct RenameRule {
        var pattern = "[N][E]"
        var find = ""
        var replacement = ""
        var start = 1
        var digits = 3
    }
    struct Rename {
        let source: URL
        let destination: URL
        let identity: String
    }
    struct RenameFailure: Error {
        let cause: Error
        /// Proofs captured immediately after each successful mutation, not
        /// rebuilt from possibly changed destinations after rollback fails.
        let remaining: [FileUndoRecord]
    }
    static func renamePlan(_ urls: [URL], rule: RenameRule) throws -> [Rename] {
        guard !urls.isEmpty, urls.count <= 10_000, rule.start >= 0, rule.start <= Int.max - urls.count,
              (1...9).contains(rule.digits) else { throw failure("tools_invalid_rule") }
        var seen = Set<String>()
        var plan: [Rename] = []
        for (i, url) in urls.enumerated() {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let folder = attributes[.type] as? FileAttributeType == .typeDirectory
            let ext = folder ? "" : url.pathExtension
            let stem = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            // Single-pass expansion: brackets inside original filenames stay literal.
            let regex = try NSRegularExpression(pattern: "\\[(N|E|C)\\]")
            let template = rule.pattern
            var name = template
            for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
                let token = (template as NSString).substring(with: match.range)
                let value = token == "[N]" ? stem : token == "[E]" ? (ext.isEmpty ? "" : "." + ext) : String(format: "%0*d", rule.digits, rule.start + i)
                name = (name as NSString).replacingCharacters(in: match.range, with: value)
            }
            if !rule.find.isEmpty { name = name.replacingOccurrences(of: rule.find, with: rule.replacement) }
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0"), name.utf8.count <= 255 else { throw failure("tools_invalid_name", name) }
            let destination = url.deletingLastPathComponent().appendingPathComponent(name)
            let key = destination.path.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(key).inserted else { throw failure("tools_duplicate_destination", name) }
            // Conservatively refuse occupied names, including other selected sources.
            // Only exact no-ops are permitted; case-only rename needs volume-specific handling.
            if destination.path != url.path && SafeFileOperations.exists(destination) { throw failure("tools_destination_exists", name) }
            plan.append(.init(source: url, destination: destination, identity: try identity(url)))
        }
        return plan
    }
    static func rename(_ plan: [Rename], cancel: FileOperationCancellation,
                       journal: CommanderRenameJournal? = nil,
                       checkpoint: ((Int) throws -> Void)? = nil,
                       move: (URL, URL) throws -> Void = { try SafeFileOperations.renameEntry($0, to: $1) }) throws -> [FileUndoRecord] {
        var done: [FileUndoRecord] = []
        do {
            for row in plan {
                try cancel.check()
                guard row.identity == (try identity(row.source)) else { throw failure("tools_changed", row.source.path) }
                if row.source.path == row.destination.path { continue }
                guard !SafeFileOperations.exists(row.destination) else { throw failure("tools_destination_exists", row.destination.path) }
            }
            for row in plan where row.source.path != row.destination.path {
                try cancel.check()
                guard row.identity == (try identity(row.source)) else { throw failure("tools_changed", row.source.path) }
                let intent = try journal?.prepare(row)
                try move(row.source, row.destination)
                let record = intent?.record ?? FileUndoRecord(source: row.source, destination: row.destination, replacedBackup: nil)
                done.append(record)
                if let journal, let intent { try journal.committed(intent) }
                try checkpoint?(done.count)
            }
        } catch {
            var remaining: [FileUndoRecord] = []
            for record in done.reversed() {
                do {
                    try record.undo(move: true, didRestore: { try journal?.finish(record) })
                } catch {
                    record.setHistoryError(error)
                    remaining.append(record)
                }
            }
            if !remaining.isEmpty { throw RenameFailure(cause: error, remaining: remaining.reversed()) }
            throw error
        }
        return done
    }
}

/// Durable intent BEFORE each local batch mutation. Startup integration must
/// reconcile these proofs, never replay a batch automatically. Explicit root
/// injection keeps CLI fixtures away from the application's real profile.
final class CommanderRenameJournal {
    struct Entry: Codable {
        let id: UUID
        let expected: Data
        let record: FileUndoRecord
        var committed: Bool
        var finished: Bool? = nil
    }
    let directory: URL
    let id: UUID
    init(root: URL, id: UUID = UUID()) throws {
        self.id = id
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let physical = root.resolvingSymlinksInPath().standardizedFileURL
        directory = physical.appendingPathComponent(id.uuidString, isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let attributes = try fm.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
        let parent = open(physical.path, O_RDONLY | O_NOFOLLOW)
        guard parent >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    private func write(_ entry: Entry) throws {
        let data = try JSONEncoder().encode(entry)
        guard data.count <= 1024 * 1024 else { throw CocoaError(.fileWriteInvalidFileName) }
        let parent = open(directory.path, O_RDONLY | O_NOFOLLOW | O_DIRECTORY)
        guard parent >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(parent) }
        var info = stat()
        guard fstat(parent, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else { throw CocoaError(.fileWriteNoPermission) }
        let temporary = ".pending-" + UUID().uuidString
        let final = entry.id.uuidString + ".json"
        let fd = openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: count < 0 ? errno : EIO) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0, renameat(parent, temporary, parent, final) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard fsync(parent) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    func prepare(_ row: CommanderTools.Rename) throws -> Entry {
        guard row.source.isFileURL, row.destination.isFileURL,
              row.source.deletingLastPathComponent().standardizedFileURL == row.destination.deletingLastPathComponent().standardizedFileURL,
              row.source.path != row.destination.path, !SafeFileOperations.exists(row.destination),
              try CommanderTools.identity(row.source) == row.identity else { throw SafeFileOperations.conflict(row.source) }
        let proof = try SafeFileOperations.snapshot(row.source, rootName: row.destination.lastPathComponent,
            providerIdentity: SafeFileOperations.providerLocation(row.destination))
        guard try CommanderTools.identity(row.source) == row.identity else { throw SafeFileOperations.conflict(row.source) }
        let entryID = UUID()
        let record = FileUndoRecord(source: row.source, destination: row.destination, replacedBackup: nil,
            expectedRenameSnapshot: proof, renameBatchID: id, renameEntryID: entryID)
        let entry = Entry(id: entryID, expected: proof, record: record, committed: false)
        try write(entry)
        return entry
    }
    func committed(_ entry: Entry) throws {
        try entry.record.verifyUnchangedDestination()
        var committed = entry; committed.committed = true
        try write(committed)
    }
    private func entries(only id: UUID? = nil) throws -> [Entry] {
        let files = try id.map { [directory.appendingPathComponent($0.uuidString + ".json")] } ??
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        guard files.count <= 10_000 else { throw CocoaError(.fileReadCorruptFile) }
        var entries: [Entry] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { throw CocoaError(.fileReadCorruptFile) }
            let fd = open(file.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw CocoaError(.fileReadCorruptFile) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == geteuid(), info.st_nlink == 1,
                  info.st_size > 0, info.st_size <= 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
            guard data.count == info.st_size else { throw CocoaError(.fileReadCorruptFile) }
            let entry = try JSONDecoder().decode(Entry.self, from: data)
            let record = entry.record
            guard entry.id.uuidString == file.deletingPathExtension().lastPathComponent,
                  record.renameEntryID == entry.id, record.renameBatchID == self.id,
                  entry.expected.count == 32, record.matchesRenameProof(entry.expected),
                  record.source.isFileURL, record.destination.isFileURL,
                  record.source.deletingLastPathComponent().standardizedFileURL == record.destination.deletingLastPathComponent().standardizedFileURL,
                  record.source.path != record.destination.path,
                  record.replacedBackup == nil, record.quarantinedSource == nil else { throw CocoaError(.fileReadCorruptFile) }
            entries.append(entry)
        }
        return entries
    }
    func finish(_ record: FileUndoRecord) throws {
        guard record.renameBatchID == id, let entryID = record.renameEntryID,
              var entry = try entries(only: entryID).first,
              entry.record.sameRenameIntent(as: record) else { throw CocoaError(.fileReadCorruptFile) }
        entry.finished = true
        try write(entry)
    }
    struct Recovery {
        var knownIDs = Set<UUID>()
        var proofs: [UUID: FileUndoRecord] = [:]
        var records: [FileUndoRecord] = []
    }
    func recovery() throws -> Recovery {
        var result = Recovery()
        for entry in try entries() {
            let record = entry.record
            result.knownIDs.insert(entry.id)
            result.proofs[entry.id] = record
            if entry.finished == true { continue }
            // A verified original at its original name means the mutation did
            // not happen or rollback/Undo already restored it. Never touch a
            // foreign occupied destination merely because its name matches.
            if SafeFileOperations.exists(record.source),
               (try? SafeFileOperations.snapshot(record.source, rootName: record.destination.lastPathComponent,
                    providerIdentity: SafeFileOperations.providerLocation(record.destination))) == entry.expected {
                continue
            }
            do { try record.verifyUnchangedDestination() }
            catch { record.setHistoryError(error) }
            result.records.append(record) // changed/missing targets remain non-destructive, inspectable failures
        }
        result.records.sort { $0.createdAt < $1.createdAt }
        return result
    }
    func recover() throws -> [FileUndoRecord] { try recovery().records }

    static func recovery(root: URL) throws -> Recovery {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return Recovery() }
        let info = try fm.attributesOfItem(atPath: root.path)
        guard info[.type] as? FileAttributeType == .typeDirectory,
              (info[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              ((info[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else { throw CocoaError(.fileReadNoPermission) }
        let batches = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        guard batches.count <= 1000 else { throw CocoaError(.fileReadCorruptFile) }
        var result = Recovery()
        for batch in batches.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let recovered = try CommanderRenameJournal(root: root, id: UUID(uuidString: batch.lastPathComponent)!).recovery()
            guard result.knownIDs.isDisjoint(with: recovered.knownIDs),
                  result.knownIDs.count + recovered.knownIDs.count <= 10_000 else { throw CocoaError(.fileReadCorruptFile) }
            result.knownIDs.formUnion(recovered.knownIDs)
            result.proofs.merge(recovered.proofs) { first, _ in first }
            result.records.append(contentsOf: recovered.records)
        }
        result.records.sort { $0.createdAt < $1.createdAt }
        return result
    }
    /// Reconcile only journal-owned move records. Unrelated history is kept.
    /// No filesystem operation is executed by this import/deduplication.
    static func merge(_ history: [OperationType], recovery: Recovery) throws -> [OperationType] {
        let pending = Set(recovery.records.compactMap(\.renameEntryID))
        var seen = Set<UUID>()
        var result: [OperationType] = []
        for operation in history {
            guard case .move(let records) = operation else { result.append(operation); continue }
            for record in records {
                if let id = record.renameEntryID, recovery.knownIDs.contains(id) {
                    guard let proof = recovery.proofs[id], record.sameRenameIntent(as: proof) else { throw CocoaError(.fileReadCorruptFile) }
                }
            }
            let kept = records.filter { record in
                guard let id = record.renameEntryID, recovery.knownIDs.contains(id) else { return true }
                guard pending.contains(id), seen.insert(id).inserted else { return false }
                return true
            }
            if !kept.isEmpty { result.append(.move(files: kept)) }
        }
        let imported = recovery.records.filter { $0.renameEntryID.map { seen.insert($0).inserted } ?? false }
        var batches: [UUID] = []
        var grouped: [UUID: [FileUndoRecord]] = [:]
        for record in imported {
            guard let batch = record.renameBatchID else { throw CocoaError(.fileReadCorruptFile) }
            if grouped[batch] == nil { batches.append(batch) }
            grouped[batch, default: []].append(record)
        }
        for batch in batches { result.append(.move(files: grouped[batch]!)) }
        return result
    }
}
