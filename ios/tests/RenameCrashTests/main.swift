import Foundation
import Darwin

guard CommandLine.arguments.count == 3,
      CommandLine.arguments[1].hasPrefix("/private/tmp/OpenCommander-RenameCrash-"),
      ["prepare", "kill-before-move", "kill-after-move", "kill-next-move", "recover", "recover-source", "recover-changed"].contains(CommandLine.arguments[2]) else {
    fatalError("isolated rename crash fixture required")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { fatalError("fixture alias") }
let fm = FileManager.default
let a = root.appendingPathComponent("A.txt"), b = root.appendingPathComponent("B.txt")
let output = root.appendingPathComponent("renamed-A.txt")
let bytes = Data("Synthetic rename restart — Grüsse.\n".utf8)
let journalRoot = root.appendingPathComponent("journal")
let idFile = root.appendingPathComponent("batch-id.txt")
let phase = CommandLine.arguments[2]
func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
if phase == "prepare" {
    try bytes.write(to: a, options: .withoutOverwriting)
    try bytes.write(to: b, options: .withoutOverwriting)
    let journal = try CommanderRenameJournal(root: journalRoot)
    try Data(journal.id.uuidString.utf8).write(to: idFile, options: .withoutOverwriting)
    print("PASS isolated batch rename source and durable journal prepared")
} else {
    let id = UUID(uuidString: try String(contentsOf: idFile, encoding: .utf8))!
    let journal = try CommanderRenameJournal(root: journalRoot, id: id)
    if phase.hasPrefix("kill-") {
        let plan = try CommanderTools.renamePlan([a, b], rule: .init(pattern: "renamed-[N][E]"))
        var calls = 0
        _ = try CommanderTools.rename(plan, cancel: FileOperationCancellation(), journal: journal, move: { from, to in
            calls += 1
            if phase == "kill-before-move" || (phase == "kill-next-move" && calls == 2) {
                Darwin.kill(getpid(), SIGKILL); _exit(99)
            }
            try SafeFileOperations.renameEntry(from, to: to)
            if phase == "kill-after-move" { Darwin.kill(getpid(), SIGKILL); _exit(99) }
        })
        fatalError("requested abrupt boundary not reached")
    } else {
        if phase == "recover-source" { try Data("foreign original occupant".utf8).write(to: a, options: .withoutOverwriting) }
        if phase == "recover-changed" { try Data("externally changed target".utf8).write(to: output) }
        let records = try journal.recover()
        if !fm.fileExists(atPath: output.path) {
            require(records.isEmpty && (try? Data(contentsOf: a)) == bytes, "unexecuted intent became destructive recovery")
            print("PASS actual SIGKILL before rename: unexecuted intent ignored, both originals intact")
        } else {
            require(records.count == 1 && (try? Data(contentsOf: b)) == bytes, "restart lost first mutation or changed unexecuted second source")
            if phase == "recover-source" || phase == "recover-changed" {
                do { try records[0].undo(move: true); fatalError("unsafe recovery accepted") } catch {}
                if phase == "recover-changed" {
                    require((try Data(contentsOf: output)) == Data("externally changed target".utf8) && !fm.fileExists(atPath: a.path), "changed target moved as original")
                    print("PASS abrupt rename restart retains original proof and refuses changed target without mutation")
                    exit(0)
                }
                require((try Data(contentsOf: a)) == Data("foreign original occupant".utf8), "recovery overwrote occupied original")
                try fm.moveItem(at: a, to: root.appendingPathComponent("foreign.saved"))
            }
            try records[0].undo(move: true)
            require((try Data(contentsOf: a)) == bytes && !fm.fileExists(atPath: output.path), "restart Undo did not restore exact original")
            require(try journal.recover().isEmpty, "already reverted rename offered destructive replay")
            print("PASS actual SIGKILL batch restart: prewritten proof recovers committed rename, explicit exact Undo, no replay")
        }
        require((try Data(contentsOf: b)) == bytes, "second original changed")
    }
}
