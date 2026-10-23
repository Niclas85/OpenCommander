import Foundation

#if targetEnvironment(macCatalyst) || os(macOS)
@objc(OpenCommanderDesktopBridgeProtocol)
protocol DesktopBridgeProtocol {
    func dragModifierKeys() -> Int
    func registerFileDropTarget(_ identifier: String, handler: @escaping (CGPoint, [URL], Int, Bool) -> Bool)
    init()
    func showNTFSWriteSettings()
    func setFolderApplication(_ application: URL, completion: @escaping (NSError?) -> Void)
    func openFile(_ url: URL, application: URL?, completion: @escaping (Bool, NSError?) -> Void)
    func previewFile(_ url: URL, closed: @escaping () -> Void) -> Bool
    func chooseApplication(for url: URL, title: String, completion: @escaping (Bool, NSError?) -> Void)
    func unmountedVolumes(completion: @escaping ([[String: String]], NSError?) -> Void)
    func mountVolume(_ identifier: String, completion: @escaping (NSError?) -> Void)
    func isEjectableVolume(_ url: URL) -> Bool
    func ejectVolume(_ url: URL, completion: @escaping (NSError?) -> Void)
    func installedCloudApplications() -> [[String: String]]
    func chooseArchiveDestination(name: String, directory: URL, title: String, completion: @escaping (URL?) -> Void)
    func chooseLocation(title: String, completion: @escaping (URL?) -> Void)
    func remoteOperation(_ requestID: String, connection: Data, password: String?, operation: String,
                         path: String, destination: String?, localURL: URL?, completion: @escaping (Data?, NSError?) -> Void)
    func cancelRemoteOperation(_ requestID: String)
    func remoteHostKeys(_ connection: Data, completion: @escaping (String?, NSError?) -> Void)
    func cloudOperation(_ requestID: String, connection: Data, operation: String, path: String,
                        destination: String?, localURL: URL?, completion: @escaping (Data?, NSError?) -> Void)
    func cancelCloudOperation(_ requestID: String)
    func shutdownCloudOperations()
    func cloudIdentity(_ connection: Data, completion: @escaping (String?, NSError?) -> Void)
    func cloudSetup(_ requestID: String, connection: Data, state: String?, answer: String?, password: Bool, oauthClient: Data?,
                    browser: @escaping (URL) -> Void, completion: @escaping (Data?, NSError?) -> Void)
    func chooseCloudConfiguration(title: String, completion: @escaping (URL?) -> Void)
    func stableVolumeIdentity(_ url: URL) -> String?
    func registerOnlineDragSource(_ identifier: String, items: @escaping (CGPoint) -> [[String: String]],
                                  write: @escaping (String, URL, @escaping (NSError?) -> Void) -> Void)
    func removeOnlineDragSource(_ identifier: String)
}
#endif

#if targetEnvironment(macCatalyst)
enum DesktopBridge {
    static let shared: DesktopBridgeProtocol? = {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let bundle = Bundle(url: plugins.appendingPathComponent("OpenCommanderMacBridge.bundle")) else {
            CommanderDragDiagnostics.event("native bridge bundle missing"); return nil
        }
        do { try bundle.loadAndReturnError() }
        catch { CommanderDragDiagnostics.event("native bridge load failed \(error)"); return nil }
        guard let type = bundle.principalClass as? DesktopBridgeProtocol.Type else {
            CommanderDragDiagnostics.event("native bridge class unavailable \(String(describing: bundle.principalClass))"); return nil
        }
        return type.init()
    }()
}
#endif
