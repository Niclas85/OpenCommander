#if targetEnvironment(macCatalyst)
import UIKit

/// The desktop connections list stays open and follows mounted/unmounted
/// devices, rather than capturing one immutable action-sheet snapshot.
@MainActor final class DesktopConnectionsController: UITableViewController {
    private let bridge: DesktopBridgeProtocol
    private var locations: [HostFileSystem.StorageLocation] = []
    private var unmounted: [[String: String]] = []
    private var applications: [[String: String]] = []
    private var ejectable = Set<String>()
    private var timer: Timer?
    private var generation = 0
    private var refreshPending = false
    private var changingVolume = false
    private var operationNotice: String?
    private let status = UILabel()
    var openLocationRequested: ((URL) -> Void)?
    var connectRequested: (() -> Void)?
    var applicationRequested: ((URL) -> Void)?
    var volumesChanged: (() -> Void)?

    init(bridge: DesktopBridgeProtocol) { self.bridge = bridge; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.get("connections")
        preferredContentSize = CGSize(width: 620, height: 500)
        tableView.accessibilityIdentifier = "ConnectionsList"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: L10n.get("refresh"), style: .plain, target: self, action: #selector(refreshList))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "ConnectionsRefresh"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "ConnectionsClose"
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshList), for: .valueChanged)
        status.numberOfLines = 0; status.font = .systemFont(ofSize: 13)
        status.textColor = .secondaryLabel; status.accessibilityIdentifier = "ConnectionsStatus"
        status.frame = CGRect(x: 16, y: 0, width: 588, height: 56)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 620, height: 56))
        status.autoresizingMask = [.flexibleWidth, .flexibleHeight]; header.addSubview(status)
        tableView.tableHeaderView = header
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshList()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshList() }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate(); timer = nil; generation += 1; refreshPending = false
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func refreshList() {
        guard !refreshPending, !changingVolume else { refreshControl?.endRefreshing(); return }
        refreshPending = true
        let revision = generation
        if locations.isEmpty && unmounted.isEmpty { status.text = L10n.get("connections_loading") }
        bridge.unmountedVolumes { [weak self] devices, error in
            guard let self else { return }
            let bridge = self.bridge
            DispatchQueue.global(qos: .utility).async {
                let places = HostFileSystem.availableStorageLocations().filter(\.visibleByDefault)
                let paths = Set(places.filter { $0.kind != .cloudStorage && bridge.isEjectableVolume($0.url) }.map { $0.url.path })
                let apps = bridge.installedCloudApplications()
                DispatchQueue.main.async {
                    guard self.generation == revision else { return }
                    self.refreshPending = false; self.refreshControl?.endRefreshing()
                    let old = self.signature()
                    self.locations = places; self.ejectable = paths
                    self.unmounted = devices; self.applications = apps
                    self.status.text = error.map { HistoryFailure($0).message } ?? self.operationNotice ?? L10n.get("connections")
                    if old != self.signature() { self.tableView.reloadData() }
                }
            }
        }
    }
    private func signature() -> [String] {
        var values: [String] = []
        for place in locations { values.append(["place", place.displayName, place.url.path, String(ejectable.contains(place.url.path))].joined(separator: "\0")) }
        for device in unmounted { values.append(["unmounted", device["identifier"] ?? "", device["name"] ?? ""].joined(separator: "\0")) }
        for app in applications { values.append(["app", app["name"] ?? "", app["path"] ?? ""].joined(separator: "\0")) }
        return values
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section { case 0: return locations.count; case 1: return unmounted.count; case 2, 4: return 1; default: return applications.count }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section { case 0: return locations.isEmpty ? nil : L10n.get("drives"); case 1: return unmounted.isEmpty ? nil : L10n.get("mount_volume"); case 3: return applications.isEmpty ? nil : L10n.get("cloud_setup"); default: return nil }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator
        switch indexPath.section {
        case 0:
            let place = locations[indexPath.row]
            cell.textLabel?.text = place.displayName; cell.detailTextLabel?.text = place.url.path
            cell.accessibilityIdentifier = "ConnectionPlace-" + place.url.path
            if ejectable.contains(place.url.path) {
                let button = UIButton(type: .system)
                button.setImage(UIImage(systemName: "eject.fill"), for: .normal)
                button.frame.size = CGSize(width: 40, height: 40); button.isEnabled = !changingVolume
                button.accessibilityLabel = L10n.get("eject_volume") + ": " + place.displayName
                cell.accessibilityCustomActions = [UIAccessibilityCustomAction(name: L10n.get("eject_volume")) { [weak self] _ in
                    self?.changeVolume(L10n.get("eject_volume")) { done in self?.bridge.ejectVolume(place.url, completion: done) }
                    return true
                }]
                button.addAction(UIAction { [weak self] _ in
                    self?.changeVolume(L10n.get("eject_volume")) { done in self?.bridge.ejectVolume(place.url, completion: done) }
                }, for: .touchUpInside)
                cell.accessoryView = button
            }
        case 1:
            let device = unmounted[indexPath.row]
            cell.textLabel?.text = L10n.get("mount_volume") + ": " + (device["name"] ?? "")
            cell.detailTextLabel?.text = device["identifier"]
        case 2: cell.textLabel?.text = L10n.get("connect_to_server")
        case 4:
            cell.textLabel?.text = L10n.get("ntfs_automatic_write_settings")
            cell.accessibilityIdentifier = "NTFSAutomaticWriteSettings"
        default: cell.textLabel?.text = applications[indexPath.row]["name"]; cell.detailTextLabel?.text = L10n.get("cloud_setup")
        }
        cell.isUserInteractionEnabled = !changingVolume
        return cell
    }
    private func changeVolume(_ message: String, action: (@escaping (NSError?) -> Void) -> Void) {
        guard !changingVolume else { return }
        generation += 1; refreshPending = false; changingVolume = true
        status.text = message; navigationItem.leftBarButtonItem?.isEnabled = false; tableView.reloadData()
        action { [weak self] error in
            guard let self else { return }
            self.changingVolume = false; self.navigationItem.leftBarButtonItem?.isEnabled = true
            self.operationNotice = error.map { HistoryFailure($0).message } ?? L10n.get("volume_operation_complete")
            self.status.text = self.operationNotice
            self.volumesChanged?(); self.refreshList()
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard !changingVolume else { return }
        switch indexPath.section {
        case 0: openLocationRequested?(locations[indexPath.row].url)
        case 1:
            guard let id = unmounted[indexPath.row]["identifier"] else { return }
            changeVolume(L10n.get("mount_volume")) { [weak self] done in self?.bridge.mountVolume(id, completion: done) }
        case 2: connectRequested?()
        case 4: bridge.showNTFSWriteSettings()
        default:
            if let path = applications[indexPath.row]["path"] { applicationRequested?(URL(fileURLWithPath: path)) }
        }
    }
}
#endif
