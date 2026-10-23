import Foundation

// References an already-authorized configuration; never reads or copies its
// contents. Only the separate test application's navigation metadata is changed.
let arguments = CommandLine.arguments
guard (arguments.count == 2 || (arguments.count == 3 && ["--remove", "--long-name"].contains(arguments[2]))),
      arguments[1].hasPrefix("/private/tmp/OpenCommander-MacUITest-Special-"),
      FileManager.default.fileExists(atPath: arguments[1] + "/PreserveAppState.txt") else {
    fatalError("isolated preserved test profile required")
}
let source = UserDefaults(suiteName: "com.github.niklaus85.OpenCommander")!
let target = UserDefaults(suiteName: "com.github.niklaus85.OpenCommander.MacUITests")!
let key = "cloud_connections_v1"
let testID = "DB994A88-13EC-43E2-B218-281C04520C0B"
if arguments.count == 3 && arguments[2] == "--remove" {
    guard let data = target.data(forKey: key),
          let profiles = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          profiles.count == 1, profiles[0]["id"] as? String == testID,
          (profiles[0]["root"] as? String)?.hasSuffix("OpenCommander-LiveQA-Size12-wUvOA0") == true else {
        fatalError("refuse removal of any profile other than this exact test reference")
    }
    target.removeObject(forKey: key)
    for pane in ["1", "2"] {
        let sessionKey = "online_pane_session_v1_" + pane
        if let data = target.data(forKey: sessionKey),
           let session = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           session["location"] as? String == "cloud://" + testID {
            target.removeObject(forKey: sessionKey)
        }
    }
    guard target.synchronize() else { fatalError("test defaults not persisted") }
    print("REMOVED only own temporary test navigation reference; account/configuration untouched")
    exit(0)
}
guard target.object(forKey: key) == nil,
      let data = source.data(forKey: key),
      let profiles = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
      var profile = profiles.first(where: { $0["kind"] as? String == "drive" }) else {
    fatalError("existing authorized Drive profile required; never overwrite test connections")
}
let existingRoot = profile["root"] as? String ?? ""
profile["root"] = [existingRoot, "OpenCommander-LiveQA-Size12-wUvOA0"].filter { !$0.isEmpty }.joined(separator: "/")
profile["id"] = testID
profile["name"] = arguments.last == "--long-name"
    ? "Google Drive – Werkzeugtest – langer Anzeigename für horizontales Scrollen im Online-Baum – Ende-Online"
    : "Google Drive – Werkzeugtest"
target.set(try JSONSerialization.data(withJSONObject: [profile]), forKey: key)
guard target.synchronize() else { fatalError("test defaults not persisted") }
print("READY isolated Drive reference restricted to existing own 12-byte QA folder; no credentials copied")
