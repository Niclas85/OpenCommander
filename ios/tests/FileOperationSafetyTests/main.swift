import Foundation

precondition(HistoryPaging.indices(count: 0, page: 0).isEmpty)
precondition(HistoryPaging.indices(count: 1000, page: 0) == Array((950..<1000).reversed()))
precondition(HistoryPaging.indices(count: 1000, page: 19) == Array((0..<50).reversed()))
precondition(HistoryPaging.indices(count: 1000, page: Int.max) == HistoryPaging.indices(count: 1000, page: 19))
precondition(HistoryPaging.indices(count: 3, page: -1) == [2, 1, 0])
let pagedHistory = (0..<20).flatMap { HistoryPaging.indices(count: 1000, page: $0) }
precondition(pagedHistory == Array((0..<1000).reversed()) && Set(pagedHistory).count == 1000)
print("PASS bounded history pages preserve every original Undo index exactly once, newest/oldest and invalid-page bounds")
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

let emptyFolder = fixture.appendingPathComponent("new-empty-folder", isDirectory: true)
try fm.createDirectory(at: emptyFolder, withIntermediateDirectories: false)
let folderUndo = FileUndoRecord(source: emptyFolder, destination: emptyFolder, replacedBackup: nil, createdDirectory: true)
let reopenedFolderUndo = try JSONDecoder().decode(FileUndoRecord.self, from: JSONEncoder().encode(folderUndo))
try check(reopenedFolderUndo.createdDirectory == true, "Created-folder identity survives restart")
try reopenedFolderUndo.undo(move: false)
try check(!fm.fileExists(atPath: emptyFolder.path), "Undo removes the visible created folder")
let changedFolder = fixture.appendingPathComponent("new-changed-folder", isDirectory: true)
try fm.createDirectory(at: changedFolder, withIntermediateDirectories: false)
let changedUndo = FileUndoRecord(source: changedFolder, destination: changedFolder, replacedBackup: nil, createdDirectory: true)
let addedContent = changedFolder.appendingPathComponent("later.txt")
try Data("added afterwards".utf8).write(to: addedContent)
mustFail("Created folder changed before Undo") { try changedUndo.undo(move: false) }
try check(try contents(addedContent) == "added afterwards", "Later folder contents remain untouched")
print("PASS: created-folder Undo survives restart and refuses later content without removing it")

let source = try write("source.txt", "new contents")
let providerFile = try write("provider-proof.txt", "provider bytes")
try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: providerFile.path)
let providerAttributes = try fm.attributesOfItem(atPath: providerFile.path)
let strictProof = try SafeFileOperations.snapshot(providerFile)
let providerProof = try SafeFileOperations.snapshot(providerFile, providerIdentity: true)
let oldProviderFile = fixture.appendingPathComponent("retained-provider-proof.txt")
try fm.moveItem(at: providerFile, to: oldProviderFile)
try Data("provider bytes".utf8).write(to: providerFile)
try fm.setAttributes([.modificationDate: providerAttributes[.modificationDate]!,
                      .posixPermissions: providerAttributes[.posixPermissions]!], ofItemAtPath: providerFile.path)
try check(SafeFileOperations.snapshot(providerFile) != strictProof, "Local proof still rejects a replacement inode")
try check(SafeFileOperations.snapshot(providerFile, providerIdentity: true) == providerProof, "Provider proof accepts identical bytes and metadata after inode refresh")
try Data("changed bytes!".utf8).write(to: providerFile)
try fm.setAttributes([.modificationDate: providerAttributes[.modificationDate]!], ofItemAtPath: providerFile.path)
try check(SafeFileOperations.snapshot(providerFile, providerIdentity: true) != providerProof, "Provider proof rejects changed bytes even with restored timestamp")
try check(SafeFileOperations.providerLocation(fixture.appendingPathComponent("Library/CloudStorage/Account/file"), home: fixture), "Known provider subtree accepted")
try check(!SafeFileOperations.providerLocation(fixture.appendingPathComponent("Library/CloudStorage-other/file"), home: fixture), "Provider name-prefix collision refused")
let racingFile = try write("racing-proof.txt", String(repeating: "a", count: 131072))
var replacedDuringRead = false
mustFail("provider changes during verification") {
    _ = try SafeFileOperations.snapshot(racingFile, providerIdentity: true, progress: { bytes in
        if bytes > 0 && !replacedDuringRead {
            replacedDuringRead = true
            try! fm.moveItem(at: racingFile, to: fixture.appendingPathComponent("retained-racing-proof"))
            try! Data("replacement".utf8).write(to: racingFile)
        }
    })
}
print("PASS: provider inode refresh preserves content/metadata proofs; local replacement and in-read mutation refused")
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

let fullSizeReport = BoundedFolderSize.report(at: folder)
try check(fullSizeReport.complete && fullSizeReport.bytes == scannedBytes, "interactive size excludes symlink targets")
let limitedSizeReport = BoundedFolderSize.report(at: folder, maximumEntries: 1)
try check(!limitedSizeReport.complete && limitedSizeReport.limit == "folder_size_entry_limit" && limitedSizeReport.entries == 1, "partial entry-limit report")
let timedSizeReport = BoundedFolderSize.report(at: folder, timeout: -1)
try check(!timedSizeReport.complete && timedSizeReport.limit == "folder_size_time_limit" && timedSizeReport.entries == 0, "monotonic time limit before scanning")
let linkedRoot = fixture.appendingPathComponent("size-root-link")
try fm.createSymbolicLink(atPath: linkedRoot.path, withDestinationPath: folder.path)
try check(!BoundedFolderSize.report(at: linkedRoot).complete, "folder properties must not follow root symlink")
try check(BoundedFolderSize.report(at: sizeFixture).bytes == 11, "interactive size excludes private recovery directories")
let unreadableSize = fixture.appendingPathComponent("size-read-errors")
try fm.createDirectory(at: unreadableSize, withIntermediateDirectories: false)
let deniedSize = unreadableSize.appendingPathComponent("denied")
try fm.createDirectory(at: deniedSize, withIntermediateDirectories: false)
try Data("hidden".utf8).write(to: deniedSize.appendingPathComponent("secret.txt"))
try Data("kept".utf8).write(to: unreadableSize.appendingPathComponent("readable.txt"))
try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: deniedSize.path)
let unreadableReport = BoundedFolderSize.report(at: unreadableSize)
try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedSize.path)
try check(!unreadableReport.complete && unreadableReport.errors > 0 && unreadableReport.bytes == 4, "partial read failure retains known bytes")
try check(unreadableReport.summary.contains("4"), "partial report includes known size")
print("PASS: interactive folder size reports partial bytes, read errors, entry/time limits and refuses root symlinks")

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
let archivePathRoot = fixture.appendingPathComponent("archive-existing-root", isDirectory: true)
try fm.createDirectory(at: archivePathRoot, withIntermediateDirectories: false)
for spelling in [archivePathRoot, URL(fileURLWithPath: archivePathRoot.path + "/", isDirectory: true)] {
    let child = try SafeArchiveLimits.outputURL(for: "Ordner/Grüsse.txt", in: spelling)
    try check(child.lastPathComponent == "Grüsse.txt" && child.deletingLastPathComponent().lastPathComponent == "Ordner", "Existing archive root and missing Unicode child stay confined")
    for unsafe in ["../Escape", "/Escape", "a/../Escape", "a//Escape", "./Escape", "a\\Escape", "file:Escape"] {
        mustFail("archive output path " + unsafe) { _ = try SafeArchiveLimits.outputURL(for: unsafe, in: spelling) }
    }
}
print("PASS: archive path confinement for existing directory roots, missing Unicode children and unsafe path refusal")
let archiveSource = fixture.appendingPathComponent("archive-source")
try fm.createDirectory(at: archiveSource.appendingPathComponent("Ordner"), withIntermediateDirectories: true)
try Data("Grüsse aus dem Archiv".utf8).write(to: archiveSource.appendingPathComponent("Ordner/Grüsse.txt"))
try Data("other".utf8).write(to: archiveSource.appendingPathComponent("Other.txt"))
for (suffix, options) in [("zip", ["--format=zip", "-cf"]), ("tar", ["-cf"]), ("tgz", ["-czf"]), ("tar.bz2", ["-cjf"]), ("tar.xz", ["-cJf"]), ("7z", ["--format=7zip", "-cf"])] {
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
    let originalArchive = try Data(contentsOf: archive)
    let singleOutput = fixture.appendingPathComponent("single-" + suffix)
    try CommanderNativeArchive.extract(archive, prefixes: ["Ordner/Grüsse.txt"], to: singleOutput, maximumBytes: 256 * 1024 * 1024)
    try check(Data(contentsOf: singleOutput.appendingPathComponent("Ordner/Grüsse.txt")) == Data("Grüsse aus dem Archiv".utf8), "Virtual file drag extraction content")
    try check(Data(contentsOf: archive) == originalArchive, "Read-only archive export preserved original bytes")
    let limited = fixture.appendingPathComponent("limited-" + suffix)
    mustFail("preview byte limit") { try CommanderNativeArchive.extract(archive, to: limited, maximumBytes: 1) }
    try check(!SafeFileOperations.exists(limited), "Byte limit leaves no output")
    let cancelled = fixture.appendingPathComponent("cancel-extract-" + suffix)
    mustFail("archive cancellation") { try CommanderNativeArchive.extract(archive, to: cancelled, checkCancellation: { throw CocoaError(.userCancelled) }) }
    try check(!SafeFileOperations.exists(cancelled), "Cancelled extraction leaves no output")
}
print("PASS: native TAR/TGZ/BZ2/XZ/7z listing, Unicode, selection, byte limits and cancellation")

#if OPENCOMMANDER_ZSTD
// Independently compressed with upstream zstd v1.5.7; no external executable
// is used by the decoder. Includes a Unicode file and an empty directory.
let zstdArchive = fixture.appendingPathComponent("native.tar.zst")
let zstdBytes = Data(base64Encoded: "KLUv/WQAJ10RAOZVTDQgTbUNQNEdgCAUBsIKDIA08/jSXSMJzSu6jPMXtm88KGGyoTlUsjdXLmtglAkQgHlVQigFOgBAAEAALIC7ITQl0hRdwJzgAAUA9KZWzAfr0I0mY7mzpRfreLPLB523T+fTo3zRNfzn7u6yY5zuzrZaFxuxtNPhi6Zb1Cpzq3aYNUv36E5h64XWR0YlFSQYuJBgw+U5geBKWdSqHo69Wt1cF20VhyKAGMDMGCaViqSBeQIzP+Y/o/nupIzwKdyralhabJbOQQUUATI9GJSOHnrrgWa6JB+Kg4E0NZAWzd5Ls9ZwMD0YE0nBBOkZIRdn5DNy3vzBrWZ44PBgHX3gWvVaHKqrJ4OhrCRfxgcdwXty/pQuo/j/0AJz6fXe/f30f3mz2yqGWejQsQ5Le/de8ZwMW6gBHilVQQUpKEjKhTHQApGRQITKAxKgUCgOgVCERDiSoCJAEIKEACGACCIOQQIiHElICH6ZCwfl2VBIOHxCY+L1B0B+FCj/4PseAxANf7hSAJgCcCYMABzZgB8sNIB8LwM6h27agFcN8Oswip/2JWnE7va7ghDIDVApFrg1w68LrnjhB1RVm8uBis9ffL6Wp2FAdAZEhQUCFdQ1QBfHog/IKs6YA5xgaFUILB/gbQVz5I9BWW13fjQpBuAvsldgwGzvAA/5FviKKTpAOqhuuMWqWIKuL6+HI98BaxepiXI9V2w1QBerTpjoFnyWJ9oK8LsV4RxLAWcwEkE=")!
try zstdBytes.write(to: zstdArchive)
let zstdEntries = try CommanderNativeArchive.members(zstdArchive)
try check(zstdEntries.contains { $0.path == "Ordner/Grüsse.txt" && !$0.directory }, "Bundled Zstandard Unicode listing")
try check(zstdEntries.contains { $0.path == "Ordner/Empty/" && $0.directory }, "Zstandard empty folder retained")
let zstdOutput = fixture.appendingPathComponent("zstd-output")
try CommanderNativeArchive.extract(zstdArchive, prefixes: ["Ordner/"], to: zstdOutput)
try check(try Data(contentsOf: zstdOutput.appendingPathComponent("Ordner/Grüsse.txt")) == Data("Archive content, Grüße.\n".utf8), "Zstandard exact selected extraction")
try check(try Data(contentsOf: zstdArchive) == zstdBytes, "Zstandard source unchanged")
let disguisedZstd = fixture.appendingPathComponent("zstandard-disguised.tar")
try zstdBytes.write(to: disguisedZstd)
try check(try CommanderNativeArchive.members(disguisedZstd) == zstdEntries, "Zstandard detected by content, not extension")
print("PASS: bundled TAR.ZST listing/extraction, Unicode, empty folders and disguised filename without external helper")

func rawZstdFrame(_ data: Data) -> Data {
    precondition(data.count <= 128 * 1024)
    var result = Data([0x28, 0xB5, 0x2F, 0xFD, 0xA0])
    var length = UInt32(data.count).littleEndian
    withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
    let block = UInt32(data.count << 3) | 1 // final raw block
    result.append(contentsOf: [UInt8(block & 255), UInt8((block >> 8) & 255), UInt8((block >> 16) & 255)])
    result.append(data)
    return result
}
let zstdStream = fixture.appendingPathComponent("concatenated.zst")
let zstdPayload = Data((0..<120_000).map { UInt8($0 % 251) })
try (rawZstdFrame(zstdPayload) + rawZstdFrame(Data("tail".utf8))).write(to: zstdStream)
let decodedZstd = try CommanderNativeArchive.decodedZstandard(zstdStream)!
try check(try Data(contentsOf: decodedZstd) == zstdPayload + Data("tail".utf8), "Zstandard streaming chunks and concatenated frames exact")
try fm.removeItem(at: decodedZstd)
func zstdStaging() throws -> Set<String> {
    Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("OpenCommander-Zstd-") && $0.hasSuffix(".tar") })
}
let zstdStagingBefore = try zstdStaging()
mustFail("Zstandard decompression output limit") { _ = try CommanderNativeArchive.decodedZstandard(zstdStream, maximumBytes: 1024) }
var zstdCancelChecks = 0
mustFail("Zstandard in-flight cancellation") {
    _ = try CommanderNativeArchive.decodedZstandard(zstdStream, checkCancellation: {
        zstdCancelChecks += 1
        if zstdCancelChecks == 5 { throw CocoaError(.userCancelled) }
    })
}
try check(zstdCancelChecks == 5, "Zstandard cancellation reached a streaming boundary")
let truncatedZstd = fixture.appendingPathComponent("truncated.zst")
try zstdBytes.dropLast().write(to: truncatedZstd)
mustFail("Truncated Zstandard") { _ = try CommanderNativeArchive.members(truncatedZstd) }
let hugeWindowZstd = fixture.appendingPathComponent("huge-window.zst")
try Data([0x28, 0xB5, 0x2F, 0xFD, 0xA0, 0, 0, 0, 8, 1, 0, 0]).write(to: hugeWindowZstd)
mustFail("Zstandard 128-MiB history window") { _ = try CommanderNativeArchive.decodedZstandard(hugeWindowZstd) }
try check(try zstdStaging() == zstdStagingBefore, "Zstandard failure/cancel staging removed")
print("PASS: Zstandard bounded streaming, concatenated frames, truncation, output/window limits, cancellation and cleanup")
#endif

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

// Provider wrappers and low-space failures must preserve actionable diagnostics.
try check(MobileStorageIssue.key(for: NSError(domain: "ProviderWrapper", code: 99, userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC)])) == "mobile_error_space", "Nested ENOSPC classification")
try check(MobileStorageIssue.key(for: CocoaError(.fileReadNoPermission)) == "mobile_error_permission", "Permission recovery classification")
try check(MobileStorageIssue.key(for: POSIXError(.EROFS)) == "mobile_error_readonly", "Read-only recovery classification")
try check(MobileStorageIssue.key(for: CocoaError(.fileReadNoSuchFile)) == "mobile_error_missing", "Missing folder classification")
try check(MobileStorageIssue.key(for: URLError(.notConnectedToInternet)) == "mobile_error_network", "Offline classification")
let limitedSource = try write("limited-source", "new complete contents")
let limitedDestination = try write("limited-destination", "original destination")
for injected in [POSIXError(.ENOSPC) as Error, CocoaError(.userCancelled) as Error] {
    mustFail("injected low storage or interrupted copy") {
        _ = try SafeFileOperations.copyReplacing(source: limitedSource, destination: limitedDestination, replace: true, copy: { _, stage in
            try Data("partial".utf8).write(to: stage)
            throw injected
        })
    }
    try check(contents(limitedDestination) == "original destination", "Failed copy preserves prior destination")
    try check(contents(limitedSource) == "new complete contents", "Failed copy preserves source")
}
let token = FileOperationCancellation()
token.cancel()
mustFail("cancelled copy") { try token.copy(limitedSource, fixture.appendingPathComponent("cancelled-result")) }
token.reset()
let retried = fixture.appendingPathComponent("retry-result")
try token.copy(limitedSource, retried)
try check(contents(retried) == "new complete contents", "Retry succeeds after cancellation")
print("PASS: mobile provider diagnostics, low-storage/cancel rollback, untouched source and successful retry")

// Exercise the real Darwin copyfile callback after data has reached staging.
// A bounded, non-sparse source prevents an instant sparse-file copy from racing the observer.
let streamingSource = fixture.appendingPathComponent("streaming-source")
try Data("source-start".utf8).write(to: streamingSource)
let streamingHandle = try FileHandle(forWritingTo: streamingSource)
let streamingBlock = Data(repeating: 0x35, count: 1024 * 1024)
try streamingHandle.seek(toOffset: 12)
for _ in 0..<256 { try streamingHandle.write(contentsOf: streamingBlock) }
try streamingHandle.seek(toOffset: 256 * 1024 * 1024 + 12)
try streamingHandle.write(contentsOf: Data([0x7f]))
try streamingHandle.close()
let streamingToken = FileOperationCancellation()
let retainedStagingBefore = Set(try FileManager.default.contentsOfDirectory(atPath: fixture.path).filter { $0.hasPrefix(".OpenCommanderTransfer-") })
let observedProgress = DispatchSemaphore(value: 0)
let observerFinished = DispatchSemaphore(value: 0)
do {
    _ = try SafeFileOperations.copyReplacing(source: streamingSource, destination: limitedDestination, replace: true, copy: { source, stage in
        DispatchQueue.global(qos: .userInitiated).async {
            defer { observerFinished.signal() }
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let size = (try? FileManager.default.attributesOfItem(atPath: stage.path)[.size]) as? NSNumber,
                   size.int64Value >= 64 * 1024 {
                    observedProgress.signal()
                    streamingToken.cancel()
                    return
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        try streamingToken.copy(source, stage)
    })
    fatalError("In-flight copy was not cancelled")
} catch {
    try check(MobileStorageIssue.key(for: error) == "history_error_cancelled", "In-flight cancellation reports cancellation")
}
try check(observerFinished.wait(timeout: .now() + 12) == .success, "Copy observer finished")
try check(observedProgress.wait(timeout: .now()) == .success, "Cancellation happened after staging data existed")
try check(contents(limitedDestination) == "original destination", "In-flight cancel preserves existing destination")
try check(Set(FileManager.default.contentsOfDirectory(atPath: fixture.path).filter { $0.hasPrefix(".OpenCommanderTransfer-") }) == retainedStagingBefore, "Cancelled copy removes its staging and preserves previous recovery files")
let streamingReader = try FileHandle(forReadingFrom: streamingSource)
try check(streamingReader.read(upToCount: 12) == Data("source-start".utf8), "Cancelled source prefix unchanged")
try streamingReader.seek(toOffset: 256 * 1024 * 1024 + 12)
try check(streamingReader.read(upToCount: 1) == Data([0x7f]), "Cancelled source suffix unchanged")
try streamingReader.close()
print("PASS: real in-flight copy cancellation after staging writes, original destination/source preserved, staging removed")
