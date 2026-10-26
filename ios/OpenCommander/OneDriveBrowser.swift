#if targetEnvironment(macCatalyst)
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

private final class OneDriveCell: UITableViewCell {
    var activateEntry: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard let activateEntry else { return false }
        activateEntry(); return true
    }
}
@MainActor final class OneDriveSelection {
    private static var native: [String: OneDriveSelection] = [:]
    static func resolve(_ item: UIDragItem) -> OneDriveSelection? {
        if let selection = item.localObject as? OneDriveSelection { return selection }
        return item.itemProvider.registeredTypeIdentifiers.compactMap { native[$0] }.first
    }
    func registerNative() -> String {
        let token = "org.opencommander.online-drag." + UUID().uuidString.lowercased()
        Self.native[token] = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { Self.native.removeValue(forKey: token) }
        return token
    }
    static func nativeSelection(_ token: String) -> OneDriveSelection? { native[token] }
    let browser: OneDriveBrowser
    let items: [OneDriveItem]
    let generation: UUID
    var parentID: String?
    init(browser: OneDriveBrowser, items: [OneDriveItem], generation: UUID) {
        self.browser = browser; self.items = items; self.generation = generation
        self.parentID = browser.currentParentID
    }
}

/// Embedded in a commander pane; remote items never become local FileEntry paths.
@MainActor final class OneDriveBrowser: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let nativeDragSourceID = UUID().uuidString
    private var nativeExportCount = 0
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureNativeDrag()
    }
    private func configureNativeDrag() {
        CommanderDragDiagnostics.event("native drag bridge available \(DesktopBridge.shared != nil)")
        DesktopBridge.shared?.registerOnlineDragSource(nativeDragSourceID, items: { [weak self] point in
            CommanderDragDiagnostics.event("native online hit test \(point)")
            guard let self, self.view.window?.isKeyWindow == true, !self.busy, self.authenticated,
                  self.presentedViewController == nil, self.commander?.operationInProgress != true else { return [] }
            let point = CGPoint(x: point.x * self.view.window!.bounds.width, y: point.y * self.view.window!.bounds.height)
            for list in [self.tableView, self.treeView] {
                let local = list.convert(point, from: self.view.window)
                guard CommanderVisibleHit.contains(local, in: list), let index = list.indexPathForRow(at: local) else { continue }
                let items: [OneDriveItem]
                if list === self.treeView {
                    guard self.treeRows.indices.contains(index.row), let item = self.treeRows[index.row].last else { return [] }
                    items = [item]
                } else {
                    guard self.visibleItems.indices.contains(index.row) else { return [] }
                    let item = self.visibleItems[index.row]
                    items = self.selectedIDs.contains(item.id) ? self.selectedItems : [item]
                }
                CommanderDragDiagnostics.event("native online drag snapshot \(items.count)")
                return items.map { item in
                    let selection = OneDriveSelection(browser: self, items: [item], generation: self.generation)
                    if list === self.treeView { selection.parentID = self.treeRows[index.row].dropLast().last?.id }
                    return ["token": selection.registerNative(), "name": item.name,
                            "type": (item.isFolder ? UTType.folder : (UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data)).identifier]
                }
            }
            return []
        }, write: { token, destination, completion in
            guard let selection = OneDriveSelection.nativeSelection(token), let item = selection.items.first else {
                completion(FileDropTransfer.error("The online drag expired. Please drag the file again.")); return
            }
            Task { @MainActor in
                do {
                    let browser = selection.browser
                    guard selection.generation == browser.generation, let client = browser.client else { throw CloudConnection.failure("cloud_config_changed") }
                    browser.nativeExportCount += 1
                    browser.loadingIndicator.startAnimating()
                    defer {
                        browser.nativeExportCount -= 1
                        if browser.nativeExportCount == 0 { browser.loadingIndicator.stopAnimating() }
                    }
                    let downloaded = try await client.downloadTree(item)
                    defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }
                    guard selection.generation == browser.generation else { throw CloudConnection.failure("cloud_config_changed") }
                    try await Task.detached {
                        // Finder supplies a destination for this promise; never
                        // overwrite an unrelated existing file on our own.
                        try FileManager.default.copyItem(at: downloaded, to: destination)
                    }.value
                    CommanderDragDiagnostics.event("native online promise completed")
                    completion(nil)
                } catch { completion(error as NSError) }
            }
        })
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        DesktopBridge.shared?.removeOnlineDragSource(nativeDragSourceID)
    }
    let tableView = CommanderSelectionTableView(frame: .zero, style: .plain)
    private let treeView = CommanderTreeTableView(frame: .zero, style: .plain)
    private var refreshControl: UIRefreshControl?
    private let pathLabel = UILabel()
    private let countLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var directoryMenu: CommanderDirectoryMenu?
    private weak var treeColumn: UIStackView?
    private weak var filesColumn: UIStackView?
    private weak var treeHeader: UILabel?
    private weak var filesHeader: UILabel?
    private weak var accentLine: UIView?
    private weak var treeDivider: UIView?
    private weak var closeButton: UIButton?
    private var sortButtons: [UIButton] = []
    private let remoteProfile: RemoteConnection?
    private let cloudProfile: CloudConnection?
    private var isOneDrive: Bool { remoteProfile == nil && cloudProfile == nil }
    private var locationTitle: String { cloudProfile?.name ?? remoteProfile?.name ?? "OneDrive online" }
    private var deleteTitle: String { cloudProfile != nil ? L10n.get("cloud_recovery_delete") : isOneDrive ? L10n.get("move_to_trash") : L10n.get("remote_delete") }
    private func onlineLocation(_ name: String? = nil) -> String {
        locationTitle + ":/" + (folders.map(\.name) + (name.map { [$0] } ?? [])).joined(separator: "/")
    }
    private func destinationLocation(_ parent: String?, name: String) async throws -> String {
        guard let client else { return locationTitle + ":/" + name }
        var components = [name], cursor = parent, seen = Set<String>()
        while let id = cursor {
            guard seen.insert(id).inserted, seen.count <= 100 else { throw OneDriveFailure.message("Invalid OneDrive folder hierarchy.") }
            let item = try await client.metadata(id)
            if item.root != nil { break }
            components.insert(item.name, at: 0)
            cursor = item.parentReference?.id
        }
        return locationTitle + ":/" + components.joined(separator: "/")
    }
    private func record(_ action: String, source: String, destination: String, undo: CloudUndoPayload? = nil, error: Error? = nil) {
        let keys = ["undo", "rename", "rename_button", "move_to_trash", "cloud_recovery_delete", "delete", "zip", "extract_archive", "duplicate", "remote_recovery", "folder", "copy", "move"]
        let actionKey = keys.first { L10n.get($0) == action }
        var record = CloudOperationRecord(action: action, source: source, destination: destination, actionKey: actionKey)
        record.identifier = UUID().uuidString; record.undo = undo
        if let error {
            record.status = error is CancellationError ? "cancelled" : "failed"; record.failure = HistoryFailure(error)
            let key = (error as NSError).localizedDescription
            if L10n.strings.values.contains(where: { $0[key] != nil }) { record.failureKey = key }
            if case OneDriveFailure.temporarilyUnavailable(let status, _) = error {
                record.failureKey = status == 429 ? "cloud_rate_limited" : "cloud_temporarily_unavailable"
            } else if case OneDriveFailure.nameConflict = error {
                record.failureKey = "history_error_exists"
            } else if (error as NSError).domain == NSURLErrorDomain, (error as NSError).code == NSURLErrorTimedOut {
                record.failureKey = "cloud_timeout"
            }
        }
        commander?.operationHistory.append(.cloud(record: record))
    }
    private let filterField = CommanderFilterField()
    private let filterStatus = UILabel()
    private let clearFilterButton = UIButton(type: .system)
    private var visibleItems: [OneDriveItem] = []
    private var treeRows: [[OneDriveItem]] = [[]]
    private var treeChildren: [String: [OneDriveItem]] = [:]
    private var expanded: Set<String> = ["root"]
    private var backHistory: [[OneDriveItem]] = []
    private var forwardHistory: [[OneDriveItem]] = []
    private var selectedIDs = Set<String>()
    private var selectionAnchor: String?
    private var generation = UUID()
    static var clipboard: (selection: OneDriveSelection, move: Bool)?
    weak var commander: ViewController?
    private var previewURLs: [URL] = []
    private var retainedDragBytes: Int64 = 0
    private var openAfterExport = false
    private var activeOperationPaths: (source: String, destination: String)?
    private func batch(_ selected: [OneDriveItem], action: String,
                       operation: (OneDriveItem) async throws -> Void) async throws {
        let failures = try await OnlineBatch.run(selected, operation: { item in
            self.activeOperationPaths = (self.onlineLocation(item.name), self.onlineLocation())
            try await operation(item)
        }, failed: { item, error in
            self.record(L10n.get(action), source: self.onlineLocation(item.name),
                destination: self.activeOperationPaths?.destination ?? self.onlineLocation(), error: error)
        })
        if failures > 0 {
            let notice = text("\(failures) Eintrag/Einträge fehlgeschlagen. Die übrigen Einträge wurden bearbeitet. Details stehen in der Historie.",
                              "\(failures) item(s) failed. The remaining items were processed. See History for details.")
            completionNotice = [completionNotice, notice].compactMap { $0 }.joined(separator: "\n")
        }
        // A listing refresh failure is not a failure of the last completed item.
        activeOperationPaths = (onlineLocation(), onlineLocation())
    }
    private var recoveryOffered = false
    private func offerUploadRecovery() {
        guard !recoveryOffered, authenticated, let client, presentedViewController == nil,
              view.window != nil, commander?.operationInProgress != true else { return }
        do {
            let jobs = try PendingCloudUpload.pending().filter { $0.endpoint == client.clientID }
            let downloads = try PendingCloudDownload.pending().filter { $0.endpoint == client.clientID }
            let replacements = try PendingCloudReplacement.pending().filter { $0.upload.endpoint == client.clientID }
            let moves = try PendingOnlineMove.pending().filter { $0.endpoint == client.clientID }
            let localMoves = try PendingLocalCloudMove.pending().filter { $0.uploaded.endpoint == client.clientID }
            let crossMoves = try PendingCrossCloudMove.pending().filter { $0.endpoint == client.clientID }
            guard !jobs.isEmpty || !downloads.isEmpty || !replacements.isEmpty || !moves.isEmpty || !localMoves.isEmpty || !crossMoves.isEmpty else { return }
            recoveryOffered = true
            let count = jobs.count + downloads.count + replacements.count + moves.count + localMoves.count + crossMoves.count
            let alert = UIAlertController(title: text("Cloud-Übertragung fortsetzen", "Resume cloud transfer"),
                message: text("\(count) Übertragungen sind noch offen. Bestätigte Ersetzungen und Verschiebungen werden nach erneuter Prüfung fortgesetzt; Vorgängerversionen und verschobene Quellen bleiben wiederherstellbar. Andere Ziele werden nicht überschrieben.", "\(count) transfers remain. Confirmed replacements and moves resume after verification; previous versions and moved sources remain recoverable. Other destinations are not overwritten."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: text("Später", "Later"), style: .cancel))
            alert.addAction(UIAlertAction(title: text("Fortsetzen", "Resume"), style: .default) { [weak self] _ in
                guard let self else { return }
                self.run(transfer: true, historyAction: "copy") {
                    var failed = 0
                    for job in crossMoves {
                        try Task.checkCancellation()
                        self.activeOperationPaths = (job.sourceLocation, job.destinationLocation)
                        do {
                            let sourceClient = try PersistentOnlineUndo.client(job.sourceEndpoint)
                            self.observeTransfer(sourceClient)
                            defer { self.stopObservingTransfer(sourceClient) }
                            let undo = try await PendingCrossCloudMove.resume(job, source: sourceClient, target: client)
                            self.record(L10n.get("move"), source: job.sourceLocation, destination: job.destinationLocation, undo: undo)
                            try PendingCrossCloudMove.finish(job)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failed += 1
                            self.record(L10n.get("move"), source: job.sourceLocation, destination: job.destinationLocation, error: error)
                        }
                    }
                    for job in jobs {
                        try Task.checkCancellation()
                        let action = L10n.get(job.moveIntent == nil ? (job.actionKey ?? "copy") : "move")
                        self.activeOperationPaths = (job.source, job.name)
                        do {
                            var parent = job.parent
                            if let id = parent { parent = try await client.restoreReference(id, path: job.parentPath).id }
                            let destination = try await self.destinationLocation(parent, name: job.name)
                            self.activeOperationPaths = (job.source, destination)
                            if let intent = job.moveIntent,
                               self.commander?.allowTransferPaths(writing: [URL(fileURLWithPath: intent.original)]) == false { throw CancellationError() }
                            let undo: CloudUndoPayload?
                            if job.moveIntent == nil { undo = try await PendingCloudUpload.resume(job, client: client) }
                            else { undo = try await PendingCloudUpload.resumeMove(job, client: client) }
                            self.record(action, source: job.source, destination: destination, undo: undo)
                            try PendingCloudUpload.finish(job)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failed += 1
#if DEBUG && targetEnvironment(macCatalyst)
                            if Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests", let root = AppDelegate.macUITestRoot {
                                // Only our own message enum, never URLSession userInfo
                                // (which may contain a preauthenticated capability URL).
                                let diagnostic: String
                                if case OneDriveFailure.message(let message) = error { diagnostic = message }
                                else if case OneDriveFailure.temporarilyUnavailable(let status, let delay) = error { diagnostic = "HTTP \(status); retry-after \(delay)" }
                                else { diagnostic = "\((error as NSError).domain):\((error as NSError).code)" }
                                try? Data(diagnostic.utf8).write(to: root.appendingPathComponent("CloudRecoveryFailure.txt"), options: .atomic)
                            }
#endif
                            self.record(action, source: job.source,
                                destination: self.activeOperationPaths?.destination ?? job.name, error: error)
                        }
                    }
                    for job in replacements {
                        try Task.checkCancellation()
                        self.activeOperationPaths = (job.upload.source, job.upload.name)
                        do {
                            if let intent = job.moveIntent {
                                let undo = try await PendingCloudReplacement.resumeMove(job, client: client)
                                self.record(L10n.get("move"), source: intent.original, destination: intent.destination, undo: undo)
                                try PendingCloudReplacement.finish(job)
                                continue
                            }
                            let result = try await PendingCloudReplacement.resume(job, client: client)
                            let destination = try await self.destinationLocation(result.parent, name: result.name)
                            self.record(L10n.get("copy"), source: job.upload.source, destination: destination,
                                undo: try PersistentOnlineUndo.replacement(client, record: result, account: job.upload.account))
                            try PendingCloudReplacement.finish(job)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failed += 1
                            self.record(L10n.get(job.moveIntent == nil ? "copy" : "move"), source: job.upload.source, destination: job.upload.name, error: error)
                        }
                    }
                    for job in localMoves {
                        try Task.checkCancellation()
                        self.activeOperationPaths = (job.original, job.destinationLocation)
                        do {
                            let undo = try await PendingLocalCloudMove.resume(job, client: client)
                            self.record(L10n.get("move"), source: job.original, destination: job.destinationLocation, undo: undo)
                            try PendingLocalCloudMove.finish(job)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failed += 1
                            self.record(L10n.get("move"), source: job.original, destination: job.destinationLocation, error: error)
                        }
                    }
                    for job in moves {
                        try Task.checkCancellation()
                        self.activeOperationPaths = (job.sourceLocation, job.destinationLocation)
                        do {
                            let undo = try await PendingOnlineMove.resume(job, client: client)
                            self.record(L10n.get("move"), source: job.sourceLocation, destination: job.destinationLocation, undo: undo)
                            try PendingOnlineMove.finish(job)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failed += 1
                            self.record(L10n.get("move"), source: job.sourceLocation, destination: job.destinationLocation, error: error)
                        }
                    }
                    for job in downloads {
                        try Task.checkCancellation()
                        self.activeOperationPaths = (job.name, job.directory)
                        do {
                            guard try await client.accountIdentity() == job.account else { throw CloudConnection.failure("cloud_undo_account") }
                            if job.move == true, PendingCloudDownload.hasMovePublication(job) {
                                guard self.commander?.allowTransferPaths(writing: [try PendingCloudDownload.destination(job)]) != false else { throw CancellationError() }
                                let undo = try await PendingCloudDownload.completeMove(job, client: client, sourceLocation: self.onlineLocation(job.name))
                                self.record(L10n.get("move"), source: self.onlineLocation(job.name), destination: job.directory, undo: undo)
                                try PendingCloudDownload.finish(job)
                                continue
                            }
                            let item = try await client.restoreReference(job.itemID, path: job.itemPath)
                            let selection = OneDriveSelection(browser: self, items: [item], generation: self.generation)
                            selection.parentID = item.parentReference?.id
                            try await self.exportOnlineItems(selection, to: PendingCloudDownload.destination(job), move: job.move == true)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            failed += 1
                            self.record(L10n.get(job.move == true ? "move" : "copy"), source: job.name, destination: job.directory, error: error)
                        }
                    }
                    if failed > 0 {
                        self.completionNotice = self.text("\(failed) Übertragung(en) konnten nicht fortgesetzt werden. Details stehen in der Historie; die Zwischenstände bleiben erhalten. Aktualisieren bietet einen erneuten Versuch an.",
                            "\(failed) transfer(s) could not resume. See History for details; checkpoints are retained. Refresh to retry.")
                    }
                    try await self.load()
                }
            })
            present(alert, animated: true)
        } catch { self.error(HistoryFailure.presentation(error)) }
    }
    private enum ConflictChoice { case keepBoth, replace, skip, cancel }
    private struct DestinationPlan { let name: String; var replacing: OneDriveItem? = nil }
    private var conflictPrompt: (UIAlertController, CheckedContinuation<ConflictChoice, Never>)?
    private func finishConflict(_ choice: ConflictChoice) {
        guard let (alert, continuation) = conflictPrompt else { return }
        conflictPrompt = nil
        alert.dismiss(animated: false) { continuation.resume(returning: choice) }
    }
    private func conflictChoice(name: String, alternative: String, canReplace: Bool) async throws -> ConflictChoice {
        let choice: ConflictChoice = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, self.view.window != nil else { continuation.resume(returning: .cancel); return }
                let explanation = canReplace
                    ? self.text("Ersetzen bewahrt die Vorgängerversion zur Wiederherstellung; Ordner werden vollständig ersetzt, nicht zusammengeführt.", "Replace retains the previous version for recovery; folders are replaced completely, not merged.")
                    : self.text("Bei diesem Verschiebevorgang ist Ersetzen noch nicht verfügbar. Beide behalten verändert das vorhandene Ziel nicht.", "Replace is not yet available for this move. Keep Both leaves the existing destination unchanged.")
                let alert = UIAlertController(title: self.text("Name bereits vorhanden", "Name already exists"),
                    message: self.text("‚\(name)‘ ist im Zielordner bereits vorhanden. Beide behalten erstellt ‚\(alternative)‘. ",
                        "‘\(name)’ already exists in the destination. Keep Both creates ‘\(alternative)’. ") + explanation, preferredStyle: .alert)
                if canReplace { alert.addAction(UIAlertAction(title: L10n.get("replace"), style: .destructive) { [weak self] _ in self?.finishConflict(.replace) }) }
                alert.addAction(UIAlertAction(title: self.text("Beide behalten", "Keep Both"), style: .default) { [weak self] _ in self?.finishConflict(.keepBoth) })
                alert.addAction(UIAlertAction(title: self.text("Überspringen", "Skip"), style: .default) { [weak self] _ in self?.finishConflict(.skip) })
                alert.addAction(UIAlertAction(title: L10n.get("cancel"), style: .cancel) { [weak self] _ in self?.finishConflict(.cancel) })
                self.conflictPrompt = (alert, continuation)
                self.present(alert, animated: true)
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.finishConflict(.cancel) } })
        try Task.checkCancellation()
        if case .cancel = choice { throw CancellationError() }
        return choice
    }
    private func destinationPlan(_ name: String, folder: Bool, parent: String?, excluding: String? = nil,
                                 allowReplacement: Bool) async throws -> DestinationPlan? {
        guard let client else { throw CancellationError() }
        let listing = try await client.children(of: parent).filter { $0.id != excluding }
        let alternative = OneDriveConflictNames.available(name, folder: folder, existing: listing.map(\.name))
        guard alternative != name else { return DestinationPlan(name: name) }
        let existing = listing.first { OneDriveConflictNames.key($0.name) == OneDriveConflictNames.key(name) }
        switch try await conflictChoice(name: name, alternative: alternative, canReplace: allowReplacement && existing != nil) {
        case .keepBoth: return DestinationPlan(name: alternative)
        case .replace: guard let existing else { throw RemoteConnection.failure("remote_changed") }; return DestinationPlan(name: existing.name, replacing: existing)
        case .skip: return nil
        case .cancel: throw CancellationError()
        }
    }
    func undoOnlineOperation() {
        guard let client, !busy else {
            commander?.updateGlobalStatus(L10n.get("undo_empty")); return
        }
        commander?.undoLatestCloudOperation(endpoint: client.clientID)
    }
    private var sortField = 0
    private var ascending = true
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let upButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    private var palette: ViewController.ThemeColors { ViewController.ThemeColors(darkMode: traitCollection.userInterfaceStyle == .dark) }
    private func key(_ path: [OneDriveItem]) -> String { path.last?.id ?? "root" }
    var hasSelection: Bool { !selectedIDs.isEmpty && !busy }
    var hasSelectedArchives: Bool { selectedItems.contains { !$0.isFolder && ($0.name as NSString).pathExtension.lowercased() == "zip" } }
    var currentParentID: String? { folders.last?.id }
    var connectionIdentifier: String? { client?.clientID }
    private var selectedItems: [OneDriveItem] { visibleItems.filter { selectedIDs.contains($0.id) } }
    var selection: OneDriveSelection { OneDriveSelection(browser: self, items: selectedItems, generation: generation) }
    func commanderTool(_ mode: CommanderToolsController.Mode, left: OneDriveBrowser?, right: OneDriveBrowser?, leftURL: URL, rightURL: URL) -> CommanderToolsController? {
        guard !busy, left?.busy != true, right?.busy != true, let client, mode != .rename || !selectedItems.isEmpty else { return nil }
        let initialFolders = folders, selected = selectedItems
        let base = remoteProfile?.root ?? "/"
        let path = (base == "/" ? "" : base) + "/" + folders.map(\.name).joined(separator: "/")
        let hidden = UserDefaults.standard.bool(forKey: "show_hidden_files")
        let controller = CommanderToolsController(mode: mode, root: URL(fileURLWithPath: path), other: rightURL, selected: [], hidden: hidden)
        controller.displayRoot = mode == .compare ? (left?.onlineLocation() ?? leftURL.path) : onlineLocation()
        controller.displayOther = right?.onlineLocation() ?? rightURL.path
        var renamePlan: [CommanderOnlineTools.Rename] = []
        var results: [String: CommanderOnlineTools.Entry] = [:]
        controller.onlineRun = { [weak self, weak controller] query, matchCase, searchPath, fields in
            guard let self else { throw CancellationError() }
            self.busy = true; self.updateNavigation()
            defer { self.busy = false; self.updateNavigation() }
            switch mode {
            case .search:
                guard base == "/" || searchPath == base || searchPath.hasPrefix(base + "/") else { throw RemoteConnection.failure("remote_invalid") }
                let relative = base == "/" ? searchPath : String(searchPath.dropFirst(base.count))
                let parents = try await CommanderOnlineTools.resolve(relative.isEmpty ? "/" : relative, client: client)
                let entries = try await CommanderOnlineTools.scan(client, ancestors: parents, hidden: hidden) { count in
                    controller?.report("\(count) " + self.text("Einträge geprüft …", "entries checked …"))
                }
                results = [:]
                return try entries.filter { try CommanderOnlineTools.matches($0.item.name, query: query, caseSensitive: matchCase) }.map { entry in
                    let url = URL(string: "opencommander-online://result/" + UUID().uuidString)!
                    results[url.absoluteString] = entry
                    let fullPath = (base == "/" ? "" : base) + "/" + (entry.ancestors.map(\.name) + [entry.item.name]).joined(separator: "/")
                    return .init(title: entry.item.name, detail: self.locationTitle + ":" + fullPath, url: url)
                }
            case .compare:
                @MainActor func content(_ browser: OneDriveBrowser?, _ local: URL) async throws -> [String: String] {
                    if let browser, let service = browser.client {
                        return try await CommanderOnlineTools.content(service, ancestors: browser.folders, hidden: hidden) { done, total in
                            controller?.report(browser.locationTitle + ": \(done)/\(total)")
                        }
                    }
                    var snapshot = try await RemoteContent.snapshotAsync(local, hidden: hidden); snapshot.removeValue(forKey: "")
                    return snapshot
                }
                let a = try await content(left, leftURL), b = try await content(right, rightURL)
                try Task.checkCancellation()
                return Set(a.keys).union(b.keys).sorted().compactMap { path in
                    if a[path] == "directory" && b[path] == "directory" { return nil }
                    let label = a[path] == nil ? self.text("Nur rechts", "Right only") : b[path] == nil ? self.text("Nur links", "Left only") : a[path] == b[path] ? self.text("Gleich", "Equal") : self.text("Unterschiedlich", "Different")
                    return .init(title: label + " · " + path, detail: "", url: nil)
                }
            case .rename:
                renamePlan = try await CommanderOnlineTools.renamePlan(client, parent: initialFolders.last?.id, selected: selected, fields: fields)
                return renamePlan.map { .init(title: $0.item.name + " → " + $0.name, detail: self.onlineLocation(), url: nil) }
            }
        }
        if mode == .rename {
            controller.onlineApply = { [weak self] in
                guard let self else { throw CancellationError() }
                let plan = renamePlan; renamePlan = []
                self.busy = true; self.updateNavigation()
                defer {
                    self.busy = false; self.treeChildren = [:]; self.updateNavigation()
                    Task { try? await self.load() }
                }
                let account = try await client.accountIdentity()
                var proofs: [String: [String: String]] = [:], parentPaths: [String: String] = [:]
                for row in plan {
                    proofs[row.item.id] = try await CommanderOnlineTools.contentSnapshot(client, item: row.item)
                    parentPaths[row.item.id] = try client.persistentPath(row.item.parentReference?.id)
                }
                return try await CommanderOnlineTools.rename(client, plan: plan) { row in
                    do {
                        guard try await client.accountIdentity() == account else { throw CloudConnection.failure("cloud_undo_account") }
                        let renamed = try await client.metadata(row.item.id)
                        let undo = try PersistentOnlineUndo.relocation(client, current: renamed, content: proofs[row.item.id] ?? [:], parent: row.item.parentReference?.id,
                            parentPath: parentPaths[row.item.id], name: row.item.name, account: account)
                        self.record(L10n.get("rename"), source: self.onlineLocation(row.item.name), destination: self.onlineLocation(row.name), undo: undo)
                    } catch {
                        self.record(L10n.get("rename"), source: self.onlineLocation(row.item.name), destination: self.onlineLocation(row.name))
                        self.record(L10n.get("remote_recovery"), source: self.onlineLocation(row.item.name), destination: self.onlineLocation(row.name), error: error)
                    }
                }
            }
        }
        controller.onOpen = { [weak self] url in
            guard let self, let entry = results[url.absoluteString] else { return }
            self.navigate(entry.item.isFolder ? entry.ancestors + [entry.item] : entry.ancestors)
        }
        return controller
    }
    func selectAllOnline() { selectedIDs = Set(visibleItems.map(\.id)); tableView.reloadData(); updateNavigation(); onStateChanged?() }
    func renameOnlineSelection() { if let item = selectedItems.first, selectedItems.count == 1, !busy { namePrompt(item: item) } }
    func deleteOnlineSelection() {
        let selected = selectedItems
        guard !selected.isEmpty, !busy else { return }
        let deleteTitle = self.deleteTitle
        let alert = UIAlertController(title: deleteTitle, message: selected.map(\.name).joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: deleteTitle, style: .destructive) { [weak self] _ in
            self?.run(transfer: true, historyAction: "delete") { [weak self] in
                guard let self, let client = self.client else { return }
                try await self.batch(selected, action: "delete") { item in
                    try Task.checkCancellation()
                    let undo = try await self.recycleWithUndo(client, item: item)
                    self.record(deleteTitle, source: self.onlineLocation(item.name), destination: client.moveBackupLocation ?? (self.isOneDrive ? "OneDrive Papierkorb / Recycle bin" : L10n.get("remote_deleted")), undo: undo)
                    self.rememberRecovery(client, source: self.onlineLocation(item.name))
                }
                try await self.load()
            }
        })
        alert.addAction(UIAlertAction(title: L10n.get("cancel"), style: .cancel))
        present(alert, animated: true)
    }
    func previewOnlineSelection(open: Bool = false) { if let item = selectedItems.first { openOnline(item, externally: open) } }
    func zipOnlineSelection() {
        let selected = selectedItems, parent = folders.last?.id
        guard !selected.isEmpty, !busy else { return }
        run(transfer: true, historyAction: "zip") { [weak self] in
            guard let self, let client = self.client else { return }
            let account = try await client.accountIdentity()
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommanderOnlineZIP-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            var sources: [URL] = []
            for item in selected {
                self.activeOperationPaths = (self.onlineLocation(item.name), self.onlineLocation())
                let downloaded = try await client.downloadTree(item)
                defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }
                let source = staging.appendingPathComponent(item.name)
                try FileManager.default.copyItem(at: downloaded, to: source)
                sources.append(source)
            }
            let existing = Set(try await client.children(of: parent).map { $0.name.lowercased() })
            let stem = selected.count == 1 ? (selected[0].isFolder ? selected[0].name : (selected[0].name as NSString).deletingPathExtension) : "Archive"
            var name = stem + ".zip", index = 2
            while existing.contains(name.lowercased()) || sources.contains(where: { $0.lastPathComponent.lowercased() == name.lowercased() }) {
                name = stem + " \(index).zip"; index += 1
            }
            let destination = staging.appendingPathComponent(name)
            self.activeOperationPaths = (selected.map { self.onlineLocation($0.name) }.joined(separator: ", "), self.onlineLocation(name))
            let worker = Task.detached(priority: .userInitiated) {
                try Self.createOnlineArchive(sources: sources, destination: destination)
            }
            try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            let job = try await PendingCloudUpload.prepare(destination, source: selected.map { self.onlineLocation($0.name) }.joined(separator: ", "),
                client: client, parent: parent, account: account, actionKey: "zip")
            let undo = try await PendingCloudUpload.resume(job, client: client)
            self.record(L10n.get("zip"), source: selected.map { self.onlineLocation($0.name) }.joined(separator: ", "), destination: self.onlineLocation(name), undo: undo)
            try PendingCloudUpload.finish(job)
            try await self.load()
        }
    }
    func extractOnlineSelection() {
        let selected = selectedItems.filter { !$0.isFolder && CommanderNativeArchive.supports($0.name) }, parent = folders.last?.id
        guard !selected.isEmpty, !busy else { return }
        run(transfer: true, historyAction: "extract_archive") { [weak self] in
            guard let self, let client = self.client else { return }
            let account = try await client.accountIdentity()
            var names = Set(try await client.children(of: parent).map { $0.name.lowercased() })
            try await self.batch(selected, action: "extract_archive") { item in
                let downloaded = try await client.download(item)
                defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }
                let stem = (item.name as NSString).deletingPathExtension
                var name = stem, index = 2
                while names.contains(name.lowercased()) { name = stem + " \(index)"; index += 1 }
                names.insert(name.lowercased())
                self.activeOperationPaths = (self.onlineLocation(item.name), self.onlineLocation(name))
                let destination = downloaded.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
                let worker = Task.detached(priority: .userInitiated) { try Self.extractOnlineArchive(downloaded, to: destination) }
                try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                let job = try await PendingCloudUpload.prepare(destination, source: self.onlineLocation(item.name),
                    client: client, parent: parent, account: account, actionKey: "extract_archive")
                let undo = try await PendingCloudUpload.resume(job, client: client)
                self.record(L10n.get("extract_archive"), source: self.onlineLocation(item.name), destination: self.onlineLocation(name), undo: undo)
                try PendingCloudUpload.finish(job)
            }
            try await self.load()
        }
    }
    nonisolated private static func extractOnlineArchive(_ source: URL, to directory: URL) throws {
        if source.pathExtension.lowercased() != "zip" {
            try CommanderNativeArchive.extract(source, to: directory, checkCancellation: { try Task.checkCancellation() })
            return
        }
        guard let archive = Archive(url: source, accessMode: .read) else { throw CocoaError(.fileReadCorruptFile) }
        var limits = SafeArchiveLimits()
        for entry in archive { try limits.include(path: entry.path, size: entry.uncompressedSize, symbolicLink: entry.type == .symlink) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        for entry in archive {
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent(entry.path)
            guard destination.standardizedFileURL.path.hasPrefix(directory.path + "/") else { throw CocoaError(.fileReadCorruptFile) }
            if entry.type == .directory {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                guard !SafeFileOperations.exists(destination) else { throw SafeFileOperations.conflict(destination) }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                var written: UInt64 = 0
                let checksum = try archive.extract(entry) { data in
                    try Task.checkCancellation()
                    guard UInt64(data.count) <= entry.uncompressedSize - written else { throw CocoaError(.fileReadCorruptFile) }
                    written += UInt64(data.count); try output.write(contentsOf: data)
                }
                guard written == entry.uncompressedSize, checksum == entry.checksum else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
    }
    nonisolated private static func createOnlineArchive(sources: [URL], destination: URL) throws {
        var pending = sources.map { (path: $0.lastPathComponent, url: $0) }
        var entries: [(path: String, url: URL)] = []
        var limits = SafeArchiveLimits()
        while let entry = pending.popLast() {
            try Task.checkCancellation()
            let values = try entry.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            try limits.include(path: entry.path, size: UInt64(max(0, values.isDirectory == true ? 0 : (values.fileSize ?? 0))), symbolicLink: values.isSymbolicLink == true)
            entries.append(entry)
            if values.isDirectory == true {
                for child in try FileManager.default.contentsOfDirectory(at: entry.url, includingPropertiesForKeys: nil) {
                    pending.append((entry.path + "/" + child.lastPathComponent, child))
                }
            }
        }
        let archive = try Archive(url: destination, accessMode: .create, pathEncoding: nil)
        for entry in entries {
            try Task.checkCancellation()
            try archive.addEntry(with: entry.path, fileURL: entry.url, compressionMethod: .deflate)
        }
    }
    func infoOnlineSelection() {
        guard let selected = selectedItems.first else { return }
        showOnlineInfo(selected, calculateFolder: false)
    }
    private func showOnlineInfo(_ selected: OneDriveItem, calculateFolder: Bool) {
        run(transfer: calculateFolder, progressTitle: calculateFolder ? L10n.get("calculate_folder_size") : nil) { [weak self] in
            guard let self, let item = try await self.client?.metadata(selected.id) else { return }
            let unknown = L10n.get("properties_unknown")
            var size = item.isFolder ? L10n.get("properties_folder_uncalculated") : item.size.map(CommanderFileProperties.byteDescription) ?? unknown
            if calculateFolder, item.isFolder, let client = self.client {
                let report = try await CommanderOnlineTools.folderSize(client, root: item)
                size = report.summary
            }
            let message = String(format: L10n.get("file_info_message"), item.name,
                L10n.get(item.isFolder ? "folder" : "file"),
                self.onlineLocation(item.name),
                size, unknown, item.lastModifiedDateTime ?? unknown, unknown)
                + "\n\n" + L10n.get("properties_provider_note")
            self.commander?.showScrollableDialog(title: L10n.get("file_info"), message: message,
                actionTitle: item.isFolder && !calculateFolder ? L10n.get("calculate_folder_size") : nil,
                action: { [weak self] in self?.showOnlineInfo(item, calculateFolder: true) })
        }
    }
    func duplicateOnlineSelection() {
        let selected = selectedItems, parent = folders.last?.id
        guard !selected.isEmpty else { return }
        run(transfer: true, historyAction: "duplicate") { [weak self] in
            guard let self, let client = self.client else { return }
            let account = try await client.accountIdentity()
            var names = Set(try await client.children(of: parent).map { $0.name.lowercased() })
            try await self.batch(selected, action: "duplicate") { item in
                let url = try await client.downloadTree(item)
                defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                let suffix = item.isFolder ? "" : (item.name as NSString).pathExtension
                let stem = suffix.isEmpty ? item.name : (item.name as NSString).deletingPathExtension
                var name = "", index = 1
                repeat {
                    name = stem + self.text(" Kopie", " copy") + (index == 1 ? "" : " \(index)") + (suffix.isEmpty ? "" : "." + suffix)
                    index += 1
                } while names.contains(name.lowercased())
                names.insert(name.lowercased())
                self.activeOperationPaths = (self.onlineLocation(item.name), self.onlineLocation(name))
                let renamed = url.deletingLastPathComponent().appendingPathComponent(name)
                try FileManager.default.moveItem(at: url, to: renamed)
                let job = try await PendingCloudUpload.prepare(renamed, source: self.onlineLocation(item.name),
                    client: client, parent: parent, account: account, actionKey: "duplicate")
                let undo = try await PendingCloudUpload.resume(job, client: client)
                self.record(L10n.get("duplicate"), source: self.onlineLocation(item.name), destination: self.onlineLocation(name), undo: undo)
                try PendingCloudUpload.finish(job)
            }
            try await self.load()
        }
    }
    func openOnlineSelection() {
        if let item = selectedItems.first { if item.isFolder { navigate(folders + [item]) } else { openOnline(item, externally: true) } }
    }
    private func openOnline(_ item: OneDriveItem, externally: Bool) {
        guard !item.isFolder else { return }
        run(activityKey: "file_opening", retryRead: { [weak self] in self?.openOnline(item, externally: externally) }) { [weak self] in
            guard let self, let client = self.client else { return }
            var limits = OnlinePreviewLimits.forName(item.name)
#if DEBUG
            if Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests",
               let root = AppDelegate.macUITestRoot,
               ProcessInfo.processInfo.arguments.contains("--mac-parity-preview-timeout"),
               !FileManager.default.fileExists(atPath: root.appendingPathComponent("PreviewTimeoutObserved.txt").path) {
                try Data("bounded native preview timeout".utf8).write(to: root.appendingPathComponent("PreviewTimeoutObserved.txt"))
                limits = .init(maximumBytes: limits.maximumBytes, timeout: 0.3, stallTimeout: 0.1)
            }
#endif
            let url = try await client.downloadPreview(item, limits: limits)
            var handedOff = false
            defer { if !handedOff { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
            try Task.checkCancellation()
            let entry = FileEntry(url: url, parent: nil)
            let media = ["image/", "video/", "audio/"].contains { entry.mimeType().hasPrefix($0) }
            if externally && !media {
                // External edits must target a user-saved copy, never an
                // untracked temporary download that may vanish on restart.
                self.cleanExport(); self.exportedURL = url; self.openAfterExport = true
                handedOff = true
                let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                picker.delegate = self; self.present(picker, animated: true)
            } else if let commander = self.commander {
                let epoch = self.generation
                handedOff = true
                commander.previewFile(entry, releaseDownload: { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) },
                    deletionTitle: self.deleteTitle,
                    deleteEntry: { [weak self] _, completed in
                        guard let self, self.generation == epoch, self.client === client, !self.busy,
                              self.commander?.operationInProgress != true else { completed(false); return }
                        self.run(transfer: true, historyAction: "delete") { [weak self] in
                            guard let self else { completed(false); return }
                            do {
                                let undo = try await self.recycleWithUndo(client, item: item)
                                self.record(self.deleteTitle, source: self.onlineLocation(item.name), destination: client.moveBackupLocation ?? L10n.get("remote_deleted"), undo: undo)
                                self.rememberRecovery(client, source: self.onlineLocation(item.name))
                            } catch { completed(false); throw error }
                            completed(true)
                            try await self.load()
                        }
                    })
            }
        }
    }
    func copyOnlineSelection(move: Bool) {
        guard hasSelection else { return }
        Self.clipboard = (selection, move)
        // A private marker prevents a later unrelated system clipboard from
        // accidentally triggering a stale remote move.
        UIPasteboard.general.setItems([["com.opencommander.onedrive-selection": Data(generation.uuidString.utf8)]], options: [.localOnly: true])
        commander?.updateGlobalStatus(String(format: L10n.get(move ? "clipboard_cut" : "clipboard_copied"), selectedItems.count))
    }
    private func confirmShareLink(_ item: OneDriveItem) {
        guard let client, !busy,
              client is OneDriveClient || (client as? CloudFileClient)?.supportsSharingLink == true else { return }
        let confirmation = UIAlertController(title: text("Öffentlichen Freigabelink erstellen?", "Create a public sharing link?"),
            message: text("Der Link macht „\(item.name)“ für Personen mit dem Link zugänglich, möglicherweise ohne Anmeldung. Die Freigabe kann dauerhaft bestehen und wird durch Abbrechen nach dem Erstellen nicht zurückgenommen. Prüfe bestehende Rechte und entferne die Freigabe bei Bedarf auf der Anbieter-Webseite. Erst Erstellen ändert die Freigabe.",
                          "The link makes ‘\(item.name)’ accessible to people with the link, potentially without signing in. Sharing can persist and cancelling after creation does not revoke it. Check existing permissions and revoke sharing on the provider website when needed. Only Create changes sharing."), preferredStyle: .alert)
        confirmation.addAction(UIAlertAction(title: L10n.get("cancel"), style: .cancel))
        confirmation.addAction(UIAlertAction(title: text("Erstellen", "Create"), style: .default) { [weak self] _ in
            self?.run { [weak self] in
                let url: URL
                if let api = client as? OneDriveClient { url = try await api.createReadOnlyShareLink(item) }
                else if let cloud = client as? CloudFileClient { url = try await cloud.createPublicShareLink(item) }
                else { throw CloudConnection.failure("cloud_invalid") }
                guard let self else { return }
                let result = UIAlertController(title: text("Freigabelink", "Sharing link"), message: url.absoluteString, preferredStyle: .alert)
                result.addAction(UIAlertAction(title: text("Link kopieren", "Copy link"), style: .default) { _ in UIPasteboard.general.string = url.absoluteString })
                result.addAction(UIAlertAction(title: text("Link öffnen", "Open link"), style: .default) { _ in UIApplication.shared.open(url) })
                result.addAction(UIAlertAction(title: text("Schließen", "Close"), style: .cancel))
                self.present(result, animated: true)
            }
        })
        present(confirmation, animated: true)
    }
    static var currentClipboard: (selection: OneDriveSelection, move: Bool)? {
        guard UIPasteboard.general.contains(pasteboardTypes: ["com.opencommander.onedrive-selection"]) else { clipboard = nil; return nil }
        return clipboard
    }
    private var client: (any CommanderOnlineClient)?
    var paneTitle = "1"
    var onClose: (() -> Void)?
    var onActivate: (() -> Void)?
    var onStateChanged: (() -> Void)?
    func cancelPendingWork() {
        work?.cancel(); generation = UUID(); readEpoch = UUID()
        listingRetry?.cancel(); listingRetry = nil
        if Self.clipboard?.selection.browser === self { Self.clipboard = nil }
    }
    func refreshOnline() { reload() }
    func refreshVisibility() { applyListingOrder(); rebuildTree() }
    /// Update only presentation: do not reconnect, discard folder history or
    /// recreate controls underneath an active cloud operation.
    func refreshPresentation(darkMode: Bool) {
        guard isViewLoaded else { return }
        overrideUserInterfaceStyle = darkMode ? .dark : .light
        let theme = ViewController.ThemeColors(darkMode: darkMode)
        let accent = UIColor(hex: paneTitle == "1" ? (darkMode ? "#88baff" : "#185bb5") : (darkMode ? "#79dcb9" : "#147454"))
        view.backgroundColor = theme.panelBackground
        accentLine?.backgroundColor = accent
        for column in [treeColumn, filesColumn] {
            column?.backgroundColor = theme.columnBackground
            column?.layer.borderColor = theme.columnBorder.cgColor
        }
        for (header, key) in [(treeHeader, "tree"), (filesHeader, "files")] {
            header?.text = "  " + L10n.get(key)
            header?.backgroundColor = theme.columnHeaderBackground; header?.textColor = accent
        }
        pathLabel.textColor = theme.secondaryText; pathLabel.backgroundColor = theme.pathBackground
        readErrorLabel.textColor = theme.primaryText
        readRetryButton.setTitle(L10n.get("directory_retry"), for: .normal)
        pathLabel.layer.borderColor = theme.pathBorder.cgColor; countLabel.textColor = theme.secondaryText
        treeView.backgroundColor = theme.treeBackground; treeView.separatorColor = theme.columnBorder
        tableView.backgroundColor = theme.fileBackground; tableView.separatorColor = theme.columnBorder
        treeDivider?.backgroundColor = theme.columnBorder
        backButton.accessibilityLabel = L10n.get("back"); forwardButton.accessibilityLabel = L10n.get("forward")
        upButton.accessibilityLabel = text("Übergeordneter Ordner", "Parent folder")
        closeButton?.accessibilityLabel = text("Zurück zum lokalen Ordner", "Return to local folder")
        loadingIndicator.accessibilityLabel = L10n.get(activeActivityKey ?? "directory_loading")
        actionButton.setTitle(text("Aktionen", "Actions"), for: .normal)
        navigationItem.leftBarButtonItem?.title = text("Schließen", "Close")
        navigationItem.rightBarButtonItem?.title = text("Aktionen", "Actions")
        filterField.applyTheme(theme, placeholder: L10n.get("filter_names"))
        filterStatus.textColor = theme.secondaryText
        clearFilterButton.setTitle(L10n.get("filter_clear"), for: .normal)
        for (button, key) in zip(sortButtons, ["sort_name", "sort_size", "sort_type", "sort_date"]) {
            button.setTitle(L10n.get(key), for: .normal)
        }
        applyListingOrder(); rebuildTree()
    }
    func createOnlineFolder() { guard !busy, authenticated else { return }; namePrompt(item: nil) }
    func showOnlineActions() { actions() }
    func navigateOnlineParent() {
        guard !busy, !folders.isEmpty else { return }
        navigate(Array(folders.dropLast()))
    }
    func navigateOnlineBack() { if let path = backHistory.last { navigate(path, history: -1) } }
    func navigateOnlineForward() { if let path = forwardHistory.last { navigate(path, history: 1) } }
    private var items: [OneDriveItem] = []
    private var folders: [OneDriveItem] = []
    var initialFolderNames: [String]?
    var onNavigationSaved: (([String]) -> Void)?
    private var work: Task<Void, Never>?
    private var busy = false
    private var authenticated = false
    private let readErrorBox = UIStackView()
    private let readErrorLabel = UILabel()
    private let readRetryButton = UIButton(type: .system)
    private var retryReadAction: (() -> Void)?
    private var exportedURL: URL?
    private let message = UILabel()
    private let listingWarning = UILabel()
    private var listingObserver: NSObjectProtocol?
    private var listingRetry: DispatchWorkItem?
    private var readEpoch = UUID()
    private var dropHoverWork: DispatchWorkItem?
    private var dropTreeRead: Task<Void, Never>?
    private var dropHoverKey: String?
    private var dropScrollTimer: Timer?
    private weak var dropTable: UITableView?
    private var dropSession: UIDropSession?
    private var nativeDropPoint: CGPoint?
    private var desiredFolders: [OneDriveItem] = []
    private var signingIn = false
    private weak var resizingColumns: UIStackView?
    private weak var resizingTree: UIView?
    private var treeWidthConstraint: NSLayoutConstraint?
    private var treeFraction: CGFloat = 0.28
    private weak var treeViewport: CommanderTreeViewport?
    private let clientIDKey = "OneDriveApplicationClientID"
    private var german: Bool { (UserDefaults.standard.string(forKey: "language") ?? Locale.current.language.languageCode?.identifier ?? "en").hasPrefix("de") }
    private func text(_ de: String, _ en: String) -> String { german ? de : en }
    init(remote: RemoteConnection? = nil, cloud: CloudConnection? = nil) { remoteProfile = remote; cloudProfile = cloud; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let listingObserver { NotificationCenter.default.removeObserver(listingObserver) }
        listingRetry?.cancel(); dropHoverWork?.cancel(); dropTreeRead?.cancel(); dropScrollTimer?.invalidate()
        for url in previewURLs { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        if let exportedURL { try? FileManager.default.removeItem(at: exportedURL.deletingLastPathComponent()) }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = locationTitle
        isModalInPresentation = true
        buildCommanderLayout()
        tableView.accessibilityIdentifier = "OneDriveOnlineFiles"
        message.numberOfLines = 0; message.textAlignment = .center
        message.textColor = .secondaryLabel
        message.accessibilityIdentifier = "OneDriveOnlineStatus"
        tableView.backgroundView = message
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: text("Schließen", "Close"), style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: text("Aktionen", "Actions"), style: .plain, target: self, action: #selector(actions))
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refreshControl
        for list in [tableView, treeView] { list.dragDelegate = self; list.dropDelegate = self; list.dragInteractionEnabled = DesktopBridge.shared == nil }
        configureNativeDrag()
        directoryMenu = CommanderDirectoryMenu(table: tableView) { [weak self] in
            guard let self else { return nil }
            self.onActivate?(); self.view.endEditing(true)
            let idle = !self.busy && self.commander?.operationInProgress != true
            let writable: UIMenuElement.Attributes = idle && self.authenticated ? [] : .disabled
            return UIMenu(children: [
                UIAction(title: L10n.get("new_folder"), image: UIImage(systemName: "folder.badge.plus"), attributes: writable) { [weak self] _ in self?.createOnlineFolder() },
                UIAction(title: L10n.get("paste"), image: UIImage(systemName: "doc.on.clipboard"), attributes: writable) { [weak self] _ in self?.commander?.pasteClipboard() },
                UIAction(title: L10n.get("refresh"), image: UIImage(systemName: "arrow.clockwise"), attributes: idle ? [] : .disabled) { [weak self] _ in self?.refreshOnline() },
                UIAction(title: L10n.get("commander_search"), image: UIImage(systemName: "magnifyingglass"), attributes: writable) { [weak self] _ in self?.commander?.showCommanderSearch() },
                UIAction(title: L10n.get("directory_copy_path")) { [weak self] _ in UIPasteboard.general.string = self?.onlineLocation() }
            ])
        }
#if DEBUG
        if installPreviewTestClient() { installListingObserver(); reload(); return }
#endif
        if let cloudProfile {
            client = CloudFileClient.browserClient(cloudProfile)
            installListingObserver(); reload(); return
        }
        if let remoteProfile {
            client = RemoteFileClient(remoteProfile)
            installListingObserver(); reload(); return
        }
        let id = UserDefaults.standard.string(forKey: clientIDKey) ?? Bundle.main.object(forInfoDictionaryKey: "OneDriveClientID") as? String ?? ""
        if OneDriveClient.validClientID(id) {
            client = OneDriveClient.browserClient(clientID: id)
            installListingObserver()
            do {
                if try client?.hasSavedLogin() == true { reload() }
                else { message.text = text("OpenCommander ist für OneDrive eingerichtet.\n\nÖffne Aktionen → Mit Microsoft verbinden, um dein Konto anzumelden. Es wird kein synchronisierter Ordner benötigt.",
                    "OpenCommander is configured for OneDrive.\n\nChoose Actions → Connect to Microsoft to sign in. No synchronized folder is required.") }
            } catch { message.text = error.localizedDescription }
        } else {
            message.text = text("Direkter Online-Zugang ohne synchronisierten Ordner.\n\nNoch nicht verbunden. Öffne Aktionen → Microsoft-App einrichten. Die Anmeldung im Browser allein verbindet OpenCommander nicht.",
                "Direct online access without a synchronized folder.\n\nNot connected. Choose Actions → Configure Microsoft app. Signing in on the website alone does not connect OpenCommander.")
        }
    }
#if DEBUG
    /// Isolated UI fixture only: no real account, configuration or network.
    private func installPreviewTestClient() -> Bool {
        guard Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests",
              ProcessInfo.processInfo.arguments.contains("--mac-parity-online-preview"),
              let root = AppDelegate.macUITestRoot else { return false }
        let bytes = Data("Synthetic cloud preview: Grüße 日本語 👋\n".utf8)
        let profile = CloudConnection(name: "Preview fixture", kind: "drive", remote: "fixture", configPath: root.appendingPathComponent("unused.conf").path)
        var pending: [String: Task<Void, Never>] = [:]
        let simulateOutage = ProcessInfo.processInfo.arguments.contains("--mac-parity-online-offline")
        let largeMedia = ProcessInfo.processInfo.arguments.contains("--mac-parity-online-large")
        var listRequests = 0
        client = CloudFileClient(profile, transport: { id, _, operation, path, _, local, complete in
            if operation == "download" {
                try? Data("synthetic download requested".utf8).write(to: root.appendingPathComponent("PreviewAnyDownload.txt"))
            }
            if operation == "list", path.isEmpty {
                listRequests += 1
                try? Data(String(listRequests).utf8).write(to: root.appendingPathComponent("PreviewListRequests.txt"), options: .atomic)
                if FileManager.default.fileExists(atPath: root.appendingPathComponent("PreviewQuota.txt").path) {
                    complete(nil, CloudProviderErrors.temporary("cloud_google_quota", cooldown: 10)); return
                }
                if simulateOutage && FileManager.default.fileExists(atPath: root.appendingPathComponent("PreviewOffline.txt").path) {
                    complete(nil, CloudConnection.failure("cloud_request_failed")); return
                }
                let item: [String: Any] = ["Name": "Proof.txt", "Path": "Proof.txt", "Size": bytes.count,
                    "IsDir": false, "ModTime": "2026-10-25T09:00:00Z", "ID": "proof"]
                var entries = [item]
                if largeMedia {
                    entries += [("Huge.png", Int64(128 * 1024 * 1024 + 1)), ("Huge.mp4", Int64(2) * 1024 * 1024 * 1024 + 1)].map { name, size in
                        ["Name": name, "Path": name, "Size": size, "IsDir": false, "ID": name] as [String: Any]
                    }
                }
                complete(try? JSONSerialization.data(withJSONObject: entries), nil)
            } else if operation == "download", path == "Proof.txt", let local,
                      local.lastPathComponent == "Proof.txt",
                      local.deletingLastPathComponent().lastPathComponent.hasPrefix("OpenCommander-Remote-") {
                try? Data(local.path.utf8).write(to: root.appendingPathComponent("PreviewDownloadPath.txt"), options: .atomic)
                pending[id] = Task { @MainActor in
                    defer { pending.removeValue(forKey: id) }
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        // Only this DEBUG fixture backend can hold its own
                        // response while native acceptance navigates elsewhere.
                        let hold = root.appendingPathComponent("HoldPreviewDownload.txt")
                        let deadline = Date().addingTimeInterval(60)
                        while FileManager.default.fileExists(atPath: hold.path), Date() < deadline {
                            try await Task.sleep(nanoseconds: 100_000_000)
                        }
                        try Task.checkCancellation()
                        try bytes.write(to: local, options: .atomic)
                        complete(Data(), nil)
                    } catch { complete(nil, error as NSError) }
                }
            } else { complete(nil, CloudConnection.failure("cloud_invalid")) }
        }, cancel: { id in Task { @MainActor in pending[id]?.cancel() } })
        return true
    }
#endif
    private func installListingObserver() {
        if let listingObserver { NotificationCenter.default.removeObserver(listingObserver) }
        listingObserver = NotificationCenter.default.addObserver(forName: OneDriveClient.listingChanged, object: nil, queue: .main) { [weak self] note in
            // NotificationCenter delivers on OperationQueue.main. Preserve
            // synchronous login/mutation ordering while declaring that executor.
            MainActor.assumeIsolated {
            guard let self, note.object as? String == self.client?.clientID else { return }
            if note.userInfo?["accountChanged"] as? Bool == true {
                self.readErrorBox.isHidden = true; self.retryReadAction = nil
                if !self.signingIn { self.work?.cancel() }
                self.generation = UUID(); self.readEpoch = UUID(); self.listingRetry?.cancel()
                self.folders = []; self.desiredFolders = []; self.items = []; self.selectedIDs = []
                self.treeChildren = [:]; self.expanded = ["root"]
                self.authenticated = (try? self.client?.hasSavedLogin()) == true
                if !self.authenticated { self.message.text = self.text("Bitte OneDrive mit OpenCommander verbinden.", "Please connect OneDrive to OpenCommander.") }
                self.applyListingOrder(); self.rebuildTree()
                if self.authenticated && !self.signingIn { self.scheduleListingRefresh(after: 0.1) }
                return
            }
            guard self.authenticated else { return }
            self.treeChildren.removeAll(); self.scheduleListingRefresh(after: 0.1)
            }
        }
    }
    private func buildCommanderLayout() {
        let theme = palette
        view.backgroundColor = theme.panelBackground
        let shell = UIStackView()
        shell.axis = .vertical; shell.spacing = 8
        let dark = traitCollection.userInterfaceStyle == .dark
        let accent = UIColor(hex: paneTitle == "1" ? (dark ? "#88baff" : "#185bb5") : (dark ? "#79dcb9" : "#147454"))
        let accentLine = UIView(); accentLine.backgroundColor = accent
        self.accentLine = accentLine
        accentLine.heightAnchor.constraint(equalToConstant: 3).isActive = true
        shell.addArrangedSubview(accentLine)
        shell.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shell)
        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            shell.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            shell.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            shell.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
        let pathRow = UIStackView(); pathRow.spacing = 6; pathRow.alignment = .center
        for (button, symbol, label, action) in [(backButton, "chevron.left", L10n.get("back"), { [weak self] in self?.navigateOnlineBack() }),
            (forwardButton, "chevron.right", L10n.get("forward"), { [weak self] in self?.navigateOnlineForward() }),
            (upButton, "arrow.up", text("Übergeordneter Ordner", "Parent folder"), { [weak self] in self?.navigateOnlineParent() })] {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityLabel = label
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            pathRow.addArrangedSubview(button)
        }
        pathLabel.font = .systemFont(ofSize: 11); pathLabel.textColor = theme.secondaryText
        pathLabel.backgroundColor = theme.pathBackground; pathLabel.layer.cornerRadius = 8
        pathLabel.layer.borderWidth = 1; pathLabel.layer.borderColor = theme.pathBorder.cgColor
        pathLabel.lineBreakMode = .byTruncatingMiddle; pathLabel.accessibilityIdentifier = "OneDriveOnlinePath"
        pathLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathRow.addArrangedSubview(pathLabel)
        countLabel.font = .systemFont(ofSize: 11); countLabel.textColor = theme.secondaryText
        pathRow.addArrangedSubview(countLabel)
        loadingIndicator.accessibilityIdentifier = "OneDriveLoading"
        loadingIndicator.accessibilityLabel = L10n.get("directory_loading")
        pathRow.addArrangedSubview(loadingIndicator)
        actionButton.setTitle(text("Aktionen", "Actions"), for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 11)
        actionButton.addTarget(self, action: #selector(actions), for: .touchUpInside)
        pathRow.addArrangedSubview(actionButton)
        let closeButton = UIButton(type: .system); closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        self.closeButton = closeButton
        closeButton.accessibilityLabel = text("Zurück zum lokalen Ordner", "Return to local folder")
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        pathRow.addArrangedSubview(closeButton); shell.addArrangedSubview(pathRow)
        listingWarning.numberOfLines = 0; listingWarning.font = .systemFont(ofSize: 11)
        listingWarning.textColor = .systemOrange; listingWarning.isHidden = true
        listingWarning.accessibilityIdentifier = "OnlineCachedListingWarning"
        shell.addArrangedSubview(listingWarning)
        readErrorBox.axis = .vertical; readErrorBox.spacing = 6; readErrorBox.isHidden = true
        readErrorLabel.numberOfLines = 0; readErrorLabel.font = .systemFont(ofSize: 12)
        readErrorLabel.textColor = theme.primaryText
        readErrorLabel.accessibilityIdentifier = "OnlineReadError-\(paneTitle)"
        readRetryButton.setTitle(L10n.get("directory_retry"), for: .normal)
        readRetryButton.accessibilityIdentifier = "OnlineReadRetry-\(paneTitle)"
        readRetryButton.addAction(UIAction { [weak self] _ in
            guard let self, !self.busy, self.commander?.operationInProgress != true else { return }
            self.onActivate?(); self.view.endEditing(true)
            if let retry = self.retryReadAction { retry() } else { self.reload() }
        }, for: .touchUpInside)
        readErrorBox.addArrangedSubview(readErrorLabel); readErrorBox.addArrangedSubview(readRetryButton)
        shell.addArrangedSubview(readErrorBox)
        let columns = UIStackView(); columns.axis = .horizontal; columns.spacing = 6
        func column(_ title: String) -> UIStackView {
            let stack = UIStackView(); stack.axis = .vertical
            stack.backgroundColor = theme.columnBackground; stack.layer.cornerRadius = 10
            stack.layer.borderWidth = 1; stack.layer.borderColor = theme.columnBorder.cgColor; stack.clipsToBounds = true
            let header = UILabel(); header.text = "  " + title; header.font = .boldSystemFont(ofSize: 12)
            header.backgroundColor = theme.columnHeaderBackground; header.textColor = accent
            header.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stack.addArrangedSubview(header); return stack
        }
        let treeColumn = column(L10n.get("tree")), fileColumn = column(L10n.get("files"))
        self.treeColumn = treeColumn; filesColumn = fileColumn
        treeHeader = treeColumn.arrangedSubviews.first as? UILabel
        filesHeader = fileColumn.arrangedSubviews.first as? UILabel
        treeView.dataSource = self; treeView.delegate = self; treeView.rowHeight = 44
        treeView.backgroundColor = theme.treeBackground; treeView.separatorColor = theme.columnBorder
        treeView.accessibilityIdentifier = "OneDriveOnlineTree"
        let viewport = CommanderTreeViewport(table: treeView, identifier: "OneDriveTreeHorizontal")
        treeViewport = viewport; treeColumn.addArrangedSubview(viewport)
        filterField.applyTheme(theme, placeholder: L10n.get("filter_names"))
        filterField.clearButtonMode = .always; filterField.font = .systemFont(ofSize: 12)
        filterField.accessibilityIdentifier = "OneDriveOnlineFilter"
        filterField.addAction(UIAction { [weak self] _ in self?.onActivate?(); self?.applyListingOrder() }, for: .editingChanged)
        fileColumn.addArrangedSubview(filterField)
        filterStatus.font = .systemFont(ofSize: 11); filterStatus.numberOfLines = 0
        filterStatus.isHidden = true; clearFilterButton.isHidden = true
        filterStatus.accessibilityIdentifier = "OnlineFilterStatus-\(paneTitle)"
        clearFilterButton.setTitle(L10n.get("filter_clear"), for: .normal)
        clearFilterButton.accessibilityIdentifier = "OnlineClearFilter-\(paneTitle)"
        clearFilterButton.addAction(UIAction { [weak self] _ in self?.filterField.text = ""; self?.applyListingOrder() }, for: .touchUpInside)
        let filterRow = UIStackView(arrangedSubviews: [filterStatus, clearFilterButton]); filterRow.spacing = 8
        fileColumn.addArrangedSubview(filterRow)
        let sortRow = UIStackView()
        for (index, name) in ["sort_name", "sort_size", "sort_type", "sort_date"].enumerated() {
            let button = UIButton(type: .system); button.setTitle(L10n.get(name), for: .normal)
            sortButtons.append(button)
            button.titleLabel?.font = .systemFont(ofSize: 11)
            if index > 0 { button.widthAnchor.constraint(equalToConstant: [0,90,70,125][index]).isActive = true }
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }; self.ascending = self.sortField == index ? !self.ascending : true
                self.onActivate?()
                self.sortField = index; self.applyListingOrder()
            }, for: .touchUpInside)
            sortRow.addArrangedSubview(button)
        }
        tableView.dataSource = self; tableView.delegate = self; tableView.rowHeight = 44
        tableView.backgroundColor = theme.fileBackground; tableView.separatorColor = theme.columnBorder
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(openDoubleTappedItem)); doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = true; doubleTap.delaysTouchesEnded = false; tableView.addGestureRecognizer(doubleTap)
        fileColumn.addArrangedSubview(CommanderTreeViewport(table: tableView,
            identifier: "OnlineFileHorizontal-\(paneTitle)", header: sortRow, minimumWidth: 440))
        columns.addArrangedSubview(treeColumn)
        let divider = UIView(); divider.backgroundColor = theme.columnBorder
        treeDivider = divider
        divider.widthAnchor.constraint(equalToConstant: 6).isActive = true
        divider.accessibilityIdentifier = "OnlineTreeDivider-\(paneTitle)"
        divider.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeOnlineTree(_:))))
        columns.addArrangedSubview(divider); columns.addArrangedSubview(fileColumn)
        let saved = UserDefaults.standard.double(forKey: "tree_fraction_\(paneTitle)")
        treeFraction = saved > 0 ? CGFloat(min(0.55, max(0.15, saved))) : 0.28
        resizingColumns = columns; resizingTree = treeColumn
        treeWidthConstraint = treeColumn.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: treeFraction)
        treeWidthConstraint?.isActive = true
        shell.addArrangedSubview(columns)
        updateNavigation()
    }
    @objc private func resizeOnlineTree(_ gesture: UIPanGestureRecognizer) {
        guard let columns = resizingColumns, let tree = resizingTree, columns.bounds.width > 0 else { return }
        treeFraction = min(0.55, max(0.15, treeFraction + gesture.translation(in: columns).x / columns.bounds.width))
        gesture.setTranslation(.zero, in: columns)
        treeWidthConstraint?.isActive = false
        treeWidthConstraint = tree.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: treeFraction)
        treeWidthConstraint?.isActive = true
        if gesture.state == .ended { UserDefaults.standard.set(Double(treeFraction), forKey: "tree_fraction_\(paneTitle)") }
    }
    private func scheduleListingRefresh(after delay: TimeInterval) {
        listingRetry?.cancel()
        let expected = readEpoch
        let retry = DispatchWorkItem { [weak self] in
            guard let self, self.readEpoch == expected, self.viewIfLoaded?.window != nil else { return }
            if self.busy || (self.commander?.operationInProgress == true && self.commander?.allowsOperationNavigation != true) || self.presentedViewController != nil {
                self.scheduleListingRefresh(after: 1); return
            }
            self.run(readOnly: true) { [weak self] in guard let self else { return }; try await self.load(path: self.desiredFolders) }
        }
        listingRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, delay), execute: retry)
    }
    private func updateNavigation() {
        pathLabel.text = "  " + onlineLocation()
        backButton.isEnabled = !busy && !backHistory.isEmpty
        forwardButton.isEnabled = !busy && !forwardHistory.isEmpty
        upButton.isEnabled = !busy && !folders.isEmpty
        let activity = L10n.get(activeActivityKey ?? "directory_loading")
        countLabel.text = busy ? activity : "\(selectedIDs.count)/\(visibleItems.count)"
        loadingIndicator.accessibilityLabel = activity
        if busy { loadingIndicator.startAnimating() } else { loadingIndicator.stopAnimating() }
    }
    private func applyListingOrder() {
        let filter = filterField.text ?? ""
        let hidden = UserDefaults.standard.bool(forKey: "show_hidden_files")
        visibleItems = items.filter { OnlineDisplayPolicy.visible($0.name, hidden: hidden) && (filter.isEmpty || $0.name.localizedStandardContains(filter)) }.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let comparison: ComparisonResult
            switch sortField {
            case 1: comparison = (a.size ?? 0) == (b.size ?? 0) ? a.name.localizedStandardCompare(b.name) : (a.size ?? 0) < (b.size ?? 0) ? .orderedAscending : .orderedDescending
            case 2: comparison = (a.name as NSString).pathExtension.localizedStandardCompare((b.name as NSString).pathExtension)
            case 3: comparison = (a.lastModifiedDateTime ?? "").compare(b.lastModifiedDateTime ?? "")
            default: comparison = a.name.localizedStandardCompare(b.name)
            }
            let order = comparison == .orderedSame ? a.name.localizedStandardCompare(b.name) : comparison
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        selectedIDs.formIntersection(Set(visibleItems.map(\.id)))
        filterStatus.isHidden = filter.isEmpty; clearFilterButton.isHidden = filter.isEmpty
        let total = items.filter { OnlineDisplayPolicy.visible($0.name, hidden: hidden) }.count
        filterStatus.text = visibleItems.isEmpty ? L10n.get("filter_no_matches") : String(format: L10n.get("filter_active_status"), visibleItems.count, total)
        if authenticated {
            message.text = visibleItems.isEmpty ? (items.isEmpty ? text("Dieser Ordner ist leer.", "This folder is empty.") : text("Keine passenden Dateien.", "No matching files.")) : nil
        }
        tableView.reloadData(); updateNavigation(); onStateChanged?()
    }
    private func rebuildTree() {
        treeRows = []; var visited = Set<String>()
        func append(_ path: [OneDriveItem]) {
            guard visited.insert(key(path)).inserted else { return }
            treeRows.append(path)
            if expanded.contains(key(path)) {
                for item in (treeChildren[key(path)] ?? []).filter({ $0.isFolder && OnlineDisplayPolicy.visible($0.name, hidden: UserDefaults.standard.bool(forKey: "show_hidden_files")) }) { append(path + [item]) }
            }
        }
        append([])
        treeViewport?.fit(treeRows.map { path in
            String(repeating: "  ", count: path.count) + "▼ " + (path.last?.name ?? locationTitle)
        })
        treeView.reloadData()
    }
    private func resetAccountView() {
        readErrorBox.isHidden = true; retryReadAction = nil
        authenticated = false; items = []; folders = []; visibleItems = []
        selectedIDs = []; generation = UUID(); treeChildren = [:]; expanded = ["root"]
        if Self.clipboard?.selection.browser === self { Self.clipboard = nil }
        backHistory = []; forwardHistory = []
        applyListingOrder(); rebuildTree()
    }
    private func navigate(_ path: [OneDriveItem], history: Int = 0) {
        guard !busy, authenticated else { return }
        onActivate?()
        run(readOnly: true, retryRead: { [weak self] in self?.navigate(path, history: history) }) { [weak self] in
            guard let self else { return }; let old = self.folders
            try await self.load(path: path)
            if history == -1 { self.backHistory.removeLast(); self.forwardHistory.append(old) }
            else if history == 1 { self.forwardHistory.removeLast(); self.backHistory.append(old) }
            else if self.key(old) != self.key(path) { self.backHistory.append(old); self.forwardHistory.removeAll() }
        }
    }
    @objc private func openDoubleTappedItem(_ gesture: UITapGestureRecognizer) {
        guard !busy, let row = tableView.indexPathForRow(at: gesture.location(in: tableView)), row.row < visibleItems.count else { return }
        let item = visibleItems[row.row]
        if item.isFolder { navigate(folders + [item]) } else { openOnline(item, externally: true) }
    }
    @objc private func close() {
        cancelPendingWork()
        if let onClose { onClose() } else { dismiss(animated: true) }
    }
    private var completionNotice: String?
    private var activeActivityKey: String?
    private func observeTransfer(_ client: (any CommanderOnlineClient)?) {
        let progress: (String, Int64, Int64) -> Void = { [weak self] phase, done, total in
            guard let self, total > 0 else { return }
            let percent = Int(min(100, Double(done) / Double(total) * 100))
            self.commander?.updateTransferProgress(self.locationTitle + ": " + L10n.get(phase) + " · \(done)/\(total) Bytes (\(percent)%)", progress: percent)
        }
        (client as? RemoteFileClient)?.transferProgress = progress
        (client as? CloudFileClient)?.transferProgress = progress
    }
    private func stopObservingTransfer(_ client: (any CommanderOnlineClient)?) {
        (client as? RemoteFileClient)?.transferProgress = nil
        (client as? CloudFileClient)?.transferProgress = nil
    }
    private func transferProgress(_ completed: Int, total: Int, name: String) {
        let percent = total == 0 ? 0 : completed * 100 / total
        commander?.updateTransferProgress(locationTitle + ": \(completed)/\(total) " + text("Objekte bearbeitet", "items processed") + " (\(percent)%) · " + name, progress: percent)
    }
    private func rememberRecovery(_ client: any CommanderOnlineClient, source: String) {
        guard let backup = client.moveBackupLocation else { return }
        record(L10n.get("remote_recovery"), source: source, destination: backup)
        completionNotice = L10n.get("remote_recovery_notice") + "\n" + backup
    }
    private func run(transfer: Bool = false, historyAction: String? = nil, progressTitle: String? = nil,
                     activityKey: String? = nil, readOnly: Bool = false, retryRead: (() -> Void)? = nil,
                     _ action: @escaping () async throws -> Void) {
        guard !busy, commander?.operationInProgress != true ||
            (readOnly && activityKey == nil && commander?.allowsOperationNavigation == true) else { return }
        readErrorBox.isHidden = true
        let inlineReadError = readOnly || activityKey == "file_opening"
        retryReadAction = inlineReadError ? retryRead : nil
        busy = true; completionNotice = nil; activeOperationPaths = nil
        activeActivityKey = activityKey
        let showsProgress = transfer || activityKey != nil
        updateNavigation()
        if showsProgress {
            observeTransfer(client)
            let title = progressTitle ?? locationTitle + ": " + (activityKey.map { L10n.get($0) } ?? text("Übertragung läuft…", "transferring…"))
            commander?.showProgress(title, progress: 0, cancellable: true, indeterminate: true,
                navigationOwner: self, onCancel: { [weak self] in self?.work?.cancel() })
        }
        work = Task { [weak self] in
            guard let self else { return }
            var status = self.locationTitle + ": " + self.text("fertig", "complete")
            defer {
                self.busy = false; self.activeActivityKey = nil
                self.refreshControl?.endRefreshing(); self.updateNavigation()
                if showsProgress { self.commander?.finishProgress(status); self.stopObservingTransfer(self.client) }
                if transfer { self.commander?.refreshAllPanes(clearSelectionIn: []) }
                self.onStateChanged?()
                self.activeOperationPaths = nil
                self.offerUploadRecovery()
            }
            do { try await action(); status = self.completionNotice ?? status }
            catch is CancellationError {
                status = self.text("Abgebrochen; abgeschlossene Schritte bleiben erhalten.", "Cancelled; completed steps are retained.") + (self.completionNotice.map { "\n" + $0 } ?? "")
                if let historyAction { self.record(L10n.get(historyAction), source: self.activeOperationPaths?.source ?? self.onlineLocation(), destination: self.activeOperationPaths?.destination ?? self.onlineLocation(), error: CancellationError()) }
            }
            catch where Task.isCancelled {
                status = self.text("Abgebrochen; abgeschlossene Schritte bleiben erhalten.", "Cancelled; completed steps are retained.")
                    + (self.completionNotice.map { "\n" + $0 } ?? "")
                if let historyAction { self.record(L10n.get(historyAction), source: self.activeOperationPaths?.source ?? self.onlineLocation(), destination: self.activeOperationPaths?.destination ?? self.onlineLocation(), error: CancellationError()) }
            }
            catch {
                let description = HistoryFailure.presentation(error)
                status = description + (self.completionNotice.map { "\n" + $0 } ?? "")
                if inlineReadError {
                    self.readErrorLabel.text = description + (self.items.isEmpty ? "" : "\n" + L10n.get("online_read_failed_retained"))
                    self.readErrorBox.isHidden = false
                    self.message.text = nil
                } else { self.error(status) }
                if let historyAction { self.record(L10n.get(historyAction), source: self.activeOperationPaths?.source ?? self.onlineLocation(), destination: self.activeOperationPaths?.destination ?? self.onlineLocation(), error: error) }
            }
        }
    }
    private func error(_ description: String) {
        message.text = items.isEmpty ? description : nil
        guard presentedViewController == nil, view.window != nil else { return }
        let alert = UIAlertController(title: locationTitle, message: description, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    private func load(path: [OneDriveItem]? = nil) async throws {
        guard let client else { return }
        var requested = path ?? folders
        if path == nil, let names = initialFolderNames {
            initialFolderNames = nil
            requested = []
            for name in names {
                try Task.checkCancellation()
                let matches = try await client.children(of: requested.last?.id).filter { $0.name == name && $0.isFolder }
                guard matches.count == 1 else { throw CloudConnection.failure("cloud_saved_folder_missing") }
                requested.append(matches[0])
            }
        }
        desiredFolders = requested; readEpoch = UUID(); listingRetry?.cancel()
        let expected = readEpoch
        let response = try await client.browserListing(of: requested.last?.id)
#if DEBUG
        try await holdListingAcceptanceIfRequested(expected: expected)
#endif
        let listing = response.items
        var cache = treeChildren
        // Mutation invalidation must not leave a nested location with only
        // an empty root row. Rebuild its ancestor listings, not the whole drive.
        for count in 0..<requested.count {
            let ancestor = Array(requested.prefix(count))
            if cache[key(ancestor)] == nil { cache[key(ancestor)] = try await client.children(of: ancestor.last?.id) }
        }
        try Task.checkCancellation()
        guard readEpoch == expected else { throw CancellationError() }
        let sameFolder = requested.map(\.id) == folders.map(\.id)
        let departed = !folders.isEmpty && requested.map(\.id) == folders.dropLast().map(\.id) ? folders.last?.id : nil
        items = listing
        folders = requested
        onNavigationSaved?(requested.map(\.name))
        selectedIDs = sameFolder ? selectedIDs.intersection(Set(listing.map(\.id))) : Set([departed].compactMap { $0 }.filter { id in listing.contains { $0.id == id } })
        cache[key(folders)] = listing; treeChildren = cache
        for count in 0...folders.count { expanded.insert(key(Array(folders.prefix(count)))) }
        authenticated = true
        title = folders.last?.name ?? locationTitle
        if let cachedAt = response.cachedAt {
            let stamp = DateFormatter.localizedString(from: cachedAt, dateStyle: .none, timeStyle: .medium)
            listingWarning.text = text("Zwischengespeicherter Stand von \(stamp). ", "Cached listing from \(stamp). ") + (response.warningKey.map { L10n.get($0) } ?? response.warning ?? "")
            listingWarning.isHidden = false
            scheduleListingRefresh(after: response.retryAfter ?? 10)
        } else {
            listingWarning.text = response.warningKey.map { L10n.get($0) } ?? response.warning
            listingWarning.isHidden = listingWarning.text == nil
        }
        applyListingOrder(); rebuildTree()
    }
#if DEBUG
    /// Only the separate native acceptance bundle can delay an actual provider
    /// response. Deliberately do not propagate cancellation into the hold: the
    /// test must release a late reply AFTER the user has navigated elsewhere.
    private func holdListingAcceptanceIfRequested(expected: UUID) async throws {
        guard Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests",
              let root = AppDelegate.macUITestRoot else { return }
        let flag = root.appendingPathComponent("HoldCloudListing.txt")
        guard let data = try? Data(contentsOf: flag), data.count <= 64,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let nonce = UUID(uuidString: value) else { return }
        try Data(nonce.uuidString.utf8).write(to: root.appendingPathComponent("CloudListingReady.txt"), options: .atomic)
        let released = await Task.detached(priority: .utility) {
            let deadline = Date().addingTimeInterval(90)
            while FileManager.default.fileExists(atPath: flag.path), Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return !FileManager.default.fileExists(atPath: flag.path)
        }.value
        let diagnostic = "\(nonce.uuidString) released=\(released) cancelled=\(Task.isCancelled) stale=\(readEpoch != expected)"
        try Data(diagnostic.utf8).write(to: root.appendingPathComponent("CloudListingReleased.txt"), options: .atomic)
        guard released else { throw CancellationError() }
    }
#endif
    @objc private func reload() {
        guard client != nil else { refreshControl?.endRefreshing(); return }
        recoveryOffered = false
        run(readOnly: true) { [weak self] in try await self?.load() }
    }
    @objc private func actions() {
        onActivate?()
        guard !busy else { return }
        let menu = UIAlertController(title: locationTitle, message: text("Dateien und Ordner direkt in OpenCommander. Vorschau, Kopieren, Verschieben und Drag-and-drop verwenden die normalen Bedienelemente.", "Files and folders directly in OpenCommander. Preview, copy, move and drag-and-drop use the regular controls."), preferredStyle: .actionSheet)
        if commander?.operationInProgress == true {
            menu.addAction(UIAlertAction(title: L10n.get("refresh"), style: .default) { [weak self] _ in self?.reload() })
            menu.addAction(UIAlertAction(title: L10n.get("cancel"), style: .cancel))
            if let popover = menu.popoverPresentationController {
                popover.sourceView = actionButton; popover.sourceRect = actionButton.bounds
            }
            present(menu, animated: true)
            return
        }
        if isOneDrive {
        menu.addAction(UIAlertAction(title: text("Mit Microsoft verbinden", "Connect to Microsoft"), style: .default) { [weak self] _ in self?.connect() })
        menu.addAction(UIAlertAction(title: text("Microsoft-App einrichten", "Configure Microsoft app"), style: .default) { [weak self] _ in self?.configure() })
        }
        if client != nil && authenticated {
            if !folders.isEmpty { menu.addAction(UIAlertAction(title: text("Übergeordneter Ordner", "Parent folder"), style: .default) { [weak self] _ in
                self?.navigateOnlineParent()
            }) }
            menu.addAction(UIAlertAction(title: text("Aktualisieren", "Refresh"), style: .default) { [weak self] _ in self?.reload() })
            menu.addAction(UIAlertAction(title: text("Neuer Ordner", "New folder"), style: .default) { [weak self] _ in self?.namePrompt(item: nil) })
            menu.addAction(UIAlertAction(title: text("Dateien / Ordner hochladen…", "Upload files / folders…"), style: .default) { [weak self] _ in
                guard let self else { return }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .folder], asCopy: false)
                picker.delegate = self; picker.allowsMultipleSelection = true
                self.present(picker, animated: true)
            })
            menu.addAction(UIAlertAction(title: text("Verbindung trennen", "Disconnect"), style: .destructive) { [weak self] _ in
                if self?.isOneDrive == false { self?.onClose?() } else { self?.disconnect() }
            })
        }
        menu.addAction(UIAlertAction(title: text("Abbrechen", "Cancel"), style: .cancel))
        if let item = selectedItems.first, let row = visibleItems.firstIndex(where: { $0.id == item.id }) {
            menu.addAction(UIAlertAction(title: text("Ausgewählte Datei / Ordner…", "Selected file / folder…"), style: .default) { [weak self] _ in self?.itemActions(item, row: IndexPath(row: row, section: 0)) })
        }
        menu.popoverPresentationController?.sourceView = actionButton
        menu.popoverPresentationController?.sourceRect = actionButton.bounds
        present(menu, animated: true)
    }
    private func configure() {
        let alert = UIAlertController(title: text("Microsoft-App-Registrierung", "Microsoft app registration"),
            message: text("Einmalige Entwickler-Einrichtung:\n\n1. Auf entra.microsoft.com → App-Registrierungen → Neue Registrierung: OpenCommander, auch persönliche Microsoft-Konten zulassen.\n2. Authentifizierung → Öffentliche Clientflows zulassen: Ja.\n3. API-Berechtigungen → Microsoft Graph → Delegiert: Files.ReadWrite.\n4. Application (client) ID hier einfügen. Kein Client-Secret und kein Passwort.\n\nDetails: docs/onedrive-online.md im Repository.",
                "One-time developer setup:\n\n1. entra.microsoft.com → App registrations → New registration: OpenCommander, allow personal Microsoft accounts too.\n2. Authentication → Allow public client flows: Yes.\n3. API permissions → Microsoft Graph → Delegated: Files.ReadWrite.\n4. Paste Application (client) ID below. No client secret or password.\n\nDetails: docs/onedrive-online.md in the repository."), preferredStyle: .alert)
        alert.addTextField { [weak self] field in
            field.placeholder = "Application (client) ID"; field.autocorrectionType = .no
            field.text = self?.client?.clientID
            field.accessibilityIdentifier = "OneDriveClientID"
        }
        alert.addAction(UIAlertAction(title: text("Speichern", "Save"), style: .default) { [weak self] _ in
            guard let self else { return }
            let id = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard OneDriveClient.validClientID(id) else { self.error(self.text("Die Client-ID muss eine gültige UUID sein.", "Client ID must be a valid UUID.")); return }
            self.client = OneDriveClient.browserClient(clientID: id)
            self.installListingObserver()
            UserDefaults.standard.set(id, forKey: self.clientIDKey)
            self.resetAccountView()
            self.connect()
        })
        alert.addAction(UIAlertAction(title: text("Anleitung öffnen", "Open instructions"), style: .default) { _ in
            DesktopBridge.shared?.openFile(URL(string: "https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app")!, application: nil) { _, _ in }
        })
        alert.addAction(UIAlertAction(title: text("Abbrechen", "Cancel"), style: .cancel))
        present(alert, animated: true)
    }
    private func connect() {
        guard let client else { configure(); return }
        run { [weak self] in
            guard let self else { return }
            self.signingIn = true
            defer { self.signingIn = false }
            let code = try await client.beginLogin()
            let alert = UIAlertController(title: self.text("Microsoft-Anmeldung", "Microsoft sign-in"),
                message: self.text("Öffne \(code.verification_uri) und gib diesen Code ein:\n\n\(code.user_code)\n\nPrüfe die angefragten Dateiberechtigungen. OpenCommander liest keine Browser-Passwörter.",
                    "Open \(code.verification_uri) and enter this code:\n\n\(code.user_code)\n\nReview the requested file permissions. OpenCommander does not read browser passwords."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: self.text("Code kopieren und Browser öffnen", "Copy code and open browser"), style: .default) { _ in
                UIPasteboard.general.string = code.user_code
                if let url = URL(string: code.verification_uri), url.scheme == "https", url.host == "microsoft.com" || url.host?.hasSuffix(".microsoft.com") == true {
                    DesktopBridge.shared?.openFile(url, application: nil) { _, _ in }
                }
            })
            alert.addAction(UIAlertAction(title: self.text("Abbrechen", "Cancel"), style: .cancel) { [weak self] _ in self?.work?.cancel() })
            self.present(alert, animated: true)
            self.message.text = self.text("Warte auf Microsoft-Anmeldung…", "Waiting for Microsoft sign-in…")
            do {
                try await client.completeLogin(code)
                if self.presentedViewController === alert { await self.dismissAsync() }
                try await self.load()
            } catch {
                if self.presentedViewController === alert { await self.dismissAsync() }
                throw error
            }
        }
    }
    private func dismissAsync() async {
        await withCheckedContinuation { continuation in dismiss(animated: true) { continuation.resume() } }
    }
    private func disconnect() {
        let alert = UIAlertController(title: text("OneDrive trennen?", "Disconnect OneDrive?"), message: text("Die gespeicherte Anmeldung wird aus dem Schlüsselbund entfernt. Online-Dateien werden nicht gelöscht.", "The saved sign-in is removed from Keychain. Online files are not deleted."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text("Trennen", "Disconnect"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try self.client?.disconnect(); self.resetAccountView()
                self.message.text = self.text("Verbindung getrennt.", "Disconnected.")
            } catch { self.error(HistoryFailure.presentation(error)) }
        })
        alert.addAction(UIAlertAction(title: text("Abbrechen", "Cancel"), style: .cancel))
        present(alert, animated: true)
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tableView === treeView ? treeRows.count : visibleItems.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = OneDriveCell(style: .default, reuseIdentifier: nil)
        let theme = palette
        if tableView === treeView {
            let path = treeRows[indexPath.row], id = key(path)
            cell.activateEntry = { [weak self, weak tableView] in
                guard let self, let tableView, let row = self.treeRows.firstIndex(where: { self.key($0) == id }) else { return }
                self.tableView(tableView, didSelectRowAt: IndexPath(row: row, section: 0))
            }
            cell.textLabel?.text = String(repeating: "  ", count: path.count) + (expanded.contains(id) ? "▼ " : "▶ ") + (path.last?.name ?? locationTitle)
            cell.textLabel?.font = .systemFont(ofSize: 12); cell.textLabel?.textColor = theme.primaryText
            cell.backgroundColor = id == key(folders) ? theme.selectionBackground : .clear
            cell.accessibilityIdentifier = "OneDriveTree-\(id)"
            return cell
        }
        let item = visibleItems[indexPath.row]
        cell.activateEntry = { [weak self, weak tableView] in
            guard let self, let tableView, let row = self.visibleItems.firstIndex(where: { $0.id == item.id }) else { return }
            (tableView as? CommanderSelectionTableView)?.resetSelectionModifiers()
            self.tableView(tableView, didSelectRowAt: IndexPath(row: row, section: 0))
        }
        let row = UIStackView(); row.spacing = 4; row.alignment = .center; row.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: item.isFolder ? "folder.fill" : "doc"))
        icon.tintColor = item.isFolder ? .systemOrange : .systemBlue
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        row.addArrangedSubview(icon)
        for (index, value) in [item.name, item.isFolder ? "DIR" : item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—",
            item.isFolder ? "DIR" : (item.name as NSString).pathExtension.uppercased(),
            OnlineDisplayPolicy.modifiedDate(item.lastModifiedDateTime)].enumerated() {
            let label = UILabel(); label.text = value; label.font = .systemFont(ofSize: index == 0 ? 12 : 10)
            label.textColor = index == 0 ? theme.primaryText : theme.secondaryText
            if index > 0 { label.widthAnchor.constraint(equalToConstant: [0,90,70,125][index]).isActive = true; label.textAlignment = .center }
            else { label.lineBreakMode = .byTruncatingMiddle; label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
            row.addArrangedSubview(label)
        }
        cell.contentView.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor), row.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)])
        cell.backgroundColor = selectedIDs.contains(item.id) ? theme.selectionBackground : theme.fileBackground
        cell.isAccessibilityElement = true; cell.accessibilityLabel = item.name
        cell.accessibilityIdentifier = "OneDriveFile-\(item.id)"
        cell.accessibilityTraits = selectedIDs.contains(item.id) ? [.button, .selected] : [.button]
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        commander?.view.endEditing(true)
        tableView.deselectRow(at: indexPath, animated: false)
        onActivate?()
        guard !busy else { return }
        if tableView === treeView {
            let path = treeRows[indexPath.row], id = key(path)
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            if id == key(folders) { rebuildTree() } else { navigate(path) }
        } else {
            guard visibleItems.indices.contains(indexPath.row) else { return }
            let item = visibleItems[indexPath.row]
            let modifiers = (tableView as? CommanderSelectionTableView)?.consumeSelectionModifiers() ?? []
            let selection = DesktopInteractionPolicy.selection(clicked: item.id, visible: visibleItems.map(\.id), selected: selectedIDs,
                anchor: selectionAnchor, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command))
            selectedIDs = selection.keys; selectionAnchor = selection.anchor
            // Selection styling must not replace the potential drag-source cell.
            for cell in tableView.visibleCells {
                guard let index = tableView.indexPath(for: cell), visibleItems.indices.contains(index.row) else { continue }
                let selected = selectedIDs.contains(visibleItems[index.row].id)
                cell.backgroundColor = selected ? commander?.theme.selectionBackground : commander?.theme.fileBackground
                cell.accessibilityTraits = selected ? [.button, .selected] : [.button]
            }
            updateNavigation(); onActivate?()
        }
    }
    private func itemActions(_ item: OneDriveItem, row: IndexPath) {
        let alert = UIAlertController(title: item.name, message: nil, preferredStyle: .actionSheet)
        selectedIDs = [item.id]; tableView.reloadData(); updateNavigation(); onActivate?()
        if !item.isFolder {
            alert.addAction(UIAlertAction(title: L10n.get("preview"), style: .default) { [weak self] _ in self?.openOnline(item, externally: false) })
            alert.addAction(UIAlertAction(title: L10n.get("open"), style: .default) { [weak self] _ in self?.openOnline(item, externally: true) })
            alert.addAction(UIAlertAction(title: text("Herunterladen…", "Download…"), style: .default) { [weak self] _ in
                self?.run { [weak self] in
                    guard let self, let client = self.client else { return }
                    self.cleanExport()
                    let url = try await client.download(item)
                    self.exportedURL = url
                    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                    picker.delegate = self
                    self.present(picker, animated: true)
                }
            })
        }
        alert.addAction(UIAlertAction(title: L10n.get("copy"), style: .default) { [weak self] _ in self?.copyOnlineSelection(move: false) })
        alert.addAction(UIAlertAction(title: L10n.get("cut"), style: .default) { [weak self] _ in self?.copyOnlineSelection(move: true) })
        alert.addAction(UIAlertAction(title: text("Umbenennen", "Rename"), style: .default) { [weak self] _ in self?.namePrompt(item: item) })
        alert.addAction(UIAlertAction(title: deleteTitle, style: .destructive) { [weak self] _ in self?.confirmRecycle(item) })
        alert.addAction(UIAlertAction(title: text("Abbrechen", "Cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = tableView
        alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: row)
        present(alert, animated: true)
    }
    private func namePrompt(item: OneDriveItem?) {
        let alert = UIAlertController(title: item == nil ? text("Neuer Ordner", "New folder") : text("Umbenennen", "Rename"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = item?.name }
        alert.addAction(UIAlertAction(title: text("Speichern", "Save"), style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            self?.run(historyAction: item == nil ? "folder" : "rename_button") { [weak self] in
                guard let self, let client = self.client else { return }
                if let item {
                    let account = try await client.accountIdentity()
                    let content = try await CommanderOnlineTools.contentSnapshot(client, item: item)
                    let parent = try await client.metadata(item.id).parentReference?.id
                    let parentPath = try client.persistentPath(parent)
                    try await client.rename(item, to: name)
                    let undo = try PersistentOnlineUndo.relocation(client, current: await client.metadata(item.id), content: content,
                        parent: parent, parentPath: parentPath, name: item.name, account: account)
                    self.record(L10n.get("rename_button"), source: self.onlineLocation(item.name), destination: self.onlineLocation(name), undo: undo)
                }
                else {
                    let account = try await client.accountIdentity(), parent = self.folders.last?.id
                    try await client.createFolder(name, parent: parent)
                    // Only the verified empty folder is removable by Undo.
                    // Later child additions invalidate its persisted proof.
                    let undo = try await PersistentOnlineUndo.uploaded(client, parent: parent, name: name,
                        content: ["": "directory"], account: account)
                    self.record(L10n.get("folder"), source: self.onlineLocation(), destination: self.onlineLocation(name), undo: undo)
                }
                try await self.load()
            }
        })
        alert.addAction(UIAlertAction(title: text("Abbrechen", "Cancel"), style: .cancel))
        present(alert, animated: true)
    }
    private func recycleWithUndo(_ client: any CommanderOnlineClient, item: OneDriveItem) async throws -> CloudUndoPayload? {
        if let cloud = client as? CloudFileClient { return try await PersistentOnlineUndo.cloudRecoveryDelete(cloud, item: item) }
        try await client.recycle(item)
        return nil // Provider trash or explicitly confirmed permanent server deletion.
    }
    private func confirmRecycle(_ item: OneDriveItem) {
        let alert = UIAlertController(title: deleteTitle, message: item.name, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text("Verschieben", "Move"), style: .destructive) { [weak self] _ in
            self?.run(historyAction: "delete") { [weak self] in
                guard let self, let client = self.client else { return }
                let undo = try await self.recycleWithUndo(client, item: item)
                self.record(self.deleteTitle, source: self.onlineLocation(item.name), destination: client.moveBackupLocation ?? (self.isOneDrive ? "OneDrive Papierkorb / Recycle bin" : L10n.get("remote_deleted")), undo: undo)
                self.rememberRecovery(client, source: self.onlineLocation(item.name))
                try await self.load()
            }
        })
        alert.addAction(UIAlertAction(title: text("Abbrechen", "Cancel"), style: .cancel))
        present(alert, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exportedURL != nil {
            let shouldOpen = openAfterExport
            cleanExport()
            if shouldOpen, let saved = urls.first { commander?.openDesktopEntry(FileEntry(url: saved, parent: nil)) }
            return
        }
        receiveLocal(urls)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cleanExport() }
    private func cleanExport() {
        openAfterExport = false
        if let exportedURL {
            // Only remove the unique temporary directory created by this download.
            try? FileManager.default.removeItem(at: exportedURL.deletingLastPathComponent())
            self.exportedURL = nil
        }
    }
}

extension OneDriveBrowser: UITableViewDragDelegate, UITableViewDropDelegate {
    /// Complete the destination first. A failed/cancelled operation never
    /// removes its source; an unfinished folder may remain at the destination.
    func receiveLocal(_ urls: [URL], parent: String? = nil, useCurrentFolder: Bool = true, move: Bool = false, completion: @escaping () -> Void = {}) {
        guard !busy, authenticated, !urls.isEmpty, commander?.operationInProgress != true else { completion(); return }
        let destination = useCurrentFolder ? folders.last?.id : parent
        guard commander?.allowTransferPaths(reading: move ? [] : urls, writing: move ? urls : []) != false else { completion(); return }
        run(transfer: true, historyAction: move ? "move" : "copy") { [weak self] in
            defer { completion() }
            guard let self, let client = self.client else { return }
            let account = try await client.accountIdentity()
            for (index, url) in urls.enumerated() {
                self.activeOperationPaths = (url.path, try await self.destinationLocation(destination, name: url.lastPathComponent))
                self.transferProgress(index, total: urls.count, name: url.lastPathComponent)
                try Task.checkCancellation()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let folder = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                guard let plan = try await self.destinationPlan(url.lastPathComponent, folder: folder, parent: destination, allowReplacement: true) else { continue }
                let name = plan.name
                let targetLocation = try await self.destinationLocation(destination, name: name)
                self.activeOperationPaths = (url.path, targetLocation)
                let before = try await RemoteContent.snapshotAsync(url)
                let container = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCommander-OneDrive-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: container) }
                let staged = container.appendingPathComponent(name)
                try await Task.detached { try FileManager.default.copyItem(at: url, to: staged) }.value
                let preparedSnapshot = try await RemoteContent.snapshotAsync(staged)
                guard preparedSnapshot == before else { throw OneDriveFailure.message("Source changed while preparing transfer. Source retained.") }
                var undo: CloudUndoPayload?
                var replacementJob: PendingCloudReplacement.Job?
                if let existing = plan.replacing {
                    if move {
                        let job = try await PendingCloudReplacement.prepare(staged, sourceLocation: url.path, existing: existing, client: client,
                            parent: destination, moveOriginal: url, moveDestination: targetLocation)
                        let undo = try await PendingCloudReplacement.resumeMove(job, client: client)
                        self.record(L10n.get("move"), source: url.path, destination: targetLocation, undo: undo)
                        try PendingCloudReplacement.finish(job)
                        continue
                    }
                    let job = try await PendingCloudReplacement.prepare(staged, sourceLocation: url.path, existing: existing, client: client, parent: destination)
                    replacementJob = job
                    let replacement = try await PendingCloudReplacement.resume(job, client: client)
                    undo = try PersistentOnlineUndo.replacement(client, record: replacement, account: account)
                    self.record(L10n.get("remote_recovery"), source: targetLocation, destination: try await self.destinationLocation(destination, name: replacement.previous.name))
                } else {
                    if !move {
                        let job = try await PendingCloudUpload.prepare(staged, source: url.path, client: client, parent: destination, account: account)
                        undo = try await PendingCloudUpload.resume(job, client: client)
                        self.record(L10n.get("copy"), source: url.path, destination: targetLocation, undo: undo)
                        try PendingCloudUpload.finish(job)
                        continue
                    }
                    let job = try await PendingCloudUpload.prepare(staged, source: url.path, client: client,
                        parent: destination, account: account, moveOriginal: url, moveDestination: targetLocation)
                    let moveUndo = try await PendingCloudUpload.resumeMove(job, client: client)
                    self.record(L10n.get("move"), source: url.path, destination: targetLocation, undo: moveUndo)
                    try PendingCloudUpload.finish(job)
                    continue
                }
                self.record(L10n.get("copy"), source: url.path, destination: targetLocation, undo: move ? nil : undo)
                if let replacementJob { try PendingCloudReplacement.finish(replacementJob) }
                if move {
                    try Task.checkCancellation()
                    let currentSnapshot = try await RemoteContent.snapshotAsync(url)
                    guard currentSnapshot == before else { throw OneDriveFailure.message("Source changed during transfer. Both copies retained.") }
                    guard let undo else { throw CloudConnection.failure("cloud_undo_changed") }
                    let job = try await PendingLocalCloudMove.prepare(url, uploaded: undo, destinationLocation: targetLocation)
                    let moveUndo = try await PendingLocalCloudMove.resume(job, client: client)
                    self.record(L10n.get("move"), source: url.path, destination: targetLocation, undo: moveUndo)
                    try PendingLocalCloudMove.finish(job)
                }
            }
            try await self.load()
        }
    }
    func receiveOnline(_ selection: OneDriveSelection, parent: String? = nil, useCurrentFolder: Bool = true, move: Bool) {
        let source = selection.browser
        guard !busy, authenticated, selection.generation == source.generation, !selection.items.isEmpty else { return }
        let destination = useCurrentFolder ? folders.last?.id : parent
        run(transfer: true, historyAction: move ? "move" : "copy") { [weak self] in
            guard let self, let targetClient = self.client, let sourceClient = source.client else { return }
            let sourceAccount = try await sourceClient.accountIdentity(), targetAccount = try await targetClient.accountIdentity()
            self.observeTransfer(sourceClient)
            defer { self.stopObservingTransfer(sourceClient) }
            for (index, item) in selection.items.enumerated() {
                self.activeOperationPaths = (try await source.destinationLocation(selection.parentID, name: item.name), try await self.destinationLocation(destination, name: item.name))
                self.transferProgress(index, total: selection.items.count, name: item.name)
                try Task.checkCancellation()
                let sourceLocation = try await source.destinationLocation(selection.parentID, name: item.name)
                // Validate ancestors with metadata, including collapsed/unloaded
                // tree targets. Never copy a folder into itself or descendants.
                // Two panes may use the same provider implementation while
                // being signed into different accounts. Only treat a move as
                // an in-provider atomic relocation when both the connection
                // identity and the account behind that connection match.
                let sameConnection = targetClient.clientID == sourceClient.clientID && targetAccount == sourceAccount
                if sameConnection { try await targetClient.validateDestination(destination, excluding: item.id) }
                guard let plan = try await self.destinationPlan(item.name, folder: item.isFolder, parent: destination, excluding: move && sameConnection ? item.id : nil, allowReplacement: true) else { continue }
                let name = plan.name
                let targetLocation = try await self.destinationLocation(destination, name: name)
                self.activeOperationPaths = (sourceLocation, targetLocation)
                if move, let replacing = plan.replacing {
                    let job = try await PendingCrossCloudMove.prepare(item, source: sourceClient, target: targetClient,
                        parent: destination, name: name, sourceLocation: sourceLocation, destinationLocation: targetLocation, replacing: replacing)
                    let undo = try await PendingCrossCloudMove.resume(job, source: sourceClient, target: targetClient)
                    self.record(L10n.get("move"), source: sourceLocation, destination: targetLocation, undo: undo)
                    try PendingCrossCloudMove.finish(job)
                    continue
                }
                if move && sameConnection {
                    let content = try await CommanderOnlineTools.contentSnapshot(sourceClient, item: item)
                    let parentPath = try sourceClient.persistentPath(selection.parentID)
                    // Name and parent change atomically; never rename the source first.
                    do { try await sourceClient.move(item, parent: destination, name: name) }
                    catch { self.rememberRecovery(sourceClient, source: sourceLocation); throw error }
                    let undo = try PersistentOnlineUndo.relocation(sourceClient, current: await sourceClient.metadata(item.id), content: content,
                        parent: selection.parentID, parentPath: parentPath, name: item.name, account: sourceAccount)
                    self.record(L10n.get("move"), source: sourceLocation, destination: targetLocation, undo: undo)
                    self.rememberRecovery(sourceClient, source: sourceLocation)
                } else {
                    if move {
                        let job = try await PendingCrossCloudMove.prepare(item, source: sourceClient, target: targetClient,
                            parent: destination, name: name, sourceLocation: sourceLocation, destinationLocation: targetLocation)
                        let undo = try await PendingCrossCloudMove.resume(job, source: sourceClient, target: targetClient)
                        self.record(L10n.get("move"), source: sourceLocation, destination: targetLocation, undo: undo)
                        try PendingCrossCloudMove.finish(job)
                        self.rememberRecovery(sourceClient, source: sourceLocation)
                        continue
                    }
                    let snapshot = move ? try await sourceClient.remoteSnapshot(item) : [:]
                    let url = try await sourceClient.downloadTree(item)
                    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    let content = try await Task.detached { try RemoteContent.snapshot(url) }.value
                    if move, !(sourceClient is OneDriveClient), content != snapshot { throw RemoteConnection.failure("remote_changed") }
                    let staged = url.deletingLastPathComponent().appendingPathComponent(name)
                    if staged != url { try FileManager.default.moveItem(at: url, to: staged) }
                    var undo: CloudUndoPayload?
                    var replacementJob: PendingCloudReplacement.Job?
                    if let existing = plan.replacing {
                        let job = try await PendingCloudReplacement.prepare(staged, sourceLocation: sourceLocation, existing: existing, client: targetClient, parent: destination)
                        replacementJob = job
                        let replacement = try await PendingCloudReplacement.resume(job, client: targetClient)
                        undo = try PersistentOnlineUndo.replacement(targetClient, record: replacement, account: targetAccount)
                        self.record(L10n.get("remote_recovery"), source: targetLocation, destination: try await self.destinationLocation(destination, name: replacement.previous.name))
                    } else {
                        if !move {
                            let job = try await PendingCloudUpload.prepare(staged, source: sourceLocation, client: targetClient, parent: destination, account: targetAccount)
                            undo = try await PendingCloudUpload.resume(job, client: targetClient)
                            self.record(L10n.get("copy"), source: sourceLocation, destination: targetLocation, undo: undo)
                            try PendingCloudUpload.finish(job)
                            continue
                        }
                        try await targetClient.uploadTree(staged, parent: destination)
                        undo = try await PersistentOnlineUndo.uploaded(targetClient, parent: destination, name: name, content: content, account: targetAccount)
                    }
                    self.record(L10n.get("copy"), source: sourceLocation, destination: targetLocation, undo: move ? nil : undo)
                    if let replacementJob { try PendingCloudReplacement.finish(replacementJob) }
                    if move {
                        // Verify the complete destination before changing the source.
                        guard let uploaded = try await targetClient.children(of: destination).first(where: { $0.name == name }) else { throw RemoteConnection.failure("remote_changed") }
                        let verified = try await targetClient.downloadTree(uploaded)
                        defer { try? FileManager.default.removeItem(at: verified.deletingLastPathComponent()) }
                        guard try await Task.detached(operation: { try RemoteContent.snapshot(verified) }).value == content else { throw RemoteConnection.failure("remote_changed") }
                        guard let undo else { throw CloudConnection.failure("cloud_undo_changed") }
                        guard try await sourceClient.accountIdentity() == sourceAccount else { throw CloudConnection.failure("cloud_undo_account") }
                        let job = try await PendingOnlineMove.prepare(sourceClient, item: item, content: content, uploaded: undo,
                            sourceLocation: sourceLocation, destinationLocation: targetLocation)
                        let moveUndo = try await PendingOnlineMove.resume(job, client: sourceClient, targetClient: targetClient)
                        self.record(L10n.get("move"), source: sourceLocation, destination: targetLocation,
                            undo: moveUndo)
                        try PendingOnlineMove.finish(job)
                        self.rememberRecovery(sourceClient, source: sourceLocation)
                    }
                }
            }
            if Self.clipboard?.selection === selection, move { Self.clipboard = nil }
            self.treeChildren = [:]; source.treeChildren = [:]
            try await self.load()
            if source !== self { try await source.load() }
        }
    }
    func exportOnline(_ selection: OneDriveSelection, to directory: URL, move: Bool) {
        guard !busy, selection.generation == generation, !selection.items.isEmpty else { return }
        guard commander?.allowTransferPaths(writing: selection.items.map { directory.appendingPathComponent($0.name) }) != false else { return }
        run(transfer: true, historyAction: move ? "move" : "copy") { [weak self] in
            try await self?.exportOnlineItems(selection, to: directory, move: move)
        }
    }
    private func exportOnlineItems(_ selection: OneDriveSelection, to directory: URL, move: Bool) async throws {
            guard let client = self.client else { return }
            guard commander?.allowTransferPaths(writing: selection.items.map { directory.appendingPathComponent($0.name) }) != false else { throw CancellationError() }
            let scope = directory.startAccessingSecurityScopedResource()
            defer { if scope { directory.stopAccessingSecurityScopedResource() } }
            for (index, item) in selection.items.enumerated() {
                self.activeOperationPaths = (try await self.destinationLocation(selection.parentID, name: item.name), directory.appendingPathComponent(item.name).path)
                self.transferProgress(index, total: selection.items.count, name: item.name)
                try Task.checkCancellation()
                let sourceLocation = try await self.destinationLocation(selection.parentID, name: item.name)
                let snapshot = move ? try await client.remoteSnapshot(item) : [:]
                let checkpoint: PendingCloudDownload.Job? = try await PendingCloudDownload.prepare(item, client: client, destination: directory, move: move)
                let url: URL
                if let checkpoint { url = try await PendingCloudDownload.resume(checkpoint, client: client) }
                else { url = try await client.downloadTree(item) }
                defer { if checkpoint == nil { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
                let content = try await Task.detached { try RemoteContent.snapshot(url) }.value
                if move, !(client is OneDriveClient), content != snapshot { throw RemoteConnection.failure("remote_changed") }
                var name = item.name, replace = false
                if SafeFileOperations.exists(directory.appendingPathComponent(name)) {
                    let names = try await Task.detached { try FileManager.default.contentsOfDirectory(atPath: directory.path) }.value
                    let alternative = OneDriveConflictNames.available(name, folder: item.isFolder, existing: names)
                    switch try await self.conflictChoice(name: name, alternative: alternative, canReplace: true) {
                    case .keepBoth: name = alternative
                    case .replace: replace = true
                    case .skip:
                        if let checkpoint { try PendingCloudDownload.finish(checkpoint) }
                        continue
                    case .cancel: throw CancellationError()
                    }
                }
                let destination = directory.appendingPathComponent(name)
                if let checkpoint { _ = try PendingCloudDownload.destination(checkpoint) }
                self.activeOperationPaths = (sourceLocation, destination.path)
                let replacing = replace
                let worker = Task.detached { () throws -> FileUndoRecord in
                    let original = replacing ? try SafeFileOperations.snapshot(destination) : nil
                    let backup = try SafeFileOperations.copyReplacing(source: url, destination: destination, replace: replacing,
                        recoveryRoot: HostFileSystem.isCloudStorage(destination) ? SafeFileOperations.privateRecoveryRoot() : nil,
                        copy: { source, payload in
                            try Task.checkCancellation(); try FileManager.default.copyItem(at: source, to: payload)
                            guard try RemoteContent.snapshot(payload) == content else { throw RemoteConnection.failure("remote_changed") }
                            if let original, try SafeFileOperations.snapshot(destination) != original { throw SafeFileOperations.conflict(destination) }
                        }, publish: { payload, target in
                            try Task.checkCancellation()
                            if let original {
                                let previous = payload.deletingLastPathComponent().appendingPathComponent("previous")
                                guard try SafeFileOperations.snapshot(previous, rootName: target.lastPathComponent) == original else { throw SafeFileOperations.conflict(target) }
                            }
                            try FileManager.default.moveItem(at: payload, to: target)
                        })
                    let record = FileUndoRecord(source: url, destination: destination, replacedBackup: backup)
                    record.displaySource = sourceLocation
                    return record
                }
                let record = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                if !move { self.commander?.operationHistory.append(.copy(files: [record])) }
                // The local copy record already includes the online display
                // source and working Undo. Do not add a duplicate disabled row.
                if move { self.record(L10n.get("copy"), source: sourceLocation, destination: destination.path) }
                if let checkpoint, !move { try PendingCloudDownload.finish(checkpoint) }
                if move {
                    guard try await client.remoteSnapshot(item) == snapshot else { throw CloudConnection.failure("cloud_undo_changed") }
                    guard let checkpoint else { throw CloudConnection.failure("cloud_undo_changed") }
                    let moveUndo = try await PendingCloudDownload.completeMove(checkpoint, client: client, record: record, sourceLocation: sourceLocation)
                    self.record(L10n.get("move"), source: sourceLocation, destination: destination.path,
                        undo: moveUndo)
                    try PendingCloudDownload.finish(checkpoint)
                }
            }
            if Self.clipboard?.selection === selection, move { Self.clipboard = nil }
            self.treeChildren = [:]; try await self.load()
    }
    func receiveProviders(_ providers: [NSItemProvider], parent: String? = nil, useCurrentFolder: Bool = true, forceCopy: Bool = false, moveOverride: Bool? = nil) {
        guard !busy, authenticated, commander?.operationInProgress != true else { return }
        let target = useCurrentFolder ? folders.last?.id : parent
        let move = !forceCopy && (moveOverride ?? (commander?.moveMode == true))
        let expectedGeneration = generation
        // Prevent navigation changing the destination while provider loading.
        busy = true; updateNavigation()
        FileDropTransfer.load(providers) { [weak self] result in
            guard let self else { return }
            self.busy = false; self.updateNavigation()
            guard self.generation == expectedGeneration else {
                if case .success(let batch) = result { batch.releaseResources() }
                return
            }
            switch result {
            case .failure(let error): self.error(HistoryFailure.presentation(error))
            case .success(let batch):
                if move && batch.items.contains(where: { !$0.isOriginal }) {
                    batch.releaseResources(); self.error(L10n.get("drop_original_unavailable")); return
                }
                self.receiveLocal(batch.items.map(\.url), parent: target, useCurrentFolder: false, move: move) { batch.releaseResources() }
            }
        }
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard tableView === self.tableView, visibleItems.indices.contains(indexPath.row), !busy else { return nil }
        let item = visibleItems[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu() }
            self.selectedIDs = [item.id]; self.tableView.reloadData(); self.updateNavigation(); self.onActivate?()
            var actions = [UIAction(title: L10n.get("open"), image: UIImage(systemName: "arrow.up.forward.app")) { [weak self] _ in self?.openOnlineSelection() }]
            actions.append(UIAction(title: self.text("Pfad kopieren", "Copy path")) { [weak self] _ in
                guard let self else { return }; UIPasteboard.general.string = self.onlineLocation(item.name)
            })
            if self.client is OneDriveClient || (self.client as? CloudFileClient)?.supportsSharingLink == true {
                actions.append(UIAction(title: self.text("Freigabelink erstellen …", "Create sharing link…"), image: UIImage(systemName: "link")) { [weak self] _ in self?.confirmShareLink(item) })
            }
            if self.client is OneDriveClient {
                actions.append(UIAction(title: self.text("OneDrive-Webseite öffnen", "Open OneDrive website")) { _ in UIApplication.shared.open(URL(string: "https://onedrive.live.com/")!) })
            } else if let website = self.cloudProfile?.website {
                actions.append(UIAction(title: self.text("Anbieter-Webseite öffnen", "Open provider website")) { _ in UIApplication.shared.open(website) })
            }
            if !item.isFolder { actions.append(UIAction(title: L10n.get("preview"), image: UIImage(systemName: "eye")) { [weak self] _ in self?.previewOnlineSelection() }) }
            if !item.isFolder && CommanderNativeArchive.supports(item.name) {
                actions.append(UIAction(title: L10n.get("extract_archive"), image: UIImage(systemName: "archivebox")) { [weak self] _ in self?.extractOnlineSelection() })
            }
            actions += [UIAction(title: L10n.get("copy")) { [weak self] _ in self?.copyOnlineSelection(move: false) },
                        UIAction(title: L10n.get("cut")) { [weak self] _ in self?.copyOnlineSelection(move: true) },
                        UIAction(title: L10n.get("paste")) { [weak self] _ in self?.commander?.pasteClipboard() },
                        UIAction(title: L10n.get("rename_button")) { [weak self] _ in self?.renameOnlineSelection() },
                        UIAction(title: L10n.get("duplicate")) { [weak self] _ in self?.duplicateOnlineSelection() },
                        UIAction(title: L10n.get("file_info")) { [weak self] _ in self?.infoOnlineSelection() },
                        UIAction(title: self.deleteTitle, attributes: .destructive) { [weak self] _ in self?.deleteOnlineSelection() }]
            return UIMenu(children: actions)
        }
    }
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        CommanderDragDiagnostics.event("online drag beginning")
        guard !busy, authenticated, commander?.operationInProgress != true else { return [] }
        let dragged: [OneDriveItem]
        if tableView === treeView {
            guard let item = treeRows[indexPath.row].last else { return [] }; dragged = [item]
        } else {
            let item = visibleItems[indexPath.row]
            if !selectedIDs.contains(item.id) { selectedIDs = [item.id] }
            dragged = selectedItems
            // Replacing the source cell here can cancel a Catalyst drag before
            // UIKit has installed its lift preview. Update controls, not rows.
            updateNavigation(); onActivate?(); onStateChanged?()
        }
        session.localContext = self
        return dragged.map { item in
            let payload = OneDriveSelection(browser: self, items: [item], generation: generation)
            if tableView === treeView { payload.parentID = treeRows[indexPath.row].dropLast().last?.id }
            let provider = NSItemProvider()
            provider.suggestedName = item.name
            // Export the item as a file, including text files; inline text is
            // not a file promise that Finder can save as a named document.
            provider.preferredPresentationStyle = .attachment
            let type = item.isFolder ? UTType.folder : (UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data)
            let loadFile: (@escaping (URL?, Error?) -> Void) -> Progress = { [self] completion in
                let progress = Progress(totalUnitCount: 1)
                let task = Task { @MainActor in
                    do {
                        guard payload.generation == self.generation, let client = self.client else { throw OneDriveFailure.message("The OneDrive connection changed.") }
                        guard self.previewURLs.count < 128, self.retainedDragBytes < 1024 * 1024 * 1024 else { throw CloudConnection.failure("cloud_limit") }
                        let url = try await client.downloadTree(item)
                        do {
                            let size = try await Task.detached { try BoundedFolderSize.bytes(at: url) }.value
                            guard self.previewURLs.count < 128,
                                  size <= 1024 * 1024 * 1024 - self.retainedDragBytes else { throw CloudConnection.failure("cloud_limit") }
                            guard payload.generation == self.generation else { throw CloudConnection.failure("cloud_config_changed") }
                            try Task.checkCancellation()
                            self.retainedDragBytes += size
                        } catch { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); throw error }
                        self.previewURLs.append(url)
                        CommanderDragDiagnostics.event("online drag file prepared")
                        completion(url, nil); progress.completedUnitCount = 1
                    } catch { completion(nil, error) }
                }
                progress.cancellationHandler = { task.cancel() }
                return progress
            }
            // Catalyst resolves public.file-url synchronously on its main thread.
            // Never publish a lazy URL that needs MainActor to finish downloading:
            // that blocks the drag loop and prevents the callback from running.
            provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
                loadFile { url, error in completion(url, false, error) }
            }
            let drag = UIDragItem(itemProvider: provider); drag.localObject = payload; return drag
        }
    }
    func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
        guard !busy, authenticated, commander?.operationInProgress != true, !session.items.isEmpty else { return false }
        return session.items.allSatisfy { OneDriveSelection.resolve($0) != nil || FileEntry.resolveDrag($0) != nil || FileDropTransfer.canLoad($0.itemProvider) }
    }
    private func dropParent(_ table: UITableView, session: UIDropSession) -> String? {
        let point = FileDropTransfer.location(session, in: table)
        guard CommanderVisibleHit.contains(point, in: table) else { return nil }
        if let row = table.indexPathForRow(at: point) {
            if table === treeView { return treeRows.indices.contains(row.row) ? treeRows[row.row].last?.id : nil }
            if visibleItems.indices.contains(row.row), visibleItems[row.row].isFolder { return visibleItems[row.row].id }
        }
        return folders.last?.id
    }
    func nativeFileDrop(_ point: CGPoint, urls: [URL], modifiers: Int, commit: Bool) -> Bool {
        guard !urls.isEmpty else { stopDropHover(); return false }
        guard !busy, authenticated, let window = view.window else { return false }
        let location = CGPoint(x: point.x * window.bounds.width, y: point.y * window.bounds.height)
        for table in [tableView, treeView] {
            let local = table.convert(location, from: window)
            guard CommanderVisibleHit.contains(local, in: table) else { continue }
            var parent = folders.last?.id
            if let row = table.indexPathForRow(at: local) {
                if table === treeView {
                    guard treeRows.indices.contains(row.row) else { return false }
                    parent = treeRows[row.row].last?.id
                } else if visibleItems.indices.contains(row.row), visibleItems[row.row].isFolder {
                    parent = visibleItems[row.row].id
                }
            } else if table === treeView { return false }
            if commit {
                stopDropHover()
                onActivate?()
                receiveProviders(urls.map { FileDropTransfer.provider(for: $0) }, parent: parent, useCurrentFolder: false,
                    moveOverride: FileDropAction.externalMove(modifiers: modifiers, moveMode: commander?.moveMode == true))
            } else {
                dropTable = table; dropSession = nil; nativeDropPoint = location
                let row = table.indexPathForRow(at: local)
                let path = table === treeView ? row.flatMap { treeRows.indices.contains($0.row) ? treeRows[$0.row] : nil } : nil
                trackDropPath(path)
            }
            return true
        }
        stopDropHover(); return false
    }
    private func dropPath(_ table: UITableView, session: UIDropSession) -> [OneDriveItem]? {
        // UIKit can deliver the last hovered table's callback while a native
        // AppKit promise crosses the divider. A row's vertical hit alone must
        // never redirect a drop into a tree folder outside the pointer bounds.
        let point = FileDropTransfer.location(session, in: table)
        guard CommanderVisibleHit.contains(point, in: table) else { return nil }
        if let row = table.indexPathForRow(at: point) {
            if table === treeView { return treeRows.indices.contains(row.row) ? treeRows[row.row] : nil }
            if visibleItems.indices.contains(row.row), visibleItems[row.row].isFolder { return folders + [visibleItems[row.row]] }
        }
        return table === treeView ? nil : folders
    }
    private func allowsDrop(_ table: UITableView, session: UIDropSession) -> Bool {
        guard let path = dropPath(table, session: session) else { return false }
        let selected = session.items.compactMap { OneDriveSelection.resolve($0) }
        let sameAccount = selected.filter { $0.browser.client === client }
        if sameAccount.contains(where: { $0.generation != $0.browser.generation }) { return false }
        let ancestors = Set(path.map(\.id))
        if sameAccount.contains(where: { $0.items.contains(where: { $0.isFolder && ancestors.contains($0.id) }) }) { return false }
        if sameAccount.count == session.items.count, sameAccount.allSatisfy({ $0.parentID == path.last?.id }) { return false }
        return true
    }
    private func stopDropHover() {
        dropHoverWork?.cancel(); dropHoverWork = nil; dropTreeRead?.cancel(); dropTreeRead = nil; dropHoverKey = nil
        dropScrollTimer?.invalidate(); dropScrollTimer = nil; dropTable = nil; dropSession = nil; nativeDropPoint = nil
    }
    private func trackDrop(_ table: UITableView, session: UIDropSession) {
        dropTable = table; dropSession = session
        nativeDropPoint = nil
        let path = table === treeView ? dropPath(table, session: session) : nil
        trackDropPath(path)
    }
    private func trackDropPath(_ path: [OneDriveItem]?) {
        let identifier = path.map(key)
        if identifier != dropHoverKey {
            dropHoverWork?.cancel(); dropTreeRead?.cancel(); dropHoverKey = identifier
            if let path, let identifier, !expanded.contains(identifier) {
                let epoch = generation
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.dropHoverKey == identifier, let client = self.client else { return }
                    self.dropTreeRead = Task { [weak self] in
                        do {
                            let children = try await client.children(of: path.last?.id)
                            try Task.checkCancellation()
                            guard let self, self.dropHoverKey == identifier, self.generation == epoch, self.client === client else { return }
                            let offset = self.treeView.contentOffset
                            self.treeChildren[identifier] = children; self.expanded.insert(identifier)
                            self.rebuildTree(); self.treeView.layoutIfNeeded(); self.treeView.setContentOffset(offset, animated: false)
                        } catch { /* Hover failure starts no operation and leaves current list unchanged. */ }
                    }
                }
                dropHoverWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
            }
        }
        if dropScrollTimer == nil {
            dropScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                guard let self, let table = self.dropTable,
                      let point = self.dropSession.map({ FileDropTransfer.location($0, in: table) }) ?? self.nativeDropPoint.map({ table.convert($0, from: table.window) }) else { return }
                let y = point.y - table.contentOffset.y
                let delta: CGFloat = y < 24 ? -12 : y > table.bounds.height - 24 ? 12 : 0
                if delta != 0 {
                    let lower = -table.adjustedContentInset.top, upper = max(lower, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
                    table.setContentOffset(CGPoint(x: table.contentOffset.x, y: max(lower, min(upper, table.contentOffset.y + delta))), animated: false)
                }
            }
            if let timer = dropScrollTimer { RunLoop.main.add(timer, forMode: .common) }
        }
    }
    func tableView(_ tableView: UITableView, dropSessionDidExit session: UIDropSession) { stopDropHover() }
    func tableView(_ tableView: UITableView, dropSessionDidEnd session: UIDropSession) { stopDropHover() }
    func tableView(_ tableView: UITableView, dragSessionDidEnd session: UIDragSession) { stopDropHover() }
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        guard self.tableView(tableView, canHandle: session), allowsDrop(tableView, session: session) else { stopDropHover(); return UITableViewDropProposal(operation: .forbidden) }
        trackDrop(tableView, session: session)
        let row = tableView.indexPathForRow(at: FileDropTransfer.location(session, in: tableView))
        let intoFolder = row.map { index in
            tableView === treeView || (visibleItems.indices.contains(index.row) && visibleItems[index.row].isFolder)
        } ?? false
        let archiveExport = session.items.contains { FileEntry.resolveDrag($0)?.zipPath != nil }
        return UITableViewDropProposal(operation: FileDropAction.proposal(moveMode: commander?.moveMode == true, allowsMove: session.allowsMoveOperation, archive: archiveExport),
                                      intent: intoFolder ? .insertIntoDestinationIndexPath : .unspecified)
    }
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard coordinator.proposal.operation == .copy || coordinator.proposal.operation == .move else { return }
        stopDropHover()
        guard self.tableView(tableView, canHandle: coordinator.session), allowsDrop(tableView, session: coordinator.session) else { return }
        onActivate?()
        let destination = dropParent(tableView, session: coordinator.session)
        let selections = coordinator.items.compactMap { OneDriveSelection.resolve($0.dragItem) }
        if let source = selections.first {
            guard selections.count == coordinator.items.count, selections.allSatisfy({ $0.browser === source.browser && $0.generation == source.generation }) else { return }
            let combined = OneDriveSelection(browser: source.browser, items: selections.flatMap(\.items), generation: source.generation)
            combined.parentID = source.parentID
            receiveOnline(combined, parent: destination, useCurrentFolder: false, move: coordinator.proposal.operation == .move)
        } else {
            let local = coordinator.items.compactMap { FileEntry.resolveDrag($0.dragItem) }
            if local.contains(where: { $0.zipPath != nil }) {
                receiveProviders(coordinator.items.map {
                    FileEntry.resolveDrag($0.dragItem)?.dragProvider ?? $0.dragItem.itemProvider
                }, parent: destination, useCurrentFolder: false, forceCopy: true)
            } else if local.count == coordinator.items.count {
                // Our local pane already carries the real URL. Do not round-trip
                // it through a generic provider UTI, which may be public.item.
                receiveLocal(local.map(\.url), parent: destination, useCurrentFolder: false, move: coordinator.proposal.operation == .move)
            } else {
                receiveProviders(coordinator.items.map { $0.dragItem.itemProvider }, parent: destination, useCurrentFolder: false,
                                 moveOverride: FileDropAction.externalMove(moveMode: commander?.moveMode == true))
            }
        }
    }
    func tableView(_ tableView: UITableView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { false }
    func tableView(_ tableView: UITableView, dragSessionAllowsMoveOperation session: UIDragSession) -> Bool { true }
}
#endif
