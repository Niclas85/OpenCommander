import Foundation
import Darwin
setbuf(stdout, nil)

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func refuses(_ action: () throws -> Void) {
    do { try action(); fatalError("Expected refusal") } catch { }
}
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("OpenCommander-ToolsTests-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: root) }
let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
for url in [a, b, a.appendingPathComponent("sub"), b.appendingPathComponent("sub")] { try fm.createDirectory(at: url, withIntermediateDirectories: false) }
func file(_ directory: URL, _ name: String, _ content: String) throws -> URL {
    let url = directory.appendingPathComponent(name); try Data(content.utf8).write(to: url); return url
}
let source = try file(a, "Grüsse.txt", "same")
_ = try file(b, "Grüsse.txt", "same")
_ = try file(a, "sub/diff.txt", "aaaa")
_ = try file(b, "sub/diff.txt", "bbbb")
_ = try file(a, "only.txt", "left")
_ = try file(b, "other.txt", "right")
_ = try file(a, ".hidden.txt", "hidden")
try fm.createSymbolicLink(at: a.appendingPathComponent("external"), withDestinationURL: b)
let cancel = FileOperationCancellation()
check(CommanderTools.searchDirectory("relative/path") == nil, "Relative search paths refused")
check(CommanderTools.searchDirectory("") == nil, "Empty search path refused")
check(CommanderTools.searchDirectory("https://example.com") == nil, "Web URL is not a filesystem search path")
check(CommanderTools.searchDirectory("~/Downloads")?.path.hasSuffix("/Downloads") == true, "Home path expands")
check(CommanderTools.searchDirectory(a.path)?.path == a.path, "Active pane absolute path preserved")
let specialPath = a.appendingPathComponent("Grüsse 日本語 ;$() `quote` # % trailing ", isDirectory: true)
check(CommanderTools.searchDirectory(specialPath.path)?.path == specialPath.path, "Literal shell punctuation and trailing spaces preserved")
check(CommanderTools.searchDirectory(specialPath.absoluteString)?.path == specialPath.path, "File URL roundtrip preserves exact Unicode and punctuation")
check(CommanderTools.searchDirectory("file://localhost/tmp/with%20space")?.path == "/tmp/with space", "Localhost file URL")
check(CommanderTools.searchDirectory("/DocumentsExact")?.path == "/DocumentsExact", "No iOS Documents alias on desktop input")
for invalid in ["file://remote.example/tmp/test", "file:///tmp/%00bad", "file:///tmp/test?query=1", "file:///tmp/test#fragment", "file://user@localhost/tmp/test", "sftp://localhost/tmp/test"] {
    check(CommanderTools.searchDirectory(invalid) == nil, "Invalid local URL refused: \(invalid)")
}
let changedPath = CommanderTools.searchDirectory(b.path)!
let changedResults = try CommanderTools.search(changedPath, query: "other.txt", hidden: false, cancel: cancel)
check(changedResults.urls.map { $0.resolvingSymlinksInPath().path } == [b.appendingPathComponent("other.txt").resolvingSymlinksInPath().path], "Changed dialog path searches chosen folder")
let search = try CommanderTools.search(a, query: "*.TXT", hidden: false, cancel: cancel)
check(search.urls.count == 3, "Recursive wildcard, case insensitive, hidden omitted, no link traversal")
let unicode = try CommanderTools.search(a, query: "GRÜ", hidden: false, cancel: cancel)
check(unicode.urls.count == 1, "Unicode substring")
let sensitiveGlob = try CommanderTools.search(a, query: "*.TXT", hidden: false, caseSensitive: true, cancel: cancel)
check(sensitiveGlob.urls.isEmpty, "Case-sensitive wildcard rejects differently cased extension")
let sensitiveMismatch = try CommanderTools.search(a, query: "GRÜ", hidden: false, caseSensitive: true, cancel: cancel)
check(sensitiveMismatch.urls.isEmpty, "Case-sensitive substring rejects uppercase mismatch")
let sensitiveUnicode = try CommanderTools.search(a, query: "Gru\u{0308}", hidden: false, caseSensitive: true, cancel: cancel)
check(sensitiveUnicode.urls.count == 1, "Case-sensitive substring preserves canonical Unicode matching")
let sensitiveMatch = try CommanderTools.search(a, query: "Gr?ss*.txt", hidden: false, caseSensitive: true, cancel: cancel)
check(sensitiveMatch.urls.count == 1, "Case-sensitive glob matches exact case with both wildcards")
let hidden = try CommanderTools.search(a, query: "hidden", hidden: true, cancel: cancel)
check(hidden.urls.count == 1, "Hidden opt-in")
refuses { _ = try CommanderTools.scan(a, hidden: true, cancel: cancel, limit: 1) }
cancel.cancel(); refuses { _ = try CommanderTools.search(a, query: "*", hidden: false, cancel: cancel) }; cancel.reset()
print("PASS recursive search, globs, Unicode, hidden setting, symlinks, bounds and cancellation")
let comparison = try CommanderTools.compare(a, b, hidden: false, cancel: cancel)
check(comparison.rows.first { $0.path == "Grüsse.txt" }?.state == .equal, "Content equality")
check(comparison.rows.first { $0.path == "sub/diff.txt" }?.state == .different, "Same-size different bytes detected")
check(comparison.rows.first { $0.path == "only.txt" }?.state == .leftOnly, "Only left")
check(comparison.rows.first { $0.path == "other.txt" }?.state == .rightOnly, "Only right")
check(comparison.rows.first { $0.path == "external" }?.state == .leftOnly, "Link not traversed")
check(comparison.warnings.isEmpty, "No hidden scan failures")
print("PASS content comparison, equal, changed, only-left/right and link safety")
let another = try file(a, "second.txt", "second")
let plan = try CommanderTools.renamePlan([source, another], rule: .init(pattern: "Foto-[C]-[N][E]", start: 7, digits: 2))
check(plan.map { $0.destination.lastPathComponent } == ["Foto-07-Grüsse.txt", "Foto-08-second.txt"], "Preview tokens/counter")
check(fm.fileExists(atPath: source.path), "Preview never renames")
let records = try CommanderTools.rename(plan, cancel: cancel)
check(records.count == 2 && !fm.fileExists(atPath: source.path), "Batch rename executes")
for record in records.reversed() { try record.undo(move: true) }
check(fm.fileExists(atPath: source.path) && fm.fileExists(atPath: another.path), "History undo restores originals")
let rollbackPlan = try CommanderTools.renamePlan([source, another], rule: .init(pattern: "rollback-[C][E]"))
var moves = 0
refuses {
    _ = try CommanderTools.rename(rollbackPlan, cancel: cancel, move: { source, destination in
        moves += 1
        if moves == 2 { throw CocoaError(.fileWriteNoPermission) }
        try fm.moveItem(at: source, to: destination)
    })
}
check(moves == 2 && fm.fileExists(atPath: source.path) && fm.fileExists(atPath: another.path), "Failed second rename rolls back first")
refuses {
    _ = try CommanderTools.rename(rollbackPlan, cancel: cancel, move: { source, destination in
        try fm.moveItem(at: source, to: destination); cancel.cancel()
    })
}
check(fm.fileExists(atPath: source.path) && fm.fileExists(atPath: another.path), "Cancellation rolls back completed rename")
cancel.reset()
let race = try CommanderTools.renamePlan([source, another], rule: .init(pattern: "race-[C][E]"))
try Data("unrelated".utf8).write(to: race[1].destination)
refuses { _ = try CommanderTools.rename(race, cancel: cancel) }
check(fm.fileExists(atPath: source.path), "New collision detected before mutating first file")
refuses { _ = try CommanderTools.renamePlan([source, another], rule: .init(pattern: "same.txt")) }
refuses { _ = try CommanderTools.renamePlan([source], rule: .init(pattern: "only.txt")) }
refuses { _ = try CommanderTools.renamePlan([source], rule: .init(pattern: "../escape")) }
refuses { _ = try CommanderTools.renamePlan([source], rule: .init(pattern: ".")) }
refuses { _ = try CommanderTools.renamePlan([source], rule: .init(start: -1)) }
refuses { _ = try CommanderTools.renamePlan([source], rule: .init(start: Int.max)) }
let literal = try file(a, "[C].txt", "literal")
let literalPlan = try CommanderTools.renamePlan([literal], rule: .init())
check(literalPlan[0].destination.lastPathComponent == "[C].txt", "Tokens within original names stay literal")
let stale = try CommanderTools.renamePlan([source], rule: .init(pattern: "changed[E]"))
try Data("edited".utf8).write(to: source)
refuses { _ = try CommanderTools.rename(stale, cancel: cancel) }
check(fm.fileExists(atPath: source.path), "Stale preview preserves source")
cancel.cancel(); refuses { _ = try CommanderTools.rename(try CommanderTools.renamePlan([another], rule: .init(pattern: "cancel[E]")), cancel: cancel) }
check(fm.fileExists(atPath: another.path), "Cancelled rename preserves source")
print("PASS rename preview, counters, undo, collisions, invalid names, literal tokens, stale previews and cancellation")

cancel.reset()
let partialA = try file(a, "partial-a.txt", "first original")
let partialB = try file(a, "partial-b.txt", "second original")
let partialPlan = try CommanderTools.renamePlan([partialA, partialB], rule: .init(pattern: "partial-result-[C][E]"))
var partialMoves = 0
var survivors: [FileUndoRecord] = []
do {
    _ = try CommanderTools.rename(partialPlan, cancel: cancel, move: { from, to in
        partialMoves += 1
        if partialMoves == 2 {
            // A concurrent writer occupies the original name after step one.
            try Data("foreign original name".utf8).write(to: partialA)
            throw CocoaError(.fileWriteNoPermission)
        }
        try SafeFileOperations.renameEntry(from, to: to)
    })
    fatalError("Expected partial rollback failure")
} catch let failure as CommanderTools.RenameFailure {
    check((failure.cause as NSError).code == NSFileWriteNoPermissionError, "Partial failure lost underlying reason")
    survivors = failure.remaining
}
check(survivors.count == 1 && !survivors[0].completed && survivors[0].historyErrorMessage != nil, "Partial rollback lost failure/history record")
check((try? String(contentsOf: partialA, encoding: .utf8)) == "foreign original name", "Rollback overwrote foreign original")
let reopenedSurvivor = try JSONDecoder().decode(FileUndoRecord.self, from: JSONEncoder().encode(survivors[0]))
refuses { try reopenedSurvivor.undo(move: true) }
check(fm.fileExists(atPath: partialPlan[0].destination.path) && fm.fileExists(atPath: partialB.path), "Failed Undo lost remaining files")
try fm.removeItem(at: partialA) // Only the synthetic collision injected above.
try reopenedSurvivor.undo(move: true)
check((try? String(contentsOf: partialA, encoding: .utf8)) == "first original", "Persisted partial Undo lost first original")
check((try? String(contentsOf: partialB, encoding: .utf8)) == "second original", "Partial failure changed unexecuted source")

let changedPlan = try CommanderTools.renamePlan([partialA, partialB], rule: .init(pattern: "changed-result-[C][E]"))
var changedMoves = 0
do {
    _ = try CommanderTools.rename(changedPlan, cancel: cancel, move: { from, to in
        changedMoves += 1
        if changedMoves == 2 {
            try Data("changed destination".utf8).write(to: changedPlan[0].destination)
            throw CocoaError(.fileWriteNoPermission)
        }
        try SafeFileOperations.renameEntry(from, to: to)
    })
    fatalError("Expected changed-destination rollback refusal")
} catch let failure as CommanderTools.RenameFailure {
    check(failure.remaining.count == 1, "Changed destination lost preserved proof")
    refuses { try failure.remaining[0].undo(move: true) }
    check((try? String(contentsOf: changedPlan[0].destination, encoding: .utf8)) == "changed destination", "Undo moved externally changed destination")
    check(!fm.fileExists(atPath: partialA.path), "Unsafe rollback published changed content as original")
}
print("PASS partial rename rollback keeps serialized History/Undo proof; occupied source and changed destination are preserved")

do {
    let language = L10n.currentLanguage
    defer { L10n.currentLanguage = language }
    let deniedA = try file(a, "denied-compare.txt", "permission fixture")
    _ = try file(b, "denied-compare.txt", "permission fixture")
    try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: deniedA.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: deniedA.path) }
    for code in ["de", "en"] {
        L10n.currentLanguage = code
        let denied = try CommanderTools.compare(a, b, hidden: false, cancel: cancel)
        let row = denied.rows.first { $0.path == "denied-compare.txt" }!
        check(row.state == .unreadable && row.detail == L10n.get("history_error_permission"), "Comparison lost localized unreadable detail")
        do {
            _ = try CommanderTools.renamePlan([partialB], rule: .init(pattern: "../escape"))
            fatalError("Invalid preview accepted")
        } catch {
            check(error.localizedDescription == L10n.get("tools_invalid_name", "../escape"), "Invalid plan lost localized reason")
        }
        do {
            _ = try CommanderTools.scan(a, hidden: true, cancel: cancel, limit: 1)
            fatalError("Traversal limit ignored")
        } catch {
            check(error.localizedDescription == L10n.get("tools_limit", "1"), "Traversal limit lost localized reason")
        }
    }
    print("PASS DE/EN real unreadable-file comparison, invalid-name preview and bounded-scan diagnostic reasons")
}

do {
    let journalSource = try file(a, "journal-source.txt", "journal admission original")
    let plan = try CommanderTools.renamePlan([journalSource], rule: .init(pattern: "journal-target[E]"))
    let journal = try CommanderRenameJournal(root: root.appendingPathComponent("rename-journals"))
    try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: journal.directory.path)
    refuses { _ = try CommanderTools.rename(plan, cancel: cancel, journal: journal) }
    check(fm.fileExists(atPath: journalSource.path) && !fm.fileExists(atPath: plan[0].destination.path), "Journal write refusal still renamed source")
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: journal.directory.path)
    let entry = try journal.prepare(plan[0])
    let roundTripEntry = try JSONDecoder().decode(CommanderRenameJournal.Entry.self, from: JSONEncoder().encode(entry))
    check(roundTripEntry.record.renameBatchID == journal.id, "Batch ownership did not survive journal encoding")
    check(roundTripEntry.record.renameEntryID == entry.id, "Entry ownership did not survive journal encoding")
    check(roundTripEntry.record.matchesRenameProof(roundTripEntry.expected), "Prepared rename proof did not survive journal encoding")
    _ = try file(a, "journal-target.txt", "foreign target before mutation")
    let unexecuted = try journal.recover()
    check(unexecuted.isEmpty, "Unexecuted intent adopted foreign target")
    let entryURL = journal.directory.appendingPathComponent(entry.id.uuidString + ".json")
    var tampered = try JSONSerialization.jsonObject(with: Data(contentsOf: entryURL)) as! [String: Any]
    tampered["expected"] = Data(repeating: 0, count: 32).base64EncodedString()
    try JSONSerialization.data(withJSONObject: tampered).write(to: entryURL, options: .atomic)
    refuses { _ = try journal.recover() }
    check((try? String(contentsOf: journalSource, encoding: .utf8)) == "journal admission original", "Corrupt intent changed source")
    check((try? String(contentsOf: plan[0].destination, encoding: .utf8)) == "foreign target before mutation", "Corrupt intent changed foreign target")
    print("PASS rename journal admission fails before mutation; unexecuted intent preserves foreign target; mismatched proof refused")
}

do {
    let receiptRoot = root.appendingPathComponent("receipt-journals")
    let receiptSource = try file(a, "receipt-source.txt", "receipt exact original")
    let receiptPlan = try CommanderTools.renamePlan([receiptSource], rule: .init(pattern: "receipt-result[E]"))
    let journal = try CommanderRenameJournal(root: receiptRoot)
    let records = try CommanderTools.rename(receiptPlan, cancel: cancel, journal: journal)
    let recovery = try CommanderRenameJournal.recovery(root: receiptRoot)
    let unrelated: OperationType = .copy(files: [])
    let once = try CommanderRenameJournal.merge([unrelated], recovery: recovery)
    let twice = try CommanderRenameJournal.merge(once, recovery: recovery)
    check(once.count == 2 && twice.count == 2, "Startup reimport duplicated rename History or lost unrelated entry")
    var forged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(records[0])) as! [String: Any]
    forged["source"] = a.appendingPathComponent("foreign-name.txt").absoluteString
    let wrong = try JSONDecoder().decode(FileUndoRecord.self, from: JSONSerialization.data(withJSONObject: forged))
    refuses { _ = try CommanderRenameJournal.merge([.move(files: [wrong])], recovery: recovery) }
    try records[0].undo(move: true, didRestore: { try journal.finish(records[0]) })
    let finished = try CommanderRenameJournal.recovery(root: receiptRoot)
    let reconciled = try CommanderRenameJournal.merge(twice, recovery: finished)
    check(finished.records.isEmpty && reconciled.count == 1, "Completed receipt left stale/duplicate History")
    try SafeFileOperations.renameEntry(receiptSource, to: receiptPlan[0].destination)
    let afterExternalRename = try CommanderRenameJournal.recovery(root: receiptRoot)
    check(afterExternalRename.records.isEmpty, "Old completed intent adopted later external rename")
    for index in 1...2 {
        let source = try file(a, "group-source-\(index).txt", "independent batch \(index)")
        let plan = try CommanderTools.renamePlan([source], rule: .init(pattern: "group-result-\(index)[E]"))
        let batch = try CommanderRenameJournal(root: receiptRoot)
        _ = try CommanderTools.rename(plan, cancel: cancel, journal: batch)
    }
    let multiple = try CommanderRenameJournal.recovery(root: receiptRoot)
    let groups = try CommanderRenameJournal.merge([], recovery: multiple)
    check(groups.count == 2, "Independent recovered batches collapsed into one Undo action")
    for operation in groups {
        if case .move(let files) = operation { check(files.count == 1, "Recovered batch grouping lost boundaries") }
        else { fatalError("Unexpected recovered operation") }
    }
    print("PASS startup History deduplicates stable rename IDs, preserves unrelated entries, rejects forged ownership and retires completed receipts")
}
do {
    let receiptSource = try file(a, "receipt-retry.txt", "original before receipt failure")
    let receiptPlan = try CommanderTools.renamePlan([receiptSource], rule: .init(pattern: "receipt-retry-result[E]"))
    let journal = try CommanderRenameJournal(root: root.appendingPathComponent("receipt-retry-journals"))
    let record = try CommanderTools.rename(receiptPlan, cancel: cancel, journal: journal)[0]
    try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: journal.directory.path)
    refuses { try record.undo(move: true, didRestore: { try journal.finish(record) }) }
    check(!record.completed && fm.fileExists(atPath: receiptSource.path) && !fm.fileExists(atPath: receiptPlan[0].destination.path), "Receipt failure hid incomplete acknowledgement or lost restored data")
    let reloaded = try JSONDecoder().decode(FileUndoRecord.self, from: JSONEncoder().encode(record))
    try Data("external edit after data restoration".utf8).write(to: receiptSource)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: journal.directory.path)
    try reloaded.undo(move: true, didRestore: { try journal.finish(reloaded) })
    check(reloaded.completed && (try? String(contentsOf: receiptSource, encoding: .utf8)) == "external edit after data restoration", "Receipt retry replayed filesystem mutation")
    let recovery = try journal.recover()
    check(recovery.isEmpty, "Receipt retry not durable")
    print("PASS failed completion receipt preserves retry state across serialization; retry acknowledges only and preserves later source edits")
}
