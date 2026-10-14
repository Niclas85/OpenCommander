import AppKit
import ServiceManagement
import OSLog

/// Opt-in, while OpenCommander is running. Never force-unmount or repair.
final class NTFSAutoMount {
    static let shared = NTFSAutoMount()
    private let preference = "ntfs_automatic_external_write_v1"
    private let queue = DispatchQueue(label: "OpenCommander.NTFSAutoMount")
    private var attempted = Set<String>()
    private var observers: [NSObjectProtocol] = []
    private var lastStatus = ""
    private let logger = Logger(subsystem: NTFSAccessPolicy.service, category: "Automount")
    private var service: SMAppService { .daemon(plistName: NTFSAccessPolicy.service + ".plist") }
    private func text(_ de: String, _ en: String) -> String { UserDefaults.standard.string(forKey: "language") == "de" ? de : en }

    func start() {
        guard observers.isEmpty else { return }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scan() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.scan() })
        scan()
    }
    func showSettings() {
        let enabled = UserDefaults.standard.bool(forKey: preference)
        let alert = NSAlert()
        alert.messageText = text("Automatischer NTFS-Schreibzugriff", "Automatic NTFS write access")
        let state: String
        switch service.status {
        case .enabled: state = text("Hilfsdienst freigegeben", "Helper approved")
        case .requiresApproval: state = text("Freigabe in den Systemeinstellungen ausstehend", "Approval pending in System Settings")
        case .notRegistered: state = text("Hilfsdienst noch nicht eingerichtet", "Helper not configured")
        default: state = text("Hilfsdienst nicht verfügbar", "Helper unavailable")
        }
        alert.informativeText = text(
            "Nach einmaliger Administratorfreigabe versucht OpenCommander externe USB-NTFS-Partitionen beim Anschließen beschreibbar einzubinden, solange die App läuft. Die NTFS-Dateisystemerweiterung muss zusätzlich aktiviert sein. Interne, belegte, beschädigte oder im Ruhezustand befindliche Laufwerke werden nicht erzwungen eingebunden. Der Dienst erlaubt nur kurzzeitigen Zugriff auf geprüfte NTFS-Geräte; keine beliebigen Administratorbefehle.\n\n",
            "After administrator approval, OpenCommander attempts writable mounting of external USB NTFS partitions when attached, while the app is running. The NTFS file-system extension must also be enabled. Internal, busy, damaged or hibernated drives are never forced. The helper permits only short-lived access to verified NTFS devices, not arbitrary administrator commands.\n\n") + state + (lastStatus.isEmpty ? "" : "\n" + lastStatus)
        alert.addButton(withTitle: enabled ? text("Deaktivieren", "Disable") : text("Einrichten und aktivieren", "Set up and enable"))
        alert.addButton(withTitle: text("Systemeinstellungen", "System Settings"))
        alert.addButton(withTitle: text("Schließen", "Close"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if enabled {
                UserDefaults.standard.set(false, forKey: preference)
                service.unregister { error in if let error { self.report(error.localizedDescription) } }
            } else {
                do {
                    guard try NTFSExtensionRegistration.plan(for: Bundle.main.bundleURL) != nil else { throw NTFSAccessPolicy.failure("Install the signed app in Applications first") }
                    if service.status != .enabled && service.status != .requiresApproval { try service.register() }
                    UserDefaults.standard.set(true, forKey: preference)
                    if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                    scan()
                } catch {
                    // macOS may register successfully but throw EPERM while
                    // approval is pending. Do not require a second setup click.
                    if service.status == .requiresApproval {
                        UserDefaults.standard.set(true, forKey: preference)
                        lastStatus = ""
                        SMAppService.openSystemSettingsLoginItems()
                    } else { report(error.localizedDescription) }
                }
            }
        case .alertSecondButtonReturn: SMAppService.openSystemSettingsLoginItems()
        default: break
        }
    }
    private func report(_ message: String) {
        logger.error("NTFS: \(message, privacy: .public)")
        DispatchQueue.main.async { self.lastStatus = message }
    }
    private func scan() {
        guard UserDefaults.standard.bool(forKey: preference), service.status == .enabled else { return }
        queue.async {
            do {
                guard let plan = try NTFSExtensionRegistration.plan(for: Bundle.main.bundleURL),
                      let module = Bundle(url: plan.module),
                      module.object(forInfoDictionaryKey: "OpenCommanderNTFSWriteCondition") as? String == "OPENCOMMANDER_NTFS3G_EXPERIMENTAL",
                      let attributes = module.object(forInfoDictionaryKey: "EXAppExtensionAttributes") as? [String: Any],
                      let alias = attributes["FSShortName"] as? String, ["openntfs", "openntfs2"].contains(alias) else { return }
                let data = try NTFSAccessPolicy.run("/usr/sbin/diskutil", ["list", "-plist", "external", "physical"])
                let listing = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                let disks = listing?["AllDisks"] as? [String] ?? []
                var seen = Set<String>()
                for disk in disks where NTFSAccessPolicy.validDevice(disk) {
                    guard let info = try? NTFSAccessPolicy.info(disk), let uuid = info["DiskUUID"] as? String else { continue }
                    seen.insert(uuid)
                    guard !self.attempted.contains(uuid), info["FilesystemType"] as? String == "ntfs",
                          info["WritableVolume"] as? Bool == false,
                          let path = info["MountPoint"] as? String, path.hasPrefix("/Volumes/"),
                          NTFSAccessPolicy.eligible(info, device: disk, uuid: uuid) else { continue }
                    guard UserDefaults.standard.bool(forKey: self.preference) else { break }
                    self.attempted.insert(uuid) // No repeated unmount/fallback loop.
                    do { try self.mount(disk: disk, uuid: uuid, alias: alias) }
                    catch { self.report(self.text("NTFS bleibt schreibgeschützt: ", "NTFS remains read-only: ") + error.localizedDescription) }
                }
                self.attempted.formIntersection(seen)
            } catch { self.report(error.localizedDescription) }
        }
    }
    private func mount(disk: String, uuid: String, alias: String) throws {
        let connection = NSXPCConnection(machServiceName: NTFSAccessPolicy.service, options: .privileged)
        connection.setCodeSigningRequirement(try NTFSAccessPolicy.signingRequirement(identifier: NTFSAccessPolicy.service))
        connection.remoteObjectInterface = NSXPCInterface(with: NTFSAccessProtocol.self)
        connection.resume(); defer { connection.invalidate() }
        // Use the user-context mount client: FSKit approval is per login user.
        guard let volumeUUID = UUID(uuidString: uuid) else { throw NTFSAccessPolicy.failure("Invalid volume identity") }
        let mountPoint = URL(fileURLWithPath: "/Volumes/OpenCommander-" + volumeUUID.uuidString)
        var mounted = false, unmounted = false
        defer {
            if !mounted {
                if unmounted, let current = try? NTFSAccessPolicy.info(disk), current["DiskUUID"] as? String == uuid, !NTFSAccessPolicy.isMounted(current) {
                    _ = try? NTFSAccessPolicy.run("/usr/sbin/diskutil", ["mount", "readOnly", "/dev/" + disk])
                }
            }
        }
        _ = try NTFSAccessPolicy.run("/usr/sbin/diskutil", ["unmount", "/dev/" + disk]); unmounted = true
        let ready = DispatchSemaphore(value: 0), lock = NSLock()
        var token: String?, failure: NSError?
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in lock.lock(); failure = error as NSError; lock.unlock(); ready.signal() } as? NTFSAccessProtocol
        guard let proxy else { throw NTFSAccessPolicy.failure("NTFS helper unavailable") }
        proxy.begin(device: disk, uuid: uuid) { value, error in lock.lock(); token = value; failure = error; lock.unlock(); ready.signal() }
        guard ready.wait(timeout: .now() + 35) == .success else { throw NTFSAccessPolicy.failure("NTFS helper timed out") }
        lock.lock(); let lease = token, beginError = failure; lock.unlock()
        guard let lease else { throw beginError ?? NTFSAccessPolicy.failure("NTFS helper refused access") }
        var mountError: Error?
        do {
            _ = try NTFSAccessPolicy.run("/sbin/mount", ["-F", "-t", alias, "-o", "nosuid,nodev,noowners", "/dev/" + disk, mountPoint.path], timeout: 40)
            mounted = true
        } catch { mountError = error }
        let restored = DispatchSemaphore(value: 0)
        var restoreError: NSError?
        proxy.end(token: lease) { error in lock.lock(); restoreError = error; lock.unlock(); restored.signal() }
        guard restored.wait(timeout: .now() + 10) == .success else { throw NTFSAccessPolicy.failure("NTFS permission restoration not confirmed") }
        lock.lock(); let finalError = restoreError; lock.unlock()
        if let finalError { throw finalError }; if let mountError { throw mountError }
        let info = try NTFSAccessPolicy.info(disk)
        guard info["DiskUUID"] as? String == uuid, info["WritableVolume"] as? Bool == true else { throw NTFSAccessPolicy.failure("Writable NTFS mount not confirmed") }
        self.report(self.text("NTFS-Schreibzugriff aktiv.", "NTFS write access active."))
    }
}
