import UIKit
import Darwin
import ZIPFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
#if targetEnvironment(macCatalyst)
    private var profileLease: CommanderProfileLease?
#endif
    func applicationWillTerminate(_ application: UIApplication) {
#if targetEnvironment(macCatalyst)
        DesktopBridge.shared?.shutdownCloudOperations()
#endif
    }
#if DEBUG && targetEnvironment(macCatalyst)
    static private(set) var macUITestRoot: URL?
#endif

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.isFileURL, let controller = window?.rootViewController as? ViewController else { return false }
        controller.loadViewIfNeeded()
        return controller.openIncomingFolder(url)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
#if targetEnvironment(macCatalyst)
        // Acquire before fixture preparation, preferences, queue recovery or
        // history import. LaunchServices normally reuses the running app, but a
        // forced second executable must not become another profile writer.
        do { profileLease = try CommanderProfileLease(directory: desktopProfileDirectory()) }
        catch {
            let occupied = (error as? CommanderProfileLease.Failure) == .inUse
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            window = UIWindow(frame: UIScreen.main.bounds)
            window?.rootViewController = controller; window?.makeKeyAndVisible()
            DispatchQueue.main.async {
                let alert = UIAlertController(title: L10n.get("app_name"),
                    message: L10n.get(occupied ? "profile_in_use" : "profile_unavailable"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.get("ok"), style: .cancel) { _ in exit(0) })
                controller.present(alert, animated: true)
            }
            return true
        }
#endif
#if !targetEnvironment(macCatalyst)
        MediaExportFiles.cleanInterruptedExports()
#endif
#if DEBUG
#if targetEnvironment(macCatalyst)
        if ProcessInfo.processInfo.arguments.contains("--mac-parity-fixtures") || Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests" { prepareMacParityFixtures() }
#endif
        if ProcessInfo.processInfo.arguments.contains("--reset-file-access-onboarding") {
            UserDefaults.standard.removeObject(forKey: "ios_file_access_onboarding_v2_shown")
            UserDefaults.standard.removeObject(forKey: "ios_main_folder_onboarding_v3_completed")
        }
        if ProcessInfo.processInfo.arguments.contains("--app-review-fixtures") {
            prepareAppReviewFixtures()
        }
        if ProcessInfo.processInfo.arguments.contains("--image-viewer-fixtures") {
            prepareImageViewerFixtures()
        }
        if ProcessInfo.processInfo.arguments.contains("--stale-folder-bookmark-fixture") {
            prepareStaleFolderBookmarkFixture()
        }
        if ProcessInfo.processInfo.arguments.contains("--reset-media-import-fixtures") {
            resetMediaImportFixtures()
        }
#endif
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
#if targetEnvironment(macCatalyst)
        // Initialize native services at launch, including the once-per-update
        // refresh of the installed FSKit extension registration.
        _ = DesktopBridge.shared
        if let windowScene = window?.windowScene {
            windowScene.title = "OpenCommander"
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
        }
#endif
        return true
    }

#if targetEnvironment(macCatalyst)
    private func desktopProfileDirectory() -> URL {
#if DEBUG
        if Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests" {
            let resource = Bundle.main.url(forResource: "MacUITestRoot", withExtension: "txt")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
            if let path = ProcessInfo.processInfo.environment["OPENCOMMANDER_MAC_UI_ROOT"] ?? resource,
               let canonical = realpath(path, nil) {
                defer { free(canonical) }
                let root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
                if root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-"),
                   FileManager.default.fileExists(atPath: root.appendingPathComponent("Left").path),
                   FileManager.default.fileExists(atPath: root.appendingPathComponent("Right").path) { return root }
            }
        }
#endif
        return HostFileSystem.homeDirectory.appendingPathComponent("Library/Application Support/OpenCommander", isDirectory: true)
    }
#endif

#if DEBUG
    private func prepareAppReviewFixtures() {
#if targetEnvironment(macCatalyst)
        // iOS fixtures use its container's Documents. On the desktop that is
        // the user's actual Documents directory, so use the isolated Mac suite.
        return
#else
        let fileManager = FileManager.default
        UserDefaults.standard.set("en", forKey: "language")
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let source = documents.appendingPathComponent("Source", isDirectory: true)
        let notes = source.appendingPathComponent("Notes", isDirectory: true)
        let target = documents.appendingPathComponent("Target", isDirectory: true)
        let dragMe = documents.appendingPathComponent("DragMe", isDirectory: true)
        let dropHere = documents.appendingPathComponent("DropHere", isDirectory: true)
        try? fileManager.createDirectory(at: notes, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: dragMe, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: dropHere, withIntermediateDirectories: true)
        try? Data("OpenCommander physical iPhone review test\n".utf8)
            .write(to: source.appendingPathComponent("Welcome.txt"), options: .atomic)
        try? Data("Copy, move, ZIP and undo verified.\n".utf8)
            .write(to: notes.appendingPathComponent("Checklist.txt"), options: .atomic)
        try? Data("Drop files here.\n".utf8)
            .write(to: target.appendingPathComponent("Existing.txt"), options: .atomic)
        try? Data("Drop target.\n".utf8)
            .write(to: dropHere.appendingPathComponent("Destination.txt"), options: .atomic)
        try? Data("Drag-and-drop copy verified on physical iPhone.\n".utf8)
            .write(to: dragMe.appendingPathComponent("Proof.txt"), options: .atomic)
        try? fileManager.removeItem(at: dropHere.appendingPathComponent("DragMe"))
        try? fileManager.removeItem(at: documents.appendingPathComponent("Source.zip"))
#endif
    }

#if targetEnvironment(macCatalyst)
    private func prepareMacParityFixtures() {
        let testID = "com.github.niklaus85.OpenCommander.MacUITests"
        guard Bundle.main.bundleIdentifier == testID else { return }
        // The environment is used by XCTest; an optional root-only resource
        // allows the same isolated clone to be exercised by visible UI tools.
        let resourcePath = Bundle.main.url(forResource: "MacUITestRoot", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let path = ProcessInfo.processInfo.environment["OPENCOMMANDER_MAC_UI_ROOT"] ?? resourcePath else { return }
        guard let physical = realpath(path, nil) else { return }
        defer { free(physical) }
        let root = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
        guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-"),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("Left").path),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("Right").path) else { return }
        Self.macUITestRoot = root
#if DEBUG
        // Regression for directly opened (including empty) drop destinations:
        // unlike child rows they initially have no cached listing metadata.
        do {
            for name in ["Left", "Right"] {
                let entry = FileEntry(url: root.appendingPathComponent(name), parent: nil)
                precondition(!entry.offersDirectoryDrop)
                let children = try entry.readChildren(directoriesOnly: false)
                precondition(entry.offersDirectoryDrop && entry.canWriteDirectory())
                for file in children where !file.isPhysicalDirectory() {
                    precondition(!file.offersDirectoryDrop)
                }
            }
            let absent = FileEntry(url: root.appendingPathComponent("Missing-Drag-Regression-" + UUID().uuidString), parent: nil)
            do { _ = try absent.readChildren(directoriesOnly: false); preconditionFailure("Missing directory accepted") }
            catch { precondition(!absent.offersDirectoryDrop) }
            CommanderDragDiagnostics.event("PASS directly opened drop roots, regular files and missing directory")
        } catch { preconditionFailure("Drop-root regression: \(error)") }
#endif
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("--mac-parity-reset") { defaults.removePersistentDomain(forName: testID) }
        let historyFixture = root.appendingPathComponent("AcceptanceHistory.json")
        if defaults.string(forKey: "acceptance_history_root") != root.path,
           let bytes = try? Data(contentsOf: historyFixture), bytes.count <= 2 * 1024 * 1024,
           let history = try? JSONDecoder().decode([OperationType].self, from: bytes), history.count <= 1000,
           history.allSatisfy({ operation in
               switch operation {
               case .cloud(let record):
                   return record.undo == nil && record.source.hasPrefix(root.path + "/") && record.destination.hasPrefix(root.path + "/")
               case .copy(let records):
                   // One actual oldest-page Undo, restricted to named synthetic
                   // files with a live proof, never an arbitrary seeded action.
                   guard records.count == 1, let record = records.first,
                         record.source == root.appendingPathComponent("Left/HistoryUndoSource.txt"),
                         record.destination == root.appendingPathComponent("Right/HistoryOldestUndo.txt"),
                         record.replacedBackup == nil, record.quarantinedSource == nil else { return false }
                   do { try record.verifyUnchangedDestination(); return true } catch { return false }
               default: return false
               }
           }) {
            defaults.removeObject(forKey: "operation_history_v2")
            defaults.set(bytes, forKey: "operation_history_v1")
            defaults.set(root.path, forKey: "acceptance_history_root")
        }
        let preserveState = FileManager.default.fileExists(atPath: root.appendingPathComponent("PreserveAppState.txt").path)
        let initializeState = !preserveState || defaults.string(forKey: "acceptance_state_root") != root.path
        if initializeState { defaults.set("en", forKey: "language") }
        for key in ["onboarding_shown", "mac_folder_default_prompt_v1", "mac_full_disk_access_onboarding_shown"] { defaults.set(true, forKey: key) }
        if initializeState {
            for (pane, directory) in [("1", "Left"), ("2", "Right")] {
                defaults.removeObject(forKey: "folder_bookmark_pane_" + pane)
                defaults.removeObject(forKey: "folder_last_visited_pane_" + pane)
                defaults.set(root.appendingPathComponent(directory).path, forKey: "folder_path_pane_" + pane)
            }
        }
        defaults.set(root.path, forKey: "acceptance_state_root")
    }
#endif

    private func prepareStaleFolderBookmarkFixture() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "ios_file_access_onboarding_v2_shown")
        defaults.set(true, forKey: "onboarding_shown")
        defaults.set(Data("not-a-bookmark".utf8), forKey: "folder_bookmark_pane_1")
        defaults.set(Data("not-a-bookmark".utf8), forKey: "folder_bookmark_pane_2")
        defaults.set("/private/unavailable", forKey: "folder_path_pane_1")
        defaults.set("/private/unavailable", forKey: "folder_path_pane_2")
    }

    private func resetMediaImportFixtures() {
#if targetEnvironment(simulator)
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("Media", isDirectory: true))
#endif
    }

    private func prepareImageViewerFixtures() {
#if targetEnvironment(macCatalyst)
        return
#else
        let fileManager = FileManager.default
        UserDefaults.standard.set("en", forKey: "language")
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("ImageViewerQA", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        func png(color: UIColor, text: String) -> Data? {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600))
            return renderer.pngData { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 72),
                    .foregroundColor: UIColor.white,
                ]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(
                    at: CGPoint(x: (900 - size.width) / 2, y: (600 - size.height) / 2),
                    withAttributes: attributes
                )
            }
        }

        let first = folder.appendingPathComponent("01-first.png")
        let second = folder.appendingPathComponent("02-second.png")
        try? png(color: UIColor.systemBlue, text: "FIRST")?.write(to: first, options: .atomic)
        try? png(color: UIColor.systemGreen, text: "SECOND")?.write(to: second, options: .atomic)
        try? Data("not an image".utf8).write(
            to: folder.appendingPathComponent("03-corrupt.png"), options: .atomic)

        let zip = folder.appendingPathComponent("gallery.zip")
        try? fileManager.removeItem(at: zip)
        if let archive = Archive(url: zip, accessMode: .create) {
            try? archive.addEntry(with: first.lastPathComponent, fileURL: first)
            try? archive.addEntry(with: second.lastPathComponent, fileURL: second)
        }
#endif
    }
#endif

}
