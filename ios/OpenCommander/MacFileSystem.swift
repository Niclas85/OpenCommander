import Foundation

struct DesktopLocationPreference: Codable {
    var path: String
    var name: String
    var enabled: Bool
    var custom: Bool
    var bookmark: Data?
    var visibilityConfigured: Bool?
}

enum DesktopLocationPreferences {
    static func reordered(_ entries: [DesktopLocationPreference], visible: [DesktopLocationPreference],
                          source: String, target: String, before: Bool) -> [DesktopLocationPreference]? {
        let paths = visible.map(\.path)
        guard source != target, Set(paths).count == paths.count, paths.contains(source), paths.contains(target),
              Set(entries.map(\.path)).count == entries.count else { return nil }
        var result = entries
        for entry in visible where !result.contains(where: { $0.path == entry.path }) { result.append(entry) }
        guard let old = result.firstIndex(where: { $0.path == source }) else { return nil }
        let moved = result.remove(at: old)
        guard let index = result.firstIndex(where: { $0.path == target }) else { return nil }
        result.insert(moved, at: index + (before ? 0 : 1))
        return result
    }
    static let oneDriveOnlinePath = "onedrive://online"
    static func load(from defaults: UserDefaults = .standard) -> [DesktopLocationPreference] {
        guard let data = defaults.data(forKey: "desktop_locations_v1") else { return [] }
        return (try? JSONDecoder().decode([DesktopLocationPreference].self, from: data)) ?? []
    }

    static func save(_ entries: [DesktopLocationPreference], to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: "desktop_locations_v1") }
    }
}

#if targetEnvironment(macCatalyst)
import UIKit

/// Only an app-local location token can reorder the bar. File URL/provider
/// drags never become location preferences or move their underlying folders.
@MainActor final class DesktopLocationBarInteraction: NSObject, UIDragInteractionDelegate, UIDropInteractionDelegate, UIContextMenuInteractionDelegate {
    private final class Token {
        weak var owner: DesktopLocationBarInteraction?
        let path: String
        init(_ owner: DesktopLocationBarInteraction, _ path: String) { self.owner = owner; self.path = path }
    }
    private weak var stack: UIStackView?
    private weak var scroll: UIScrollView?
    private var buttons: [(String, UIButton)] = []
    private let indicator = UIView()
    private var scrolling: Timer?
    private var session: UIDropSession?
    private var activationAfter = Date.distantPast
    private(set) var isDragging = false
    var allowsActivation: Bool { !isDragging && Date() >= activationAfter }
    var moved: ((String, String, Bool) -> Void)?
    var ended: (() -> Void)?
    init(stack: UIStackView, scroll: UIScrollView) {
        self.stack = stack; self.scroll = scroll; super.init()
        indicator.backgroundColor = .systemBlue; indicator.isHidden = true; indicator.isUserInteractionEnabled = false
        stack.addSubview(indicator); stack.addInteraction(UIDropInteraction(delegate: self))
    }
    func configure(_ values: [(String, UIButton)]) {
        guard !isDragging else { return }
        buttons = values
        for (path, button) in values {
            let drag = UIDragInteraction(delegate: self); drag.isEnabled = true; button.addInteraction(drag)
            button.addInteraction(UIContextMenuInteraction(delegate: self))
            button.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: L10n.get("location_move_left")) { [weak self] _ in self?.step(path, -1) ?? false },
                UIAccessibilityCustomAction(name: L10n.get("location_move_right")) { [weak self] _ in self?.step(path, 1) ?? false }]
        }
    }
    private func step(_ path: String, _ delta: Int) -> Bool {
        guard !isDragging, let index = buttons.firstIndex(where: { $0.0 == path }), buttons.indices.contains(index + delta) else { return false }
        moved?(path, buttons[index + delta].0, delta < 0); return true
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard !isDragging, let index = buttons.firstIndex(where: { $0.1 === interaction.view }) else { return nil }
        let path = buttons[index].0
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: [
                UIAction(title: L10n.get("location_move_left"), image: UIImage(systemName: "arrow.left"), attributes: index == 0 ? .disabled : []) { [weak self] _ in _ = self?.step(path, -1) },
                UIAction(title: L10n.get("location_move_right"), image: UIImage(systemName: "arrow.right"), attributes: index == self.buttons.count - 1 ? .disabled : []) { [weak self] _ in _ = self?.step(path, 1) }])
        }
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let entry = buttons.first(where: { $0.1 === interaction.view }) else { return [] }
        isDragging = true; session.localContext = self
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: FileDropTransfer.locationReorderType, visibility: .ownProcess) { completion in
            completion(Data([1]), nil); return nil
        }
        let item = UIDragItem(itemProvider: provider)
        item.localObject = Token(self, entry.0); return [item]
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: UIDragSession) -> Bool { true }
    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
        stopTracking(); isDragging = false; activationAfter = Date().addingTimeInterval(0.3); ended?()
    }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.items.count == 1 && (session.items.first?.localObject as? Token)?.owner === self
    }
    private func target(_ session: UIDropSession) -> (String, Bool, CGFloat)? {
        guard let stack, !buttons.isEmpty else { return nil }
        let x = session.location(in: stack).x
        for (path, button) in buttons where x < button.frame.maxX {
            let before = x < button.frame.midX
            return (path, before, before ? button.frame.minX : button.frame.maxX)
        }
        return buttons.last.map { ($0.0, false, $0.1.frame.maxX) }
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        guard dropInteraction(interaction, canHandle: session), let stack, let target = target(session) else { return UIDropProposal(operation: .forbidden) }
        self.session = session; indicator.isHidden = false
        indicator.frame = CGRect(x: target.2 - 2, y: 0, width: 3, height: stack.bounds.height)
        stack.bringSubviewToFront(indicator)
        if scrolling == nil {
            scrolling = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                guard let self, let scroll = self.scroll, let session = self.session else { return }
                let x = session.location(in: scroll).x - scroll.contentOffset.x
                let delta: CGFloat = x < 24 ? -10 : x > scroll.bounds.width - 24 ? 10 : 0
                let limit = max(0, scroll.contentSize.width - scroll.bounds.width)
                if delta != 0 { scroll.setContentOffset(CGPoint(x: max(0, min(limit, scroll.contentOffset.x + delta)), y: 0), animated: false) }
            }
            if let scrolling { RunLoop.main.add(scrolling, forMode: .common) }
        }
        return UIDropProposal(operation: .move)
    }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard dropInteraction(interaction, canHandle: session), let source = session.items.first?.localObject as? Token,
              let target = target(session) else { return }
        moved?(source.path, target.0, target.1); stopTracking()
    }
    private func stopTracking() { indicator.isHidden = true; scrolling?.invalidate(); scrolling = nil; session = nil }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) { stopTracking() }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) { stopTracking() }
}
#endif

#if targetEnvironment(macCatalyst) || os(macOS)
import Darwin
#endif

enum HostFileSystem {
    private static let providerStatusLock = NSLock()
    private static let providerStatusKey = "mac_disabled_provider_paths_v1"

    /// Discovery only reads local folder metadata. A provider's contents are
    /// coordinated when the user opens it; a disconnected provider must not
    /// hold up the complete drive list.
    private static func knownProviderDisabled(_ root: URL, defaults: UserDefaults) -> Bool {
        providerStatusLock.lock(); defer { providerStatusLock.unlock() }
        let states = defaults.dictionary(forKey: providerStatusKey) ?? [:]
        guard let recorded = states[root.standardizedFileURL.path] as? TimeInterval else { return false }
        let age = Date().timeIntervalSince1970 - recorded
        return age >= 0 && age < 300
    }
    static func noteProviderAccess(_ url: URL, error: NSError?, home: URL = homeDirectory, defaults: UserDefaults = .standard) {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let prefixes = ["Library/CloudStorage", "Library/Mobile Documents"].map { home.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path + "/" }
        var root: String?
        for prefix in prefixes where path.hasPrefix(prefix) {
            if let account = path.dropFirst(prefix.count).split(separator: "/").first { root = prefix + account }
        }
        if root == nil {
            let prefix = home.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            if path.hasPrefix(prefix), let first = path.dropFirst(prefix.count).split(separator: "/").first,
               ["OneDrive", "Dropbox", "Google Drive", "Box"].contains(String(first)) || first.hasPrefix("OneDrive-") || first.hasPrefix("OneDrive - ") || first.hasPrefix("GoogleDrive-") { root = prefix + first }
        }
        guard let root, error == nil || isDisabledProvider(error!) else { return }
        providerStatusLock.lock(); defer { providerStatusLock.unlock() }
        var states = (defaults.dictionary(forKey: providerStatusKey) ?? [:]).compactMapValues { $0 as? TimeInterval }
        let now = Date().timeIntervalSince1970
        states = states.filter { now - $0.value < 300 }
        if error == nil { states.removeValue(forKey: root) } else { states[root] = now }
        if states.count > 128, let oldest = states.min(by: { $0.value < $1.value }) { states.removeValue(forKey: oldest.key) }
        defaults.set(states, forKey: providerStatusKey)
    }
    static func coordinatedRead<T>(at url: URL, _ read: (URL) throws -> T) throws -> T {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            result = Result { try read(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
    enum StorageKind {
        case externalDrive
        case networkShare
        case cloudStorage
    }

    struct StorageLocation {
        let name: String
        let url: URL
        let kind: StorageKind
        var isLocalArchive: Bool = false
        var isDisabled: Bool = false
        var visibleByDefault: Bool { !isLocalArchive && !isDisabled }
        var previousDefaultNames: [String] {
            let component = url.lastPathComponent
            if component.hasPrefix("OneDrive-FreigegebeneBibliotheken") {
                return ["OneDrive — " + String(component.dropFirst("OneDrive-".count))]
            }
            return []
        }

        var displayName: String {
            if isLocalArchive { return "\(name) — \(L10n.get("cloud_local_archive"))" }
            if isDisabled { return "\(name) — \(L10n.get("location_disabled"))" }
            return name
        }
    }

    enum FullDiskAccessStatus: Equatable {
        case granted
        case denied
        case unavailable
    }

    static var homeDirectory: URL {
#if targetEnvironment(macCatalyst) || os(macOS)
        if let passwordEntry = getpwuid(getuid()),
           let home = passwordEntry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
#endif
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var downloadsDirectory: URL {
        homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var desktopDirectory: URL {
        homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Finds storage already made available by macOS. Cloud File Provider services
    /// live below Library/CloudStorage, while removable media and mounted network
    /// shares normally live below /Volumes. The direct /Volumes scan is necessary
    /// because Mac Catalyst does not always report every mounted share through
    /// `mountedVolumeURLs`.
    static func availableStorageLocations() -> [StorageLocation] {
#if targetEnvironment(macCatalyst)
        var result: [StorageLocation] = []
        var addedPaths = Set<String>()
        let fm = FileManager.default
        let volumeKeys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey
        ]

        func append(_ url: URL, name: String? = nil, kind: StorageKind) {
            let normalized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  addedPaths.insert(normalized.path).inserted else { return }
            result.append(StorageLocation(name: name ?? normalized.lastPathComponent, url: normalized, kind: kind))
        }

        let reportedVolumes = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(volumeKeys),
            options: []
        ) ?? []
        for volume in reportedVolumes where volume.standardizedFileURL.path.hasPrefix("/Volumes/") {
            let values = try? volume.resourceValues(forKeys: volumeKeys)
            let kind: StorageKind = values?.volumeIsLocal == false ? .networkShare : .externalDrive
            append(volume, name: values?.volumeName, kind: kind)
        }

        let volumesDirectory = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let directlyVisibleVolumes = (try? fm.contentsOfDirectory(
            at: volumesDirectory,
            includingPropertiesForKeys: Array(volumeKeys) + [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for volume in directlyVisibleVolumes {
            let values = try? volume.resourceValues(forKeys: volumeKeys)
            let kind: StorageKind = values?.volumeIsLocal == false ? .networkShare : .externalDrive
            append(volume, name: values?.volumeName, kind: kind)
        }

        result.append(contentsOf: cloudStorageLocations(in: homeDirectory).filter {
            addedPaths.insert($0.url.standardizedFileURL.path).inserted
        })

        let order: (StorageKind) -> Int = {
            switch $0 {
            case .externalDrive: return 0
            case .networkShare: return 1
            case .cloudStorage: return 2
            }
        }
        return result.sorted {
            let leftOrder = order($0.kind)
            let rightOrder = order($1.kind)
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            if $0.isLocalArchive != $1.isLocalArchive { return !$0.isLocalArchive }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
#else
        return []
#endif
    }

    /// Discover provider-published folders, not app bundles: an installed client
    /// without a signed-in/syncing account does not expose a filesystem to browse.
    /// Keep preserved Google domains accessible, but never present them as live accounts.
    static func cloudStorageLocations(in home: URL, providerDefaults: UserDefaults = .standard) -> [StorageLocation] {
        let fm = FileManager.default
        var result: [StorageLocation] = []
        var addedPaths = Set<String>()
        func append(_ url: URL, name: String) {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard isDirectory(resolved), addedPaths.insert(resolved.path).inserted else { return }
            let datedGoogleCopy = resolved.lastPathComponent.hasPrefix("GoogleDrive-") &&
                resolved.lastPathComponent.range(of: #" \(\d{2}\.\d{2}\.\d{2} \d{2}:\d{2}\)$"#, options: .regularExpression) != nil
            let archived = datedGoogleCopy || fm.fileExists(atPath: resolved.appendingPathComponent(".drive_fs_ignore_preserved_domain").path)
            let disabled = !archived && knownProviderDisabled(resolved, defaults: providerDefaults)
            result.append(StorageLocation(name: name, url: resolved, kind: .cloudStorage,
                isLocalArchive: archived, isDisabled: disabled))
        }

        let cloudRoot = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let cloudProviders = (try? fm.contentsOfDirectory(
            at: cloudRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for provider in cloudProviders {
            let values = try? provider.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true || values?.isSymbolicLink == true else { continue }
            append(provider, name: cloudDisplayName(provider.lastPathComponent))
        }

        let iCloudDrive = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs",
            isDirectory: true
        )
        append(iCloudDrive, name: "iCloud Drive")
        // Dropbox's sync folder may have been moved outside the home directory.
        if let data = try? Data(contentsOf: home.appendingPathComponent(".dropbox/info.json")),
           let accounts = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for account in accounts.values {
                if let path = account["path"] as? String, path.hasPrefix("/") {
                    append(URL(fileURLWithPath: path, isDirectory: true), name: "Dropbox")
                }
            }
        }

        // Older sync clients and user-visible links can live in the home folder.
        // Resolve links before deduplication; never recursively search private app data.
        let homeChildren = (try? fm.contentsOfDirectory(at: home,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for folder in homeChildren {
            let name = folder.lastPathComponent
            if ["OneDrive", "Dropbox", "Google Drive", "Box"].contains(name) ||
                name.hasPrefix("OneDrive - ") || name.hasPrefix("OneDrive-") || name.hasPrefix("GoogleDrive-") {
                append(folder, name: cloudDisplayName(name))
            }
        }
        return result.sorted {
            if $0.isLocalArchive != $1.isLocalArchive { return !$0.isLocalArchive }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        // File Provider placeholders expose their type as URL metadata even when
        // no content is downloaded. Fall back to stat for ordinary symlinks.
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return true }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    static func isCloudStorage(_ url: URL, home: URL = homeDirectory) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = ["Library/CloudStorage", "Library/Mobile Documents"].map {
            home.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        if roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard path.hasPrefix(homePath), let first = path.dropFirst(homePath.count).split(separator: "/").first else { return false }
        return ["OneDrive", "Dropbox", "Google Drive", "Box"].contains(String(first)) ||
            first.hasPrefix("OneDrive - ") || first.hasPrefix("OneDrive-") || first.hasPrefix("GoogleDrive-")
    }

    static func directoryContents(at url: URL, showHidden: Bool) throws -> [URL] {
        let read: (URL) throws -> [URL] = { directory in
            try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: showHidden ? [] : [.skipsHiddenFiles])
        }
#if targetEnvironment(macCatalyst) || os(macOS)
        if isCloudStorage(url) {
            // Run off the UI thread. Coordinate the directory listing with its
            // provider; do not read file contents or recursively hydrate the drive.
            var coordinationError: NSError?
            var result: Result<[URL], Error>?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges,
                error: &coordinationError) { coordinatedURL in
                    result = Result { try read(coordinatedURL) }
                }
            if let coordinationError {
                noteProviderAccess(url, error: coordinationError as NSError)
                throw coordinationError
            }
            guard let result else { throw CocoaError(.fileReadUnknown) }
            do {
                let contents = try result.get()
                noteProviderAccess(url, error: nil)
                return contents
            } catch {
                noteProviderAccess(url, error: error as NSError)
                throw error
            }
        }
        return try read(url)
#else
        return try coordinatedRead(at: url, read)
#endif
    }

    static func cloudClientName(for url: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        for (prefix, name) in [("OneDrive", "OneDrive"), ("GoogleDrive", "Google Drive"),
                               ("Dropbox", "Dropbox"), ("Box-", "Box")] {
            if components.contains(where: { $0.hasPrefix(prefix) }) { return name }
        }
        return nil
    }

    static func isDisabledProvider(_ error: NSError) -> Bool {
        // NSFileProviderErrorDomainDisabled: the OS reports a user-disabled domain.
        if error.domain == "NSFileProviderErrorDomain" && error.code == -2011 { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isDisabledProvider(underlying) }
        return false
    }

    private static func cloudDisplayName(_ directoryName: String) -> String {
        let knownPrefixes: [(String, String)] = [
            ("GoogleDrive-", "Google Drive — "),
            ("OneDrive-", "OneDrive — "),
            ("Dropbox-", "Dropbox — "),
            ("Box-", "Box — ")
        ]
        for (prefix, replacement) in knownPrefixes where directoryName.hasPrefix(prefix) {
            let account = String(directoryName.dropFirst(prefix.count))
            if prefix == "OneDrive-", account.hasPrefix("FreigegebeneBibliotheken") {
                return L10n.get("onedrive_shared_local")
            }
            return replacement + account
        }
        return directoryName
    }

    /// macOS has no public API that returns the Full Disk Access switch. Reading one of
    /// the user's TCC-protected Library folders is the established fail-closed probe.
    /// The probe never creates, changes, or uploads a file.
    static func fullDiskAccessStatus() -> FullDiskAccessStatus {
#if targetEnvironment(macCatalyst)
        let protectedDirectories = ["Mail", "Safari", "Messages"].map {
            homeDirectory.appendingPathComponent("Library/\($0)", isDirectory: true)
        }
        var sawPermissionDenial = false
        for directory in protectedDirectories {
            do {
                _ = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                return .granted
            } catch {
                let nsError = error as NSError
                let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
                if nsError.code == NSFileReadNoPermissionError ||
                    (underlying?.domain == NSPOSIXErrorDomain &&
                     (underlying?.code == Int(EACCES) || underlying?.code == Int(EPERM))) {
                    sawPermissionDenial = true
                }
            }
        }
        return sawPermissionDenial ? .denied : .unavailable
#else
        return .unavailable
#endif
    }
}

#if targetEnvironment(macCatalyst) || os(macOS)
/// Observe only the folder the user is browsing, not an entire cloud account.
/// Its owner must stop registration explicitly: NSFileCoordinator retains presenters.
final class CloudDirectoryObserver: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }
    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidAppear(at url: URL) { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { onChange() }
    func presentedItemDidMove(to newURL: URL) { onChange() }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
        onChange()
    }
}
#endif
