import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

extension FileEntry {
    private static var nativeArchiveDrags: [String: FileEntry] = [:]
    static func resolveDrag(_ item: UIDragItem) -> FileEntry? {
        (item.localObject as? FileEntry) ?? item.itemProvider.registeredTypeIdentifiers.compactMap { nativeArchiveDrags[$0] }.first
    }
    func registerArchiveDrag() -> String {
        let token = "org.opencommander.archive-drag." + UUID().uuidString.lowercased()
        Self.nativeArchiveDrags[token] = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { Self.nativeArchiveDrags.removeValue(forKey: token) }
        return token
    }
    static func archiveDrag(_ token: String) -> FileEntry? { nativeArchiveDrags[token] }
}

enum CommanderDragDiagnostics {
    static func event(_ value: String) {
#if DEBUG && targetEnvironment(macCatalyst)
        guard Bundle.main.bundleIdentifier == "com.github.niklaus85.OpenCommander.MacUITests",
              let resource = Bundle.main.url(forResource: "MacUITestRoot", withExtension: "txt"),
              let root = try? String(contentsOf: resource, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              root.hasPrefix("/private/tmp/OpenCommander-MacUITest-") else { return }
        let url = URL(fileURLWithPath: root).appendingPathComponent("DragEvents.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data((value + "\n").utf8))
        }
#endif
    }
}

#if targetEnvironment(macCatalyst)
/// Capture the actual pointer event before UITableView sends its selection
/// callback, including Shift and Command. Consume once so accessibility clicks
/// cannot inherit a modifier from an earlier pointer action.
final class CommanderSelectionTableView: UITableView {
    private var selectionModifiers: UIKeyModifierFlags = []
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        CommanderDragDiagnostics.event("pointer began")
        selectionModifiers = event?.modifierFlags ?? []
        super.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        CommanderDragDiagnostics.event("pointer moved")
        super.touchesMoved(touches, with: event)
    }
    func consumeSelectionModifiers() -> UIKeyModifierFlags {
        defer { selectionModifiers = [] }
        return selectionModifiers
    }
    func resetSelectionModifiers() { selectionModifiers = [] }
}

/// A directory menu for the unused area of a list. Existing row menus still
/// own file selections; returning nil on rows leaves their semantics intact.
final class CommanderDirectoryMenu: NSObject, UIContextMenuInteractionDelegate {
    private weak var table: UITableView?
    private let makeMenu: () -> UIMenu?
    init(table: UITableView, makeMenu: @escaping () -> UIMenu?) {
        self.table = table; self.makeMenu = makeMenu
        super.init()
        table.addInteraction(UIContextMenuInteraction(delegate: self))
    }
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let table, table.indexPathForRow(at: location) == nil else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in self?.makeMenu() }
    }
}
#endif

final class CommanderFilterField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        autocorrectionType = .no
        spellCheckingType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width, height: max(30, size.height))
    }
    func applyTheme(_ theme: ViewController.ThemeColors, placeholder text: String) {
        borderStyle = .none
        textColor = theme.primaryText
        backgroundColor = theme.pathBackground
        attributedPlaceholder = NSAttributedString(string: text, attributes: [.foregroundColor: theme.secondaryText])
        layer.borderColor = theme.pathBorder.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 6
        leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        leftViewMode = .always
    }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(clearFilter))]
    }
    @objc private func clearFilter() { text = ""; sendActions(for: .editingChanged) }
}

class TreeNode {
    let entry: FileEntry
    let depth: Int
    var expanded: Bool = false
    var loaded: Bool = false
    var children: [TreeNode] = []
    
    init(entry: FileEntry, depth: Int) {
        self.entry = entry
        self.depth = depth
    }
}

class CommanderPane: NSObject, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate {
    private let archiveDragSourceID = UUID().uuidString
    let title: String
    let accent: String
    weak var viewController: ViewController?
    
    var flatTree: [TreeNode] = []
    var visibleEntries: [FileEntry] = []
    private var allEntries: [FileEntry] = []
    private var nameFilter = ""
    private weak var filterInput: CommanderFilterField?
    private weak var filterStatus: UILabel?
    private weak var clearFilterButton: UIButton?
    private var sortField = 0
    private var sortAscending = true
    private weak var resizingColumns: UIStackView?
    private weak var resizingTree: UIView?
    private var treeWidthConstraint: NSLayoutConstraint?
    private var treeFraction: CGFloat = 0.28
#if !targetEnvironment(macCatalyst)
    private weak var mobileTreeColumn: UIView?
    private weak var breadcrumbButton: UIButton?
    private lazy var treeVisible: Bool = UserDefaults.standard.object(forKey: "mobile_tree_" + title) as? Bool ?? true
#endif
    var selectedKeys: Set<String> = []
    private var selectionAnchor: String?
    private var reentrySelection: (directory: String, entry: String)?
    
    
    var rootNode: TreeNode!
    var currentDirectory: FileEntry!
    private var backHistory: [FileEntry] = []
    private var forwardHistory: [FileEntry] = []
    private var listingGeneration = 0
    private var listedDirectoryKey: String?
    private var listingPending = false
    private var expandedTreeKeys = Set<String>()
    private var treeGeneration = 0
    private var dropHoverWork: DispatchWorkItem?
    private var dropHoverKey: String?
    private var dropScrollTimer: Timer?
    private weak var dropHoverTable: UITableView?
    private var currentDropSession: UIDropSession?
    private var nativeDropPoint: CGPoint?
#if targetEnvironment(macCatalyst)
    var onlineNavigation: UINavigationController?
    private weak var paneShell: UIStackView?
    var onlineBrowser: OneDriveBrowser? { onlineNavigation?.viewControllers.first as? OneDriveBrowser }

    func showOnline(_ navigation: UINavigationController) {
        onlineNavigation = navigation
        selectedKeys.removeAll()
        mountOnlineView()
    }
    private func mountOnlineView() {
        guard let shell = paneShell, let navigation = onlineNavigation else { return }
        shell.arrangedSubviews.forEach { $0.isHidden = true }
        let content = navigation.view!
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 4),
            content.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -4),
            content.topAnchor.constraint(equalTo: shell.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: shell.bottomAnchor, constant: -4)
        ])
    }
    func closeOnline() {
        guard let navigation = onlineNavigation else { return }
        onlineBrowser?.cancelPendingWork()
        navigation.willMove(toParent: nil)
        navigation.view.removeFromSuperview()
        navigation.removeFromParent()
        onlineNavigation = nil
        paneShell?.arrangedSubviews.forEach { $0.isHidden = false }
    }
    private var cloudObserver: CloudDirectoryObserver?
    private var cloudRefreshWork: DispatchWorkItem?
    private var directoryMenu: CommanderDirectoryMenu?
#endif
    private static let listingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "OpenCommander.directory-listing"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 4
        return queue
    }()
    
    var treeList: UITableView!
    var fileList: UITableView!
    var pathText: UITextField!
    var selectionText: UILabel!
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    
    var currentDirectoryBytes: Int64 = -1
    
    init(title: String, root: FileEntry, accent: String, viewController: ViewController) {
        self.title = title
        self.accent = accent
        self.viewController = viewController
        super.init()
        self.setRoot(root)
    }

    deinit {
        dropHoverWork?.cancel(); dropScrollTimer?.invalidate()
#if targetEnvironment(macCatalyst)
        cloudObserver?.stop()
        cloudRefreshWork?.cancel()
#endif
    }
    
    func setRoot(_ root: FileEntry, recordHistory: Bool = true) {
#if targetEnvironment(macCatalyst)
        closeOnline()
#endif
        if recordHistory, let current = currentDirectory, current.key() != root.key() {
            backHistory.append(current)
            forwardHistory.removeAll()
        }
        currentDirectory = root
        treeGeneration += 1
        expandedTreeKeys.removeAll()
#if targetEnvironment(macCatalyst)
        rootNode = TreeNode(entry: FileEntry(url: URL(fileURLWithPath: "/", isDirectory: true), parent: nil), depth: 0)
#else
        rootNode = TreeNode(entry: currentDirectory, depth: 0)
#endif
        rootNode.expanded = true
        loadChildren(for: rootNode)
        selectedKeys.removeAll()
    }
    
    private func dp(_ value: CGFloat) -> CGFloat {
        return value
    }
    
    func createView(portrait: Bool, first: Bool) -> UIView {
        guard let vc = viewController, let theme = vc.theme else { return UIView() }
        
        let shell = UIStackView()
#if targetEnvironment(macCatalyst)
        paneShell = shell
#endif
        shell.accessibilityIdentifier = "Pane-\(title)"
        let activate = UITapGestureRecognizer(target: self, action: #selector(activatePane))
        activate.cancelsTouchesInView = false
        activate.delaysTouchesEnded = false
        activate.delegate = self
        shell.addGestureRecognizer(activate)
        shell.axis = .vertical
        shell.spacing = dp(8)
        shell.layer.borderWidth = 1
        shell.layer.borderColor = theme.panelBorder.cgColor
        shell.layer.cornerRadius = 12
        shell.backgroundColor = theme.panelBackground
        shell.isLayoutMarginsRelativeArrangement = true
        shell.layoutMargins = UIEdgeInsets(top: dp(8), left: dp(8), bottom: dp(8), right: dp(8))
#if targetEnvironment(macCatalyst)
        let accentLine = UIView()
        accentLine.backgroundColor = UIColor(hex: title == "1" ? (vc.darkMode ? "#88baff" : "#185bb5") : (vc.darkMode ? "#79dcb9" : "#147454"))
        accentLine.heightAnchor.constraint(equalToConstant: 3).isActive = true
        shell.addArrangedSubview(accentLine)
#endif
        
        let pathRow = UIStackView()
        pathRow.axis = .horizontal
        pathRow.spacing = dp(6)
        pathRow.alignment = .center
        
        pathText = UITextField()
        pathText.textColor = theme.secondaryText
        pathText.font = UIFont.systemFont(ofSize: 11)
        pathText.layer.cornerRadius = 8
        pathText.layer.borderWidth = 1
        pathText.layer.borderColor = theme.pathBorder.cgColor
        pathText.backgroundColor = theme.pathBackground
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: dp(8), height: dp(20)))
        pathText.leftView = paddingView
        pathText.leftViewMode = .always
        pathText.delegate = self
        pathText.returnKeyType = .go
        pathText.accessibilityIdentifier = "Path-\(title)"
        
        selectionText = UILabel()
        selectionText.accessibilityIdentifier = "Selection-\(title)"
        selectionText.textColor = theme.secondaryText
        selectionText.font = UIFont.systemFont(ofSize: 11)
        selectionText.textAlignment = .center
        selectionText.layer.cornerRadius = 8
        selectionText.layer.borderWidth = 1
        selectionText.layer.borderColor = theme.pathBorder.cgColor
        selectionText.backgroundColor = theme.pathBackground
        
        let upButton = UIButton(type: .system)
        upButton.setTitle("⬆", for: .normal)
        upButton.titleLabel?.font = UIFont.systemFont(ofSize: 11)
        upButton.layer.cornerRadius = 4
        upButton.layer.borderWidth = 1
        upButton.layer.borderColor = theme.pathBorder.cgColor
        upButton.backgroundColor = theme.buttonBackground
        upButton.setTitleColor(theme.primaryText, for: .normal)
        upButton.contentEdgeInsets = UIEdgeInsets(top: dp(2), left: dp(4), bottom: dp(2), right: dp(4))
        upButton.addTarget(self, action: #selector(navigateUp), for: .touchUpInside)
        upButton.accessibilityIdentifier = "Up-\(title)"
        
        pathRow.addArrangedSubview(upButton)
#if targetEnvironment(macCatalyst)
        for (symbol, action, identifier) in [("chevron.left", #selector(navigateBack), "Back"),
                                             ("chevron.right", #selector(navigateForward), "Forward")] {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityIdentifier = "\(identifier)-\(title)"
            button.accessibilityLabel = L10n.get(identifier.lowercased())
            button.addTarget(self, action: action, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            pathRow.insertArrangedSubview(button, at: pathRow.arrangedSubviews.count - 1)
        }
#endif
        pathRow.addArrangedSubview(pathText)
#if targetEnvironment(macCatalyst)
        pathRow.addArrangedSubview(selectionText)
#else
        let breadcrumbs = UIButton(type: .system)
        breadcrumbs.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        breadcrumbs.accessibilityIdentifier = "Breadcrumbs-\(title)"
        breadcrumbs.accessibilityLabel = L10n.get("mobile_path")
        breadcrumbs.showsMenuAsPrimaryAction = true
        breadcrumbs.widthAnchor.constraint(equalToConstant: 44).isActive = true
        breadcrumbs.heightAnchor.constraint(equalToConstant: 44).isActive = true
        breadcrumbButton = breadcrumbs
        pathRow.addArrangedSubview(breadcrumbs)
#endif
        loadingIndicator.accessibilityIdentifier = "DirectoryLoading-\(title)"
        loadingIndicator.accessibilityLabel = L10n.get("directory_loading")
        pathRow.addArrangedSubview(loadingIndicator)
        if listingPending { loadingIndicator.startAnimating() }
        
        pathText.translatesAutoresizingMaskIntoConstraints = false
        selectionText.translatesAutoresizingMaskIntoConstraints = false
        upButton.translatesAutoresizingMaskIntoConstraints = false
        
        upButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        upButton.setContentHuggingPriority(.required, for: .horizontal)
        upButton.heightAnchor.constraint(equalToConstant: dp(44)).isActive = true
        upButton.widthAnchor.constraint(equalToConstant: dp(44)).isActive = true
        pathText.heightAnchor.constraint(equalToConstant: dp(44)).isActive = true
        
        pathText.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        selectionText.setContentHuggingPriority(.required, for: .horizontal)
        selectionText.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        shell.addArrangedSubview(pathRow)
        pathRow.setContentHuggingPriority(.required, for: .vertical)
        pathRow.setContentCompressionResistancePriority(.required, for: .vertical)
        
        let columns = UIStackView()
        columns.axis = .horizontal
        columns.spacing = dp(6)
        columns.distribution = .fillEqually
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)
        
        let treeColumn = createColumn(title: L10n.get("tree"), accent: accent, theme: theme)
        treeList = UITableView()
        treeList.accessibilityIdentifier = "TreeList-\(title)"
        treeList.backgroundColor = theme.treeBackground
        treeList.separatorStyle = .singleLine
        treeList.separatorColor = theme.columnBorder
        treeList.dataSource = self
        treeList.delegate = self
        treeList.register(UITableViewCell.self, forCellReuseIdentifier: "TreeCell")
        treeColumn.addArrangedSubview(treeList)
        
        let fileColumn = createColumn(title: L10n.get("files"), accent: accent, theme: theme)
#if !targetEnvironment(macCatalyst)
        mobileTreeColumn = treeColumn
        treeColumn.isHidden = !treeVisible
        if let header = fileColumn.arrangedSubviews.first as? UIStackView {
            let spacer = UIView(); header.addArrangedSubview(spacer)
            let treeToggle = UIButton(type: .system)
            treeToggle.setImage(UIImage(systemName: "sidebar.left"), for: .normal)
            treeToggle.accessibilityIdentifier = "ToggleTree-\(title)"
            treeToggle.accessibilityLabel = L10n.get("tree")
            treeToggle.isSelected = treeVisible
            treeToggle.addAction(UIAction { [weak self, weak treeToggle] _ in
                guard let self else { return }
                let visible = !self.treeVisible
                self.treeVisible = visible
                UserDefaults.standard.set(visible, forKey: "mobile_tree_" + self.title)
                self.mobileTreeColumn?.isHidden = !visible
                treeToggle?.isSelected = visible
            }, for: .touchUpInside)
            let focus = UIButton(type: .system)
            focus.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
            focus.accessibilityIdentifier = "FocusPane-\(title)"
            focus.accessibilityLabel = L10n.get("mobile_focus")
            focus.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.viewController?.toggleMobilePane(self)
            }, for: .touchUpInside)
            for button in [treeToggle, focus] {
                button.widthAnchor.constraint(equalToConstant: 44).isActive = true
                button.heightAnchor.constraint(equalToConstant: 44).isActive = true
                header.addArrangedSubview(button)
            }
        }
#endif
#if targetEnvironment(macCatalyst)
        let filter = CommanderFilterField()
        filterInput = filter
        filter.applyTheme(theme, placeholder: L10n.get("filter_names"))
        filter.text = nameFilter
        filter.accessibilityIdentifier = "Filter-\(title)"
        filter.clearButtonMode = .always
        filter.font = .systemFont(ofSize: 12)
        filter.addAction(UIAction { [weak self, weak filter] _ in
            self?.nameFilter = filter?.text ?? ""
            self?.applyListingOrder()
        }, for: .editingChanged)
        fileColumn.addArrangedSubview(filter)
        let filterNote = UILabel(); filterNote.font = .systemFont(ofSize: 11); filterNote.numberOfLines = 0
        filterNote.textColor = theme.secondaryText
        filterNote.accessibilityIdentifier = "FilterStatus-\(title)"; filterStatus = filterNote
        let clear = UIButton(type: .system); clear.setTitle(L10n.get("filter_clear"), for: .normal)
        clear.accessibilityIdentifier = "ClearFilter-\(title)"; clearFilterButton = clear
        clear.addAction(UIAction { [weak self] _ in self?.filterInput?.text = ""; self?.nameFilter = ""; self?.applyListingOrder() }, for: .touchUpInside)
        let filterRow = UIStackView(arrangedSubviews: [filterNote, clear]); filterRow.spacing = 8
        fileColumn.addArrangedSubview(filterRow)
        let sortRow = UIStackView()
        sortRow.distribution = .fill
        for (index, key) in ["sort_name", "sort_size", "sort_type", "sort_date"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(L10n.get(key), for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 11)
            button.accessibilityIdentifier = "Sort-\(title)-\(index)"
            if index > 0 { button.widthAnchor.constraint(equalToConstant: [0, 90, 70, 125][index]).isActive = true }
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.sortAscending = self.sortField == index ? !self.sortAscending : true
                self.sortField = index
                self.applyListingOrder()
            }, for: .touchUpInside)
            sortRow.addArrangedSubview(button)
        }
        fileColumn.addArrangedSubview(sortRow)
#endif
#if targetEnvironment(macCatalyst)
        fileList = CommanderSelectionTableView()
#else
        fileList = UITableView()
#endif
#if targetEnvironment(macCatalyst)
        directoryMenu = CommanderDirectoryMenu(table: fileList) { [weak self] in
            guard let self, let controller = self.viewController else { return nil }
            controller.activePane = self; controller.view.endEditing(true)
            let writable = self.currentDirectory.canWriteDirectory() && !controller.operationInProgress
            let mutations: UIMenuElement.Attributes = writable ? [] : .disabled
            let idle: UIMenuElement.Attributes = controller.operationInProgress ? .disabled : []
            return UIMenu(children: [
                UIAction(title: L10n.get("new_folder"), image: UIImage(systemName: "folder.badge.plus"), attributes: mutations) { [weak self] _ in
                    guard let self else { return }; controller.activePane = self; controller.createFolder()
                },
                UIAction(title: L10n.get("paste"), image: UIImage(systemName: "doc.on.clipboard"), attributes: mutations) { [weak self] _ in
                    guard let self else { return }; controller.activePane = self; controller.pasteClipboard()
                },
                UIAction(title: L10n.get("refresh"), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                    self?.reloadTreeKeepingExpansion(); self?.refreshFiles()
                },
                UIAction(title: L10n.get("commander_search"), image: UIImage(systemName: "magnifyingglass"), attributes: idle) { [weak self] _ in
                    guard let self else { return }; controller.activePane = self; controller.showCommanderSearch()
                },
                UIAction(title: L10n.get("directory_copy_path")) { [weak self] _ in UIPasteboard.general.string = self?.currentDirectory.url.path }
            ])
        }
#endif
        fileList.accessibilityIdentifier = "FileList-\(title)"
        fileList.backgroundColor = theme.fileBackground
        fileList.separatorStyle = .singleLine
        fileList.separatorColor = theme.columnBorder
        fileList.dataSource = self
        fileList.delegate = self
        fileList.dataSource = self
        fileList.rowHeight = 44
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleFileListDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = true
        doubleTap.delaysTouchesEnded = false
        fileList.addGestureRecognizer(doubleTap)
        
        setupDragAndDrop()
        
        fileList.register(FileCell.self, forCellReuseIdentifier: "FileCell")
        fileColumn.addArrangedSubview(fileList)
        
        columns.addArrangedSubview(treeColumn)
#if targetEnvironment(macCatalyst)
        let divider = UIView()
        divider.backgroundColor = theme.columnBorder
        divider.widthAnchor.constraint(equalToConstant: 6).isActive = true
        divider.accessibilityIdentifier = "TreeDivider-\(title)"
        divider.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeTree(_:))))
        columns.addArrangedSubview(divider)
#endif
        columns.addArrangedSubview(fileColumn)
#if targetEnvironment(macCatalyst)
        columns.distribution = .fill
        let savedFraction = UserDefaults.standard.double(forKey: "tree_fraction_\(title)")
        treeFraction = savedFraction > 0 ? CGFloat(min(0.55, max(0.15, savedFraction))) : 0.28
        resizingColumns = columns
        resizingTree = treeColumn
        treeWidthConstraint = treeColumn.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: treeFraction)
        treeWidthConstraint?.isActive = true
#endif
        
        treeColumn.translatesAutoresizingMaskIntoConstraints = false
        fileColumn.translatesAutoresizingMaskIntoConstraints = false
        
        shell.addArrangedSubview(columns)
#if !targetEnvironment(macCatalyst)
        shell.addArrangedSubview(selectionText)
#endif
        
        refreshFiles()
        rebuildTree()
        
#if targetEnvironment(macCatalyst)
        mountOnlineView()
        configureArchiveDrag()
#endif
        return shell
    }

    @objc private func resizeTree(_ gesture: UIPanGestureRecognizer) {
        guard let columns = resizingColumns, let tree = resizingTree, columns.bounds.width > 0 else { return }
        treeFraction = min(0.55, max(0.15, treeFraction + gesture.translation(in: columns).x / columns.bounds.width))
        gesture.setTranslation(.zero, in: columns)
        treeWidthConstraint?.isActive = false
        treeWidthConstraint = tree.widthAnchor.constraint(equalTo: columns.widthAnchor, multiplier: treeFraction)
        treeWidthConstraint?.isActive = true
        if gesture.state == .ended { UserDefaults.standard.set(Double(treeFraction), forKey: "tree_fraction_\(title)") }
    }
    
    private func createColumn(title: String, accent: String, theme: ViewController.ThemeColors) -> UIStackView {
        let col = UIStackView()
        col.axis = .vertical
        col.layer.borderWidth = 1
        col.layer.borderColor = theme.columnBorder.cgColor
        col.backgroundColor = theme.columnBackground
        col.layer.cornerRadius = 10
        col.clipsToBounds = true
        
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.backgroundColor = theme.columnHeaderBackground
        headerRow.isLayoutMarginsRelativeArrangement = true
        headerRow.layoutMargins = UIEdgeInsets(top: 0, left: dp(10), bottom: 0, right: dp(10))
        
        let label = UILabel()
        label.text = title
        label.textColor = UIColor(hex: accent)
#if targetEnvironment(macCatalyst)
        let dark = viewController?.darkMode == true
        label.textColor = UIColor(hex: self.title == "1" ? (dark ? "#88baff" : "#185bb5") : (dark ? "#79dcb9" : "#147454"))
#endif
        label.font = UIFont.boldSystemFont(ofSize: 12)
        
        headerRow.addArrangedSubview(label)
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.heightAnchor.constraint(greaterThanOrEqualToConstant: dp(32)).isActive = true
        headerRow.setContentHuggingPriority(.required, for: .vertical)
        headerRow.setContentCompressionResistancePriority(.required, for: .vertical)
        
        col.addArrangedSubview(headerRow)
        return col
    }
    
    @objc func navigateUp() {
#if !targetEnvironment(macCatalyst)
        if currentDirectory.key() == rootNode.entry.key() {
            viewController?.activePane = self
            viewController?.showComputerLocations()
            return
        }
#endif
        if let parent = currentDirectory.parent {
            reentrySelection = (navigationKey(parent), navigationKey(currentDirectory))
            openDirectory(parent)
        }
    }

    @objc func navigateBack() {
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(currentDirectory)
        showDirectory(previous)
    }

    @objc func navigateForward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(currentDirectory)
        showDirectory(next)
    }

    private func isEntryInside(_ parent: FileEntry, _ child: FileEntry) -> Bool {
#if targetEnvironment(macCatalyst)
        if parent.isPhysicalDirectory() {
            let parentPath = parent.url.standardizedFileURL.path
            let childPath = child.url.standardizedFileURL.path
            if parentPath == "/" || childPath == parentPath || childPath.hasPrefix(parentPath + "/") { return true }
        }
#endif
        var cursor: FileEntry? = child
        while let c = cursor {
            if c.key() == parent.key() { return true }
            cursor = c.parent
        }
        return false
    }

    func openDirectory(_ directory: FileEntry) {
        viewController?.activePane = self
        guard currentDirectory.key() != directory.key() else { return }
        backHistory.append(currentDirectory)
        forwardHistory.removeAll()
        showDirectory(directory)
    }

    private func navigationKey(_ entry: FileEntry) -> String {
        // Foundation may return /private/tmp children for a typed /tmp URL.
        // Keep the actual selection key; normalize only this navigation match.
        entry.url.standardizedFileURL.path + String(entry.key().dropFirst(entry.url.path.count))
    }
    private func showDirectory(_ directory: FileEntry) {
        if reentrySelection?.directory != navigationKey(directory) { reentrySelection = nil }
        currentDirectory = directory
        if !isEntryInside(rootNode.entry, directory) {
            treeGeneration += 1
            rootNode = TreeNode(entry: directory, depth: 0)
            rootNode.expanded = true
            loadChildren(for: rootNode)
        }
#if targetEnvironment(macCatalyst)
        _ = ensureTreePathVisible(rootNode, target: currentDirectory)
#endif
        rebuildTree()
        refreshFiles()
    }
    
    func refreshFiles() {
        let directory = currentDirectory!
        listingGeneration += 1
        let generation = listingGeneration
        if listedDirectoryKey != directory.key() {
            visibleEntries.removeAll()
            allEntries.removeAll()
            selectedKeys.removeAll()
        }
        listedDirectoryKey = directory.key()
        listingPending = true
        loadingIndicator.startAnimating()
        currentDirectoryBytes = -1
        showDirectoryMessage(visibleEntries.isEmpty ? L10n.get("directory_loading") : nil, retry: false)
        updateSelectionStatus()
        fileList?.reloadData()

#if targetEnvironment(macCatalyst)
        observeCloudDirectory(directory.url)
#endif
        Self.listingQueue.addOperation { [weak self] in
            let result = Result { try directory.readChildren(directoriesOnly: false) }
            DispatchQueue.main.async {
                guard let self, self.listingGeneration == generation,
                      self.currentDirectory.key() == directory.key() else { return }
                self.finishListing(result)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.listingGeneration == generation, self.listingPending else { return }
            self.showDirectoryMessage(L10n.get("directory_waiting"), retry: true)
        }

    }

#if targetEnvironment(macCatalyst)
    private func observeCloudDirectory(_ url: URL) {
        guard cloudObserver?.presentedItemURL != url else { return }
        cloudObserver?.stop()
        cloudObserver = nil
        cloudRefreshWork?.cancel()
        guard HostFileSystem.isCloudStorage(url) else { return }
        cloudObserver = CloudDirectoryObserver(url: url) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.currentDirectory.url == url else { return }
                self.cloudRefreshWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.currentDirectory.url == url,
                          self.viewController?.operationInProgress == false else { return }
                    self.reloadTreeKeepingExpansion()
                    self.refreshFiles()
                }
                self.cloudRefreshWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
        }
    }
#endif

    private func finishListing(_ result: Result<[FileEntry], Error>) {
        listingPending = false
        loadingIndicator.stopAnimating()
        switch result {
        case .success(let entries):
            allEntries = entries
#if targetEnvironment(macCatalyst)
            if currentDirectory.isListedPhysicalDirectory {
                viewController?.recordVisitedLocalDirectory(currentDirectory.url, forPane: title)
            }
#endif
            applyListingOrder()
        case .failure(let error):
            // Do not leave stale rows actionable after a failed refresh.
            visibleEntries.removeAll()
            allEntries.removeAll()
            currentDirectoryBytes = -2
#if targetEnvironment(macCatalyst)
            // Cocoa/FileProvider descriptions can stay English even when the
            // application language is German. Keep the explanation in our UI
            // language; retain the stable diagnostic code, not a frozen OS sentence.
            let failure = HistoryFailure(error)
            let diagnostic = "(\(failure.domain) \(failure.code))"
            let message = HostFileSystem.cloudClientName(for: currentDirectory.url).map {
                String(format: L10n.get(HostFileSystem.isDisabledProvider(error as NSError)
                    ? "cloud_domain_disabled" : "cloud_unavailable"), $0) + "\n" + diagnostic
            } ?? String(format: L10n.get("directory_error"), failure.message + "\n" + diagnostic)
#else
            let message = L10n.get(MobileStorageIssue.key(for: error))
#endif
            showDirectoryMessage(message, retry: true)
        }
        let newKeys = Set(visibleEntries.map { $0.key() })
        selectedKeys = selectedKeys.intersection(newKeys)
        updateSelectionStatus()
        fileList?.reloadData()
        if let reentry = reentrySelection, reentry.directory == navigationKey(currentDirectory) {
            reentrySelection = nil
            if case .success = result, let row = visibleEntries.firstIndex(where: { navigationKey($0) == reentry.entry }) {
                let key = visibleEntries[row].key()
                selectedKeys = [key]; selectionAnchor = key
                updateSelectionStatus(); fileList?.reloadData()
                fileList?.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: false)
            }
        }
        if case .success = result { scanDirectorySize() }
    }

    private func applyListingOrder() {
        let filtered = allEntries.filter { nameFilter.isEmpty || $0.name().localizedCaseInsensitiveContains(nameFilter) }
        // readChildren already sorts directory-first/natural-name in the worker.
        // Do not repeat that expensive comparison on the UI thread for the
        // default order, particularly for tens of thousands of entries.
        visibleEntries = sortField == 0 && sortAscending ? filtered : filtered.sorted { lhs, rhs in
                if lhs.isDirectoryLike() != rhs.isDirectoryLike() { return lhs.isDirectoryLike() }
                var order: ComparisonResult
                switch sortField {
                case 1: order = lhs.size() == rhs.size() ? .orderedSame : (lhs.size() < rhs.size() ? .orderedAscending : .orderedDescending)
                case 2: order = (lhs.name() as NSString).pathExtension.localizedCaseInsensitiveCompare((rhs.name() as NSString).pathExtension)
                case 3: order = lhs.modified() == rhs.modified() ? .orderedSame : (lhs.modified() < rhs.modified() ? .orderedAscending : .orderedDescending)
                default: order = .orderedSame
                }
                if order == .orderedSame { order = lhs.name().localizedStandardCompare(rhs.name()) }
                return sortAscending ? order == .orderedAscending : order == .orderedDescending
            }
        selectedKeys.formIntersection(Set(visibleEntries.map { $0.key() }))
        filterStatus?.isHidden = nameFilter.isEmpty; clearFilterButton?.isHidden = nameFilter.isEmpty
        filterStatus?.text = visibleEntries.isEmpty ? L10n.get("filter_no_matches") : String(format: L10n.get("filter_active_status"), visibleEntries.count, allEntries.count)
        fileList?.reloadData()
        updateSelectionStatus()
        let emptyMessage = listingPending ? "directory_loading" : (nameFilter.isEmpty ? "directory_empty" : "filter_no_matches")
        showDirectoryMessage(visibleEntries.isEmpty ? L10n.get(emptyMessage) : nil, retry: false)
    }

    private func showDirectoryMessage(_ message: String?, retry: Bool) {
        guard let message else { fileList?.backgroundView = nil; return }
        let container = UIScrollView()
        // Empty-state decoration must not become the hit-test target of a drop.
        // Error states retain their interactive retry/reconnect buttons.
        container.isUserInteractionEnabled = retry
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 13)
        label.textColor = viewController?.theme.secondaryText
        label.accessibilityIdentifier = "DirectoryMessage-\(title)"
        stack.addArrangedSubview(label)
        if retry {
            let button = UIButton(type: .system)
            button.setTitle(L10n.get("directory_retry"), for: .normal)
            button.accessibilityIdentifier = "DirectoryRetry-\(title)"
            button.addAction(UIAction { [weak self] _ in
                self?.reloadTreeKeepingExpansion()
                self?.refreshFiles()
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
#if !targetEnvironment(macCatalyst)
            let chooseButton = UIButton(type: .system)
            chooseButton.setTitle(L10n.get("choose_another_folder"), for: .normal)
            chooseButton.titleLabel?.numberOfLines = 0
            chooseButton.titleLabel?.textAlignment = .center
            chooseButton.titleLabel?.font = .systemFont(ofSize: 13)
            chooseButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            chooseButton.accessibilityIdentifier = "DirectoryChooseFolder-\(title)"
            chooseButton.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.viewController?.activePane = self
                self.viewController?.showComputerLocations()
            }, for: .touchUpInside)
            stack.addArrangedSubview(chooseButton)
            chooseButton.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
#else
            if HostFileSystem.cloudClientName(for: currentDirectory.url) != nil {
                let reconnect = UIButton(type: .system)
                reconnect.setTitle(L10n.get("cloud_setup"), for: .normal)
                reconnect.accessibilityIdentifier = "OpenSyncClient-\(title)"
                reconnect.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.viewController?.openSyncApplication(for: self.currentDirectory.url)
                }, for: .touchUpInside)
                stack.addArrangedSubview(reconnect)
                if HostFileSystem.cloudClientName(for: currentDirectory.url) == "OneDrive" {
                    let online = UIButton(type: .system)
                    online.setTitle(L10n.get("onedrive_open_online"), for: .normal)
                    online.accessibilityIdentifier = "OpenOneDriveOnline-\(title)"
                    online.addAction(UIAction { [weak self] _ in
                        self?.viewController?.openOneDriveOnline()
                    }, for: .touchUpInside)
                    stack.addArrangedSubview(online)
                }
            }
#endif
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: container.contentLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.contentLayoutGuide.trailingAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: container.frameLayoutGuide.widthAnchor, constant: -24)
        ])
        fileList?.backgroundView = container
    }
    
    func rebuildTree() {
        // Loading hovered children completes asynchronously. Preserve the
        // visible node, otherwise reloadData can jump back to the system root
        // while the user is still holding a file over a lower tree row.
        let anchor = treeList?.indexPathsForVisibleRows?.first
        let anchorKey = anchor.flatMap { flatTree.indices.contains($0.row) ? flatTree[$0.row].entry.key() : nil }
        let anchorY = anchor.map { treeList.rectForRow(at: $0).minY - treeList.contentOffset.y }
        flatTree.removeAll()
        addVisibleNode(rootNode)
        treeList?.reloadData()
        treeList?.layoutIfNeeded()
        if let anchorKey, let anchorY, let row = flatTree.firstIndex(where: { $0.entry.key() == anchorKey }), let treeList {
            let lower = -treeList.adjustedContentInset.top
            let upper = max(lower, treeList.contentSize.height - treeList.bounds.height + treeList.adjustedContentInset.bottom)
            let desired = treeList.rectForRow(at: IndexPath(row: row, section: 0)).minY - anchorY
            treeList.setContentOffset(CGPoint(x: treeList.contentOffset.x, y: max(lower, min(upper, desired))), animated: false)
        }
    }

    func reloadTreeKeepingExpansion() {
        treeGeneration += 1
        let expandedKeys = Set(flatTree.filter { $0.expanded }.map { $0.entry.key() })
        expandedTreeKeys = expandedKeys
        rootNode = rebuildNode(entry: rootNode.entry, depth: 0, expandedKeys: expandedKeys)
        _ = ensureTreePathVisible(rootNode, target: currentDirectory)
        rebuildTree()
    }

    private func rebuildNode(entry: FileEntry, depth: Int, expandedKeys: Set<String>) -> TreeNode {
        let node = TreeNode(entry: entry, depth: depth)
        node.expanded = depth == 0 || expandedKeys.contains(entry.key())
        if node.expanded {
            loadChildren(for: node)
            node.children = node.children.map { rebuildNode(entry: $0.entry, depth: depth + 1, expandedKeys: expandedKeys) }
        }
        return node
    }

    @discardableResult
    private func ensureTreePathVisible(_ node: TreeNode, target: FileEntry) -> Bool {
        if node.entry.key() == target.key() { return true }
        if !node.loaded { loadChildren(for: node) }
        for child in node.children where isEntryInside(child.entry, target) {
            node.expanded = true
            return ensureTreePathVisible(child, target: target)
        }
        return false
    }

    private func scanDirectorySize() {
        let directory = currentDirectory!
        let generation = listingGeneration
#if !targetEnvironment(macCatalyst)
        // Listing metadata only: never recursively hydrate a provider's folders.
        currentDirectoryBytes = allEntries.filter { !$0.isDirectoryLike() }.reduce(0) { $0 + max(0, $1.size()) }
        updateSelectionStatus()
        return
#else
        let directoryPath = directory.url.standardizedFileURL.path
        let homePath = HostFileSystem.homeDirectory.standardizedFileURL.path
        let volumePaths = Set((FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []).map { $0.standardizedFileURL.path })
        if directoryPath == "/" || directoryPath == homePath || volumePaths.contains(directoryPath) ||
            HostFileSystem.isCloudStorage(directory.url) {
            currentDirectoryBytes = -2
            updateSelectionStatus()
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let bytes = directory.contentBytes()
            DispatchQueue.main.async {
                guard self.listingGeneration == generation, self.currentDirectory.key() == directory.key() else { return }
                self.currentDirectoryBytes = bytes
                self.updateSelectionStatus()
            }
        }
#endif
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        activatePane()
        let requestedPath = textField.text ?? ""
        textField.resignFirstResponder()
        openTypedPath(requestedPath)
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        activatePane()
#if !targetEnvironment(macCatalyst)
        textField.text = currentDirectory.displayPath()
#endif
    }
    func textFieldDidEndEditing(_ textField: UITextField) { updateSelectionStatus() }
#if !targetEnvironment(macCatalyst)
    private func updateMobilePath() {
        var chain: [FileEntry] = []
        var cursor: FileEntry? = currentDirectory
        while let entry = cursor, chain.count < 128 {
            chain.insert(entry, at: 0)
            if entry.key() == rootNode.entry.key() { break }
            cursor = entry.parent
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        func label(_ entry: FileEntry) -> String {
            if entry.url.standardizedFileURL.path.replacingOccurrences(of: "/private/var/", with: "/var/") == documents.standardizedFileURL.path.replacingOccurrences(of: "/private/var/", with: "/var/") && entry.zipPath == nil {
                return L10n.get("local_documents")
            }
            return entry.name()
        }
        if !pathText.isFirstResponder { pathText.text = chain.map(label).joined(separator: " › ") }
        let ancestors = chain.map { entry in
            UIAction(title: label(entry), image: UIImage(systemName: "folder"), state: entry.key() == currentDirectory.key() ? .on : .off) { [weak self] _ in self?.openDirectory(entry) }
        }
        let retry = UIAction(title: L10n.get("directory_retry"), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.reloadTreeKeepingExpansion(); self?.refreshFiles()
        }
        breadcrumbButton?.menu = UIMenu(title: L10n.get("mobile_path"), children: ancestors + [retry])
    }
#endif

    @objc private func activatePane() {
        viewController?.activePane = self
        viewController?.updateDesktopActions()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    private func openTypedPath(_ value: String) {
#if targetEnvironment(macCatalyst)
        var input = value
        if input.hasSuffix("!/") { input.removeLast(2) }
        guard let local = CommanderTools.searchDirectory(input) else {
            updateSelectionStatus()
            viewController?.updateGlobalStatus(L10n.get("path_invalid"))
            return
        }
        let path = local.path
#else
        var path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/Documents") {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
            path = documents + String(path.dropFirst("/Documents".count))
        }
        if path.hasSuffix("!/") { path.removeLast(2) }
#endif
        guard !path.isEmpty else {
            updateSelectionStatus()
            viewController?.updateGlobalStatus(L10n.get("path_empty"))
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            updateSelectionStatus()
            viewController?.updateGlobalStatus(L10n.get("path_not_found"))
            return
        }
        let entry = FileEntry(url: URL(fileURLWithPath: path), parent: nil)
        guard isDirectory.boolValue || entry.isZipArchive() else {
            updateSelectionStatus()
            viewController?.updateGlobalStatus(L10n.get("path_not_folder"))
            return
        }
        setRoot(entry)
        rebuildTree()
        refreshFiles()
        viewController?.updateGlobalStatus(L10n.get("folder_opened"))
    }
    
    private func addVisibleNode(_ node: TreeNode) {
        flatTree.append(node)
        if !node.expanded { return }
        if !node.loaded { loadChildren(for: node) }
        for child in node.children {
            addVisibleNode(child)
        }
    }
    
    private func loadChildren(for node: TreeNode) {
        // Mark this attempt before rebuilding to avoid duplicate provider requests.
        // A refresh creates new nodes, so failures and empty startup listings retry.
        node.loaded = true
        let generation = treeGeneration
        Self.listingQueue.addOperation { [weak self, weak node] in
            guard let node else { return }
            let entries = (try? node.entry.readChildren(directoriesOnly: true)) ?? []
            DispatchQueue.main.async {
                guard let self, self.treeGeneration == generation else { return }
                node.children = entries.map {
                    let child = TreeNode(entry: $0, depth: node.depth + 1)
                    child.expanded = self.expandedTreeKeys.contains($0.key())
                    return child
                }
                // Expand the current path once provider metadata has arrived.
                _ = self.ensureTreePathVisible(self.rootNode, target: self.currentDirectory)
                self.rebuildTree()
            }
        }

    }
    
    func updateSelectionStatus() {
        viewController?.updateDesktopActions()
        guard let selectionText = selectionText, let pathText = pathText else { return }
        let sizeStr = currentDirectoryBytes >= 0 ? ByteCountFormatter.string(fromByteCount: currentDirectoryBytes, countStyle: .file) : (currentDirectoryBytes == -2 ? "—" : "...")
        selectionText.text = listingPending ? L10n.get("directory_loading") : "\(selectedKeys.count)/\(visibleEntries.count) | \(sizeStr)"
        // A background size scan must not overwrite a path being typed.
#if targetEnvironment(macCatalyst)
        if !pathText.isFirstResponder { pathText.text = currentDirectory.displayPath() }
#else
        updateMobilePath()
#endif
    }
    
    // MARK: - UITableViewDataSource & Delegate
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView === treeList {
            return flatTree.count
        } else {
            return visibleEntries.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView === treeList {
            let cell = tableView.dequeueReusableCell(withIdentifier: "TreeCell", for: indexPath)
            let node = flatTree[indexPath.row]
            
            var indent = ""
            for _ in 0..<node.depth { indent += "  " }
            let prefix = node.expanded ? "▼ " : (node.entry.isDirectoryLike() ? "▶ " : "")
            
            cell.textLabel?.text = "\(indent)\(prefix)\(node.entry.name())"
            cell.textLabel?.font = UIFont.systemFont(ofSize: 12)
            cell.textLabel?.textColor = viewController?.theme.primaryText
            cell.backgroundColor = .clear
            cell.isAccessibilityElement = true
            cell.accessibilityIdentifier = "Tree-\(title)-\(node.entry.name())"
            cell.accessibilityLabel = node.entry.name()
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
            let entry = visibleEntries[indexPath.row]
            
            cell.configure(with: entry, theme: viewController!.theme, isSelected: selectedKeys.contains(entry.key()))
            cell.activateEntry = { [weak self, weak tableView] in
                guard let self, let tableView, let row = self.visibleEntries.firstIndex(where: { $0.key() == entry.key() }) else { return }
#if targetEnvironment(macCatalyst)
                (tableView as? CommanderSelectionTableView)?.resetSelectionModifiers()
#endif
                self.tableView(tableView, didSelectRowAt: IndexPath(row: row, section: 0))
            }
            cell.isAccessibilityElement = true
            cell.accessibilityIdentifier = "File-\(title)-\(entry.name())"
            cell.accessibilityLabel = entry.name()
            cell.accessibilityTraits = selectedKeys.contains(entry.key()) ? [.button, .selected] : [.button]
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewController?.view.endEditing(true)
        tableView.deselectRow(at: indexPath, animated: true)
        viewController?.activePane = self
        
        if tableView === treeList {
            let node = flatTree[indexPath.row]
            if currentDirectory.key() != node.entry.key() {
                backHistory.append(currentDirectory)
                forwardHistory.removeAll()
            }
            currentDirectory = node.entry
            if !node.loaded { loadChildren(for: node) }
            node.expanded.toggle()
            rebuildTree()
            refreshFiles()
        } else {
            guard visibleEntries.indices.contains(indexPath.row) else { return }
            let entry = visibleEntries[indexPath.row]
#if targetEnvironment(macCatalyst)
            let modifiers = (tableView as? CommanderSelectionTableView)?.consumeSelectionModifiers() ?? []
            let selection = DesktopInteractionPolicy.selection(clicked: entry.key(), visible: visibleEntries.map { $0.key() },
                selected: selectedKeys, anchor: selectionAnchor, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command))
            selectedKeys = selection.keys; selectionAnchor = selection.anchor
#else
            if selectedKeys.contains(entry.key()) {
                selectedKeys.remove(entry.key())
            } else {
                selectedKeys.insert(entry.key())
            }
#endif
            updateSelectionStatus()
            // Keep the cell under the mouse alive while a click turns into a
            // drag. Reloading here destroys UIKit's candidate drag source.
            for cell in tableView.visibleCells {
                guard let index = tableView.indexPath(for: cell), visibleEntries.indices.contains(index.row),
                      let fileCell = cell as? FileCell, let theme = viewController?.theme else { continue }
                let item = visibleEntries[index.row]
                let selected = selectedKeys.contains(item.key())
                fileCell.configure(with: item, theme: theme, isSelected: selected)
                cell.accessibilityTraits = selected ? [.button, .selected] : [.button]
            }
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }

    @objc private func handleFileListDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let indexPath = fileList.indexPathForRow(at: recognizer.location(in: fileList)),
              indexPath.row < visibleEntries.count else { return }
        let entry = visibleEntries[indexPath.row]
        viewController?.activePane = self
        if entry.opensInPaneByDefault() {
            openDirectory(entry)
        } else {
#if targetEnvironment(macCatalyst)
            viewController?.openDesktopEntry(entry)
#else
            viewController?.openExternal(entry)
#endif
        }
    }
}

#if targetEnvironment(macCatalyst)
extension CommanderPane {
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        let entry = tableView === treeList ? flatTree[indexPath.row].entry : visibleEntries[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self, let controller = self.viewController else { return nil }
            controller.activePane = self
            self.viewController?.view.endEditing(true)
            if !self.selectedKeys.contains(entry.key()) {
                self.selectedKeys = DesktopInteractionPolicy.contextSelection(clicked: entry.key(), selected: self.selectedKeys)
                self.updateSelectionStatus()
                self.fileList.reloadData()
            }
            var actions: [UIAction] = [
                UIAction(title: L10n.get("open"), image: UIImage(systemName: "arrow.up.forward.app")) { _ in
                    controller.activePane = self
                    if entry.opensInPaneByDefault() { self.openDirectory(entry) }
                    else { controller.openDesktopEntry(entry) }
                },
                UIAction(title: L10n.get("open_with"), image: UIImage(systemName: "app")) { _ in
                    controller.openDesktopFile(entry, chooseApplication: true)
                },
                UIAction(title: L10n.get("preview"), image: UIImage(systemName: "eye")) { _ in
                    controller.activePane = self
                    controller.previewFile(entry)
                }
            ]
            if entry.isDirectoryLike() {
                actions.append(UIAction(title: L10n.get("browse_contents"), image: UIImage(systemName: "folder")) { _ in
                    self.openDirectory(entry)
                })
            }
            func selectEntry(preserveSelection: Bool = true) {
                controller.activePane = self
                if !preserveSelection || !self.selectedKeys.contains(entry.key()) {
                    self.selectedKeys = preserveSelection
                        ? DesktopInteractionPolicy.contextSelection(clicked: entry.key(), selected: self.selectedKeys)
                        : [entry.key()]
                }
                self.updateSelectionStatus()
                self.fileList.reloadData()
            }
            if entry.isZipArchive() || entry.isZipEntry() {
                actions.append(UIAction(title: L10n.get("extract_archive"), image: UIImage(systemName: "archivebox")) { _ in
                    selectEntry()
                    controller.extractSelection()
                })
            }
            actions.append(UIAction(title: L10n.get("file_info"), image: UIImage(systemName: "info.circle")) { _ in
                selectEntry(preserveSelection: false)
                controller.showFileInfo()
            })
            if entry.isPhysical() {
                for (title, selector) in [("copy", #selector(ViewController.copySelectionToClipboard)),
                                          ("cut", #selector(ViewController.cutSelectionToClipboard)),
                                          ("rename_button", #selector(ViewController.showRenameDialog)),
                                          ("move_to_trash", #selector(ViewController.moveSelectionToTrash))] {
                    actions.append(UIAction(title: L10n.get(title)) { _ in
                        selectEntry()
                        controller.perform(selector)
                    })
                }
            }
            return UIMenu(children: actions)
        }
    }
}
#endif

import UIKit
import UniformTypeIdentifiers

extension CommanderPane: UITableViewDragDelegate, UITableViewDropDelegate {
    func setupDragAndDrop() {
        fileList.dragDelegate = self
        fileList.dropDelegate = self
        fileList.dragInteractionEnabled = true
        treeList.dragDelegate = self
        treeList.dropDelegate = self
        treeList.dragInteractionEnabled = true
    }
    
    // MARK: - Drag Delegate

#if targetEnvironment(macCatalyst)
    private func archiveProvider(_ entry: FileEntry) -> NSItemProvider {
        let archive = entry.url, member = entry.zipPath!
        let type = entry.zipDirectory ? UTType.folder : (UTType(filenameExtension: (entry.name() as NSString).pathExtension) ?? .data)
        return FileDropTransfer.materializingProvider(name: entry.name(), type: type) { root, progress in
            let scoped = archive.startAccessingSecurityScopedResource()
            defer { if scoped { archive.stopAccessingSecurityScopedResource() } }
            let output = root.appendingPathComponent("content")
            var failure: Error?, coordination: NSError?
            NSFileCoordinator().coordinate(readingItemAt: archive, options: [], error: &coordination) { source in
                do {
                    try CommanderNativeArchive.extract(source, prefixes: [member], to: output,
                        maximumBytes: 256 * 1024 * 1024,
                        checkCancellation: { if progress.isCancelled { throw CocoaError(.userCancelled) } })
                } catch { failure = error }
            }
            if let coordination { throw coordination }
            if let failure { throw failure }
            return output.appendingPathComponent(member)
        }
    }

    private func configureArchiveDrag() {
        DesktopBridge.shared?.registerOnlineDragSource(archiveDragSourceID, items: { [weak self] point in
            guard let self, self.onlineBrowser == nil, let window = self.fileList.window, window.isKeyWindow,
                  self.viewController?.presentedViewController == nil,
                  self.viewController?.operationInProgress == false else { return [] }
            let point = CGPoint(x: point.x * window.bounds.width, y: point.y * window.bounds.height)
            let local = self.fileList.convert(point, from: window)
            guard self.fileList.bounds.contains(local), let index = self.fileList.indexPathForRow(at: local),
                  self.visibleEntries.indices.contains(index.row) else { return [] }
            let entry = self.visibleEntries[index.row]
            guard entry.zipPath != nil, !entry.isUpButton else { return [] }
            let entries = self.selectedKeys.contains(entry.key()) ? self.visibleEntries.filter { self.selectedKeys.contains($0.key()) } : [entry]
            return entries.filter { $0.zipPath != nil && !$0.isUpButton }.map { entry in
                entry.dragProvider = self.archiveProvider(entry)
                return ["token": entry.registerArchiveDrag(), "name": entry.name(),
                        "type": (entry.zipDirectory ? UTType.folder : (UTType(filenameExtension: (entry.name() as NSString).pathExtension) ?? .data)).identifier]
            }
        }, write: { token, destination, completion in
            guard let provider = FileEntry.archiveDrag(token)?.dragProvider else {
                completion(CocoaError(.fileReadUnknown) as NSError); return
            }
            FileDropTransfer.load([provider]) { result in
                switch result {
                case .failure(let error): completion(error as NSError)
                case .success(let batch):
                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { batch.releaseResources() }
                        do {
                            guard let file = batch.items.first else { throw CocoaError(.fileReadUnknown) }
                            try FileManager.default.copyItem(at: file.url, to: destination)
                            completion(nil)
                        } catch { completion(error as NSError) }
                    }
                }
            }
        })
    }
#endif
    
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        CommanderDragDiagnostics.event("drag beginning pane \(title) row \(indexPath.row)")
        guard indexPath.section == 0 else { return [] }
        let entries = tableView === treeList ? flatTree.map(\.entry) : visibleEntries
        guard entries.indices.contains(indexPath.row) else { return [] }
        let entry = entries[indexPath.row]
        if entry.isUpButton { return [] }
#if !targetEnvironment(macCatalyst)
        if !entry.isPhysical() { return [] }
#endif
        
        if !selectedKeys.contains(entry.key()) {
            selectedKeys = [entry.key()]
            updateSelectionStatus()
        }
        
        viewController?.activeDragPane = self
        session.localContext = self
        let dragged = tableView === treeList ? [entry] : visibleEntries.filter { selectedKeys.contains($0.key()) }
        return dragged.compactMap { entry in
            guard !entry.isUpButton else { return nil }
            let provider: NSItemProvider
#if targetEnvironment(macCatalyst)
            if entry.zipPath != nil {
                provider = archiveProvider(entry)
            } else { provider = FileDropTransfer.provider(for: entry.url) }
#else
            guard entry.isPhysical() else { return nil }
            provider = FileDropTransfer.provider(for: entry.url)
#endif
            let item = UIDragItem(itemProvider: provider)
            entry.dragProvider = provider
            item.localObject = entry
            return item
        }
    }
    
    // MARK: - Drop Delegate
    
    func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
        CommanderDragDiagnostics.event("drop queried pane \(title) items \(session.items.count)")
        guard viewController?.externalDropInProgress != true, viewController?.fileOperationInProgress != true,
              viewController?.presentedViewController == nil, !session.items.isEmpty else { return false }
#if targetEnvironment(macCatalyst)
        if session.items.allSatisfy({ OneDriveSelection.resolve($0) != nil }) { return true }
        if session.items.allSatisfy({ FileEntry.resolveDrag($0)?.zipPath != nil }) { return true }
#endif
        if session.localDragSession?.localContext is CommanderPane {
            return session.items.allSatisfy { $0.localObject is FileEntry }
        }
        return session.items.allSatisfy { FileDropTransfer.canLoad($0.itemProvider) }
    }

#if targetEnvironment(macCatalyst)
    func nativeFileDrop(_ point: CGPoint, urls: [URL], modifiers: Int, commit: Bool) -> Bool {
        guard !urls.isEmpty else { stopDropHover(); _ = onlineBrowser?.nativeFileDrop(point, urls: [], modifiers: modifiers, commit: false); return false }
        if let onlineBrowser { return onlineBrowser.nativeFileDrop(point, urls: urls, modifiers: modifiers, commit: commit) }
        guard let window = fileList.window, let controller = viewController else { return false }
        let location = CGPoint(x: point.x * window.bounds.width, y: point.y * window.bounds.height)
        for table in [fileList, treeList].compactMap({ $0 }) {
            let local = table.convert(location, from: window)
            guard let target = targetForDrop(in: table, point: local), target.canWriteDirectory(),
                  CommanderDropPolicy.accepts(urls.map { ($0, (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) }, target: target.url) else { continue }
            if commit {
                stopDropHover()
                controller.activePane = self
                controller.receiveExternalDrop(providers: urls.map { FileDropTransfer.provider(for: $0) }, targetDirectory: target,
                    moveOverride: FileDropAction.externalMove(modifiers: modifiers, moveMode: controller.moveMode))
            } else {
                dropHoverTable = table; currentDropSession = nil; nativeDropPoint = location
                trackDropTarget(table, target: target)
            }
            return true
        }
        stopDropHover(); return false
    }
#endif
    private func targetForDrop(in tableView: UITableView, session: UIDropSession) -> FileEntry? {
        targetForDrop(in: tableView, point: FileDropTransfer.location(session, in: tableView))
    }
    private func targetForDrop(in tableView: UITableView, point: CGPoint) -> FileEntry? {
        // Reject a stale callback from a table the pointer has already left.
        // In particular, its old tree row must not become a different target
        // while an external file promise crosses into the adjacent file list.
        guard tableView.bounds.contains(point) else { return nil }
        // Use the actual row under the pointer, not UIKit's insertion index.
        if let index = tableView.indexPathForRow(at: point), index.section == 0 {
            if tableView === treeList, flatTree.indices.contains(index.row) { return flatTree[index.row].entry }
            if tableView === fileList, visibleEntries.indices.contains(index.row) {
                let entry = visibleEntries[index.row]
                if entry.offersDirectoryDrop { return entry }
            }
        }
        if tableView === treeList { return nil }
        return currentDirectory
    }
    private func permittedDrop(_ session: UIDropSession, target: FileEntry) -> Bool {
        let local = session.items.compactMap { FileEntry.resolveDrag($0) }
        guard !local.isEmpty else { return true }
        guard local.count == session.items.count else { return false }
        // Archive entries are exported under their member names, not the
        // archive's own name. Its parent directory is a valid export target.
        return local.filter { $0.isPhysical() }.isEmpty || CommanderDropPolicy.accepts(local.filter { $0.isPhysical() }.map { ($0.url, $0.offersDirectoryDrop) }, target: target.url)
    }
    private func stopDropHover() {
        dropHoverWork?.cancel(); dropHoverWork = nil; dropHoverKey = nil
        dropScrollTimer?.invalidate(); dropScrollTimer = nil
        dropHoverTable = nil; currentDropSession = nil; nativeDropPoint = nil
    }
    private func trackDrop(_ table: UITableView, session: UIDropSession, target: FileEntry) {
        dropHoverTable = table; currentDropSession = session
        nativeDropPoint = nil
        trackDropTarget(table, target: target)
    }
    private func trackDropTarget(_ table: UITableView, target: FileEntry) {
        let hoverKey = table === treeList ? target.key() : nil
        if hoverKey != dropHoverKey {
            dropHoverWork?.cancel(); dropHoverKey = hoverKey
            if let hoverKey {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.dropHoverKey == hoverKey,
                        let node = self.flatTree.first(where: { $0.entry.key() == hoverKey }), !node.expanded else { return }
                    let offset = self.treeList.contentOffset
                    node.expanded = true; self.expandedTreeKeys.insert(hoverKey)
                    if !node.loaded { self.loadChildren(for: node) }
                    self.rebuildTree(); self.treeList.layoutIfNeeded()
                    self.treeList.setContentOffset(offset, animated: false)
                }
                dropHoverWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
            }
        }
        if dropScrollTimer == nil {
            dropScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                guard let self, let table = self.dropHoverTable,
                      let point = self.currentDropSession.map({ FileDropTransfer.location($0, in: table) }) ?? self.nativeDropPoint.map({ table.convert($0, from: table.window) }) else { return }
                let y = point.y - table.contentOffset.y
                let delta: CGFloat = y < 24 ? -12 : y > table.bounds.height - 24 ? 12 : 0
                if delta != 0 {
                    let lower = -table.adjustedContentInset.top
                    let upper = max(lower, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
                    table.setContentOffset(CGPoint(x: table.contentOffset.x, y: max(lower, min(upper, table.contentOffset.y + delta))), animated: false)
                }
            }
            if let timer = dropScrollTimer { RunLoop.main.add(timer, forMode: .common) }
        }
    }
    func tableView(_ tableView: UITableView, dropSessionDidExit session: UIDropSession) { stopDropHover() }
    func tableView(_ tableView: UITableView, dropSessionDidEnd session: UIDropSession) { stopDropHover() }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        guard self.tableView(tableView, canHandle: session),
              let target = targetForDrop(in: tableView, session: session), target.offersDirectoryDrop, permittedDrop(session, target: target) else {
            stopDropHover()
            return UITableViewDropProposal(operation: .forbidden)
        }
        trackDrop(tableView, session: session, target: target)
        let archiveExport = session.items.contains { FileEntry.resolveDrag($0)?.zipPath != nil }
        let operation = FileDropAction.proposal(moveMode: viewController?.moveMode == true,
                                               allowsMove: session.allowsMoveOperation, archive: archiveExport)
        // Dropping on background means copying into the current directory, not
        // into a table row (which does not even exist for an empty directory).
        let row = tableView.indexPathForRow(at: FileDropTransfer.location(session, in: tableView))
        let intoFolder = row.map { index in
            tableView === treeList || (visibleEntries.indices.contains(index.row) && visibleEntries[index.row].offersDirectoryDrop)
        } ?? false
        return UITableViewDropProposal(operation: operation, intent: intoFolder ? .insertIntoDestinationIndexPath : .unspecified)
    }
    
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard coordinator.proposal.operation == .copy || coordinator.proposal.operation == .move else { return }
        CommanderDragDiagnostics.event("drop committed pane \(title)")
        stopDropHover()
        guard self.tableView(tableView, canHandle: coordinator.session),
              let target = targetForDrop(in: tableView, session: coordinator.session), target.canWriteDirectory(), permittedDrop(coordinator.session, target: target),
              let controller = viewController else { return }
        controller.activePane = self
#if targetEnvironment(macCatalyst)
        let online = coordinator.items.compactMap { OneDriveSelection.resolve($0.dragItem) }
        if let first = online.first {
            guard online.count == coordinator.items.count, online.allSatisfy({ $0.browser === first.browser && $0.generation == first.generation }) else { return }
            let selection = OneDriveSelection(browser: first.browser, items: online.flatMap(\.items), generation: first.generation)
            first.browser.exportOnline(selection, to: target.url, move: coordinator.proposal.operation == .move)
            return
        }
#endif
        let archiveEntries = coordinator.items.compactMap { FileEntry.resolveDrag($0.dragItem) }
        if archiveEntries.count == coordinator.items.count, archiveEntries.contains(where: { $0.zipPath != nil }) {
            controller.receiveExternalDrop(providers: coordinator.items.map {
                FileEntry.resolveDrag($0.dragItem)?.dragProvider ?? $0.dragItem.itemProvider
            }, targetDirectory: target, forceCopy: true)
            return
        }
        if let sourcePane = coordinator.session.localDragSession?.localContext as? CommanderPane {
            // Use the actual drag payload, never a selection that may have changed.
            let sources = coordinator.items.compactMap { $0.dragItem.localObject as? FileEntry }
            if sources.contains(where: { $0.zipPath != nil }) {
                controller.receiveExternalDrop(providers: coordinator.items.map {
                    ($0.dragItem.localObject as? FileEntry)?.dragProvider ?? $0.dragItem.itemProvider
                }, targetDirectory: target, forceCopy: true)
                return
            }
            controller.runFileOperation(sources: sources, sourcePane: sourcePane, targetDirectory: target,
                                        move: coordinator.proposal.operation == .move)
        } else {
            controller.receiveExternalDrop(providers: coordinator.items.map { $0.dragItem.itemProvider }, targetDirectory: target,
                                           moveOverride: FileDropAction.externalMove(moveMode: controller.moveMode))
        }
    }

    func tableView(_ tableView: UITableView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { false }

    func tableView(_ tableView: UITableView, dragSessionAllowsMoveOperation session: UIDragSession) -> Bool { true }

    func tableView(_ tableView: UITableView, dragSessionDidEnd session: UIDragSession) {
        stopDropHover()
        if viewController?.activeDragPane === self {
            viewController?.activeDragPane = nil
        }
        // Finder may have moved a directly exported URL. Refresh only this
        // source listing; committed internal operations refresh their own
        // destinations. Rebuilding every tree here also reset hover expansion
        // and scroll position after a cancelled drag.
        // Never delete source files merely because a drag session ended.
        refreshFiles()
    }
}

extension CommanderPane {
    func selectedEntries() -> [FileEntry] {
#if targetEnvironment(macCatalyst)
        if onlineNavigation != nil { return [] }
#endif
        return visibleEntries.filter { selectedKeys.contains($0.key()) }
    }
}
import UIKit

class FileCell: UITableViewCell {
    var activateEntry: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard let activateEntry else { return false }
        activateEntry()
        return true
    }
    private static let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private var thumbnailRequest: QLThumbnailGenerator.Request?
    private var representedKey: String?
    private let thumbnailView = UIImageView()
    let iconView = FileIconView()
    let nameLabel = UILabel()
    let sizeLabel = UILabel()
    let dateLabel = UILabel()
    private let typeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.backgroundColor = .clear
        
        nameLabel.font = UIFont.systemFont(ofSize: 12)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        sizeLabel.font = UIFont.systemFont(ofSize: 10)
        sizeLabel.textColor = .gray
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        dateLabel.font = UIFont.systemFont(ofSize: 10)
        dateLabel.textColor = .gray
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(iconView)
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFit
        contentView.addSubview(thumbnailView)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: iconView.topAnchor),
            thumbnailView.widthAnchor.constraint(equalTo: iconView.widthAnchor),
            thumbnailView.heightAnchor.constraint(equalTo: iconView.heightAnchor)])
        contentView.addSubview(nameLabel)
        contentView.addSubview(sizeLabel)
        contentView.addSubview(dateLabel)

#if targetEnvironment(macCatalyst)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.font = .systemFont(ofSize: 11)
        typeLabel.textColor = .gray
        sizeLabel.textAlignment = .right
        dateLabel.textAlignment = .center
        typeLabel.textAlignment = .center
        contentView.addSubview(typeLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24), iconView.heightAnchor.constraint(equalToConstant: 24),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -4),
            sizeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            sizeLabel.widthAnchor.constraint(equalToConstant: 90),
            sizeLabel.trailingAnchor.constraint(equalTo: typeLabel.leadingAnchor),
            typeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            typeLabel.widthAnchor.constraint(equalToConstant: 70),
            typeLabel.trailingAnchor.constraint(equalTo: dateLabel.leadingAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dateLabel.widthAnchor.constraint(equalToConstant: 125),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
#else
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            
            sizeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sizeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            
            dateLabel.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 8),
            dateLabel.bottomAnchor.constraint(equalTo: sizeLabel.bottomAnchor)
        ])
#endif
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with entry: FileEntry, theme: ViewController.ThemeColors, isSelected: Bool) {
        if let request = thumbnailRequest { QLThumbnailGenerator.shared.cancel(request) }
        thumbnailRequest = nil
        thumbnailView.image = nil
        iconView.isHidden = false
        iconView.text = ""
        let key = "\(entry.key())|\(entry.modified())|\(entry.size())"
        representedKey = key
        let mime = entry.mimeType()
        if entry.zipPath == nil && !entry.isDirectoryLike() && (mime.hasPrefix("image/") || mime.hasPrefix("video/")) {
            if let cached = Self.thumbnails.object(forKey: key as NSString) {
                thumbnailView.image = cached; iconView.isHidden = true
            } else {
                let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: CGSize(width: 48, height: 48), scale: 1, representationTypes: .thumbnail)
                thumbnailRequest = request
                QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                    guard let representation else { return }
                    DispatchQueue.main.async {
                        guard let self, self.representedKey == key else { return }
                        let image = representation.uiImage
                        Self.thumbnails.setObject(image, forKey: key as NSString, cost: 48 * 48 * 4)
                        self.thumbnailView.image = image
                        self.iconView.isHidden = true
                    }
                }
            }
        }
        nameLabel.text = entry.name()
        nameLabel.textColor = theme.primaryText
        
        if entry.isDirectoryLike() && !entry.isZipArchive() {
            sizeLabel.text = "DIR"
            iconView.kind = "folder"
        } else {
            let s = entry.size()
            if s > 1024 * 1024 {
                sizeLabel.text = String(format: "%.1f MB", Double(s) / (1024.0 * 1024.0))
            } else if s > 1024 {
                sizeLabel.text = String(format: "%.1f KB", Double(s) / 1024.0)
            } else {
                sizeLabel.text = "\(s) B"
            }
            
            let mime = entry.mimeType()
            let ext = entry.url.pathExtension.lowercased()
            if mime.starts(with: "image/") { iconView.kind = "image" }
            else if mime.starts(with: "video/") { iconView.kind = "video" }
            else if mime.starts(with: "audio/") { iconView.kind = "audio" }
            else if ext == "pdf" { iconView.kind = "pdf" }
            else if ext == "zip" { iconView.kind = "archive" }
            else if ext == "apk" { iconView.kind = "apk" }
            else if ext == "db" || ext == "sqlite" { iconView.kind = "database" }
            else if ext == "html" || ext == "xml" || ext == "json" || ext == "swift" || ext == "java" || ext == "py" { iconView.kind = "code" }
            else if ext == "txt" || ext == "md" || ext == "log" { iconView.kind = "text" }
            else {
                iconView.kind = "file"
                iconView.text = String(ext.prefix(4))
            }
        }
        iconView.setNeedsDisplay()
#if targetEnvironment(macCatalyst)
        typeLabel.text = entry.isPhysicalDirectory() || entry.zipDirectory ? "DIR" : (entry.name() as NSString).pathExtension.uppercased()
#endif
        
        if entry.modified() > 0 {
            let d = Date(timeIntervalSince1970: TimeInterval(entry.modified() / 1000))
            dateLabel.text = OnlineDisplayPolicy.localDate(d)
        } else {
            dateLabel.text = ""
        }
        
        backgroundColor = isSelected ? theme.selectionBackground : .clear
    }
}
import UIKit

class FileIconView: UIView {
    var kind: String = "file"
    var text: String = ""

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        let w = rect.width
        let h = rect.height
        
        let fillPath = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        UIColor(hex: iconFill(kind: kind)).setFill()
        fillPath.fill()
        
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        
        let box = rect
        if kind == "folder" {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: box.minX + box.width * 0.15, y: box.minY + box.height * 0.35))
            path.addLine(to: CGPoint(x: box.minX + box.width * 0.40, y: box.minY + box.height * 0.35))
            path.addLine(to: CGPoint(x: box.minX + box.width * 0.50, y: box.minY + box.height * 0.20))
            path.addLine(to: CGPoint(x: box.maxX - box.width * 0.15, y: box.minY + box.height * 0.20))
            path.addLine(to: CGPoint(x: box.maxX - box.width * 0.15, y: box.maxY - box.height * 0.20))
            path.addLine(to: CGPoint(x: box.minX + box.width * 0.15, y: box.maxY - box.height * 0.20))
            path.close()
            path.stroke()
        } else if kind == "image" {
            let frame = CGRect(x: box.minX + box.width * 0.15, y: box.minY + box.height * 0.2, width: box.width * 0.7, height: box.height * 0.6)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: 3)
            path.stroke()
            
            let mountain = UIBezierPath()
            mountain.move(to: CGPoint(x: frame.minX + frame.width * 0.12, y: frame.maxY - frame.height * 0.12))
            mountain.addLine(to: CGPoint(x: frame.minX + frame.width * 0.40, y: frame.minY + frame.height * 0.56))
            mountain.addLine(to: CGPoint(x: frame.minX + frame.width * 0.56, y: frame.maxY - frame.height * 0.18))
            mountain.addLine(to: CGPoint(x: frame.minX + frame.width * 0.70, y: frame.minY + frame.height * 0.48))
            mountain.addLine(to: CGPoint(x: frame.maxX - frame.width * 0.10, y: frame.maxY - frame.height * 0.12))
            mountain.stroke()
        } else if kind == "video" {
            let frame = CGRect(x: box.minX + box.width * 0.18, y: box.minY + box.height * 0.24, width: box.width * 0.64, height: box.height * 0.52)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: 3)
            path.stroke()
            
            let play = UIBezierPath()
            play.move(to: CGPoint(x: frame.minX + frame.width * 0.40, y: frame.minY + frame.height * 0.28))
            play.addLine(to: CGPoint(x: frame.minX + frame.width * 0.40, y: frame.maxY - frame.height * 0.28))
            play.addLine(to: CGPoint(x: frame.minX + frame.width * 0.65, y: frame.minY + frame.height * 0.50))
            play.close()
            UIColor.white.setFill()
            play.fill()
        } else if kind == "audio" {
            let note = UIBezierPath()
            note.move(to: CGPoint(x: box.minX + box.width * 0.35, y: box.maxY - box.height * 0.25))
            note.addLine(to: CGPoint(x: box.minX + box.width * 0.35, y: box.minY + box.height * 0.20))
            note.addLine(to: CGPoint(x: box.minX + box.width * 0.70, y: box.minY + box.height * 0.30))
            note.addLine(to: CGPoint(x: box.minX + box.width * 0.70, y: box.maxY - box.height * 0.35))
            note.stroke()
            
            let dot1 = UIBezierPath(arcCenter: CGPoint(x: box.minX + box.width * 0.30, y: box.maxY - box.height * 0.25), radius: 3, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            UIColor.white.setFill()
            dot1.fill()
            
            let dot2 = UIBezierPath(arcCenter: CGPoint(x: box.minX + box.width * 0.65, y: box.maxY - box.height * 0.35), radius: 3, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            dot2.fill()
        } else if kind == "code" {
            drawTextIcon(box: box, txt: "</>")
        } else if kind == "archive" {
            let zip = UIBezierPath()
            zip.move(to: CGPoint(x: box.minX + box.width * 0.3, y: box.minY + box.height * 0.2))
            zip.addLine(to: CGPoint(x: box.maxX - box.width * 0.3, y: box.minY + box.height * 0.2))
            zip.addLine(to: CGPoint(x: box.maxX - box.width * 0.3, y: box.maxY - box.height * 0.2))
            zip.addLine(to: CGPoint(x: box.minX + box.width * 0.3, y: box.maxY - box.height * 0.2))
            zip.close()
            zip.stroke()
            
            let mid = box.minX + box.width * 0.5
            let teeth = UIBezierPath()
            teeth.move(to: CGPoint(x: mid, y: box.minY + box.height * 0.2))
            teeth.addLine(to: CGPoint(x: mid, y: box.minY + box.height * 0.5))
            teeth.stroke()
        } else if kind == "apk" {
            let droid = UIBezierPath()
            droid.move(to: CGPoint(x: box.minX + box.width * 0.3, y: box.minY + box.height * 0.4))
            droid.addLine(to: CGPoint(x: box.maxX - box.width * 0.3, y: box.minY + box.height * 0.4))
            droid.addLine(to: CGPoint(x: box.maxX - box.width * 0.3, y: box.maxY - box.height * 0.3))
            droid.addLine(to: CGPoint(x: box.minX + box.width * 0.3, y: box.maxY - box.height * 0.3))
            droid.close()
            droid.stroke()
            
            let head = UIBezierPath()
            head.addArc(withCenter: CGPoint(x: box.minX + box.width * 0.5, y: box.minY + box.height * 0.35), radius: box.width * 0.2, startAngle: .pi, endAngle: 0, clockwise: true)
            head.stroke()
        } else if kind == "database" {
            let db = UIBezierPath(ovalIn: CGRect(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.2, width: box.width * 0.5, height: box.height * 0.15))
            db.stroke()
            let db2 = UIBezierPath(ovalIn: CGRect(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.4, width: box.width * 0.5, height: box.height * 0.15))
            db2.stroke()
            let db3 = UIBezierPath(ovalIn: CGRect(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.6, width: box.width * 0.5, height: box.height * 0.15))
            db3.stroke()
        } else if kind == "pdf" || kind == "doc" || kind == "sheet" || kind == "slide" {
            drawTextIcon(box: box, txt: kind.uppercased())
        } else {
            drawTextIcon(box: box, txt: text.isEmpty ? "FILE" : text.uppercased())
        }
    }
    
    private func drawTextIcon(box: CGRect, txt: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: txt.count > 2 ? 8 : 10),
            .foregroundColor: UIColor.white
        ]
        let size = (txt as NSString).size(withAttributes: attrs)
        let rect = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
        (txt as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func iconFill(kind: String) -> String {
        if kind == "folder" { return "#F2A91B" }
        if kind == "image" { return "#2F80ED" }
        if kind == "video" { return "#7C3AED" }
        if kind == "audio" { return "#10A36F" }
        if kind == "pdf" { return "#E53935" }
        if kind == "doc" { return "#2B6CB0" }
        if kind == "sheet" { return "#16803A" }
        if kind == "slide" { return "#D97706" }
        if kind == "archive" { return "#8B5CF6" }
        if kind == "apk" { return "#16A34A" }
        if kind == "code" { return "#475569" }
        if kind == "database" { return "#0F766E" }
        if kind == "font" { return "#9333EA" }
        return "#64748B"
    }
}
