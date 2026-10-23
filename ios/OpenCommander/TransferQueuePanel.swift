#if targetEnvironment(macCatalyst)
import UIKit

final class TransferQueuePanel: UIViewController {
    let queue: DurableTransferQueue
    private let stack = UIStackView()
    private let scroll = UIScrollView()
    private let selector = UISegmentedControl(items: ["1", "2", "3", "4"])
    private let pauseAll = UIButton(type: .system)
    private let resumeAll = UIButton(type: .system)
    private let removeCompleted = UIButton(type: .system)
    private let pageControls = UIStackView()
    private let newerPage = UIButton(type: .system)
    private let olderPage = UIButton(type: .system)
    private let pageLabel = UILabel()
    private var pageIndex = 0
    private var pageHeight: NSLayoutConstraint!
    private var rendered: [DurableTransferQueue.Job] = []
    private struct Controls {
        let name: UILabel; let compact: UIButton; let pause: UIButton; let resume: UIButton
        let cancel: UIButton; let forget: UIButton; let progress: UIProgressView
        let route: UILabel; let details: UILabel; let summary: UILabel; let error: UILabel; let timestamp: String; let report: UIButton
    }
    private var controls: [UUID: Controls] = [:]
    private var renderedStoreError: String?
    private var durationTimer: Timer?
    var closeRequested: (() -> Void)?
    var heightRequested: ((CGFloat, Bool) -> Void)?
    private var resizeStart: CGFloat = 0
    init(queue: DurableTransferQueue) { self.queue = queue; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { durationTimer?.invalidate() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12; view.clipsToBounds = true
        view.accessibilityIdentifier = "TransferQueuePanel"
        let grip = UIView(); grip.translatesAutoresizingMaskIntoConstraints = false
        grip.accessibilityIdentifier = "TransferPanelDivider"
        grip.accessibilityLabel = L10n.get("transfer_resize")
        grip.backgroundColor = .separator
        grip.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizePanel(_:))))
        view.addSubview(grip)
        let title = UILabel(); title.text = L10n.get("transfer_queue")
        title.font = .boldSystemFont(ofSize: 16)
        let concurrency = UILabel(); concurrency.text = L10n.get("transfer_parallel")
        selector.accessibilityIdentifier = "TransferParallelism"
        selector.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.queue.setLimit(self.selector.selectedSegmentIndex + 1)
        }, for: .valueChanged)
        let done = UIButton(type: .system); done.setTitle(L10n.get("settings_done"), for: .normal)
        done.addAction(UIAction { [weak self] _ in self?.closeRequested?() }, for: .touchUpInside)
        pauseAll.setTitle(L10n.get("transfer_pause_all"), for: .normal)
        resumeAll.setTitle(L10n.get("transfer_resume_all"), for: .normal)
        pauseAll.accessibilityIdentifier = "TransferPauseAll"
        resumeAll.accessibilityIdentifier = "TransferResumeAll"
        removeCompleted.setTitle(L10n.get("transfer_remove_completed"), for: .normal)
        removeCompleted.titleLabel?.numberOfLines = 2
        removeCompleted.accessibilityIdentifier = "TransferRemoveCompleted"
        removeCompleted.addAction(UIAction { [weak self] _ in self?.queue.forgetCompleted() }, for: .touchUpInside)
        pauseAll.addAction(UIAction { [weak self] _ in self?.queue.controlAll(.pause) }, for: .touchUpInside)
        resumeAll.addAction(UIAction { [weak self] _ in self?.queue.controlAll(.proceed) }, for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [title, concurrency, selector, pauseAll, resumeAll, removeCompleted, done]); header.spacing = 12
        newerPage.setTitle(L10n.get("transfer_newer"), for: .normal)
        olderPage.setTitle(L10n.get("transfer_older"), for: .normal)
        newerPage.accessibilityIdentifier = "TransferPageNewer"
        olderPage.accessibilityIdentifier = "TransferPageOlder"
        pageLabel.accessibilityIdentifier = "TransferPageStatus"
        newerPage.addAction(UIAction { [weak self] _ in self?.changePage(-1) }, for: .touchUpInside)
        olderPage.addAction(UIAction { [weak self] _ in self?.changePage(1) }, for: .touchUpInside)
        [newerPage, pageLabel, olderPage].forEach { pageControls.addArrangedSubview($0) }
        pageControls.spacing = 12; pageControls.alignment = .center
        pageControls.translatesAutoresizingMaskIntoConstraints = false
        pageHeight = pageControls.heightAnchor.constraint(equalToConstant: 0)
        header.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header); view.addSubview(pageControls); view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            grip.topAnchor.constraint(equalTo: view.topAnchor),
            grip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grip.heightAnchor.constraint(equalToConstant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: grip.bottomAnchor, constant: 4),
            pageControls.topAnchor.constraint(equalTo: header.bottomAnchor),
            pageControls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            pageControls.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            pageHeight,
            scroll.topAnchor.constraint(equalTo: pageControls.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
    }
    @objc private func resizePanel(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { resizeStart = view.bounds.height }
        if [.began, .changed, .ended, .cancelled].contains(gesture.state) {
            heightRequested?(resizeStart - gesture.translation(in: view.superview).y, gesture.state == .ended)
        }
    }
    private func changePage(_ delta: Int) {
        pageIndex += delta
        render(rendered, limit: selector.selectedSegmentIndex + 1, error: renderedStoreError, force: true)
    }
    func render(_ jobs: [DurableTransferQueue.Job], limit: Int, error: String?, force: Bool = false) {
        pauseAll.isEnabled = jobs.contains { [.queued, .running].contains($0.state) && $0.requestedControl != "pause" }
        resumeAll.isEnabled = jobs.contains { $0.state == .paused }
        removeCompleted.isEnabled = jobs.contains { $0.state == .completed }
        loadViewIfNeeded(); selector.selectedSegmentIndex = limit - 1
        let page = DurableTransferQueue.cardPage(jobs, index: pageIndex)
        pageIndex = page.index
        newerPage.isEnabled = page.index > 0; olderPage.isEnabled = page.index + 1 < page.count
        pageLabel.text = String(format: L10n.get("transfer_page_status"), page.index + 1, page.count, jobs.count)
        pageControls.isHidden = page.count <= 1; pageHeight.constant = page.count <= 1 ? 0 : 28
        if jobs.contains(where: { $0.state == .running }) {
            if durationTimer == nil {
                durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    for job in DurableTransferQueue.cardPage(self.rendered, index: self.pageIndex).jobs where job.state == .running { self.update(job) }
                }
            }
        } else { durationTimer?.invalidate(); durationTimer = nil }
        if !force, rendered.map(\.id) == jobs.map(\.id), renderedStoreError == error, !controls.isEmpty {
            rendered = jobs
            for job in page.jobs { update(job) }
            return
        }
        rendered = jobs; renderedStoreError = error; controls.removeAll()
        let offset = force ? CGPoint.zero : scroll.contentOffset
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if error != nil || jobs.isEmpty {
            let label = UILabel(); label.text = L10n.get(error ?? "transfer_empty")
            label.numberOfLines = 0; stack.addArrangedSubview(label)
        }
        for job in page.jobs {
            let card = UIStackView(); card.axis = .vertical; card.spacing = 4
            card.isLayoutMarginsRelativeArrangement = true
            card.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            card.backgroundColor = .tertiarySystemBackground; card.layer.cornerRadius = 8
            card.accessibilityIdentifier = "TransferCard-\(job.id)"
            let name = UILabel(); name.text = job.displayName + " · " + L10n.get(job.statusKey)
            name.numberOfLines = 1; name.lineBreakMode = .byTruncatingMiddle; name.font = .systemFont(ofSize: 12)
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // A bounded name and progress leave all applicable controls on the same row.
            let row = UIStackView(arrangedSubviews: [name]); row.spacing = 8; row.alignment = .center
            let progress = UIProgressView(progressViewStyle: .default)
            progress.accessibilityIdentifier = "TransferProgress-\(job.id)"
            progress.widthAnchor.constraint(equalToConstant: 100).isActive = true
            row.addArrangedSubview(progress)
            func button(_ key: String, enabled: Bool = true, action: @escaping () -> Void) -> UIButton {
                let button = UIButton(type: .system); button.setTitle(L10n.get(key), for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 12)
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
                button.accessibilityIdentifier = "\(key)-\(job.id)"; button.isEnabled = enabled
                button.addAction(UIAction { _ in action() }, for: .touchUpInside); row.addArrangedSubview(button)
                return button
            }
            let compact = button("transfer_compact") { [weak self] in self?.queue.compact(job.id) }
            let pause = button("transfer_pause") { [weak self] in self?.queue.control(job.id, .pause) }
            let resume = button("transfer_resume") { [weak self] in self?.queue.control(job.id, .proceed) }
            let cancel = button("cancel") { [weak self] in self?.queue.control(job.id, .cancel) }
            let forget = button("transfer_forget") { [weak self] in self?.queue.forget(job.id) }
            card.addArrangedSubview(row)
            progress.progress = job.state == .completed ? 1 : job.total > 0 ? Float(job.bytes) / Float(job.total) : 0
            let route = UILabel(); route.numberOfLines = 2; route.lineBreakMode = .byTruncatingMiddle; route.font = .systemFont(ofSize: 11)
            route.text = job.routeDescription
            route.accessibilityLabel = route.text
            card.addArrangedSubview(route)
            let details = UILabel(); details.font = .systemFont(ofSize: 11); details.numberOfLines = 0
            let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .medium
            card.addArrangedSubview(details)
            let summary = UILabel(); summary.font = .systemFont(ofSize: 11); summary.numberOfLines = 0
            summary.accessibilityIdentifier = "TransferSummary-\(job.id)"; card.addArrangedSubview(summary)
            let error = UILabel(); error.numberOfLines = 0; error.text = L10n.get("transfer_failed_help"); card.addArrangedSubview(error)
            let report = UIButton(type: .system); report.setTitle(L10n.get("transfer_copy_details"), for: .normal)
            report.accessibilityIdentifier = "TransferCopyDetails-\(job.id)"
            report.accessibilityHint = L10n.get("transfer_details_paths")
            report.addAction(UIAction { [weak self] _ in
                guard let self, let current = self.rendered.first(where: { $0.id == job.id }) else { return }
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                let description = "OpenCommander macOS \(version)\nID: \(current.id)\n" + L10n.get(current.statusKey) + "\n" + current.source + " → " + current.destination + "\n\(current.bytes)/\(current.total) Bytes\n" + self.description(current) + "\n" + (current.errorMessage ?? "")
                UIPasteboard.general.setItems([["public.utf8-plain-text": Data(description.utf8)]], options: [.localOnly: true])
            }, for: .touchUpInside)
            card.addArrangedSubview(report)
            controls[job.id] = Controls(name: name, compact: compact, pause: pause, resume: resume, cancel: cancel,
                forget: forget, progress: progress, route: route, details: details, summary: summary, error: error, timestamp: formatter.string(from: job.created), report: report)
            update(job)
            stack.addArrangedSubview(card)
        }
        view.layoutIfNeeded()
        let minimum = -scroll.adjustedContentInset.top
        let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, offset.y))), animated: false)
    }
    private func update(_ job: DurableTransferQueue.Job) {
        guard let refs = controls[job.id] else { return }
        refs.name.text = job.displayName + " · " + L10n.get(job.statusKey) + " · \(Int(job.progressFraction * 100))%"
        refs.name.accessibilityValue = job.routeDescription + "\n" + description(job) + "\n" + (job.errorMessage ?? "")
        refs.compact.setTitle(L10n.get(job.compact ? "transfer_details" : "transfer_compact"), for: .normal)
        refs.pause.isEnabled = [.running, .queued].contains(job.state) && job.requestedControl == nil
        refs.pause.isHidden = ![.running, .queued].contains(job.state)
        refs.resume.isEnabled = [.paused, .failed].contains(job.state)
        refs.resume.isHidden = ![.paused, .failed].contains(job.state)
        refs.cancel.isEnabled = ![.completed, .cancelled].contains(job.state) && job.requestedControl != "cancel"
        refs.cancel.isHidden = [.completed, .cancelled].contains(job.state)
        refs.forget.isHidden = !job.canForget
        refs.progress.progress = job.progressFraction
        refs.progress.accessibilityLabel = L10n.get(job.isDeletion ? "transfer_processed" : job.isChecking ? "transfer_checked" : "transfer_copied")
        refs.route.isHidden = job.compact; refs.details.isHidden = job.compact
        refs.route.text = job.routeDescription
        refs.route.accessibilityLabel = job.routeDescription
        refs.report.isHidden = job.compact
        refs.error.isHidden = job.compact || job.errorMessage == nil
        refs.error.text = job.errorMessage.map { L10n.get("transfer_previous_error") + " " + $0 }
        if job.engine == "nas-exclusive", job.state != .completed {
            refs.error.isHidden = false
            refs.error.text = L10n.get("transfer_nas_partial") + (refs.error.text.map { "\n" + $0 } ?? "")
        }
        refs.summary.isHidden = true
        refs.summary.text = description(job)
        refs.details.text = refs.timestamp + "\n" + description(job)
    }
    private func description(_ job: DurableTransferQueue.Job) -> String {
        let german = L10n.currentLanguage.hasPrefix("de")
        let elapsed = (job.elapsed ?? 0) + (job.activeSince.map { max(0, Date().timeIntervalSince($0)) } ?? 0)
        let copied = ByteCountFormatter.string(fromByteCount: job.bytes, countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: job.total, countStyle: .file)
        let percent = Int(job.progressFraction * 100)
        var text = L10n.get(job.statusKey) + " · \(percent)%\n" + L10n.get(job.isChecking ? "transfer_already_copied" : "transfer_copied") + ": " + copied
        if job.isDeletion { text = L10n.get(job.statusKey) + "\n" + job.routeDescription }
        if job.isChecking {
            text += "\n" + L10n.get("transfer_checked") + ": " + ByteCountFormatter.string(fromByteCount: job.checkedBytes ?? 0, countStyle: .file) + " / " + ByteCountFormatter.string(fromByteCount: job.checkingTotal ?? 0, countStyle: .file)
        }
        text += "\n" + L10n.get("transfer_active_time") + ": " + CommanderDuration.format(elapsed, german: german)
        if job.state == .cancelled, let staging = job.staging {
            text += "\n" + L10n.get(job.isDeletion ? "transfer_delete_retained" : "transfer_partial_location", staging)
        }
        if let requested = job.controlRequestedAt, job.requestedControl != nil {
            text += "\n" + L10n.get("transfer_control_wait") + ": " + CommanderDuration.format(max(0, Date().timeIntervalSince(requested)), german: german) + "\n" + L10n.get("transfer_control_pending_help")
        }
        return text
    }
}
#endif
