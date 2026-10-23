import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("isolated keyboard fixture required") }
let root = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Keyboard-20261023-") else { fatalError("unsafe fixture") }
let left = try Data(contentsOf: root.appendingPathComponent("Left/Keyboard.txt"))
let right = try Data(contentsOf: root.appendingPathComponent("Right/Sentinel.txt"))
precondition(left == Data("Own keyboard acceptance file. Do not change.\n".utf8))
precondition(right == Data("Own unchanged destination sentinel.\n".utf8))
let leftNames = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Left").path)
let rightNames = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Right").path)
precondition(leftNames.sorted() == ["Keyboard.txt"] && rightNames.sorted() == ["Sentinel.txt"])
let journal = root.appendingPathComponent("Transfers/copy-jobs-v1.json")
if fm.fileExists(atPath: journal.path) {
    let store = try JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as! [String:Any]
    precondition((store["jobs"] as? [[String:Any]])?.isEmpty == true)
}
let defaults = UserDefaults(suiteName: "com.github.niklaus85.OpenCommander.MacUITests")!
precondition(defaults.string(forKey: "acceptance_state_root") == root.path)
precondition(defaults.string(forKey: "language") == "de" && defaults.bool(forKey: "dark_mode"))
print("PASS exact keyboard source/sentinel, no extra directory entries or transfer jobs, DE/dark test preferences persist")
