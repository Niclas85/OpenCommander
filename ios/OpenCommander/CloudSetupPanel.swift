#if targetEnvironment(macCatalyst)
import UIKit

/// New connections use their own private backend configuration. Existing accounts
/// and configurations are never overwritten by a cancelled or failed wizard.
final class CloudSetupPanel: UIViewController {
    private var profile: CloudConnection
    private let name = UITextField()
    private let help = UILabel(), status = UILabel(), fieldLabel = UILabel()
    private let answer = UITextField(), choice = UIButton(type: .system)
    private let nextButton = UIButton(type: .system), sms = UIButton(type: .system), browserButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)
    private let clientID = UITextField(), clientSecret = UITextField()
    private let expert = UIButton(type: .system), clientHelp = UILabel()
    private let restart = UIButton(type: .system)
    private var customClientRequested = false
    private var selectedClient: PublicCloudOAuth?
    private var question: CloudSetupQuestion?
    private var selectedValue = ""
    private var requestID: String?
    private var work: Task<Void, Never>?
    private var pending = false
    private var browserURL: URL?
    private var smsSentAt: Date?
    private var smsTimer: Timer?
    var completed: ((CloudConnection) throws -> Void)?
    var closeRequested: (() -> Void)?
    var existingConfigurationRequested: (() -> Void)?
    init(profile: CloudConnection) {
        var value = profile
        value.id = UUID().uuidString
        value.remote = "oc_" + value.id.replacingOccurrences(of: "-", with: "").lowercased()
        value.configPath = HostFileSystem.homeDirectory.appendingPathComponent("Library/Application Support/OpenCommander/CloudSetup/" + value.id + "/rclone.conf").path
        value.root = ""
        self.profile = value
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { smsTimer?.invalidate() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground; view.layer.cornerRadius = 12
        view.accessibilityIdentifier = "CloudSetupPanel"
        let title = UILabel(); title.text = profile.name; title.font = .boldSystemFont(ofSize: 17)
        let close = UIButton(type: .system); close.setTitle(L10n.get("cancel"), for: .normal)
        close.accessibilityIdentifier = "CloudSetupCancel"
        close.addAction(UIAction { [weak self] _ in self?.cancel(); self?.closeRequested?() }, for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [title, close]); header.spacing = 8
        name.text = profile.name; name.borderStyle = .roundedRect; name.accessibilityIdentifier = "CloudSetupName"
        name.accessibilityLabel = L10n.get("remote_name")
        help.numberOfLines = 0; help.font = .systemFont(ofSize: 13)
        help.text = L10n.get(profile.kind == "iclouddrive" ? "cloud_setup_icloud_help" : "cloud_setup_oauth_help")
        status.numberOfLines = 0; status.font = .systemFont(ofSize: 12); status.accessibilityIdentifier = "CloudSetupStatus"
        fieldLabel.numberOfLines = 0; fieldLabel.font = .boldSystemFont(ofSize: 14)
        fieldLabel.accessibilityIdentifier = "CloudSetupFieldLabel"
        answer.borderStyle = .roundedRect; answer.autocorrectionType = .no; answer.autocapitalizationType = .none
        answer.accessibilityIdentifier = "CloudSetupAnswer"; answer.returnKeyType = .next
        answer.addAction(UIAction { [weak self] _ in self?.submit() }, for: .primaryActionTriggered)
        choice.accessibilityIdentifier = "CloudSetupChoice"; choice.showsMenuAsPrimaryAction = true
        nextButton.accessibilityIdentifier = "CloudSetupNext"; nextButton.setTitle(L10n.get("cloud_setup_begin"), for: .normal)
        nextButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        sms.accessibilityIdentifier = "CloudSetupSMS"
        sms.addAction(UIAction { [weak self] _ in self?.requestSMS() }, for: .touchUpInside)
        browserButton.accessibilityIdentifier = "CloudSetupBrowser"
        browserButton.setTitle(L10n.get(profile.kind == "iclouddrive" ? "cloud_setup_icloud_browser" : "cloud_setup_browser"), for: .normal)
        browserButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if let url = self.profile.kind == "iclouddrive" ? self.profile.website : self.browserURL {
                UIApplication.shared.open(url)
                self.status.text = L10n.get("cloud_setup_website_separate")
            }
        }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [activity, nextButton, sms, browserButton]); buttons.spacing = 12
        let existing = UIButton(type: .system); existing.setTitle(L10n.get("cloud_setup_existing"), for: .normal)
        existing.accessibilityIdentifier = "CloudSetupExisting"
        existing.addAction(UIAction { [weak self] _ in self?.cancel(); self?.existingConfigurationRequested?() }, for: .touchUpInside)
        expert.setTitle(L10n.get("cloud_oauth_expert"), for: .normal); expert.isHidden = profile.kind == "iclouddrive"
        expert.accessibilityIdentifier = "CloudSetupExpert"
        clientID.borderStyle = .roundedRect; clientID.placeholder = L10n.get("cloud_oauth_client_id")
        clientID.accessibilityLabel = clientID.placeholder; clientID.accessibilityIdentifier = "CloudSetupClientID"
        clientSecret.borderStyle = .roundedRect; clientSecret.placeholder = L10n.get("cloud_oauth_desktop_secret")
        clientSecret.accessibilityLabel = clientSecret.placeholder; clientSecret.accessibilityIdentifier = "CloudSetupClientSecret"
        clientSecret.isSecureTextEntry = true
        for field in [clientID, clientSecret] { field.autocorrectionType = .no; field.autocapitalizationType = .none; field.isHidden = true }
        clientHelp.numberOfLines = 0; clientHelp.font = .systemFont(ofSize: 12); clientHelp.isHidden = true
        clientHelp.text = L10n.get("cloud_oauth_expert_help")
        expert.addAction(UIAction { [weak self] _ in
            guard let self, !self.pending, self.question == nil else { return }
            let hidden = !self.clientID.isHidden
            self.customClientRequested = !hidden
            self.clientID.isHidden = hidden; self.clientSecret.isHidden = hidden || self.profile.kind != "drive"; self.clientHelp.isHidden = hidden
        }, for: .touchUpInside)
        restart.setTitle(L10n.get("cloud_setup_restart"), for: .normal)
        restart.accessibilityIdentifier = "CloudSetupRestart"
        restart.addAction(UIAction { [weak self] _ in
            guard let self, !self.pending else { return }
            self.resetConnection(); self.displayQuestion(); self.status.text = nil
        }, for: .touchUpInside)
        let content = UIStackView(arrangedSubviews: [header, name, help, expert, clientID, clientSecret, clientHelp, status, fieldLabel, answer, choice, buttons, restart, existing])
        content.axis = .vertical; content.spacing = 12; content.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 16), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        displayQuestion()
    }
    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelAndClose))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }
    override var canBecomeFirstResponder: Bool { true }
    @objc private func cancelAndClose() { cancel(); closeRequested?() }
    func cancel() {
        work?.cancel()
        if let requestID { self.requestID = nil; DesktopBridge.shared?.cancelCloudOperation(requestID) }
        answer.text = nil; clientSecret.text = nil; browserURL = nil; smsTimer?.invalidate(); smsTimer = nil
    }
    private func resetConnection() {
        question = nil; browserURL = nil; selectedClient = nil; selectedValue = ""
        answer.text = nil; smsSentAt = nil; smsTimer?.invalidate(); smsTimer = nil
        profile.id = UUID().uuidString
        profile.remote = "oc_" + profile.id.replacingOccurrences(of: "-", with: "").lowercased()
        profile.configPath = HostFileSystem.homeDirectory.appendingPathComponent("Library/Application Support/OpenCommander/CloudSetup/" + profile.id + "/rclone.conf").path
    }
    private func displayQuestion() {
        let option = question?.Option
        restart.isHidden = question == nil && browserURL == nil
        fieldLabel.isHidden = option == nil; answer.isHidden = option == nil || !(option?.Examples ?? []).isEmpty
        choice.isHidden = (option?.Examples ?? []).isEmpty
        if let option {
            let key: String
            switch option.Name {
            case "apple_id": key = "cloud_setup_apple_id"
            case "password": key = "cloud_setup_password"
            case "config_2fa", "config_2fa_sms": key = "cloud_setup_code"
            case "config_2fa_phone": key = "cloud_setup_phone"
            case "config_driveid": key = "cloud_setup_drive"
            default: key = "cloud_setup_option"
            }
            fieldLabel.text = L10n.get(key)
            answer.accessibilityLabel = fieldLabel.text
            answer.isSecureTextEntry = option.IsPassword == true || option.Name == "config_2fa" || option.Name == "config_2fa_sms"
            answer.text = nil // Never reuse a password, device code or another question's answer.
            selectedValue = option.Examples?.first?.Value ?? ""
            let choices: [CloudSetupQuestion.Field.Choice] = profile.kind == "drive" && option.Name == "config_shared_client_id" ? [
                .init(Value: "false", Help: L10n.get("cloud_google_custom_choice")),
                .init(Value: "true", Help: L10n.get("cloud_google_shared_choice"))
            ] : option.Examples ?? []
            if !choices.isEmpty { selectedValue = choices[0].Value; answer.isHidden = true; choice.isHidden = false }
            choice.setTitle(choices.first?.Help ?? choices.first?.Value, for: .normal)
            choice.menu = UIMenu(children: choices.map { example in
                UIAction(title: example.Help?.isEmpty == false ? example.Help! : example.Value) { [weak self] _ in
                    self?.selectedValue = example.Value; self?.choice.setTitle(example.Help ?? example.Value, for: .normal)
                }
            })
        }
        nextButton.setTitle(L10n.get(option == nil ? "cloud_setup_begin" : "cloud_setup_continue"), for: .normal)
        if profile.kind == "drive" && option?.Name == "config_shared_client_id" {
            help.text = L10n.get("cloud_google_signin_choice")
        } else { help.text = L10n.get(profile.kind == "iclouddrive" ? "cloud_setup_icloud_help" : "cloud_setup_oauth_help") }
        browserButton.isHidden = profile.kind != "iclouddrive" && browserURL == nil
        updateSMS()
    }
    private var supportsSMS: Bool {
        guard profile.kind == "iclouddrive", let question, let field = question.Option?.Name else { return false }
        return (field == "config_2fa" && question.State == "2fa_do") || (field == "config_2fa_sms" && (question.State ?? "").hasPrefix("2fa_sms_"))
    }
    private func updateSMS() {
        sms.isHidden = !supportsSMS
        sms.setTitle(L10n.get(smsSentAt == nil ? "cloud_setup_sms" : "cloud_setup_sms_again"), for: .normal)
        sms.isEnabled = !pending && (smsSentAt.map { Date().timeIntervalSince($0) >= 30 } ?? true)
    }
    private func requestSMS() {
        guard supportsSMS, !pending, sms.isEnabled else { return }
        smsSentAt = Date(); answer.text = nil
        smsTimer?.invalidate()
        smsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }; self.updateSMS()
            if self.smsSentAt.map({ Date().timeIntervalSince($0) >= 30 }) == true { timer.invalidate() }
        }
        start(state: "2fa_do", answer: "sms", password: false)
    }
    private func submit() {
        guard !pending else { return }
        let selectedName = name.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selectedName.isEmpty else { status.text = L10n.get("cloud_invalid"); return }
        profile.name = selectedName
        var value = choice.isHidden ? answer.text ?? "" : selectedValue
        if profile.kind == "drive", question?.Option?.Name == "config_shared_client_id", value == "false" {
            resetConnection(); customClientRequested = true
            clientID.isHidden = false; clientSecret.isHidden = false; clientHelp.isHidden = false
            displayQuestion(); status.text = L10n.get("cloud_oauth_client_invalid"); clientID.becomeFirstResponder()
            return
        }
        if let option = question?.Option {
            if option.Name.hasPrefix("config_2fa") { value = value.trimmingCharacters(in: .whitespacesAndNewlines) }
            if ["config_2fa", "config_2fa_sms"].contains(option.Name) && value.lowercased() == "sms" {
                status.text = L10n.get("cloud_setup_use_sms_button"); return
            }
            if value.isEmpty && (option.Required == true || ["apple_id", "password", "config_2fa", "config_2fa_sms"].contains(option.Name)) {
                status.text = L10n.get("cloud_setup_field_required"); return
            }
        }
        start(state: question?.State, answer: question == nil ? nil : value, password: question?.Option?.IsPassword == true)
        answer.text = nil
    }
    private func setPending(_ value: Bool) {
        pending = value; name.isEnabled = !value; nextButton.isEnabled = !value; answer.isEnabled = !value; choice.isEnabled = !value
        expert.isEnabled = !value && question == nil; clientID.isEnabled = !value && question == nil; clientSecret.isEnabled = !value && question == nil
        restart.isEnabled = !value
        value ? activity.startAnimating() : activity.stopAnimating(); updateSMS()
    }
    private func step(state: String?, answer: String?, password: Bool) async throws -> CloudSetupQuestion {
        guard let bridge = DesktopBridge.shared else { throw CloudConnection.failure("cloud_backend_unavailable") }
        let id = UUID().uuidString; requestID = id
        defer { if requestID == id { requestID = nil } }
        let connection = try JSONEncoder().encode(profile)
        let oauthClient = state == nil ? try selectedClient?.encoded() : nil
        let data: Data = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                bridge.cloudSetup(id, connection: connection, state: state, answer: answer, password: password,
                    oauthClient: oauthClient, browser: { [weak self] url in
                    guard let self, self.requestID == id, self.pending else { return }
                    self.browserURL = url; self.browserButton.isHidden = false
                    UIApplication.shared.open(url)
                    self.status.text = L10n.get("cloud_setup_browser_wait")
                }, completion: { data, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: data ?? Data()) }
                })
            }
        }, onCancel: { bridge.cancelCloudOperation(id) })
        try Task.checkCancellation()
        return try CloudSetupQuestion.decode(data, kind: profile.kind)
    }
    private func start(state: String?, answer: String?, password: Bool) {
        guard !pending else { return }; setPending(true); status.text = L10n.get("cloud_connecting")
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.work = nil; self.setPending(false) }
            do {
                if state == nil {
                    let manualID = self.clientID.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let manualSecret = self.clientSecret.text ?? ""
                    if self.customClientRequested || !manualID.isEmpty || !manualSecret.isEmpty {
                        let value = self.profile.kind == "drive" ? ["client_id": manualID, "client_secret": manualSecret] : ["client_id": manualID, "flow": "pkce"]
                        self.selectedClient = try PublicCloudOAuth.decode(JSONSerialization.data(withJSONObject: value), kind: self.profile.kind)
                    } else { self.selectedClient = try PublicCloudOAuth.bundled(kind: self.profile.kind) }
                }
                var nextQuestion = try await self.step(state: state, answer: answer, password: password)
                var steps = 0
                while let automatic = self.automaticAnswer(nextQuestion) {
                    steps += 1; guard steps <= 128 else { throw CloudConnection.failure("cloud_login_incomplete") }
                    nextQuestion = try await self.step(state: nextQuestion.State, answer: automatic, password: false)
                }
                try Task.checkCancellation()
                if nextQuestion.complete {
                    _ = try await CloudFileClient.browserClient(self.profile).children(of: nil)
                    try Task.checkCancellation()
                    guard let completed = self.completed else { throw CloudConnection.failure("cloud_invalid") }
                    try completed(self.profile)
                    self.status.text = L10n.get("cloud_connected")
                } else {
                    self.question = nextQuestion; self.displayQuestion(); self.status.text = L10n.get("cloud_setup_answer")
                }
            } catch {
                if error is CancellationError { self.status.text = L10n.get("history_error_cancelled") }
                else {
                    let error = error as NSError
                    self.status.text = error.domain == "OpenCommander.Cloud" ? L10n.get(error.localizedDescription) : L10n.get("cloud_login_incomplete")
                }
                // Retry is another NEW private connection. Partial setup never
                // gets reused as an existing account or overwritten.
                self.resetConnection(); self.displayQuestion()
            }
        }
    }
    private func automaticAnswer(_ question: CloudSetupQuestion) -> String? {
        if selectedClient?.pkce == true && question.Option?.Name == "config_refresh_token" { return "false" }
        return question.automaticAnswer(kind: profile.kind)
    }
}
#endif
