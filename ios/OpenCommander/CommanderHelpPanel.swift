#if targetEnvironment(macCatalyst)
import UIKit
import WebKit

final class CommanderHelpPanel: UIViewController, WKNavigationDelegate {
    private let chapters: [CommanderHandbook.Chapter]
    private let web = WKWebView()
    private let search = UIButton(type: .system)
    private let printButton = UIButton(type: .system)
    private let query = UISearchTextField()
    private let searchRow = UIStackView()
    private let searchStatus = UILabel()
    private var searchRevision = 0
    var closeRequested: (() -> Void)?
    init(chapters: [CommanderHandbook.Chapter]) { self.chapters = chapters; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    override var keyCommands: [UIKeyCommand]? {
        guard presentedViewController == nil else { return [] }
        return [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeForKeyboard))]
    }
    @objc private func closeForKeyboard() { closeRequested?() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12; view.clipsToBounds = true
        view.accessibilityIdentifier = "CommanderHelpPanel"
        let title = UILabel(); title.text = L10n.get("help_title"); title.font = .boldSystemFont(ofSize: 16)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        search.setTitle(L10n.currentLanguage.hasPrefix("de") ? "Suchen" : "Search", for: .normal)
        search.accessibilityIdentifier = "HelpSearch"
        search.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.searchRow.isHidden.toggle()
            if self.searchRow.isHidden { self.query.resignFirstResponder() }
            else { self.query.becomeFirstResponder() }
        }, for: .touchUpInside)
        printButton.setTitle(L10n.currentLanguage.hasPrefix("de") ? "Drucken…" : "Print…", for: .normal)
        printButton.accessibilityIdentifier = "HelpPrint"
        printButton.addAction(UIAction { [weak self] _ in self?.showPrintPreview() }, for: .touchUpInside)
        search.isEnabled = false; printButton.isEnabled = false
        let close = UIButton(type: .system); close.setTitle(L10n.get("settings_done"), for: .normal)
        close.accessibilityIdentifier = "HelpClose"
        close.addAction(UIAction { [weak self] _ in self?.closeRequested?() }, for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [title, search, printButton, close]); header.spacing = 12
        query.placeholder = L10n.currentLanguage.hasPrefix("de") ? "Im Handbuch suchen…" : "Search handbook…"
        query.accessibilityIdentifier = "HelpSearchField"; query.returnKeyType = .search
        query.autocorrectionType = .no; query.autocapitalizationType = .none; query.spellCheckingType = .no
        query.addAction(UIAction { [weak self] _ in self?.find(backwards: false, navigate: false) }, for: .editingChanged)
        query.addAction(UIAction { [weak self] _ in self?.find(backwards: false) }, for: .primaryActionTriggered)
        searchStatus.font = .systemFont(ofSize: 12); searchStatus.accessibilityIdentifier = "HelpSearchStatus"
        let previous = UIButton(type: .system); previous.setTitle("↑", for: .normal)
        previous.accessibilityLabel = L10n.currentLanguage.hasPrefix("de") ? "Vorheriger Treffer" : "Previous match"
        previous.accessibilityIdentifier = "HelpSearchPrevious"
        previous.addAction(UIAction { [weak self] _ in self?.find(backwards: true) }, for: .touchUpInside)
        let next = UIButton(type: .system); next.setTitle("↓", for: .normal)
        next.accessibilityLabel = L10n.currentLanguage.hasPrefix("de") ? "Nächster Treffer" : "Next match"
        next.accessibilityIdentifier = "HelpSearchNext"
        next.addAction(UIAction { [weak self] _ in self?.find(backwards: false) }, for: .touchUpInside)
        searchRow.addArrangedSubview(query); searchRow.addArrangedSubview(searchStatus)
        searchRow.addArrangedSubview(previous); searchRow.addArrangedSubview(next)
        searchRow.spacing = 8; searchRow.isHidden = true
        let moreApps = UIButton(type: .system)
        moreApps.setTitle(L10n.get("more_apps"), for: .normal)
        moreApps.accessibilityIdentifier = "HelpMoreApps"
        moreApps.contentHorizontalAlignment = .leading
        moreApps.addAction(UIAction { _ in
            DesktopBridge.shared?.openFile(CommanderHandbook.moreAppsURL, application: nil) { _, _ in }
        }, for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [header, moreApps, searchRow]); controls.axis = .vertical; controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        web.translatesAutoresizingMaskIntoConstraints = false; web.navigationDelegate = self
        view.addSubview(controls); view.addSubview(web)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            controls.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            web.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        web.loadHTMLString(CommanderHandbook.html(chapters, german: L10n.currentLanguage.hasPrefix("de")), baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        search.isEnabled = true; printButton.isEnabled = UIPrintInteractionController.isPrintingAvailable
    }
    private func find(backwards: Bool, navigate: Bool = true) {
        let needle = query.text ?? ""
        if navigate { query.resignFirstResponder(); web.becomeFirstResponder() }
        searchRevision += 1; let revision = searchRevision
        // Arguments are data, never interpolated into executable source. Only
        // our offline handbook is loaded; markup is created using text nodes.
        web.callAsyncJavaScript(CommanderHandbook.searchScript,
            arguments: ["needle": needle, "backwards": backwards, "advance": navigate],
            in: nil, in: .page) { [weak self] result in
            guard let self, self.searchRevision == revision else { return }
            guard case .success(let value) = result, let state = value as? [String: Any],
                  let count = state["count"] as? Int, let index = state["index"] as? Int else {
                self.searchStatus.text = L10n.currentLanguage.hasPrefix("de") ? "Suche nicht verfügbar" : "Search unavailable"
                return
            }
            self.searchStatus.text = needle.isEmpty ? nil : (count > 0
                ? (L10n.currentLanguage.hasPrefix("de") ? "Treffer \(index + 1) von \(count)" : "Match \(index + 1) of \(count)")
                : (L10n.currentLanguage.hasPrefix("de") ? "Keine Treffer" : "No matches"))
        }
    }
    private func showPrintPreview() {
        // Merely opens system preview. A user must choose a printer/PDF and submit.
        guard UIPrintInteractionController.isPrintingAvailable else { return }
        query.resignFirstResponder()
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "OpenCommander · " + (L10n.currentLanguage.hasPrefix("de") ? "Handbuch" : "Handbook")
        info.outputType = .general; controller.printInfo = info
        controller.printFormatter = web.viewPrintFormatter()
        controller.present(from: printButton.bounds, in: printButton, animated: true, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // This handbook deliberately has no website links or remote content.
        let url = navigationAction.request.url
        decisionHandler(url?.scheme == "about" || url == nil ? .allow : .cancel)
    }
}
#endif
