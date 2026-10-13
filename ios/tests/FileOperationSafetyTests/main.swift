import Foundation
import CryptoKit

let fm = FileManager.default
let fixture = fm.temporaryDirectory.appendingPathComponent("OpenCommander-SafetyTests-\(UUID().uuidString)")
try fm.createDirectory(at: fixture, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: fixture) }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { fatalError("FAIL: " + message) }
}
func write(_ name: String, _ content: String) throws -> URL {
    let url = fixture.appendingPathComponent(name)
    try Data(content.utf8).write(to: url)
    return url
}
func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
func mustFail(_ label: String, _ action: () throws -> Void) {
    do { try action(); fatalError("FAIL: expected error: " + label) } catch { }
}

let source = try write("source.txt", "new contents")
let sizeFixture = fixture.appendingPathComponent("size-check")
try fm.createDirectory(at: sizeFixture, withIntermediateDirectories: false)
try Data("visible".utf8).write(to: sizeFixture.appendingPathComponent(".ordinary-hidden"))
let recoveryFixture = sizeFixture.appendingPathComponent(".OpenCommanderJob-" + UUID().uuidString)
try fm.createDirectory(at: recoveryFixture, withIntermediateDirectories: false)
try Data("recovery".utf8).write(to: recoveryFixture.appendingPathComponent("private"))
let similarFile = sizeFixture.appendingPathComponent(".OpenCommanderUndo-" + UUID().uuidString)
try Data("file".utf8).write(to: similarFile)
try check(BoundedFolderSize.bytes(at: sizeFixture) == 19, "Default folder size includes all regular files")
try check(BoundedFolderSize.bytes(at: sizeFixture, excludingRecovery: true) == 11, "UI size excludes private recovery directories, not hidden files or similarly named files")
print("PASS: folder size excludes internal recovery only")
let target = try write("target.txt", "old contents")
mustFail("partial copy") {
    _ = try SafeFileOperations.copyReplacing(source: source, destination: target, replace: true, copy: { _, staging in
        try Data("partial".utf8).write(to: staging)
        throw NSError(domain: "InjectedCopyFailure", code: 1)
    })
}
try check(contents(target) == "old contents", "partial copy leaves previous target in place")
try check(contents(source) == "new contents", "partial copy leaves source in place")

mustFail("publication failure") {
    _ = try SafeFileOperations.copyReplacing(source: source, destination: target, replace: true,
                                             publish: { _, _ in throw NSError(domain: "InjectedPublishFailure", code: 1) })
}
try check(contents(target) == "old contents", "previous target restored after publication failure")

let backup = try SafeFileOperations.copyReplacing(source: source, destination: target, replace: true)
try check(backup != nil, "replacement retains old version")
try check(contents(target) == "new contents", "complete replacement published")
let copyRecord = FileUndoRecord(source: source, destination: target, replacedBackup: backup)
let date = try fm.attributesOfItem(atPath: target.path)[.modificationDate] as! Date
try Data("new CONtents".utf8).write(to: target) // Same size.
try fm.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
mustFail("edited destination") { try copyRecord.undo(move: false) }
try check(contents(target) == "new CONtents", "edited file retained")
try check(contents(backup!) == "old contents", "backup retained after refused undo")

let second = try write("second.txt", "unchanged")
let secondRecord = FileUndoRecord(source: source, destination: second, replacedBackup: nil)
try secondRecord.undo(move: false)
try check(!SafeFileOperations.exists(second), "unchanged copy undone")
try secondRecord.undo(move: false) // Completed records are idempotent during partial batch retries.
try check(secondRecord.completed, "completed record remains completed")
let recoveryFolders = try fm.contentsOfDirectory(at: fixture, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix(".OpenCommanderUndo-") }
try check(recoveryFolders.contains { fm.fileExists(atPath: $0.appendingPathComponent("second.txt").path) },
          "undone copy retained for recovery")

let moved = try write("moved.txt", "moved contents")
let original = fixture.appendingPathComponent("original.txt")
let moveRecord = FileUndoRecord(source: original, destination: moved, replacedBackup: nil)
_ = try write("original.txt", "new file at original path")
mustFail("source conflict") { try moveRecord.undo(move: true) }
try check(contents(original) == "new file at original path", "new source file not overwritten")
try check(contents(moved) == "moved contents", "destination retained on conflict")
try fm.removeItem(at: original)
try moveRecord.undo(move: true)
try check(contents(original) == "moved contents", "move can be undone after conflict is resolved")

let retryTarget = try write("retry.txt", "copy")
let retryBackup = fixture.appendingPathComponent("retry-backup.txt")
let missingBackupRecord = FileUndoRecord(source: source, destination: retryTarget, replacedBackup: retryBackup)
var legacyRetryJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(missingBackupRecord)) as! [String: Any]
legacyRetryJSON.removeValue(forKey: "backupVerificationRequired")
legacyRetryJSON.removeValue(forKey: "backupSnapshot")
let retryRecord = try JSONDecoder().decode(FileUndoRecord.self, from: JSONSerialization.data(withJSONObject: legacyRetryJSON))
mustFail("missing backup") { try retryRecord.undo(move: false) }
try check(contents(retryTarget) == "copy", "missing backup refuses before removing current target")
_ = try write("retry-backup.txt", "previous")
mustFail("new record with initially unverifiable backup") { try missingBackupRecord.undo(move: false) }
try check(contents(retryTarget) == "copy", "unverified old version must not displace current target")
try retryRecord.undo(move: false)
try check(contents(retryTarget) == "previous", "retry resumes restoration without repeating destination removal")

let folder = fixture.appendingPathComponent("folder")
try fm.createDirectory(at: folder, withIntermediateDirectories: false)
let folderRecord = FileUndoRecord(source: source, destination: folder, replacedBackup: nil)
try Data("added".utf8).write(to: folder.appendingPathComponent("new.txt"))
mustFail("new directory child") { try folderRecord.undo(move: false) }
try check(SafeFileOperations.exists(folder.appendingPathComponent("new.txt")), "added child retained")
print("PASS: staged copy failure, replacement backup, same-size edits, copy undo, recovery, source conflict, move undo, partial retry and added children")

let independentRoot = fixture.appendingPathComponent("independent-recovery", isDirectory: true)
try fm.createDirectory(at: independentRoot, withIntermediateDirectories: false)
let providerTarget = try write("provider-target.txt", "provider old")
let independentBackup = try SafeFileOperations.copyReplacing(source: source, destination: providerTarget,
    replace: true, recoveryRoot: independentRoot)!
try check(independentBackup.path.hasPrefix(independentRoot.path + "/"), "provider backup outside sync staging")
let providerUndo = FileUndoRecord(source: source, destination: providerTarget, replacedBackup: independentBackup)
// Reproduce a provider discarding the on-volume 'previous' during reconciliation.
for directory in try fm.contentsOfDirectory(at: fixture, includingPropertiesForKeys: nil) where directory.lastPathComponent.hasPrefix(".OpenCommanderTransfer-") {
    let displaced = directory.appendingPathComponent("previous")
    if SafeFileOperations.exists(displaced) { try fm.removeItem(at: displaced) }
}
let reloadedProviderUndo = try JSONDecoder().decode(FileUndoRecord.self, from: JSONEncoder().encode(providerUndo))
try reloadedProviderUndo.undo(move: false)
try check(contents(providerTarget) == "provider old", "independent backup restores despite discarded staging")
try check(contents(independentBackup) == "provider old", "restored previous version remains independently recoverable")
let changedBackupTarget = try write("backup-guard-target.txt", "new")
let changedBackup = try write("backup-guard-previous.txt", "old")
let changedBackupUndo = FileUndoRecord(source: source, destination: changedBackupTarget, replacedBackup: changedBackup)
try Data("externally changed".utf8).write(to: changedBackup)
mustFail("changed backup") { try changedBackupUndo.undo(move: false) }
try check(contents(changedBackupTarget) == "new", "changed backup refuses before current target removal")
print("PASS: independent provider recovery, discarded staging, persisted verified backup and changed-backup refusal before writes")

let providerFailTarget = try write("provider-fail-target.txt", "original provider bytes")
mustFail("independent recovery publication failure") {
    _ = try SafeFileOperations.copyReplacing(source: source, destination: providerFailTarget,
        replace: true, recoveryRoot: independentRoot, publish: { _, _ in
            throw NSError(domain: "InjectedPublishFailure", code: 2)
        })
}
try check(contents(providerFailTarget) == "original provider bytes", "independent recovery rollback retains displaced original")
let backupRaceTarget = try write("backup-race-target.txt", "before backup")
mustFail("edit during independent backup") {
    _ = try SafeFileOperations.copyReplacing(source: source, destination: backupRaceTarget,
        replace: true, recoveryRoot: independentRoot, copy: { from, to in
            try fm.copyItem(at: from, to: to)
            if from == backupRaceTarget { try Data("edited while backing up".utf8).write(to: from) }
        })
}
try check(contents(backupRaceTarget) == "edited while backing up", "independent backup race refuses before displacement")
print("PASS: independent recovery publication rollback and racing target edit retained before displacement")

let persistedTarget = try write("persisted.txt", "saved")
let persisted = FileUndoRecord(source: source, destination: persistedTarget, replacedBackup: nil)
let reloaded = try JSONDecoder().decode(FileUndoRecord.self, from: JSONEncoder().encode(persisted))
try check(reloaded.createdAt == persisted.createdAt, "history timestamp survives restart")
try reloaded.undo(move: false)
try check(!SafeFileOperations.exists(persistedTarget), "saved undo remains operational")
let guardedTarget = try write("persisted-guard.txt", "before")
let guarded = FileUndoRecord(source: source, destination: guardedTarget, replacedBackup: nil)
let guardedReloaded = try JSONDecoder().decode(FileUndoRecord.self, from: JSONEncoder().encode(guarded))
try Data("after!".utf8).write(to: guardedTarget)
mustFail("persisted snapshot guard") { try guardedReloaded.undo(move: false) }
try check(contents(guardedTarget) == "after!", "persisted history preserves external changes")
print("PASS: Codable history roundtrip and post-restart conflict protection")

let cancellation = FileOperationCancellation()
let cancelTarget = try write("cancel-target.txt", "old destination")
cancellation.cancel()
mustFail("cancel before transfer") {
    _ = try SafeFileOperations.copyReplacing(source: source, destination: cancelTarget, replace: true, copy: cancellation.copy)
}
try check(contents(cancelTarget) == "old destination", "cancel keeps destination")
cancellation.reset()
let nativeCopy = fixture.appendingPathComponent("native-copy.txt")
_ = try SafeFileOperations.copyReplacing(source: source, destination: nativeCopy, replace: false, copy: cancellation.copy)
try check(contents(nativeCopy) == contents(source), "native cancellable copy preserves content")
mustFail("cancel after staging before publish") {
    _ = try SafeFileOperations.copyReplacing(source: source, destination: cancelTarget, replace: true, copy: { from, to in
        try cancellation.copy(from, to)
        cancellation.cancel()
        try cancellation.check()
    })
}
try check(contents(cancelTarget) == "old destination", "cancelled staging does not displace target")
print("PASS: native copy and cancellation preserves existing destination")

cancellation.reset()
let nativeFolder = fixture.appendingPathComponent("native-folder")
let nested = folder.appendingPathComponent("nested")
try fm.createDirectory(at: nested, withIntermediateDirectories: false)
try Data("nested content".utf8).write(to: nested.appendingPathComponent("child.txt"))
try fm.createSymbolicLink(atPath: folder.appendingPathComponent("outside-link").path, withDestinationPath: source.path)
try fm.createSymbolicLink(atPath: folder.appendingPathComponent("dangling-link").path, withDestinationPath: "/nonexistent-opencommander-fixture")
_ = try SafeFileOperations.copyReplacing(source: folder, destination: nativeFolder, replace: false, copy: cancellation.copy)
try check(contents(nativeFolder.appendingPathComponent("nested/child.txt")) == "nested content", "recursive native copy")
try check(fm.destinationOfSymbolicLink(atPath: nativeFolder.appendingPathComponent("outside-link").path) == source.path, "copy does not dereference links")
try check(SafeFileOperations.exists(nativeFolder.appendingPathComponent("dangling-link")), "dangling link copied")
let scannedBytes = try BoundedFolderSize.bytes(at: folder)
try check(scannedBytes == Int64("added".utf8.count + "nested content".utf8.count), "folder scan skips symlink content (actual: \(scannedBytes))")
mustFail("bounded folder entry limit") { _ = try BoundedFolderSize.bytes(at: folder, maximumEntries: 1) }
mustFail("bounded folder timeout") { _ = try BoundedFolderSize.bytes(at: folder, timeout: -1) }
print("PASS: recursive native copy, symlinks and bounded folder metadata")

for name in ["../escape", "/absolute", "a/../escape", "a/./b", "a//b", "C:/escape", "a\\b", "nul\0name", ""] {
    mustFail("unsafe ZIP name \(name)") {
        var limits = SafeArchiveLimits()
        try limits.include(path: name, size: 1, symbolicLink: false)
    }
}
mustFail("ZIP symlink") {
    var limits = SafeArchiveLimits()
    try limits.include(path: "link", size: 1, symbolicLink: true)
}
mustFail("case insensitive ZIP duplicate") {
    var limits = SafeArchiveLimits()
    try limits.include(path: "Folder/", size: 0, symbolicLink: false)
    try limits.include(path: "folder", size: 0, symbolicLink: false)
}
mustFail("ZIP byte limit") {
    var limits = SafeArchiveLimits()
    try limits.include(path: "big", size: SafeArchiveLimits.maximumBytes, symbolicLink: false)
    try limits.include(path: "extra", size: 1, symbolicLink: false)
}
print("PASS: ZIP traversal, duplicate, symlink and expanded-size safety limits")
let permissionsTarget = try write("permission-guard.txt", "unchanged content")
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: permissionsTarget.path)
let permissionsRecord = FileUndoRecord(source: source, destination: permissionsTarget, replacedBackup: nil)
try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: permissionsTarget.path)
mustFail("metadata-only external change") { try permissionsRecord.undo(move: false) }
try check(SafeFileOperations.exists(permissionsTarget), "metadata-edited destination retained")
print("PASS: undo protects external permission changes")
try check(DesktopInteractionPolicy.contextSelection(clicked: "b", selected: ["a", "b"]) == ["a", "b"],
          "context action retains existing multi-selection")
try check(DesktopInteractionPolicy.contextSelection(clicked: "c", selected: ["a", "b"]) == ["c"],
          "context action selects an unselected clicked entry")
try check(!DesktopInteractionPolicy.showsExtraction(archiveContext: false, selectedArchives: []), "no extraction without selection")
try check(!DesktopInteractionPolicy.showsExtraction(archiveContext: false, selectedArchives: [false]), "hide extraction for normal file")
try check(!DesktopInteractionPolicy.showsExtraction(archiveContext: false, selectedArchives: [true, false]), "hide extraction for mixed selection")
try check(DesktopInteractionPolicy.showsExtraction(archiveContext: false, selectedArchives: [true]), "show extraction for ZIP")
try check(DesktopInteractionPolicy.showsExtraction(archiveContext: true, selectedArchives: []), "show extraction inside ZIP")
print("PASS: Linux desktop context-selection and ZIP-action parity")
let displayedKeys = ["c", "a", "b", "d"]
let plainSelection = DesktopInteractionPolicy.selection(clicked: "a", visible: displayedKeys, selected: ["a", "d"], anchor: "d", extend: false, toggle: false)
try check(plainSelection.keys == ["a"] && plainSelection.anchor == "a", "plain desktop click replaces selection")
let toggledSelection = DesktopInteractionPolicy.selection(clicked: "d", visible: displayedKeys, selected: ["a", "d"], anchor: "a", extend: false, toggle: true)
try check(toggledSelection.keys == ["a"] && toggledSelection.anchor == "d", "Command click toggles one entry")
let rangeSelection = DesktopInteractionPolicy.selection(clicked: "d", visible: displayedKeys, selected: ["c"], anchor: "a", extend: true, toggle: false)
try check(rangeSelection.keys == ["a", "b", "d"] && rangeSelection.anchor == "a", "Shift uses the visible sorted range and retains its anchor")
let addedRange = DesktopInteractionPolicy.selection(clicked: "d", visible: displayedKeys, selected: ["c"], anchor: "a", extend: true, toggle: true)
try check(addedRange.keys == Set(displayedKeys), "Command Shift adds a range")
let staleAnchor = DesktopInteractionPolicy.selection(clicked: "b", visible: displayedKeys, selected: ["a"], anchor: "removed", extend: true, toggle: false)
try check(staleAnchor.keys == ["b"], "hidden or stale anchors cannot select unrelated entries")
print("PASS: shared desktop plain/Command/Shift selection, sorted ranges and stale-anchor protection")
let cloudRecord = CloudOperationRecord(action: "Verschieben", source: "OneDrive online:/Quelle/Grüsse.txt", destination: "OneDrive online:/Ziel/Grüsse.txt")
let cloudData = try JSONEncoder().encode(cloudRecord)
try check(JSONDecoder().decode(CloudOperationRecord.self, from: cloudData) == cloudRecord,
          "cloud history preserves action, Unicode locations and completion date across restart")
print("PASS: persistent cloud audit history round-trip")
let fileDigest = "sha256:" + Data(SHA256.hash(data: Data("fixture".utf8))).base64EncodedString()
let cloudObject = CloudUndoPayload.Object(id: "item-1", name: "Grüsse.txt", path: "/Grüsse.txt", parent: nil,
    parentPath: nil, content: ["": fileDigest])
let cloudUndo = CloudUndoPayload(endpoint: "drive-account-1", account: "account-pin-1", kind: "relocate",
    current: cloudObject, originalName: "Vorher.txt", originalParent: nil, originalParentPath: nil)
try cloudUndo.validate()
let cloudUndoRoundTrip = try JSONDecoder().decode(CloudUndoPayload.self, from: JSONEncoder().encode(cloudUndo))
try check(cloudUndoRoundTrip == cloudUndo, "persistent cloud Undo proof survives serialization")
let unsafeName = CloudUndoPayload(endpoint: "drive-account-1", account: "account-pin-1", kind: "relocate",
    current: cloudObject, originalName: "../escape", originalParent: nil, originalParentPath: nil)
mustFail("unsafe cloud Undo name") { try unsafeName.validate() }
let unsafePathObject = CloudUndoPayload.Object(id: "item-1", name: "Grüsse.txt", path: "/Grüsse.txt", parent: nil,
    parentPath: nil, content: ["../escape": fileDigest])
let unsafePath = CloudUndoPayload(endpoint: "drive-account-1", account: "account-pin-1", kind: "relocate",
    current: unsafePathObject, originalName: "Vorher.txt", originalParent: nil, originalParentPath: nil)
mustFail("unsafe cloud Undo manifest path") { try unsafePath.validate() }
let invalidDigestObject = CloudUndoPayload.Object(id: "item-1", name: "Grüsse.txt", path: "/Grüsse.txt", parent: nil,
    parentPath: nil, content: ["": "sha256:invalid"])
let invalidDigest = CloudUndoPayload(endpoint: "drive-account-1", account: "account-pin-1", kind: "relocate",
    current: invalidDigestObject, originalName: "Vorher.txt", originalParent: nil, originalParentPath: nil)
mustFail("invalid cloud Undo content proof") { try invalidDigest.validate() }
print("PASS: cloud Undo proof round-trip and unsafe name/path/digest refusal")
let mixedHistory: [OperationType] = [.copy(files: [permissionsRecord]), .cloud(record: cloudRecord)]
let decodedHistory = try JSONDecoder().decode([OperationType].self, from: JSONEncoder().encode(mixedHistory))
try check(decodedHistory.count == 2, "local and online history coexist")
if case .copy(let files) = decodedHistory[0] {
    try check(files.first?.destination == permissionsTarget, "existing local undo schema preserved")
} else { fatalError("FAIL: local history type changed") }
if case .cloud(let record) = decodedHistory[1] {
    try check(record == cloudRecord, "cloud history restored without local undo paths")
} else { fatalError("FAIL: cloud history type changed") }
print("PASS: mixed local undo and cloud audit history compatibility")

let historyLanguage = L10n.currentLanguage
L10n.currentLanguage = "de"
let localizedRecord = FileUndoRecord(source: source, destination: permissionsTarget, replacedBackup: nil)
localizedRecord.setHistoryError(NSError(domain: NSCocoaErrorDomain, code: 4,
    userInfo: [NSLocalizedDescriptionKey: "The file could not be moved because it does not exist."]))
try check(localizedRecord.historyErrorMessage == L10n.get("history_error_missing"), "OS English does not leak into German history")
let restoredError = try JSONDecoder().decode(FileUndoRecord.self, from: JSONEncoder().encode(localizedRecord))
L10n.currentLanguage = "en"
try check(restoredError.historyErrorMessage == L10n.get("history_error_missing"), "Error follows language after persistence")
L10n.currentLanguage = "de"
for (domain, code, key) in [(NSCocoaErrorDomain, 513, "history_error_permission"),
    (NSCocoaErrorDomain, 516, "history_error_exists"), (NSPOSIXErrorDomain, 28, "history_error_space"),
    ("OpenCommander.FileSafety", 1, "undo_changed"), ("Unknown", 7, "history_error_generic")] {
    try check(HistoryFailure(NSError(domain: domain, code: code)).message == L10n.get(key), "Localized error code mapping")
}
localizedRecord.lastFailure = nil
localizedRecord.lastError = "English error from an earlier installation"
var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(localizedRecord)) as! [String: Any]
oldJSON.removeValue(forKey: "lastFailure")
let legacyError = try JSONDecoder().decode(FileUndoRecord.self, from: JSONSerialization.data(withJSONObject: oldJSON))
try check(legacyError.historyErrorMessage == L10n.get("history_error_legacy"), "Old records remain readable and use German explanation")
L10n.currentLanguage = historyLanguage
print("PASS: history errors follow app language, stable codes, persistence and legacy compatibility")
try check(CommanderDuration.format(12, german: true) == "12 Sek.", "Explicit German seconds")
try check(CommanderDuration.format(120, german: true) == "2.0 Min.", "Explicit German minutes")
try check(CommanderDuration.format(7200, german: false) == "2.0 hours", "Explicit hours")
try check(CommanderDuration.format(172800, german: false) == "2.0 days", "Explicit days")
try check(CommanderDuration.format(.infinity, german: false) == "—", "Invalid duration safely displayed")
print("PASS: elapsed-time units and invalid-duration handling")

let cancelUndoFile = try write("cancel-undo.bin", String(repeating: "x", count: 200_000))
let cancelUndoRecord = FileUndoRecord(source: source, destination: cancelUndoFile, replacedBackup: nil)
var snapshotChecks = 0
do {
    try cancelUndoRecord.undo(move: false, checkCancellation: {
        snapshotChecks += 1
        if snapshotChecks == 4 { throw CocoaError(.userCancelled) }
    })
    fatalError("FAIL: cancelled undo completed")
} catch { try check((error as NSError).code == NSUserCancelledError, "Undo propagates cancellation") }
try check(snapshotChecks == 4 && SafeFileOperations.exists(cancelUndoFile) && !cancelUndoRecord.completed,
          "Cancellation during hashing preserves destination and unfinished record")
try cancelUndoRecord.undo(move: false)
try check(cancelUndoRecord.completed && !SafeFileOperations.exists(cancelUndoFile), "Cancelled undo can be retried safely")
print("PASS: cancellable blockwise undo verification, destination retained and safe retry")

#if os(macOS)
let archiveSource = fixture.appendingPathComponent("archive-source")
try fm.createDirectory(at: archiveSource.appendingPathComponent("Ordner"), withIntermediateDirectories: true)
try Data("Grüsse aus dem Archiv".utf8).write(to: archiveSource.appendingPathComponent("Ordner/Grüsse.txt"))
try Data("other".utf8).write(to: archiveSource.appendingPathComponent("Other.txt"))
for (suffix, options) in [("tar", ["-cf"]), ("tgz", ["-czf"]), ("tar.bz2", ["-cjf"]), ("tar.xz", ["-cJf"]), ("7z", ["--format=7zip", "-cf"])] {
    let archive = fixture.appendingPathComponent("native." + suffix)
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = options + [archive.path, "-C", archiveSource.path, "."]
    process.environment = ["PATH": "/usr/bin:/bin", "COPYFILE_DISABLE": "1"]
    try process.run(); process.waitUntilExit()
    try check(process.terminationStatus == 0, "Create native archive fixture: " + suffix)
    let entries = try CommanderNativeArchive.members(archive)
    try check(entries.contains { $0.path == "Ordner/Grüsse.txt" && !$0.directory }, "Unicode native archive listing: " + suffix)
    let output = fixture.appendingPathComponent("extract-" + suffix)
    try CommanderNativeArchive.extract(archive, prefixes: ["Ordner/"], to: output)
    try check(String(contentsOf: output.appendingPathComponent("Ordner/Grüsse.txt"), encoding: .utf8) == "Grüsse aus dem Archiv", "Selected folder extraction: " + suffix)
    try check(!SafeFileOperations.exists(output.appendingPathComponent("Other.txt")), "Unselected file not extracted")
    let limited = fixture.appendingPathComponent("limited-" + suffix)
    mustFail("preview byte limit") { try CommanderNativeArchive.extract(archive, to: limited, maximumBytes: 1) }
    try check(!SafeFileOperations.exists(limited), "Byte limit leaves no output")
    let cancelled = fixture.appendingPathComponent("cancel-extract-" + suffix)
    mustFail("archive cancellation") { try CommanderNativeArchive.extract(archive, to: cancelled, checkCancellation: { throw CocoaError(.userCancelled) }) }
    try check(!SafeFileOperations.exists(cancelled), "Cancelled extraction leaves no output")
}
print("PASS: native TAR/TGZ/BZ2/XZ/7z listing, Unicode, selection, byte limits and cancellation")

func unsafeTar(_ name: String, entries: [(String, UInt8, String)]) throws -> URL {
    var tar = Data()
    for (path, type, link) in entries {
        var header = [UInt8](repeating: 0, count: 512)
        func field(_ offset: Int, _ value: String) {
            let bytes = Array(value.utf8); precondition(offset + bytes.count < 512)
            header.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
        field(0, path); field(100, "0000644"); field(108, "0000000"); field(116, "0000000")
        field(124, "00000000000"); field(136, "00000000000")
        header.replaceSubrange(148..<156, with: [UInt8](repeating: 32, count: 8))
        header[156] = type; field(157, link); field(257, "ustar"); field(263, "00")
        field(148, String(format: "%06o", header.reduce(0) { $0 + Int($1) }) + "\0 ")
        tar.append(contentsOf: header)
    }
    tar.append(Data(repeating: 0, count: 1024))
    let url = fixture.appendingPathComponent(name + ".tar"); try tar.write(to: url); return url
}
for (name, entries) in [
    ("traversal", [("../outside.txt", UInt8(48), "")]),
    ("absolute", [("/outside.txt", UInt8(48), "")]),
    ("symlink", [("link", UInt8(50), "../outside")]),
    ("hardlink", [("link", UInt8(49), "outside")]),
    ("fifo", [("pipe", UInt8(54), "")]),
    ("duplicate", [("same.txt", UInt8(48), ""), ("same.txt", UInt8(48), "")]),
    ("case-collision", [("Same.txt", UInt8(48), ""), ("same.txt", UInt8(48), "")])
] {
    let archive = try unsafeTar(name, entries: entries)
    mustFail("unsafe native archive " + name) { _ = try CommanderNativeArchive.members(archive) }
    let output = fixture.appendingPathComponent("unsafe-output-" + name)
    mustFail("unsafe extraction " + name) { try CommanderNativeArchive.extract(archive, to: output) }
    try check(!SafeFileOperations.exists(output), "Unsafe archive is rejected before output creation")
}
print("PASS: native archive traversal, absolute paths, links, special files and duplicate/case-collision refusal")

// RAR5 stored fixture from libarchive v3.7.2, also used by the Linux parity tests.
// https://raw.githubusercontent.com/libarchive/libarchive/v3.7.2/libarchive/test/test_read_format_rar5_stored.rar.uu
// Copyright (c) 2003-2018 <author(s)>
// All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer in this position
//    and unchanged.
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
// NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
let rar = fixture.appendingPathComponent("stored.rar")
try Data(base64Encoded: "UmFyIRoHAQAzkrXlCgEFBgAFAQGAgAA4MAZjLAIDC50ABJ0ApIMCtEOglYAAAQ5oZWxsb3dvcmxkLnR4dAoDE34Oq1tW6Q4aaGVsbG8gbGliYXJjaGl2ZSB0ZXN0IHN1aXRlIQodd1ZRAwUEAA==")!.write(to: rar)
let rarMembers = try CommanderNativeArchive.members(rar)
try check(rarMembers.count == 1 && rarMembers[0].path == "helloworld.txt" && rarMembers[0].size == 29, "Real Linux RAR5 fixture lists identically")
let rarOutput = fixture.appendingPathComponent("rar-output")
try CommanderNativeArchive.extract(rar, to: rarOutput)
try check(contents(rarOutput.appendingPathComponent("helloworld.txt")) == "hello libarchive test suite!\n", "Real RAR5 payload extracted")
print("PASS: real Linux RAR5 fixture listing and extraction")
let onlineDisplayRecord = FileUndoRecord(source: fixture.appendingPathComponent("temporary-download"), destination: fixture.appendingPathComponent("display-target"), replacedBackup: nil)
onlineDisplayRecord.displaySource = "OneDrive online:/QA/File.txt"
let displayData = try JSONEncoder().encode(onlineDisplayRecord)
try check(JSONDecoder().decode(FileUndoRecord.self, from: displayData).displaySource == onlineDisplayRecord.displaySource, "online history display source survives restart")
var legacyDisplay = try JSONSerialization.jsonObject(with: displayData) as! [String: Any]
legacyDisplay.removeValue(forKey: "displaySource")
let legacyDisplayRecord = try JSONDecoder().decode(FileUndoRecord.self, from: JSONSerialization.data(withJSONObject: legacyDisplay))
try check(legacyDisplayRecord.displaySource == nil, "older histories remain readable")
print("PASS: logical online history source persists without changing local Undo paths; legacy records remain readable")
let dragFolder = URL(fileURLWithPath: "/synthetic/Folder")
let dragSource = URL(fileURLWithPath: "/synthetic/File.txt")
try check(!CommanderDropPolicy.accepts([(dragFolder, true)], target: dragFolder), "drop onto self refused")
try check(!CommanderDropPolicy.accepts([(dragFolder, true)], target: dragFolder.appendingPathComponent("Child")), "descendant drop refused")
try check(!CommanderDropPolicy.accepts([(dragSource, false)], target: dragSource.deletingLastPathComponent()), "same-parent no-op refused")
try check(CommanderDropPolicy.accepts([(dragFolder, true)], target: URL(fileURLWithPath: "/synthetic/FolderElse")), "name prefix is not a descendant")
try check(CommanderDropPolicy.accepts([(dragSource, false)], target: URL(fileURLWithPath: "/target")), "ordinary target accepted")
try check(!CommanderDropPolicy.accepts([], target: URL(fileURLWithPath: "/target")), "empty drag refused")
try check(!CommanderDropPolicy.accepts([(URL(fileURLWithPath: "/"), true)], target: URL(fileURLWithPath: "/target")), "root-descendant drop refused")
print("PASS: pointer-time drop policy rejects self, descendant, same-parent and empty targets without filesystem access")
#endif
