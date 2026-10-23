import Foundation
import AppKit
import Darwin

struct ProbeIdentity: Codable, Equatable {
    let device: UInt64, inode: UInt64, size: Int64
    static func read(_ url: URL) throws -> Self {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return Self(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: info.st_size)
    }
}
struct Probe: Codable {
    let variant: String, original: String, called: String, bookmark: String, identity: ProbeIdentity, text: String
}
guard CommandLine.arguments.count == 3, let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("root and create|resolve required") }
defer { free(physical) }
let root = String(cString: physical), fm = FileManager.default
guard root.hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      URL(fileURLWithPath: root).deletingLastPathComponent().path == "/private/tmp" else { fatalError("isolated fixture only") }
let full = CommandLine.arguments[2].hasSuffix("-full")
let staged = CommandLine.arguments[2].hasSuffix("-staged")
let fixture = URL(fileURLWithPath: root + (full ? "/TrashBookmarkFullProbe" : staged ? "/TrashBookmarkStagedProbe" : "/TrashBookmarkProbe"))
let manifest = fixture.appendingPathComponent("planned.json")
switch CommandLine.arguments[2] {
case "create", "create-full", "create-staged":
    guard !fm.fileExists(atPath: fixture.path) else { fatalError("never overwrite a probe") }
    try fm.createDirectory(at: fixture, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let sources = fixture.appendingPathComponent("Sources"), staging = fixture.appendingPathComponent("Staging")
    try fm.createDirectory(at: sources, withIntermediateDirectories: false)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var probes: [Probe] = [], observations: [[String: String]] = []
    let variants = full ? ["FullBookmarkPathReused", "BookmarkFilePathReused"] : staged ? ["StagedOriginalPathReused"] : ["FoundationOriginal", "FoundationStaged", "WorkspaceOriginal", "OriginalPathReused"]
    for variant in variants {
        let id = UUID().uuidString
        let original = sources.appendingPathComponent("OpenCommander-" + variant + "-" + id)
        try fm.createDirectory(at: original, withIntermediateDirectories: false)
        let text = "Own Trash/bookmark probe " + variant + " " + id + "\n"
        try Data(text.utf8).write(to: original.appendingPathComponent("Probe.txt"), options: .withoutOverwriting)
        let called: URL
        if variant == "FoundationStaged" || variant == "StagedOriginalPathReused" {
            let privateArea = staging.appendingPathComponent(".OpenCommanderUndo-" + id)
            try fm.createDirectory(at: privateArea, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            called = privateArea.appendingPathComponent(original.lastPathComponent)
            try fm.moveItem(at: original, to: called)
        } else { called = original }
        let bookmark = fixture.appendingPathComponent(id + ".bookmark")
        let options: URL.BookmarkCreationOptions = variant == "FullBookmarkPathReused" ? [] : variant == "BookmarkFilePathReused" ? .suitableForBookmarkFile : .minimalBookmark
        let data = try called.bookmarkData(options: options, includingResourceValuesForKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey], relativeTo: nil)
        try data.write(to: bookmark, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: bookmark); try handle.synchronize(); try handle.close()
        probes.append(Probe(variant: variant, original: original.path, called: called.path, bookmark: bookmark.path,
                            identity: try ProbeIdentity.read(called), text: text))
        // Recovery manifest deliberately has NO post-mutation destination URL.
        try JSONEncoder().encode(probes).write(to: manifest, options: .atomic)
        let destination: URL
        if variant == "WorkspaceOriginal" {
            var result: URL?, failure: Error?, done = false
            NSWorkspace.shared.recycle([called]) { urls, error in result = urls[called]; failure = error; done = true }
            let deadline = Date().addingTimeInterval(30)
            while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            if let failure { throw failure }
            guard done, let result else { fatalError("workspace recycling did not finish") }
            destination = result
        } else {
            var result: NSURL?
            try fm.trashItem(at: called, resultingItemURL: &result)
            guard let result = result as URL? else { fatalError("Trash URL missing") }
            destination = result
        }
        guard try ProbeIdentity.read(destination) == probes.last!.identity else { fatalError("recycling changed identity") }
        observations.append(["variant": variant, "trash": destination.path, "original": original.path, "called": called.path])
        try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
            .write(to: fixture.appendingPathComponent("observations.json"), options: .atomic)
        if variant.contains("PathReused") {
            try fm.createDirectory(at: original, withIntermediateDirectories: false)
            try Data("New unrelated source entry; must remain untouched\n".utf8)
                .write(to: original.appendingPathComponent("New.txt"), options: .withoutOverwriting)
        }
        print("TRASH_PROBE", variant, destination.path)
    }
    print("READY own probes; bookmarks persisted before Trash, independent resolver must not read observations.json")
case "resolve", "resolve-full", "resolve-staged":
    let probes = try JSONDecoder().decode([Probe].self, from: Data(contentsOf: manifest))
    guard probes.count == (full ? 2 : staged ? 1 : 4) else { fatalError("incomplete probe creation") }
    var failures = 0
    for probe in probes {
        do {
            guard probe.bookmark.hasPrefix(fixture.path + "/") else { fatalError("unsafe bookmark path") }
            var stale = false
            let resolved = try URL(resolvingBookmarkData: Data(contentsOf: URL(fileURLWithPath: probe.bookmark)),
                                   options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
            let actualIdentity = try ProbeIdentity.read(resolved)
            print("CANDIDATE", probe.variant, "inode=", actualIdentity.inode, "expected=", probe.identity.inode, resolved.path)
            guard actualIdentity == probe.identity else { throw CocoaError(.fileReadCorruptFile) }
            let text = try String(contentsOf: resolved.appendingPathComponent("Probe.txt"), encoding: .utf8)
            guard text == probe.text else { throw CocoaError(.fileReadCorruptFile) }
            if probe.variant.contains("PathReused") {
                let new = try String(contentsOfFile: probe.original + "/New.txt", encoding: .utf8)
                guard new == "New unrelated source entry; must remain untouched\n" else { throw CocoaError(.fileReadCorruptFile) }
            }
            print("PASS independent pre-mutation bookmark", probe.variant, "stale=", stale, "resolved=", resolved.path)
        } catch {
            failures += 1
            print("FAIL independent pre-mutation bookmark", probe.variant, (error as NSError).domain, (error as NSError).code)
        }
    }
    guard failures == 0 else { exit(2) }
    print("PASS no recovery destination or Trash scan used; selected identities/content exact, replacement source untouched")
case "restore", "restore-full", "restore-staged":
    let probes = try JSONDecoder().decode([Probe].self, from: Data(contentsOf: manifest))
    let observations = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("observations.json"))) as! [[String: String]]
    let preserved = fixture.appendingPathComponent("PreservedReplacements")
    if !fm.fileExists(atPath: preserved.path) { try fm.createDirectory(at: preserved, withIntermediateDirectories: false) }
    for probe in probes {
        guard probe.original.hasPrefix(fixture.path + "/Sources/OpenCommander-"),
              probe.called.hasPrefix(fixture.path + "/"),
              let observation = observations.first(where: { $0["variant"] == probe.variant }),
              let trash = observation["trash"],
              trash.hasPrefix(fm.homeDirectoryForCurrentUser.path + "/.Trash/OpenCommander-" + probe.variant + "-") else { fatalError("unsafe restoration manifest") }
        let candidates = Set([probe.original, probe.called, trash]).compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            return (try? ProbeIdentity.read(url)) == probe.identity ? url : nil
        }
        guard candidates.count == 1 else { fatalError("selected own probe missing or ambiguous") }
        let source = candidates[0], original = URL(fileURLWithPath: probe.original)
        let text = try String(contentsOf: source.appendingPathComponent("Probe.txt"), encoding: .utf8)
        guard text == probe.text else { fatalError("probe contents changed") }
        if source.path != original.path {
            if fm.fileExists(atPath: original.path) {
                let new = try String(contentsOf: original.appendingPathComponent("New.txt"), encoding: .utf8)
                guard new == "New unrelated source entry; must remain untouched\n" else { fatalError("unknown source occupant") }
                let target = preserved.appendingPathComponent(probe.variant)
                guard !fm.fileExists(atPath: target.path) else { fatalError("never overwrite retained replacement") }
                try fm.moveItem(at: original, to: target)
            }
            try fm.moveItem(at: source, to: original)
        }
        guard try ProbeIdentity.read(original) == probe.identity else { fatalError("restoration changed identity") }
        print("RESTORED verified own probe", probe.variant)
    }
    print("PASS only verified own probes restored, synthetic replacements preserved; no deletion or Trash emptying")
case "create-finder":
    let source = fixture.appendingPathComponent("Sources/OpenCommander-FinderAction-6B4B1BCD-55AD-4E7C-A498-95E6F04B2C31")
    guard fm.fileExists(atPath: manifest.path), !fm.fileExists(atPath: source.path) else { fatalError("existing probe required, never overwrite control") }
    try fm.createDirectory(at: source, withIntermediateDirectories: false)
    try Data("Own Finder-created Trash control; restore exactly\n".utf8).write(to: source.appendingPathComponent("Probe.txt"), options: .withoutOverwriting)
    print("FINDER_CONTROL", source.path)
default: fatalError("unsupported probe mode")
}
