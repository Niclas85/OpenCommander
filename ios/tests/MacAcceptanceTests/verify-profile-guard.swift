import Foundation

@main
struct VerifyProfileGuard {
    static func main() throws {
        precondition(CommandLine.arguments.count == 3)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let running = CommandLine.arguments[2] == "running"
        precondition(running || CommandLine.arguments[2] == "closed")
        precondition(root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-ProfileGuard-20261023-"))
        let fm = FileManager.default
        let source = try Data(contentsOf: root.appendingPathComponent("Left/Guard.txt"))
        let sentinel = try Data(contentsOf: root.appendingPathComponent("Right/Sentinel.txt"))
        let leftNames = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Left").path)
        let rightNames = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Right").path)
        precondition(source == Data("Own guarded profile source.\n".utf8))
        precondition(sentinel == Data("Own guarded profile destination sentinel.\n".utf8))
        precondition(leftNames == ["Guard.txt"] && rightNames == ["Sentinel.txt"])
        let defaults = UserDefaults(suiteName: "com.github.niklaus85.OpenCommander.MacUITests")!
        precondition(defaults.string(forKey: "acceptance_state_root") == root.path)
        let journal = root.appendingPathComponent("Transfers/copy-jobs-v1.json")
        if fm.fileExists(atPath: journal.path) {
            let store = try JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as! [String:Any]
            precondition((store["jobs"] as? [[String:Any]])?.isEmpty == true)
        }
        if running {
            do {
                _ = try CommanderProfileLease(directory: root)
                fatalError("live native app did not retain profile lease")
            } catch CommanderProfileLease.Failure.inUse {}
            print("PASS live native app excludes independent writer; exact files and empty queue unchanged")
        } else {
            let lease = try CommanderProfileLease(directory: root)
            withExtendedLifetime(lease) {}
            print("PASS native quit releases profile lease without deleting lock; exact files and empty queue unchanged")
        }
    }
}
